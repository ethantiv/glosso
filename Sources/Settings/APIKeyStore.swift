import Foundation
import Security

protocol KeychainAccess: Sendable {
    func read(_ query: [String: Any]) -> (OSStatus, Data?)
    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus
    func add(_ attributes: [String: Any]) -> OSStatus
    func delete(_ query: [String: Any]) -> OSStatus
}

struct SystemKeychainAccess: KeychainAccess {
    func read(_ query: [String: Any]) -> (OSStatus, Data?) {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        return (status, item as? Data)
    }
    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }
    func add(_ attributes: [String: Any]) -> OSStatus { SecItemAdd(attributes as CFDictionary, nil) }
    func delete(_ query: [String: Any]) -> OSStatus { SecItemDelete(query as CFDictionary) }
}

/// The cloud API keys in the Keychain — the app's only secrets; UserDefaults would put them in a plain-text plist.
enum APIKeyStore {
    private static let service = "com.mirek.glosso"
    static let googleAccount = "google-api-key"
    static let ollamaAccount = "ollama-api-key"

    private static func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func read(account: String = googleAccount, using keychain: any KeychainAccess = SystemKeychainAccess()) -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let (status, data) = keychain.read(query)
        guard status == errSecSuccess, let data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// False when the Keychain rejected the write (locked keychain, denied ACL prompt) — the caller must say so,
    /// or the field keeps showing a key that will be gone after relaunch.
    @discardableResult
    static func save(_ key: String, account: String = googleAccount, using keychain: any KeychainAccess = SystemKeychainAccess()) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return delete(account: account, using: keychain) }
        guard let data = trimmed.data(using: .utf8) else { return false }
        let attributes = [kSecValueData as String: data]
        let updated = keychain.update(baseQuery(account), attributes: attributes)
        if updated == errSecSuccess { return true }
        guard updated == errSecItemNotFound else { return false }
        var insert = baseQuery(account)
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return keychain.add(insert) == errSecSuccess
    }

    @discardableResult
    static func delete(account: String = googleAccount, using keychain: any KeychainAccess = SystemKeychainAccess()) -> Bool {
        let status = keychain.delete(baseQuery(account))
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
