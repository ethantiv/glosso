import Foundation
import Synchronization

enum PrimaryLanguage: String, CaseIterable, Sendable {
    case polish = "pl"
    case english = "en"

    /// Endonym for pickers and menus — a language names itself.
    var displayName: String {
        switch self {
        case .polish: "Polski"
        case .english: "English"
        }
    }

    /// English name the prompts instruct the model with.
    var englishName: String {
        switch self {
        case .polish: "Polish"
        case .english: "English"
        }
    }

    /// Two-letter code shown in the popup's direction arrow.
    var code: String {
        switch self {
        case .polish: "PL"
        case .english: "EN"
        }
    }

    var counterpart: PrimaryLanguage {
        switch self {
        case .polish: .english
        case .english: .polish
        }
    }

    var asSecond: SecondLanguage {
        switch self {
        case .polish: .polish
        case .english: .english
        }
    }
}

enum L10n {
    @TaskLocal static var override: PrimaryLanguage?
    private static let box = Mutex(
        Locale.preferredLanguages.first?.hasPrefix("pl") == true ? PrimaryLanguage.polish : .english
    )
    static var current: PrimaryLanguage { override ?? box.withLock { $0 } }
}

/// Resolves a user-facing string in the app's current primary language.
func loc(_ pl: String, _ en: String) -> String {
    L10n.current == .polish ? pl : en
}
