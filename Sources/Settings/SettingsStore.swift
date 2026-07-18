import Foundation
import Observation

/// User-editable, persisted translation settings: which Ollama model to use,
/// the app's primary language and the other side of the pair. Backed by
/// UserDefaults; the SwiftUI Settings view binds to it and AppCoordinator reads
/// it at translate time.
@MainActor
@Observable
final class SettingsStore {
    private enum Key {
        static let model = "llm.model"
        static let primaryLanguage = "app.primaryLanguage"
        static let secondLanguage = "translation.secondLanguage"
        static let formality = "translation.formality"
        static let fixChord = "shortcut.fixInPlace"
        static let translateInPlaceChord = "shortcut.translateInPlace"
        static let hasCompletedOnboarding = "app.hasCompletedOnboarding"
        static let lastNotifiedVersion = "update.lastNotifiedVersion"
    }

    /// UserDefaults sentinel for the automatic second language (`nil` in code).
    private static let autoSecond = "auto"

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let loginItem: any LoginItemManaging

    var modelName: String {
        didSet { defaults.set(modelName, forKey: Key.model) }
    }

    /// The fixed side of the pair and the UI language. Switching it away from a
    /// conflicting second (the pair must never be X↔X) flips the second to the
    /// PL/EN counterpart.
    var primaryLanguage: PrimaryLanguage {
        didSet {
            defaults.set(primaryLanguage.rawValue, forKey: Key.primaryLanguage)
            L10n.set(primaryLanguage)
            if secondLanguage == primaryLanguage.asSecond {
                secondLanguage = primaryLanguage.counterpart.asSecond
            }
        }
    }

    /// `nil` means Automatic: the second side is detected per selection/page.
    var secondLanguage: SecondLanguage? {
        didSet { defaults.set(secondLanguage?.rawValue ?? Self.autoSecond, forKey: Key.secondLanguage) }
    }

    var formality: Formality {
        didSet { defaults.set(formality.rawValue, forKey: Key.formality) }
    }

    /// Headless "fix grammar in place" chord (issue #21), default Ctrl+Cmd+G.
    var fixChord: KeyChord {
        didSet { defaults.set(try? JSONEncoder().encode(fixChord), forKey: Key.fixChord) }
    }

    /// Headless "translate in place" chord (issue #21), default Ctrl+Cmd+T.
    var translateInPlaceChord: KeyChord {
        didSet { defaults.set(try? JSONEncoder().encode(translateInPlaceChord), forKey: Key.translateInPlaceChord) }
    }

    /// False on a fresh install (absent key) — drives the first-run wizard. Set
    /// true once the user finishes (or skips) onboarding.
    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding) }
    }

    /// The release version we have already shown a notification for, so the update
    /// dymek fires exactly once per version (empty until the first one fires).
    var lastNotifiedVersion: String {
        didSet { defaults.set(lastNotifiedVersion, forKey: Key.lastNotifiedVersion) }
    }

    // Source of truth is the system registration, not UserDefaults: the user can
    // revoke it in System Settings, so a mirrored flag would drift.
    var launchAtLogin: Bool {
        didSet {
            // Skip when the value already matches reality (a refresh or a revert),
            // so this only acts on a genuine user toggle.
            guard launchAtLogin != loginItem.isEnabled else { return }
            do { try loginItem.setEnabled(launchAtLogin) }
            catch { launchAtLogin = oldValue }
        }
    }

    init(
        defaults: UserDefaults = .standard,
        loginItem: any LoginItemManaging = SMAppServiceLoginItem(),
        systemLanguages: [String] = Locale.preferredLanguages
    ) {
        self.defaults = defaults
        self.loginItem = loginItem
        self.modelName = defaults.string(forKey: Key.model) ?? EmbeddedModelCatalog.recommended.id
        // Existing installs (any onboarding flag present) predate the primary
        // language setting and were Polish-axis — keep their behavior. Fresh
        // installs seed from the system language, so onboarding renders in it.
        let primary = defaults.string(forKey: Key.primaryLanguage)
            .flatMap(PrimaryLanguage.init(rawValue:))
            ?? (defaults.object(forKey: Key.hasCompletedOnboarding) != nil
                ? .polish
                : (systemLanguages.first?.hasPrefix("pl") == true ? .polish : .english))
        self.primaryLanguage = primary
        let storedSecond = defaults.string(forKey: Key.secondLanguage)
        let second: SecondLanguage? = storedSecond == Self.autoSecond
            ? nil
            : storedSecond.flatMap(SecondLanguage.init(rawValue:)) ?? primary.counterpart.asSecond
        // A stored second equal to the primary (e.g. defaults written by hand)
        // would make the pair X↔X — flip it to the counterpart.
        self.secondLanguage = second == primary.asSecond ? primary.counterpart.asSecond : second
        self.formality = defaults.string(forKey: Key.formality)
            .flatMap(Formality.init(rawValue:)) ?? .automatic
        self.fixChord = defaults.data(forKey: Key.fixChord)
            .flatMap { try? JSONDecoder().decode(KeyChord.self, from: $0) } ?? .fixGrammarDefault
        self.translateInPlaceChord = defaults.data(forKey: Key.translateInPlaceChord)
            .flatMap { try? JSONDecoder().decode(KeyChord.self, from: $0) } ?? .translateInPlaceDefault
        self.hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)
        self.lastNotifiedVersion = defaults.string(forKey: Key.lastNotifiedVersion) ?? ""
        self.launchAtLogin = loginItem.isEnabled
        // didSet doesn't fire during init — mirror the UI language explicitly.
        L10n.set(primaryLanguage)
    }

    /// Re-reads the real registration status; the user may have toggled the login
    /// item in System Settings while the app was running.
    func refreshLaunchAtLogin() {
        let actual = loginItem.isEnabled
        if launchAtLogin != actual { launchAtLogin = actual }
    }
}
