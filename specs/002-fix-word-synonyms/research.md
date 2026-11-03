# Research: Synonimy słowa w poprawionym tekście

W Technical Context nie było pozycji „NEEDS CLARIFICATION”. Poniżej są decyzje projektowe wynikające z istniejącego kodu.

## R1. Jedna ścieżka popupu, rozgałęzienie w koordynatorze

- **Decision**: popup dalej woła `onFetchAlternatives(word, text)` i `onPickAlternative(original, chosen, text)`. `AppCoordinator` wybiera prompt według `lastCapture.action`: `.translate` używa `alternatives`/`reword`, a `.fixGrammar` używa `synonyms`/`swapSynonym`. Wynik podmiany trafia do `actionCache[capture.action]`, a `handleUndo` czyści cache bieżącej akcji.
- **Rationale**: popup nie musi znać różnicy, bo `TranslationPopupPresenting` zostaje bez zmian, podobnie jak `FakePopup` i oba okna (panel Cmd+C i Tłumacz…). Akcja jest już zapisana w `lastCapture`.
- **Alternatives considered**: osobne callbacki `onFetchSynonyms`/`onPickSynonym` w kontrakcie popupu. Odrzucone, bo dublują ścieżkę bez zysku.

## R2. Nowe metody `LLMClient`, a nie flaga w istniejących

- **Decision**: dodać `synonyms(for:in:model:)` i `swapSynonym(original:to:in:model:)`. Obie są zaimplementowane w `PromptRunning.swift`, a prompty siedzą w `PromptBuilder` (`buildSynonyms`, `buildSwapSynonym`). Wynik synonimów przechodzi przez istniejący `AlternativesParser.parse(_, original:)`.
- **Rationale**: prompty tłumaczeniowe mówią o „translation between X and Y”, a poprawka nie ma kierunku. Osobne metody nie potrzebują `primary`/`second`/`source`. `RoutingLLMClient` dostaje je za darmo przez rozszerzenie `GenerationBackend`, więc fallback na model lokalny działa bez zmian (FR-010).
- **Alternatives considered**: parametr `mode` w `alternatives`/`reword`. Odrzucony, bo każde wywołanie i atrapa musiałyby przekazywać nieistotne `primary`/`second`.

## R3. Formalność przy podmianie synonimu

- **Decision**: `swapSynonym` nie przyjmuje formalności. Prompt każe zachować resztę tekstu bez zmian.
- **Rationale**: spec (Assumptions) mówi, że podmiana nie zmienia formalności. Poprawiony tekst ma już ustalony rejestr.

## R4. Unikalne identyfikatory słów w widoku zmian

- **Decision**: słowa w niezmienionych odcinkach diffu dostają ujemne id (`-1 - kolejny indeks` w całym diffie), budowane raz w `PopupModel.diffSameRuns`. Fragmenty zmienione zachowują id części diffu (≥ 0).
- **Rationale**: `Tokenizer.segments` numeruje od zera w każdym odcinku, więc id kolidowałyby między odcinkami i z id zmian. Kolizja psułaby zaznaczenie, kotwicę menu (`WordAnchorKey`) i cache (`altsCache`, `fixReasonCache`). Ujemne id rozdzielają obie przestrzenie bez nowego typu.
- **Alternatives considered**: id złożone (struct). Odrzucone, bo `selectedWordID`, kotwice i cache są typu `Int`.

## R5. Menu fragmentu zmienionego: synonimy plus „Dlaczego poprawiono?” na żądanie

- **Decision**: `PopupModel` dostaje `selectedWord` i `selectedFixChange: (before, after)?`. Kliknięcie zmiany, w której `after` zawiera słowo (litera lub cyfra), otwiera menu synonimów dla `after` przyciętego z białych znaków. Nagłówek „Dlaczego poprawiono?” woła `showFixReason()`. Widok powodu ma wtedy strzałkę „wstecz” (`fixReasonHasBack`), a Esc wraca do listy. Zmiana bez słowa w `after` (samo usunięcie, sama interpunkcja) otwiera od razu powód, jak dotąd. Pobieranie powodu przenosi się z `PopupView` do `TranslationPopupController`, bo wołają je teraz oba widoki (panel i okno menu).
- **Rationale**: odpowiada wyborowi A z Clarifications: jedno zapytanie na kliknięcie i ten sam wzór co „Dlaczego tak?”.
- **Alternatives considered**: ładowanie powodu równolegle z synonimami. Odrzucone w Clarifications.

## R6. Ukryty widok zmian w trybie podzielonym

- **Decision**: gdy `diffHidden`, poprawiona wersja renderuje się jako `wordFlow`, czyli klikalne słowa. `toggleDiffHidden` czyści `altsCache`, bo `wordFlow` używa id tokenów (≥ 0), które mogą się pokrywać z id zmian.
- **Rationale**: spec, Edge Cases. Koszt to utrata zaznaczania tekstu w tym jednym widoku, a kopiowanie dalej działa przyciskiem.
