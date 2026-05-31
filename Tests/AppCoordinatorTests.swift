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
            ax: FakeAccessibility(),
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

    @Test func timeoutReportsNothingSelected() async {
        let llm = FakeLLMClient()
        let reader = FakePasteboardReader()
        reader.readyAfterAttempts = nil   // never ready
        let popup = FakePopup()
        let coordinator = makeCoordinator(llm: llm, reader: reader, popup: popup)

        await coordinator.captureAndTranslate(baseline: 0, at: .zero)

        #expect(llm.recorder.receivedText == nil)
        #expect(popup.errorMessage == "Nic nie zaznaczono do tłumaczenia.")
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
