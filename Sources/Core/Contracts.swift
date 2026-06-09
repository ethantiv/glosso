import Foundation
import CoreGraphics

/// The non-Polish side of the PL↔X translation pair, user-selectable in
/// Settings. Polish is the fixed axis; this is the "other" language a copied
/// selection is translated to (when the selection is Polish) or from.
enum SecondLanguage: String, CaseIterable, Sendable {
    case english = "en"
    case german = "de"
    case russian = "ru"
    case spanish = "es"
    case dutch = "nl"
    case french = "fr"

    /// Polish display name for the Settings picker.
    var displayName: String {
        switch self {
        case .english: "angielski"
        case .german: "niemiecki"
        case .russian: "rosyjski"
        case .spanish: "hiszpański"
        case .dutch: "niderlandzki"
        case .french: "francuski"
        }
    }

    /// English name the prompt instructs the model to translate Polish into.
    var englishName: String {
        switch self {
        case .english: "English"
        case .german: "German"
        case .russian: "Russian"
        case .spanish: "Spanish"
        case .dutch: "Dutch"
        case .french: "French"
        }
    }

    /// Two-letter code shown in the popup's direction arrow.
    var code: String {
        switch self {
        case .english: "EN"
        case .german: "DE"
        case .russian: "RU"
        case .spanish: "ES"
        case .dutch: "NL"
        case .french: "FR"
        }
    }
}

/// Tone the model should use for the translation, user-selectable in Settings.
/// `automatic` adds no directive (the source text's register is preserved);
/// `formal`/`informal` inject an explicit tone instruction that works for any
/// target language — switching pronouns where the language has a T–V split
/// (German Sie/du, French vous/tu, …) and the overall register everywhere else.
enum Formality: String, CaseIterable, Sendable {
    case automatic = "auto"
    case formal = "formal"
    case informal = "informal"

    /// Polish display name for the popup's tone pill.
    var displayName: String {
        switch self {
        case .automatic: "Automatyczny"
        case .formal: "Formalny"
        case .informal: "Nieformalny"
        }
    }

    /// The next mode in the cycle, so the popup's tone pill advances one step
    /// per click (Automatyczny → Formalny → Nieformalny → Automatyczny).
    var next: Formality {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

enum TranslationDirection: Sendable, Equatable {
    case fromPolish(SecondLanguage)   // PL → second language
    case toPolish(SecondLanguage)     // second language → PL
    case unknown

    var label: String {
        switch self {
        case .fromPolish(let second): "PL → \(second.code)"
        case .toPolish(let second): "\(second.code) → PL"
        case .unknown: "…"
        }
    }
}

enum TranslationEvent: Sendable, Equatable {
    case token(String)
    case finished(doneReason: String?)
}

enum TranslationError: Error, Sendable, Equatable {
    case ollamaUnreachable
    case httpStatus(Int)
    case ollamaError(String)
    case malformedStream
    case emptyInput
    case cancelled

    var userMessage: String {
        switch self {
        case .ollamaUnreachable:
            "Nie mogę połączyć się z Ollamą (localhost:11434). Sprawdź, czy działa."
        case .httpStatus(let code):
            "Ollama zwróciła błąd HTTP \(code)."
        case .ollamaError(let message):
            "Ollama zgłosiła błąd: \(message)"
        case .malformedStream:
            "Otrzymałem nieprawidłową odpowiedź z modelu."
        case .emptyInput:
            "Nic nie zaznaczono do tłumaczenia."
        case .cancelled:
            "Tłumaczenie przerwane."
        }
    }
}

enum CaptureError: Error, Sendable, Equatable {
    case nothingSelected
    case emptyOrNonText
}

struct LLMConfig: Sendable {
    var endpoint: URL
    var model: String
    var keepAlive: String
    var temperature: Double
    var think: Bool

    static let `default` = LLMConfig(
        endpoint: URL(string: "http://localhost:11434/api/generate")!,
        model: "gemma4:26b-mlx",
        keepAlive: "30m",
        temperature: 0,
        think: false
    )
}

protocol LLMClient: Sendable {
    func translate(_ text: String, model: String, second: SecondLanguage, formality: Formality) -> AsyncThrowingStream<TranslationEvent, Error>
    func prewarm(model: String) async throws
    /// Context-aware alternatives for a single word of the finished translation,
    /// for the popup's per-word dropdown (issue #17). Given the source text, the
    /// current full translation and the clicked word (in the target language),
    /// returns N distinct renderings of that word that fit the context.
    func alternatives(for word: String, in translation: String, source: String, second: SecondLanguage, model: String) async throws -> [String]
    /// Re-translates so the clicked word is rendered as `chosen`, adjusting only
    /// the surrounding clause for grammatical agreement and leaving the rest
    /// unchanged. Streams the revised translation exactly like `translate`, so the
    /// coordinator can feed it into the same popup pane.
    func reword(original: String, to chosen: String, in translation: String, source: String, second: SecondLanguage, formality: Formality, model: String) -> AsyncThrowingStream<TranslationEvent, Error>
    /// A single short Polish sentence explaining why the clicked word of the
    /// finished translation was rendered that way — its literal sense in context,
    /// the nuance separating it from alternatives, or the grammatical form — for
    /// the learner-facing "Dlaczego tak?" row in the per-word dropdown (issue #39).
    /// Non-streaming like `alternatives`; the source and full translation give context.
    func explain(word: String, in translation: String, source: String, second: SecondLanguage, model: String) async throws -> String
}

/// Lists the models actually installed in Ollama, so Settings can offer a live
/// picker instead of a hardcoded name.
protocol ModelListing: Sendable {
    func availableModels() async throws -> [String]
}

/// Controls whether the app launches at login. `isEnabled` reflects the *actual*
/// system registration (the user can revoke it in System Settings), so Settings
/// derives its toggle from it rather than from a mirrored UserDefaults flag.
@MainActor
protocol LoginItemManaging {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

protocol TimeSource: Sendable {
    func now() -> TimeInterval
}

protocol DoubleKeyDetecting: Sendable {
    mutating func registerCopy(at now: TimeInterval) -> Bool
    mutating func reset()
}

@MainActor
protocol HotkeyMonitor: AnyObject {
    /// Fires on a double Cmd+C, carrying the pasteboard `changeCount` sampled at
    /// the *first* press of the pair — a baseline that always precedes the
    /// second copy even when the foreground app copies synchronously.
    var onDoubleCopy: (@MainActor (_ baselineChangeCount: Int) -> Void)? { get set }
    func start() throws
    func stop()
}

@MainActor
protocol PasteboardReading {
    var currentChangeCount: Int { get }
    func readSelection(baselineChangeCount: Int) throws -> String
}

@MainActor
protocol AXSelectionReading {
    /// Reads the focused UI element's selected text directly via the
    /// Accessibility API, independent of the pasteboard. Returns nil when no
    /// focused element exposes selected text.
    func selectedText() -> String?
}

@MainActor
protocol TranslationPopupPresenting: AnyObject {
    var onDismiss: (@MainActor () -> Void)? { get set }
    /// Fires when the user cycles the tone pill, carrying the newly selected
    /// formality so the coordinator can persist it and re-translate.
    var onSelectFormality: (@MainActor (Formality) -> Void)? { get set }
    /// Fires when the user clicks a word in the finished translation, asking the
    /// coordinator for context-aware alternatives (issue #17). Carries the clicked
    /// word and the current full translation; the coordinator fills in the source
    /// and second language. Returns an empty array on any failure or no alternatives.
    var onFetchAlternatives: (@MainActor (_ word: String, _ translation: String) async -> [String])? { get set }
    /// Fires when the user picks an alternative for a clicked word, so the
    /// coordinator can re-translate the clause with that word in place. Carries the
    /// original word, the chosen alternative and the current full translation.
    var onPickAlternative: (@MainActor (_ original: String, _ chosen: String, _ translation: String) -> Void)? { get set }
    /// Fires when the user taps "Dlaczego tak?" for a clicked word, asking the
    /// coordinator for a one-sentence Polish explanation of that rendering (issue
    /// #39). Carries the clicked word and the current full translation; the
    /// coordinator fills in the source and second language. Returns an empty string
    /// on any failure, which the dropdown shows as a fallback message.
    var onFetchExplanation: (@MainActor (_ word: String, _ translation: String) async -> String)? { get set }
    /// Fires when the user clicks Replace, carrying the finished translation so the
    /// coordinator can paste it over the source selection (issue #22).
    var onReplace: (@MainActor (_ translation: String) -> Void)? { get set }
    func present(at screenPoint: CGPoint, formality: Formality)
    func update(direction: TranslationDirection, sourceText: String)
    func append(token: String)
    func showError(_ message: String)
    func finish(truncated: Bool)
    /// Resets the translation pane to its loading skeleton for a re-translation,
    /// keeping the window in place along with the source text, direction and the
    /// selected tone.
    func restartTranslation()
    func dismiss()
}

@MainActor
protocol AccessibilityAuthorizing {
    var isTrusted: Bool { get }
    func requestAccess(prompt: Bool)
    func openSystemSettings()
}

@MainActor
protocol SelectionReplacing {
    /// Pastes `text` over the current selection in the frontmost app via a
    /// synthesized Cmd+V, preserving and restoring the clipboard (issue #22).
    func replace(with text: String)
}
