import Foundation
import AppKit
import Testing
@testable import Glosso

@MainActor
@Suite(.timeLimit(.minutes(1))) struct AppCoordinatorSpeechTests {
    private let clipboard = TestPasteboard()
    private let synth = FakeSpeechSynthesizer()
    private let player = FakeSpeechPlayer()
    private let notes = Locked<[String]>([])

    private func makeCoordinator(llm: FakeLLMClient = FakeLLMClient(events: []), popup: FakePopup) -> AppCoordinator {
        let settings = SettingsStore(defaults: TestDefaults())
        settings.modelName = "test-model"
        let notes = self.notes
        return AppCoordinator(
            llm: llm,
            monitor: FakeHotkeyMonitor(),
            reader: FakeEmptyPasteboardReader(),
            axReader: FakeAXSelectionReader(),
            popup: popup,
            settings: settings,
            pollStepMs: 1,
            pollMaxAttempts: 5,
            prefetchLingerMs: 0,
            frontmostBundleID: { "com.apple.TextEdit" },
            pasteboard: clipboard.value,
            notify: { message in notes.update { $0.append(message) } },
            narrator: Narrator(synthesizer: synth, player: player, voice: { .female })
        )
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<500 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func speakerReadsTheResultAndGoesIdle() async {
        let popup = FakePopup()
        let coordinator = makeCoordinator(popup: popup)
        defer { coordinator.stop() }

        popup.onToggleSpeech?("Dzień dobry. To jest wynik tłumaczenia.")
        await waitUntil { popup.speechStates.last == .idle }

        #expect(synth.texts == ["Dzień dobry. To jest wynik tłumaczenia."])
        #expect(popup.speechStates == [.preparing(nil), .playing, .idle])
        #expect(player.enqueued.count == 1)
    }

    @Test func secondClickStopsReading() async {
        let popup = FakePopup()
        let coordinator = makeCoordinator(popup: popup)
        defer { coordinator.stop() }
        synth.gate = StreamGate()

        popup.onToggleSpeech?("Długi tekst do przeczytania.")
        popup.onToggleSpeech?("Długi tekst do przeczytania.")

        #expect(popup.speechStates == [.preparing(nil), .idle])
        #expect(player.stopCount >= 1)
    }

    @Test func dismissingThePopupStopsReading() async {
        let popup = FakePopup()
        let coordinator = makeCoordinator(popup: popup)
        defer { coordinator.stop() }
        synth.gate = StreamGate()
        popup.present(at: .zero, formality: .automatic)

        popup.onToggleSpeech?("Tekst.")
        popup.dismiss()

        #expect(popup.speechStates.last == .idle)
    }
}
