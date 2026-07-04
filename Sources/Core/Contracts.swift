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

/// What the model should do with the selection, user-selectable in the popup's
/// verb strip (issue #23). `translate` is the default — the gesture's original
/// meaning; the rest re-run over the same captured text. Each verb is just a
/// different prompt (see `PromptBuilder.build`); the streaming/popup stack is
/// shared. (Unrelated to `LLMClient.explain(word:)`, which explains one word of a
/// finished translation for issue #39's per-word dropdown.)
enum Action: String, CaseIterable, Sendable {
    // Case order is load-bearing: Action.allCases drives both the palette strip
    // order (PopupView) and the background prefetch priority (AppCoordinator).
    // Translate stays first (the default after a double Cmd+C); the rest follow
    // the prefetch order fix → reply → summarize.
    case translate
    case fixGrammar
    // Unlike the others, Reply doesn't transform the selection — it generates a
    // reply to it, returning several drafts to pick from (issue #60). It rides the
    // same capture→LLM→popup pipeline but takes the non-streaming list path
    // (LLMClient.reply), not run().
    case reply
    case summarize

    /// Polish label for the verb strip pill.
    var displayName: String {
        switch self {
        case .translate: "Tłumacz"
        case .summarize: "Streść"
        case .fixGrammar: "Popraw"
        case .reply: "Odpowiedz"
        }
    }

    /// SF Symbol shown alongside the label in the pill. Summarize uses a list glyph
    /// (its output is a bulleted list) — kept clear of the Replace button's
    /// `text.insert`, which a `text.*` glyph would read too close to.
    var systemImage: String {
        switch self {
        case .translate: "character.book.closed"
        case .summarize: "list.bullet"
        case .fixGrammar: "checkmark.circle"
        case .reply: "arrowshape.turn.up.left"
        }
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
    case engineUnavailable

    var userMessage: String {
        switch self {
        case .ollamaUnreachable:
            "Nie mogę połączyć się z Ollamą (localhost:11434). Sprawdź, czy działa."
        case .engineUnavailable:
            "Brak silnika tłumaczenia. Pobierz go w Ustawieniach Glosso."
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
    /// Runs `action` over `text` and streams the result into the popup, exactly
    /// like the original translate path (issue #23). `humanize` only affects the
    /// `.translate` action — it folds a "natural human writing" directive into the
    /// prompt (default-on, toggled in Settings); the other verbs ignore it.
    /// `style` is its `.fixGrammar` twin: a moderate style pass (flow, word order
    /// and word choice within sentences, never merging/splitting them) folded into
    /// the correction prompt; the other verbs ignore it. Toggled by the popup's
    /// style pill and honored by the headless fix-in-place chord alike.
    func run(_ text: String, action: Action, model: String, second: SecondLanguage, formality: Formality, humanize: Bool, style: Bool) -> AsyncThrowingStream<TranslationEvent, Error>
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
    /// A single short Polish sentence naming why the learner's text was corrected
    /// from `error` to `correction` (issue #51) — the grammar, spelling or
    /// punctuation rule behind the fix ("brak rodzajnika", "zła forma czasu
    /// przeszłego"). Non-streaming like `explain`; the full original and corrected
    /// texts give context. `error` or `correction` may be empty (a pure insertion
    /// or deletion). `englishRules` picks the rule base grounding the explanation:
    /// the English-grammar cards (for an English text corrected under an English
    /// second language) instead of the default Polish RJP/style cards — decided by
    /// the caller, which detects the corrected text's language.
    func explainFix(error: String, correction: String, original: String, corrected: String, second: SecondLanguage, englishRules: Bool, model: String) async throws -> String
    /// Generates several distinct reply drafts to `text` (issue #60) — a reply, not
    /// a transformation, so there's no single "right" answer and the popup offers a
    /// few to choose from. Replies in the language `text` is written in. Non-streaming
    /// like `alternatives` (all drafts arrive together); parsed by `ReplyParser`.
    func reply(to text: String, model: String) async throws -> [String]
}

/// Lists the models actually installed in Ollama, so Settings can offer a live
/// picker instead of a hardcoded name.
protocol ModelListing: Sendable {
    func availableModels() async throws -> [String]
}

/// Resolves the base `/api/generate` URL of the active Ollama engine: the user's
/// own daemon on 11434 when reachable, otherwise a private `ollama serve` that
/// Glosso spawns on a free port (from an installed Ollama.app or a downloaded
/// engine). `ensureEngine` forces provisioning — downloading the ~177 MB engine
/// when none is present — for the explicit "download engine" action in Settings,
/// reporting download progress (0…1). `activeBaseURL` never downloads on its own:
/// it throws `TranslationError.engineUnavailable` when only a download would help,
/// so a translation surfaces an actionable message instead of a silent 177 MB pull.
protocol EngineProviding: Sendable {
    func activeBaseURL() async throws -> URL
    func ensureEngine(progress: @escaping @Sendable (Double) -> Void) async throws
    /// Non-spawning, non-downloading probe for the Settings UI: whether an engine
    /// is already usable (`ready`), spawnable from a local binary without a
    /// download (`installable`), or only obtainable by downloading (`needsDownload`).
    func status() async -> EngineStatus
}

enum EngineStatus: Sendable, Equatable {
    case ready          // the user's Ollama is up, or we already spawned one
    case installable    // a local binary exists (installed Ollama.app or a prior download)
    case needsDownload  // nothing local — only `ensureEngine` (a 177 MB pull) helps
}

/// Progress of a `POST /api/pull` model download — one Ollama status line
/// (`completed`/`total` are bytes of the current layer, 0 until known).
struct PullProgress: Sendable, Equatable {
    var status: String
    var completed: Int64
    var total: Int64
}

/// Pulls (`POST /api/pull`, streaming progress) and deletes (`DELETE /api/delete`)
/// models on the active engine, backing the Settings model catalog's
/// Download/Delete affordances.
protocol ModelManaging: Sendable {
    func pull(_ model: String) -> AsyncThrowingStream<PullProgress, Error>
    func delete(_ model: String) async throws
}

/// Controls whether the app launches at login. `isEnabled` reflects the *actual*
/// system registration (the user can revoke it in System Settings), so Settings
/// derives its toggle from it rather than from a mirrored UserDefaults flag.
@MainActor
protocol LoginItemManaging {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

protocol DoubleKeyDetecting: Sendable {
    mutating func registerCopy(at now: TimeInterval) -> Bool
    mutating func reset()
}

/// A user-configurable headless shortcut (issue #21): a base character plus the
/// Command/Control/Option/Shift modifiers it must be held with. `modifiers` is an
/// `NSEvent.ModifierFlags.rawValue` masked to that chord set, kept as a plain UInt
/// so this stays a pure value type with no AppKit dependency.
struct KeyChord: Codable, Equatable, Sendable {
    var key: String
    var modifiers: UInt

    /// Command + Control, the modifier pair both default action chords use.
    static let cmdCtrl: UInt = 0x100000 | 0x40000 // .command | .control rawValues
    static let fixGrammarDefault = KeyChord(key: "g", modifiers: cmdCtrl)
    static let translateInPlaceDefault = KeyChord(key: "t", modifiers: cmdCtrl)

    func matches(key: String, modifiers: UInt) -> Bool {
        self.key == key.lowercased() && self.modifiers == modifiers
    }
}

@MainActor
protocol HotkeyMonitor: AnyObject {
    /// Fires on a double Cmd+C, carrying the pasteboard `changeCount` sampled at
    /// the *first* press of the pair — a baseline that always precedes the
    /// second copy even when the foreground app copies synchronously.
    var onDoubleCopy: (@MainActor (_ baselineChangeCount: Int) -> Void)? { get set }
    /// Fires on the configurable headless "fix grammar in place" chord (default
    /// Ctrl+Cmd+G, issue #21/#46) — distinct from the double Cmd+C translate trigger.
    var onFixGrammar: (@MainActor () -> Void)? { get set }
    /// Fires on the configurable headless "translate in place" chord (default
    /// Ctrl+Cmd+T, issue #21): translate the selection and paste it back, no popup.
    var onTranslateInPlace: (@MainActor () -> Void)? { get set }
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
    /// Fires when the user toggles the fixGrammar style pill (grammar-only vs
    /// grammar+style), so the coordinator can persist it and re-run the correction.
    var onSelectStyle: (@MainActor (Bool) -> Void)? { get set }
    /// Fires when the user picks a verb in the palette strip (issue #23), so the
    /// coordinator can re-run that action over the same captured selection.
    var onSelectAction: (@MainActor (Action) -> Void)? { get set }
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
    /// Fires when the user taps a grammar-diff change in a `fixGrammar` result,
    /// asking the coordinator for a one-sentence Polish reason for that correction
    /// (issue #51). Carries the struck error text, its correction and the full
    /// corrected text; the coordinator fills in the original source and second
    /// language. Returns an empty string on any failure, shown as a fallback.
    var onFetchFixReason: (@MainActor (_ before: String, _ after: String, _ corrected: String) async -> String)? { get set }
    /// Fires when the user clicks Replace, carrying the finished translation so the
    /// coordinator can paste it over the source selection (issue #22).
    var onReplace: (@MainActor (_ translation: String) -> Void)? { get set }
    /// Fires when the user edits the source text and asks to translate it again
    /// (issue #44), carrying the edited source. The coordinator re-runs over it with
    /// the same point and action, exactly like the formality/verb re-run path.
    var onRetranslate: (@MainActor (_ source: String) -> Void)? { get set }
    /// Fires when the user undoes a picked-alternative reword (issue #25). The
    /// coordinator's per-action cache holds the reworded text under `.translate`,
    /// which the undo discards — so it must drop that entry, or a later verb
    /// round-trip back to Translate would replay the undone reword.
    var onUndo: (@MainActor () -> Void)? { get set }
    func present(at screenPoint: CGPoint, formality: Formality, style: Bool)
    func update(direction: TranslationDirection, sourceText: String, action: Action)
    func append(token: String)
    func showError(_ message: String)
    func finish(truncated: Bool)
    /// Shows the generated reply drafts (issue #60) and moves to the done phase,
    /// selecting the first so the Copy button has something to copy immediately.
    func showReplies(_ drafts: [String])
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
    /// Fires the focused app's Cmd+C so the selection lands on the pasteboard —
    /// the headless fix-grammar fallback when AXSelectedText reads empty, e.g. in
    /// terminals and some web/Electron fields (issue #46). The caller polls the
    /// pasteboard for the copy and preserves the user's clipboard around it.
    func synthesizeCopy()
}
