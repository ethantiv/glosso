import AVFoundation

/// Plays the speech model's PCM stream as it arrives. `AVAudioPlayer` would need the whole file first — seconds of
/// silence on a long answer — and the stream's WAV header carries placeholder sizes it can't trust.
@MainActor
final class PCMStreamPlayer: SpeechPlaying {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: Double(SpeechAudio.sampleRate), channels: 1)!
    private var attached = false
    private var paused = false
    private var pendingBuffers = 0
    /// Bumped by `stop()`, so completions of buffers it discarded don't count against the next session.
    private var generation = 0
    private var drainWaiters: [CheckedContinuation<Void, Never>] = []

    private(set) var queuedDuration: TimeInterval = 0

    func enqueue(_ pcm: Data) {
        let samples = SpeechAudio.floatSamples(pcm)
        guard !samples.isEmpty, startEngine(),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }

        let duration = Double(samples.count) / Double(SpeechAudio.sampleRate)
        let generation = self.generation
        pendingBuffers += 1
        queuedDuration += duration
        // @Sendable keeps the closure off the main actor: AVFoundation calls it on its own render thread.
        // The player is app-lifetime, so the strong capture costs nothing.
        node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { @Sendable _ in
            Task { @MainActor in self.played(duration, generation: generation) }
        }
        if !paused, !node.isPlaying { node.play() }
    }

    func drain() async {
        guard pendingBuffers > 0 else { return }
        await withCheckedContinuation { drainWaiters.append($0) }
    }

    // Every node call is guarded by `attached`: AVAudioPlayerNode raises an exception when used outside an engine,
    // and the narrator calls `stop()` before anything was ever queued.
    func pause() {
        paused = true
        if attached { node.pause() }
    }

    func resume() {
        paused = false
        if pendingBuffers > 0 { node.play() }
    }

    func stop() {
        generation += 1
        paused = false
        pendingBuffers = 0
        queuedDuration = 0
        if attached { node.stop() }
        idle()
    }

    private func played(_ duration: TimeInterval, generation: Int) {
        guard generation == self.generation else { return }
        pendingBuffers -= 1
        queuedDuration = max(0, queuedDuration - duration)
        if pendingBuffers == 0 {
            queuedDuration = 0
            idle()
        }
    }

    /// Releases the output device between sessions instead of keeping it open for the app's lifetime.
    private func idle() {
        if engine.isRunning { engine.pause() }
        let waiters = drainWaiters
        drainWaiters = []
        waiters.forEach { $0.resume() }
    }

    private func startEngine() -> Bool {
        if !attached {
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            attached = true
        }
        if engine.isRunning { return true }
        do {
            try engine.start()
            return true
        } catch {
            return false
        }
    }
}
