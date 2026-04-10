import Foundation

// @Observable — like a Zustand/Jotai store: any SwiftUI view reading its properties auto-rerenders on change
@Observable
// @MainActor — constrains all methods/property access to the main thread (like ensuring everything runs on the UI thread; Rust analogy: !Send)
@MainActor
// `final` — cannot be subclassed (like a sealed class in Kotlin, or no vtable in Rust)
final class AuthManager {
    // private(set) — public read, private write (like a getter-only export in TS; Rust: pub field with no pub setter)
    private(set) var user: AuthUser?
    private(set) var isLoading: Bool = true

    // Computed property — like a derived/computed value in a Zustand store (or useMemo that auto-tracks deps)
    var isAnonymous: Bool { user?.isAnonymous ?? true }

    // `let` = immutable binding (like `const` in JS or `let` in Rust — but for classes, the reference is fixed, not contents)
    private let apiClient: AuthAPIClient
    private let tokenStorage: TokenStorage
    // Task<Void, Never> — like a Promise<void> that can't throw (`Never` = the error type is impossible, like Rust's `!`/`Infallible`)
    private var refreshTask: Task<Void, Never>?
    private var currentAccessToken: String?

    // `init` = constructor. `self.x = x` is required to disambiguate (no implicit `this` assignment like TS constructor shorthand)
    init(apiClient: AuthAPIClient, tokenStorage: TokenStorage) {
        self.apiClient = apiClient
        self.tokenStorage = tokenStorage
    }

    // MARK: — section comment convention in Swift (like `// #region` in TS, shows up in Xcode's jump bar)

    // `async` — like TS async. Called with `await` just like JS/Rust.
    func bootstrap() async {
        // `defer` — runs when scope exits, success or failure (exactly like Go's `defer`, or Rust's Drop).
        // Like a `finally` block in JS/React — guarantees isLoading becomes false no matter which code path runs.
        defer { isLoading = false }

        let storedTokens = await tokenStorage.getTokens()
        let storedIsAnonymous = await tokenStorage.getIsAnonymous()

        // `if let storedTokens` — unwraps Optional (like Rust's `if let Some(tokens)`). Binds the non-nil value to same name.
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
                // `as?` — conditional type cast, returns Optional (like a TS type guard, or Rust's downcast_ref)
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

    // `throws` — function can throw (like Rust's Result return; callers must `try` or propagate)
    func login(email: String, password: String) async throws {
        let tokens = try await apiClient.login(email: email, password: password)
        await processAuthResponse(tokens, isAnonymous: false)
    }

    func register(email: String, password: String) async throws {
        let tokens = try await apiClient.register(email: email, password: password)
        await processAuthResponse(tokens, isAnonymous: false)
    }

    func claimAccount(email: String, password: String) async throws {
        // `guard let ... else` — early return unwrap (like Rust's `let Some(x) = val else { return }`, or Go's if-err-return pattern)
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
            // `try?` — discard the error, convert to nil on failure (like `.ok()` in Rust, or a catch that swallows)
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

    // `_` as first param label — means caller doesn't need a label: processAuthResponse(tokens, ...) instead of processAuthResponse(tokens: tokens, ...)
    private func processAuthResponse(_ tokens: AuthTokens, isAnonymous: Bool) async {
        // Multi-clause guard — like chaining Rust's `let Some(x) = ... else { return }` checks
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

        // Task { } — spawns a concurrent task (like goroutine, or tokio::spawn, or launching a Promise)
        // [weak self] — capture list: prevents retain cycle (prevents the closure from preventing dealloc — no React/TS equivalent, closest is Rust's Weak<T>)
        refreshTask = Task { [weak self] in
            // Task.sleep — like setTimeout but as an awaitable (non-blocking, cooperative cancellation)
            try? await Task.sleep(for: .seconds(delay))
            // Task.isCancelled — cooperative cancellation check (like Go's ctx.Done() or AbortSignal)
            guard !Task.isCancelled else { return }
            // self? — optional chaining since self is weak (no-op if AuthManager was deallocated)
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
