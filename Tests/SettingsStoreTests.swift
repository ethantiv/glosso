import AppKit
import Foundation
import Testing
@testable import Glosso

@MainActor
@Suite struct SettingsStoreTests {
    private func transientDefaults() -> UserDefaults {
        UserDefaults(suiteName: "SettingsStoreTests-\(UUID().uuidString)")!
    }

    @Test func defaultsMatchTheHardcodedConfig() {
        let store = SettingsStore(defaults: transientDefaults(), systemLanguages: ["pl-PL"])
        #expect(store.modelName == EmbeddedModelCatalog.recommended.id)
        #expect(store.primaryLanguage == .polish)
        #expect(store.secondLanguage == .english)
        #expect(store.formality == .automatic)
        #expect(store.fixChord == .fixGrammarDefault)
        #expect(store.translateInPlaceChord == .translateInPlaceDefault)
    }

    @Test func readerRetentionDefaultsPersistsAndNormalizes() {
        let defaults = transientDefaults()
        let store = SettingsStore(defaults: defaults)
        #expect(store.readerRetentionDays == 7)

        store.readerRetentionDays = 30
        #expect(SettingsStore(defaults: defaults).readerRetentionDays == 30)

        defaults.set(11, forKey: "reader.retentionDays")
        #expect(SettingsStore(defaults: defaults).readerRetentionDays == 7)
    }

    @Test func readerCinemaModeDefaultsOnAndPersistsOff() {
        let defaults = transientDefaults()
        let store = SettingsStore(defaults: defaults)
        #expect(store.readerCinemaMode)

        store.readerCinemaMode = false
        #expect(!SettingsStore(defaults: defaults).readerCinemaMode)
    }

    // MARK: Primary language (internationalization)

    @Test func freshInstallSeedsPrimaryFromSystemLanguage() {
        let polish = SettingsStore(defaults: transientDefaults(), systemLanguages: ["pl-PL", "en-US"])
        #expect(polish.primaryLanguage == .polish)
        #expect(polish.secondLanguage == .english)

        let english = SettingsStore(defaults: transientDefaults(), systemLanguages: ["en-US"])
        #expect(english.primaryLanguage == .english)
        #expect(english.secondLanguage == .polish)

        let german = SettingsStore(defaults: transientDefaults(), systemLanguages: ["de-DE"])
        #expect(german.primaryLanguage == .english)
    }

    @Test func existingInstallMigratesToPolishPrimary() {
        let defaults = transientDefaults()
        defaults.set(true, forKey: "app.hasCompletedOnboarding")
        defaults.set("en", forKey: "translation.secondLanguage")
        let store = SettingsStore(defaults: defaults, systemLanguages: ["en-US"])
        #expect(store.primaryLanguage == .polish)
        #expect(store.secondLanguage == .english)
    }

    @Test func seededPrimarySurvivesOnboardingCompletion() {
        let defaults = transientDefaults()
        let first = SettingsStore(defaults: defaults, systemLanguages: ["en-US"])
        #expect(first.primaryLanguage == .english)
        first.hasCompletedOnboarding = true

        let secondLaunch = SettingsStore(defaults: defaults, systemLanguages: ["en-US"])
        #expect(secondLaunch.primaryLanguage == .english)
    }

    @Test func persistsPrimaryLanguageAcrossReload() {
        let defaults = transientDefaults()
        SettingsStore(defaults: defaults).primaryLanguage = .english
        #expect(SettingsStore(defaults: defaults).primaryLanguage == .english)
    }

    @Test func switchingPrimaryOntoSecondFlipsTheSecond() {
        let store = SettingsStore(defaults: transientDefaults(), systemLanguages: ["pl-PL"])
        #expect(store.secondLanguage == .english)
        store.primaryLanguage = .english
        #expect(store.secondLanguage == .polish)
        store.primaryLanguage = .polish
        #expect(store.secondLanguage == .english)
    }

    @Test func conflictingStoredSecondIsSanitizedOnLoad() {
        let defaults = transientDefaults()
        defaults.set("en", forKey: "app.primaryLanguage")
        defaults.set("en", forKey: "translation.secondLanguage")
        let store = SettingsStore(defaults: defaults)
        #expect(store.secondLanguage == .polish)
    }

    // nil = Automatic, persisted as the "auto" sentinel.
    @Test func automaticSecondRoundTrips() {
        let defaults = transientDefaults()
        SettingsStore(defaults: defaults).secondLanguage = nil
        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.secondLanguage == nil)
    }

    @Test func onboardingFlagDefaultsFalseAndPersists() {
        let defaults = transientDefaults()
        #expect(SettingsStore(defaults: defaults).hasCompletedOnboarding == false)

        SettingsStore(defaults: defaults).hasCompletedOnboarding = true
        #expect(SettingsStore(defaults: defaults).hasCompletedOnboarding == true)
    }

    @Test func persistsChordsAcrossReload() {
        let defaults = transientDefaults()
        let cmdOpt = NSEvent.ModifierFlags([.command, .option]).rawValue
        let first = SettingsStore(defaults: defaults)
        first.fixChord = KeyChord(key: "g", modifiers: cmdOpt)
        first.translateInPlaceChord = KeyChord(key: "r", modifiers: cmdOpt)

        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.fixChord == KeyChord(key: "g", modifiers: cmdOpt))
        #expect(reloaded.translateInPlaceChord == KeyChord(key: "r", modifiers: cmdOpt))
    }

    @Test func persistsChangesAcrossReload() {
        let defaults = transientDefaults()
        let first = SettingsStore(defaults: defaults)
        first.modelName = "llama3:8b"
        first.secondLanguage = .german
        first.formality = .formal

        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.modelName == "llama3:8b")
        #expect(reloaded.secondLanguage == .german)
        #expect(reloaded.formality == .formal)
    }

    // MARK: Cloud provider

    @Test func freshInstallStaysOnTheLocalEngine() {
        // The cloud sends the selection off the machine, so it must be opt-in.
        let store = SettingsStore(defaults: transientDefaults(), readAPIKey: { nil }, writeAPIKey: { _ in true })
        #expect(store.provider == .local)
        #expect(store.cloudModel == CloudModelCatalog.default.id)
        #expect(store.activeModel == store.modelName)
    }

    @Test func aFreshInstallDoesNotPersistTheCloudModel() {
        // Nothing written means a changed catalog default reaches everyone who never picked a model themselves.
        let defaults = transientDefaults()
        _ = SettingsStore(defaults: defaults, readAPIKey: { nil }, writeAPIKey: { _ in true })
        #expect(defaults.object(forKey: "llm.cloudModel") == nil)
    }

    @Test func activeModelFollowsTheSelectedProvider() {
        // The engines name models differently; every LLM call reads activeModel, so the wrong side means "model not found".
        let store = SettingsStore(defaults: transientDefaults(), readAPIKey: { nil }, writeAPIKey: { _ in true })
        store.modelName = "gemma4:26b-mlx"
        store.cloudModel = "gemma-4-31b-it"

        #expect(store.activeModel == "gemma4:26b-mlx")
        store.provider = .cloud
        #expect(store.activeModel == "gemma-4-31b-it")
    }

    @Test func persistsProviderAndCloudModelAcrossReload() {
        let defaults = transientDefaults()
        let first = SettingsStore(defaults: defaults, readAPIKey: { nil }, writeAPIKey: { _ in true })
        first.provider = .cloud
        first.cloudModel = "gemma-4-26b-a4b-it"

        let reloaded = SettingsStore(defaults: defaults, readAPIKey: { nil }, writeAPIKey: { _ in true })
        #expect(reloaded.provider == .cloud)
        #expect(reloaded.cloudModel == "gemma-4-26b-a4b-it")
    }

    @Test func unknownPersistedProviderFallsBackToLocal() {
        let defaults = transientDefaults()
        defaults.set("xx", forKey: "llm.provider")
        let store = SettingsStore(defaults: defaults, readAPIKey: { nil }, writeAPIKey: { _ in true })
        #expect(store.provider == .local)
    }

    @Test func apiKeyIsWrittenToTheKeychainNotToDefaults() {
        let defaults = transientDefaults()
        let written = KeyBox()
        let store = SettingsStore(defaults: defaults, readAPIKey: { nil }, writeAPIKey: { written.value = $0; return true })

        store.apiKey = "AIza-secret"

        #expect(written.value == "AIza-secret")
        // A secret in the defaults plist would sit in plain text and ride into backups.
        #expect(defaults.dictionaryRepresentation().values.allSatisfy { ($0 as? String) != "AIza-secret" })
    }

    @Test func theKeychainIsUntouchedUntilTheFieldShowingTheKeyAppears() {
        // On a self-signed build the signature changes every release, so each Keychain read is a password prompt.
        // Nothing but the two SecureFields needs these — the clients read the Keychain themselves, per request.
        let google = Counter(), ollama = Counter()
        let writes = KeyBox()
        let store = SettingsStore(
            defaults: transientDefaults(),
            readAPIKey: { google.bump(); return "AIza-secret" },
            writeAPIKey: { writes.value = $0; return true },
            readOllamaAPIKey: { ollama.bump(); return "ollama-secret" },
            writeOllamaAPIKey: { _ in true }
        )
        #expect(google.value == 0)
        #expect(ollama.value == 0)
        #expect(store.apiKey.isEmpty)

        // One field on screen must cost one prompt, not two: the other provider's section isn't rendered.
        store.loadGoogleAPIKey()
        #expect(store.apiKey == "AIza-secret")
        #expect(ollama.value == 0)
        // Seeding must not look like an edit, or showing the field would write the key straight back.
        #expect(writes.value == nil)

        store.loadGoogleAPIKey()
        #expect(google.value == 1)

        store.loadOllamaAPIKey()
        #expect(store.ollamaAPIKey == "ollama-secret")
        #expect(ollama.value == 1)
    }

    @Test func activeModelFollowsTheOllamaCloudProvider() {
        // Three engines, three naming schemes: `gemma4:31b` means nothing to Gemini and `gemma-4-31b-it` means nothing to Ollama.
        let store = SettingsStore(defaults: transientDefaults(), readAPIKey: { nil }, writeAPIKey: { _ in true },
                                  readOllamaAPIKey: { nil }, writeOllamaAPIKey: { _ in true })
        store.modelName = "gemma4:26b-mlx"
        store.cloudModel = "gemma-4-31b-it"

        store.provider = .ollamaCloud
        #expect(store.activeModel == OllamaCloudCatalog.defaultModel)
        store.ollamaCloudModel = "gpt-oss:120b"
        #expect(store.activeModel == "gpt-oss:120b")
    }

    @Test func aFreshInstallDoesNotPersistTheOllamaCloudModel() {
        // Same reason as the Gemini catalog: Ollama retires cloud models, and an unwritten key lets a new default reach everyone who never picked one.
        let defaults = transientDefaults()
        _ = SettingsStore(defaults: defaults, readAPIKey: { nil }, writeAPIKey: { _ in true },
                          readOllamaAPIKey: { nil }, writeOllamaAPIKey: { _ in true })
        #expect(defaults.object(forKey: "llm.ollamaCloudModel") == nil)
    }

    @Test func theOllamaKeyIsWrittenToTheKeychainNotToDefaults() {
        let defaults = transientDefaults()
        let written = KeyBox()
        let store = SettingsStore(defaults: defaults, readAPIKey: { nil }, writeAPIKey: { _ in true },
                                  readOllamaAPIKey: { nil }, writeOllamaAPIKey: { written.value = $0; return true })

        store.ollamaAPIKey = "ollama-secret"

        #expect(written.value == "ollama-secret")
        #expect(defaults.dictionaryRepresentation().values.allSatisfy { ($0 as? String) != "ollama-secret" })
    }

    @Test func theTwoCloudKeysDoNotOverwriteEachOther() {
        // One Keychain service, two accounts — a shared slot would make picking a provider wipe the other's key.
        let google = KeyBox()
        let ollama = KeyBox()
        let store = SettingsStore(defaults: transientDefaults(),
                                  readAPIKey: { nil }, writeAPIKey: { google.value = $0; return true },
                                  readOllamaAPIKey: { nil }, writeOllamaAPIKey: { ollama.value = $0; return true })

        store.apiKey = "AIza-secret"
        store.ollamaAPIKey = "ollama-secret"

        #expect(google.value == "AIza-secret")
        #expect(ollama.value == "ollama-secret")
    }

    @Test func unknownPersistedLanguageFallsBackToEnglish() {
        let defaults = transientDefaults()
        defaults.set("xx", forKey: "translation.secondLanguage")
        let store = SettingsStore(defaults: defaults)
        #expect(store.secondLanguage == .english)
    }

    // Same guard for a corrupt/unknown persisted formality code.
    @Test func unknownPersistedFormalityFallsBackToAutomatic() {
        let defaults = transientDefaults()
        defaults.set("xx", forKey: "translation.formality")
        let store = SettingsStore(defaults: defaults)
        #expect(store.formality == .automatic)
    }

    @Test func togglingLaunchAtLoginRegistersAndUnregisters() {
        let login = FakeLoginItem(isEnabled: false)
        let store = SettingsStore(defaults: transientDefaults(), loginItem: login)
        #expect(store.launchAtLogin == false)

        store.launchAtLogin = true
        #expect(login.setEnabledCalls == [true])
        #expect(login.isEnabled)

        store.launchAtLogin = false
        #expect(login.setEnabledCalls == [true, false])
        #expect(login.isEnabled == false)
    }

    @Test func launchAtLoginRevertsWhenRegistrationFails() {
        struct Boom: Error {}
        let login = FakeLoginItem(isEnabled: false)
        login.setEnabledError = Boom()
        let store = SettingsStore(defaults: transientDefaults(), loginItem: login)

        store.launchAtLogin = true
        #expect(store.launchAtLogin == false)
        #expect(login.isEnabled == false)
    }

    @Test func refreshReflectsExternalStatusWithoutReRegistering() {
        let login = FakeLoginItem(isEnabled: true)
        let store = SettingsStore(defaults: transientDefaults(), loginItem: login)
        #expect(store.launchAtLogin)

        login.isEnabled = false
        store.refreshLaunchAtLogin()
        #expect(store.launchAtLogin == false)
        #expect(login.setEnabledCalls.isEmpty)
    }
}

private final class KeyBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?

    var value: String? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int { lock.withLock { count } }
    func bump() { lock.withLock { count += 1 } }
}
