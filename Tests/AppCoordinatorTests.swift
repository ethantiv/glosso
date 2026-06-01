import Foundation
import CoreGraphics
import Testing
@testable import TranslatorMenuBar

@MainActor
@Suite struct AppCoordinatorTests {
    private func makeCoordinator(
        llm: FakeLLMClient,
        reader: any PasteboardReading,
        popup: FakePopup
    ) -> AppCoordinator {
        AppCoordinator(
            llm: llm,
            monitor: FakeHotkeyMonitor(),
            reader: reader,
            popup: popup,
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
        let coordinator = makeCoordinator(llm: llm, reader: reader, popup: popup)

        await coordinator.captureAndTranslate(baseline: 0, at: .zero)

        #expect(llm.recorder.receivedText == "Dzień dobry")
        #expect(popup.presented)
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

    @Test func newDoubleCopyDismissesThePreviousPopup() async {
        let llm = FakeLLMClient()
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = 0
        let popup = FakePopup()
        let coordinator = makeCoordinator(llm: llm, reader: reader, popup: popup)

        await coordinator.captureAndTranslate(baseline: 0, at: .zero)
        #expect(popup.presented)

        coordinator.handleDoubleCopy(baseline: 0)

        #expect(popup.dismissCount == 1)
    }

    @Test func cancelledStreamDoesNotShowErrorOnNewPopup() async {
        let llm = FakeLLMClient(events: [], error: .cancelled)
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = 0
        reader.text = "Dzień dobry"
        let popup = FakePopup()
        let coordinator = makeCoordinator(llm: llm, reader: reader, popup: popup)

        await coordinator.captureAndTranslate(baseline: 0, at: .zero)

        #expect(popup.presented)
        #expect(popup.errorMessage == nil)
    }

    @Test func stopHaltsTheMonitor() {
        let monitor = FakeHotkeyMonitor()
        let coordinator = AppCoordinator(
            llm: FakeLLMClient(),
            monitor: monitor,
            reader: FakePasteboardReader(),
            popup: FakePopup()
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
}
