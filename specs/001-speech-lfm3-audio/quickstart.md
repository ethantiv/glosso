# Quickstart: sprawdzenie funkcji mowy

## Wymagania

- Mac z Apple Silicon, macOS 26+, Ollama ≥ 0.40.12 (`curl -s localhost:11434/api/version`).
- Do sprawdzenia pobierania na żądanie: model nie jest pobrany (`ollama rm lfm3-audio`).

## Testy automatyczne

```bash
scripts/test.sh            # offline; nowe suity: SpeechAudioTests, OllamaSpeechClientTests, NarratorTests,
                           # rozszerzone GlobalHotkeyMonitorTests, AppCoordinatorTests, SettingsStoreTests
```

Oczekiwane: wszystkie testy zielone; `xcrun xcresulttool get test-results summary --path <xcresult>`.

## Ręcznie (`scripts/run.sh`)

1. **US1, panel.** Podwójne Cmd+C na zdaniu z `docs/test-sentences.txt`. Po zakończeniu generowania kliknij 🔊.
   - Pierwszy raz bez modelu: powiadomienie o pobieraniu (około 2 GB), przycisk pokazuje postęp, potem odtwarzanie bez ponownego kliknięcia.
   - Potem dźwięk w mniej niż 1 s, głos w języku wyniku. Drugie kliknięcie, Esc albo zamknięcie panelu przerywa odtwarzanie.
2. **US2, czytnik.** Skopiuj adres długiego artykułu (podwójne Cmd+C). Kliknij „Czytaj na głos” w pasku narzędzi.
   - Czytanie rusza w mniej niż 2 s, idzie fragmentami bez pauz dłuższych niż 1 s. Gdy tłumaczenie jeszcze trwa, czytanie czeka na kolejne bloki.
   - Przycisk ▶︎ zaczyna czytanie, w trakcie zmienia się w ⏸ (wstrzymaj) i z powrotem w ▶︎ (wznów). Przycisk ■ obok kończy czytanie i jest aktywny tylko w trakcie; zamknięcie okna też kończy.
3. **US3, mowa.** Ustawienia → Skróty → „Przytrzymaj, aby mówić”: przypisz np. ⌃⌘M.
   - Pierwsze użycie: systemowa prośba o mikrofon. Przy odmowie pojawia się komunikat z drogą do Ustawień systemowych.
   - Przytrzymaj skrót, przeczytaj zdanie, puść. Na pasku menu w trakcie nagrywania widać czerwoną kropkę. Panel pokazuje rozpoznany tekst jako oryginał i tłumaczenie.
   - Krótkie stuknięcie albo cisza: powiadomienie „Nic nie usłyszałem”, bez panelu.
4. **SC-006.** Z wyłączonym skrótem mowy i bez klikania 🔊: brak prośby o mikrofon, model mowy się nie pobiera.
5. **Dark mode:** `GLOSSO_FORCE_DARK=1` — przycisk 🔊 i ikona w czytniku czytelne.
