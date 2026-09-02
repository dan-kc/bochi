import Foundation

enum AppleEntitlementActivationResult: Equatable, Sendable {
    case inactive
    case activeForAccount
    case activeOnDeviceNeedsAccount
    case activeOnDeviceAccountLinkFailed

    var shouldShowPremiumWelcome: Bool {
        switch self {
        case .activeForAccount, .activeOnDeviceNeedsAccount:
            return true
        case .inactive, .activeOnDeviceAccountLinkFailed:
            return false
        }
    }
}

struct AccountDeletionEvent: Equatable, Sendable {
    let userID: String
    let revision: Int
}

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
    private(set) var isPurchasingPremium = false
    private(set) var isDeletingAccount = false
    private(set) var localAppleEntitlement = AppleEntitlementStatus.inactive
    private(set) var accountDeletionEvent: AccountDeletionEvent?

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
        appleEntitlementClient: AppleEntitlementClient
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

        let storedTokens: AuthTokens?
        do {
            storedTokens = try await tokenStorage.getTokens()
        } catch {
            transitionToSignedOutState()
            return
        }

        guard let storedTokens else {
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
                try? await tokenStorage.clear()
                currentAccessToken = nil
                transitionToSignedOutState()
            }
            // Behaviour: network failures during bootstrap should keep any
            // provisional signed-in state visible instead of forcing a logout.
        }
    }

    // User authorizes with Apple, then the backend creates or reuses the
    // account keyed by Apple's stable per-app user identifier.
    func signInWithApple(
        identityToken: String,
        email: String?,
        nonce: String?,
        authorizationCode: String? = nil
    ) async throws {
        let tokens = try await apiClient.signInWithApple(
            identityToken: identityToken,
            email: email,
            nonce: nonce,
            authorizationCode: authorizationCode
        )
        await applyAuthenticatedTokens(tokens)
    }

    #if BOCHI_LOCAL
    // Behaviour: local builds authenticate as the configured fixture account,
    // then follow the same token and account bootstrap path as Apple sign-in.
    func signInForLocalDevelopment(account: LocalDevelopmentAccount) async throws {
        try await signInWithApple(
            identityToken: "test-apple-subject:\(account.subject)",
            email: account.email,
            nonce: nil
        )
    }
    #endif

    // Logging out should only clear the backend session. If this device still
    // owns an Apple premium entitlement, that local premium state stays visible.
    func logout() async {
        cancelRefresh()

        if let tokens = try? await tokenStorage.getTokens() {
            try? await apiClient.logout(refreshToken: tokens.refreshToken)
        }

        try? await tokenStorage.clear()
        currentAccessToken = nil
        user = nil
        localAppleEntitlement = await appleEntitlementClient.currentEntitlement()
        recomputeSessionState()
    }

    // Behaviour: account deletion is stronger than logout. It removes the
    // server account first, then clears this device's session and tells root
    // lifecycles which account-owned local rows must be purged.
    func deleteAccount() async throws {
        guard let user else {
            throw ApiError.genericFailure(message: "Sign in before deleting an account.")
        }
        guard let accessToken = currentAccessToken else {
            throw ApiError.genericFailure(message: "Your session is no longer valid. Try signing in again.")
        }

        isDeletingAccount = true
        defer { isDeletingAccount = false }

        try await apiClient.deleteAccount(accessToken: accessToken)

        let deletedUserID = user.id
        cancelRefresh()
        try? await tokenStorage.clear()
        currentAccessToken = nil
        self.user = nil
        localAppleEntitlement = await appleEntitlementClient.currentEntitlement()
        let nextRevision = (accountDeletionEvent?.revision ?? 0) + 1
        accountDeletionEvent = AccountDeletionEvent(userID: deletedUserID, revision: nextRevision)
        recomputeSessionState()
    }

    // Behaviour: Restore Purchases may grant premium locally on this device
    // even when there is no signed-in account yet. That is intentional.
    @discardableResult
    func restorePurchases() async throws -> AppleEntitlementActivationResult {
        isRestoringPurchases = true
        defer { isRestoringPurchases = false }

        localAppleEntitlement = try await appleEntitlementClient.restorePurchases()
        do {
            try await linkLocalAppleEntitlementIfPossible()
        } catch {
            recomputeSessionState()
            guard localAppleEntitlement.isActive else { throw error }
            return activationResult()
        }
        recomputeSessionState()
        return activationResult()
    }

    // Behaviour: purchase can unlock premium locally before the user has an
    // account, then the same entitlement links to sync once they sign in.
    @discardableResult
    func purchasePremium(productID: String) async throws -> AppleEntitlementActivationResult {
        isPurchasingPremium = true
        defer { isPurchasingPremium = false }

        localAppleEntitlement = try await appleEntitlementClient.purchase(
            productID: productID,
            appAccountToken: user.flatMap { UUID(uuidString: $0.id) }
        )
        do {
            try await linkLocalAppleEntitlementIfPossible()
        } catch {
            recomputeSessionState()
            guard localAppleEntitlement.isActive else { throw error }
            return activationResult()
        }
        recomputeSessionState()
        return activationResult()
    }

    // StoreKit can report renewals, refunds, and purchases outside the exact
    // button tap that started them, so the root lifecycle uses this single hook.
    func refreshAppleEntitlementFromStoreKit() async {
        localAppleEntitlement = await appleEntitlementClient.currentEntitlement()
        do {
            try await linkLocalAppleEntitlementIfPossible()
        } catch {
            // Behaviour: a StoreKit update should not destabilize the session if
            // the backend link step is temporarily unavailable.
        }
        recomputeSessionState()
    }

    private func applyAuthenticatedTokens(_ tokens: AuthTokens) async {
        guard let payload = JWTParser.parse(tokens.accessToken),
              let subject = payload.subject
        else { return }

        currentAccessToken = tokens.accessToken
        try? await tokenStorage.storeTokens(tokens)

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
                subscriptionProductID: nil,
                isEntitled: false,
                subscriptionExpiresAt: nil
            )
        }

        do {
            try await linkLocalAppleEntitlementIfPossible()
        } catch {
            // Behaviour: Apple sign-in should still succeed even if the
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
            subscriptionProductID: nil,
            isEntitled: false,
            subscriptionExpiresAt: nil
        )
    }

    private func transitionToSignedOutState() {
        user = nil
        recomputeSessionState()
    }

    private func activationResult() -> AppleEntitlementActivationResult {
        guard localAppleEntitlement.isActive else { return .inactive }
        guard let user else { return .activeOnDeviceNeedsAccount }
        guard user.isEntitled else { return .activeOnDeviceAccountLinkFailed }
        return .activeForAccount
    }

    private func linkLocalAppleEntitlementIfPossible() async throws {
        guard
            let user,
            let accessToken = currentAccessToken,
            localAppleEntitlement.isActive,
            !(user.isEntitled),
            let originalTransactionID = localAppleEntitlement.originalTransactionID,
            let productID = localAppleEntitlement.productID
        else {
            return
        }
        let transactionID = localAppleEntitlement.transactionID ?? originalTransactionID
        let environment = localAppleEntitlement.environment ?? "production"

        let linkedAccount = try await apiClient.linkAppleSubscription(
            transactionID: transactionID,
            originalTransactionID: originalTransactionID,
            productID: productID,
            environment: environment,
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
                try? await tokenStorage.clear()
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
