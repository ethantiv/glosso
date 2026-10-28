import Foundation
import NaturalLanguage
import Testing
@testable import Glosso

@MainActor
@Suite(.timeLimit(.minutes(1))) struct NarratorTests {
    private let synth = FakeSpeechSynthesizer()
    private let player = FakeSpeechPlayer()

    private func makeNarrator(voice: SpeechVoice = .female) -> Narrator {
        Narrator(synthesizer: synth, player: player, voice: { voice })
    }

    /// Hands out `texts` one per call, then nil.
    private func source(_ texts: [String]) -> @MainActor () async -> String? {
        let queue = Locked(texts)
        return {
            var next: String?
            queue.update { if !$0.isEmpty { next = $0.removeFirst() } }
            return next
        }
    }

    @Test func readsChunksInOrderWithAVoicePerLanguage() async {
        let narrator = makeNarrator(voice: .male)
        let states = Locked<[SpeechPlaybackState]>([])
        let done = StreamGate()
        narrator.start(
            next: source(["Dzień dobry, to jest pierwsze zdanie po polsku.",
                          "Good morning, this is the second sentence in English."]),
            onState: { state in
                states.update { $0.append(state) }
                if state == .idle { done.release() }
            },
            onError: { _ in Issue.record("unexpected error") })
        await done.wait()

        #expect(synth.texts.count == 2)
        #expect(synth.voices == ["male-polish", "male-american-english"])
        #expect(player.enqueued.count == 2)
        #expect(states.value == [.preparing(nil), .playing, .idle])
    }

    @Test func sessionLanguageFixesTheVoice() async {
        let narrator = makeNarrator()
        let done = StreamGate()
        narrator.start(
            language: .polish,
            next: source(["OK.", "Good morning, this English line still belongs to a Polish article."]),
            onState: { state in if state == .idle { done.release() } },
            onError: { _ in Issue.record("unexpected error") })
        await done.wait()

        #expect(synth.voices == ["female-polish", "female-polish"])
    }

    @Test func aNewSessionEndsThePreviousOne() async {
        let narrator = makeNarrator()
        synth.gate = StreamGate()  // never opens: the first session stays mid-chunk
        let first = Locked<[SpeechPlaybackState]>([])
        narrator.start(next: source(["Pierwszy tekst."]),
                       onState: { state in first.update { $0.append(state) } },
                       onError: { _ in Issue.record("unexpected error") })

        let done = StreamGate()
        narrator.start(next: source([]),
                       onState: { state in if state == .idle { done.release() } },
                       onError: { _ in Issue.record("unexpected error") })

        #expect(first.value == [.preparing(nil), .idle])
        await done.wait()
        #expect(player.stopCount >= 1)
    }

    @Test func pauseAndResumeReachThePlayer() async {
        let narrator = makeNarrator()
        let hold = StreamGate()
        let calls = Locked(0)
        let playing = StreamGate()
        let done = StreamGate()
        narrator.start(
            next: {
                calls.update { $0 += 1 }
                if calls.value == 1 { return "Tekst do przeczytania." }
                await hold.wait()
                return nil
            },
            onState: { state in
                if state == .playing { playing.release() }
                if state == .idle { done.release() }
            },
            onError: { _ in Issue.record("unexpected error") })
        await playing.wait()

        narrator.pause()
        #expect(narrator.state == .paused)
        #expect(player.pauseCount == 1)
        narrator.resume()
        #expect(narrator.state == .playing)
        #expect(player.resumeCount == 1)

        hold.release()
        await done.wait()
    }

    @Test func synthesisErrorIsReportedAndEndsTheSession() async {
        let narrator = makeNarrator()
        synth.synthesizeError = SpeechError.server("boom")
        let done = StreamGate()
        let message = Locked<String?>(nil)
        narrator.start(next: source(["Tekst."]),
                       onState: { state in if state == .idle { done.release() } },
                       onError: { text in message.set(text) })
        await done.wait()

        #expect(message.value == SpeechError.server("boom").userMessage)
        #expect(narrator.state == .idle)
    }

    @Test func stopIsSilent() async {
        let narrator = makeNarrator()
        synth.gate = StreamGate()
        let states = Locked<[SpeechPlaybackState]>([])
        narrator.start(next: source(["Tekst."]),
                       onState: { state in states.update { $0.append(state) } },
                       onError: { _ in Issue.record("stop must not report an error") })
        narrator.stop()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(states.value == [.preparing(nil), .idle])
        #expect(narrator.state == .idle)
    }
}
