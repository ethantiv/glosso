---
description: "Task list for Mowa w Glosso (lokalny model lfm3-audio)"
---

# Tasks: Mowa w Glosso (lokalny model lfm3-audio)

**Input**: Design documents from `specs/001-speech-lfm3-audio/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Wymagane przez konwencje projektu (`CLAUDE.md`: offline, Swift Testing, fałszywe implementacje na granicach `Contracts.swift`). Zadania testowe stoją przy kodzie, który sprawdzają.

**Organization**: Zadania są pogrupowane według historii użytkownika.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: można robić równolegle (inne pliki, brak zależności)
- **[Story]**: US1, US2, US3 ze spec.md

---

## Phase 1: Setup

**Purpose**: Uprawnienia, wersja i nowy katalog źródeł

- [X] T001 W `project.yml` dodaj do `info.properties` klucz `NSMicrophoneUsageDescription` („Glosso słucha mikrofonu tylko, gdy przytrzymujesz skrót mowy. / Glosso listens only while you hold the speech shortcut.”), do `entitlements.properties` klucz `com.apple.security.device.audio-input: true` (hardened runtime w Release, research R8) i zmień `MARKETING_VERSION` na `"0.27.0"`.
- [X] T002 Utwórz katalog `Sources/Speech/`. XcodeGen włącza go automatycznie przez wpis `path: Sources`.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Granice, czyste funkcje audio, klient HTTP, odtwarzacz i narrator, wspólne dla US1 i US2. US3 potrzebuje z nich tylko klienta i granic.

- [X] T003 W `Sources/Core/Contracts.swift` dodaj `SpeechPlaybackState` (`idle`, `preparing(Double?)`, `playing`, `paused`; `Equatable`, `Sendable`), `SpeechError` (`engineTooOld(String)`, `microphoneDenied`, `nothingHeard`, `server(String)`) z `userMessage` przez `loc()` (teksty z data-model.md), protokoły `SpeechSynthesizing`, `SpeechTranscribing`, `SpeechRecording`, `SpeechPlaying` dokładnie wg `contracts/swift-seams.md`, rozszerz `HotkeyMonitor` o `onSpeechStart`/`onSpeechEnd`, a `TranslationPopupPresenting` o `onToggleSpeech` i `setSpeech(_:)`.
- [X] T004 [P] Utwórz `Sources/Speech/SpeechAudio.swift` (`enum SpeechAudio`): stałe `sampleRate = 24_000`, `speechModel = "lfm3-audio"`, `minimumEngineVersion = [0, 40, 12]`; `chunks(_ text:) -> [String]` (zdania sklejane do „≤ 400 znaków”, dłuższe zdanie dzielone na spacjach; puste i same białe znaki pominięte; adresy `http(s)://…` usuwane przed podziałem, bo czytane na głos są bezużyteczne); `voice(for text:, gender: SpeechVoice) -> String` (`NLLanguageRecognizer` → `female-polish`, `male-american-english` itd.; nieznany język → sama płeć); `containsSpeech(wav:) -> Bool` (parsuje kawałki RIFF do `data`, 16-bit LE mono; „długość ≥ 0,5 s” i „najgłośniejsze okno 50 ms z RMS ≥ 0,01”); `isSupported(version:) -> Bool` (porównanie numeryczne, sufiksy ignorowane); `floatSamples(_ pcm: Data) -> [Float]`. Tu też `enum SpeechVoice: String, CaseIterable { case female, male }` z `displayName` przez `loc()`.
- [X] T005 [P] Utwórz `Tests/SpeechAudioTests.swift`: `chunks` (granice zdań, limit 400, długie zdanie bez kropek, pusty tekst, usunięty URL), `voice` (PL, EN, rosyjski → sama płeć), `containsSpeech` (cisza, za krótki ton, ton 0,6 s, WAV z dodatkowym kawałkiem `FLLR`), `isSupported` (`0.40.12` tak, `0.40.11` nie, `0.41.0-rc1` tak, `garbage` nie), `floatSamples` (Int16.min/max → −1/~1).
- [X] T006 Utwórz `Sources/LLM/OllamaSpeechClient.swift` (`final class`, `SpeechSynthesizing & SpeechTranscribing`; `init(session:, endpointProvider:, modelManager: any ModelManaging, keepAliveProvider:, onDownload: @Sendable () -> Void)`). Baza = `endpointProvider()` bez dwóch ostatnich komponentów. `prepare`: `GET /api/version` → `SpeechError.engineTooOld` gdy `!isSupported`; `POST /api/show` 404 → `onDownload()` i `modelManager.pull` z postępem `completed/total`; potem rozgrzanie `POST /api/generate {"model","keep_alive"}` (błędy ignorowane). `synthesize`: `POST /v1/audio/speech` z `"response_format":"pcm"`, strumień `URLSession.bytes` cięty na bufory po 12 000 bajtów (parzysta liczba bajtów, reszta do następnego bufora). `transcribe`: multipart `model` + `file` (`audio/wav`), dekoduje `{"text"}`. Błędy wg `contracts/ollama-audio.md`: koperta `error.message` albo `error` string → `SpeechError.server`; błędy sieci → `TranslationError.ollamaUnreachable`; anulowanie → `TranslationError.cancelled`.
- [X] T007 [P] Utwórz `Tests/OllamaSpeechClientTests.swift` (`MockURLProtocol`, `HTTPFixture`): ciało żądania syntezy (model, voice, `pcm`), sklejanie buforów i nieparzysty bajt, 400 z kopertą OpenAI → `.server(message)`, `transcribe` wysyła multipart z `model` i plikiem i zwraca `text`, `prepare` przy wersji 0.40.11 → `.engineTooOld`, `prepare` przy 404 z `/api/show` woła `pull` w fałszywym `ModelManaging` i `onDownload`, rozgrzanie wysyła `keep_alive`.
- [X] T008 Utwórz `Sources/Speech/Narrator.swift` (`@MainActor final class Narrator`, `init(synthesizer: any SpeechSynthesizing, player: any SpeechPlaying, voice: @MainActor () -> SpeechVoice)`): `start(next:onState:onError:)` kończy poprzednią sesję (jej `onState(.idle)`), woła `prepare` (stan `.preparing(progress)`), potem dla każdego tekstu z `next()` przesyła bufory z `synthesize(text, voice: SpeechAudio.voice(for:gender:))` do `player.enqueue`; stan `.playing` po pierwszym buforze; nie pobiera kolejnego tekstu, gdy `queuedDuration > 20`; po `nil` z `next()` czeka na `player.drain()` i kończy `.idle`. `pause`/`resume` przełączają gracz i stan; `stop()` anuluje zadanie, zatrzymuje gracz, `.idle`. Błąd → `onError(message)` (`SpeechError`/`TranslationError.userMessage`) i `.idle`; anulowanie bez komunikatu.
- [X] T009 [P] Utwórz `Sources/Speech/PCMStreamPlayer.swift` (`SpeechPlaying`): `AVAudioEngine` + `AVAudioPlayerNode`, format Float32 24 kHz mono, `enqueue` zamienia PCM przez `SpeechAudio.floatSamples` na `AVAudioPCMBuffer` i planuje go z callbackiem `.dataPlayedBack`, który zmniejsza `queuedDuration` na MainActor; `drain()` czeka, aż `queuedDuration` spadnie do zera albo przyjdzie `stop()`; silnik startuje leniwie przy pierwszym `enqueue`.
- [X] T010 Dodaj do `Tests/Support/CoordinatorFakes.swift`: `FakeSpeechSynthesizer` (zapis tekstów i głosów, konfigurowalne bufory i błąd, licznik `prepare`), `FakeSpeechPlayer` (zapis buforów, `pause`/`resume`/`stop`, `drain` natychmiast), `FakeSpeechTranscriber`, `FakeSpeechRecorder` (konfigurowalny WAV albo błąd); `FakeHotkeyMonitor` i `FakePopup` dostają nowe właściwości z T003 (`setSpeech` zapisuje ostatni stan).
- [X] T011 Utwórz `Tests/NarratorTests.swift`: fragmenty grają po kolei i każdy dostaje głos wg języka; drugi `start` wysyła pierwszej sesji `.idle` (FR-004); `pause`/`resume` przechodzą do gracza i zmieniają stan; błąd syntezy → `onError` i `.idle`; `stop` w trakcie → `.idle` bez `onError`.
- [X] T012 W `Sources/Settings/SettingsStore.swift` dodaj `speechVoice: SpeechVoice` (klucz `speech.voice`, domyślnie `.female`) i `speechChord: KeyChord?` (klucz `shortcut.speech`, JSON, domyślnie `nil`; `nil` usuwa klucz). Testy w `Tests/SettingsStoreTests.swift`: wartości domyślne, zapis i odczyt, wyczyszczenie akordu.
- [X] T013 W `Sources/App/GlossoApp.swift` złóż (po strażniku XCTest) jeden `OllamaSpeechClient` (`endpointProvider(engine)`, `modelManager`, `keepAliveProvider` z `settings.keepAlive`, `onDownload` → `SystemUserNotifier.post` „Pobieram model mowy (około 2 GB)…”) i jeden `Narrator` z `PCMStreamPlayer`, przekaż je do `AppCoordinator` (oba) i `ReaderController`.

**Checkpoint**: granice, klient i narrator gotowe i przetestowane.

---

## Phase 3: User Story 1 - Odsłuch tłumaczenia z panelu (Priority: P1) 🎯 MVP

**Goal**: przycisk 🔊 w panelu czyta wynik na głos w jego języku.

**Independent Test**: przetłumacz zdanie z `docs/test-sentences.txt`, kliknij 🔊, potem kliknij jeszcze raz albo Esc.

- [X] T014 [P] [US1] W `Sources/Popup/PopupModel.swift` dodaj `speech: SpeechPlaybackState = .idle`, zerowane w `TranslationPopupController.resetTranslationPane`.
- [X] T015 [US1] W `Sources/Popup/PopupView.swift` dodaj parametr `toggleSpeech: () -> Void` i przycisk w nagłówku panelu wyniku (miejsce wskaźnika postępu; pasek ma limit szerokości z `PopupLayoutTests`), widoczny przy `canCopy` (FR-010, FR-012): ikona `speaker.wave.2` (idle), `stop.fill` (playing/paused), `ProgressView` z wartością przy `.preparing(p)` i nieokreślony przy `nil`; etykieta i `.help` przez `loc("Czytaj na głos", "Read aloud")` / `loc("Zatrzymaj czytanie", "Stop reading")`.
- [X] T016 [US1] W `Sources/Popup/TranslationPopupController.swift` dodaj `onToggleSpeech`, przekaż `toggleSpeech: { self.onToggleSpeech?(self.model.text) }` do `PopupView`, zaimplementuj `setSpeech(_:)` (ustawia `model.speech`).
- [X] T017 [US1] W `Sources/Coordinator/AppCoordinator.swift` dodaj parametr `narrator: Narrator?` (domyślnie `nil`); `popup.onToggleSpeech`: gdy panel czyta (`speechOwned`), `narrator.stop()`, inaczej `narrator.start` z kolejnymi `SpeechAudio.chunks(text)`, `onState` → `popup.setSpeech`, `onError` → powiadomienie (`notify`), żeby nie zastąpić wyniku; `popup.onDismiss` i każde nowe przechwycenie/`restartTranslation` zatrzymują narrację należącą do panelu (FR-011, edge case „nowe tłumaczenie”).
- [X] T018 [US1] Testy w `Tests/AppCoordinatorSpeechTests.swift`: `onToggleSpeech` czyta tekst przez `FakeSpeechSynthesizer` i ustawia stany w `FakePopup`; drugie wywołanie zatrzymuje; `onDismiss` zatrzymuje narrację.

**Checkpoint**: US1 działa samodzielnie (MVP).

---

## Phase 4: User Story 2 - „Czytaj na głos” w czytniku (Priority: P2)

**Goal**: czytanie przetłumaczonego artykułu fragmentami z pauzą, wznowieniem i stopem.

**Independent Test**: długi artykuł w czytniku → „Czytaj na głos”; pierwszy dźwięk < 2 s, pauza, wznowienie, „Zatrzymaj”, zamknięcie okna.

- [X] T019 [P] [US2] W `Sources/Reader/ReaderTemplate.swift` dodaj JS `glossoSpeakable()`: JSON `{title, blocks:[…]}`; `title` = przetłumaczony tytuł albo `null`, gdy jeszcze nie ma; każdy blok w kolejności `data-glosso-id`: `{"text": …}` gdy jest w `glosso.translated` (tekst przez `textContent` tymczasowego elementu), `{"pending": true}` gdy w `glosso.pending`, inaczej `{}` (pomiń). Test w `Tests/ReaderTemplateTests.swift`: skrypt zawiera `function glossoSpeakable(`.
- [X] T020 [P] [US2] W `Sources/Reader/ReaderToolbar.swift` dodaj `.glossoSpeak` do `itemIdentifiers` (przed `.glossoChat`) jako `NSMenuToolbarItem`: główne kliknięcie → `controller?.toggleReadAloud()`, menu z „Zatrzymaj” / „Stop” → `controller?.stopReadAloud()`; `speakItem` jak pozostałe. Popraw `Tests/ReaderToolbarTests.swift`, jeśli sprawdza listę identyfikatorów.
- [X] T021 [US2] W `Sources/Reader/ReaderController.swift`: parametr `narrator: Narrator?` w `init`; `toggleReadAloud()` (idle → start, playing → pause, paused → resume), `stopReadAloud()`; źródło fragmentów: tytuł (gdy jeszcze `null`, a tłumaczenie trwa, czekaj jak na blok `pending`; po końcu tłumaczenia bez tytułu pomiń), potem bloki po indeksie z `glossoSpeakable()`, każdy blok przez `SpeechAudio.chunks`; blok `pending` → czekaj 0,5 s i pytaj ponownie, póki trwa tłumaczenie (`translating`), inaczej pomiń (FR-022); `onState` zmienia ikonę i etykietę `speakItem` (`speaker.wave.2` „Czytaj na głos”, `pause.fill` „Wstrzymaj”, `play.fill` „Wznów”, postęp pobierania w `setStatus`); `onError` → `setStatus`. `resetForArticle` i zamknięcie okna wołają `stopReadAloud()` (FR-023).

**Checkpoint**: US1 i US2 działają niezależnie.

---

## Phase 5: User Story 3 - Tłumaczenie mowy (Priority: P3)

**Goal**: przytrzymaj skrót, powiedz, puść → tłumaczenie w panelu.

**Independent Test**: przypisz skrót w Ustawieniach, przytrzymaj, przeczytaj zdanie, puść.

- [X] T022 [P] [US3] Utwórz `Sources/Speech/MicrophoneRecorder.swift` (`SpeechRecording`): `start()` sprawdza `AVCaptureDevice.authorizationStatus(for: .audio)` i przy `.notDetermined` pyta `requestAccess` (FR-034), odmowa → `SpeechError.microphoneDenied`; `AVAudioRecorder` do pliku `.wav` w `FileManager.default.temporaryDirectory` (16 kHz, mono, 16-bit LE PCM), `record(forDuration: 120)` („najdłużej 2 minuty”, FR-031); `stop()` zatrzymuje, czyta `Data`, usuwa plik (FR-036).
- [X] T023 [US3] W `Sources/Hotkey/GlobalHotkeyMonitor.swift`: maska `[.keyDown, .keyUp]`; nowy parametr `speechChordProvider: () -> KeyChord?` (domyślnie `nil`; istniejący `chordProvider` bez zmian); `keyDown` pasujący do akordu mowy (bez powtórzeń) zapamiętuje `keyCode` i woła `onSpeechStart`; `keyUp` z tym `keyCode` czyści go i woła `onSpeechEnd`; pozostałe `keyUp` są ignorowane. Wydziel czystą funkcję `resolveSpeech(key:modifiers:keyCode:isRepeat:isKeyUp:) -> SpeechHit?` i przetestuj ją w `Tests/GlobalHotkeyMonitorTests.swift` (start, powtórzenie, puszczenie, puszczenie innego klawisza, brak akordu).
- [X] T024 [US3] W `Sources/Coordinator/AppCoordinator.swift` dodaj parametry `recorder: (any SpeechRecording)?`, `transcriber: (any SpeechTranscribing)?`, `onRecordingChange: @MainActor (Bool) -> Void = { _ in }`; `handleSpeechStart`: `transcriber.prepare` w tle, `try await recorder.start()` (błąd → `notify(userMessage)`), `onRecordingChange(true)`; puszczenie w trakcie `start` kończy nagrywanie bez tłumaczenia; `handleSpeechEnd`: `onRecordingChange(false)`, `stop()`, `SpeechAudio.containsSpeech` fałsz → `notify(SpeechError.nothingHeard.userMessage)` (FR-035); inaczej `popup.present` przy myszy, `transcriber.prepare` + `transcribe` (błąd → `popup.showError`), pusty tekst → `nothingHeard`, w przeciwnym razie istniejące `stream(text, at:, action: .translate)` (FR-032, FR-033). Podepnij `monitor.onSpeechStart/End` w `start()`.
- [X] T025 [US3] Testy w `Tests/AppCoordinatorSpeechTests.swift`: cisza → powiadomienie, brak panelu i brak `llm.run`; poprawne nagranie → `popup.update(sourceText: <transkrypcja>)` i `llm.run` z tym tekstem; odmowa mikrofonu → powiadomienie z `microphoneDenied`.
- [X] T026 [US3] W `Sources/Coordinator/AppState.swift` dodaj `recordingSpeech = false`; w `Sources/App/GlossoApp.swift` przekaż `MicrophoneRecorder`, `OllamaSpeechClient` jako `transcriber` i `onRecordingChange` → `appState.recordingSpeech`, przekaż `speechChordProvider` z `settings.speechChord`, a `MenuBarGlyph.image` o `recording: Bool` (czerwona kropka `systemRed`, ma pierwszeństwo przed kropką modelu).
- [X] T027 [US3] W `Sources/Settings/KeyChordRecorder.swift` zmień `chord` na `Binding<KeyChord?>` (rysuje „—” dla `nil`) i `otherChord` na `otherChords: [KeyChord]` (każdy z trzech rejestratorów dostaje dwa pozostałe akordy, akord mowy tylko gdy nie jest `nil`); w `Sources/Settings/SettingsView.swift` dostosuj dwa istniejące wiersze (`Binding($store.fixChord)`), dodaj w sekcji „Skróty” wiersz „Przytrzymaj, aby mówić” / „Hold to speak” z przyciskiem „Usuń” / „Clear” (`store.speechChord = nil`), a wybór głosu (`Picker` po `SpeechVoice.allCases`) w menu paska obok języków (`LanguageMenus` w `GlossoApp.swift`), bo formularz Ustawień był na limicie `SettingsLayoutTests`; sam wiersz skrótu mowy podniósł formularz Google AI do 828 pt, więc limit testu wzrósł z 800 do 840 pt (decyzja użytkownika). Konflikty z innymi akordami odrzuca rejestrator (edge case).

**Checkpoint**: wszystkie trzy historie działają.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T028 [P] W `Tests/SanityTests.swift` przypnij `SpeechAudio.speechModel == "lfm3-audio"` i `SpeechAudio.minimumEngineVersion == [0, 40, 12]`.
- [X] T029 [P] W `README.md` (po polsku) dopisz jedno zdanie o funkcjach mowy i o tym, że model mowy (około 2 GB) pobiera się przy pierwszym użyciu.
- [X] T030 Uruchom `scripts/test.sh` na Macu i sprawdź ręcznie scenariusze z `quickstart.md`.

---

## Dependencies & Execution Order

- **Setup (T001–T002)** → **Foundational (T003–T013)** → US1, US2, US3.
- T003 blokuje wszystko poza T004/T005. T006 wymaga T003 i T004. T008 wymaga T003, T004. T010 wymaga T003. T011 wymaga T008 i T010. T013 wymaga T006, T008, T009, T012.
- **US1** (T014–T018) zależy tylko od Foundational.
- **US2** (T019–T021) zależy tylko od Foundational; niezależna od US1.
- **US3** (T022–T027) korzysta z `OllamaSpeechClient` i `Narrator.prewarm` z Foundational; niezależna od US1 i US2. T024 i T017 edytują ten sam plik, więc w jednym przebiegu robi się je po kolei.
- **Polish** po wszystkich historiach.

## Parallel Example

```text
Foundational: T004 (SpeechAudio) ‖ T009 (PCMStreamPlayer) po T003; T005 ‖ T007 równolegle z implementacją
US1: T014 ‖ T015 (różne pliki), potem T016 → T017 → T018
US2: T019 ‖ T020, potem T021
US3: T022 ‖ T023, potem T024 → T025 → T026 → T027
```

## Implementation Strategy

1. **MVP**: Setup + Foundational + US1. Sprawdź syntezę, pobieranie na żądanie i odtwarzanie na jednym przycisku.
2. **+US2**: ta sama ścieżka, nowe źródło fragmentów (DOM czytnika).
3. **+US3**: nowe wejście (mikrofon, skrót), wyjście przez istniejący panel.
4. Każda historia kończy się zielonym `scripts/test.sh`.
