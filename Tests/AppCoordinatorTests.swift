import Foundation
import CoreGraphics
import Testing
@testable import TranslatorMenuBar

@MainActor
@Suite struct AppCoordinatorTests {
    private func makeSettings(model: String = "test-model", second: SecondLanguage = .english) -> SettingsStore {
        let defaults = UserDefaults(suiteName: "AppCoordinatorTests-\(UUID().uuidString)")!
        let store = SettingsStore(defaults: defaults)
        store.modelName = model
        store.secondLanguage = second
        return store
    }

    private func makeCoordinator(
        llm: FakeLLMClient,
        reader: any PasteboardReading,
        popup: FakePopup,
        settings: SettingsStore? = nil,
        axReader: any AXSelectionReading = FakeAXSelectionReader()
    ) -> AppCoordinator {
        AppCoordinator(
            llm: llm,
            monitor: FakeHotkeyMonitor(),
            reader: reader,
            axReader: axReader,
            popup: popup,
            settings: settings ?? makeSettings(),
            pollStepMs: 1,
            pollMaxAttempts: 5
        )
    }

    @Test func translatesOnceClipboardBecomesReady() async {
        let llm = FakeLLMClient(events: [.token("He"), .token("llo"), .finished(doneReason: "stop")])
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = 2   // first two polls report nothing yet
        reader.text = "Dzień dobry"
        let popup = FakePopup()
        let settings = makeSettings(model: "test-model", second: .english)
        let coordinator = makeCoordinator(llm: llm, reader: reader, popup: popup, settings: settings)

        await coordinator.captureAndTranslate(baseline: 0, at: .zero)

        #expect(llm.recorder.receivedText == "Dzień dobry")
        // The coordinator must thread the persisted model + second language into
        // the translate call and mirror the same language in the arrow.
        #expect(llm.recorder.receivedModel == "test-model")
        #expect(llm.recorder.receivedSecond == .english)
        #expect(popup.presented)
        #expect(popup.presentedDirection == .fromPolish(.english))
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
    // wiring, dismissing the popup (Esc / outside-click) would not stop the stream.
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

    // An AX revocation calls stop() while a popup may be on screen; its
    // Esc/outside-click monitors are AX-gated and die with the revocation, so
    // stop() must dismiss the popup itself or it orphans with a stuck spinner.
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
}
