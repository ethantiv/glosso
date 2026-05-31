import Foundation
import CoreGraphics

enum TranslationDirection: String, Sendable, Equatable {
    case plToEn
    case enToPl
    case unknown

    var label: String {
        switch self {
        case .plToEn: "PL → EN"
        case .enToPl: "EN → PL"
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
    func translate(_ text: String) -> AsyncThrowingStream<TranslationEvent, Error>
    func prewarm() async throws
}

protocol TimeSource: Sendable {
    func now() -> TimeInterval
}

protocol DoubleKeyDetecting: Sendable {
    mutating func registerCopy(at now: TimeInterval) -> Bool
}

@MainActor
protocol HotkeyMonitor: AnyObject {
    var onDoubleCopy: (@MainActor () -> Void)? { get set }
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
    func finish()
    func dismiss()
}

@MainActor
protocol AccessibilityAuthorizing {
    var isTrusted: Bool { get }
    func requestAccess(prompt: Bool)
    func openSystemSettings()
}
