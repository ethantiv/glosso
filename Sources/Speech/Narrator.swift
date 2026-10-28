import Foundation
import NaturalLanguage

/// Reads text aloud chunk by chunk. One instance serves the whole app, so a new session always ends the previous one
/// — the popup and the reader never talk over each other.
@MainActor
final class Narrator {
    /// Generation runs ~4× faster than playback; past this much queued audio, wait instead of fetching more text,
    /// so a paused article doesn't synthesize itself to the end in the background.
    static let lookahead: TimeInterval = 20

    private let synthesizer: any SpeechSynthesizing
    private let player: any SpeechPlaying
    private let voice: @MainActor () -> SpeechVoice
    private var task: Task<Void, Never>?
    private var session = 0
    private var onState: (@MainActor (SpeechPlaybackState) -> Void)?

    private(set) var state: SpeechPlaybackState = .idle {
        didSet { if state != oldValue { onState?(state) } }
    }

    init(synthesizer: any SpeechSynthesizing, player: any SpeechPlaying, voice: @escaping @MainActor () -> SpeechVoice) {
        self.synthesizer = synthesizer
        self.player = player
        self.voice = voice
    }

    /// `next` hands out the text to read, one chunk per call, and nil at the end; it may wait (the reader waits for
    /// a block still being translated).
    /// `language` fixes the voice for the whole session; a short chunk ("OK.", a quoted name) misdetected on its own
    /// would otherwise switch accents mid-text. nil detects per chunk.
    func start(language: NLLanguage? = nil,
               next: @escaping @MainActor () async -> String?,
               onState: @escaping @MainActor (SpeechPlaybackState) -> Void,
               onError: @escaping @MainActor (String) -> Void) {
        stop()
        session += 1
        let id = session
        self.onState = onState
        state = .preparing(nil)
        task = Task { @MainActor [weak self] in
            await self?.run(id: id, language: language, next: next, onError: onError)
        }
    }

    func pause() {
        guard state == .playing else { return }
        player.pause()
        state = .paused
    }

    func resume() {
        guard state == .paused else { return }
        player.resume()
        state = .playing
    }

    /// Ends the session; its owner hears `.idle` once more.
    func stop() {
        task?.cancel()
        task = nil
        player.stop()
        state = .idle
        onState = nil
    }

    private func run(id: Int, language: NLLanguage?, next: @MainActor () async -> String?, onError: @MainActor (String) -> Void) async {
        do {
            // Strong capture is fine: the closure lives only as long as this `prepare` call.
            try await synthesizer.prepare { @Sendable progress in
                Task { @MainActor in
                    guard self.session == id, case .preparing = self.state else { return }
                    self.state = .preparing(progress)
                }
            }
            while let text = await next() {
                try Task.checkCancellation()
                for try await pcm in synthesizer.synthesize(text, voice: SpeechAudio.voice(
                    language: language ?? NLLanguageRecognizer.dominantLanguage(for: text), gender: voice())) {
                    try Task.checkCancellation()
                    player.enqueue(pcm)
                    if case .preparing = state { state = .playing }
                }
                while player.queuedDuration > Self.lookahead {
                    try await Task.sleep(for: .milliseconds(250))
                }
            }
            try Task.checkCancellation()
            await player.drain()
            try Task.checkCancellation()
            finish(id)
        } catch {
            guard session == id, !Task.isCancelled else { return }
            player.stop()
            finish(id)
            if case TranslationError.cancelled = error { return }
            onError((error as? SpeechError)?.userMessage
                    ?? (error as? TranslationError)?.userMessage
                    ?? loc("Nie udało się odczytać tekstu na głos.", "Couldn't read the text aloud."))
        }
    }

    private func finish(_ id: Int) {
        guard session == id else { return }
        task = nil
        state = .idle
        onState = nil
    }
}
