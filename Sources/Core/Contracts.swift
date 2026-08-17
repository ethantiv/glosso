import Foundation
import CoreGraphics

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

}

enum Action: String, CaseIterable, Sendable {
    case translate
    case fixGrammar
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
    case cancelled
    case engineUnavailable
    case cloudUnreachable
    case cloudError(String)
    case missingAPIKey
    case invalidAPIKey
    case rateLimited(TimeInterval?)
    case quotaExhausted
    /// The model refused this particular text on content-policy grounds. Unlike the
    /// other cloud errors, retrying or waiting cannot change the answer.
    case contentBlocked(String)

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
        case .cancelled:
            loc("Tłumaczenie przerwane.",
                "Translation cancelled.")
        // Neutral wording: both cloud engines throw these three, so neither may name Google.
        case .cloudUnreachable:
            loc("Nie mogę połączyć się z usługą w chmurze. Sprawdź połączenie z internetem.",
                "Can't connect to the cloud service. Check your internet connection.")
        case .cloudError(let message):
            loc("Usługa w chmurze zgłosiła błąd: \(message)",
                "The cloud service reported an error: \(message)")
        case .missingAPIKey:
            loc("Brak klucza API. Wpisz go w Ustawieniach Glosso.",
                "No API key. Enter it in Glosso Settings.")
        case .invalidAPIKey:
            loc("Klucz API jest nieprawidłowy. Sprawdź go w Ustawieniach Glosso.",
                "The API key is not valid. Check it in Glosso Settings.")
        case .rateLimited:
            loc("Przekroczono limit zapytań usługi w chmurze. Spróbuj za chwilę.",
                "The cloud service's rate limit was exceeded. Try again shortly.")
        case .quotaExhausted:
            loc("Wyczerpał się dzienny darmowy limit Google AI. Odnowi się jutro.",
                "The free Google AI daily quota is used up. It resets tomorrow.")
        case .contentBlocked:
            loc("Google AI odmówiło przetworzenia tego tekstu.",
                "Google AI refused to process this text.")
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

/// Which engine serves the prompts: the local Ollama, Gemma on the Gemini API, or Gemma on Ollama Cloud.
enum LLMProvider: String, CaseIterable, Sendable {
    case local
    case cloud
    case ollamaCloud

    var displayName: String {
        switch self {
        case .local: loc("Lokalnie", "On this Mac")
        case .cloud: loc("Google AI", "Google AI")
        case .ollamaCloud: "Ollama Cloud"
        }
    }
}

/// Transport seam under the prompt layer — what an engine must provide for PromptRunning.swift's shared methods.
protocol GenerationBackend: Sendable {
    func generate(prompt: String, model: String, timeout: TimeInterval?, numPredict: Int?) async throws -> String
    func streamGeneration(prompt: String, model: String) -> AsyncThrowingStream<TranslationEvent, Error>
    func prewarm(model: String) async throws
}

protocol LLMClient: Sendable {
    func run(_ text: String, action: Action, model: String, primary: PrimaryLanguage, second: SecondLanguage, formality: Formality, style: Bool) -> AsyncThrowingStream<TranslationEvent, Error>
    func prewarm(model: String) async throws
    func alternatives(for word: String, in translation: String, source: String, primary: PrimaryLanguage, second: SecondLanguage, model: String) async throws -> [String]
    func reword(original: String, to chosen: String, in translation: String, source: String, primary: PrimaryLanguage, second: SecondLanguage, formality: Formality, model: String) -> AsyncThrowingStream<TranslationEvent, Error>
    func explain(word: String, in translation: String, source: String, primary: PrimaryLanguage, second: SecondLanguage, model: String) async throws -> String
    func explainFix(error: String, correction: String, original: String, corrected: String, primary: PrimaryLanguage, second: SecondLanguage, englishRules: Bool, style: Bool, model: String) async throws -> String
    func explainRegister(previous: String, current: String, from: Formality, to: Formality, source: String, primary: PrimaryLanguage, second: SecondLanguage, model: String) async throws -> String
    func reply(to text: String, model: String) async throws -> [String]
    func translateBlock(html: String, into primary: PrimaryLanguage, model: String) async throws -> String
    /// Several blocks in one request, keyed back by the ids sent — the reader's answer to a per-minute request cap.
    func translateBlocks(_ blocks: [(id: Int, html: String)], into primary: PrimaryLanguage, model: String) async throws -> [Int: String]
    func readerSummary(of text: String, into primary: PrimaryLanguage, model: String) async throws -> String
    func askArticle(question: String, history: [(question: String, answer: String)], article: String, into primary: PrimaryLanguage, model: String) async throws -> String
    func articleQuestions(about article: String, into primary: PrimaryLanguage, model: String) async throws -> [String]
}

@MainActor
protocol ReaderPresenting: AnyObject {
    func show(_ url: URL)
}

protocol ModelListing: Sendable {
    func availableModels() async throws -> [String]
}

protocol EngineProviding: Sendable {
    func activeBaseURL() async throws -> URL
    func ensureEngine(progress: @escaping @Sendable (Double) -> Void) async throws
    func status() async -> EngineStatus
}

enum EngineStatus: Sendable, Equatable {
    case ready          // the user's Ollama is up, or we already spawned one
    case installable    // a local binary exists (installed Ollama.app or a prior download)
    case needsDownload  // nothing local — only `ensureEngine` (a 177 MB pull) helps
}

struct PullProgress: Sendable, Equatable {
    var status: String
    var completed: Int64
    var total: Int64
}

protocol ModelManaging: Sendable {
    func pull(_ model: String) -> AsyncThrowingStream<PullProgress, Error>
    func delete(_ model: String) async throws
}

@MainActor
protocol LoginItemManaging {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

protocol DoubleKeyDetecting: Sendable {
    mutating func registerCopy(at now: TimeInterval) -> Bool
    mutating func reset()
}

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
    var onDoubleCopy: (@MainActor (_ baselineChangeCount: Int) -> Void)? { get set }
    var onFixGrammar: (@MainActor () -> Void)? { get set }
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
    func selectedText() -> String?
}

@MainActor
protocol TranslationPopupPresenting: AnyObject {
    var onDismiss: (@MainActor () -> Void)? { get set }
    var onSelectFormality: (@MainActor (Formality) -> Void)? { get set }
    var onSelectAction: (@MainActor (Action) -> Void)? { get set }
    var onFetchAlternatives: (@MainActor (_ word: String, _ translation: String) async -> [String])? { get set }
    var onPickAlternative: (@MainActor (_ original: String, _ chosen: String, _ translation: String) -> Void)? { get set }
    var onFetchExplanation: (@MainActor (_ word: String, _ translation: String) async -> String)? { get set }
    var onFetchFixReason: (@MainActor (_ before: String, _ after: String, _ corrected: String) async -> String)? { get set }
    var onFetchToneNote: (@MainActor (_ previous: String, _ current: String, _ from: Formality, _ to: Formality) async -> String)? { get set }
    var onReplace: (@MainActor (_ translation: String) -> Void)? { get set }
    var onRetranslate: (@MainActor (_ source: String) -> Void)? { get set }
    var onUndo: (@MainActor () -> Void)? { get set }
    func present(at screenPoint: CGPoint, formality: Formality)
    func update(direction: TranslationDirection, sourceText: String, action: Action)
    func append(token: String)
    func showError(_ message: String)
    func finish(truncated: Bool)
    func showReplies(_ drafts: [String])
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
    func replace(with text: String)
    func synthesizeCopy()
}
