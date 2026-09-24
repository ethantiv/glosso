import Foundation
import CoreGraphics
@testable import Glosso

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
        private let lock = NSLock()
        private struct State {
            var receivedText: String?
            var receivedModel: String?
            var receivedPrimary: PrimaryLanguage?
            var receivedSecond: SecondLanguage?
            var receivedFormality: Formality?
            var receivedAction: Action?
            var receivedStyle: Bool?
            var runCount = 0
            var runActions: [Action] = []
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
            var fixStyle: Bool?
            var fixModel: String?
            // explainRegister(...)
            var registerPrevious: String?
            var registerCurrent: String?
            var registerFrom: Formality?
            var registerTo: Formality?
            var registerSource: String?
            var registerSecond: SecondLanguage?
            var registerModel: String?
            // translateBlock(...)
            var blockHTMLs: [String] = []
            var blockPrimary: PrimaryLanguage?
            var blockModel: String?
            // translateBlocks(...) — one entry per batch, so a test can assert how the blocks were packed
            var batches: [[Int]] = []
            // readerSummary(...)
            var summaryText: String?
            var summaryPrimary: PrimaryLanguage?
            var summaryModel: String?
            // askArticle(...)
            var askQuestion: String?
            var askHistory: [(question: String, answer: String)]?
            var askArticleText: String?
            var askPrimary: PrimaryLanguage?
            var askModel: String?
            // articleQuestions(...)
            var questionsArticleText: String?
            var questionsPrimary: PrimaryLanguage?
            var questionsModel: String?
            // reword(...)
            var rewordOriginal: String?
            var rewordChosen: String?
            var rewordTranslation: String?
            var rewordSource: String?
            var rewordSecond: SecondLanguage?
            var rewordFormality: Formality?
            var rewordModel: String?
        }
        private var storage = State()
        var receivedText: String? {
            get { lock.withLock { storage.receivedText } }
            _modify { lock.lock(); defer { lock.unlock() }; yield &storage.receivedText }
        }
        var receivedModel: String? {
            get { lock.withLock { storage.receivedModel } }
            _modify { lock.lock(); defer { lock.unlock() }; yield &storage.receivedModel }
        }
        var receivedPrimary: PrimaryLanguage? {
            get { lock.withLock { storage.receivedPrimary } }
            _modify { lock.lock(); defer { lock.unlock() }; yield &storage.receivedPrimary }
        }
        var receivedSecond: SecondLanguage? {
            get { lock.withLock { storage.receivedSecond } }
            _modify { lock.lock(); defer { lock.unlock() }; yield &storage.receivedSecond }
        }
        var receivedFormality: Formality? {
            get { lock.withLock { storage.receivedFormality } }
            _modify { lock.lock(); defer { lock.unlock() }; yield &storage.receivedFormality }
        }
        var receivedAction: Action? {
            get { lock.withLock { storage.receivedAction } }
            _modify { lock.lock(); defer { lock.unlock() }; yield &storage.receivedAction }
        }
        var receivedStyle: Bool? {
            get { lock.withLock { storage.receivedStyle } }
            _modify { lock.lock(); defer { lock.unlock() }; yield &storage.receivedStyle }
        }
        var runCount: Int {
            get { lock.withLock { storage.runCount } }
            _modify { lock.lock(); defer { lock.unlock() }; yield &storage.runCount }
        }
        var runActions: [Action] {
            get { lock.withLock { storage.runActions } }
            _modify { lock.lock(); defer { lock.unlock() }; yield &storage.runActions }
        }
        var prewarmModel: String? {
            get { lock.withLock { storage.prewarmModel } }
            _modify { lock.lock(); defer { lock.unlock() }; yield &storage.prewarmModel }
        }
        var altWord: String? {
            get { lock.withLock { storage.altWord } }
            _modify { lock.lock(); defer { lock.unlock() }; yield &storage.altWord }
        }
        var altTranslation: String? {
            get { lock.withLock { storage.altTranslation } }
            _modify { lock.lock(); defer { lock.unlock() }; yield &storage.altTranslation }
        }
        var altSource: String? {
            get { lock.withLock { storage.altSource } }
            _modify { lock.lock(); defer { lock.unlock() }; yield &storage.altSource }
        }
        var altSecond: SecondLanguage? {
            get { lock.withLock { storage.altSecond } }
            _modify { lock.lock(); defer { lock.unlock() }; yield &storage.altSecond }
        }
        var altModel: String? {
            get { lock.withLock { storage.altModel } }
            _modify { lock.lock(); defer { lock.unlock() }; yield &storage.altModel }
        }
        var explainWord: String? {
            get { lock.withLock { storage.explainWord } }
            _modify { lock.lock(); defer { lock.unlock() }; yield &storage.explainWord }
        }
        var explainTranslation: String? {
            get { lock.withLock { storage.explainTranslation } }
            _modify { lock.lock(); defer { lock.unlock() }; yield &storage.explainTranslation }
        }
        var explainSource: String? {
            get { lock.withLock { storage.explainSource } }
            _modify { lock.lock(); defer { lock.unlock() }; yield &storage.explainSource }
        }
        var explainSecond: SecondLanguage? {
            get { lock.withLock { storage.explainSecond } }
            _modify { lock.lock(); defer { lock.unlock() }; yield &storage.explainSecond }
        }
        var explainModel: String? {
            get { lock.withLock { storage.explainModel } }
            _modify { lock.lock(); defer { lock.unlock() }; yield &storage.explainModel }
        }
        var fixError: String? {
            get { lock.withLock { storage.fixError } }
            _modify { lock.lock(); defer { lock.unlock() }; yield &storage.fixError }
        }
        var fixCorrection: String? {
            get { lock.withLock { storage.fixCorrection } }
            _modify { lock.lock(); defer { lock.unlock() }; yield &storage.fixCorrection }
        }
        var fixOriginal: String? {
            get { lock.withLock { storage.fixOriginal } }
            _modify { lock.lock(); defer { lock.unlock() }; yield &storage.fixOriginal }
        }
        var fixCorrected: String? {
            get { lock.withLock { storage.fixCorrected } }
            _modify { lock.lock(); defer { lock.unlock() }; yield &storage.fixCorrected }
        }
        var fixSecond: SecondLanguage? {
            get { lock.withLock { storage.fixSecond } }
            _modify { lock.lock(); defer { lock.unlock() }; yield &storage.fixSecond }
        }
        var fixEnglishRules: Bool? {
            get { lock.withLock { storage.fixEnglishRules } }
            _modify { lock.lock(); defer { lock.unlock() }; yield &storage.fixEnglishRules }
        }
        var fixStyle: Bool? {
            get { lock.withLock { storage.fixStyle } }
            _modify { lock.lock(); defer { lock.unlock() }; yield &storage.fixStyle }
        }
        var fixModel: String? {
            get { lock.withLock { storage.fixModel } }
            _modify { lock.lock(); defer { lock.unlock() }; yield &storage.fixModel }
        }
        var registerPrevious: String? {
            get { lock.withLock { storage.registerPrevious } }
            _modify { lock.lock(); defer { lock.unlock() }; yield &storage.registerPrevious }
        }
        var registerCurrent: String? {
            get { lock.withLock { storage.registerCurrent } }
            _modify { lock.lock(); defer { lock.unlock() }; yield &storage.registerCurrent }
        }
        var registerFrom: Formality? {
            get { lock.withLock { storage.registerFrom } }
            _modify { lock.lock(); defer { lock.unlock() }; yield &storage.registerFrom }
        }
        var registerTo: Formality? {
            get { lock.withLock { storage.registerTo } }
            _modify { lock.lock(); defer { lock.unlock() }; yield &storage.registerTo }
        }
        var registerSource: String? {
            get { lock.withLock { storage.registerSource } }
            _modify { lock.lock(); defer { lock.unlock() }; yield &storage.registerSource }
        }
        var registerSecond: SecondLanguage? {
            get { lock.withLock { storage.registerSecond } }
            _modify { lock.lock(); defer { lock.unlock() }; yield &storage.registerSecond }
        }
        var registerModel: String? {
            get { lock.withLock { storage.registerModel } }
            _modify { lock.lock(); defer { lock.unlock() }; yield &storage.registerModel }
        }
        var blockHTMLs: [String] {
            get { lock.withLock { storage.blockHTMLs } }
            _modify { lock.lock(); defer { lock.unlock() }; yield &storage.blockHTMLs }
        }
        var blockPrimary: PrimaryLanguage? {
            get { lock.withLock { storage.blockPrimary } }
            _modify { lock.lock(); defer { lock.unlock() }; yield &storage.blockPrimary }
        }
        var blockModel: String? {
            get { lock.withLock { storage.blockModel } }
            _modify { lock.lock(); defer { lock.unlock() }; yield &storage.blockModel }
        }
        var batches: [[Int]] {
            get { lock.withLock { storage.batches } }
            _modify { lock.lock(); defer { lock.unlock() }; yield &storage.batches }
        }
        var summaryText: String? {
            get { lock.withLock { storage.summaryText } }
            _modify { lock.lock(); defer { lock.unlock() }; yield &storage.summaryText }
        }
        var summaryPrimary: PrimaryLanguage? {
            get { lock.withLock { storage.summaryPrimary } }
            _modify { lock.lock(); defer { lock.unlock() }; yield &storage.summaryPrimary }
        }
        var summaryModel: String? {
            get { lock.withLock { storage.summaryModel } }
            _modify { lock.lock(); defer { lock.unlock() }; yield &storage.summaryModel }
        }
        var askQuestion: String? {
            get { lock.withLock { storage.askQuestion } }
            _modify { lock.lock(); defer { lock.unlock() }; yield &storage.askQuestion }
        }
        var askHistory: [(question: String, answer: String)]? {
            get { lock.withLock { storage.askHistory } }
            _modify { lock.lock(); defer { lock.unlock() }; yield &storage.askHistory }
        }
        var askArticleText: String? {
            get { lock.withLock { storage.askArticleText } }
            _modify { lock.lock(); defer { lock.unlock() }; yield &storage.askArticleText }
        }
        var askPrimary: PrimaryLanguage? {
            get { lock.withLock { storage.askPrimary } }
            _modify { lock.lock(); defer { lock.unlock() }; yield &storage.askPrimary }
        }
        var askModel: String? {
            get { lock.withLock { storage.askModel } }
            _modify { lock.lock(); defer { lock.unlock() }; yield &storage.askModel }
        }
        var questionsArticleText: String? {
            get { lock.withLock { storage.questionsArticleText } }
            _modify { lock.lock(); defer { lock.unlock() }; yield &storage.questionsArticleText }
        }
        var questionsPrimary: PrimaryLanguage? {
            get { lock.withLock { storage.questionsPrimary } }
            _modify { lock.lock(); defer { lock.unlock() }; yield &storage.questionsPrimary }
        }
        var questionsModel: String? {
            get { lock.withLock { storage.questionsModel } }
            _modify { lock.lock(); defer { lock.unlock() }; yield &storage.questionsModel }
        }
        var rewordOriginal: String? {
            get { lock.withLock { storage.rewordOriginal } }
            _modify { lock.lock(); defer { lock.unlock() }; yield &storage.rewordOriginal }
        }
        var rewordChosen: String? {
            get { lock.withLock { storage.rewordChosen } }
            _modify { lock.lock(); defer { lock.unlock() }; yield &storage.rewordChosen }
        }
        var rewordTranslation: String? {
            get { lock.withLock { storage.rewordTranslation } }
            _modify { lock.lock(); defer { lock.unlock() }; yield &storage.rewordTranslation }
        }
        var rewordSource: String? {
            get { lock.withLock { storage.rewordSource } }
            _modify { lock.lock(); defer { lock.unlock() }; yield &storage.rewordSource }
        }
        var rewordSecond: SecondLanguage? {
            get { lock.withLock { storage.rewordSecond } }
            _modify { lock.lock(); defer { lock.unlock() }; yield &storage.rewordSecond }
        }
        var rewordFormality: Formality? {
            get { lock.withLock { storage.rewordFormality } }
            _modify { lock.lock(); defer { lock.unlock() }; yield &storage.rewordFormality }
        }
        var rewordModel: String? {
            get { lock.withLock { storage.rewordModel } }
            _modify { lock.lock(); defer { lock.unlock() }; yield &storage.rewordModel }
        }

    }
    let recorder = Recorder()
    let events: [TranslationEvent]
    let error: TranslationError?
    let gate: StreamGate?
    let streamStarted = StreamGate()
    let alternativesResult: [String]
    let alternativesError: TranslationError?
    let blockResult: String
    let blockError: TranslationError?
    let summaryResult: String
    let summaryError: TranslationError?
    let askResult: String
    let askError: TranslationError?
    let questionsResult: [String]
    let questionsError: TranslationError?
    let explanationResult: String
    let explanationError: TranslationError?
    let fixReasonResult: String
    let fixReasonError: TranslationError?
    let toneNoteResult: String
    let toneNoteError: TranslationError?

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
        toneNote: String = "- Sie → du: zwrot nieformalny",
        toneNoteError: TranslationError? = nil,
        blockResult: String = "<b>PL</b>",
        blockError: TranslationError? = nil,
        summaryResult: String = "Krótkie streszczenie artykułu.",
        summaryError: TranslationError? = nil,
        askResult: String = "Odpowiedź z artykułu.",
        askError: TranslationError? = nil,
        questionsResult: [String] = ["Pytanie 1?", "Pytanie 2?", "Pytanie 3?"],
        questionsError: TranslationError? = nil
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
        self.toneNoteResult = toneNote
        self.toneNoteError = toneNoteError
        self.blockResult = blockResult
        self.blockError = blockError
        self.summaryResult = summaryResult
        self.summaryError = summaryError
        self.askResult = askResult
        self.askError = askError
        self.questionsResult = questionsResult
        self.questionsError = questionsError
    }

    func run(_ text: String, action: Action, model: String, primary: PrimaryLanguage, second: SecondLanguage, formality: Formality, style: Bool) -> AsyncThrowingStream<TranslationEvent, Error> {
        recorder.receivedText = text
        recorder.receivedModel = model
        recorder.receivedPrimary = primary
        recorder.receivedSecond = second
        recorder.receivedFormality = formality
        recorder.receivedAction = action
        recorder.receivedStyle = style
        recorder.runCount += 1
        recorder.runActions.append(action)
        return makeStream()
    }

    func reword(original: String, to chosen: String, in translation: String, source: String, primary: PrimaryLanguage, second: SecondLanguage, formality: Formality, model: String) -> AsyncThrowingStream<TranslationEvent, Error> {
        recorder.rewordOriginal = original
        recorder.rewordChosen = chosen
        recorder.rewordTranslation = translation
        recorder.rewordSource = source
        recorder.rewordSecond = second
        recorder.rewordFormality = formality
        recorder.rewordModel = model
        return makeStream()
    }

    func alternatives(for word: String, in translation: String, source: String, primary: PrimaryLanguage, second: SecondLanguage, model: String) async throws -> [String] {
        recorder.altWord = word
        recorder.altTranslation = translation
        recorder.altSource = source
        recorder.altSecond = second
        recorder.altModel = model
        if let alternativesError { throw alternativesError }
        return alternativesResult
    }

    func explain(word: String, in translation: String, source: String, primary: PrimaryLanguage, second: SecondLanguage, model: String) async throws -> String {
        recorder.explainWord = word
        recorder.explainTranslation = translation
        recorder.explainSource = source
        recorder.explainSecond = second
        recorder.explainModel = model
        if let explanationError { throw explanationError }
        return explanationResult
    }

    func explainFix(error: String, correction: String, original: String, corrected: String, primary: PrimaryLanguage, second: SecondLanguage, englishRules: Bool, style: Bool, model: String) async throws -> String {
        recorder.fixError = error
        recorder.fixCorrection = correction
        recorder.fixOriginal = original
        recorder.fixCorrected = corrected
        recorder.fixSecond = second
        recorder.fixEnglishRules = englishRules
        recorder.fixStyle = style
        recorder.fixModel = model
        if let fixReasonError { throw fixReasonError }
        return fixReasonResult
    }

    func explainRegister(previous: String, current: String, from: Formality, to: Formality, source: String, primary: PrimaryLanguage, second: SecondLanguage, model: String) async throws -> String {
        recorder.registerPrevious = previous
        recorder.registerCurrent = current
        recorder.registerFrom = from
        recorder.registerTo = to
        recorder.registerSource = source
        recorder.registerSecond = second
        recorder.registerModel = model
        if let toneNoteError { throw toneNoteError }
        return toneNoteResult
    }

    private func makeStream() -> AsyncThrowingStream<TranslationEvent, Error> {
        let events = self.events
        let error = self.error
        let gate = self.gate
        let started = streamStarted
        return AsyncThrowingStream { continuation in
            guard let gate else {
                for event in events { continuation.yield(event) }
                if let error { continuation.finish(throwing: error) } else { continuation.finish() }
                return
            }
            let task = Task {
                var pending: StreamGate? = gate
                started.release()
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

    func translateBlock(html: String, into primary: PrimaryLanguage, model: String) async throws -> String {
        recorder.blockHTMLs.append(html)
        recorder.blockPrimary = primary
        recorder.blockModel = model
        if let blockError { throw blockError }
        return blockResult
    }

    func translateBlocks(_ blocks: [(id: Int, html: String)], into primary: PrimaryLanguage, model: String) async throws -> [Int: String] {
        recorder.batches.append(blocks.map(\.id))
        recorder.blockPrimary = primary
        recorder.blockModel = model
        if let blockError { throw blockError }
        return Dictionary(uniqueKeysWithValues: blocks.map { ($0.id, blockResult) })
    }

    func readerSummary(of text: String, into primary: PrimaryLanguage, model: String) async throws -> String {
        recorder.summaryText = text
        recorder.summaryPrimary = primary
        recorder.summaryModel = model
        if let summaryError { throw summaryError }
        return summaryResult
    }

    func askArticle(question: String, history: [(question: String, answer: String)], article: String, into primary: PrimaryLanguage, model: String) async throws -> String {
        recorder.askQuestion = question
        recorder.askHistory = history
        recorder.askArticleText = article
        recorder.askPrimary = primary
        recorder.askModel = model
        if let askError { throw askError }
        return askResult
    }

    func articleQuestions(about article: String, into primary: PrimaryLanguage, model: String) async throws -> [String] {
        recorder.questionsArticleText = article
        recorder.questionsPrimary = primary
        recorder.questionsModel = model
        if let questionsError { throw questionsError }
        return questionsResult
    }

    func prewarm(model: String) async throws { recorder.prewarmModel = model }
}

@MainActor
final class FakeReaderPresenter: ReaderPresenting {
    private(set) var shownURLs: [URL] = []
    func show(_ url: URL) { shownURLs.append(url) }
}

@MainActor
final class FakePasteboardReader: PasteboardReading {
    var currentChangeCount: Int = 0
    /// Throw this many `.nothingSelected` before the copy "lands". nil = never lands.
    var readyAfterAttempts: Int?
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
    var snapshotPID: pid_t = 42
    var elementID = "editor"
    var selectedRange = NSRange(location: 0, length: 7)
    var snapshotAvailable = true
    func snapshot() -> SelectionSnapshot? {
        guard snapshotAvailable, let text = selectedText(), !text.isEmpty else { return nil }
        return SelectionSnapshot(pid: snapshotPID, element: elementID as NSString, range: selectedRange, text: text)
    }
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
    let firstToken = StreamGate()
    var onDismiss: (@MainActor () -> Void)?
    var onSelectFormality: (@MainActor (Formality) -> Void)?
    var onSelectAction: (@MainActor (Action) -> Void)?
    var onFetchAlternatives: (@MainActor (_ word: String, _ translation: String) async -> [String])?
    var onPickAlternative: (@MainActor (_ original: String, _ chosen: String, _ translation: String) -> Void)?
    var onFetchExplanation: (@MainActor (_ word: String, _ translation: String) async -> String)?
    var onFetchFixReason: (@MainActor (_ before: String, _ after: String, _ corrected: String) async -> String)?
    var onFetchToneNote: (@MainActor (_ previous: String, _ current: String, _ from: Formality, _ to: Formality) async -> String)?
    var onReplace: (@MainActor (_ translation: String) -> Void)?
    var onRetranslate: (@MainActor (_ source: String) -> Void)?
    var onSourceChange: (@MainActor () -> Void)?
    var onUndo: (@MainActor () -> Void)?
    private(set) var presented = false
    private(set) var presentedDirection: TranslationDirection?
    private(set) var presentedSourceText: String?
    private(set) var presentedAction: Action?
    private(set) var presentedFormality: Formality?
    private(set) var dismissCount = 0
    private(set) var restartCount = 0
    private(set) var tokens: [String] = []
    private(set) var errorMessage: String?
    private(set) var finished = false
    private(set) var truncated = false

    private(set) var manualOpenCount = 0
    private(set) var idle = false

    func openTranslator(formality: Formality) {
        guard !presented else { return }
        manualOpenCount += 1
        present(at: .zero, formality: formality)
        resetToIdle()
    }
    func resetToIdle() {
        restartTranslation()
        idle = true
    }
    func present(at screenPoint: CGPoint, formality: Formality) {
        presented = true
        presentedFormality = formality
    }
    func update(direction: TranslationDirection, sourceText: String, action: Action) {
        presentedDirection = direction
        presentedSourceText = sourceText
        presentedAction = action
    }
    func append(token: String) { tokens.append(token); firstToken.release() }
    func showError(_ message: String) { errorMessage = message }
    func finish(truncated: Bool) { finished = true; self.truncated = truncated }
    func restartTranslation() {
        idle = false
        restartCount += 1
        tokens.removeAll()
        errorMessage = nil
        finished = false
        truncated = false
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
    private(set) var startCount = 0
    private(set) var stopCount = 0
    var startError: (any Error)?
    func start() throws {
        startCount += 1
        if let startError { throw startError }
    }
    func stop() { stopCount += 1 }
}
