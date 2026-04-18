import Foundation

// AuthManager owns two separate truths:
// 1. which backend account, if any, is signed in
// 2. whether this device currently has a local Apple premium entitlement
//
// The state machine derived from those facts is what SwiftUI renders.
@Observable
@MainActor
final class AuthManager {
    private(set) var user: AuthUser?
    private(set) var sessionState: AuthSessionState = .signedOutFree
    private(set) var isLoading = true
    private(set) var isRestoringPurchases = false
    private(set) var localAppleEntitlement = AppleEntitlementStatus.inactive

    var isSignedIn: Bool { user != nil }
    var isPremiumEntitled: Bool { sessionState.isPremiumEntitled }
    var canSync: Bool { isSignedIn }

    // Behaviour: after restoring an Apple purchase while signed out, the app
    // should clearly prompt the user to create or log into an account instead
    // of silently inventing one on their behalf.
    var needsAccountToLinkPurchase: Bool {
        sessionState == .signedOutPremiumRestored
    }

    // Behaviour: a device-level Apple entitlement can exist before the backend
    // account is linked. The app should surface that mismatch instead of hiding it.
    var hasUnlinkedAppleEntitlement: Bool {
        isSignedIn && localAppleEntitlement.isActive && !(user?.isEntitled ?? false)
    }

    private let apiClient: AuthAPIClient
    private let tokenStorage: TokenStorage
    private let appleEntitlementClient: AppleEntitlementClient

    private var refreshTask: Task<Void, Never>?
    private var currentAccessToken: String?

    func currentAccessTokenForSync() -> String? {
        currentAccessToken
    }

    init(
        apiClient: AuthAPIClient,
        tokenStorage: TokenStorage,
        appleEntitlementClient: AppleEntitlementClient = StoreKitAppleEntitlementClient()
    ) {
        self.apiClient = apiClient
        self.tokenStorage = tokenStorage
        self.appleEntitlementClient = appleEntitlementClient
    }

    // Called once on app launch. It restores local Apple entitlement first so
    // signed-out premium users still land in the correct state before network work.
    func bootstrap() async {
        defer { isLoading = false }

        localAppleEntitlement = await appleEntitlementClient.currentEntitlement()

        guard let storedTokens = await tokenStorage.getTokens() else {
            transitionToSignedOutState()
            return
        }

        if let provisionalUser = provisionalUser(from: storedTokens.accessToken) {
            user = provisionalUser
            currentAccessToken = storedTokens.accessToken
            recomputeSessionState()
        }

        do {
            let refreshedTokens = try await apiClient.refreshTokens(refreshToken: storedTokens.refreshToken)
            await applyAuthenticatedTokens(refreshedTokens)
        } catch {
            let apiError = error as? ApiError
            if apiError?.statusCode == 401 {
                await tokenStorage.clear()
                currentAccessToken = nil
                transitionToSignedOutState()
            }
            // Behaviour: network failures during bootstrap should keep any
            // provisional signed-in state visible instead of forcing a logout.
        }
    }

    // User signs into an existing backend account. The app then asks `/auth/me`
    // which premium state belongs to that account.
    func login(email: String, password: String) async throws {
        let tokens = try await apiClient.login(email: email, password: password)
        await applyAuthenticatedTokens(tokens)
    }

    // User creates a new backend account from signed-out local mode.
    func register(email: String, password: String) async throws {
        let tokens = try await apiClient.register(email: email, password: password)
        await applyAuthenticatedTokens(tokens)
    }

    // Logging out should only clear the backend session. If this device still
    // owns an Apple premium entitlement, that local premium state stays visible.
    func logout() async {
        cancelRefresh()

        if let tokens = await tokenStorage.getTokens() {
            try? await apiClient.logout(refreshToken: tokens.refreshToken)
        }

        await tokenStorage.clear()
        currentAccessToken = nil
        user = nil
        localAppleEntitlement = await appleEntitlementClient.currentEntitlement()
        recomputeSessionState()
    }

    func changePassword(currentPassword: String, newPassword: String) async throws {
        guard let accessToken = currentAccessToken, isSignedIn else {
            throw ApiError.genericFailure(
                message: "You need to be signed in before you can change your password."
            )
        }

        try await apiClient.changePassword(
            currentPassword: currentPassword,
            newPassword: newPassword,
            accessToken: accessToken
        )
    }

    func changeEmail(newEmail: String, password: String) async throws {
        guard let accessToken = currentAccessToken, isSignedIn else {
            throw ApiError.genericFailure(
                message: "You need to be signed in before you can change your email."
            )
        }

        try await apiClient.changeEmail(
            newEmail: newEmail,
            password: password,
            accessToken: accessToken
        )
    }

    // Behaviour: Restore Purchases may grant premium locally on this device
    // even when there is no signed-in account yet. That is intentional.
    func restorePurchases() async throws {
        isRestoringPurchases = true
        defer { isRestoringPurchases = false }

        localAppleEntitlement = try await appleEntitlementClient.restorePurchases()
        do {
            try await linkLocalAppleEntitlementIfPossible()
        } catch {
            recomputeSessionState()
            throw error
        }
        recomputeSessionState()
    }

    private func applyAuthenticatedTokens(_ tokens: AuthTokens) async {
        guard let payload = JWTParser.parse(tokens.accessToken),
              let subject = payload.subject
        else { return }

        currentAccessToken = tokens.accessToken
        await tokenStorage.storeTokens(tokens)

        if let account = try? await apiClient.getCurrentAccount(accessToken: tokens.accessToken) {
            user = account.makeUser(id: subject)
        } else if user?.id != subject {
            // Behaviour: if `/auth/me` is temporarily unavailable right after a
            // successful auth response, the user should still stay signed in.
            user = AuthUser(
                id: subject,
                email: nil,
                subscriptionSource: nil,
                subscriptionStatus: .none,
                isEntitled: false,
                subscriptionExpiresAt: nil
            )
        }

        do {
            try await linkLocalAppleEntitlementIfPossible()
        } catch {
            // Behaviour: login/register should still succeed even if the
            // follow-up purchase-link step fails. The UI can continue showing
            // the device-level entitlement as unlinked until the user retries.
        }

        recomputeSessionState()

        if let expiresAt = payload.expiresAt {
            scheduleRefresh(expiresAt: expiresAt, refreshToken: tokens.refreshToken)
        }
    }

    private func provisionalUser(from accessToken: String) -> AuthUser? {
        guard let payload = JWTParser.parse(accessToken),
              let subject = payload.subject
        else { return nil }

        return AuthUser(
            id: subject,
            email: nil,
            subscriptionSource: nil,
            subscriptionStatus: .none,
            isEntitled: false,
            subscriptionExpiresAt: nil
        )
    }

    private func transitionToSignedOutState() {
        user = nil
        recomputeSessionState()
    }

    private func linkLocalAppleEntitlementIfPossible() async throws {
        guard
            let user,
            let accessToken = currentAccessToken,
            localAppleEntitlement.isActive,
            !(user.isEntitled),
            let originalTransactionID = localAppleEntitlement.originalTransactionID
        else {
            return
        }

        let linkedAccount = try await apiClient.linkAppleSubscription(
            originalTransactionID: originalTransactionID,
            subscriptionExpiresAt: localAppleEntitlement.expirationDate,
            accessToken: accessToken
        )
        self.user = linkedAccount.makeUser(id: user.id)
    }

    private func recomputeSessionState() {
        guard let user else {
            sessionState = localAppleEntitlement.isActive ? .signedOutPremiumRestored : .signedOutFree
            return
        }

        if user.isEntitled {
            switch user.subscriptionSource {
            case .apple:
                sessionState = .signedInPremiumApple
            case .web:
                sessionState = .signedInPremiumWeb
            case .none:
                sessionState = .signedInFree
            }
            return
        }

        sessionState = user.subscriptionStatus.isLapsed ? .signedInLapsed : .signedInFree
    }

    private func scheduleRefresh(expiresAt: Int, refreshToken: String) {
        cancelRefresh()

        let expiresAtDate = Date(timeIntervalSince1970: TimeInterval(expiresAt))
        let refreshAt = expiresAtDate.addingTimeInterval(-60)
        let delay = refreshAt.timeIntervalSinceNow

        guard delay > 0 else {
            refreshTask = Task { [weak self] in
                await self?.performRefresh(refreshToken: refreshToken)
            }
            return
        }

        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.performRefresh(refreshToken: refreshToken)
        }
    }

    private func performRefresh(refreshToken: String) async {
        do {
            let refreshedTokens = try await apiClient.refreshTokens(refreshToken: refreshToken)
            await applyAuthenticatedTokens(refreshedTokens)
        } catch {
            let apiError = error as? ApiError
            if apiError?.statusCode == 401 {
                await tokenStorage.clear()
                currentAccessToken = nil
                transitionToSignedOutState()
            } else {
                refreshTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(60))
                    guard !Task.isCancelled else { return }
                    await self?.performRefresh(refreshToken: refreshToken)
                }
            }
        }
    }

    private func cancelRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }
}
