# Research: Mowa w Glosso

Źródła: dokumentacja Ollamy (`api/introduction`, `api/openai-compatibility`, `api/errors`, `capabilities/speech`, `faq`) i testy `curl` na Ollamie 0.40.12 z 2026-10-28 (szczegóły w [feasibility.md](feasibility.md)).

## R1. Którędy rozmawiać z modelem mowy

- **Decyzja:** synteza przez `POST /v1/audio/speech`, rozpoznawanie przez `POST /v1/audio/transcriptions`. Natywne `/api/*` tylko do kontroli: `/api/version`, `/api/show`, `/api/pull` i rozgrzewanie przez `/api/generate`.
- **Uzasadnienie:** natywne `/api/chat` i `/api/generate` nie mają pól audio (dokumentacja zna tylko `images`). Endpointy `/v1/audio/*` działają z `lfm3-audio`, co potwierdził test.
- **Odrzucone:** `/v1/audio/translations`. Tłumaczy słabo („Green morning”, zmyślone zakończenia) i omija ustawienia Glosso (kierunek, dostawca, pamięć podręczna).

## R2. Nowa klasa czy rozszerzenie `OllamaClient`

- **Decyzja:** nowa klasa `OllamaSpeechClient` w `Sources/LLM/`. Korzysta z tego samego `endpointProvider` (`EngineManager.activeBaseURL`) i tej samej `URLSession` co `OllamaClient`. Model pobiera przez istniejący `ModelManaging`.
- **Uzasadnienie:** `OllamaClient` implementuje `GenerationBackend`, obsługuje też chmurę i mapuje błędy na przypadki fallbacku `RoutingLLMClient`. Mowa działa tylko lokalnie, ma inne trasy (`/v1`), inne formaty odpowiedzi (surowe PCM, multipart) i inne błędy (koperta OpenAI). Dopisanie tego do `OllamaClient` mieszałoby dwa kontrakty w jednej klasie.

## R3. Format audio i odtwarzanie

- **Decyzja:** `response_format: "pcm"` (16-bit LE, mono, 24 kHz) czytane strumieniowo. Bufory po około 0,25 s trafiają do `AVAudioEngine` + `AVAudioPlayerNode` (AVFoundation, bez nowych zależności).
- **Uzasadnienie:** pomiar: 16 s mowy powstaje w 4,3 s, pierwszy bajt po 0,2 s. Gdyby czekać na cały plik i grać go przez `AVAudioPlayer`, 300 znaków dawałoby około 4 s ciszy, a to łamie SC-001 (< 1 s). Strumień daje dźwięk po około 0,3 s. Do tego nagłówek WAV ze strumienia ma rozmiary ustawione na maksimum, więc `AVAudioPlayer(data:)` jest tu ryzykowny.
- **Odrzucone:** `AVAudioPlayer` z koncepcji. Prostszy, ale nie spełnia SC-001 i SC-002.

## R4. Dzielenie tekstu

- **Decyzja:** zdania sklejane do fragmentów po co najwyżej 400 znaków; zdanie dłuższe niż 400 znaków jest dzielone na spacjach. Limit API to 4096 znaków na żądanie.
- **Uzasadnienie:** krótkie fragmenty dają szybki start i pozwalają generować następny fragment w trakcie grania bieżącego (FR-021). Granica zdania nie psuje intonacji.

## R5. Wybór głosu

- **Decyzja:** głos `<płeć>-<język>`, np. `female-polish`, `male-american-english`. Język wynika z `NLLanguageRecognizer` na czytanym tekście. Dla języka, którego model nie ma (rosyjski), wysyłana jest sama płeć (`female`).
- **Uzasadnienie:** serwer zwraca 400 dla nieznanego głosu i podaje listę. Głosy z dokumentacji `phonon` (`Zoey` itd.) nie działają z `lfm3-audio`.

## R6. Utrzymanie modelu w pamięci (`keep_alive`)

- **Decyzja:** przed użyciem mowy klient wysyła `POST /api/generate {"model":"lfm3-audio","keep_alive":<ustawienie>}` bez promptu. Test zwrócił `done_reason: "load"`, a `/api/ps` pokazał nowy czas wygaśnięcia. To samo żądanie przy wciśnięciu skrótu mowy ładuje model, zanim użytkownik skończy mówić.
- **Uzasadnienie:** `/v1/audio/*` nie przyjmuje `keep_alive`. `OLLAMA_KEEP_ALIVE` działa globalnie i Glosso nie ustawia go dla Ollamy użytkownika.

## R7. Pobieranie modelu i wersja silnika

- **Decyzja:** `prepare(progress:)` sprawdza po kolei: `/api/version` ≥ 0.40.12 (inaczej `SpeechError.engineTooOld`), `/api/show` (404 → `ModelManaging.pull` z postępem), rozgrzanie (R6). Bez stanu: każde wywołanie to trzy szybkie żądania na localhost.
- **Uzasadnienie:** zbyt stary serwer odpowiada na `/v1/audio/*` zwykłym tekstem „404 page not found”, który trudno odróżnić od braku modelu. Jawne sprawdzenie wersji daje jasny komunikat (FR-005). Wersja 0.40.12 to najstarsza, na której przeszły wszystkie testy (`/v1/audio/speech` od 0.40.8, wersja dla transkrypcji nieudokumentowana).

## R8. Nagrywanie i cisza

- **Decyzja:** `AVAudioRecorder` zapisuje plik WAV (16 kHz, mono, 16-bit PCM) w katalogu tymczasowym, najdłużej 120 s (`record(forDuration:)`). Po zatrzymaniu aplikacja czyta dane i od razu usuwa plik (FR-036). Przed wysłaniem czysta funkcja sprawdza długość (≥ 0,5 s) i głośność (najgłośniejsze okno 50 ms ma RMS ≥ 0,01).
- **Uzasadnienie:** test: 1 s ciszy dał transkrypcję „Okay.”, więc ciszę trzeba odsiać lokalnie (FR-035). 16 kHz to częstotliwość enkodera modelu.
- **Uprawnienia:** `NSMicrophoneUsageDescription` w Info.plist i `com.apple.security.device.audio-input` w entitlements, bo build Release ma hardened runtime i bez tego uprawnienia mikrofon jest zablokowany. Prośba przez `AVCaptureDevice.requestAccess(for: .audio)` przy pierwszym użyciu (FR-034).

## R9. Skrót „przytrzymaj, aby mówić”

- **Decyzja:** `GlobalHotkeyMonitor` nasłuchuje `[.keyDown, .keyUp]`. Pierwsze, niepowtórzone wciśnięcie akordu mowy zapamiętuje `keyCode` i woła `onSpeechStart`. `keyUp` z tym samym `keyCode` woła `onSpeechEnd`. Akord jest opcjonalny (`KeyChord?`), domyślnie `nil`.
- **Uzasadnienie:** nie wymaga nowych uprawnień poza Dostępnością. Porównanie `keyCode` przy puszczeniu działa także wtedy, gdy modyfikatory puszczono wcześniej.

## R10. Wyłączność odtwarzania

- **Decyzja:** jeden współdzielony `Narrator` (`@MainActor`) w aplikacji. Każde `start` kończy poprzednią sesję i wysyła jej `onState(.idle)`.
- **Uzasadnienie:** FR-004. Popup i czytnik dostają stan przez callback i nie muszą o sobie wiedzieć.
