import Foundation
@testable import tofustash

// Mock implementing the TokenStorage protocol — an in-memory fake for what's
// probably Keychain storage in production. Same idea as mocking localStorage in Jest.
final class MockTokenStorage: TokenStorage, @unchecked Sendable {
    var storedTokens: AuthTokens?

    var storeCallCount = 0
    var clearCallCount = 0

    func getTokens() async -> AuthTokens? {
        return storedTokens
    }

    func storeTokens(_ tokens: AuthTokens) async {
        storeCallCount += 1
        storedTokens = tokens
    }

    func clear() async {
        clearCallCount += 1
        storedTokens = nil
    }
}
