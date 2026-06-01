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

    /// Polish display name for the Settings picker.
    var displayName: String {
        switch self {
        case .english: "angielski"
        case .german: "niemiecki"
        case .russian: "rosyjski"
        case .spanish: "hiszpański"
        case .dutch: "niderlandzki"
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
    func translate(_ text: String, model: String, second: SecondLanguage) -> AsyncThrowingStream<TranslationEvent, Error>
    func prewarm(model: String) async throws
}

/// Lists the models actually installed in Ollama, so Settings can offer a live
/// picker instead of a hardcoded name.
protocol ModelListing: Sendable {
    func availableModels() async throws -> [String]
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
protocol TranslationPopupPresenting: AnyObject {
    var onDismiss: (@MainActor () -> Void)? { get set }
    func present(direction: TranslationDirection, at screenPoint: CGPoint)
    func append(token: String)
    func showError(_ message: String)
    func finish(truncated: Bool)
    func dismiss()
}

@MainActor
protocol AccessibilityAuthorizing {
    var isTrusted: Bool { get }
    func requestAccess(prompt: Bool)
    func openSystemSettings()
}
