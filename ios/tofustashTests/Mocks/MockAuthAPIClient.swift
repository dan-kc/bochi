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
    // Result<T, E> is exactly like Rust's Result<T, E>. .success(val) / .failure(err).
    var anonymousAuthResult: Result<AuthTokens, Error> = .failure(MockError.notConfigured)
    var anonymousAuthCallCount = 0
    var lastAnonymousAuthDeviceId: String? // Optional — like T | undefined in TS, Option<T> in Rust

    var registerResult: Result<AuthTokens, Error> = .failure(MockError.notConfigured)
    var registerCallCount = 0

    var loginResult: Result<AuthTokens, Error> = .failure(MockError.notConfigured)
    var loginCallCount = 0
    var lastLoginEmail: String?

    var claimAccountResult: Result<AuthTokens, Error> = .failure(MockError.notConfigured)
    var claimAccountCallCount = 0
    var lastClaimAccessToken: String?

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

    // Each method fulfills a protocol requirement — like implementing an interface method.
    // `async throws` = can await + can throw (combines Go's error return with JS async).
    func anonymousAuth(deviceId: String) async throws -> AuthTokens {
        anonymousAuthCallCount += 1
        lastAnonymousAuthDeviceId = deviceId
        // .get() extracts the success value or throws the error — like Rust's `?` operator
        return try anonymousAuthResult.get()
    }

    func register(email: String, password: String) async throws -> AuthTokens {
        registerCallCount += 1
        return try registerResult.get()
    }

    func login(email: String, password: String) async throws -> AuthTokens {
        loginCallCount += 1
        lastLoginEmail = email
        return try loginResult.get()
    }

    func claimAccount(email: String, password: String, accessToken: String) async throws -> AuthTokens {
        claimAccountCallCount += 1
        lastClaimAccessToken = accessToken
        return try claimAccountResult.get()
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
