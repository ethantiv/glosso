import AVFoundation

/// Hold-to-talk capture: 16 kHz mono 16-bit WAV, the rate the speech model's encoder runs at, into a temp file that
/// lives only until `stop()` reads it back.
@MainActor
final class MicrophoneRecorder: SpeechRecording {
    static let maxDuration: TimeInterval = 120

    private var recorder: AVAudioRecorder?
    private var fileURL: URL?

    func start() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .audio) else { throw SpeechError.microphoneDenied }
        default:
            throw SpeechError.microphoneDenied
        }
        discard()
        let url = FileManager.default.temporaryDirectory.appending(path: "glosso-speech-\(UUID().uuidString).wav")
        let recorder = try AVAudioRecorder(url: url, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ])
        fileURL = url
        // The duration cap stops the take on its own; the key's release still decides when it is processed.
        guard recorder.record(forDuration: Self.maxDuration) else {
            discard()
            throw CocoaError(.fileWriteUnknown)
        }
        self.recorder = recorder
    }

    func stop() -> Data? {
        defer { discard() }
        guard let recorder else { return nil }
        recorder.stop()
        return fileURL.flatMap { try? Data(contentsOf: $0) }
    }

    private func discard() {
        recorder?.stop()
        recorder = nil
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
        fileURL = nil
    }
}
