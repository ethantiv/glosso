import Foundation
import AppKit
import Testing
@testable import Glosso

@MainActor
@Suite(.timeLimit(.minutes(1))) struct AppCoordinatorSpeechTests {
    private let clipboard = TestPasteboard()
    private let synth = FakeSpeechSynthesizer()
    private let player = FakeSpeechPlayer()
    private let recorder = FakeSpeechRecorder()
    private let notes = Locked<[String]>([])
    private let recording = Locked<[Bool]>([])

    private func makeCoordinator(llm: FakeLLMClient = FakeLLMClient(events: []), popup: FakePopup) -> AppCoordinator {
        let settings = SettingsStore(defaults: TestDefaults())
        settings.modelName = "test-model"
        let notes = self.notes, recording = self.recording
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
            narrator: Narrator(synthesizer: synth, player: player, voice: { .female }),
            recorder: recorder,
            transcriber: synth,
            onRecordingChange: { on in recording.update { $0.append(on) } }
        )
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<500 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: Popup read-aloud (US1)

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

    // MARK: Hold to talk (US3)

    @Test func silentTakeNotifiesAndTranslatesNothing() async {
        let llm = FakeLLMClient(events: [.token("x"), .finished(doneReason: "stop")])
        let popup = FakePopup()
        let coordinator = makeCoordinator(llm: llm, popup: popup)
        defer { coordinator.stop() }
        recorder.wav = SpeechAudioTests.wav(samples: Array(repeating: 0, count: 16_000))

        coordinator.handleSpeechStart()
        coordinator.handleSpeechEnd()
        await coordinator.speechTask?.value

        #expect(notes.value == [SpeechError.nothingHeard.userMessage])
        #expect(recording.value == [true, false])
        #expect(!popup.presented)
        #expect(synth.transcribedWavs.isEmpty)
        #expect(llm.recorder.runCount == 0)
    }

    @Test func spokenTakeIsTranscribedAndTranslatedInThePopup() async {
        let llm = FakeLLMClient(events: [.token("Good morning"), .finished(doneReason: "stop")])
        let popup = FakePopup()
        let coordinator = makeCoordinator(llm: llm, popup: popup)
        defer { coordinator.stop() }
        recorder.wav = SpeechAudioTests.wav(samples: SpeechAudioTests.tone(seconds: 0.6))
        synth.transcript = "Dzień dobry"

        coordinator.handleSpeechStart()
        coordinator.handleSpeechEnd()
        await coordinator.speechTask?.value
        await coordinator.captureTask?.value

        #expect(synth.transcribedWavs.count == 1)
        #expect(popup.presented)
        #expect(popup.presentedSourceText == "Dzień dobry")
        #expect(popup.tokens == ["Good morning"])
        #expect(llm.recorder.runActions.first == .translate)
        #expect(notes.value.isEmpty)
    }

    @Test func failedTranscriptionShowsTheErrorAndTranslatesNothing() async {
        let llm = FakeLLMClient(events: [.token("x"), .finished(doneReason: "stop")])
        let popup = FakePopup()
        let coordinator = makeCoordinator(llm: llm, popup: popup)
        defer { coordinator.stop() }
        recorder.wav = SpeechAudioTests.wav(samples: SpeechAudioTests.tone(seconds: 0.6))
        synth.transcribeError = SpeechError.server("boom")

        coordinator.handleSpeechStart()
        coordinator.handleSpeechEnd()
        await coordinator.speechTask?.value
        await coordinator.captureTask?.value

        #expect(popup.presented)
        #expect(popup.errorMessage == SpeechError.server("boom").userMessage)
        #expect(llm.recorder.runCount == 0)
    }

    @Test func deniedMicrophoneNotifiesOnce() async {
        let popup = FakePopup()
        let coordinator = makeCoordinator(popup: popup)
        defer { coordinator.stop() }
        recorder.startError = SpeechError.microphoneDenied

        coordinator.handleSpeechStart()
        coordinator.handleSpeechEnd()
        await coordinator.speechTask?.value

        #expect(notes.value == [SpeechError.microphoneDenied.userMessage])
        #expect(recording.value.isEmpty)
        #expect(recorder.stopCount == 0)
        #expect(!popup.presented)
    }
}
