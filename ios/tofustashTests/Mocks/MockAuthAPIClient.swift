import Foundation
@testable import tofustash

// `AuthAPIClient` is a protocol (= TS interface / Go interface / Rust trait).
// This class conforms to it, providing a mock implementation — same pattern as
// jest.fn() mocks but done manually since Swift has no built-in mocking.
//
// `final` = cannot be subclassed (like Go structs / Rust types by default).
// `@unchecked Sendable` opts out of Swift's compile-time thread-safety checks —
// like `unsafe impl Send` in Rust. Needed because mutable state in a class isn't
// normally safe to share across threads, but in tests we control access.
final class MockAuthAPIClient: AuthAPIClient, @unchecked Sendable {
    var registerResult: Result<AuthTokens, Error> = .failure(MockError.notConfigured)
    var registerCallCount = 0

    var loginResult: Result<AuthTokens, Error> = .failure(MockError.notConfigured)
    var loginCallCount = 0
    var lastLoginEmail: String?

    var currentAccountResult: Result<CurrentAccountResponse, Error> = .failure(MockError.notConfigured)
    var currentAccountCallCount = 0
    var lastCurrentAccountAccessToken: String?

    var linkAppleSubscriptionResult: Result<CurrentAccountResponse, Error> = .failure(MockError.notConfigured)
    var linkAppleSubscriptionCallCount = 0
    var lastLinkAppleSubscriptionAccessToken: String?
    var lastLinkedOriginalTransactionID: String?

    var refreshTokensResult: Result<AuthTokens, Error> = .failure(MockError.notConfigured)
    var refreshTokensCallCount = 0
    var lastRefreshToken: String?

    var logoutResult: Result<Void, Error> = .success(())
    var logoutCallCount = 0
    var lastLogoutRefreshToken: String?

    var changePasswordResult: Result<Void, Error> = .success(())
    var changePasswordCallCount = 0
    var lastChangePasswordAccessToken: String?

    var changeEmailResult: Result<Void, Error> = .success(())
    var changeEmailCallCount = 0
    var lastChangeEmailAccessToken: String?

    func register(email: String, password: String) async throws -> AuthTokens {
        registerCallCount += 1
        return try registerResult.get()
    }

    func login(email: String, password: String) async throws -> AuthTokens {
        loginCallCount += 1
        lastLoginEmail = email
        return try loginResult.get()
    }

    func getCurrentAccount(accessToken: String) async throws -> CurrentAccountResponse {
        currentAccountCallCount += 1
        lastCurrentAccountAccessToken = accessToken
        return try currentAccountResult.get()
    }

    func linkAppleSubscription(
        originalTransactionID: String,
        subscriptionExpiresAt: Date?,
        accessToken: String
    ) async throws -> CurrentAccountResponse {
        linkAppleSubscriptionCallCount += 1
        lastLinkAppleSubscriptionAccessToken = accessToken
        lastLinkedOriginalTransactionID = originalTransactionID
        return try linkAppleSubscriptionResult.get()
    }

    func refreshTokens(refreshToken: String) async throws -> AuthTokens {
        refreshTokensCallCount += 1
        lastRefreshToken = refreshToken
        return try refreshTokensResult.get()
    }

    func logout(refreshToken: String) async throws {
        logoutCallCount += 1
        lastLogoutRefreshToken = refreshToken
        try logoutResult.get()
    }

    func changePassword(currentPassword: String, newPassword: String, accessToken: String) async throws {
        changePasswordCallCount += 1
        lastChangePasswordAccessToken = accessToken
        try changePasswordResult.get()
    }

    func changeEmail(newEmail: String, password: String, accessToken: String) async throws {
        changeEmailCallCount += 1
        lastChangeEmailAccessToken = accessToken
        try changeEmailResult.get()
    }
}

// Enum conforming to Error protocol — like implementing the error interface in Go
// or impl std::error::Error in Rust
enum MockError: Error {
    case notConfigured
}
