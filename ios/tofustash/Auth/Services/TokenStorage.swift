import Foundation
// Security = Apple's framework for Keychain (OS-level secure storage, like OS credential managers).
import Security

// Protocol with Sendable = thread-safe interface. Think of it as a TS interface + Rust's Send bound.
protocol TokenStorage: Sendable {
    func getTokens() async -> AuthTokens?
    func storeTokens(_ tokens: AuthTokens, isAnonymous: Bool) async
    func getIsAnonymous() async -> Bool?
    func clear() async
    func getOrCreateDeviceId() async -> String
}

// final class = reference type that can't be subclassed (like a sealed class in Kotlin, or Rust's non-dyn struct).
// class vs struct: class = reference type (like JS objects, passed by reference), struct = value type (copied on assign).
// Using class here because it conforms to Sendable and manages shared Keychain state.
final class KeychainTokenStorage: TokenStorage {
    private let service = "com.tofustash.auth"
    private let tokensKey = "auth_tokens"
    private let anonymousKey = "auth_is_anonymous"
    private let deviceIdKey = "device_id"

    func getTokens() async -> AuthTokens? {
        guard let data = readKeychain(key: tokensKey) else { return nil }
        return try? JSONDecoder().decode(AuthTokens.self, from: data)
    }

    // _ before param name = caller omits the label. `isAnonymous:` has a label so callers write storeTokens(tokens, isAnonymous: true).
    func storeTokens(_ tokens: AuthTokens, isAnonymous: Bool) async {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        writeKeychain(key: tokensKey, data: data)
        // Data(...utf8) = convert string to raw bytes. Like Go's []byte("string") or Rust's .as_bytes().
        writeKeychain(key: anonymousKey, data: Data(isAnonymous ? "true".utf8 : "false".utf8))
    }

    func getIsAnonymous() async -> Bool? {
        // Multi-clause guard: unwraps two optionals or bails. Each `let` introduces a new non-optional binding.
        guard let data = readKeychain(key: anonymousKey),
              let value = String(data: data, encoding: .utf8)
        else { return nil }
        return value == "true"
    }

    func clear() async {
        deleteKeychain(key: tokensKey)
        deleteKeychain(key: anonymousKey)
    }

    func getOrCreateDeviceId() async -> String {
        // `if let` with multiple bindings = like chaining Rust's .and_then(). Both must succeed to enter the block.
        if let data = readKeychain(key: deviceIdKey),
           let id = String(data: data, encoding: .utf8) {
            return id
        }
        // UUID().uuidString = generates a v4 UUID string. Like Go's uuid.New().String() or crypto.randomUUID() in JS.
        let id = UUID().uuidString
        writeKeychain(key: deviceIdKey, data: Data(id.utf8))
        return id
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
        guard status == errSecSuccess else { return nil }
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
        SecItemAdd(query as CFDictionary, nil)
    }

    private func deleteKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
