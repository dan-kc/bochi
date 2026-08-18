import Foundation
@testable import bochi

// `AuthAPIClient` is a protocol (= TS interface / Go interface / Rust trait).
// This class conforms to it, providing a mock implementation — same pattern as
// jest.fn() mocks but done manually since Swift has no built-in mocking.
//
// `final` = cannot be subclassed (like Go structs / Rust types by default).
// `@unchecked Sendable` opts out of Swift's compile-time thread-safety checks —
// like `unsafe impl Send` in Rust. Needed because mutable state in a class isn't
// normally safe to share across threads, but in tests we control access.
final class MockAuthAPIClient: AuthAPIClient, @unchecked Sendable {
    var signInWithAppleResult: Result<AuthTokens, Error> = .failure(MockError.notConfigured)
    var signInWithAppleCallCount = 0
    var lastAppleIdentityToken: String?
    var lastAppleEmail: String?
    var lastAppleNonce: String?
    var lastAppleAuthorizationCode: String?

    var currentAccountResult: Result<CurrentAccountResponse, Error> = .failure(MockError.notConfigured)
    var currentAccountCallCount = 0
    var lastCurrentAccountAccessToken: String?

    var linkAppleSubscriptionResult: Result<CurrentAccountResponse, Error> = .failure(MockError.notConfigured)
    var linkAppleSubscriptionCallCount = 0
    var lastLinkAppleSubscriptionAccessToken: String?
    var lastLinkedTransactionID: String?
    var lastLinkedOriginalTransactionID: String?
    var lastLinkedProductID: String?
    var lastLinkedEnvironment: String?

    var refreshTokensResult: Result<AuthTokens, Error> = .failure(MockError.notConfigured)
    var refreshTokensCallCount = 0
    var lastRefreshToken: String?

    var logoutResult: Result<Void, Error> = .success(())
    var logoutCallCount = 0
    var lastLogoutRefreshToken: String?

    var deleteAccountResult: Result<Void, Error> = .success(())
    var deleteAccountCallCount = 0
    var lastDeleteAccountAccessToken: String?

    func signInWithApple(
        identityToken: String,
        email: String?,
        nonce: String?,
        authorizationCode: String?
    ) async throws -> AuthTokens {
        signInWithAppleCallCount += 1
        lastAppleIdentityToken = identityToken
        lastAppleEmail = email
        lastAppleNonce = nonce
        lastAppleAuthorizationCode = authorizationCode
        return try signInWithAppleResult.get()
    }

    func getCurrentAccount(accessToken: String) async throws -> CurrentAccountResponse {
        currentAccountCallCount += 1
        lastCurrentAccountAccessToken = accessToken
        return try currentAccountResult.get()
    }

    func linkAppleSubscription(
        transactionID: String,
        originalTransactionID: String,
        productID: String?,
        environment: String?,
        subscriptionExpiresAt: Date?,
        accessToken: String
    ) async throws -> CurrentAccountResponse {
        linkAppleSubscriptionCallCount += 1
        lastLinkAppleSubscriptionAccessToken = accessToken
        lastLinkedTransactionID = transactionID
        lastLinkedOriginalTransactionID = originalTransactionID
        lastLinkedProductID = productID
        lastLinkedEnvironment = environment
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

    func deleteAccount(accessToken: String) async throws {
        deleteAccountCallCount += 1
        lastDeleteAccountAccessToken = accessToken
        try deleteAccountResult.get()
    }

}

// Enum conforming to Error protocol — like implementing the error interface in Go
// or impl std::error::Error in Rust
enum MockError: Error {
    case notConfigured
}
