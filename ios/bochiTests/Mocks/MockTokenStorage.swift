import Foundation
@testable import bochi

// Mock implementing the TokenStorage protocol — an in-memory fake for what's
// probably Keychain storage in production. Same idea as mocking localStorage in Jest.
final class MockTokenStorage: TokenStorage, @unchecked Sendable {
    var storedTokens: AuthTokens?
    var getTokensError: Error?
    var storeTokensError: Error?
    var clearError: Error?

    var storeCallCount = 0
    var clearCallCount = 0

    func getTokens() async throws -> AuthTokens? {
        if let getTokensError {
            throw getTokensError
        }
        return storedTokens
    }

    func storeTokens(_ tokens: AuthTokens) async throws {
        storeCallCount += 1
        if let storeTokensError {
            throw storeTokensError
        }
        storedTokens = tokens
    }

    func clear() async throws {
        clearCallCount += 1
        if let clearError {
            throw clearError
        }
        storedTokens = nil
    }
}
