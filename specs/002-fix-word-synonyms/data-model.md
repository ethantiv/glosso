# Data Model: Synonimy słowa w poprawionym tekście

Stan jest wyłącznie w pamięci, w `PopupModel` i `AppCoordinator`. Nic nie jest zapisywane na dysku.

## PopupModel (nowe i zmienione pola)

| Pole | Typ | Znaczenie |
|---|---|---|
| `selectedWord` | `String` | Tekst klikniętego słowa lub fragmentu. Ustawiany przez `openDropdown`, czyszczony przez `closeDropdown`. Zastępuje wyszukiwanie w `segments` po id (które nie działa dla id z diffu). |
| `selectedFixChange` | `(before: String, after: String)?` | Kliknięta zmiana z diffu. `nil` dla zwykłego słowa. |
| `fixReasonHasBack` | `Bool` (wyliczane) | `true`, gdy `selectedFixChange.after` zawiera słowo, czyli powód otwarto z menu synonimów i strzałka „wstecz” ma dokąd wrócić. |
| `diffSameRuns` | `[Int: [FlowRun]]` | Bez zmiany typu. Słowa dostają ujemne, unikalne w całym diffie id. |

## Przejścia stanu menu

```text
zamknięte
  ── klik słowa (tłumaczenie lub niezmienione w poprawce) ──► lista (alternatywy/synonimy)
  ── klik zmiany ze słowem w `after` ─────────────────────► lista synonimów + nagłówek „Dlaczego poprawiono?”
  ── klik zmiany bez słowa w `after` ─────────────────────► powód (bez „wstecz”)

lista + nagłówek ── klik nagłówka ──► powód (z „wstecz”)
powód (z „wstecz”) ── „wstecz” / Esc ──► lista (bez ponownego pobierania)
lista ── wybór pozycji ──► zamknięte, snapshot do cofnięcia, strumień przepisania
dowolny ── Esc / klik obok / zmiana wyniku ──► zamknięte
```

## Reguły

- Cache synonimów (`altsCache`), wyjaśnień i powodów jest kluczowany id elementu i czyszczony przy każdym nowym wyniku (`resetTranslationPane`), przy cofnięciu i przy przełączeniu `diffHidden`.
- Podmiana zapisuje wynik w `actionCache[capture.action]`, a cofnięcie usuwa wpis bieżącej akcji.
- Diff zawsze porównuje `capturedSource` z bieżącym `text` (FR-007).
