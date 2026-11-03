# Kontrakty: szwy Swift

## `LLMClient` (`Sources/Core/Contracts.swift`)

Dochodzą dwie metody. Obie są zaimplementowane raz, w `PromptRunning.swift`, dla każdego `GenerationBackend`.

```swift
/// Up to 6 same-language synonyms of `word` as it is used in `text`; never `word` itself.
func synonyms(for word: String, in text: String, model: String) async throws -> [String]

/// `text` with `original` replaced by `chosen`, only the surrounding words adjusted for agreement.
func swapSynonym(original: String, to chosen: String, in text: String, model: String) -> AsyncThrowingStream<TranslationEvent, Error>
```

Wymagania wobec promptów (`PromptBuilder.buildSynonyms`, `PromptBuilder.buildSwapSynonym`):

- Tekst trafia w `<text>…</text>` przez `neutralize`, a słowa przez `quoted`. Treść jest danymi, nie poleceniami (FR-011).
- Synonimy muszą być w języku tekstu: do 6 pozycji, jedna na wiersz, bez numeracji, bez cudzysłowów i bez słowa wyjściowego (FR-002).
- Podmiana zmienia tylko sąsiednie słowa dla uzgodnienia, a resztę zostawia identyczną. Nie zmienia języka ani rejestru (FR-005).

## `TranslationPopupPresenting`

Bez zmian. `onFetchAlternatives` i `onPickAlternative` obsługują obie akcje. Drugi parametr to bieżący wynik: tłumaczenie albo poprawiony tekst.

## `PopupView` (inicjalizator)

`showFixReason: () -> Void` zastępuje `fetchFixReason: (before, after, corrected) async -> String`. Kontroler pobiera powód dla `model.selectedFixChange`, bo ta sama akcja przychodzi teraz także z nagłówka menu (osobne okno).

## `AlternativesDropdown`

Sygnatura bez zmian (`onPick`, `onExplain`, `onBack`). Nagłówek listy zależy od stanu:

| Stan | Nagłówek |
|---|---|
| `model.action == .translate` | „Dlaczego tak?” → `onExplain` |
| `model.selectedFixChange != nil` | „Dlaczego poprawiono?” → `onExplain` |
| inaczej | brak |

Widok powodu ma przycisk „wstecz” (`onBack`), gdy `model.fixReasonHasBack`.
