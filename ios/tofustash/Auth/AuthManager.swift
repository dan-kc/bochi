import Foundation

@Observable
@MainActor
final class AuthManager {
    private(set) var user: AuthUser?
    private(set) var isLoading: Bool = true

    var isAnonymous: Bool { user?.isAnonymous ?? true }

    private let apiClient: AuthAPIClient
    private let tokenStorage: TokenStorage
    private var refreshTask: Task<Void, Never>?
    private var currentAccessToken: String?

    init(apiClient: AuthAPIClient, tokenStorage: TokenStorage) {
        self.apiClient = apiClient
        self.tokenStorage = tokenStorage
    }

    // MARK: - Bootstrap

    func bootstrap() async {
        defer { isLoading = false }

        let storedTokens = await tokenStorage.getTokens()
        let storedIsAnonymous = await tokenStorage.getIsAnonymous()

        if let storedTokens {
            let isAnonymous = storedIsAnonymous ?? false
            if let parsed = JWTParser.parse(storedTokens.accessToken), let subject = parsed.subject {
                user = AuthUser(id: subject, isAnonymous: isAnonymous)
                currentAccessToken = storedTokens.accessToken
            }

            // Attempt refresh
            do {
                let newTokens = try await apiClient.refreshTokens(refreshToken: storedTokens.refreshToken)
                await processAuthResponse(newTokens, isAnonymous: isAnonymous)
            } catch {
                let apiError = error as? ApiError
                if apiError?.statusCode == 401 {
                    await tokenStorage.clear()
                    user = nil
                    currentAccessToken = nil
                    await performAnonymousAuth()
                }
                // For non-401 errors, keep the current session and schedule a retry
            }
        } else {
            await performAnonymousAuth()
        }
    }

    // MARK: - Auth Actions

    func login(email: String, password: String) async throws {
        let tokens = try await apiClient.login(email: email, password: password)
        await processAuthResponse(tokens, isAnonymous: false)
    }

    func register(email: String, password: String) async throws {
        let tokens = try await apiClient.register(email: email, password: password)
        await processAuthResponse(tokens, isAnonymous: false)
    }

    func claimAccount(email: String, password: String) async throws {
        guard let accessToken = currentAccessToken else {
            throw ApiError(errors: nil, message: "No access token available", statusCode: nil)
        }
        let tokens = try await apiClient.claimAccount(
            email: email,
            password: password,
            accessToken: accessToken
        )
        await processAuthResponse(tokens, isAnonymous: false)
    }

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

    func changePassword(currentPassword: String, newPassword: String) async throws {
        guard let accessToken = currentAccessToken else {
            throw ApiError(errors: nil, message: "No access token available", statusCode: nil)
        }
        try await apiClient.changePassword(
            currentPassword: currentPassword,
            newPassword: newPassword,
            accessToken: accessToken
        )
    }

    func changeEmail(newEmail: String, password: String) async throws {
        guard let accessToken = currentAccessToken else {
            throw ApiError(errors: nil, message: "No access token available", statusCode: nil)
        }
        try await apiClient.changeEmail(
            newEmail: newEmail,
            password: password,
            accessToken: accessToken
        )
    }

    // MARK: - Private

    private func performAnonymousAuth() async {
        let deviceId = await tokenStorage.getOrCreateDeviceId()
        do {
            let tokens = try await apiClient.anonymousAuth(deviceId: deviceId)
            await processAuthResponse(tokens, isAnonymous: true)
        } catch {
            // Leave user as nil — can retry later
        }
    }

    private func processAuthResponse(_ tokens: AuthTokens, isAnonymous: Bool) async {
        guard let payload = JWTParser.parse(tokens.accessToken),
              let subject = payload.subject
        else { return }

        await tokenStorage.storeTokens(tokens, isAnonymous: isAnonymous)
        user = AuthUser(id: subject, isAnonymous: isAnonymous)
        currentAccessToken = tokens.accessToken

        if let expiresAt = payload.expiresAt {
            scheduleRefresh(expiresAt: expiresAt, refreshToken: tokens.refreshToken)
        }
    }

    private func scheduleRefresh(expiresAt: Int, refreshToken: String) {
        cancelRefresh()

        let expiresAtDate = Date(timeIntervalSince1970: TimeInterval(expiresAt))
        let refreshAt = expiresAtDate.addingTimeInterval(-60) // 1 minute before expiry
        let delay = refreshAt.timeIntervalSinceNow

        guard delay > 0 else {
            // Already expired or expiring very soon — refresh immediately
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
                await tokenStorage.clear()
                user = nil
                currentAccessToken = nil
                await performAnonymousAuth()
            } else {
                // Retry in 60 seconds on network errors
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
