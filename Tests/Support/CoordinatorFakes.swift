import Foundation
import CoreGraphics
@testable import Glosso

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
        var receivedFormality: Formality?
        var receivedAction: Action?
        var receivedHumanize: Bool?
        var receivedStyle: Bool?
        // Call counts/order so cache + prefetch tests can assert the model is hit the
        // expected number of times (a cache hit must not re-run it).
        var runCount = 0
        var runActions: [Action] = []
        var replyCount = 0
        var prewarmModel: String?
        // alternatives(...)
        var altWord: String?
        var altTranslation: String?
        var altSource: String?
        var altSecond: SecondLanguage?
        var altModel: String?
        // explain(...)
        var explainWord: String?
        var explainTranslation: String?
        var explainSource: String?
        var explainSecond: SecondLanguage?
        var explainModel: String?
        // explainFix(...)
        var fixError: String?
        var fixCorrection: String?
        var fixOriginal: String?
        var fixCorrected: String?
        var fixSecond: SecondLanguage?
        var fixEnglishRules: Bool?
        var fixModel: String?
        // reply(...)
        var replyText: String?
        var replyModel: String?
        // reword(...)
        var rewordOriginal: String?
        var rewordChosen: String?
        var rewordTranslation: String?
        var rewordSource: String?
        var rewordSecond: SecondLanguage?
        var rewordFormality: Formality?
        var rewordModel: String?
    }
    let recorder = Recorder()
    let events: [TranslationEvent]
    let error: TranslationError?
    /// When set, the stream yields the first event, then suspends on the gate
    /// until the test releases it before yielding the rest — so a test can cancel
    /// or supersede the capture while the stream is still mid-flight.
    let gate: StreamGate?
    let alternativesResult: [String]
    let alternativesError: TranslationError?
    let replyResult: [String]
    let replyError: TranslationError?
    let explanationResult: String
    let explanationError: TranslationError?
    let fixReasonResult: String
    let fixReasonError: TranslationError?

    init(
        events: [TranslationEvent] = [.token("ok"), .finished(doneReason: "stop")],
        error: TranslationError? = nil,
        gate: StreamGate? = nil,
        alternatives: [String] = ["alt-one", "alt-two"],
        alternativesError: TranslationError? = nil,
        explanation: String = "bo tak każe gramatyka",
        explanationError: TranslationError? = nil,
        fixReason: String = "zła forma czasu przeszłego",
        fixReasonError: TranslationError? = nil,
        reply: [String] = ["draft-one", "draft-two", "draft-three"],
        replyError: TranslationError? = nil
    ) {
        self.events = events
        self.error = error
        self.gate = gate
        self.alternativesResult = alternatives
        self.alternativesError = alternativesError
        self.explanationResult = explanation
        self.explanationError = explanationError
        self.fixReasonResult = fixReason
        self.fixReasonError = fixReasonError
        self.replyResult = reply
        self.replyError = replyError
    }

    func run(_ text: String, action: Action, model: String, second: SecondLanguage, formality: Formality, humanize: Bool, style: Bool) -> AsyncThrowingStream<TranslationEvent, Error> {
        recorder.receivedText = text
        recorder.receivedModel = model
        recorder.receivedSecond = second
        recorder.receivedFormality = formality
        recorder.receivedAction = action
        recorder.receivedHumanize = humanize
        recorder.receivedStyle = style
        recorder.runCount += 1
        recorder.runActions.append(action)
        return makeStream()
    }

    func reword(original: String, to chosen: String, in translation: String, source: String, second: SecondLanguage, formality: Formality, model: String) -> AsyncThrowingStream<TranslationEvent, Error> {
        recorder.rewordOriginal = original
        recorder.rewordChosen = chosen
        recorder.rewordTranslation = translation
        recorder.rewordSource = source
        recorder.rewordSecond = second
        recorder.rewordFormality = formality
        recorder.rewordModel = model
        return makeStream()
    }

    func alternatives(for word: String, in translation: String, source: String, second: SecondLanguage, model: String) async throws -> [String] {
        recorder.altWord = word
        recorder.altTranslation = translation
        recorder.altSource = source
        recorder.altSecond = second
        recorder.altModel = model
        if let alternativesError { throw alternativesError }
        return alternativesResult
    }

    func reply(to text: String, model: String) async throws -> [String] {
        recorder.replyText = text
        recorder.replyModel = model
        recorder.replyCount += 1
        if let replyError { throw replyError }
        return replyResult
    }

    func explain(word: String, in translation: String, source: String, second: SecondLanguage, model: String) async throws -> String {
        recorder.explainWord = word
        recorder.explainTranslation = translation
        recorder.explainSource = source
        recorder.explainSecond = second
        recorder.explainModel = model
        if let explanationError { throw explanationError }
        return explanationResult
    }

    func explainFix(error: String, correction: String, original: String, corrected: String, second: SecondLanguage, englishRules: Bool, model: String) async throws -> String {
        recorder.fixError = error
        recorder.fixCorrection = correction
        recorder.fixOriginal = original
        recorder.fixCorrected = corrected
        recorder.fixSecond = second
        recorder.fixEnglishRules = englishRules
        recorder.fixModel = model
        if let fixReasonError { throw fixReasonError }
        return fixReasonResult
    }

    private func makeStream() -> AsyncThrowingStream<TranslationEvent, Error> {
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
    /// When non-empty, successive selectedText() calls return these in order so a
    /// test can model a selection that collapses between the capture read and the
    /// pre-paste re-check; falls back to `text` once drained.
    var texts: [String?] = []
    private(set) var callCount = 0
    func selectedText() -> String? {
        callCount += 1
        return texts.isEmpty ? text : texts.removeFirst()
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
    var onSelectFormality: (@MainActor (Formality) -> Void)?
    var onSelectStyle: (@MainActor (Bool) -> Void)?
    var onSelectAction: (@MainActor (Action) -> Void)?
    var onFetchAlternatives: (@MainActor (_ word: String, _ translation: String) async -> [String])?
    var onPickAlternative: (@MainActor (_ original: String, _ chosen: String, _ translation: String) -> Void)?
    var onFetchExplanation: (@MainActor (_ word: String, _ translation: String) async -> String)?
    var onFetchFixReason: (@MainActor (_ before: String, _ after: String, _ corrected: String) async -> String)?
    var onReplace: (@MainActor (_ translation: String) -> Void)?
    var onRetranslate: (@MainActor (_ source: String) -> Void)?
    var onUndo: (@MainActor () -> Void)?
    private(set) var presented = false
    private(set) var presentedDirection: TranslationDirection?
    private(set) var presentedSourceText: String?
    private(set) var presentedAction: Action?
    private(set) var presentedFormality: Formality?
    private(set) var presentedStyle: Bool?
    private(set) var dismissCount = 0
    private(set) var restartCount = 0
    private(set) var tokens: [String] = []
    private(set) var errorMessage: String?
    private(set) var finished = false
    private(set) var truncated = false
    private(set) var shownReplies: [String]?

    func present(at screenPoint: CGPoint, formality: Formality, style: Bool) {
        presented = true
        presentedFormality = formality
        presentedStyle = style
    }
    func update(direction: TranslationDirection, sourceText: String, action: Action) {
        presentedDirection = direction
        presentedSourceText = sourceText
        presentedAction = action
    }
    func append(token: String) { tokens.append(token) }
    func showError(_ message: String) { errorMessage = message }
    func finish(truncated: Bool) { finished = true; self.truncated = truncated }
    func showReplies(_ drafts: [String]) { shownReplies = drafts }
    func restartTranslation() {
        restartCount += 1
        tokens.removeAll()
        errorMessage = nil
        finished = false
        truncated = false
        shownReplies = nil
    }
    func dismiss() {
        guard presented else { return }
        presented = false
        dismissCount += 1
        onDismiss?()
    }
}

@MainActor
final class FakeSelectionReplacer: SelectionReplacing {
    private(set) var replacedText: String?
    private(set) var copyCount = 0
    func replace(with text: String) { replacedText = text }
    func synthesizeCopy() { copyCount += 1 }
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
    var onFixGrammar: (@MainActor () -> Void)?
    var onTranslateInPlace: (@MainActor () -> Void)?
    private(set) var stopCount = 0
    /// When set, `start()` throws it — so a test can assert the coordinator
    /// surfaces a failed monitor start as `start() == false`.
    var startError: (any Error)?
    func start() throws { if let startError { throw startError } }
    func stop() { stopCount += 1 }
}
