---
name: Glosso
description: macOS-owa apka w pasku menu — popraw, streść i przetłumacz zaznaczenie skrótem ⌘C C, lokalnie.
colors:
  indigo: "#4f5bd8"
  indigo-600: "#4350c4"
  indigo-800: "#2a2f86"
  indigo-950: "#15173f"
  indigo-tint: "#f2f2fb"
  coral: "#ff7a59"
  coral-700: "#e85f3c"
  ink: "#191b30"
  ink-soft: "#4a4d68"
  paper: "#ffffff"
  line: "#e6e6f1"
typography:
  display:
    fontFamily: "Bricolage Grotesque, system-ui, sans-serif"
    fontSize: "clamp(2.6rem, 5.2vw, 4.1rem)"
    fontWeight: 800
    lineHeight: 1.04
    letterSpacing: "-0.035em"
  headline:
    fontFamily: "Bricolage Grotesque, system-ui, sans-serif"
    fontSize: "clamp(1.9rem, 4.5vw, 3rem)"
    fontWeight: 800
    lineHeight: 1.04
    letterSpacing: "-0.02em"
  title:
    fontFamily: "Bricolage Grotesque, system-ui, sans-serif"
    fontSize: "1.3rem"
    fontWeight: 800
    lineHeight: 1.04
    letterSpacing: "-0.02em"
  body:
    fontFamily: "-apple-system, BlinkMacSystemFont, SF Pro Text, system-ui, Segoe UI, Roboto, sans-serif"
    fontSize: "17px"
    fontWeight: 400
    lineHeight: 1.6
    letterSpacing: "normal"
  label:
    fontFamily: "-apple-system, BlinkMacSystemFont, SF Pro Text, system-ui, sans-serif"
    fontSize: "0.68rem"
    fontWeight: 700
    lineHeight: 1.2
    letterSpacing: "0.09em"
rounded:
  sm: "6px"
  md: "12px"
  lg: "16px"
  pill: "9px"
spacing:
  xs: "8px"
  sm: "12px"
  md: "16px"
  lg: "24px"
components:
  button-accent:
    backgroundColor: "{colors.coral}"
    textColor: "#2a1206"
    rounded: "{rounded.md}"
    padding: "0.8rem 1.4rem"
  button-accent-hover:
    backgroundColor: "{colors.coral-700}"
    textColor: "#2a1206"
  button-ghost:
    backgroundColor: "transparent"
    textColor: "{colors.paper}"
    rounded: "{rounded.md}"
    padding: "0.8rem 1.4rem"
  keycap:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    rounded: "{rounded.pill}"
    padding: "0.18em 0.42em"
  card-phase:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    rounded: "{rounded.lg}"
    padding: "1.6rem 1.9rem"
  panel-popup:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    rounded: "{rounded.lg}"
    padding: "0.7rem 0.8rem 0.85rem"
---

# Design System: Glosso

## 1. Overview

**Creative North Star: "Gest jako bohater"**

Strona istnieje, by zainscenizować jeden ruch palców — przytrzymaj ⌘, stuknij C dwa razy, a przy kursorze pojawia się panel. Cała kompozycja podporządkowuje się temu jednemu pomysłowi: nie *opowiada* o geście, tylko go *odgrywa*. Bohaterem nie jest nagłówek ani lista funkcji, lecz wierne, ręcznie odtworzone okno Glosso (zrzuty natywnych okien macOS blokuje system, więc panel jest zbudowany w HTML/CSS), z paskiem czasowników, diffem poprawki i rozwijanym „Dlaczego?". Reszta strony schodzi w cień, żeby ten panel mógł być widoczny.

System mówi trzema słowami z marki: **natywne, prywatne, błyskawiczne**. Estetyka jest wierna macOS (typografia systemowa w UI, realistyczny panel, keycapy), ale niesiona odważnym kolorem i dużą skalą, nie krzykliwymi efektami. Indygo zalewa sekcje-bohaterów (hero, filary prywatności, domknięcie), biel oddycha między nimi, a koralowy akcent pojawia się rzadko — na CTA i na drugim klawiszu „C", bo to on uruchamia magię.

System świadomie odrzuca to, co PRODUCT.md nazywa anty-referencjami: generyczny landing SaaS (gradientowe bloby, „hero metric", powtarzalne siatki kart ikona+nagłówek+tekst), estetykę startupu AI/ML (ciemne tło z neonem, „terminal vibe", przesadny glow) i ciężki korporacyjny szablon (stocki, banery, pustosłowie).

**Key Characteristics:**
- Bohaterem jest odtworzony panel produktu, nie copy.
- Indygo-drench na sekcjach kluczowych, biel jako oddech.
- Koralowy akcent rezerwowany dla akcji i sygnaturowego klawisza.
- Display: Bricolage Grotesque (gruby, ciasny); UI/body: font systemowy macOS — celowo.
- Jedna decyzja na stronie: „Pobierz" i pierwsze tłumaczenie.

## 2. Colors

Strategia **Committed/Drenched**: indygo niesie markę i zalewa sekcje-bohaterów; koralowy jest pojedynczym, rzadkim głosem akcentu; biel i atramentowe neutrale dają oddech i czytelność.

### Primary
- **Indygo** (`#4f5bd8`): rdzeń marki. Tło hero (jako gradient do ciemniejszych odcieni), badge'e kroków, ikony, klawisz w keycapach na jasnym tle, podkreślenia. To kolor, w którym strona „myśli".
- **Indygo głębokie** (`#4350c4`): tekst akcentowy na bieli (kod, „gorące" słowo, ikony wariantowe), drugi przystanek w gradientach.
- **Indygo nocne** (`#2a2f86` → `#15173f`): dolne partie gradientów drench, tło nawigacji (z przezroczystością), stopka. Buduje głębię zalania.
- **Indygo mgła** (`#f2f2fb`): jasne tło sekcji-oddechu (Przewodnik, banda chords) i tint keycapów na bieli.

### Secondary
- **Koral** (`#ff7a59`): jedyny akcent ciepła. CTA „Pobierz", drugi klawisz „C" w sygnaturze gestu, radialne rozbłyski w gradientach, trzeci badge ścieżki. Jego rzadkość jest sensem.
- **Koral przygaszony** (`#e85f3c`): stan hover akcentu i ikon wariantowych na bieli.

### Neutral
- **Atrament** (`#191b30`): główny kolor tekstu na jasnych powierzchniach; tło paska „Przejdź do treści".
- **Atrament miękki** (`#4a4d68`): tekst drugorzędny, ledy sekcji, opisy kart. Trzymany przy ciemnym końcu rampy dla kontrastu ≥4.5:1, nie rozjaśniany „dla elegancji".
- **Papier** (`#ffffff`): tło sekcji-oddechu i wnętrza odtworzonego panelu/kart.
- **Linia** (`#e6e6f1`): obrysy, dzielniki, cień keycapów na bieli.

### Named Rules
**Reguła Jednego Koralu.** Koral pojawia się tylko tam, gdzie coś się *dzieje* — akcja użytkownika (CTA) albo klawisz uruchamiający gest. Nigdy jako dekoracja powierzchni. Jego rzadkość jest komunikatem.

**Reguła Pełnej Siły Indygo na ciemnym.** Biały tekst kładziemy wyłącznie na pełnej sile indygo (od `#4f5bd8` w dół), nigdy na pastelu. Pastelowe indygo + biały tekst łamie WCAG AA — zakazane.

## 3. Typography

**Display Font:** Bricolage Grotesque (z fallbackiem `system-ui, sans-serif`)
**Body/UI Font:** systemowy stos macOS — `-apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui` (z fallbackiem Segoe UI / Roboto)
**Mono Font:** `ui-monospace, "SF Mono", Menlo` — tylko dla `code`

**Character:** Kontrast oparty na jednej osi: gruby, ciasno ułożony grotesk display (waga 800, `letter-spacing` od −0.02em do −0.035em) kontra neutralny, wierny macOS font systemowy w treści. To celowa decyzja — UI ma wyglądać jak natywny macOS, więc body nie udaje „brandowego" kroju. Nagłówki krzyczą, interfejs mówi normalnie.

### Hierarchy
- **Display** (800, `clamp(2.6rem, 5.2vw, 4.1rem)`, line-height 1.04, tracking −0.035em): tylko tytuł hero. Maksimum ≤ ~4.1rem — strona projektuje, nie wrzeszczy.
- **Headline** (800, `clamp(1.9rem, 4.5vw, 3rem)`, line-height 1.04, tracking −0.02em): tytuły sekcji (`.section__title`, `.pillars h2`, `.closer h2`).
- **Title** (800, 1.3rem): nagłówki kart (`.vcard h3`, `.phase__head h3`, `.shot__cap h3`, `.pillar h3`).
- **Body** (400, 17px, line-height 1.6): tekst akapitów i ledów; ledy sekcji 1.12rem w atramencie miękkim. Mierz długość wiersza w 48–65ch (`max-width` ledów ~52–56ch).
- **Label** (700, 0.68rem, tracking 0.09em, UPPERCASE): etykiety wewnątrz odtworzonego panelu (`ORYGINAŁ`, `POPRAWKA`, `TŁUMACZENIE`). Eyebrow hero (`.hero__eyebrow`, 0.9rem, waga 600) jest pojedynczy i nazwany, nie powtarzany nad każdą sekcją.

### Named Rules
**Reguła Systemowego UI.** Tekst, który udaje interfejs Glosso (panel, keycapy, czasowniki), zawsze w foncie systemowym macOS — to część wierności produktowi. Bricolage zostaje dla narracji strony, nigdy nie wchodzi do odtworzonego okna.

**Reguła Jednego Eyebrow.** Mały tracked label nad nagłówkiem dozwolony tylko raz — w hero. Powtarzanie go nad każdą sekcją to szablonowy rusztowy AI; zakazane.

## 4. Elevation

System jest w większości płaski, z głębią budowaną dwoma środkami: **gradientami drench** (radialny rozbłysk koralu nałożony na liniowy gradient indygo) na sekcjach-bohaterach oraz **miękkimi, daleko rozmytymi cieniami** pod pływającymi elementami — odtworzonym panelem, kartami przewodnika, dropdownami. Cienie są ambient (rozproszone, kolorowane atramentem `rgba(21,23,63,…)`), nigdy twarde kontury — naśladują sposób, w jaki macOS unosi okna nad pulpitem.

### Shadow Vocabulary
- **Panel** (`box-shadow: 0 28px 70px -24px rgba(21,23,63,.55), 0 4px 14px -6px rgba(21,23,63,.3)`): pływające okno Glosso i jego klony.
- **Stage** (`box-shadow: 0 34px 80px -38px rgba(8,9,36,.75)`): „ekran" spinający pasek menu z panelem w hero.
- **Card** (`box-shadow: 0 10px 30px -20px rgba(21,23,63,.4)`, hover `0 20px 44px -22px rgba(21,23,63,.5)`): karty przewodnika; unoszą się o 3px przy hover.
- **Dropdown** (`box-shadow: 0 18px 40px -18px rgba(21,23,63,.45)`): rozwijane menu alternatyw/„Dlaczego?".
- **CTA glow** (`box-shadow: 0 10px 24px -10px rgba(255,122,89,.8)`): jedyny cień barwiony koralem, tylko pod akcentowym przyciskiem.
- **Keycap** (`box-shadow: 0 2px 0 …`): twardy 2px „spód" klawisza — jedyny celowo nie-rozmyty cień, bo udaje fizyczny keycap.

### Named Rules
**Reguła Płaskiego Tła.** Powierzchnie są płaskie w spoczynku. Cień to odpowiedź na unoszenie (pływający panel, karta, hover, focus), nie domyślna ozdoba prostokąta.

## 5. Components

### Buttons
- **Shape:** zaokrąglone narożniki (12px; nav-CTA 10px). Wariant `--lg` powiększa padding do `1rem 1.7rem`.
- **Accent (primary):** tło koralowe, tekst ciemnobrązowy `#2a1206` (kontrast na koralu), miękki koralowy glow. Może nieść dwuwierszowy podpis (`.btn__sub`, np. „.zip · za darmo").
- **Ghost:** przezroczyste tło, biały tekst, obrys `1.5px rgba(255,255,255,.4)` — tylko na ciemnym (hero). Hover rozjaśnia tło `rgba(255,255,255,.1)`.
- **Hover / Active:** wszystkie przyciski unoszą się `translateY(-2px)` (hover) i wracają na `0` (active); accent dodatkowo ciemnieje do koralu przygaszonego. Przejścia `0.25s` krzywą `cubic-bezier(.22,1,.36,1)`.

### Keycaps (signature)
- **Style:** mały `inline-flex` klawisz, min-width 1.7em, font systemowy 600, róg 7px, twardy 2px spód. Trzy warianty tła pod kontekst: na bieli — biały z linią; na ciemnym (hero, filary) — `rgba(255,255,255,.14)` z białym tekstem; na powierzchniach tintowanych (banda capa, karty przewodnika) — `--indigo-tint` z obrysem `#cdcef0`.
- **Sygnatura gestu:** w hero drugi klawisz „C" (`.kbd-2`) jest **koralowy** — wizualnie oddziela „stuknij drugi raz", który uruchamia akcję.

### Cards / Containers
- **Phase (przewodnik):** dwukolumnowa karta na badge'u kroku, róg 16px, obrys `--line`, cień Card, hover unosi o 3px i rozjaśnia obrys. Łączone pionową linią-gradientem między krokami (1→2 indygo, 2→3 do koralu).
- **Capability (`.vcard`):** bez pudełka — tylko **górny** pasek 2px (indygo / koral / indygo-głębokie naprzemiennie), ikona + tytuł + opis. Świadomie nie ramka, by uniknąć powtarzalnej siatki kart.
- **Shot (showcase):** odtworzony panel na gradientowym „ekranie" z kropkami traffic-light, prezentujący stany popupu (klikalne słowa, „Dlaczego tak?", edytowalne źródło, diff poprawki).
- **Border:** pełne obrysy lub górne paski; **nigdy** kolorowy `border-left/right` jako akcent.

### Panel / Popup (signature component)
Wierne odtworzenie okna Glosso: pasek czasowników (Tłumacz / Streść / Popraw — aktywny ma tło `#e5e7fb` i tekst indygo-głębokie), akcje (kopiuj, zamknij), dwukolumnowe ciało ORYGINAŁ | POPRAWKA, diff (usunięcia `#c0492f` przekreślone, wstawienia indygo-głębokie pogrubione), rozwijane „Dlaczego poprawiono?" z cytatem reguły RJP. Tło białe, róg 16px, cień Panel, uchwyt resize w rogu. To bohater strony — renderowany w HTML, bo TCC blokuje zrzuty natywnych okien.

### Navigation
- **Style:** sticky, tło `rgba(21,23,63,.92)` z `backdrop-filter: blur(8px)`, dolny obrys w bieli półprzezroczystej. Brand (Bricolage 800) + linki `rgba(255,255,255,.82)` (hover do bieli) + koralowy CTA „Pobierz".
- **Mobile (≤720px):** linki nawigacyjne znikają poza ostatnim; CTA zostaje. Kotwice mają `scroll-margin-top` pod sticky-nav.

### Inputs (reprezentowane)
Edytowalne źródło w panelu pokazane stanem `--edit`: obrys indygo + glow `0 0 0 2px rgba(79,91,216,.18)`, dolna linia kreskowana, migający koralowo-indygowy karet. To wzorzec „popraw w źródle i puść ponownie".

## 6. Do's and Don'ts

### Do:
- **Do** czyń bohaterem odtworzony panel/gest, nie nagłówek — „pokaż gest, nie opowiadaj o nim".
- **Do** zalewaj sekcje kluczowe indygo (hero, filary, domknięcie) i przeplataj je oddechem bieli/`--indigo-tint`.
- **Do** rezerwuj koral dla akcji i sygnaturowego klawisza „C" (Reguła Jednego Koralu).
- **Do** trzymaj biały tekst na pełnej sile indygo (≥4.5:1); tekst drugorzędny w `--ink-soft`, nie jaśniejszy.
- **Do** używaj fontu systemowego macOS w elementach udających UI; Bricolage zostaw narracji.
- **Do** trzymaj cienie miękkie i barwione atramentem — unoszenie macOS, nie twarde kontury.
- **Do** dawaj `@media (prefers-reduced-motion: reduce)` do każdego ruchu; treść widoczna domyślnie (`@starting-style`, nie ukrywanie JS-em).

### Don't:
- **Don't** rób generycznego landingu SaaS: gradientowych blobów, „hero metric" (wielka liczba + drobny label), powtarzalnych siatek kart ikona+nagłówek+tekst.
- **Don't** schodź w estetykę startupu AI/ML: ciemne tło z neonem, „terminal vibe", przesadny glow.
- **Don't** buduj ciężkiej korporacyjnej strony: stocków, banerów cookie, nadmiaru sekcji, pustosłowia.
- **Don't** powtarzaj małego tracked eyebrow nad każdą sekcją — tylko jeden, w hero.
- **Don't** używaj `border-left`/`border-right` >1px jako kolorowego paska akcentu (górny pasek `.vcard` jest OK).
- **Don't** kładź białego tekstu na pastelowym indygo ani nie rozjaśniaj tekstu „dla elegancji".
- **Don't** wpuszczaj Bricolage do odtworzonego okna Glosso — to łamie wierność macOS.
