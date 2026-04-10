import Foundation
@testable import tofustash

// Mock implementing the TokenStorage protocol — an in-memory fake for what's
// probably Keychain storage in production. Same idea as mocking localStorage in Jest.
final class MockTokenStorage: TokenStorage, @unchecked Sendable {
    var storedTokens: AuthTokens?
    var storedIsAnonymous: Bool?
    var deviceId: String = "test-device-id"

    var storeCallCount = 0
    var clearCallCount = 0

    func getTokens() async -> AuthTokens? {
        return storedTokens
    }

    // `_ tokens` = the external label is suppressed. Callers write storeTokens(myTokens, isAnonymous: true)
    // instead of storeTokens(tokens: myTokens, isAnonymous: true). The _ is like making a named param positional.
    func storeTokens(_ tokens: AuthTokens, isAnonymous: Bool) async {
        storeCallCount += 1
        storedTokens = tokens
        storedIsAnonymous = isAnonymous
    }

    func getIsAnonymous() async -> Bool? {
        return storedIsAnonymous
    }

    func clear() async {
        clearCallCount += 1
        storedTokens = nil
        storedIsAnonymous = nil
    }

    func getOrCreateDeviceId() async -> String {
        return deviceId
    }
}
