import Foundation
import CoreGraphics

/// The non-primary side of the translation pair, user-selectable in Settings.
/// The primary language (`PrimaryLanguage`) is the fixed axis; this is the
/// "other" language a copied selection is translated to (when the selection is
/// in the primary language) or from. `.polish` is offered only when the primary
/// is English — the pair is never X↔X.
enum SecondLanguage: String, CaseIterable, Sendable {
    case english = "en"
    case german = "de"
    case russian = "ru"
    case spanish = "es"
    case dutch = "nl"
    case french = "fr"
    case polish = "pl"

    /// Display name for the Settings picker, in the app's UI language.
    var displayName: String {
        switch self {
        case .english: loc("angielski", "English")
        case .german: loc("niemiecki", "German")
        case .russian: loc("rosyjski", "Russian")
        case .spanish: loc("hiszpański", "Spanish")
        case .dutch: loc("niderlandzki", "Dutch")
        case .french: loc("francuski", "French")
        case .polish: loc("polski", "Polish")
        }
    }

    /// English name the prompt instructs the model to translate into.
    var englishName: String {
        switch self {
        case .english: "English"
        case .german: "German"
        case .russian: "Russian"
        case .spanish: "Spanish"
        case .dutch: "Dutch"
        case .french: "French"
        case .polish: "Polish"
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
        case .polish: "PL"
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

    /// Display name for the popup's tone pill, in the app's UI language.
    var displayName: String {
        switch self {
        case .automatic: loc("Automatyczny", "Automatic")
        case .formal: loc("Formalny", "Formal")
        case .informal: loc("Nieformalny", "Informal")
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

    /// Label for the verb strip pill, in the app's UI language.
    var displayName: String {
        switch self {
        case .translate: loc("Tłumacz", "Translate")
        case .summarize: loc("Streść", "Summarize")
        case .fixGrammar: loc("Popraw", "Fix")
        case .reply: loc("Odpowiedz", "Reply")
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
    case fromPrimary(PrimaryLanguage, SecondLanguage)   // primary → second language
    case toPrimary(PrimaryLanguage, SecondLanguage)     // second language → primary
    case unknown

    var label: String {
        switch self {
        case .fromPrimary(let primary, let second): "\(primary.code) → \(second.code)"
        case .toPrimary(let primary, let second): "\(second.code) → \(primary.code)"
        case .unknown: "…"
        }
    }

    /// Whether the fixGrammar style pass covers this text's language: Polish or
    /// English — the two rule bases that exist. The primary is always one of the
    /// two, so `fromPrimary` always qualifies; `toPrimary` only when the source
    /// side is Polish or English. `.unknown` (empty/ambiguous text) stays
    /// permissive. This is the gate for the automatic style pass, applied
    /// whenever the direction supports it.
    var supportsStyleFix: Bool {
        switch self {
        case .fromPrimary: true
        case .toPrimary(_, let second): second == .english || second == .polish
        case .unknown: true
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
            loc("Nie mogę połączyć się z Ollamą (localhost:11434). Sprawdź, czy działa.",
                "Can't connect to Ollama (localhost:11434). Check that it is running.")
        case .engineUnavailable:
            loc("Brak silnika tłumaczenia. Pobierz go w Ustawieniach Glosso.",
                "No translation engine. Download it in Glosso Settings.")
        case .httpStatus(let code):
            loc("Ollama zwróciła błąd HTTP \(code).",
                "Ollama returned HTTP error \(code).")
        case .ollamaError(let message):
            loc("Ollama zgłosiła błąd: \(message)",
                "Ollama reported an error: \(message)")
        case .malformedStream:
            loc("Otrzymałem nieprawidłową odpowiedź z modelu.",
                "Received a malformed response from the model.")
        case .emptyInput:
            loc("Nic nie zaznaczono do tłumaczenia.",
                "Nothing selected to translate.")
        case .cancelled:
            loc("Tłumaczenie przerwane.",
                "Translation cancelled.")
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
    /// like the original translate path (issue #23).
    /// `style` only affects `.fixGrammar`: a moderate style pass (flow, word order
    /// and word choice within sentences, never merging/splitting them) folded into
    /// the correction prompt; the other verbs ignore it. Applied automatically
    /// whenever the detected direction supports it, in the popup and the headless
    /// fix-in-place chord alike.
    func run(_ text: String, action: Action, model: String, primary: PrimaryLanguage, second: SecondLanguage, formality: Formality, style: Bool) -> AsyncThrowingStream<TranslationEvent, Error>
    func prewarm(model: String) async throws
    /// Context-aware alternatives for a single word of the finished translation,
    /// for the popup's per-word dropdown (issue #17). Given the source text, the
    /// current full translation and the clicked word (in the target language),
    /// returns N distinct renderings of that word that fit the context.
    func alternatives(for word: String, in translation: String, source: String, primary: PrimaryLanguage, second: SecondLanguage, model: String) async throws -> [String]
    /// Re-translates so the clicked word is rendered as `chosen`, adjusting only
    /// the surrounding clause for grammatical agreement and leaving the rest
    /// unchanged. Streams the revised translation exactly like `translate`, so the
    /// coordinator can feed it into the same popup pane.
    func reword(original: String, to chosen: String, in translation: String, source: String, primary: PrimaryLanguage, second: SecondLanguage, formality: Formality, model: String) -> AsyncThrowingStream<TranslationEvent, Error>
    /// A single short sentence, in the primary language, explaining why the clicked word of the
    /// finished translation was rendered that way — its literal sense in context,
    /// the nuance separating it from alternatives, or the grammatical form — for
    /// the learner-facing "Dlaczego tak?" row in the per-word dropdown (issue #39).
    /// Non-streaming like `alternatives`; the source and full translation give context.
    func explain(word: String, in translation: String, source: String, primary: PrimaryLanguage, second: SecondLanguage, model: String) async throws -> String
    /// A single short sentence, in the primary language, naming why the learner's text was corrected
    /// from `error` to `correction` (issue #51) — the grammar, spelling or
    /// punctuation rule behind the fix ("brak rodzajnika", "zła forma czasu
    /// przeszłego"). Non-streaming like `explain`; the full original and corrected
    /// texts give context. `error` or `correction` may be empty (a pure insertion
    /// or deletion). `englishRules` picks the rule base grounding the explanation:
    /// the English-grammar cards (for an English text corrected under an English
    /// second language) instead of the default Polish RJP cards — decided by
    /// the caller, which detects the corrected text's language. Both card sets are
    /// written in Polish for Polish learners, so grounding applies only when the
    /// primary language is Polish; under an English primary the explanation is a
    /// plain rule-naming sentence in English. `style` mirrors the
    /// correction that produced the diff: only a grammar+style run can produce
    /// style-driven changes, so only then do the Polish style cards join the base
    /// (a grammar-only correction grounded in style cards could cite a rule that
    /// cannot govern any of its changes).
    func explainFix(error: String, correction: String, original: String, corrected: String, primary: PrimaryLanguage, second: SecondLanguage, englishRules: Bool, style: Bool, model: String) async throws -> String
    /// A few short bullets, in the primary language, naming what the tone pill actually did to the
    /// translation (issue #53): which words, pronouns and verb forms shifted between
    /// the `from`-register rendering (`previous`) and the `to`-register one
    /// (`current`), and why — German Sie→du, French vous→tu, a dropped hedge.
    /// Non-streaming like `explain`; `source` gives the shared original for context.
    func explainRegister(previous: String, current: String, from: Formality, to: Formality, source: String, primary: PrimaryLanguage, second: SecondLanguage, model: String) async throws -> String
    /// Generates several distinct reply drafts to `text` (issue #60) — a reply, not
    /// a transformation, so there's no single "right" answer and the popup offers a
    /// few to choose from. Replies in the language `text` is written in. Non-streaming
    /// like `alternatives` (all drafts arrive together); parsed by `ReplyParser`.
    func reply(to text: String, model: String) async throws -> [String]
    /// Translates one HTML block of an extracted web article into the primary
    /// language, preserving its inline tags verbatim (the URL reader window). The
    /// target is unconditionally the primary — an article can be in any language,
    /// not just the primary↔second pair — so there is no `second:` parameter.
    /// Non-streaming like `alternatives`; an already-primary-language block comes
    /// back unchanged.
    func translateBlock(html: String, into primary: PrimaryLanguage, model: String) async throws -> String
    /// A 2–3 sentence prose summary of an extracted article, in the primary
    /// language, shown as the tl;dr under the reader window's title. Non-streaming
    /// like `translateBlock`; best-effort in the reader (a failure hides the
    /// section, never blocks the block translation).
    func readerSummary(of text: String, into primary: PrimaryLanguage, model: String) async throws -> String
    /// Answers the user's question about the reader window's article, in the
    /// primary language regardless of the article's or question's language
    /// ("Zapytaj artykuł"). Non-streaming like `readerSummary`; best-effort in
    /// the reader (a failure shows an error bubble, never touches the article).
    func askArticle(question: String, article: String, into primary: PrimaryLanguage, model: String) async throws -> String
    /// 3–5 suggested questions about the article, in the primary language, for
    /// the chat panel's clickable chips — generated lazily on first panel open.
    /// Non-streaming; one question per line, parsed by `AlternativesParser`.
    func articleQuestions(about article: String, into primary: PrimaryLanguage, model: String) async throws -> [String]
}

/// Opens the reader window for a copied article URL (double Cmd+C on a URL)
/// and drives its progressive block-by-block translation. One window: a new
/// `show` cancels the in-flight translation and reuses it.
@MainActor
protocol ReaderPresenting: AnyObject {
    func show(_ url: URL)
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
    /// Fires when the user asks what a tone change did ("Co się zmieniło?", issue
    /// #53), carrying the translation as it read under the previous register, the
    /// current one, and both registers; the coordinator fills in the source and
    /// second language. Returns an empty string on any failure, shown as a fallback.
    var onFetchToneNote: (@MainActor (_ previous: String, _ current: String, _ from: Formality, _ to: Formality) async -> String)? { get set }
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
    func present(at screenPoint: CGPoint, formality: Formality)
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
