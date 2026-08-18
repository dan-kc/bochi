import Foundation
// Security = Apple's framework for Keychain (OS-level secure storage, like OS credential managers).
import Security

// Protocol with Sendable = thread-safe interface. Think of it as a TS interface + Rust's Send bound.
protocol TokenStorage: Sendable {
    func getTokens() async throws -> AuthTokens?
    func storeTokens(_ tokens: AuthTokens) async throws
    func clear() async throws
}

actor InMemoryTokenStorage: TokenStorage {
    private var tokens: AuthTokens?

    init(tokens: AuthTokens? = nil) {
        self.tokens = tokens
    }

    func getTokens() async throws -> AuthTokens? {
        tokens
    }

    func storeTokens(_ tokens: AuthTokens) async throws {
        self.tokens = tokens
    }

    func clear() async throws {
        tokens = nil
    }
}

enum TokenStorageError: Error, Equatable, LocalizedError {
    case temporarilyUnavailable(String)
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .temporarilyUnavailable(let message), .operationFailed(let message):
            return message
        }
    }
}

enum KeychainAccessibility: Sendable {
    case afterFirstUnlockThisDeviceOnly

    var secValue: CFString {
        switch self {
        case .afterFirstUnlockThisDeviceOnly:
            return kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        }
    }
}

protocol KeychainAccessing: Sendable {
    func read(service: String, account: String) -> KeychainReadResult
    func add(service: String, account: String, data: Data, accessibility: KeychainAccessibility) -> OSStatus
    func update(service: String, account: String, data: Data, accessibility: KeychainAccessibility) -> OSStatus
    func delete(service: String, account: String) -> OSStatus
    func errorMessage(for status: OSStatus) -> String?
}

enum KeychainReadResult: Sendable {
    case found(Data)
    case notFound
    case failed(OSStatus)
}

struct SystemKeychainAccess: KeychainAccessing {
    func read(service: String, account: String) -> KeychainReadResult {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        // AnyObject? = optional reference to any class instance. Like Go's interface{} but only for reference types.
        var result: AnyObject?
        // &result = inout parameter (like a pointer in Go/Rust). The function writes into `result` through this reference.
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            guard status != errSecItemNotFound else { return .notFound }
            return .failed(status)
        }
        guard let data = result as? Data else { return .notFound }
        return .found(data)
    }

    func add(
        service: String,
        account: String,
        data: Data,
        accessibility: KeychainAccessibility
    ) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessibility.secValue,
        ]
        return SecItemAdd(query as CFDictionary, nil)
    }

    func update(
        service: String,
        account: String,
        data: Data,
        accessibility: KeychainAccessibility
    ) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessibility.secValue,
        ]
        return SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }

    func delete(service: String, account: String) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        return SecItemDelete(query as CFDictionary)
    }

    func errorMessage(for status: OSStatus) -> String? {
        SecCopyErrorMessageString(status, nil) as String?
    }
}

// final class = reference type that can't be subclassed (like a sealed class in Kotlin, or Rust's non-dyn struct).
// class vs struct: class = reference type (like JS objects, passed by reference), struct = value type (copied on assign).
// Using class here because it conforms to Sendable and manages shared Keychain state.
final class KeychainTokenStorage: TokenStorage {
    private let service = "com.bochi.auth"
    private let tokensKey = "auth_tokens"
    private let keychain: any KeychainAccessing
    private let accessibility: KeychainAccessibility

    init(
        keychain: any KeychainAccessing = SystemKeychainAccess(),
        accessibility: KeychainAccessibility = .afterFirstUnlockThisDeviceOnly
    ) {
        self.keychain = keychain
        self.accessibility = accessibility
    }

    func getTokens() async throws -> AuthTokens? {
        let readResult = keychain.read(service: service, account: tokensKey)
        let data: Data?
        switch readResult {
        case .found(let storedData):
            data = storedData
        case .notFound:
            data = nil
        case .failed(let status):
            throw storageError(operation: "read", status: status)
        }
        guard let data else { return nil }
        return try? JSONDecoder().decode(AuthTokens.self, from: data)
    }

    // Behaviour: once a user signs in successfully, only the backend tokens
    // need to persist locally. Signed-out mode is now fully local-only.
    func storeTokens(_ tokens: AuthTokens) async throws {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        try writeKeychain(key: tokensKey, data: data)
    }

    func clear() async throws {
        try deleteKeychain(key: tokensKey)
    }

    // MARK: - Keychain helpers
    // ^ MARK comments = section dividers that show up in Xcode's jump bar. Like #region in C# or // region in JetBrains IDEs.

    private func writeKeychain(key: String, data: Data) throws {
        let updateStatus = keychain.update(
            service: service,
            account: key,
            data: data,
            accessibility: accessibility
        )
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            break
        default:
            throw storageError(operation: "write", status: updateStatus)
        }

        let addStatus = keychain.add(
            service: service,
            account: key,
            data: data,
            accessibility: accessibility
        )
        guard addStatus != errSecDuplicateItem else {
            let retryStatus = keychain.update(
                service: service,
                account: key,
                data: data,
                accessibility: accessibility
            )
            guard retryStatus == errSecSuccess else {
                throw storageError(operation: "write", status: retryStatus)
            }
            return
        }
        guard addStatus == errSecSuccess else {
            throw storageError(operation: "write", status: addStatus)
        }
    }

    private func deleteKeychain(key: String) throws {
        let status = keychain.delete(service: service, account: key)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw storageError(operation: "delete", status: status)
        }
    }

    private func storageError(operation: String, status: OSStatus) -> TokenStorageError {
        let fallbackMessage = "OSStatus \(status)"
        let platformMessage = keychain.errorMessage(for: status)
        let detail = platformMessage ?? fallbackMessage
        let message = "Keychain \(operation) failed: \(detail)"
        if status == errSecInteractionNotAllowed {
            return .temporarilyUnavailable(message)
        }
        return .operationFailed(message)
    }
}
