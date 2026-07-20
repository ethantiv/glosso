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

    /// Spins the runloop until `condition` holds or a generous cap, so a test can
    /// wait on the background prefetch (a detached Task with its own linger sleep)
    /// without a fixed delay.
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
        // The coordinator must thread the persisted model + second language +
        // formality into the translate call and mirror the same language in the arrow.
        #expect(llm.recorder.receivedModel == "test-model")
        #expect(llm.recorder.receivedSecond == .english)
        #expect(llm.recorder.receivedFormality == .formal)
        #expect(popup.presented)
        #expect(popup.presentedFormality == .formal)
        #expect(popup.presentedDirection == .fromPrimary(.polish, .english))
    }

    // MARK: URL reader routing

    // A copied article URL must open the reader window, not translate the URL
    // string: the model is never hit and the skeleton popup is torn down.
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

    // A URL merely contained in prose is ordinary text — normal translation, the
    // reader stays untouched.
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

    // Without an injected reader (tests, or a build wiring none) a URL falls back
    // to plain translation instead of dropping the capture.
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

    // The AX fallback path (the app never copied on Cmd+C) must route URLs to the
    // reader exactly like the pasteboard path.
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

    // The popup now shows the source alongside the translation, so the coordinator
    // must hand the captured text to present() — not just stream the result.
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

    // A poll timeout (changeCount never rose) is ambiguous — slow copy or truly
    // nothing — so it must not claim "nic nie zaznaczono"; that wording belongs
    // only to the emptyOrNonText branch (see nonTextSelectionReportsImmediately).
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

    // The VS Code case: the gesture's copies land BEFORE our delayed event
    // callbacks even run (an open popup's active Esc tap routes every keyDown
    // through this process), so the strict baseline is post-copy and the poll never
    // sees a rise. The trailing snapshot — taken on a timer seconds earlier — must
    // then accept the gesture's own copy. Removing the second chance fails this test.
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

    // Freshness guard: when the pasteboard hasn't changed since the trailing
    // snapshot (nothing was copied in the last few seconds), the second chance must
    // NOT fire and the old clipboard content must not translate.
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

    // The trailing snapshot cannot tell the gesture's own copy from an unrelated
    // one made a few seconds earlier, so when the source app exposes its live
    // selection via AX, that read must win — otherwise a failed copy on a fresh
    // selection would translate (and Replace would paste) the stale clipboard.
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

    // A second double-copy arriving WHILE the first stream is still in flight must
    // cancel and tear down that stream before reassigning, or the abandoned stream
    // resumes and writes stale tokens into the popup. Gating the fake keeps the
    // first capture genuinely suspended mid-stream when the second one fires.
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

    // A .cancelled that did NOT come from our own captureTask (e.g. URLSession
    // suspended the request mid-stream) must surface as an error — only a cancel
    // that actually cancelled this Task is owned by the caller and stays silent.
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

    // A length-truncated stream keeps the partial text (still copyable) but flags
    // it truncated, rather than discarding what the user watched stream in.
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

    // start() must surface a failed monitor start as `false` so AppDelegate stops
    // claiming "Nasłuch aktywny" when Accessibility was not granted.
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

    // start() wires popup.onDismiss to cancel the in-flight capture; without that
    // wiring, dismissing the popup (Esc / close button) would not stop the stream.
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

    // readSelection only yields text once the change count rises strictly above
    // the baseline sampled at the first Cmd+C. An equal count (or a `>=`
    // regression) must time out, not translate a stale clipboard.
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

    // The headless fix-grammar chord (issue #46) reads the selection via AX, runs
    // fixGrammar, and pastes the corrected text straight back — no popup involved.
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

    // The headless chord always runs grammar+style for a language the style pass
    // supports (TranslationDirection.supportsStyleFix) — there is no toggle to check.
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

    // The headless "translate in place" chord (issue #21) reuses the same in-place
    // pipeline as fix-grammar but with action .translate, pasting the translation
    // straight back over the selection — the silent twin of the popup's Replace button.
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

    // With nothing selected — AX empty and the synthetic-copy fallback landing
    // nothing — there's nothing to correct: notify instead of silently doing
    // nothing, and never touch the LLM or the replacer's paste.
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

    // A terminal with copy-on-selection (VS Code's default) puts the text on the
    // clipboard the moment the mouse selects it, so by the time the chord fires the
    // fallback's Cmd+C rewrites identical content — a no-op that never bumps
    // changeCount. The strict baseline can then never rise and the chord would report
    // "nie udało się odczytać zaznaczenia" while the selection sits on the clipboard.
    // The trailing snapshot, taken before the selection, is what rescues it.
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

    // The other side of that second chance, and the only guard it left standing: the
    // retry cannot tell the selection's own copy from an unrelated one, so it must at
    // least refuse a clipboard that already predates the trailing snapshot. Without
    // this, a chord fired with no selection at all would run the model over whatever
    // the user last copied and hand the result back over their clipboard.
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

    // In a terminal even a fresh synthetic copy proves nothing: the "selection" is a
    // mouse highlight the shell won't replace, and Cmd+V would append at the prompt.
    // A known terminal bundle id keeps the clipboard notice instead of pasting.
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

    // The VS Code editor case (AX-nil Electron): the synthetic Cmd+C bumps the strict
    // baseline — proof the app performed a real copy — and the frontmost app is no
    // terminal, so the correction pastes back in place, silently.
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

    // VS Code's Monaco answers AXSelectedText with "" (not nil) throughout, so the
    // collapsed-selection guard must not read that as "the selection disappeared" —
    // it only means anything when the capture itself came from AX.
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

    // No bundle id means no proof the frontmost app isn't a terminal — stay
    // conservative and hand the result back via the clipboard.
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

    // The selection can collapse to an insertion point while the model streams (a
    // click back into the source). A non-nil but empty AXSelectedText at paste time
    // proves it; pasting would insert at the cursor, so the correction goes to the
    // clipboard with a notice instead — mirroring handleReplace.
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

    // If the user switched apps while the model streamed, pasting would land in the
    // wrong app — fall back to the clipboard plus a notification instead.
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

    // An AX revocation calls stop() while a popup may be on screen; its Esc
    // monitor is AX-gated and dies with the revocation, so stop() must dismiss
    // the popup itself or it orphans with a stuck spinner.
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

    // Cycling the popup's tone pill after a translation must persist the new tone,
    // reset the translation pane (restartTranslation), and re-run the SAME source
    // text through translate with the new formality — no re-copy needed.
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

    // Changing the tone before any text was captured must only persist the choice
    // (the pending stream reads it fresh) — not restart or re-translate nothing.
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

    // Style is requested automatically (no toggle to check), but gated per-run by
    // TranslationDirection.supportsStyleFix: for a text the gate doesn't cover
    // (German under a German second language) the run must not carry a style pass.
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

    // The capture threads style into the LLM call automatically for a language the
    // style pass supports (TranslationDirection.supportsStyleFix) — no toggle to seed.
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

    // Picking a verb in the palette after a translation re-runs the SAME source
    // text through that action and resets the pane — no re-copy needed. A non-
    // translate verb computes no translation direction (the popup hides the arrow).
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

    // fixGrammar computes a real direction (unlike summarize/reply): the coordinator
    // gates the automatic style pass on the detected language, so it must know it.
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

    // Reply (#60) is generative, not a transform: picking it must take the
    // non-streaming list path (llm.reply → popup.showReplies), NOT stream a single
    // result through run(). The drafts must reach the popup.
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

    // An empty drafts result (or a thrown error, swallowed to []) must surface as an
    // error in the popup, not a silent empty list.
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

    // Editing the source text and asking to translate again re-runs over the EDITED
    // text, resets the pane, and keeps the current action — no re-copy needed.
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

    // Clicking a word asks the model for alternatives, threading the captured
    // source and the persisted second language alongside the clicked word.
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

    // Before any capture there is no source context, so a fetch returns nothing
    // rather than calling the model with an empty source.
    @Test func fetchAlternativesBeforeCaptureReturnsEmpty() async {
        let llm = FakeLLMClient(alternatives: ["x"])
        let popup = FakePopup()
        let coordinator = makeCoordinator(llm: llm, reader: FakePasteboardReader(), popup: popup)

        coordinator.start()
        let result = await popup.onFetchAlternatives?("foo", "bar")

        #expect(result == [])
        #expect(llm.recorder.altWord == nil)
    }

    // A failed alternatives fetch collapses to an empty list (the dropdown shows
    // "no alternatives"), never surfacing as an error in the pane.
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

    // Tapping "Dlaczego tak?" asks the model for an explanation, threading the
    // captured source and the persisted second language alongside the clicked word.
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

    // Before any capture there is no source context, so a fetch returns empty
    // rather than calling the model with an empty source.
    @Test func fetchExplanationBeforeCaptureReturnsEmpty() async {
        let llm = FakeLLMClient(explanation: "x")
        let popup = FakePopup()
        let coordinator = makeCoordinator(llm: llm, reader: FakePasteboardReader(), popup: popup)

        coordinator.start()
        let result = await popup.onFetchExplanation?("foo", "bar")

        #expect(result == "")
        #expect(llm.recorder.explainWord == nil)
    }

    // A failed explanation fetch collapses to an empty string (the dropdown shows a
    // fallback message), never surfacing as an error in the pane.
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

    // Asking what a tone change did threads both renderings and both registers to
    // the model, plus the captured source and the persisted second language — the
    // note contrasts two translations of the same selection, so all four matter.
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

    // No capture means no source context, so the note returns empty instead of
    // asking the model to contrast against nothing (mirrors the explanation seam).
    @Test func fetchToneNoteBeforeCaptureReturnsEmpty() async {
        let llm = FakeLLMClient(toneNote: "x")
        let popup = FakePopup()
        let coordinator = makeCoordinator(llm: llm, reader: FakePasteboardReader(), popup: popup)

        coordinator.start()
        let result = await popup.onFetchToneNote?("a", "b", .automatic, .formal)

        #expect(result == "")
        #expect(llm.recorder.registerPrevious == nil)
    }

    // A failed note fetch collapses to an empty string — the row shows its fallback
    // message; a tone change must never surface as a translation error.
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

    // Tapping a diff change asks the model for the reason, threading the struck
    // error, its correction, the corrected text and the captured original alongside
    // the persisted second language.
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

    // The English base exists only for English: any other second language falls
    // back to the Polish base and its simple-reason escape, whatever the text.
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

    // Before any capture there is no original context, so a fetch returns empty
    // rather than calling the model with an empty original.
    @Test func fetchFixReasonBeforeCaptureReturnsEmpty() async {
        let llm = FakeLLMClient(fixReason: "x")
        let popup = FakePopup()
        let coordinator = makeCoordinator(llm: llm, reader: FakePasteboardReader(), popup: popup)

        coordinator.start()
        let result = await popup.onFetchFixReason?("a", "b", "c")

        #expect(result == "")
        #expect(llm.recorder.fixError == nil)
    }

    // A failed fix-reason fetch collapses to an empty string (the dropdown shows a
    // fallback message), never surfacing as an error in the pane.
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

    // Picking an alternative resets the result pane and re-translates the clause via
    // reword, threading the chosen word, the captured source and the persisted tone.
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

    // Clicking Replace after a translation pastes it over the source selection and
    // dismisses the popup — but only when the source app is still frontmost.
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

    // If the user switched apps (Cmd+Tab) after copying, Replace must not paste into
    // the wrong app: it surfaces an error and leaves the clipboard/popup untouched.
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

    // The source app is still frontmost, but the user clicked into the document
    // mid-stream and collapsed the selection — an empty (non-nil) AXSelectedText is
    // positive proof of that. Replace must refuse rather than insert at the cursor.
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

    // A live, non-empty AXSelectedText means the selection is still there — Replace
    // proceeds. (nil, the Electron/Chromium case where AX exposes nothing, is the
    // default fake and is covered by the happy-path test above.)
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

    // When the app never copies on Cmd+C (changeCount never rises), the coordinator
    // must fall back to the focused element's selected text via Accessibility and
    // translate that, instead of giving up with a fetch-failure error.
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

    // The pasteboard is the primary path: when the copy lands, AX must never be
    // consulted, so a stale focused-element selection can't override the copy.
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

    // Both paths empty: clipboard never lands and AX exposes no selection — the
    // user must still get the fetch-failure error, not a silent no-op.
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

    // A whitespace-only AX selection is not translatable text; it must be treated
    // as no fallback (error), not streamed as an empty translation.
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

    // The AX fallback resolves the focused element ~480ms after the press. If the
    // user switched apps (Cmd+Tab) within that window, reading the now-focused
    // element would translate a different app's selection — so a changed frontmost
    // app must bail with the fetch error and never consult AX at all.
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

    // The mirror of the above: when the frontmost app is unchanged across the poll
    // window, the AX fallback is the legitimate source and must still translate.
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

    // emptyOrNonText means something WAS copied but it's blank — the AX fallback
    // is only for the "nothing copied" timeout, so it must not run here.
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

    // After the foreground translate lands, the background prefetch fills the other
    // verbs over the same selection (fix/summarize via run, reply via reply) so a
    // later switch is instant. Translate is never prefetched — it's the foreground.
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

    // The point of the cache: switching to a verb the prefetch already computed
    // replays the stored result instantly and never hits the model again.
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

    // A tone change alters the generation params for every verb, so the whole cache
    // must drop — proven by a subsequent switch having to re-run the model. Linger is
    // parked far out so the background prefetch can't muddy the run counts here.
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

    // A reword overwrites the .translate cache with the reworded text; undoing the
    // reword restores the original text in the popup but must also drop that cache
    // entry, or a later switch back to Translate would replay the discarded reword.
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
