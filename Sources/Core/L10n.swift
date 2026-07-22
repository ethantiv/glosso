import Foundation
import Synchronization

/// The app's primary language: the fixed side of the translation pair.
/// Persisted in `SettingsStore`. Also the type of the UI language in `L10n`,
/// which is seeded from the macOS language independently of the setting.
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

    /// The other of the PL/EN pair — the fallback second language when the
    /// automatic second detects the selection is already in the primary, and
    /// the target a conflicting second setting switches to.
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

/// Current UI language, readable off the main actor (error messages and
/// `Sendable` enum display names resolve outside it) — hence a Mutex, not
/// a `@MainActor` global. Seeded once from the macOS language (any non-Polish
/// system reads English) and fixed for the process lifetime — independent of
/// the `primaryLanguage` translation setting. `override` is a task-local for
/// tests: string assertions pin their language through it instead of relying
/// on the machine's language.
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
