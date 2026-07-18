import AppKit
import Foundation
import Testing
@testable import Glosso

@MainActor
@Suite struct SettingsStoreTests {
    private func transientDefaults() -> UserDefaults {
        UserDefaults(suiteName: "SettingsStoreTests-\(UUID().uuidString)")!
    }

    // A fresh install must start on the model recommended for this Mac's RAM (not a
    // hardcoded tag), and on the hardcoded MVP defaults for everything else, so the
    // app behaves predictably until the user changes anything.
    @Test func defaultsMatchTheHardcodedConfig() {
        let store = SettingsStore(defaults: transientDefaults(), systemLanguages: ["pl-PL"])
        #expect(store.modelName == EmbeddedModelCatalog.recommended.id)
        #expect(store.primaryLanguage == .polish)
        #expect(store.secondLanguage == .english)
        #expect(store.formality == .automatic)
        #expect(store.fixChord == .fixGrammarDefault)
        #expect(store.translateInPlaceChord == .translateInPlaceDefault)
    }

    // MARK: Primary language (internationalization)

    // A fresh install seeds the primary from the system language, so onboarding
    // renders in it; the second then defaults to the counterpart, never X↔X.
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

    // Existing installs predate the primary-language setting and were Polish-axis:
    // the onboarding flag's presence is the migration marker, and their stored
    // English second language must survive untouched.
    @Test func existingInstallMigratesToPolishPrimary() {
        let defaults = transientDefaults()
        defaults.set(true, forKey: "app.hasCompletedOnboarding")
        defaults.set("en", forKey: "translation.secondLanguage")
        let store = SettingsStore(defaults: defaults, systemLanguages: ["en-US"])
        #expect(store.primaryLanguage == .polish)
        #expect(store.secondLanguage == .english)
    }

    // The seed must be persisted during init (didSet doesn't fire there): after
    // onboarding completes without the user touching the primary picker, the next
    // launch would otherwise see the key absent and migration-revert to Polish.
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

    // The pair must never be X↔X: switching the primary onto the current second
    // flips the second to the PL/EN counterpart, live and on load.
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

    // The first-run wizard must show exactly once: a fresh install starts
    // not-onboarded, and once finished the flag must survive a restart so the wizard
    // never reappears.
    @Test func onboardingFlagDefaultsFalseAndPersists() {
        let defaults = transientDefaults()
        #expect(SettingsStore(defaults: defaults).hasCompletedOnboarding == false)

        SettingsStore(defaults: defaults).hasCompletedOnboarding = true
        #expect(SettingsStore(defaults: defaults).hasCompletedOnboarding == true)
    }

    // The configurable action shortcuts (issue #21) must survive a restart, or the
    // user's rebinding is lost the moment the app relaunches.
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

    // A reload (app restart) must see the previously chosen values, proving they
    // were persisted and not just held in memory — the whole point of the feature.
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

    // A corrupt/unknown persisted language code must fall back to English rather
    // than leave the picker on an invalid selection.
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

    // The toggle is the whole point of the setting: flipping it on/off must drive
    // the actual login-item registration, and the store must mirror fresh state.
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

    // If the system rejects registration, the toggle must snap back, so the UI
    // never claims an enabled state that isn't actually in effect.
    @Test func launchAtLoginRevertsWhenRegistrationFails() {
        struct Boom: Error {}
        let login = FakeLoginItem(isEnabled: false)
        login.setEnabledError = Boom()
        let store = SettingsStore(defaults: transientDefaults(), loginItem: login)

        store.launchAtLogin = true
        #expect(store.launchAtLogin == false)
        #expect(login.isEnabled == false)
    }

    // A status change made in System Settings (revocation) must surface on
    // refresh — and refresh must only reflect it, never re-trigger registration.
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
