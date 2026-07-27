import Foundation
import AppKit
import CoreGraphics
import Testing
@testable import Glosso

@MainActor
@Suite struct AppCoordinatorTests {
    private func makeSettings(model: String = "test-model", second: SecondLanguage = .english, formality: Formality = .automatic) -> SettingsStore {
        let defaults = UserDefaults(suiteName: "AppCoordinatorTests-\(UUID().uuidString)")!
        let store = SettingsStore(defaults: defaults)
        store.modelName = model
        store.secondLanguage = second
        store.formality = formality
        return store
    }

    private func makeCoordinator(
        llm: FakeLLMClient,
        reader: any PasteboardReading,
        popup: FakePopup,
        settings: SettingsStore? = nil,
        axReader: any AXSelectionReading = FakeAXSelectionReader(),
        articleReader: (any ReaderPresenting)? = nil,
        prefetchLingerMs: Int = 0
    ) -> AppCoordinator {
        AppCoordinator(
            llm: llm,
            monitor: FakeHotkeyMonitor(),
            reader: reader,
            axReader: axReader,
            popup: popup,
            settings: settings ?? makeSettings(),
            articleReader: articleReader,
            pollStepMs: 1,
            pollMaxAttempts: 5,
            prefetchLingerMs: prefetchLingerMs
        )
    }

    private func spin(until condition: () -> Bool, max: Int = 20_000) async {
        var spins = 0
        while !condition() && spins < max { await Task.yield(); spins += 1 }
    }

    @Test func translatesOnceClipboardBecomesReady() async {
        let llm = FakeLLMClient(events: [.token("He"), .token("llo"), .finished(doneReason: "stop")])
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = 2   // first two polls report nothing yet
        reader.text = "Dzień dobry"
        let popup = FakePopup()
        let settings = makeSettings(model: "test-model", second: .english, formality: .formal)
        let coordinator = makeCoordinator(llm: llm, reader: reader, popup: popup, settings: settings)

        await coordinator.captureAndTranslate(baseline: 0, at: .zero)

        #expect(llm.recorder.receivedText == "Dzień dobry")
        #expect(llm.recorder.receivedModel == "test-model")
        #expect(llm.recorder.receivedSecond == .english)
        #expect(llm.recorder.receivedFormality == .formal)
        #expect(popup.presented)
        #expect(popup.presentedFormality == .formal)
        #expect(popup.presentedDirection == .fromPrimary(.polish, .english))
    }

    // MARK: URL reader routing

    @Test func copiedURLRoutesToTheReaderInsteadOfTranslating() async {
        let llm = FakeLLMClient()
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = 0
        reader.text = "https://example.com/artykul"
        let popup = FakePopup()
        let presenter = FakeReaderPresenter()
        let coordinator = makeCoordinator(llm: llm, reader: reader, popup: popup, articleReader: presenter)

        await coordinator.captureAndTranslate(baseline: 0, at: .zero)

        #expect(presenter.shownURLs == [URL(string: "https://example.com/artykul")!])
        #expect(llm.recorder.runCount == 0)
        #expect(popup.dismissCount == 1)
    }

    @Test func urlInsideProseTranslatesNormally() async {
        let llm = FakeLLMClient()
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = 0
        reader.text = "zobacz https://example.com/artykul proszę"
        let popup = FakePopup()
        let presenter = FakeReaderPresenter()
        let coordinator = makeCoordinator(llm: llm, reader: reader, popup: popup, articleReader: presenter)

        await coordinator.captureAndTranslate(baseline: 0, at: .zero)

        #expect(presenter.shownURLs.isEmpty)
        #expect(llm.recorder.receivedText == "zobacz https://example.com/artykul proszę")
    }

    @Test func copiedURLWithoutReaderFallsBackToTranslation() async {
        let llm = FakeLLMClient()
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = 0
        reader.text = "https://example.com/artykul"
        let popup = FakePopup()
        let coordinator = makeCoordinator(llm: llm, reader: reader, popup: popup)

        await coordinator.captureAndTranslate(baseline: 0, at: .zero)

        #expect(llm.recorder.receivedText == "https://example.com/artykul")
    }

    @Test func axFallbackAlsoRoutesURLsToTheReader() async {
        let llm = FakeLLMClient()
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = nil   // pasteboard never delivers
        let axReader = FakeAXSelectionReader()
        axReader.text = "https://example.com/artykul"
        let popup = FakePopup()
        let presenter = FakeReaderPresenter()
        let coordinator = makeCoordinator(
            llm: llm, reader: reader, popup: popup,
            axReader: axReader, articleReader: presenter)

        await coordinator.captureAndTranslate(baseline: 0, at: .zero)

        #expect(presenter.shownURLs == [URL(string: "https://example.com/artykul")!])
        #expect(llm.recorder.runCount == 0)
    }

    @Test func passesCapturedSourceTextToThePopup() async {
        let llm = FakeLLMClient(events: [.token("Hello"), .finished(doneReason: "stop")])
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = 0
        reader.text = "Dzień dobry"
        let popup = FakePopup()
        let coordinator = makeCoordinator(llm: llm, reader: reader, popup: popup)

        await coordinator.captureAndTranslate(baseline: 0, at: .zero)

        #expect(popup.presentedSourceText == "Dzień dobry")
    }

    @Test func timeoutReportsFetchFailureNotEmptySelection() async {
        let llm = FakeLLMClient()
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = nil   // never ready
        let popup = FakePopup()
        let coordinator = makeCoordinator(llm: llm, reader: reader, popup: popup)

        await coordinator.captureAndTranslate(baseline: 0, at: .zero)

        #expect(llm.recorder.receivedText == nil)
        #expect(popup.errorMessage == "Nie udało się pobrać zaznaczenia. Spróbuj ponownie.")
    }

    @Test func trailingSnapshotAcceptsACopyThatPrecededTheCallbacks() async {
        let llm = FakeLLMClient()
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = 0
        reader.landedChangeCount = 5   // the gesture's copy, already landed at callback time
        reader.text = "select from the terminal"
        let popup = FakePopup()
        let coordinator = makeCoordinator(llm: llm, reader: reader, popup: popup)
        coordinator.trailingChangeCounts = [4]   // snapshot from before the gesture

        await coordinator.captureAndTranslate(baseline: 5, at: .zero)

        #expect(llm.recorder.receivedText == "select from the terminal")
        #expect(popup.errorMessage == nil)
    }

    @Test func trailingSnapshotRefusesAnUntouchedClipboard() async {
        let llm = FakeLLMClient()
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = 0
        reader.landedChangeCount = 5   // stale content, copied long before this gesture
        reader.text = "stare dane sprzed kwadransa"
        let popup = FakePopup()
        let coordinator = makeCoordinator(llm: llm, reader: reader, popup: popup)
        coordinator.trailingChangeCounts = [5]   // the snapshot already saw this copy

        await coordinator.captureAndTranslate(baseline: 5, at: .zero)

        #expect(llm.recorder.receivedText == nil)
        #expect(popup.errorMessage == "Nie udało się pobrać zaznaczenia. Spróbuj ponownie.")
    }

    @Test func liveAXSelectionBeatsAStaleCopyInsideTheSnapshotWindow() async {
        let llm = FakeLLMClient()
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = 0
        reader.landedChangeCount = 5   // unrelated copy, landed before the gesture
        reader.text = "skopiowane chwilę wcześniej, niezwiązane"
        let axReader = FakeAXSelectionReader()
        axReader.text = "faktyczne bieżące zaznaczenie"
        let popup = FakePopup()
        let coordinator = makeCoordinator(llm: llm, reader: reader, popup: popup, axReader: axReader)
        coordinator.trailingChangeCounts = [4]   // snapshot predates the unrelated copy

        await coordinator.captureAndTranslate(baseline: 5, at: .zero)

        #expect(llm.recorder.receivedText == "faktyczne bieżące zaznaczenie")
        #expect(popup.errorMessage == nil)
    }

    @Test func aSecondDoubleCopyTearsDownTheInFlightStream() async {
        let gate = StreamGate()
        let llm = FakeLLMClient(events: [.token("first"), .token("late"), .finished(doneReason: "stop")], gate: gate)
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = 0
        let popup = FakePopup()
        let coordinator = makeCoordinator(llm: llm, reader: reader, popup: popup)

        coordinator.handleDoubleCopy(baseline: 0)
        var spins = 0
        while popup.tokens.isEmpty && spins < 10_000 { await Task.yield(); spins += 1 }
        #expect(popup.tokens == ["first"])   // capture #1 is suspended mid-stream

        reader.readyAfterAttempts = nil       // #2 just polls; it won't stream and muddy the tokens
        coordinator.handleDoubleCopy(baseline: 0)
        #expect(popup.dismissCount == 1)      // #1's popup torn down

        gate.release()                        // resume #1 — it is cancelled, must not append "late"
        spins = 0
        while spins < 200 { await Task.yield(); spins += 1 }
        #expect(popup.tokens == ["first"])
    }

    @Test func unexpectedCancelSurfacesErrorNotAnOrphan() async {
        let llm = FakeLLMClient(events: [], error: .cancelled)
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = 0
        reader.text = "Dzień dobry"
        let popup = FakePopup()
        let coordinator = makeCoordinator(llm: llm, reader: reader, popup: popup)

        await coordinator.captureAndTranslate(baseline: 0, at: .zero)

        #expect(popup.presented)
        #expect(popup.errorMessage == TranslationError.cancelled.userMessage)
    }

    @Test func lengthTruncatedStreamKeepsTextAndFlagsTruncation() async {
        let llm = FakeLLMClient(events: [.token("Cześć"), .finished(doneReason: "length")])
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = 0
        reader.text = "Hello"
        let popup = FakePopup()
        let coordinator = makeCoordinator(llm: llm, reader: reader, popup: popup)

        await coordinator.captureAndTranslate(baseline: 0, at: .zero)

        #expect(popup.tokens == ["Cześć"])
        #expect(popup.finished == true)
        #expect(popup.truncated == true)
        #expect(popup.errorMessage == nil)
    }

    @Test func startReturnsTrueWhenTheMonitorStarts() {
        let coordinator = makeCoordinator(llm: FakeLLMClient(), reader: FakePasteboardReader(), popup: FakePopup())
        #expect(coordinator.start() == true)
    }

    @Test func startReturnsFalseWhenTheMonitorThrows() {
        struct StartFailure: Error {}
        let monitor = FakeHotkeyMonitor()
        monitor.startError = StartFailure()
        let coordinator = AppCoordinator(
            llm: FakeLLMClient(), monitor: monitor,
            reader: FakePasteboardReader(), axReader: FakeAXSelectionReader(), popup: FakePopup(),
            settings: makeSettings()
        )
        #expect(coordinator.start() == false)
    }

    @Test func startWiresPopupDismissToCancelTheCapture() async {
        let gate = StreamGate()
        let llm = FakeLLMClient(events: [.token("first"), .token("late"), .finished(doneReason: "stop")], gate: gate)
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = 0
        let popup = FakePopup()
        let coordinator = AppCoordinator(
            llm: llm, monitor: FakeHotkeyMonitor(), reader: reader,
            axReader: FakeAXSelectionReader(), popup: popup,
            settings: makeSettings(), pollStepMs: 1, pollMaxAttempts: 5
        )

        coordinator.start()
        coordinator.handleDoubleCopy(baseline: 0)
        var spins = 0
        while popup.tokens.isEmpty && spins < 10_000 { await Task.yield(); spins += 1 }
        #expect(popup.tokens == ["first"])

        popup.dismiss()                       // onDismiss wiring should cancel the capture
        #expect(popup.dismissCount == 1)
        gate.release()
        spins = 0
        while spins < 200 { await Task.yield(); spins += 1 }
        #expect(popup.tokens == ["first"])    // cancelled capture never appended "late"
    }

    @Test func captureRequiresChangeCountStrictlyAboveBaseline() async {
        let llm = FakeLLMClient()
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = 0
        reader.landedChangeCount = 7          // copy lands at change count 7
        let popup = FakePopup()
        let coordinator = makeCoordinator(llm: llm, reader: reader, popup: popup)

        await coordinator.captureAndTranslate(baseline: 7, at: .zero)   // equal, not above

        #expect(llm.recorder.receivedText == nil)
        #expect(popup.errorMessage == "Nie udało się pobrać zaznaczenia. Spróbuj ponownie.")
    }

    @Test func stopHaltsTheMonitor() {
        let monitor = FakeHotkeyMonitor()
        let coordinator = AppCoordinator(
            llm: FakeLLMClient(),
            monitor: monitor,
            reader: FakePasteboardReader(),
            axReader: FakeAXSelectionReader(),
            popup: FakePopup(),
            settings: makeSettings()
        )

        coordinator.stop()

        #expect(monitor.stopCount == 1)
    }

    @Test func fixGrammarReplacesSelectionInPlace() async {
        let llm = FakeLLMClient(events: [.token("the "), .token("cat"), .finished(doneReason: "stop")])
        let axReader = FakeAXSelectionReader()
        axReader.text = "teh cat"
        let replacer = FakeSelectionReplacer()
        let coordinator = AppCoordinator(
            llm: llm, monitor: FakeHotkeyMonitor(),
            reader: FakePasteboardReader(), axReader: axReader, popup: FakePopup(),
            settings: makeSettings(model: "test-model"), replacer: replacer,
            frontmostPID: { 42 }
        )

        await coordinator.fixGrammarInPlace(sourcePID: 42)

        #expect(llm.recorder.receivedAction == .fixGrammar)
        #expect(llm.recorder.receivedText == "teh cat")
        #expect(llm.recorder.receivedModel == "test-model")
        #expect(replacer.replacedText == "the cat")
    }

    @Test func fixGrammarInPlaceRunsWithStyleForSupportedLanguage() async {
        let llm = FakeLLMClient(events: [.token("the cat"), .finished(doneReason: "stop")])
        let axReader = FakeAXSelectionReader()
        axReader.text = "teh cat"
        let replacer = FakeSelectionReplacer()
        let settings = makeSettings()
        let coordinator = AppCoordinator(
            llm: llm, monitor: FakeHotkeyMonitor(),
            reader: FakePasteboardReader(), axReader: axReader, popup: FakePopup(),
            settings: settings, replacer: replacer,
            frontmostPID: { 42 }
        )

        await coordinator.fixGrammarInPlace(sourcePID: 42)

        #expect(llm.recorder.receivedStyle == true)
        #expect(replacer.replacedText == "the cat")
    }

    @Test func translateInPlaceReplacesSelectionWithTranslation() async {
        let llm = FakeLLMClient(events: [.token("kot "), .token("śpi"), .finished(doneReason: "stop")])
        let axReader = FakeAXSelectionReader()
        axReader.text = "the cat sleeps"
        let replacer = FakeSelectionReplacer()
        let coordinator = AppCoordinator(
            llm: llm, monitor: FakeHotkeyMonitor(),
            reader: FakePasteboardReader(), axReader: axReader, popup: FakePopup(),
            settings: makeSettings(model: "test-model"), replacer: replacer,
            frontmostPID: { 42 }
        )

        await coordinator.fixGrammarInPlace(sourcePID: 42, action: .translate)

        #expect(llm.recorder.receivedAction == .translate)
        #expect(llm.recorder.receivedText == "the cat sleeps")
        #expect(replacer.replacedText == "kot śpi")
    }

    @Test func fixGrammarNotifiesWhenNothingSelected() async {
        let llm = FakeLLMClient()
        let axReader = FakeAXSelectionReader()
        axReader.text = nil
        let reader = FakePasteboardReader()    // readyAfterAttempts nil → never lands
        let replacer = FakeSelectionReplacer()
        var messages: [String] = []
        let coordinator = AppCoordinator(
            llm: llm, monitor: FakeHotkeyMonitor(),
            reader: reader, axReader: axReader, popup: FakePopup(),
            settings: makeSettings(), replacer: replacer,
            pollStepMs: 1, pollMaxAttempts: 5,
            notify: { messages.append($0) }
        )

        await coordinator.fixGrammarInPlace(sourcePID: 42)

        #expect(replacer.copyCount == 1)        // the fallback was attempted
        #expect(replacer.replacedText == nil)
        #expect(llm.recorder.receivedText == nil)
        #expect(messages.count == 1)
    }

    @Test func fixGrammarReadsASelectionTheTerminalCopiedOnSelection() async {
        let llm = FakeLLMClient(events: [.token("the cat"), .finished(doneReason: "stop")])
        let axReader = FakeAXSelectionReader()
        axReader.text = nil                    // terminals expose no AXSelectedText
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = 0
        reader.landedChangeCount = 5           // copied when the mouse selected it...
        reader.currentChangeCount = 5          // ...so the chord's own baseline is post-copy
        reader.text = "teh cat"
        let replacer = FakeSelectionReplacer()
        var messages: [String] = []
        let coordinator = AppCoordinator(
            llm: llm, monitor: FakeHotkeyMonitor(),
            reader: reader, axReader: axReader, popup: FakePopup(),
            settings: makeSettings(), replacer: replacer,
            pollStepMs: 1, pollMaxAttempts: 5,
            notify: { messages.append($0) }
        )
        coordinator.trailingChangeCounts = [4]  // snapshot from before the selection

        await coordinator.fixGrammarInPlace(sourcePID: 42)

        #expect(llm.recorder.receivedText == "teh cat")
        #expect(messages.first?.contains("schowku") == true)
    }

    @Test func fixGrammarRefusesAClipboardOlderThanTheSnapshot() async {
        let llm = FakeLLMClient(events: [.token("the cat"), .finished(doneReason: "stop")])
        let axReader = FakeAXSelectionReader()
        axReader.text = nil                    // terminals expose no AXSelectedText
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = 0
        reader.landedChangeCount = 5           // stale clipboard, copied long before the chord
        reader.currentChangeCount = 5
        reader.text = "hasło skopiowane kwadrans temu"
        var messages: [String] = []
        let coordinator = AppCoordinator(
            llm: llm, monitor: FakeHotkeyMonitor(),
            reader: reader, axReader: axReader, popup: FakePopup(),
            settings: makeSettings(), replacer: FakeSelectionReplacer(),
            pollStepMs: 1, pollMaxAttempts: 5,
            notify: { messages.append($0) }
        )
        coordinator.trailingChangeCounts = [5]  // the snapshot already saw this copy

        await coordinator.fixGrammarInPlace(sourcePID: 42)

        #expect(llm.recorder.receivedText == nil)
        #expect(messages == ["Nie udało się odczytać zaznaczenia do poprawy."])
    }

    @Test func fixGrammarFallbackInTerminalCopiesToClipboard() async {
        let llm = FakeLLMClient(events: [.token("the cat"), .finished(doneReason: "stop")])
        let axReader = FakeAXSelectionReader()
        axReader.text = nil                     // AX read yields nothing
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = 0           // the synthetic copy lands immediately
        reader.text = "teh cat"
        let replacer = FakeSelectionReplacer()
        var messages: [String] = []
        let coordinator = AppCoordinator(
            llm: llm, monitor: FakeHotkeyMonitor(),
            reader: reader, axReader: axReader, popup: FakePopup(),
            settings: makeSettings(), replacer: replacer,
            pollStepMs: 1, pollMaxAttempts: 5, frontmostPID: { 42 },
            frontmostBundleID: { "com.apple.Terminal" },
            notify: { messages.append($0) }
        )

        await coordinator.fixGrammarInPlace(sourcePID: 42)

        #expect(replacer.copyCount == 1)
        #expect(llm.recorder.receivedAction == .fixGrammar)
        #expect(llm.recorder.receivedText == "teh cat")
        #expect(replacer.replacedText == nil)   // no paste — would append in a terminal
        #expect(messages.count == 1)
        #expect(NSPasteboard.general.string(forType: .string) == "the cat")
    }

    @Test func fixGrammarFreshCopyInNonTerminalPastesInPlace() async {
        let llm = FakeLLMClient(events: [.token("the cat"), .finished(doneReason: "stop")])
        let axReader = FakeAXSelectionReader()
        axReader.text = nil                     // AX read yields nothing
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = 0           // the synthetic copy lands immediately
        reader.text = "teh cat"
        let replacer = FakeSelectionReplacer()
        var messages: [String] = []
        let coordinator = AppCoordinator(
            llm: llm, monitor: FakeHotkeyMonitor(),
            reader: reader, axReader: axReader, popup: FakePopup(),
            settings: makeSettings(), replacer: replacer,
            pollStepMs: 1, pollMaxAttempts: 5, frontmostPID: { 42 },
            frontmostBundleID: { "com.microsoft.VSCode" },
            notify: { messages.append($0) }
        )

        await coordinator.fixGrammarInPlace(sourcePID: 42)

        #expect(llm.recorder.receivedText == "teh cat")
        #expect(replacer.replacedText == "the cat")
        #expect(messages.isEmpty)
    }

    @Test func fixGrammarEmptyAXReadThroughoutStillPastesInPlace() async {
        let llm = FakeLLMClient(events: [.token("the cat"), .finished(doneReason: "stop")])
        let axReader = FakeAXSelectionReader()
        axReader.text = ""                      // non-nil empty, before and after
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = 0
        reader.text = "teh cat"
        let replacer = FakeSelectionReplacer()
        var messages: [String] = []
        let coordinator = AppCoordinator(
            llm: llm, monitor: FakeHotkeyMonitor(),
            reader: reader, axReader: axReader, popup: FakePopup(),
            settings: makeSettings(), replacer: replacer,
            pollStepMs: 1, pollMaxAttempts: 5, frontmostPID: { 42 },
            frontmostBundleID: { "com.microsoft.VSCode" },
            notify: { messages.append($0) }
        )

        await coordinator.fixGrammarInPlace(sourcePID: 42)

        #expect(replacer.replacedText == "the cat")
        #expect(messages.isEmpty)
    }

    @Test func fixGrammarUnknownBundleIDCopiesToClipboard() async {
        let llm = FakeLLMClient(events: [.token("the cat"), .finished(doneReason: "stop")])
        let axReader = FakeAXSelectionReader()
        axReader.text = nil
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = 0
        reader.text = "teh cat"
        let replacer = FakeSelectionReplacer()
        var messages: [String] = []
        let coordinator = AppCoordinator(
            llm: llm, monitor: FakeHotkeyMonitor(),
            reader: reader, axReader: axReader, popup: FakePopup(),
            settings: makeSettings(), replacer: replacer,
            pollStepMs: 1, pollMaxAttempts: 5, frontmostPID: { 42 },
            frontmostBundleID: { nil },
            notify: { messages.append($0) }
        )

        await coordinator.fixGrammarInPlace(sourcePID: 42)

        #expect(replacer.replacedText == nil)
        #expect(messages.count == 1)
        #expect(NSPasteboard.general.string(forType: .string) == "the cat")
    }

    @Test func fixGrammarCopiesToClipboardWhenSelectionCollapsed() async {
        let llm = FakeLLMClient(events: [.token("the cat"), .finished(doneReason: "stop")])
        let axReader = FakeAXSelectionReader()
        axReader.texts = ["teh cat", ""]    // read for capture, then collapsed at paste
        let replacer = FakeSelectionReplacer()
        var messages: [String] = []
        let coordinator = AppCoordinator(
            llm: llm, monitor: FakeHotkeyMonitor(),
            reader: FakePasteboardReader(), axReader: axReader, popup: FakePopup(),
            settings: makeSettings(), replacer: replacer,
            frontmostPID: { 42 },
            notify: { messages.append($0) }
        )

        await coordinator.fixGrammarInPlace(sourcePID: 42)

        #expect(llm.recorder.receivedText == "teh cat")
        #expect(replacer.replacedText == nil)   // no paste — would insert at cursor
        #expect(messages.count == 1)
        #expect(NSPasteboard.general.string(forType: .string) == "the cat")
    }

    @Test func fixGrammarFallsBackToClipboardWhenAppChanged() async {
        let llm = FakeLLMClient(events: [.token("the cat"), .finished(doneReason: "stop")])
        let axReader = FakeAXSelectionReader()
        axReader.text = "teh cat"
        let replacer = FakeSelectionReplacer()
        var messages: [String] = []
        let coordinator = AppCoordinator(
            llm: llm, monitor: FakeHotkeyMonitor(),
            reader: FakePasteboardReader(), axReader: axReader, popup: FakePopup(),
            settings: makeSettings(), replacer: replacer,
            frontmostPID: { 99 },           // now a different app than the captured PID
            notify: { messages.append($0) }
        )

        await coordinator.fixGrammarInPlace(sourcePID: 42)

        #expect(replacer.replacedText == nil)
        #expect(messages.count == 1)
        #expect(NSPasteboard.general.string(forType: .string) == "the cat")
    }

    @Test func stopDismissesAVisiblePopup() async {
        let llm = FakeLLMClient()
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = 0
        let popup = FakePopup()
        let coordinator = makeCoordinator(llm: llm, reader: reader, popup: popup)

        await coordinator.captureAndTranslate(baseline: 0, at: .zero)
        #expect(popup.presented)

        coordinator.stop()

        #expect(popup.dismissCount == 1)
        #expect(popup.presented == false)
    }

    @Test func cyclingFormalityPersistsAndRetranslatesTheSameText() async {
        let llm = FakeLLMClient(events: [.token("Hallo"), .finished(doneReason: "stop")])
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = 0
        reader.text = "Dzień dobry"
        let popup = FakePopup()
        let settings = makeSettings(second: .german, formality: .automatic)
        let coordinator = makeCoordinator(llm: llm, reader: reader, popup: popup, settings: settings)

        coordinator.start()
        await coordinator.captureAndTranslate(baseline: 0, at: .zero)
        #expect(llm.recorder.receivedFormality == .automatic)

        popup.onSelectFormality?(.formal)   // user clicked the tone pill
        var spins = 0
        while llm.recorder.receivedFormality != .formal && spins < 10_000 { await Task.yield(); spins += 1 }

        #expect(settings.formality == .formal)
        #expect(popup.restartCount == 1)
        #expect(llm.recorder.receivedText == "Dzień dobry")
        #expect(llm.recorder.receivedFormality == .formal)
    }

    @Test func cyclingFormalityBeforeCaptureOnlyPersists() {
        let llm = FakeLLMClient()
        let popup = FakePopup()
        let settings = makeSettings(formality: .automatic)
        let coordinator = makeCoordinator(llm: llm, reader: FakePasteboardReader(), popup: popup, settings: settings)

        coordinator.start()
        popup.onSelectFormality?(.informal)

        #expect(settings.formality == .informal)
        #expect(popup.restartCount == 0)
        #expect(llm.recorder.receivedText == nil)
    }

    // MARK: Style pass (grammar+style, always-on where the direction supports it)

    @Test func styleGatedOffForUnsupportedLanguage() async {
        let llm = FakeLLMClient(events: [.token("X"), .finished(doneReason: "stop")])
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = 0
        reader.text = "Guten Morgen, wie geht es dir heute?"
        let popup = FakePopup()
        let settings = makeSettings(second: .german)
        let coordinator = makeCoordinator(llm: llm, reader: reader, popup: popup, settings: settings)

        coordinator.start()
        await coordinator.captureAndTranslate(baseline: 0, at: .zero)
        popup.onSelectAction?(.fixGrammar)
        await spin(until: { llm.recorder.receivedAction == .fixGrammar })

        #expect(llm.recorder.receivedStyle == false)
    }

    // MARK: Action palette (issue #23)

    // The first capture always runs the Translate verb.
    @Test func firstCaptureRunsTranslate() async {
        let llm = FakeLLMClient(events: [.token("Hi"), .finished(doneReason: "stop")])
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = 0
        reader.text = "Dzień dobry"
        let popup = FakePopup()
        let settings = makeSettings()
        let coordinator = makeCoordinator(llm: llm, reader: reader, popup: popup, settings: settings)

        await coordinator.captureAndTranslate(baseline: 0, at: .zero)

        #expect(llm.recorder.receivedAction == .translate)
        #expect(popup.presentedAction == .translate)
        #expect(popup.presentedDirection == .fromPrimary(.polish, .english))
    }

    @Test func captureRunsWithStyleForSupportedLanguage() async {
        let llm = FakeLLMClient(events: [.token("Hi"), .finished(doneReason: "stop")])
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = 0
        let popup = FakePopup()
        let settings = makeSettings()
        let coordinator = makeCoordinator(llm: llm, reader: reader, popup: popup, settings: settings)

        await coordinator.captureAndTranslate(baseline: 0, at: .zero)

        #expect(llm.recorder.receivedStyle == true)
    }

    @Test func pickingVerbRerunsSameTextWithThatAction() async {
        let llm = FakeLLMClient(events: [.token("…"), .finished(doneReason: "stop")])
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = 0
        reader.text = "Dzień dobry"
        let popup = FakePopup()
        let coordinator = makeCoordinator(llm: llm, reader: reader, popup: popup)

        coordinator.start()
        await coordinator.captureAndTranslate(baseline: 0, at: .zero)
        #expect(llm.recorder.receivedAction == .translate)

        popup.onSelectAction?(.summarize)   // user clicked the Streść pill
        var spins = 0
        while llm.recorder.receivedAction != .summarize && spins < 10_000 { await Task.yield(); spins += 1 }

        #expect(popup.restartCount == 1)
        #expect(llm.recorder.receivedText == "Dzień dobry")
        #expect(llm.recorder.receivedAction == .summarize)
        #expect(popup.presentedAction == .summarize)
        #expect(popup.presentedDirection == .unknown)
    }

    @Test func fixGrammarVerbComputesDirection() async {
        let llm = FakeLLMClient(events: [.token("…"), .finished(doneReason: "stop")])
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = 0
        reader.text = "Dzień dobry"
        let popup = FakePopup()
        let coordinator = makeCoordinator(llm: llm, reader: reader, popup: popup)

        coordinator.start()
        await coordinator.captureAndTranslate(baseline: 0, at: .zero)

        popup.onSelectAction?(.fixGrammar)
        var spins = 0
        while popup.presentedAction != .fixGrammar && spins < 10_000 { await Task.yield(); spins += 1 }

        #expect(popup.presentedDirection == .fromPrimary(.polish, .english))
    }

    @Test func pickingReplyShowsDraftsViaTheListPath() async {
        let llm = FakeLLMClient(reply: ["wersja A", "wersja B", "wersja C"])
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = 0
        reader.text = "Hi, are we still on for Thursday?"
        let popup = FakePopup()
        let coordinator = makeCoordinator(llm: llm, reader: reader, popup: popup)

        coordinator.start()
        await coordinator.captureAndTranslate(baseline: 0, at: .zero)

        popup.onSelectAction?(.reply)   // user clicked the Odpowiedz pill
        var spins = 0
        while popup.shownReplies == nil && spins < 10_000 { await Task.yield(); spins += 1 }

        #expect(popup.shownReplies == ["wersja A", "wersja B", "wersja C"])
        #expect(llm.recorder.replyText == "Hi, are we still on for Thursday?")
        #expect(popup.presentedAction == .reply)
        #expect(popup.presentedDirection == .unknown)
    }

    @Test func pickingReplyWithNoDraftsShowsError() async {
        let llm = FakeLLMClient(reply: [])
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = 0
        let popup = FakePopup()
        let coordinator = makeCoordinator(llm: llm, reader: reader, popup: popup)

        coordinator.start()
        await coordinator.captureAndTranslate(baseline: 0, at: .zero)

        popup.onSelectAction?(.reply)
        var spins = 0
        while popup.errorMessage == nil && spins < 10_000 { await Task.yield(); spins += 1 }

        #expect(popup.shownReplies == nil)
        #expect(popup.errorMessage != nil)
    }

    // Changing the verb before any text was captured is a no-op (nothing to re-run).
    @Test func pickingVerbBeforeCaptureIsNoop() {
        let llm = FakeLLMClient()
        let popup = FakePopup()
        let coordinator = makeCoordinator(llm: llm, reader: FakePasteboardReader(), popup: popup)

        coordinator.start()
        popup.onSelectAction?(.fixGrammar)

        #expect(popup.restartCount == 0)
        #expect(llm.recorder.receivedText == nil)
    }

    // MARK: Editable source (issue #44)

    @Test func editingSourceRerunsWithNewText() async {
        let llm = FakeLLMClient(events: [.token("…"), .finished(doneReason: "stop")])
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = 0
        reader.text = "Dzień dobry"
        let popup = FakePopup()
        let coordinator = makeCoordinator(llm: llm, reader: reader, popup: popup)

        coordinator.start()
        await coordinator.captureAndTranslate(baseline: 0, at: .zero)
        #expect(llm.recorder.receivedText == "Dzień dobry")

        popup.onRetranslate?("Poprawiony tekst")   // user edited the source and hit Przetłumacz
        var spins = 0
        while llm.recorder.receivedText != "Poprawiony tekst" && spins < 10_000 { await Task.yield(); spins += 1 }

        #expect(popup.restartCount == 1)
        #expect(llm.recorder.receivedText == "Poprawiony tekst")
        #expect(llm.recorder.receivedAction == .translate)
        #expect(popup.presentedSourceText == "Poprawiony tekst")
    }

    // Re-translating before any text was captured is a no-op (nothing to re-run).
    @Test func retranslateBeforeCaptureIsNoop() {
        let llm = FakeLLMClient()
        let popup = FakePopup()
        let coordinator = makeCoordinator(llm: llm, reader: FakePasteboardReader(), popup: popup)

        coordinator.start()
        popup.onRetranslate?("cokolwiek")

        #expect(popup.restartCount == 0)
        #expect(llm.recorder.receivedText == nil)
    }

    // An empty edit is ignored — there is nothing meaningful to translate.
    @Test func retranslateWithEmptyTextIsNoop() async {
        let llm = FakeLLMClient(events: [.token("…"), .finished(doneReason: "stop")])
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = 0
        reader.text = "Dzień dobry"
        let popup = FakePopup()
        let coordinator = makeCoordinator(llm: llm, reader: reader, popup: popup)

        coordinator.start()
        await coordinator.captureAndTranslate(baseline: 0, at: .zero)

        popup.onRetranslate?("")

        #expect(popup.restartCount == 0)
        #expect(llm.recorder.receivedText == "Dzień dobry")
    }

    // MARK: Per-word alternatives (issue #17)

    @Test func fetchAlternativesThreadsSourceAndSecondLanguage() async {
        let llm = FakeLLMClient(alternatives: ["świetny", "wspaniały"])
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = 0
        reader.text = "This is great"
        let popup = FakePopup()
        let settings = makeSettings(second: .english)
        let coordinator = makeCoordinator(llm: llm, reader: reader, popup: popup, settings: settings)

        coordinator.start()
        await coordinator.captureAndTranslate(baseline: 0, at: .zero)

        let result = await popup.onFetchAlternatives?("wspaniały", "To jest wspaniały")
        #expect(result == ["świetny", "wspaniały"])
        #expect(llm.recorder.altWord == "wspaniały")
        #expect(llm.recorder.altTranslation == "To jest wspaniały")
        #expect(llm.recorder.altSource == "This is great")   // the captured source
        #expect(llm.recorder.altSecond == .english)
    }

    @Test func fetchAlternativesBeforeCaptureReturnsEmpty() async {
        let llm = FakeLLMClient(alternatives: ["x"])
        let popup = FakePopup()
        let coordinator = makeCoordinator(llm: llm, reader: FakePasteboardReader(), popup: popup)

        coordinator.start()
        let result = await popup.onFetchAlternatives?("foo", "bar")

        #expect(result == [])
        #expect(llm.recorder.altWord == nil)
    }

    @Test func fetchAlternativesSwallowsErrorsIntoEmptyList() async {
        let llm = FakeLLMClient(alternatives: [], alternativesError: .ollamaUnreachable)
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = 0
        reader.text = "great"
        let popup = FakePopup()
        let coordinator = makeCoordinator(llm: llm, reader: reader, popup: popup)

        coordinator.start()
        await coordinator.captureAndTranslate(baseline: 0, at: .zero)
        let result = await popup.onFetchAlternatives?("wspaniały", "wspaniały")

        #expect(result == [])
    }

    // MARK: Per-word explanation — "Dlaczego tak?" (issue #39)

    @Test func fetchExplanationThreadsSourceAndSecondLanguage() async {
        let llm = FakeLLMClient(explanation: "Rzeczownik rodzaju żeńskiego.")
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = 0
        reader.text = "die Vergangenheit"
        let popup = FakePopup()
        let settings = makeSettings(second: .german)
        let coordinator = makeCoordinator(llm: llm, reader: reader, popup: popup, settings: settings)

        coordinator.start()
        await coordinator.captureAndTranslate(baseline: 0, at: .zero)

        let result = await popup.onFetchExplanation?("przeszłość", "To jest przeszłość")
        #expect(result == "Rzeczownik rodzaju żeńskiego.")
        #expect(llm.recorder.explainWord == "przeszłość")
        #expect(llm.recorder.explainTranslation == "To jest przeszłość")
        #expect(llm.recorder.explainSource == "die Vergangenheit")   // the captured source
        #expect(llm.recorder.explainSecond == .german)
    }

    @Test func fetchExplanationBeforeCaptureReturnsEmpty() async {
        let llm = FakeLLMClient(explanation: "x")
        let popup = FakePopup()
        let coordinator = makeCoordinator(llm: llm, reader: FakePasteboardReader(), popup: popup)

        coordinator.start()
        let result = await popup.onFetchExplanation?("foo", "bar")

        #expect(result == "")
        #expect(llm.recorder.explainWord == nil)
    }

    @Test func fetchExplanationSwallowsErrorsIntoEmptyString() async {
        let llm = FakeLLMClient(explanation: "", explanationError: .ollamaUnreachable)
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = 0
        reader.text = "great"
        let popup = FakePopup()
        let coordinator = makeCoordinator(llm: llm, reader: reader, popup: popup)

        coordinator.start()
        await coordinator.captureAndTranslate(baseline: 0, at: .zero)
        let result = await popup.onFetchExplanation?("wspaniały", "wspaniały")

        #expect(result == "")
    }

    // MARK: Register coach — "Co się zmieniło?" (issue #53)

    @Test func fetchToneNoteThreadsBothRenderingsRegistersAndSource() async {
        let llm = FakeLLMClient(toneNote: "- Sie → du: zwrot nieformalny")
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = 0
        reader.text = "Czy mógłby Pan przyjść?"
        let popup = FakePopup()
        let settings = makeSettings(second: .german)
        let coordinator = makeCoordinator(llm: llm, reader: reader, popup: popup, settings: settings)

        coordinator.start()
        await coordinator.captureAndTranslate(baseline: 0, at: .zero)

        let result = await popup.onFetchToneNote?("Könnten Sie kommen?", "Könntest du kommen?", .formal, .informal)
        #expect(result == "- Sie → du: zwrot nieformalny")
        #expect(llm.recorder.registerPrevious == "Könnten Sie kommen?")
        #expect(llm.recorder.registerCurrent == "Könntest du kommen?")
        #expect(llm.recorder.registerFrom == .formal)
        #expect(llm.recorder.registerTo == .informal)
        #expect(llm.recorder.registerSource == "Czy mógłby Pan przyjść?")   // the captured source
        #expect(llm.recorder.registerSecond == .german)
    }

    @Test func fetchToneNoteBeforeCaptureReturnsEmpty() async {
        let llm = FakeLLMClient(toneNote: "x")
        let popup = FakePopup()
        let coordinator = makeCoordinator(llm: llm, reader: FakePasteboardReader(), popup: popup)

        coordinator.start()
        let result = await popup.onFetchToneNote?("a", "b", .automatic, .formal)

        #expect(result == "")
        #expect(llm.recorder.registerPrevious == nil)
    }

    @Test func fetchToneNoteSwallowsErrorsIntoEmptyString() async {
        let llm = FakeLLMClient(toneNote: "", toneNoteError: .ollamaUnreachable)
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = 0
        reader.text = "Dzień dobry"
        let popup = FakePopup()
        let coordinator = makeCoordinator(llm: llm, reader: reader, popup: popup)

        coordinator.start()
        await coordinator.captureAndTranslate(baseline: 0, at: .zero)
        let result = await popup.onFetchToneNote?("Good morning", "Hi", .formal, .informal)

        #expect(result == "")
    }

    // MARK: Grammar-diff reason — "Dlaczego poprawiono?" (issue #51)

    @Test func fetchFixReasonThreadsChangeOriginalAndSecondLanguage() async {
        let llm = FakeLLMClient(fixReason: "brak rodzajnika")
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = 0
        reader.text = "i has went to school"
        let popup = FakePopup()
        let settings = makeSettings(second: .english)
        let coordinator = makeCoordinator(llm: llm, reader: reader, popup: popup, settings: settings)

        coordinator.start()
        await coordinator.captureAndTranslate(baseline: 0, at: .zero)

        let result = await popup.onFetchFixReason?("has went", "have gone", "I have gone to school")
        #expect(result == "brak rodzajnika")
        #expect(llm.recorder.fixError == "has went")
        #expect(llm.recorder.fixCorrection == "have gone")
        #expect(llm.recorder.fixCorrected == "I have gone to school")
        #expect(llm.recorder.fixOriginal == "i has went to school")   // the captured original
        #expect(llm.recorder.fixSecond == .english)
        // English text under an English second language → the English rule base.
        #expect(llm.recorder.fixEnglishRules == true)
        // The explanation style grounding always mirrors the direction gate.
        #expect(llm.recorder.fixStyle == true)
    }

    // Polish text keeps the Polish rule base even with an English second language.
    @Test func fetchFixReasonKeepsPolishRulesForPolishText() async {
        let llm = FakeLLMClient(fixReason: "x")
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = 0
        reader.text = "W dniu dzisiejszym cofnąłem się do tyłu"
        let popup = FakePopup()
        let settings = makeSettings(second: .english)
        let coordinator = makeCoordinator(llm: llm, reader: reader, popup: popup, settings: settings)

        coordinator.start()
        await coordinator.captureAndTranslate(baseline: 0, at: .zero)
        _ = await popup.onFetchFixReason?("dzisiejszym", "dziś", "Dziś się cofnąłem")

        #expect(llm.recorder.fixEnglishRules == false)
    }

    @Test func fetchFixReasonKeepsPolishRulesForNonEnglishSecondLanguage() async {
        let llm = FakeLLMClient(fixReason: "x")
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = 0
        reader.text = "i has went to school"
        let popup = FakePopup()
        let settings = makeSettings(second: .german)
        let coordinator = makeCoordinator(llm: llm, reader: reader, popup: popup, settings: settings)

        coordinator.start()
        await coordinator.captureAndTranslate(baseline: 0, at: .zero)
        _ = await popup.onFetchFixReason?("has went", "went", "i went to school")

        #expect(llm.recorder.fixEnglishRules == false)
    }

    @Test func fetchFixReasonBeforeCaptureReturnsEmpty() async {
        let llm = FakeLLMClient(fixReason: "x")
        let popup = FakePopup()
        let coordinator = makeCoordinator(llm: llm, reader: FakePasteboardReader(), popup: popup)

        coordinator.start()
        let result = await popup.onFetchFixReason?("a", "b", "c")

        #expect(result == "")
        #expect(llm.recorder.fixError == nil)
    }

    @Test func fetchFixReasonSwallowsErrorsIntoEmptyString() async {
        let llm = FakeLLMClient(fixReason: "", fixReasonError: .ollamaUnreachable)
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = 0
        reader.text = "great"
        let popup = FakePopup()
        let coordinator = makeCoordinator(llm: llm, reader: reader, popup: popup)

        coordinator.start()
        await coordinator.captureAndTranslate(baseline: 0, at: .zero)
        let result = await popup.onFetchFixReason?("teh", "the", "the")

        #expect(result == "")
    }

    @Test func pickingAlternativeRewordsTheClause() async {
        let llm = FakeLLMClient(events: [.token("To jest świetny"), .finished(doneReason: "stop")])
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = 0
        reader.text = "This is great"
        let popup = FakePopup()
        let settings = makeSettings(second: .english, formality: .formal)
        let coordinator = makeCoordinator(llm: llm, reader: reader, popup: popup, settings: settings)

        coordinator.start()
        await coordinator.captureAndTranslate(baseline: 0, at: .zero)

        popup.onPickAlternative?("wspaniały", "świetny", "To jest wspaniały")
        var spins = 0
        while llm.recorder.rewordChosen == nil && spins < 10_000 { await Task.yield(); spins += 1 }

        #expect(popup.restartCount == 1)
        #expect(llm.recorder.rewordOriginal == "wspaniały")
        #expect(llm.recorder.rewordChosen == "świetny")
        #expect(llm.recorder.rewordTranslation == "To jest wspaniały")
        #expect(llm.recorder.rewordSource == "This is great")   // the captured source
        #expect(llm.recorder.rewordSecond == .english)
        #expect(llm.recorder.rewordFormality == .formal)
    }

    // MARK: Replace (issue #22)

    @Test func replacePastesTranslationAndDismissesWhenSourceAppUnchanged() async {
        let llm = FakeLLMClient(events: [.token("Hello"), .finished(doneReason: "stop")])
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = 0
        reader.text = "Dzień dobry"
        let popup = FakePopup()
        let replacer = FakeSelectionReplacer()
        let coordinator = AppCoordinator(
            llm: llm, monitor: FakeHotkeyMonitor(), reader: reader,
            axReader: FakeAXSelectionReader(), popup: popup, settings: makeSettings(),
            replacer: replacer, pollStepMs: 1, pollMaxAttempts: 5,
            frontmostPID: { 123 }
        )

        coordinator.start()
        await coordinator.captureAndTranslate(baseline: 0, at: .zero, sourcePID: 123)
        popup.onReplace?("Hello")

        #expect(replacer.replacedText == "Hello")
        #expect(popup.dismissCount == 1)
        #expect(popup.errorMessage == nil)
    }

    @Test func replaceIsASafeNoOpWhenFrontmostAppChanged() async {
        let llm = FakeLLMClient(events: [.token("Hello"), .finished(doneReason: "stop")])
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = 0
        reader.text = "Dzień dobry"
        let popup = FakePopup()
        let replacer = FakeSelectionReplacer()
        let coordinator = AppCoordinator(
            llm: llm, monitor: FakeHotkeyMonitor(), reader: reader,
            axReader: FakeAXSelectionReader(), popup: popup, settings: makeSettings(),
            replacer: replacer, pollStepMs: 1, pollMaxAttempts: 5,
            frontmostPID: { 999 }   // a different app is frontmost now
        )

        coordinator.start()
        await coordinator.captureAndTranslate(baseline: 0, at: .zero, sourcePID: 123)
        popup.onReplace?("Hello")

        #expect(replacer.replacedText == nil)
        #expect(popup.errorMessage == "Aplikacja źródłowa się zmieniła — nie wklejono.")
        #expect(popup.dismissCount == 0)
    }

    @Test func replaceRefusesWhenSelectionCollapsed() async {
        let llm = FakeLLMClient(events: [.token("Hello"), .finished(doneReason: "stop")])
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = 0
        reader.text = "Dzień dobry"
        let popup = FakePopup()
        let replacer = FakeSelectionReplacer()
        let ax = FakeAXSelectionReader()
        ax.text = "   "
        let coordinator = AppCoordinator(
            llm: llm, monitor: FakeHotkeyMonitor(), reader: reader,
            axReader: ax, popup: popup, settings: makeSettings(),
            replacer: replacer, pollStepMs: 1, pollMaxAttempts: 5,
            frontmostPID: { 123 }
        )

        coordinator.start()
        await coordinator.captureAndTranslate(baseline: 0, at: .zero, sourcePID: 123)
        popup.onReplace?("Hello")

        #expect(replacer.replacedText == nil)
        #expect(popup.errorMessage == "Brak zaznaczenia do zastąpienia.")
        #expect(popup.dismissCount == 0)
    }

    @Test func replaceProceedsWhenSelectionStillLive() async {
        let llm = FakeLLMClient(events: [.token("Hello"), .finished(doneReason: "stop")])
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = 0
        reader.text = "Dzień dobry"
        let popup = FakePopup()
        let replacer = FakeSelectionReplacer()
        let ax = FakeAXSelectionReader()
        ax.text = "Dzień dobry"
        let coordinator = AppCoordinator(
            llm: llm, monitor: FakeHotkeyMonitor(), reader: reader,
            axReader: ax, popup: popup, settings: makeSettings(),
            replacer: replacer, pollStepMs: 1, pollMaxAttempts: 5,
            frontmostPID: { 123 }
        )

        coordinator.start()
        await coordinator.captureAndTranslate(baseline: 0, at: .zero, sourcePID: 123)
        popup.onReplace?("Hello")

        #expect(replacer.replacedText == "Hello")
        #expect(popup.dismissCount == 1)
        #expect(popup.errorMessage == nil)
    }

    @Test func nonTextSelectionReportsImmediately() async {
        let llm = FakeLLMClient()
        let popup = FakePopup()
        let coordinator = makeCoordinator(llm: llm, reader: FakeEmptyPasteboardReader(), popup: popup)

        await coordinator.captureAndTranslate(baseline: 0, at: .zero)

        #expect(llm.recorder.receivedText == nil)
        #expect(popup.errorMessage == "Zaznaczenie nie zawiera tekstu do tłumaczenia.")
    }

    @Test func fallsBackToAXSelectionWhenClipboardNeverLands() async {
        let llm = FakeLLMClient()
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = nil   // clipboard never updates
        let ax = FakeAXSelectionReader()
        ax.text = "Dzień dobry"
        let popup = FakePopup()
        let coordinator = makeCoordinator(llm: llm, reader: reader, popup: popup, axReader: ax)

        await coordinator.captureAndTranslate(baseline: 0, at: .zero)

        #expect(llm.recorder.receivedText == "Dzień dobry")
        #expect(popup.presented)
        #expect(popup.errorMessage == nil)
    }

    @Test func clipboardTakesPrecedenceAndAXIsNotConsulted() async {
        let llm = FakeLLMClient()
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = 0
        reader.text = "Hello"
        let ax = FakeAXSelectionReader()
        ax.text = "stale selection"
        let popup = FakePopup()
        let coordinator = makeCoordinator(llm: llm, reader: reader, popup: popup, axReader: ax)

        await coordinator.captureAndTranslate(baseline: 0, at: .zero)

        #expect(llm.recorder.receivedText == "Hello")
        #expect(ax.callCount == 0)
    }

    @Test func presentsErrorWhenClipboardAndAXBothFail() async {
        let llm = FakeLLMClient()
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = nil
        let ax = FakeAXSelectionReader()
        ax.text = nil
        let popup = FakePopup()
        let coordinator = makeCoordinator(llm: llm, reader: reader, popup: popup, axReader: ax)

        await coordinator.captureAndTranslate(baseline: 0, at: .zero)

        #expect(llm.recorder.receivedText == nil)
        #expect(popup.errorMessage == "Nie udało się pobrać zaznaczenia. Spróbuj ponownie.")
    }

    @Test func whitespaceOnlyAXSelectionIsTreatedAsFailure() async {
        let llm = FakeLLMClient()
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = nil
        let ax = FakeAXSelectionReader()
        ax.text = "   \n\t "
        let popup = FakePopup()
        let coordinator = makeCoordinator(llm: llm, reader: reader, popup: popup, axReader: ax)

        await coordinator.captureAndTranslate(baseline: 0, at: .zero)

        #expect(llm.recorder.receivedText == nil)
        #expect(popup.errorMessage == "Nie udało się pobrać zaznaczenia. Spróbuj ponownie.")
    }

    @Test func axFallbackBailsWhenFrontmostAppChanged() async {
        let llm = FakeLLMClient()
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = nil   // clipboard never lands → AX fallback territory
        let ax = FakeAXSelectionReader()
        ax.text = "another app's selection"
        let popup = FakePopup()
        let coordinator = AppCoordinator(
            llm: llm, monitor: FakeHotkeyMonitor(), reader: reader,
            axReader: ax, popup: popup, settings: makeSettings(),
            pollStepMs: 1, pollMaxAttempts: 5,
            frontmostPID: { 999 }   // the app focused *now* differs from the source below
        )

        await coordinator.captureAndTranslate(baseline: 0, at: .zero, sourcePID: 123)

        #expect(ax.callCount == 0)
        #expect(llm.recorder.receivedText == nil)
        #expect(popup.errorMessage == "Nie udało się pobrać zaznaczenia. Spróbuj ponownie.")
    }

    @Test func axFallbackProceedsWhenFrontmostAppUnchanged() async {
        let llm = FakeLLMClient()
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = nil
        let ax = FakeAXSelectionReader()
        ax.text = "Dzień dobry"
        let popup = FakePopup()
        let coordinator = AppCoordinator(
            llm: llm, monitor: FakeHotkeyMonitor(), reader: reader,
            axReader: ax, popup: popup, settings: makeSettings(),
            pollStepMs: 1, pollMaxAttempts: 5,
            frontmostPID: { 123 }
        )

        await coordinator.captureAndTranslate(baseline: 0, at: .zero, sourcePID: 123)

        #expect(llm.recorder.receivedText == "Dzień dobry")
        #expect(popup.errorMessage == nil)
    }

    @Test func emptyOrNonTextSelectionDoesNotConsultAX() async {
        let llm = FakeLLMClient()
        let ax = FakeAXSelectionReader()
        ax.text = "would-be fallback"
        let popup = FakePopup()
        let coordinator = makeCoordinator(llm: llm, reader: FakeEmptyPasteboardReader(), popup: popup, axReader: ax)

        await coordinator.captureAndTranslate(baseline: 0, at: .zero)

        #expect(ax.callCount == 0)
        #expect(popup.errorMessage == "Zaznaczenie nie zawiera tekstu do tłumaczenia.")
    }

    @Test func prefetchFillsTheOtherVerbsAfterTheForegroundResult() async {
        let llm = FakeLLMClient(events: [.token("X"), .finished(doneReason: "stop")])
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = 0
        reader.text = "Cześć"
        let popup = FakePopup()
        let coordinator = makeCoordinator(llm: llm, reader: reader, popup: popup, prefetchLingerMs: 0)

        await coordinator.captureAndTranslate(baseline: 0, at: .zero)
        await spin(until: { llm.recorder.runCount >= 3 && llm.recorder.replyCount >= 1 })

        // translate (foreground) + fixGrammar + summarize; reply takes the reply() path.
        #expect(llm.recorder.runCount == 3)
        #expect(llm.recorder.runActions.contains(.fixGrammar))
        #expect(llm.recorder.runActions.contains(.summarize))
        #expect(llm.recorder.replyCount == 1)
    }

    @Test func switchingToAPrefetchedVerbReplaysFromCacheWithoutRerunning() async {
        let llm = FakeLLMClient(events: [.token("X"), .finished(doneReason: "stop")])
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = 0
        reader.text = "Cześć"
        let popup = FakePopup()
        let coordinator = makeCoordinator(llm: llm, reader: reader, popup: popup, prefetchLingerMs: 0)

        await coordinator.captureAndTranslate(baseline: 0, at: .zero)
        await spin(until: { llm.recorder.runCount >= 3 && llm.recorder.replyCount >= 1 })
        let runsBefore = llm.recorder.runCount
        let repliesBefore = llm.recorder.replyCount

        coordinator.handleActionChange(.fixGrammar)
        await spin(until: { popup.finished && popup.presentedAction == .fixGrammar })
        #expect(llm.recorder.runCount == runsBefore)   // served from cache
        #expect(popup.tokens == ["X"])                 // the cached result replayed

        coordinator.handleActionChange(.reply)
        await spin(until: { popup.shownReplies != nil })
        #expect(llm.recorder.replyCount == repliesBefore)
        #expect(popup.shownReplies == ["draft-one", "draft-two", "draft-three"])
    }

    @Test func changingToneInvalidatesTheActionCache() async {
        let llm = FakeLLMClient(events: [.token("X"), .finished(doneReason: "stop")])
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = 0
        reader.text = "Cześć"
        let popup = FakePopup()
        let coordinator = makeCoordinator(llm: llm, reader: reader, popup: popup, prefetchLingerMs: 600_000)

        await coordinator.captureAndTranslate(baseline: 0, at: .zero)   // translate cached, runCount 1
        coordinator.handleActionChange(.fixGrammar)                     // miss → run, runCount 2
        await spin(until: { llm.recorder.runCount == 2 })

        coordinator.handleActionChange(.translate)                      // cached from foreground → no run
        await spin(until: { popup.finished && popup.presentedAction == .translate })
        #expect(llm.recorder.runCount == 2)

        coordinator.handleFormalityChange(.formal)                      // clears cache + re-runs translate → 3
        await spin(until: { llm.recorder.runCount == 3 })
        coordinator.handleActionChange(.fixGrammar)                     // cache was cleared → must re-run → 4
        await spin(until: { llm.recorder.runCount == 4 })
        #expect(llm.recorder.runCount == 4)
    }

    @Test func undoDropsTheRewordedTranslateCacheSoARoundTripRecomputes() async {
        let llm = FakeLLMClient(events: [.token("X"), .finished(doneReason: "stop")])
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = 0
        reader.text = "Cześć"
        let popup = FakePopup()
        let coordinator = makeCoordinator(llm: llm, reader: reader, popup: popup, prefetchLingerMs: 600_000)

        await coordinator.captureAndTranslate(baseline: 0, at: .zero)   // translate cached, runCount 1
        coordinator.handlePickAlternative(original: "a", chosen: "b", translation: "X") // reword overwrites .translate
        await spin(until: { popup.finished })

        coordinator.handleUndo()                                        // must drop the reworded .translate entry
        coordinator.handleActionChange(.translate)                      // cache gone → must re-run → 2
        await spin(until: { llm.recorder.runCount == 2 })
        #expect(llm.recorder.runCount == 2)
    }
}
