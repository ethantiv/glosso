# Kontrakt: Ollama (lokalnie), model `lfm3-audio`

Baza: wynik `EngineManager.activeBaseURL()` bez `/api/generate` (np. `http://localhost:11434` albo `http://127.0.0.1:<port>` dla uruchomionego przez Glosso `ollama serve`). Brak autoryzacji.

## `GET /api/version`

`200 {"version":"0.40.12"}`. Wymagane ≥ 0.40.12; porównanie numeryczne po kropkach, sufiksy (`-rc1`) ignorowane.

## `POST /api/show`

Body `{"model":"lfm3-audio"}`. `200` = model jest. `404 {"error":"model 'lfm3-audio:latest' not found"}` = trzeba pobrać przez `/api/pull` (istniejący `OllamaModelManager`).

## `POST /api/generate` (rozgrzanie)

Body `{"model":"lfm3-audio","keep_alive":"<SettingsStore.keepAlive>"}`, bez `prompt`. `200 {"done":true,"done_reason":"load",…}`. Błędy ignorowane (rozgrzanie jest opcjonalne).

## `POST /v1/audio/speech`

```json
{"model":"lfm3-audio","input":"<≤ 4096 znaków>","voice":"female-polish","response_format":"pcm"}
```

- `200`, `Content-Type: audio/pcm`: strumień surowych próbek 16-bit LE, mono, 24 kHz. Długość nieznana z góry.
- `400 {"error":{"message":"voice \"Zoey\" is not supported; …","type":"invalid_request_error",…}}`
- `404 {"error":{"message":"model \"x\" not found, try pulling it first","type":"not_found_error",…}}`
- Zbyt stary serwer: `404` z ciałem `404 page not found` (tekst, nie JSON). Wykrywane wcześniej przez `/api/version`.

Komunikat błędu: `error.message` (koperta OpenAI) albo `error` (string, styl natywny), w tej kolejności; gdy żadne nie pasuje, sam kod HTTP.

## `POST /v1/audio/transcriptions`

`multipart/form-data`: `model=lfm3-audio`, `file=@nagranie.wav` (`Content-Type: audio/wav`). Bez `language`: model wykrywa język sam (test: poprawnie dla PL i EN).

- `200 {"text":"Dzień dobry. To jest test…"}`
- Błędy jak wyżej.
