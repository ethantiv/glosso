# Przeglądy kodu po implementacji

Kod nie był kompilowany ani testowany: kontener to Linux bez Swifta i Xcode. Przed scaleniem uruchom `scripts/test.sh` na Macu (zadanie T030).

## `/code-review --fix`

Znalazł 10 problemów. Sam poprawił 5:

1. Podwójne `prepare` przy przytrzymaj-i-mów, czyli dwa równoległe pobrania modelu. Teraz `translateSpeech` czeka na zadanie `speechPrepare` uruchomione przy wciśnięciu skrótu.
2. `stop()` w trakcie okna zgody na mikrofon zostawiał mikrofon włączony. Teraz `recordingStart` sprawdza anulowanie po `recorder.start()`.
3. `glossoSpeakable()` przy każdym bloku parsował cały artykuł (O(n²)). Teraz `glossoSpeakable(index)` zwraca jeden blok.
4. Komentarz dokumentujący `setStatus` trafił nad `toggleReadAloud`. Przeniesiony z powrotem.
5. Odpowiedź transkrypcji dekodowana jako `[String: String]` psuła się przy polach innych niż tekst. Teraz to struktura `Transcript { text }`.

Dwa pominięte przez code review poprawiłem ręcznie:

6. Głos był wybierany osobno dla każdego fragmentu, więc krótki fragment mógł zmienić akcent w środku tekstu. Teraz `Narrator.start(language:)` ustala go raz na sesję: w panelu z całego wyniku, w czytniku z języka głównego. Test: `sessionLanguageFixesTheVoice`.
7. Przytrzymanie skrótu nie zatrzymywało lektora, więc mikrofon nagrywał czytany tekst. Teraz `handleSpeechStart` woła `narrator?.stop()`.

Pozostałe trzy znaleziska nie zostały poprawione: dwa naciśnięcia skrótu w trakcie okna zgody, czyszczenie statusu po pobraniu modelu i wersja `0.0.0` w Ollamie zbudowanej ze źródeł. To rzadkie przypadki.

## `/ponytail:ponytail-review` (z poprawkami)

**Co robi zmiana:** dodaje trzy funkcje mowy na lokalnym `lfm3-audio` (odsłuch z panelu, czytanie artykułu, tłumaczenie mowy) przez `/v1/audio/*` Ollamy, ze strumieniowym odtwarzaniem. Rozpoznany tekst idzie dotychczasową ścieżką tłumaczenia. Obciążenie: jeden użytkownik, aplikacja na pasku menu.

**Must fix**

1. **Skrót mowy blokował się do restartu** (`Sources/Hotkey/GlobalHotkeyMonitor.swift`, `resolveSpeech`). Gdy macOS nie dostarczy puszczenia klawisza (pole hasła ukrywa klawisze przed globalnymi monitorami), stan „trzymany” zostawał na zawsze i każde kolejne naciśnięcie było ignorowane. **Poprawione:** świeże naciśnięcie przy stanie „trzymany” kończy zawieszone nagranie (`.end`). Test: `aLostKeyUpIsRecoveredByTheNextPress`.

**Should fix**

2. **Martwa funkcja `SpeechAudio.voice(for:gender:)`.** Po poprawce 6 używały jej już tylko testy. **Poprawione:** funkcja usunięta, testy przepięte na `voice(language:gender:)`.

**Werdykt:** ship po zielonym `scripts/test.sh` na Macu. **Lean:** −4 linie, więcej się nie da. **Nie sprawdzone:** kompilacja i testy.

## `/ponytail:ponytail-review`, druga runda (osobny agent, z poprawkami)

Zastosowane:

1. Czytnik w stanie `.preparing` pokazywał ten sam głośnik co przed kliknięciem, więc drugi klik przerywał czytanie. Teraz pokazuje `stop.fill` i podpis „Przygotowuję mowę… Kliknij, aby przerwać.” (`Sources/Reader/ReaderController.swift`, `showReadAloud`).
2. Brakowało testu błędu transkrypcji. Dodany `failedTranscriptionShowsTheErrorAndTranslatesNothing` (`Tests/AppCoordinatorSpeechTests.swift`).
3. Usunięte nieużywane pola fałszywych obiektów testowych (`Tests/Support/CoordinatorFakes.swift`).

Pominięte: dekodowanie `/api/version` przez `[String: String]` (Nice to have, dziś działa), test `nextReadChunk` (wymaga `WKWebView`), wyścig dwóch naciśnięć w trakcie pierwszego okna zgody.

## Weryfikacja na Macu (`scripts/test.sh`, 2026-10-28)

1. Błąd kompilacji: `accessibilityAction(perform:)` nie istnieje. Poprawione na `.accessibilityAction(.default, toggleSpeech)` w `PopupView.swift`.
2. `SpeechAudioTests.chunksRespectTheLimit`: zdania w teście zaczynały się małą literą, a tokenizer nie dzieli „. s”. Poprawiony test.
3. `SettingsLayoutTests.formFitsOnOneScreen`: formularz Google AI miał 828 pt. Wybór głosu przeniesiony do menu paska, a limit testu podniesiony z 800 do 840 pt (decyzja użytkownika).

Wynik końcowy: wszystkie testy przechodzą (`.build/TestResults-20261028-135141-59086.xcresult`).
