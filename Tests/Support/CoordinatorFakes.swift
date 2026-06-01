import Foundation
import CoreGraphics
@testable import TranslatorMenuBar

/// A one-shot gate a test can use to suspend a producer mid-stream and release
/// it on demand, so cancellation/reassignment can be exercised while a stream is
/// genuinely in flight rather than already drained.
final class StreamGate: @unchecked Sendable {
    private let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    init() {
        var captured: AsyncStream<Void>.Continuation!
        stream = AsyncStream { captured = $0 }
        continuation = captured
    }

    func wait() async { for await _ in stream { break } }
    func release() { continuation.yield(()); continuation.finish() }
}

struct FakeLLMClient: LLMClient {
    final class Recorder: @unchecked Sendable {
        var receivedText: String?
        var receivedModel: String?
        var receivedSecond: SecondLanguage?
        var prewarmModel: String?
    }
    let recorder = Recorder()
    let events: [TranslationEvent]
    let error: TranslationError?
    /// When set, the stream yields the first event, then suspends on the gate
    /// until the test releases it before yielding the rest — so a test can cancel
    /// or supersede the capture while the stream is still mid-flight.
    let gate: StreamGate?

    init(
        events: [TranslationEvent] = [.token("ok"), .finished(doneReason: "stop")],
        error: TranslationError? = nil,
        gate: StreamGate? = nil
    ) {
        self.events = events
        self.error = error
        self.gate = gate
    }

    func translate(_ text: String, model: String, second: SecondLanguage) -> AsyncThrowingStream<TranslationEvent, Error> {
        recorder.receivedText = text
        recorder.receivedModel = model
        recorder.receivedSecond = second
        let events = self.events
        let error = self.error
        let gate = self.gate
        return AsyncThrowingStream { continuation in
            guard let gate else {
                for event in events { continuation.yield(event) }
                if let error { continuation.finish(throwing: error) } else { continuation.finish() }
                return
            }
            let task = Task {
                var pending: StreamGate? = gate
                for event in events {
                    continuation.yield(event)
                    if let pending { await pending.wait() }
                    pending = nil
                }
                if let error { continuation.finish(throwing: error) } else { continuation.finish() }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func prewarm(model: String) async throws { recorder.prewarmModel = model }
}

@MainActor
final class FakePasteboardReader: PasteboardReading {
    var currentChangeCount: Int = 0
    /// Throw this many `.nothingSelected` before the copy "lands". nil = never lands.
    var readyAfterAttempts: Int?
    /// The change count a landed copy reports. readSelection only returns text
    /// once it rises strictly above the passed baseline, mirroring SelectionGuard,
    /// so the coordinator's baseline handshake is actually exercised here.
    var landedChangeCount: Int = 1
    var text: String = "Cześć"
    private var attempts = 0

    func readSelection(baselineChangeCount: Int) throws -> String {
        defer { attempts += 1 }
        guard let readyAfter = readyAfterAttempts, attempts >= readyAfter else {
            throw CaptureError.nothingSelected
        }
        currentChangeCount = landedChangeCount
        guard currentChangeCount > baselineChangeCount else { throw CaptureError.nothingSelected }
        return text
    }
}

@MainActor
final class FakeAXSelectionReader: AXSelectionReading {
    var text: String?
    private(set) var callCount = 0
    func selectedText() -> String? { callCount += 1; return text }
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
    private(set) var presentedDirection: TranslationDirection?
    private(set) var presentedSourceText: String?
    private(set) var dismissCount = 0
    private(set) var tokens: [String] = []
    private(set) var errorMessage: String?
    private(set) var finished = false
    private(set) var truncated = false

    func present(at screenPoint: CGPoint) {
        presented = true
    }
    func update(direction: TranslationDirection, sourceText: String) {
        presentedDirection = direction
        presentedSourceText = sourceText
    }
    func append(token: String) { tokens.append(token) }
    func showError(_ message: String) { errorMessage = message }
    func finish(truncated: Bool) { finished = true; self.truncated = truncated }
    func dismiss() {
        guard presented else { return }
        presented = false
        dismissCount += 1
        onDismiss?()
    }
}

@MainActor
final class FakeAccessibilityAuthorizing: AccessibilityAuthorizing {
    var isTrusted: Bool
    private(set) var requestedPrompt: Bool?
    private(set) var openedSettings = false

    init(isTrusted: Bool) { self.isTrusted = isTrusted }

    func requestAccess(prompt: Bool) { requestedPrompt = prompt }
    func openSystemSettings() { openedSettings = true }
}

@MainActor
final class FakeHotkeyMonitor: HotkeyMonitor {
    var onDoubleCopy: (@MainActor (Int) -> Void)?
    private(set) var stopCount = 0
    /// When set, `start()` throws it — so a test can assert the coordinator
    /// surfaces a failed monitor start as `start() == false`.
    var startError: (any Error)?
    func start() throws { if let startError { throw startError } }
    func stop() { stopCount += 1 }
}
