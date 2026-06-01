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

    var modelName: String {
        didSet { defaults.set(modelName, forKey: Key.model) }
    }

    var secondLanguage: SecondLanguage {
        didSet { defaults.set(secondLanguage.rawValue, forKey: Key.secondLanguage) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.modelName = defaults.string(forKey: Key.model) ?? LLMConfig.default.model
        self.secondLanguage = defaults.string(forKey: Key.secondLanguage)
            .flatMap(SecondLanguage.init(rawValue:)) ?? .english
    }
}
