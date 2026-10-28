# Model danych: Mowa w Glosso

Funkcja nie zapisuje nowych danych poza dwoma ustawieniami. Nagrania i dźwięk istnieją tylko w pamięci, a plik nagrania tylko do czasu odczytu.

## Ustawienia (`SettingsStore`, UserDefaults)

| Pole | Typ | Domyślnie | Klucz | Uwagi |
|---|---|---|---|---|
| `speechChord` | `KeyChord?` | `nil` | `shortcut.speech` | JSON jak pozostałe akordy. `nil` = skrót wyłączony (FR-030). Nie może równać się `fixChord` ani `translateInPlaceChord`. |
| `speechVoice` | `SpeechVoice` (`female`, `male`) | `.female` | `speech.voice` | FR-003. |

## `SpeechVoice`

Wartości: `female`, `male`. Nazwa głosu wysyłana do serwera: `<rawValue>-<język>` albo samo `<rawValue>`, gdy model nie zna języka tekstu (patrz research R5).

## `SpeechError`

| Przypadek | Kiedy | Komunikat (PL) |
|---|---|---|
| `engineTooOld(String)` | `/api/version` < 0.40.12 | „Ta wersja Ollamy (X) nie obsługuje mowy. Zaktualizuj Ollamę do 0.40.12 lub nowszej.” |
| `microphoneDenied` | brak zgody na mikrofon | „Glosso nie ma dostępu do mikrofonu. Włącz go w Ustawieniach systemowych → Prywatność i ochrona → Mikrofon.” |
| `nothingHeard` | nagranie < 0,5 s albo cisza | „Nic nie usłyszałem. Przytrzymaj skrót i mów.” |
| `server(String)` | odpowiedź inna niż 200 z `/v1/audio/*` | „Model mowy zgłosił błąd: …” |

Błędy silnika (`TranslationError.engineUnavailable`, `.ollamaUnreachable`, `.ollamaError` przy pobieraniu) przechodzą bez zmian i mają już komunikaty.

## `SpeechPlaybackState`

```
idle ──start──▶ preparing(progress) ──pierwszy bufor──▶ playing ⇄ paused
  ▲                    │                                   │
  └──── stop / koniec / błąd / start innej sesji ◀─────────┘
```

- `preparing(Double?)`: wersja, model, rozgrzanie i oczekiwanie na pierwszy bufor. `Double` to postęp pobierania modelu (0…1), `nil` gdy nic się nie pobiera.
- Każda sesja ma własny callback `onState`. Rozpoczęcie nowej sesji wysyła poprzedniej `.idle` (FR-004).

## Fragment do przeczytania

`String` z `SpeechText.chunks(_:)`: zdania sklejone do ≤ 400 znaków (R4). Czytnik podaje fragmenty w kolejności bloków artykułu. Blok, który czeka na tłumaczenie, wstrzymuje czytanie do czasu przetłumaczenia (FR-022). Blok, którego nie da się przeczytać (obraz, tabela, kod, blok porzucony po przerwanym tłumaczeniu), jest pomijany.

## Wypowiedź

Dane WAV z `SpeechRecording.stop()`. Walidacja (`SpeechAudio.containsSpeech`): długość ≥ 0,5 s (8000 próbek przy 16 kHz) i najgłośniejsze okno 50 ms z RMS ≥ 0,01. Po transkrypcji zostaje tylko tekst, który trafia do panelu jako oryginał (FR-033).
