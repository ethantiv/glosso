# Implementation Plan: Mowa w Glosso (lokalny model lfm3-audio)

**Branch**: `001-speech-lfm3-audio` | **Date**: 2026-10-28 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/001-speech-lfm3-audio/spec.md`

## Summary

Trzy funkcje na lokalnym modelu `lfm3-audio`: odsłuch wyniku z panelu (US1), „Czytaj na głos” w czytniku (US2) i tłumaczenie mowy pod przytrzymanym skrótem (US3). Mowa idzie przez endpointy Ollamy zgodne z OpenAI (`/v1/audio/speech`, `/v1/audio/transcriptions`), bo natywne API nie ma pól audio. Syntezę odtwarza `AVAudioEngine` strumieniowo, a nie `AVAudioPlayer`, żeby dźwięk zaczynał się po około 0,3 s. Rozpoznany tekst trafia do istniejącej ścieżki tłumaczenia. Szczegóły i odrzucone warianty: [research.md](research.md).

## Technical Context

**Language/Version**: Swift 6 (strict concurrency), Xcode 26

**Primary Dependencies**: AppKit, SwiftUI, AVFoundation (`AVAudioEngine`, `AVAudioPlayerNode`, `AVAudioRecorder`, `AVCaptureDevice`), NaturalLanguage. Bez nowych pakietów.

**Storage**: UserDefaults (dwa nowe ustawienia). Plik nagrania tylko w katalogu tymczasowym, usuwany od razu po odczycie.

**Testing**: Swift Testing (`Tests/`, offline): `MockURLProtocol`, fałszywe implementacje granic w `Tests/Support/CoordinatorFakes.swift`.

**Target Platform**: macOS 26+, Apple Silicon

**Project Type**: aplikacja paska menu (`LSUIElement`)

**Performance Goals**: pierwszy dźwięk z panelu < 1 s, z czytnika < 2 s; przerwy między fragmentami < 1 s; tłumaczenie mowy < 3 s po puszczeniu skrótu (model rozgrzany).

**Constraints**: mowa tylko lokalnie (FR-002); limit 4096 znaków na żądanie TTS; Ollama ≥ 0.40.12; podpis `Local Self-Signed` bez zmian; hardened runtime w Release wymaga uprawnienia `audio-input`.

**Scale/Scope**: jeden użytkownik; około 8 nowych plików źródłowych, 3 nowe suity testów.

## Constitution Check

`.specify/memory/constitution.md` to niewypełniony szablon. Bramki pochodzą więc z `CLAUDE.md` projektu:

| Bramka | Stan |
|---|---|
| Moduły rozmawiają tylko przez `Contracts.swift` | ✅ nowe protokoły `SpeechSynthesizing`, `SpeechTranscribing`, `SpeechRecording`, `SpeechPlaying` i rozszerzenia `HotkeyMonitor` i `TranslationPopupPresenting` są tam ([contracts/swift-seams.md](contracts/swift-seams.md)) |
| `think: false`, natywne `/api/generate` dla promptów | ✅ bez zmian; `/v1` tylko dla audio, bo innej drogi nie ma (R1) |
| `AppDelegate` wraca wcześnie pod XCTest | ✅ cały nowy kod składany jest po tej linii |
| Testy offline i deterministyczne, Swift Testing | ✅ HTTP przez `MockURLProtocol`, audio przez fałszywy `SpeechPlaying` |
| Teksty UI przez `loc()` | ✅ FR-006 |
| Prefetch tylko lokalnie, chmura bez zmian | ✅ mowa nie dotyka routingu dostawców |
| Podpis i TCC | ✅ identyczne; dochodzi wpis `NSMicrophoneUsageDescription` i uprawnienie `com.apple.security.device.audio-input` |
| Wersja | ✅ `MARKETING_VERSION` 0.26.2 → 0.27.0 (nowa funkcja) |

Po projekcie (Phase 1): bez naruszeń, Complexity Tracking pusty.

## Project Structure

### Documentation (this feature)

```text
specs/001-speech-lfm3-audio/
├── spec.md, feasibility.md
├── plan.md, research.md, data-model.md, quickstart.md
├── contracts/
│   ├── swift-seams.md
│   └── ollama-audio.md
└── tasks.md            # /speckit-tasks
```

### Source Code (repository root)

```text
Sources/
├── Core/Contracts.swift            # + protokoły mowy, SpeechPlaybackState, SpeechError, HotkeyMonitor/Popup
├── LLM/OllamaSpeechClient.swift    # NOWY: prepare/synthesize/transcribe (SpeechSynthesizing + SpeechTranscribing)
├── Speech/                         # NOWY moduł
│   ├── SpeechAudio.swift           #   czyste funkcje: chunks, voice, containsSpeech, PCM→Float
│   ├── Narrator.swift              #   kolejka fragmentów, wyłączność, stan
│   ├── PCMStreamPlayer.swift       #   SpeechPlaying na AVAudioEngine
│   └── MicrophoneRecorder.swift    #   SpeechRecording na AVAudioRecorder
├── Hotkey/GlobalHotkeyMonitor.swift      # + keyUp, akord mowy
├── Coordinator/AppCoordinator.swift      # + onToggleSpeech, przytrzymaj-i-mów
├── Coordinator/AppState.swift            # + recordingSpeech
├── Popup/{PopupModel,PopupView,TranslationPopupController}.swift  # + przycisk 🔊
├── Reader/{ReaderController,ReaderToolbar,ReaderTemplate}.swift   # + „Czytaj na głos”, glossoSpeakable()
├── Settings/{SettingsStore,SettingsView,KeyChordRecorder}.swift   # + speechChord, speechVoice
└── App/GlossoApp.swift                   # kompozycja, czerwona kropka nagrywania
project.yml                               # mikrofon: Info.plist + entitlements, 0.27.0
Tests/
├── SpeechAudioTests.swift, OllamaSpeechClientTests.swift, NarratorTests.swift   # NOWE
├── GlobalHotkeyMonitorTests.swift, AppCoordinatorTests.swift, SettingsStoreTests.swift  # rozszerzone
└── Support/CoordinatorFakes.swift        # + fałszywe granice mowy
```

**Structure Decision**: nowy katalog `Sources/Speech/` na logikę audio, która nie jest promptem ani czytnikiem. Klient HTTP leży obok `OllamaClient` w `Sources/LLM/` i dzieli z nim `endpointProvider` i `URLSession` (R2).

## Kluczowe decyzje projektu

1. **Strumień zamiast pliku.** `OllamaSpeechClient.synthesize` zwraca `AsyncThrowingStream<Data>` z buforów PCM po około 12 000 bajtów (0,25 s). Nieparzysty bajt przechodzi do następnego bufora. `Narrator` przekazuje bufory do `SpeechPlaying.enqueue`. Gdy jeden fragment skończy się generować, od razu pobiera następny tekst, chyba że w kolejce czeka już ponad 20 s dźwięku (ogranicza bufor przy pauzie).
2. **Czytnik** czyta stan z DOM przez nową funkcję JS `glossoSpeakable()`: tytuł i bloki po kolei, każdy jako `{text}` (przetłumaczony), `{pending:true}` albo pominięty. Źródło fragmentów w Swifcie idzie po indeksie bloku i odpytuje co 0,5 s, póki blok czeka na tłumaczenie (FR-022). Zamknięcie okna i `resetForArticle` wołają `narrator.stop()` (FR-023).
3. **Przytrzymaj i mów** w `AppCoordinator`: `onSpeechStart` → `transcriber.prepare` w tle (ładuje model w trakcie mówienia), `recorder.start()`, `onRecordingChange(true)`. `onSpeechEnd` → `stop()`, walidacja ciszy, `popup.present`, `transcriber.transcribe`, potem istniejące `stream(text, at:, action: .translate)`. Rozpoznany tekst trafia do panelu źródła przez `popup.update(sourceText:)` (FR-033). Puszczenie przed zakończeniem `start()` (okno zgody) kończy nagrywanie bez tłumaczenia.
4. **Panel**: przycisk 🔊 w nagłówku panelu wyniku (pasek ma limit szerokości pilnowany przez `PopupLayoutTests`), widoczny przy `canCopy` (FR-010). Błąd odsłuchu idzie do powiadomienia, żeby nie zastąpić wyniku. `AppCoordinator` łączy `onToggleSpeech` z `Narrator` i przekazuje stan przez `popup.setSpeech`. `onDismiss` zatrzymuje narrację należącą do panelu (FR-011).
5. **Błędy** są pokazywane tam, gdzie użytkownik patrzy: w panelu (`popup.showError`), w pasku stanu czytnika (`setStatus`) albo w powiadomieniu (przytrzymaj i mów bez panelu).

## Complexity Tracking

Brak naruszeń.
