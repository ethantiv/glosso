# Wykonalność: lfm3-audio w Ollamie

Test z 2026-10-28 na Ollamie 0.40.12 (Mac użytkownika), model `lfm3-audio` (tag `latest` = `2b-nvfp4`, runner MLX, 2,1 GB).

## Wnioski

Wszystkie trzy funkcje z koncepcji są wykonalne przez Ollamę, ale **nie** przez `/api/chat` ani `/api/generate`. Natywne API nie ma pól audio. Mowa idzie przez endpointy zgodne z OpenAI:

| Funkcja | Endpoint | Od wersji Ollamy |
|---|---|---|
| Synteza (TTS) | `POST /v1/audio/speech` (JSON) | 0.40.8 |
| Rozpoznawanie (ASR) | `POST /v1/audio/transcriptions` (multipart, plik WAV) | nie podano; działa na 0.40.12 |
| Tłumaczenie mowy | `POST /v1/audio/translations` (multipart) | 0.40.12 |

`/api/show` zwraca dla modelu `capabilities: ["completion","tools","audio","speech"]`. Strona tagów pokazuje tylko „Text input”, ale to nieaktualne.

Konsekwencja dla projektu: `CLAUDE.md` mówi, że Glosso używa natywnego API, bo `/v1` nie ma `keep_alive`. Dla mowy innej drogi nie ma, więc rozgrzewanie modelu mowy trzeba rozwiązać osobno (do sprawdzenia w planie).

## Synteza

```bash
curl -s localhost:11434/v1/audio/speech -H 'Content-Type: application/json' \
  -d '{"model":"lfm3-audio","input":"Dzień dobry…","voice":"female-polish"}' -o out.wav
```

- Odpowiedź: `audio/wav`, 24 kHz, mono, 16 bit, strumieniowana. Format `pcm` daje surowe próbki bez nagłówka. Nagłówek WAV ma rozmiary ustawione na maksimum, bo długość nie jest znana z góry.
- Głosy: `female`, `male`, opcjonalnie z językiem, np. `female-polish`, `male-american-english`. Nazwy z dokumentacji `phonon` (`Zoey` itd.) zwracają 400. `default` też działa.
- Limit `input`: 4096 znaków na żądanie (dokumentacja speech).
- Czasy: około 6,5 s mowy w 1,1–1,4 s, pierwszy bajt po 60–80 ms (model rozgrzany); pierwsze żądanie 2,9 s do pierwszego bajtu.

## Rozpoznawanie i tłumaczenie

```bash
curl -s localhost:11434/v1/audio/transcriptions -F model=lfm3-audio -F language=pl -F file=@pl.wav
# {"text":"Dzień dobry. To jest test syntezy mowy w języku polskim. Zarzuć gęślą jaśń."}
curl -s localhost:11434/v1/audio/translations -F model=lfm3-audio -F to_language=en -F file=@pl.wav
# {"text":"Good morning. This is a speech synthesis test in Polish. I will give you a hint."}
curl -s localhost:11434/v1/audio/translations -F model=lfm3-audio -F to_language=pl -F file=@en.wav
# {"text":"Green morning. To jest test syntezy mowy."}
```

- Rozpoznawanie: 0,2–1,2 s, poprawne poza pangramem. Działa też bez `language`.
- Tłumaczenie mowy wprost: słabe (zmyślone zakończenie, „Green morning”). Stąd decyzja w specyfikacji: model mowy tylko rozpoznaje, tłumaczy istniejąca ścieżka tekstowa.
- `stream=true` zwraca SSE (`transcript.text.delta`, `transcript.text.done`).
- Wejście: WAV, do 2 h i 512 MB; powyżej 30 s dzielone na pauzach.

## Tekst

`/api/chat` z `think: false` działa i zwraca tekst bez pola `thinking`. Glosso nie potrzebuje tej drogi.
