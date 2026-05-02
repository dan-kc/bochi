import Foundation
// Security = Apple's framework for Keychain (OS-level secure storage, like OS credential managers).
import Security

// Protocol with Sendable = thread-safe interface. Think of it as a TS interface + Rust's Send bound.
protocol TokenStorage: Sendable {
    func getTokens() async -> AuthTokens?
    func storeTokens(_ tokens: AuthTokens) async
    func clear() async
}

actor InMemoryTokenStorage: TokenStorage {
    private var tokens: AuthTokens?

    func getTokens() async -> AuthTokens? {
        tokens
    }

    func storeTokens(_ tokens: AuthTokens) async {
        self.tokens = tokens
    }

    func clear() async {
        tokens = nil
    }
}

// final class = reference type that can't be subclassed (like a sealed class in Kotlin, or Rust's non-dyn struct).
// class vs struct: class = reference type (like JS objects, passed by reference), struct = value type (copied on assign).
// Using class here because it conforms to Sendable and manages shared Keychain state.
final class KeychainTokenStorage: TokenStorage {
    private let service = "com.tofustash.auth"
    private let tokensKey = "auth_tokens"

    func getTokens() async -> AuthTokens? {
        guard let data = readKeychain(key: tokensKey) else { return nil }
        return try? JSONDecoder().decode(AuthTokens.self, from: data)
    }

    // Behaviour: once a user signs in successfully, only the backend tokens
    // need to persist locally. Signed-out mode is now fully local-only.
    func storeTokens(_ tokens: AuthTokens) async {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        writeKeychain(key: tokensKey, data: data)
    }

    func clear() async {
        deleteKeychain(key: tokensKey)
    }

    // MARK: - Keychain helpers
    // ^ MARK comments = section dividers that show up in Xcode's jump bar. Like #region in C# or // region in JetBrains IDEs.

    // [String: Any] = dictionary literal. Like TS Record<string, any> or Go map[string]interface{}.
    // The kSec* constants are Apple's Keychain API keys (CoreFoundation strings).
    private func readKeychain(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        // AnyObject? = optional reference to any class instance. Like Go's interface{} but only for reference types.
        var result: AnyObject?
        // &result = inout parameter (like a pointer in Go/Rust). The function writes into `result` through this reference.
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            guard status != errSecItemNotFound else { return nil }
            reportKeychainFailure(operation: "read", status: status)
            return nil
        }
        return result as? Data
    }

    private func writeKeychain(key: String, data: Data) {
        // Delete-then-add pattern because Keychain has no upsert. Like a SQL DELETE + INSERT.
        deleteKeychain(key: key)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            reportKeychainFailure(operation: "write", status: status)
            return
        }
    }

    private func deleteKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            reportKeychainFailure(operation: "delete", status: status)
            return
        }
    }

    private func reportKeychainFailure(operation: String, status: OSStatus) {
        let fallbackMessage = "OSStatus \(status)"
        let platformMessage = SecCopyErrorMessageString(status, nil) as String?
        let detail = platformMessage ?? fallbackMessage
        assertionFailure("Keychain \(operation) failed: \(detail)")
    }
}
