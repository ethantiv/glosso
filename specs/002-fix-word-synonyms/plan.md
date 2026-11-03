# Implementation Plan: Synonimy słowa w poprawionym tekście (akcja „Popraw”)

**Branch**: `002-fix-word-synonyms` | **Date**: 2026-11-03 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/002-fix-word-synonyms/spec.md`

## Summary

Po akcji „Popraw” słowa w wyniku stają się klikalne, tak jak w tłumaczeniu. Kliknięcie otwiera to samo menu co alternatywy tłumaczenia, ale z synonimami w języku tekstu. Przy fragmencie zmienionym przez poprawkę u góry menu jest wiersz „Dlaczego poprawiono?”, a powód pobiera się dopiero po kliknięciu tego wiersza. Wybór synonimu przepisuje poprawiony tekst z dopasowaną gramatyką i można go cofnąć.

Podejście polega na ponownym użyciu istniejącej ścieżki alternatyw (`onFetchAlternatives`, `onPickAlternative`, `AlternativesDropdown`, cofanie). `AppCoordinator` wybiera prompt według bieżącej akcji. Warstwa LLM dostaje dwie nowe metody `LLMClient`: `synonyms` i `swapSynonym`, zaimplementowane raz w `PromptRunning.swift`. Szczegóły są w [research.md](research.md).

## Technical Context

**Language/Version**: Swift 6, ścisła współbieżność

**Primary Dependencies**: SwiftUI i AppKit (macOS 26+). Ollama `/api/generate` oraz Gemini przez istniejący `RoutingLLMClient`.

**Storage**: brak. Synonimy są cache'owane w pamięci `PopupModel.altsCache` tylko dla bieżącego wyniku.

**Testing**: Swift Testing (`scripts/test.sh`), offline, z atrapami z `Tests/Support/`

**Target Platform**: macOS 26+, Apple Silicon

**Project Type**: aplikacja desktopowa w pasku menu (`LSUIElement`)

**Performance Goals**: kliknięcie słowa kosztuje jedno zapytanie do modelu. Powód poprawki pobiera się tylko na żądanie (SC-002).

**Constraints**: wywołania chmurowe zużywają dzienny limit, więc nie ma prefetchu synonimów ani powodów. Treść użytkownika trafia do promptu przez `neutralize` (FR-011).

**Scale/Scope**: 2 nowe metody LLM, 2 prompty, zmiany w 8 plikach (`Sources/Core`, `Sources/LLM`, `Sources/Coordinator`, `Sources/Popup`), testy w 4 plikach i atrapa w `Tests/Support`

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

`.specify/memory/constitution.md` to niewypełniony szablon, więc nie definiuje bramek. Zamiast niego obowiązują zasady z `CLAUDE.md`:

| Zasada | Status |
|---|---|
| Moduły rozmawiają przez `Contracts.swift` (nowe metody trafiają do `LLMClient`) | ✅ |
| Prompt istnieje raz, w `PromptRunning.swift`; nowy silnik nie musi nic dopisywać | ✅ |
| Wywołania przekazują `settings.activeModel` | ✅ |
| Teksty UI idą przez `loc()` | ✅ |
| Testy offline (Swift Testing, atrapy na szwach) | ✅ |
| Zmiana widoczna dla użytkownika podnosi `MARKETING_VERSION` (minor) | ✅ (zadanie w tasks) |
| Brak prefetchu w chmurze | ✅ (synonimy i powód tylko po kliknięciu) |

Po fazie 1 status się nie zmienił: wszystkie zasady są spełnione.

## Project Structure

### Documentation (this feature)

```text
specs/002-fix-word-synonyms/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── swift-seams.md
└── tasks.md             # /speckit-tasks
```

### Source Code (repository root)

```text
Sources/
├── Core/Contracts.swift              # LLMClient: + synonyms, + swapSynonym
├── LLM/PromptBuilder.swift           # + buildSynonyms, + buildSwapSynonym
├── LLM/PromptRunning.swift           # implementacje obu metod (wspólne dla silników)
├── Coordinator/AppCoordinator.swift  # fetchAlternatives / streamReword / handleUndo zależne od akcji
└── Popup/
    ├── PopupModel.swift              # selectedWord, selectedFixChange, showFixReason, unikalne id słów w diffie
    ├── PopupView.swift               # klikalne słowa w diffie, menu dla poprawionych fragmentów
    ├── WordFlow.swift                # AlternativesDropdown: nagłówek zależny od kontekstu, „wstecz” w powodzie
    └── TranslationPopupController.swift  # pobieranie powodu poprawki, onPick/onExplain przez selectedWord

Tests/
├── PromptBuilderTests.swift
├── AppCoordinatorTests.swift
├── PopupModelTests.swift
├── PopupLayoutTests.swift
└── Support/CoordinatorFakes.swift    # FakeLLMClient: + synonyms, + swapSynonym
```

**Structure Decision**: istniejąca struktura modułów bez nowych plików źródłowych. Funkcja rozszerza ścieżkę alternatyw tłumaczenia.

## Complexity Tracking

Brak naruszeń.
