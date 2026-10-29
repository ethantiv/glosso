# Feature Specification: Mowa w Glosso (lokalny model lfm3-audio)

**Feature Branch**: `001-speech-lfm3-audio`

**Created**: 2026-10-28

**Status**: Draft

**Input**: User description: "Dodaj do aplikacji obsługę modelu lfm3-audio: czytanie przetłumaczonego artykułu na głos w czytniku, tłumaczenie mowy pod przytrzymanym skrótem i odsłuch wyniku z panelu tłumaczenia. Model pobiera się przy pierwszym użyciu. Sprawdź szczegóły w dokumentacji Ollamy (capabilities/speech)."

> **Zmiana zakresu (2026-10-29, v0.28.0):** US3 (tłumaczenie mowy pod przytrzymanym skrótem) usunięta na prośbę użytkownika — do dyktowania służy dyktowanie macOS. Zostaje sama synteza mowy (US1, US2); FR-030…FR-036 nie obowiązują.

Wykonalność potwierdzono testem na lokalnej Ollamie 0.40.12 przed napisaniem specyfikacji. Wyniki są w [feasibility.md](feasibility.md).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Odsłuch tłumaczenia z panelu (Priority: P1)

Użytkownik przetłumaczył zaznaczenie podwójnym Cmd+C i chce usłyszeć, jak wynik brzmi. Klika przycisk głośnika w panelu tłumaczenia, a aplikacja czyta wynik na głos w jego języku: polski polskim głosem, angielski angielskim. Drugie kliknięcie zatrzymuje odtwarzanie.

**Why this priority**: To najmniejszy fragment, który dostarcza całą ścieżkę mowy: pobranie modelu na żądanie, syntezę i odtwarzanie. Czytanie w czytniku (US2) używa tej samej ścieżki, więc US1 jest jej pierwszym, samodzielnym zastosowaniem.

**Independent Test**: Przetłumacz zdanie z `docs/test-sentences.txt`, kliknij głośnik i sprawdź, że słychać wynik w języku tłumaczenia, a drugie kliknięcie przerywa odtwarzanie.

**Acceptance Scenarios**:

1. **Given** panel pokazuje gotowe tłumaczenie na angielski, **When** użytkownik kliknie głośnik, **Then** aplikacja odtwarza tekst angielskim głosem, a przycisk pokazuje stan „odtwarzanie”.
2. **Given** trwa odtwarzanie, **When** użytkownik kliknie głośnik ponownie, naciśnie Esc albo panel się zamknie, **Then** odtwarzanie natychmiast się kończy.
3. **Given** wynik jeszcze się generuje, **When** użytkownik patrzy na panel, **Then** przycisk głośnika jest niewidoczny do zakończenia generowania, tak jak przycisk kopiowania.
4. **Given** model mowy nie jest jeszcze pobrany, **When** użytkownik pierwszy raz kliknie głośnik, **Then** aplikacja informuje o pobieraniu (rozmiar około 2 GB), pokazuje postęp, a po pobraniu odtwarza wynik bez ponownego kliknięcia.

---

### User Story 2 - „Czytaj na głos” w czytniku (Priority: P2)

Użytkownik otworzył artykuł w oknie czytnika. Wybiera „Czytaj na głos” i słucha przetłumaczonego artykułu od początku. Pierwszy fragment zaczyna grać, zanim przygotują się kolejne. Może wstrzymać, wznowić albo zatrzymać czytanie.

**Why this priority**: Daje najwięcej przy długich artykułach, ale zależy od tej samej ścieżki co US1 i jest od niej większe (kolejka fragmentów, sterowanie odtwarzaniem).

**Independent Test**: Otwórz długi artykuł w czytniku, włącz czytanie i zmierz czas do pierwszego dźwięku. Sprawdź, że fragmenty grają po kolei bez pominięć i że pauza, wznowienie i stop działają.

**Acceptance Scenarios**:

1. **Given** czytnik pokazuje przetłumaczony artykuł, **When** użytkownik wybierze „Czytaj na głos”, **Then** czytanie zaczyna się od tytułu i pierwszego fragmentu, a kolejne fragmenty grają w kolejności artykułu bez słyszalnych przerw dłuższych niż 1 s.
2. **Given** trwa czytanie, **When** użytkownik wybierze pauzę, a potem wznowienie, **Then** czytanie wraca w miejscu przerwania.
3. **Given** trwa czytanie, **When** użytkownik zatrzyma je albo zamknie okno czytnika, **Then** dźwięk kończy się natychmiast, a przygotowywanie kolejnych fragmentów ustaje.
4. **Given** tłumaczenie artykułu wciąż trwa, **When** użytkownik włączy czytanie, **Then** czytanie obejmuje fragmenty już przetłumaczone i czeka na kolejne, zamiast czytać tekst oryginału.

---

### User Story 3 - Tłumaczenie mowy (Priority: P3)

Użytkownik przytrzymuje skrót klawiszowy, mówi zdanie po polsku (albo po angielsku) i puszcza klawisz. W tym samym panelu co dziś pojawia się tłumaczenie powiedzianego zdania, tak jakby skopiował ten tekst podwójnym Cmd+C.

**Why this priority**: Nowy sposób wejścia z największą liczbą nowych elementów: uprawnienie do mikrofonu, przytrzymywany skrót i nagrywanie. Pozostałe historie go nie potrzebują.

**Independent Test**: Przypisz skrót w Ustawieniach, przytrzymaj go, przeczytaj na głos zdanie z `docs/test-sentences.txt` i sprawdź, że panel pokazuje jego tłumaczenie w drugim języku pary.

**Acceptance Scenarios**:

1. **Given** skrót mowy jest przypisany, a mikrofon dozwolony, **When** użytkownik przytrzyma skrót, powie zdanie i puści klawisz, **Then** panel przy kursorze pokazuje tłumaczenie w przeciwnym kierunku niż język wypowiedzi.
2. **Given** użytkownik trzyma skrót, **When** nagrywanie trwa, **Then** aplikacja wyraźnie pokazuje, że słucha (np. w ikonie paska menu).
3. **Given** aplikacja nie ma jeszcze dostępu do mikrofonu, **When** użytkownik pierwszy raz użyje skrótu, **Then** system pyta o zgodę, a przy odmowie aplikacja wyjaśnia, jak włączyć dostęp w Ustawieniach systemowych.
4. **Given** użytkownik puścił skrót po mniej niż 0,5 s albo w nagraniu nie ma mowy, **When** kończy się nagrywanie, **Then** aplikacja niczego nie tłumaczy i krótko informuje, że nic nie usłyszała.
5. **Given** panel pokazuje wynik tłumaczenia mowy, **When** użytkownik spojrzy na panel, **Then** widzi też rozpoznany tekst wypowiedzi, żeby ocenić błędy rozpoznania.

---

### Edge Cases

- Użytkownik korzysta z dostawcy chmurowego (Google, Ollama Cloud): funkcje mowy i tak działają lokalnie, a tłumaczenie tekstu w US3 idzie do aktualnego dostawcy jak dziś.
- Silnik lokalny nie jest zainstalowany: funkcja mowy pokazuje ten sam komunikat co dziś tłumaczenie, kierujący do pobrania silnika w Ustawieniach.
- Silnik jest za stary i nie obsługuje mowy: aplikacja pokazuje komunikat z prośbą o aktualizację Ollamy, zamiast cichego błędu.
- Pobieranie modelu nie powiodło się albo brakuje miejsca na dysku: komunikat z przyczyną, możliwość ponowienia przy następnym użyciu.
- Bardzo długi fragment artykułu albo długi wynik w panelu: tekst jest czytany w całości, bez ucinania.
- Tekst zawiera fragmenty, których nie da się sensownie przeczytać (adresy URL, bloki kodu, tabele): czytnik je pomija.
- Odtwarzanie z panelu trwa, a użytkownik uruchamia nowe tłumaczenie: poprzednie odtwarzanie kończy się.
- Czytanie w czytniku trwa, a użytkownik klika głośnik w panelu: w danej chwili gra tylko jedno źródło dźwięku; nowe zatrzymuje poprzednie.
- Nagranie przekracza 2 minuty: nagrywanie kończy się automatycznie, a nagrane 2 minuty są przetwarzane po puszczeniu skrótu.
- Wypowiedź jest w języku spoza pary: obowiązuje to samo zachowanie co przy tekście, gdy kierunku tłumaczenia nie da się ustalić.
- Skrót mowy koliduje z istniejącym skrótem: Ustawienia odrzucają przypisanie jak przy obecnych skrótach.

## Requirements *(mandatory)*

### Functional Requirements

**Wspólne**

- **FR-001**: Aplikacja MUSI pobierać model mowy przy pierwszym użyciu dowolnej funkcji mowy, z informacją o rozmiarze i postępem, tak jak dziś pobiera modele tekstowe. Bez użycia funkcji mowy model nie jest pobierany, chyba że użytkownik sam wybierze „Pobierz model mowy” w ostatnim kroku kreatora pierwszego uruchomienia.
- **FR-002**: Synteza i rozpoznawanie mowy MUSZĄ działać lokalnie, niezależnie od wybranego dostawcy tłumaczenia. Dźwięk (nagrania i synteza) nie opuszcza Maca. Rozpoznany tekst wypowiedzi trafia do wybranego dostawcy tłumaczenia tak jak każdy inny tekst (FR-032).
- **FR-003**: Aplikacja MUSI wybierać głos według języka czytanego tekstu (polski albo angielski). Użytkownik MUSI móc wybrać głos żeński albo męski (menu paska, obok języków).
- **FR-004**: W danej chwili MOŻE grać tylko jedno odtwarzanie. Rozpoczęcie nowego kończy poprzednie.
- **FR-005**: Każdy błąd funkcji mowy (brak silnika, za stary silnik, brak modelu, błąd pobierania, brak mikrofonu) MUSI skończyć się zrozumiałym komunikatem, a nie ciszą.
- **FR-006**: Wszystkie nowe teksty interfejsu MUSZĄ mieć wersję polską i angielską.

**Panel tłumaczenia (US1)**

- **FR-010**: Panel tłumaczenia MUSI mieć przycisk odsłuchu aktywny po zakończeniu generowania wyniku.
- **FR-011**: Kliknięcie przycisku w trakcie odtwarzania, Esc albo zamknięcie panelu MUSZĄ zatrzymać odtwarzanie.
- **FR-012**: Odsłuch dotyczy wyniku wyświetlanego w panelu: tłumaczenia albo poprawionego tekstu.

**Czytnik (US2)**

- **FR-020**: Okno czytnika MUSI mieć polecenie „Czytaj na głos” z pauzą, wznowieniem i zatrzymaniem.
- **FR-021**: Czytanie MUSI iść fragmentami w kolejności artykułu. Pierwszy fragment gra, zanim przygotowane zostaną następne, a kolejny jest przygotowywany w tle podczas odtwarzania bieżącego.
- **FR-022**: Czytanie MUSI używać przetłumaczonego tekstu. Fragmenty jeszcze nieprzetłumaczone są czytane dopiero po przetłumaczeniu.
- **FR-023**: Zamknięcie okna czytnika albo zatrzymanie czytania MUSI przerwać odtwarzanie i przygotowywanie kolejnych fragmentów.

**Tłumaczenie mowy (US3)**

- **FR-030**: Użytkownik MUSI móc przypisać w Ustawieniach skrót „przytrzymaj, aby mówić”. Domyślnie skrót jest nieprzypisany.
- **FR-031**: Nagrywanie trwa, dopóki skrót jest przytrzymany, najdłużej 2 minuty.
- **FR-032**: Rozpoznany tekst wypowiedzi MUSI przejść przez tę samą ścieżkę tłumaczenia co tekst ze schowka: wykrywanie kierunku, aktualnego dostawcę, panel i pamięć podręczną wyników.
- **FR-033**: Panel MUSI pokazywać rozpoznany tekst wypowiedzi obok tłumaczenia.
- **FR-034**: Aplikacja MUSI prosić o dostęp do mikrofonu dopiero przy pierwszym użyciu skrótu mowy, nie przy starcie ani podczas onboardingu.
- **FR-035**: Nagranie krótsze niż 0,5 s albo bez rozpoznanej mowy NIE MOŻE uruchomić tłumaczenia.
- **FR-036**: Nagrania NIE MOGĄ być zapisywane na dysku dłużej, niż trwa ich przetwarzanie.

### Key Entities

- **Głos**: płeć (żeński/męski) wybrana przez użytkownika i język wynikający z czytanego tekstu.
- **Fragment do przeczytania**: kawałek przetłumaczonego tekstu z czytnika albo panelu, w kolejności czytania. Fragment czytnika może czekać na tłumaczenie.
- **Wypowiedź**: nagranie od przytrzymania do puszczenia skrótu i rozpoznany z niego tekst; istnieje tylko podczas przetwarzania.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Przy pobranym i rozgrzanym modelu odtwarzanie z panelu zaczyna się w mniej niż 1 s od kliknięcia dla wyniku do 300 znaków.
- **SC-002**: W czytniku pierwszy dźwięk pada w mniej niż 2 s od „Czytaj na głos” (model rozgrzany), niezależnie od długości artykułu.
- **SC-003**: Podczas czytania artykułu przerwy między fragmentami nie przekraczają 1 s.
- **SC-004**: Dla wypowiedzi do 15 s tłumaczenie zaczyna się pojawiać w panelu w mniej niż 3 s od puszczenia skrótu (model rozgrzany, dostawca lokalny).
- **SC-005**: Dla 10 zdań z `docs/test-sentences.txt` przeczytanych na głos co najmniej 9 tłumaczeń oddaje sens wypowiedzi.
- **SC-006**: Użytkownik, który nie używa funkcji mowy, nie zauważa zmian: nie pobiera się dodatkowy model, nie pojawia się prośba o mikrofon, a czas tłumaczenia tekstu się nie zmienia.

## Assumptions

- Funkcje mowy korzystają z tego samego lokalnego silnika Ollama, którym Glosso już zarządza. Wymagana jest wersja z obsługą mowy; test przeszedł na 0.40.12.
- Model mowy (około 2 GB) mieści się obok `gemma4:26b-mlx` na docelowych Macach z Apple Silicon.
- Model mowy rozpoznaje wypowiedź, ale tłumaczy ją istniejąca ścieżka tekstowa. W teście tłumaczenie wprost z mowy przez model mowy było słabe („Green morning” zamiast „Good morning”), a rozpoznanie poprawne. Ta decyzja daje też spójność z tłumaczeniem tekstu (kierunek, dostawca, pamięć podręczna).
- Zakres to polski i angielski, czyli para, którą Glosso dziś obsługuje. Model zna 18 języków, ale inne pary nie są celem tej funkcji.
- Czytnik czyta tylko tekst tłumaczenia, bez podświetlania czytanego fragmentu. Podświetlanie, zapis audio do pliku, zmiana tempa mowy i czytanie oryginału są poza zakresem.
- Synteza audio nie jest zapisywana w pamięci podręcznej. Ponowny odsłuch generuje ją jeszcze raz, co przy zmierzonych czasach jest akceptowalne.
- Pomysły dla innych repozytoriów (`audiobook-wrapper`, `elden-ring-checklist`) są poza zakresem.
