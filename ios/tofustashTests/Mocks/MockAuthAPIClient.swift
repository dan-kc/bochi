import Foundation
@testable import tofustash

final class MockAuthAPIClient: AuthAPIClient, @unchecked Sendable {
    var anonymousAuthResult: Result<AuthTokens, Error> = .failure(MockError.notConfigured)
    var anonymousAuthCallCount = 0
    var lastAnonymousAuthDeviceId: String?

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

    func anonymousAuth(deviceId: String) async throws -> AuthTokens {
        anonymousAuthCallCount += 1
        lastAnonymousAuthDeviceId = deviceId
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

enum MockError: Error {
    case notConfigured
}
