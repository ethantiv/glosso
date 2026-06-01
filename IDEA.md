# Translator — analiza i architektura startowa

Aplikacja macOS działająca w tle: po podwójnym Cmd+C tłumaczy zaznaczony tekst
lokalnym modelem LLM (Gemma 4 przez Ollamę) i pokazuje wynik w pływającym popupie.

## Werdykt: silnik i SDK

**Google SDK odpada.** `google-genai` i Vertex AI są wyłącznie chmurowe i mówią
protokołem Gemini/Vertex — nie rozmawiają z lokalną Gemmą nawet przez `base_url`
(ten parametr działa tylko jako proxy przed Vertex). Wpięcie do Ollamy
wymagałoby warstwy pośredniej (LiteLLM) — obejście bez wartości. Sprzeczne z
wymogiem „lokalnie, bez chmury".

**Ollama zostaje silnikiem — nie embedujemy modelu.** Hot-swapping modeli
(`ollama pull` / `ollama.list()` / `keep_alive`) to dokładnie ten model pracy,
którego oczekujemy. Embedowanie (llama.cpp w binarce, mlx-lm in-process) daje
jeden model na proces i własną logikę cyklu życia — odpada.

**Natywny REST `/api/generate`, NIE warstwa OpenAI-compatible `/v1`.** Warstwa
`/v1` nie wystawia `keep_alive` (kontrola rezydencji modelu w pamięci) i ma
słabsze strukturalne wyjście. `/api/generate` mapuje się idealnie na single-shot
tłumaczenie: `POST {model, prompt, stream}` i czytasz `.response`.

### Niuans MLX vs Ollama — sprostowanie premisy

Tag „gemma4:26b-mlx via ollama" brzmiał niespójnie (klasyczna Ollama to
GGUF/llama.cpp; ścieżka MLX w 0.19 wymaga M5 + NVFP4; research wskazywał issue
#15436 jako blokujący Gemma 4). **Weryfikacja empiryczna na Ollamie 0.24.0
obaliła te wątpliwości — model działa i generuje poprawnie.** Research był
nieaktualny.

## Stos aplikacji: natywny Swift/SwiftUI

Electron/Tauri i tak zmuszają do natywnego kodu dla globalnego skrótu,
Accessibility API i odczytu zaznaczenia — za to z narzutem warstwy webowej.
Podwójne Cmd+C **nie jest klasycznym globalnym skrótem** — to monitorowanie
zdarzeń keyDown i pomiar odstępu.

- Aplikacja agentowa w pasku menu: `LSUIElement = true`, `MenuBarExtra`.
- Dystrybucja poza Mac App Store (Accessibility zwykle wyklucza sandbox MAS).

## Decyzje (ustalone w grill-me)

| Obszar | Decyzja |
|---|---|
| Odbiorca | Narzędzie osobiste, jeden Mac |
| Trigger | Podwójne Cmd+C, `NSEvent.addGlobalMonitorForEvents(.keyDown)` (pasywny) |
| Capture | Odczyt `NSPasteboard` (użytkownik sam skopiował) + guard na `changeCount` |
| Kierunek | PL↔(wybrany drugi język) z auto-swapem wbudowanym w prompt; drugi język konfigurowalny w Ustawieniach (domyślnie EN) |
| Detekcja kierunku | Tłumaczenie: tylko LLM, w jednym wywołaniu (bez JSON Schema). Etykieta strzałki w UI: lokalny `NLLanguageRecognizer` (`DirectionDetector`, ograniczony do PL + wybrany język), musi lustrzanie odbijać swap z promptu |
| Topologia | Ollama na tym samym Macu, `localhost:11434` |
| Model | domyślnie `gemma4:26b-mlx` (zweryfikowany, działa pod Ollamą 0.24.0); wybór w Ustawieniach z listy `/api/tags` |
| Wyjście | Streaming plain text (`stream:true`) |
| Nasłuch | `NSEvent global monitor` — jedyne uprawnienie: **Accessibility** |
| Popup | `NSPanel .nonactivatingPanel .floating`; Esc/klik poza zamyka, klik kopiuje |
| Cykl modelu | `keep_alive:"30m"` + pre-warm przy starcie |

## Parametry wywołania `/api/generate`

```jsonc
{
  "model": "gemma4:26b-mlx",
  "prompt": "<swap-logic + tylko tłumaczenie + tekst>",
  "stream": true,
  "think": false,        // OBOWIĄZKOWE — patrz niżej
  "options": { "temperature": 0 },
  "keep_alive": "30m"
}
```

Prompt (swap w treści; `{drugi język}` = wybrany w Ustawieniach, domyślnie English):
> If it is Polish, translate it to {drugi język}. Otherwise, translate it to
> Polish. Output ONLY the translation, no explanations, no quotes.

## Ustalenia empiryczne (2026-05-31, na docelowym Macu)

**`think:false` jest obowiązkowe.** Gemma 4 to model z reasoningiem — domyślnie
generuje setki tokenów „myślenia" przed odpowiedzią.

| think | tokeny | total | jakość tłumaczenia |
|---|---|---|---|
| `false` | 18–50 | ~1–2 s | identyczna |
| `true` | 388–957 | ~10–26 s | identyczna |

Czas myślenia zależy od wejścia (10–26 s), co tym bardziej dyskwalifikuje
`think:true`. Ciepły model: ~38 tok/s.

**Poziomy reasoningu nie działają na gemma4.** `think` przyjmuje boolean oraz
stringi `"low"/"medium"/"high"`, ale gemma4 ich nie honoruje — `"low"/"medium"/
"high"` dają identyczny wynik co `true`. W praktyce przełącznik binarny: `false`
= off, cokolwiek innego = pełny reasoning. Brak opcji „trochę myślenia".

## Diagram komponentów

```
[Pasek menu: MenuBarExtra, LSUIElement=true]
   │  (włącz/wyłącz, ewentualne ustawienia)
   ▼
[1. Hotkey listener]  NSEvent global monitor keyDown
   │   wykryj 2× Cmd+C w oknie < ~300 ms (uprawnienie Accessibility)
   │   oba Cmd+C kopiują normalnie (monitor pasywny)
   ▼
[2. Text capture]  odczyt NSPasteboard
   │   guard: changeCount musiał wzrosnąć (inaczej „nic nie zaznaczono")
   ▼
[3. LLM client]  POST http://localhost:11434/api/generate
   │   stream:true, think:false, temperature:0, keep_alive:"30m"
   │   swap PL↔(wybrany język) + „tylko tłumaczenie" w promptcie; parsowanie NDJSON
   ▼
[4. Popup UI]  NSPanel .nonactivatingPanel .floating .borderless
       NSHostingView/SwiftUI, pozycja wg NSEvent.mouseLocation
       streaming tokenów, etykieta kierunku (PL→XX)
       canBecomeKey=false (nie kradnie focusu)
       Esc / klik poza → zamknij; klik w wynik → kopiuj do schowka
```

Punkty 1, 2, 4 to czysty natywny macOS (AppKit). Punkt 3 to jedyna granica
sieciowa — cienki klient HTTP do Ollamy na localhost.

## MVP (pierwszy wycinek)

Aplikacja w pasku menu, która:

1. Prosi o uprawnienie Accessibility przy pierwszym uruchomieniu.
2. Nasłuchuje podwójnego Cmd+C (`NSEvent` + pomiar `doubleClickInterval`).
3. Czyta zaznaczenie z `NSPasteboard` (+ guard na `changeCount`); gdy aplikacja
   nie skopiowała mimo Cmd+C, fallback czyta zaznaczenie wprost przez
   Accessibility (`AXSelectedText` fokusowanego elementu).
4. Pre-warmuje model przy starcie, `keep_alive:"30m"`.
5. Wysyła `POST /api/generate` ze `stream:true`, `think:false`, swap PL↔EN
   zaszyty w promptcie.
6. Streamuje wynik w `NSPanel .floating` przy kursorze; Esc/klik poza zamyka,
   klik kopiuje.

**Świadomie odłożone:** dalsza kaskada capture (AppleScript, `CGEventTap`,
głębsza obsługa Safari przez JavaScript/Apple Events), konfigurowalny adres
Ollamy (osobny host w LAN).

## Ustawienia (zaimplementowane po MVP)

Okno `Settings` (SwiftUI, otwierane przez `SettingsLink` w `MenuBarExtra`) daje
dwie konfigurowalne osie, trwale zapisywane w `UserDefaults` (`SettingsStore`):

- **Model** — wybór z listy modeli faktycznie zainstalowanych w Ollamie
  (`OllamaModelLister`, `GET /api/tags`). Gdy Ollama nie odpowiada, pokazany jest
  zapisany model + przycisk odświeżania.
- **Drugi język** — niepolska strona pary, spośród: angielski (domyślny),
  niemiecki, rosyjski, hiszpański, niderlandzki (`SecondLanguage`). Polski jest
  stałą osią; podwójne ⌘C nadal auto-wykrywa kierunek, ale względem pary
  `polski ↔ wybrany język` (prompt i `DirectionDetector` respektują wybór).
- **Uruchamiaj przy logowaniu** — przełącznik rejestrujący apkę przez
  `SMAppService.mainApp` (`LoginItemManaging`). Stan pochodzi z faktycznej
  rejestracji systemowej, nie z `UserDefaults`, więc cofnięcie w Ustawieniach
  systemu jest odzwierciedlane (po otwarciu okna). Działa wiarygodnie, gdy apka
  żyje w `/Applications`.

Niezmienniki empiryczne (`think:false`, `temperature:0`, `keep_alive:"30m"`,
`endpoint`) **nie są** wystawione w UI — zostają zaszyte w bazowym `LLMConfig`
w `OllamaClient`, więc ustawienia nie mogą ich złamać. Świadomy kompromis: po
zmianie modelu pierwsze tłumaczenie jest wolniejsze (nowy model ładuje się
leniwie; pre-warm przy starcie dotyczy zapisanego modelu).

## Ryzyka i decyzje do potwierdzenia przy implementacji

- **Uprawnienie Accessibility** — bez niego monitor klawiatury milczy. Jasny
  onboarding z prośbą i linkiem do Ustawień → Prywatność i bezpieczeństwo.
- **Ollama offline** — choć localhost, daemon może nie działać. Jawny komunikat
  w popupie zamiast cichej porażki.
- **Okno czasowe podwójnego Cmd+C** — `NSEvent.doubleClickInterval` vs własna
  stała ~300 ms (do dostrojenia).
- **Popup nie może kraść focusu** — `nonactivatingPanel`, `canBecomeKey=false`.
- **RAM** — model 16 GB rezydentny przez 30 min konkuruje o unified memory z
  resztą pracy; `keep_alive:"30m"` to kompromis.
