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
            if let access = anyApplicationAccess() {
                insert[kSecAttrAccess as String] = access
            }
            SecItemAdd(insert as CFDictionary, nil)
        }
    }

    /// An ACL with an empty trusted-application list, which the Keychain reads as "any application" — the programmatic
    /// form of Keychain Access's "Allow all applications", and of `security add-generic-password -A`. Without it
    /// `SecItemAdd` pins the item to the binary that created it, and since the app is signed with a self-signed identity
    /// whose binary changes with every release, each update would ask for the login password before the key could be
    /// read. The trade-off is deliberate: any process on the Mac can then read the key without a prompt. The alternative
    /// — the data-protection keychain, which has no ACLs at all — needs a stable Team ID this project doesn't have.
    /// Only new items are affected; `SecItemUpdate` leaves an existing item's ACL alone. The deprecation warning on
    /// `SecAccessCreate` is expected and load-bearing: setting an ACL on a file-keychain item has no replacement API.
    private static func anyApplicationAccess() -> SecAccess? {
        var access: SecAccess?
        guard SecAccessCreate(service as CFString, [] as CFArray, &access) == errSecSuccess else { return nil }
        return access
    }

    static func delete(account: String = googleAccount) {
        SecItemDelete(baseQuery(account) as CFDictionary)
    }
}
