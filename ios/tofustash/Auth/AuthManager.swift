import Foundation

// AuthManager owns the app's auth session from the user's point of view:
// app launch decides whether they land in an anonymous session or a restored
// signed-in session, auth actions swap identities, and token refresh tries to
// keep that experience uninterrupted.
//
// @Observable works like a tiny reactive store. SwiftUI views that read `user`
// or `isLoading` automatically update when those values change.
@Observable
// @MainActor keeps all mutations on the main thread, which is the SwiftUI
// equivalent of making sure UI-facing state changes happen on React's UI path.
@MainActor
// `final` means this is a concrete store, not a base class to extend.
final class AuthManager {
    // Views can observe auth state, but only AuthManager can change it.
    private(set) var user: AuthUser?
    private(set) var isLoading: Bool = true

    // Swift computed property: similar to a derived selector in a React store.
    var isAnonymous: Bool { user?.isAnonymous ?? true }

    private let apiClient: AuthAPIClient
    private let tokenStorage: TokenStorage

    // Background refresh work is tracked so it can be cancelled on logout
    // or replaced when a newer token arrives.
    private var refreshTask: Task<Void, Never>?
    private var currentAccessToken: String?

    init(apiClient: AuthAPIClient, tokenStorage: TokenStorage) {
        self.apiClient = apiClient
        self.tokenStorage = tokenStorage
    }

    // Called once on app launch. It tries to restore the last session first,
    // then falls back to an anonymous account so the app stays usable even
    // before registration.
    func bootstrap() async {
        // `defer` behaves like a `finally` block: loading stops regardless of
        // which branch returns or throws.
        defer { isLoading = false }

        let storedTokens = await tokenStorage.getTokens()
        let storedIsAnonymous = await tokenStorage.getIsAnonymous()

        if let storedTokens {
            let isAnonymous = storedIsAnonymous ?? false
            if let parsed = JWTParser.parse(storedTokens.accessToken), let subject = parsed.subject {
                // The app can render immediately from the cached token payload
                // while the network refresh happens in the background.
                user = AuthUser(id: subject, isAnonymous: isAnonymous)
                currentAccessToken = storedTokens.accessToken
            }

            do {
                let newTokens = try await apiClient.refreshTokens(refreshToken: storedTokens.refreshToken)
                await processAuthResponse(newTokens, isAnonymous: isAnonymous)
            } catch {
                let apiError = error as? ApiError
                if apiError?.statusCode == 401 {
                    // Expired sessions should quietly drop back to anonymous
                    // instead of leaving the user stranded on launch.
                    await tokenStorage.clear()
                    user = nil
                    currentAccessToken = nil
                    await performAnonymousAuth()
                }
                // For transient failures we keep the restored session and let the
                // scheduled refresh path try again later.
            }
        } else {
            await performAnonymousAuth()
        }
    }

    // User submits the login form. Success replaces any anonymous identity with
    // the real account while preserving the same in-app store object.
    func login(email: String, password: String) async throws {
        let tokens = try await apiClient.login(email: email, password: password)
        await processAuthResponse(tokens, isAnonymous: false)
    }

    // User registers directly instead of claiming an anonymous session.
    func register(email: String, password: String) async throws {
        let tokens = try await apiClient.register(email: email, password: password)
        await processAuthResponse(tokens, isAnonymous: false)
    }

    // User converts an anonymous account into a permanent one so their current
    // local progress stays attached to the new credentials.
    func claimAccount(email: String, password: String) async throws {
        guard let accessToken = currentAccessToken else {
            throw ApiError.genericFailure(
                message: "You need an active session before you can create an account."
            )
        }
        let tokens = try await apiClient.claimAccount(
            email: email,
            password: password,
            accessToken: accessToken
        )
        await processAuthResponse(tokens, isAnonymous: false)
    }

    // Logging out intentionally clears local state first, then immediately
    // provisions a fresh anonymous session so the app still works afterward.
    func logout() async {
        cancelRefresh()

        if let tokens = await tokenStorage.getTokens() {
            try? await apiClient.logout(refreshToken: tokens.refreshToken)
        }

        await tokenStorage.clear()
        user = nil
        currentAccessToken = nil

        await performAnonymousAuth()
    }

    // Account settings actions reuse the current access token, matching how a
    // React app would send the session token with a profile mutation request.
    func changePassword(currentPassword: String, newPassword: String) async throws {
        guard let accessToken = currentAccessToken else {
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
        guard let accessToken = currentAccessToken else {
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

    // Silent bootstrap fallback when no usable saved session exists.
    private func performAnonymousAuth() async {
        let deviceId = await tokenStorage.getOrCreateDeviceId()
        do {
            let tokens = try await apiClient.anonymousAuth(deviceId: deviceId)
            await processAuthResponse(tokens, isAnonymous: true)
        } catch {
            // Leave user as nil so the UI can present a retry path later.
        }
    }

    private func processAuthResponse(_ tokens: AuthTokens, isAnonymous: Bool) async {
        guard let payload = JWTParser.parse(tokens.accessToken),
              let subject = payload.subject
        else { return }

        // Persist first so a crash/relaunch still restores the same identity.
        await tokenStorage.storeTokens(tokens, isAnonymous: isAnonymous)
        user = AuthUser(id: subject, isAnonymous: isAnonymous)
        currentAccessToken = tokens.accessToken

        if let expiresAt = payload.expiresAt {
            // Refresh is scheduled relative to token expiry so the user doesn't
            // hit a surprise auth interruption mid-session.
            scheduleRefresh(expiresAt: expiresAt, refreshToken: tokens.refreshToken)
        }
    }

    private func scheduleRefresh(expiresAt: Int, refreshToken: String) {
        cancelRefresh()

        let expiresAtDate = Date(timeIntervalSince1970: TimeInterval(expiresAt))
        let refreshAt = expiresAtDate.addingTimeInterval(-60) // 1 minute before expiry
        let delay = refreshAt.timeIntervalSinceNow

        guard delay > 0 else {
            // If the token is already near expiry, refresh right away rather
            // than waiting for the user to hit an auth boundary.
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
        let isAnonymous = user?.isAnonymous ?? false
        do {
            let newTokens = try await apiClient.refreshTokens(refreshToken: refreshToken)
            await processAuthResponse(newTokens, isAnonymous: isAnonymous)
        } catch {
            let apiError = error as? ApiError
            if apiError?.statusCode == 401 {
                // If refresh is rejected, the old session is no longer trusted.
                await tokenStorage.clear()
                user = nil
                currentAccessToken = nil
                await performAnonymousAuth()
            } else {
                // Network problems shouldn't immediately log the user out.
                // Retry later and keep the current session visible for now.
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
