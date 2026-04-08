import Foundation
import Security

protocol TokenStorage: Sendable {
    func getTokens() async -> AuthTokens?
    func storeTokens(_ tokens: AuthTokens, isAnonymous: Bool) async
    func getIsAnonymous() async -> Bool?
    func clear() async
    func getOrCreateDeviceId() async -> String
}

final class KeychainTokenStorage: TokenStorage {
    private let service = "com.tofustash.auth"
    private let tokensKey = "auth_tokens"
    private let anonymousKey = "auth_is_anonymous"
    private let deviceIdKey = "device_id"

    func getTokens() async -> AuthTokens? {
        guard let data = readKeychain(key: tokensKey) else { return nil }
        return try? JSONDecoder().decode(AuthTokens.self, from: data)
    }

    func storeTokens(_ tokens: AuthTokens, isAnonymous: Bool) async {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        writeKeychain(key: tokensKey, data: data)
        writeKeychain(key: anonymousKey, data: Data(isAnonymous ? "true".utf8 : "false".utf8))
    }

    func getIsAnonymous() async -> Bool? {
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
        if let data = readKeychain(key: deviceIdKey),
           let id = String(data: data, encoding: .utf8) {
            return id
        }
        let id = UUID().uuidString
        writeKeychain(key: deviceIdKey, data: Data(id.utf8))
        return id
    }

    // MARK: - Keychain helpers

    private func readKeychain(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    private func writeKeychain(key: String, data: Data) {
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
