import Foundation
import Testing
@testable import TranslatorMenuBar

@MainActor
@Suite struct SettingsStoreTests {
    private func transientDefaults() -> UserDefaults {
        UserDefaults(suiteName: "SettingsStoreTests-\(UUID().uuidString)")!
    }

    // A fresh install must start on exactly the hardcoded MVP defaults, so the
    // app behaves identically until the user changes anything.
    @Test func defaultsMatchTheHardcodedConfig() {
        let store = SettingsStore(defaults: transientDefaults())
        #expect(store.modelName == LLMConfig.default.model)
        #expect(store.secondLanguage == .english)
    }

    // A reload (app restart) must see the previously chosen values, proving they
    // were persisted and not just held in memory — the whole point of the feature.
    @Test func persistsChangesAcrossReload() {
        let defaults = transientDefaults()
        let first = SettingsStore(defaults: defaults)
        first.modelName = "llama3:8b"
        first.secondLanguage = .german

        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.modelName == "llama3:8b")
        #expect(reloaded.secondLanguage == .german)
    }

    // A corrupt/unknown persisted language code must fall back to English rather
    // than leave the picker on an invalid selection.
    @Test func unknownPersistedLanguageFallsBackToEnglish() {
        let defaults = transientDefaults()
        defaults.set("xx", forKey: "translation.secondLanguage")
        let store = SettingsStore(defaults: defaults)
        #expect(store.secondLanguage == .english)
    }
}
