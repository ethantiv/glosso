import Foundation
import Observation

/// User-editable, persisted translation settings: which Ollama model to use and
/// the non-Polish side of the PL↔X pair. Backed by UserDefaults; the SwiftUI
/// Settings view binds to it and AppCoordinator reads it at translate time.
@MainActor
@Observable
final class SettingsStore {
    private enum Key {
        static let model = "llm.model"
        static let secondLanguage = "translation.secondLanguage"
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let loginItem: any LoginItemManaging

    var modelName: String {
        didSet { defaults.set(modelName, forKey: Key.model) }
    }

    var secondLanguage: SecondLanguage {
        didSet { defaults.set(secondLanguage.rawValue, forKey: Key.secondLanguage) }
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

    init(defaults: UserDefaults = .standard, loginItem: any LoginItemManaging = SMAppServiceLoginItem()) {
        self.defaults = defaults
        self.loginItem = loginItem
        self.modelName = defaults.string(forKey: Key.model) ?? LLMConfig.default.model
        self.secondLanguage = defaults.string(forKey: Key.secondLanguage)
            .flatMap(SecondLanguage.init(rawValue:)) ?? .english
        self.launchAtLogin = loginItem.isEnabled
    }

    /// Re-reads the real registration status; the user may have toggled the login
    /// item in System Settings while the app was running.
    func refreshLaunchAtLogin() {
        let actual = loginItem.isEnabled
        if launchAtLogin != actual { launchAtLogin = actual }
    }
}
