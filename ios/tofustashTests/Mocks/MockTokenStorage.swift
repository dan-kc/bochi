import Foundation
@testable import tofustash

final class MockTokenStorage: TokenStorage, @unchecked Sendable {
    var storedTokens: AuthTokens?
    var storedIsAnonymous: Bool?
    var deviceId: String = "test-device-id"

    var storeCallCount = 0
    var clearCallCount = 0

    func getTokens() async -> AuthTokens? {
        return storedTokens
    }

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
