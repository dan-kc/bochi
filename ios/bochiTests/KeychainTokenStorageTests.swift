import Foundation
import Security
import Testing
@testable import bochi

private final class FakeKeychainAccess: KeychainAccessing, @unchecked Sendable {
    var storedDataByAccount: [String: Data] = [:]
    var updateStatuses: [OSStatus] = []
    var addStatuses: [OSStatus] = []
    var deleteStatuses: [OSStatus] = []

    private(set) var addCallCount = 0
    private(set) var updateCallCount = 0
    private(set) var deleteCallCount = 0
    private(set) var lastAccessibility: KeychainAccessibility?

    func read(service: String, account: String) -> KeychainReadResult {
        guard let data = storedDataByAccount[account] else { return .notFound }
        return .found(data)
    }

    func add(
        service: String,
        account: String,
        data: Data,
        accessibility: KeychainAccessibility
    ) -> OSStatus {
        addCallCount += 1
        lastAccessibility = accessibility
        if !addStatuses.isEmpty {
            let status = addStatuses.removeFirst()
            if status == errSecDuplicateItem {
                storedDataByAccount[account] = Data()
            }
            guard status == errSecSuccess else { return status }
        } else if storedDataByAccount[account] != nil {
            return errSecDuplicateItem
        }

        storedDataByAccount[account] = data
        return errSecSuccess
    }

    func update(
        service: String,
        account: String,
        data: Data,
        accessibility: KeychainAccessibility
    ) -> OSStatus {
        updateCallCount += 1
        lastAccessibility = accessibility
        if !updateStatuses.isEmpty {
            let status = updateStatuses.removeFirst()
            guard status == errSecSuccess else { return status }
        } else if storedDataByAccount[account] == nil {
            return errSecItemNotFound
        }

        storedDataByAccount[account] = data
        return errSecSuccess
    }

    func delete(service: String, account: String) -> OSStatus {
        deleteCallCount += 1
        if !deleteStatuses.isEmpty {
            let status = deleteStatuses.removeFirst()
            guard status == errSecSuccess else { return status }
        }

        storedDataByAccount.removeValue(forKey: account)
        return errSecSuccess
    }

    func errorMessage(for status: OSStatus) -> String? {
        switch status {
        case errSecInteractionNotAllowed:
            return "User interaction is not allowed."
        case errSecItemNotFound:
            return "The specified item could not be found."
        case errSecDuplicateItem:
            return "The specified item already exists."
        default:
            return "OSStatus \(status)"
        }
    }
}

@MainActor
struct KeychainTokenStorageTests {
    private let tokensKey = "auth_tokens"

    private func encoded(_ tokens: AuthTokens) throws -> Data {
        try JSONEncoder().encode(tokens)
    }

    private func decoded(_ data: Data?) throws -> AuthTokens {
        try JSONDecoder().decode(AuthTokens.self, from: try #require(data))
    }

    // Behaviour: refreshing an existing backend session should update the
    // Keychain item in place, leaving the previous token intact if update fails.
    @Test func storingTokensUpdatesExistingItemWithoutDeletingFirst() async throws {
        let keychain = FakeKeychainAccess()
        let oldTokens = TestHelpers.makeTokens(userId: "old-user")
        let newTokens = TestHelpers.makeTokens(userId: "new-user")
        keychain.storedDataByAccount[tokensKey] = try encoded(oldTokens)
        let storage = KeychainTokenStorage(keychain: keychain)

        try await storage.storeTokens(newTokens)

        #expect(keychain.updateCallCount == 1)
        #expect(keychain.addCallCount == 0)
        #expect(keychain.deleteCallCount == 0)
        #expect(keychain.lastAccessibility == .afterFirstUnlockThisDeviceOnly)
        #expect(try decoded(keychain.storedDataByAccount[tokensKey]) == newTokens)
    }

    // Behaviour: first sign-in should create a Keychain item that remains
    // available after first unlock, which avoids lock-screen refresh failures.
    @Test func storingTokensAddsMissingItemWithAfterFirstUnlockAccessibility() async throws {
        let keychain = FakeKeychainAccess()
        let tokens = TestHelpers.makeTokens(userId: "new-user")
        let storage = KeychainTokenStorage(keychain: keychain)

        try await storage.storeTokens(tokens)

        #expect(keychain.updateCallCount == 1)
        #expect(keychain.addCallCount == 1)
        #expect(keychain.deleteCallCount == 0)
        #expect(keychain.lastAccessibility == .afterFirstUnlockThisDeviceOnly)
        #expect(try decoded(keychain.storedDataByAccount[tokensKey]) == tokens)
    }

    // Behaviour: if iOS temporarily refuses Keychain interaction, storage should
    // surface a recoverable error and keep the previous token untouched.
    @Test func interactionNotAllowedWriteDoesNotDeleteExistingToken() async throws {
        let keychain = FakeKeychainAccess()
        let oldTokens = TestHelpers.makeTokens(userId: "old-user")
        let newTokens = TestHelpers.makeTokens(userId: "new-user")
        keychain.storedDataByAccount[tokensKey] = try encoded(oldTokens)
        keychain.updateStatuses = [errSecInteractionNotAllowed]
        let storage = KeychainTokenStorage(keychain: keychain)

        do {
            try await storage.storeTokens(newTokens)
            Issue.record("Expected Keychain write to fail")
        } catch let error as TokenStorageError {
            #expect(error == .temporarilyUnavailable("Keychain write failed: User interaction is not allowed."))
        }

        #expect(keychain.updateCallCount == 1)
        #expect(keychain.addCallCount == 0)
        #expect(keychain.deleteCallCount == 0)
        #expect(try decoded(keychain.storedDataByAccount[tokensKey]) == oldTokens)
    }

    // Behaviour: if another task creates the item between update and add, the
    // write should retry update instead of treating the duplicate as fatal.
    @Test func duplicateAddRetriesUpdate() async throws {
        let keychain = FakeKeychainAccess()
        let tokens = TestHelpers.makeTokens(userId: "race-user")
        keychain.updateStatuses = [errSecItemNotFound]
        keychain.addStatuses = [errSecDuplicateItem]
        let storage = KeychainTokenStorage(keychain: keychain)

        try await storage.storeTokens(tokens)

        #expect(keychain.updateCallCount == 2)
        #expect(keychain.addCallCount == 1)
        #expect(keychain.deleteCallCount == 0)
        #expect(try decoded(keychain.storedDataByAccount[tokensKey]) == tokens)
    }
}
