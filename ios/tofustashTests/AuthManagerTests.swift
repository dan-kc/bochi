import Foundation
import Testing
@testable import tofustash

// @MainActor pins this entire struct to the main thread — like ensuring all code runs
// in React's render thread. Needed because AuthManager likely uses @Published/@Observable
// properties that must be accessed from the main actor (Swift's concurrency safety).
@MainActor
struct AuthManagerTests {

    // SUT = "System Under Test". Returns a tuple (like a Go multi-return).
    // Default param values (= MockAuthAPIClient()) work like TS default params.
    private func makeSUT(
        apiClient: MockAuthAPIClient = MockAuthAPIClient(),
        storage: MockTokenStorage = MockTokenStorage()
    ) -> (AuthManager, MockAuthAPIClient, MockTokenStorage) {
        // Dependency injection via constructor — same pattern as passing mock props in React tests
        let manager = AuthManager(apiClient: apiClient, tokenStorage: storage)
        return (manager, apiClient, storage)
    }

    // MARK: - Bootstrap

    // Behaviour: When the app launches with no saved session, it creates an anonymous account
    // so the user can start using the app immediately without signing up.
    // async test — like an async Jest test. Swift Testing handles the await natively.
    @Test func bootstrapWithNoStoredTokensPerformsAnonymousAuth() async {
        let (manager, api, storage) = makeSUT()
        let tokens = TestHelpers.makeTokens(userId: "anon-1", isAnonymous: true)
        api.anonymousAuthResult = .success(tokens)

        await manager.bootstrap()

        #expect(api.anonymousAuthCallCount == 1)
        #expect(api.lastAnonymousAuthDeviceId == "test-device-id")
        #expect(manager.user?.id == "anon-1")
        #expect(manager.user?.isAnonymous == true)
        #expect(manager.isLoading == false)
    }

    // Behaviour: When the app launches with a previously saved session, the user is
    // restored to their logged-in state and tokens are refreshed for continued access.
    @Test func bootstrapWithStoredTokensRestoresUserAndRefreshes() async {
        let api = MockAuthAPIClient()
        let storage = MockTokenStorage()
        let tokens = TestHelpers.makeTokens(userId: "user-456")
        storage.storedTokens = tokens
        storage.storedIsAnonymous = false
        api.refreshTokensResult = .success(tokens)

        let (manager, _, _) = makeSUT(apiClient: api, storage: storage)
        await manager.bootstrap()

        #expect(manager.user?.id == "user-456")
        #expect(manager.user?.isAnonymous == false)
        #expect(api.anonymousAuthCallCount == 0)
        #expect(manager.isLoading == false)
        // Verifies refresh was attempted with the stored token
        #expect(api.refreshTokensCallCount == 1)
        #expect(api.lastRefreshToken == tokens.refreshToken)
    }

    // Behaviour: When the app launches with a saved anonymous session, the user
    // remains anonymous (they haven't signed up yet but had data from a prior session).
    @Test func bootstrapWithStoredAnonymousTokensRestoresAnonymousUser() async {
        let api = MockAuthAPIClient()
        let storage = MockTokenStorage()
        let tokens = TestHelpers.makeTokens(userId: "anon-789", isAnonymous: true)
        storage.storedTokens = tokens
        storage.storedIsAnonymous = true
        api.refreshTokensResult = .success(tokens)

        let (manager, _, _) = makeSUT(apiClient: api, storage: storage)
        await manager.bootstrap()

        #expect(manager.user?.isAnonymous == true)
    }

    // MARK: - Login

    // Behaviour: When a user logs in with valid credentials, they become the authenticated user.
    // `async throws` = this test can both await and throw errors. `throws` is like
    // Rust's Result — but the test runner catches thrown errors as failures automatically.
    @Test func loginCallsAPIAndSetsUser() async throws {
        let (manager, api, storage) = makeSUT()
        let anonTokens = TestHelpers.makeTokens(userId: "anon-1", isAnonymous: true)
        api.anonymousAuthResult = .success(anonTokens)
        await manager.bootstrap()

        let loginTokens = TestHelpers.makeTokens(userId: "logged-in-user")
        api.loginResult = .success(loginTokens)

        try await manager.login(email: "test@example.com", password: "password123")

        #expect(api.loginCallCount == 1)
        #expect(api.lastLoginEmail == "test@example.com")
        #expect(manager.user?.id == "logged-in-user")
        #expect(manager.user?.isAnonymous == false)
        #expect(storage.storedIsAnonymous == false)
    }

    // Behaviour: When a user logs in with wrong credentials, login fails and
    // they remain on their current (anonymous) account.
    @Test func loginWithInvalidCredentialsThrows() async {
        let (manager, api, _) = makeSUT()
        let anonTokens = TestHelpers.makeTokens(userId: "anon-1", isAnonymous: true)
        api.anonymousAuthResult = .success(anonTokens)
        await manager.bootstrap()

        api.loginResult = .failure(ApiError(errors: nil, message: "Invalid credentials", statusCode: 401))

        // do/catch = try/catch in TS. `try` keyword before throwing calls is mandatory in Swift.
        do {
            try await manager.login(email: "test@example.com", password: "wrong")
            Issue.record("Expected login to throw") // Like Jest's fail() — marks test as failed
        } catch {
            // `error` is implicitly available in catch blocks (like Go's err)
            #expect(manager.user?.id == "anon-1") // User unchanged
        }
    }

    // MARK: - Register

    // Behaviour: When a user registers a new account, they become the authenticated user.
    @Test func registerCallsAPIAndSetsUser() async throws {
        let (manager, api, storage) = makeSUT()
        let anonTokens = TestHelpers.makeTokens(userId: "anon-1", isAnonymous: true)
        api.anonymousAuthResult = .success(anonTokens)
        await manager.bootstrap()

        let registerTokens = TestHelpers.makeTokens(userId: "new-user")
        api.registerResult = .success(registerTokens)

        try await manager.register(email: "new@example.com", password: "password123")

        #expect(api.registerCallCount == 1)
        #expect(manager.user?.id == "new-user")
        #expect(manager.user?.isAnonymous == false)
        #expect(storage.storedIsAnonymous == false)
    }

    // MARK: - Claim Account

    // Behaviour: When an anonymous user claims their account (signs up), their data
    // is preserved and they become a fully authenticated user.
    @Test func claimAccountConvertsToNonAnonymous() async throws {
        let api = MockAuthAPIClient()
        let storage = MockTokenStorage()
        let anonTokens = TestHelpers.makeTokens(userId: "anon-1", isAnonymous: true)
        api.anonymousAuthResult = .success(anonTokens)

        let (manager, _, _) = makeSUT(apiClient: api, storage: storage)
        await manager.bootstrap()

        #expect(manager.isAnonymous == true)

        let claimTokens = TestHelpers.makeTokens(userId: "claimed-user")
        api.claimAccountResult = .success(claimTokens)

        try await manager.claimAccount(email: "claim@example.com", password: "password123")

        // Verifies the current access token was sent for claiming
        #expect(api.claimAccountCallCount == 1)
        #expect(api.lastClaimAccessToken == anonTokens.accessToken)
        #expect(manager.user?.id == "claimed-user")
        #expect(manager.isAnonymous == false)
        #expect(storage.storedIsAnonymous == false)
    }

    // MARK: - Logout

    // Behaviour: When a user logs out, their session is cleared and a fresh
    // anonymous session is created so the app remains usable.
    @Test func logoutCallsAPIAndCreatesNewAnonymousSession() async throws {
        let (manager, api, storage) = makeSUT()
        let loginTokens = TestHelpers.makeTokens(userId: "user-1")
        storage.storedTokens = loginTokens
        storage.storedIsAnonymous = false
        api.refreshTokensResult = .success(loginTokens)
        await manager.bootstrap()

        let newAnonTokens = TestHelpers.makeTokens(userId: "anon-new", isAnonymous: true)
        api.anonymousAuthResult = .success(newAnonTokens)

        await manager.logout()

        #expect(api.logoutCallCount == 1)
        #expect(storage.clearCallCount == 1)
        #expect(manager.user?.id == "anon-new")
        #expect(manager.user?.isAnonymous == true)
    }

    // Behaviour: When a user logs out but the server is unreachable, the local
    // session is still cleared so the user isn't stuck in a broken state.
    @Test func logoutStillClearsLocallyIfAPIFails() async throws {
        let (manager, api, storage) = makeSUT()
        let loginTokens = TestHelpers.makeTokens(userId: "user-1")
        storage.storedTokens = loginTokens
        storage.storedIsAnonymous = false
        api.refreshTokensResult = .success(loginTokens)
        await manager.bootstrap()

        api.logoutResult = .failure(ApiError(errors: nil, message: "Server error", statusCode: 500))
        let newAnonTokens = TestHelpers.makeTokens(userId: "anon-new", isAnonymous: true)
        api.anonymousAuthResult = .success(newAnonTokens)

        await manager.logout()

        #expect(storage.clearCallCount == 1)
        #expect(manager.user?.id == "anon-new")
        #expect(manager.user?.isAnonymous == true)
    }

    // MARK: - Change Password

    // Behaviour: When a user changes their password, the request is sent with their current session.
    @Test func changePasswordCallsAPIWithAccessToken() async throws {
        let (manager, api, storage) = makeSUT()
        let tokens = TestHelpers.makeTokens(userId: "user-1")
        storage.storedTokens = tokens
        storage.storedIsAnonymous = false
        api.refreshTokensResult = .success(tokens)
        await manager.bootstrap()

        try await manager.changePassword(currentPassword: "old", newPassword: "newpass123")

        #expect(api.changePasswordCallCount == 1)
        #expect(api.lastChangePasswordAccessToken != nil)
    }

    // MARK: - Change Email

    // Behaviour: When a user changes their email, the request is sent with their current session.
    @Test func changeEmailCallsAPIWithAccessToken() async throws {
        let (manager, api, storage) = makeSUT()
        let tokens = TestHelpers.makeTokens(userId: "user-1")
        storage.storedTokens = tokens
        storage.storedIsAnonymous = false
        api.refreshTokensResult = .success(tokens)
        await manager.bootstrap()

        try await manager.changeEmail(newEmail: "new@example.com", password: "password123")

        #expect(api.changeEmailCallCount == 1)
        #expect(api.lastChangeEmailAccessToken != nil)
    }

    // MARK: - Token Refresh Failure

    // Behaviour: When a returning user's session has expired (server rejects refresh),
    // they are logged out and given a fresh anonymous session instead of seeing an error.
    @Test func refreshFailsWith401FallsBackToAnonymous() async {
        let api = MockAuthAPIClient()
        let storage = MockTokenStorage()
        let tokens = TestHelpers.makeTokens(userId: "user-1")
        storage.storedTokens = tokens
        storage.storedIsAnonymous = false
        api.refreshTokensResult = .failure(ApiError(errors: nil, message: "Unauthorized", statusCode: 401))

        let anonTokens = TestHelpers.makeTokens(userId: "anon-fallback", isAnonymous: true)
        api.anonymousAuthResult = .success(anonTokens)

        let (manager, _, _) = makeSUT(apiClient: api, storage: storage)
        await manager.bootstrap()

        #expect(manager.user?.id == "anon-fallback")
        #expect(manager.user?.isAnonymous == true)
        #expect(storage.clearCallCount == 1)
    }
}
