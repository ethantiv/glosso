# Mockup — wizualna referencja do przeniesienia na SwiftUI

Samodzielny mockup webowy (HTML/CSS/JS, bez builda). Otwórz `index.html` w przeglądarce.
Pasek na górze przełącza **stan** (przechwytywanie / streaming / gotowe / błąd / obcięte) i **motyw** (jasny / ciemny). Ten pasek to tylko podgląd, nie jest częścią aplikacji.

To jest **referencja wizualna**, nie kod do skopiowania. W kolejnej sesji przepisujemy decyzje na SwiftUI/AppKit.

## Założenie projektowe

Zostać w idiomie macOS (materiał, SF Pro, systemowe promienie i cienie, standardowe kontrolki), ale uciec od monotonii dwóch identycznych białych kolumn z poprzedniej wersji. Charakter dają trzy rzeczy: **para językowa kodowana kolorem**, **dwutonowe panele** (źródło wcięte, tłumaczenie jako fokus) i **dopracowany słownik stanów**.

## Mapowanie decyzji na SwiftUI

| Mockup (web) | Odpowiednik w SwiftUI / AppKit |
|---|---|
| Tło panelu `--material` + `backdrop-filter: blur` | `NSVisualEffectView` (material `.popover` / `.hudWindow`) jako tło `FloatingPanel`, albo `.background(.regularMaterial)` |
| `--ink` / `--ink-2` / `--ink-3` | `.primary` / `.secondary` / `.tertiary` (`Color` semantyczne, same się adaptują do jasny/ciemny) |
| `--accent` (indygo-błękit) | własny `Color` w Assets z wariantem Any/Dark, użyty jako `.tint(...)`; albo systemowy `Color.accentColor` jeśli wolisz stock |
| Panel źródłowy `--pane-recessed` | osobny `NSVisualEffectView`/`.background` z lekkim przyciemnieniem, lub `Color.primary.opacity(0.06)` |
| Akcentowa krawędź u góry panelu tłumaczenia | cienki `Rectangle` z gradientem akcentu, `.frame(height: 2)`, widoczny tylko w `streaming`/`done` |
| Pigułki `PL` / `EN` (`lang--from` neutralna, `lang--to` w akcencie) | dwa `Text` w `.clipShape(Capsule())`; cel z `.background(accent.opacity(0.18))`, źródło neutralne |
| Strzałka kierunku (`scaleX(-1)` dla rtl) | SF Symbol `arrow.right`, obrót/odbicie zależnie od `DirectionDetector` (PL→XX vs XX→PL) |
| Przyciski w nagłówku | `Button` + `.buttonStyle(.borderless)` z SF Symbols: `doc.on.doc`, `pin`, `xmark` |
| Morfing Kopiuj → ✓ | zamiana SF Symbol `doc.on.doc` ↔ `checkmark`, reset po ~1.4 s (`Task.sleep`) |
| Stan `capturing` (skeleton) | `.redacted(reason: .placeholder)` na placeholderowym tekście, lub własne prostokąty z shimmerem |
| `live-dot` (pulsująca kropka) | mała `Circle` z powtarzalną animacją `scale`/`opacity` (`prefers-reduced-motion` → bez pulsu) |
| Kursor streamingu | migający `Rectangle` doklejony do tekstu, lub po prostu pomiń w v1 |
| Stopka „obcięte" | `Label(...)` z `exclamationmark.triangle.fill`, tło `Color.orange.opacity(0.08)` |
| Okno Ustawień (grupy/wiersze) | to już masz: `Form` + `.formStyle(.grouped)`; mockup pokazuje docelowy rytm i opisy pod etykietami |
| Wejście panelu `panel-in` (scale+fade ~190ms) | `.transition(.scale(0.965).combined(with: .opacity))` + `.animation(.easeOut, ...)`; krzywa ≈ `ease-out-expo` |

## Tokeny (skopiuj do SwiftUI jako stałe)

- Akcent (jasny): `oklch(0.585 0.176 264)` ≈ `#4F5BD8` (indygo-błękit, bogatszy niż stockowy systemBlue)
- Akcent (ciemny): `oklch(0.68 0.16 264)` ≈ `#7C84F0`
- Promienie: okno `13`, panel wewn. `9`, kontrolka `7`
- Padding panelu: `15` (wewn.), `9` (okno)
- Skala typografii (px): label `11`, meta `12`, źródło `15`, tłumaczenie `16` (tłumaczenie celowo o stopień większe = fokus)
- Czas animacji: `190ms` wejście, `130ms` mikro-interakcje; krzywa `cubic-bezier(0.16, 1, 0.3, 1)`

## Świadome odstępstwa od poprzedniej wersji

1. Tłumaczenie jest stopień większe i ciemniejsze niż oryginał — hierarchia zamiast dwóch równorzędnych kolumn.
2. Kierunek (PL→EN) wyniesiony do nagłówka panelu jako para pigułek, nie ukryty w menu barze.
3. Pełny słownik stanów (skeleton przy przechwytywaniu zamiast pustki/spinnera w środku treści).
4. Materiał + akcentowa krawędź dają głębię bez łamania estetyki Apple.
