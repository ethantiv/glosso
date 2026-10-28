# Kontrakt: nowe granice w `Sources/Core/Contracts.swift`

Moduły rozmawiają tylko przez ten plik, a testy podstawiają fałszywe implementacje na tych granicach.

```swift
/// The local speech model's text-to-speech side; audio arrives as raw 16-bit LE mono PCM at `SpeechAudio.sampleRate`.
protocol SpeechSynthesizing: Sendable {
    /// Engine version check, on-demand model pull (progress 0…1, nil when nothing downloads), preload with keep_alive.
    func prepare(progress: @escaping @Sendable (Double?) -> Void) async throws
    func synthesize(_ text: String, voice: String) -> AsyncThrowingStream<Data, Error>
}

/// The same model's speech-to-text side.
protocol SpeechTranscribing: Sendable {
    func prepare(progress: @escaping @Sendable (Double?) -> Void) async throws
    func transcribe(wav: Data) async throws -> String
}

/// Microphone capture for hold-to-talk; asks for permission on first use.
@MainActor
protocol SpeechRecording: AnyObject {
    func start() async throws          // throws SpeechError.microphoneDenied
    func stop() -> Data?               // WAV, nil when nothing was captured; the temp file is gone afterwards
}

/// Gapless playback of streamed PCM.
@MainActor
protocol SpeechPlaying: AnyObject {
    func enqueue(_ pcm: Data)
    var queuedDuration: TimeInterval { get }   // scheduled but not yet played
    func drain() async                          // returns when everything played, or after stop()
    func pause()
    func resume()
    func stop()
}
```

Zmiany w istniejących granicach:

- `HotkeyMonitor`: `onSpeechStart` i `onSpeechEnd` (`(@MainActor () -> Void)?`).
- `TranslationPopupPresenting`: `onToggleSpeech: (@MainActor (_ text: String) -> Void)?` i `func setSpeech(_ state: SpeechPlaybackState)`.
- Nowy typ wartości `enum SpeechPlaybackState: Equatable { case idle, preparing(Double?), playing, paused }` i `enum SpeechError` (patrz data-model.md), oba w `Contracts.swift`.

`Narrator` (`Sources/Speech/Narrator.swift`) nie jest granicą. To konkretna klasa `@MainActor`, która składa `SpeechSynthesizing` i `SpeechPlaying`. Popup (przez `AppCoordinator`) i czytnik dostają ją w konstruktorze.

```swift
@MainActor final class Narrator {
    func start(next: @escaping @MainActor () async -> String?,
               onState: @escaping @MainActor (SpeechPlaybackState) -> Void,
               onError: @escaping @MainActor (String) -> Void)
    func pause(); func resume(); func stop()
}
```
