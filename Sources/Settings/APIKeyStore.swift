import Foundation
import Security

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

    static func read(account: String = googleAccount) -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ key: String, account: String = googleAccount) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return delete(account: account) }
        guard let data = trimmed.data(using: .utf8) else { return }
        let attributes = [kSecValueData as String: data]
        if SecItemUpdate(baseQuery(account) as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            var insert = baseQuery(account)
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(insert as CFDictionary, nil)
        }
    }

    static func delete(account: String = googleAccount) {
        SecItemDelete(baseQuery(account) as CFDictionary)
    }
}
