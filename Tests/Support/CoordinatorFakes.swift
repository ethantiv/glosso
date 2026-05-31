import Foundation
import CoreGraphics
@testable import TranslatorMenuBar

struct FakeLLMClient: LLMClient {
    final class Recorder: @unchecked Sendable {
        var receivedText: String?
    }
    let recorder = Recorder()
    let events: [TranslationEvent]

    init(events: [TranslationEvent] = [.token("ok"), .finished(doneReason: "stop")]) {
        self.events = events
    }

    func translate(_ text: String) -> AsyncThrowingStream<TranslationEvent, Error> {
        recorder.receivedText = text
        let events = self.events
        return AsyncThrowingStream { continuation in
            for event in events { continuation.yield(event) }
            continuation.finish()
        }
    }

    func prewarm() async throws {}
}

@MainActor
final class FakePasteboardReader: PasteboardReading {
    var currentChangeCount: Int = 0
    /// Throw this many `.nothingSelected` before yielding `text`. nil = never ready.
    var readyAfterAttempts: Int?
    var text: String = "Cześć"
    private var attempts = 0

    func readSelection(baselineChangeCount: Int) throws -> String {
        defer { attempts += 1 }
        guard let readyAfter = readyAfterAttempts else { throw CaptureError.nothingSelected }
        if attempts >= readyAfter { return text }
        throw CaptureError.nothingSelected
    }
}

@MainActor
final class FakeEmptyPasteboardReader: PasteboardReading {
    var currentChangeCount: Int = 0
    func readSelection(baselineChangeCount: Int) throws -> String {
        throw CaptureError.emptyOrNonText
    }
}

@MainActor
final class FakePopup: TranslationPopupPresenting {
    var onDismiss: (@MainActor () -> Void)?
    private(set) var presented = false
    private(set) var dismissCount = 0
    private(set) var tokens: [String] = []
    private(set) var errorMessage: String?
    private(set) var finished = false

    func present(direction: TranslationDirection, at screenPoint: CGPoint) { presented = true }
    func append(token: String) { tokens.append(token) }
    func showError(_ message: String) { errorMessage = message }
    func finish() { finished = true }
    func dismiss() {
        guard presented else { return }
        presented = false
        dismissCount += 1
        onDismiss?()
    }
}

@MainActor
final class FakeHotkeyMonitor: HotkeyMonitor {
    var onDoubleCopy: (@MainActor () -> Void)?
    func start() throws {}
    func stop() {}
}

@MainActor
final class FakeAccessibility: AccessibilityAuthorizing {
    var isTrusted: Bool = true
    func requestAccess(prompt: Bool) {}
    func openSystemSettings() {}
}
