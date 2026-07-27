import Foundation
import Observation

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

    var primaryLanguage: PrimaryLanguage {
        didSet {
            defaults.set(primaryLanguage.rawValue, forKey: Key.primaryLanguage)
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

    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding) }
    }

    var lastNotifiedVersion: String {
        didSet { defaults.set(lastNotifiedVersion, forKey: Key.lastNotifiedVersion) }
    }

    var launchAtLogin: Bool {
        didSet {
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
        let primary = defaults.string(forKey: Key.primaryLanguage)
            .flatMap(PrimaryLanguage.init(rawValue:))
            ?? (defaults.object(forKey: Key.hasCompletedOnboarding) != nil
                ? .polish
                : (systemLanguages.first?.hasPrefix("pl") == true ? .polish : .english))
        defaults.set(primary.rawValue, forKey: Key.primaryLanguage)
        self.primaryLanguage = primary
        let storedSecond = defaults.string(forKey: Key.secondLanguage)
        let second: SecondLanguage? = storedSecond == Self.autoSecond
            ? nil
            : storedSecond.flatMap(SecondLanguage.init(rawValue:)) ?? primary.counterpart.asSecond
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
    }

    func refreshLaunchAtLogin() {
        let actual = loginItem.isEnabled
        if launchAtLogin != actual { launchAtLogin = actual }
    }
}
