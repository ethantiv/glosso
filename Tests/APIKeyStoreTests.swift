import Foundation
import Security
import Synchronization
import Testing
@testable import Glosso

private final class FakeKeychain: KeychainAccess {
    struct State {
        var values: [String: Data] = [:]
        var failure: OSStatus?
        var added = 0
        var updates = 0
    }
    let state = Mutex(State())
    private func account(_ query: [String: Any]) -> String { query[kSecAttrAccount as String] as! String }
    func read(_ query: [String: Any]) -> (OSStatus, Data?) {
        state.withLock {
            if let failure = $0.failure { return (failure, nil) }
            return ($0.values[account(query)] == nil ? errSecItemNotFound : errSecSuccess, $0.values[account(query)])
        }
    }
    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        state.withLock {
            if let failure = $0.failure { return failure }
            guard $0.values[account(query)] != nil else { return errSecItemNotFound }
            $0.updates += 1
            $0.values[account(query)] = attributes[kSecValueData as String] as? Data
            return errSecSuccess
        }
    }
    func add(_ attributes: [String: Any]) -> OSStatus {
        state.withLock {
            if let failure = $0.failure { return failure }
            $0.added += 1
            $0.values[account(attributes)] = attributes[kSecValueData as String] as? Data
            return errSecSuccess
        }
    }
    func delete(_ query: [String: Any]) -> OSStatus {
        state.withLock {
            if let failure = $0.failure { return failure }
            return $0.values.removeValue(forKey: account(query)) == nil ? errSecItemNotFound : errSecSuccess
        }
    }
}

@Suite struct APIKeyStoreTests {
    @Test func insertsUpdatesAndKeepsProviderAccountsSeparate() {
        let keychain = FakeKeychain()
        #expect(APIKeyStore.read(using: keychain) == nil)
        #expect(APIKeyStore.save(" first ", using: keychain))
        #expect(APIKeyStore.save("second", using: keychain))
        #expect(APIKeyStore.save("cloud", account: APIKeyStore.ollamaAccount, using: keychain))
        #expect(APIKeyStore.read(using: keychain) == "second")
        #expect(APIKeyStore.read(account: APIKeyStore.ollamaAccount, using: keychain) == "cloud")
        #expect(keychain.state.withLock { $0.added } == 2)
        #expect(keychain.state.withLock { $0.updates } == 1)
    }

    @Test(arguments: [errSecAuthFailed, errSecInteractionNotAllowed, errSecNotAvailable])
    func deniedAccessNeverReportsSuccessfulSaveOrDeletion(status: OSStatus) {
        let keychain = FakeKeychain()
        #expect(APIKeyStore.save("existing", using: keychain))
        keychain.state.withLock { $0.failure = status }
        #expect(!APIKeyStore.save("new", using: keychain))
        #expect(!APIKeyStore.save("  ", using: keychain))
        #expect(!APIKeyStore.delete(using: keychain))
        #expect(APIKeyStore.read(using: keychain) == nil)
        keychain.state.withLock { $0.failure = nil }
        #expect(APIKeyStore.read(using: keychain) == "existing")
    }

    @Test func emptyKeyDeletesAndMissingDeletionIsIdempotent() {
        let keychain = FakeKeychain()
        #expect(APIKeyStore.save("key", using: keychain))
        #expect(APIKeyStore.save("\n ", using: keychain))
        #expect(APIKeyStore.read(using: keychain) == nil)
        #expect(APIKeyStore.delete(using: keychain))
    }
}
