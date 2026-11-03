# Feature Specification: Synonimy słowa w poprawionym tekście (akcja „Popraw”)

**Feature Branch**: `002-fix-word-synonyms`

**Created**: 2026-11-03

**Status**: Draft

**Input**: User description: "dodaj w trybie tłumacza dla akcji popraw wyszukiwanie synonimów dla wybranego słowa analogicznie do tego jak to działa w tłumaczeniu"

## Clarifications

### Session 2026-11-03

- Q: W którym miejscu kliknięcie słowa w poprawionym tekście ma pokazywać synonimy? → A: W obu miejscach, w których działa akcja „Popraw”: w panelu otwieranym podwójnym Cmd+C i w oknie Tłumacz… z menu paska.
- Q: Co ma się pojawić po kliknięciu fragmentu, który poprawka zmieniła? → A: Jedno menu jak w tłumaczeniu: u góry wiersz „Dlaczego poprawiono?” (otwiera powód, wraca strzałką „wstecz”), pod nim synonimy poprawionego fragmentu. Niezmienione słowa dostają to samo menu bez wiersza z powodem.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Synonimy klikniętego słowa w poprawionym tekście (Priority: P1)

Użytkownik wybiera akcję „Popraw” w panelu po podwójnym Cmd+C albo w oknie Tłumacz…. Po poprawieniu tekstu klika dowolne słowo w wyniku, także fragment zmieniony przez poprawkę. Pod słowem otwiera się lista synonimów pasujących do kontekstu zdania, w tym samym języku co tekst. Działa to tak samo jak lista alternatyw po kliknięciu słowa w tłumaczeniu: ten sam wygląd, wskaźnik ładowania, komunikat przy braku wyników, zamknięcie klawiszem Esc albo kliknięciem obok.

**Why this priority**: Bez listy synonimów nie ma funkcji. Sama lista już pomaga dobrać lepsze słowo, nawet bez automatycznej podmiany.

**Independent Test**: W panelu po podwójnym Cmd+C i w oknie Tłumacz… poprawić zdanie, kliknąć niezmienione słowo i poprawiony fragment, i sprawdzić, że lista pokazuje synonimy w języku tekstu, a nie tłumaczenia, a przy poprawionym fragmencie u góry jest też „Dlaczego poprawiono?”.

**Acceptance Scenarios**:

1. **Given** panel albo okno Tłumacz… z gotowym wynikiem akcji „Popraw” w języku polskim, **When** użytkownik klika słowo „szybko”, **Then** pod słowem pojawia się lista do 6 polskich synonimów pasujących do kontekstu (np. „prędko”, „błyskawicznie”), bez powtórzenia samego słowa.
2. **Given** otwarta lista synonimów, **When** wyniki jeszcze się ładują, **Then** lista pokazuje wskaźnik „Szukam synonimów…”.
3. **Given** model nie zwrócił żadnego synonimu albo wystąpił błąd, **When** ładowanie się kończy, **Then** lista pokazuje „Brak synonimów”, a poprawiony tekst zostaje bez zmian.
4. **Given** lista synonimów dla słowa była już raz pobrana, **When** użytkownik ponownie klika to samo słowo w tym samym wyniku, **Then** lista pojawia się od razu, bez ponownego zapytania.
5. **Given** wynik, w którym poprawka zmieniła „szybko” na „szybciej”, **When** użytkownik klika „szybciej”, **Then** menu pokazuje u góry wiersz „Dlaczego poprawiono?”, a pod nim synonimy „szybciej” (np. „prędzej”); powód poprawki nie jest jeszcze pobierany.
6. **Given** otwarte menu poprawionego fragmentu, **When** użytkownik klika „Dlaczego poprawiono?”, **Then** menu pokazuje powód poprawki ze strzałką „wstecz”, a strzałka albo Esc wraca do listy synonimów bez ponownego pobierania.
7. **Given** wynik, w którym poprawka zmieniła kilka słów naraz (np. „w ogóle” zamiast „wogóle”), **When** użytkownik klika ten fragment, **Then** synonimy dotyczą całego fragmentu jako frazy.

---

### User Story 2 - Podmiana słowa na wybrany synonim (Priority: P2)

Użytkownik wybiera synonim z listy. Glosso podmienia słowo w poprawionym tekście i dopasowuje do niego resztę zdania (odmianę, uzgodnienie rodzaju i liczby), tak jak wybór alternatywy w tłumaczeniu przebudowuje tłumaczenie. Użytkownik może cofnąć podmianę.

**Why this priority**: Domyka przepływ: wybór synonimu bez ręcznego przepisywania. Wymaga działającej listy z US1.

**Independent Test**: Poprawić zdanie, kliknąć słowo, wybrać synonim i sprawdzić, że wynik zawiera synonim w poprawnej formie gramatycznej, a „Cofnij” przywraca poprzednią wersję.

**Acceptance Scenarios**:

1. **Given** lista synonimów dla słowa „dom” w zdaniu „Kupiłem nowy dom”, **When** użytkownik wybiera „mieszkanie”, **Then** wynik zmienia się na „Kupiłem nowe mieszkanie” (przymiotnik uzgodniony z rodzajem).
2. **Given** podmiana synonimu zakończona, **When** użytkownik używa „Cofnij”, **Then** wraca poprzednia wersja poprawionego tekstu.
3. **Given** podmiana synonimu zakończona, **When** użytkownik patrzy na widok zmian, **Then** zmiany są liczone względem tekstu wejściowego, więc podmienione słowo widać jako zmianę.
4. **Given** podmiana synonimu, **When** model przebudowuje zdanie, **Then** pozostała część tekstu poza dopasowaniem gramatycznym zostaje bez zmian.

---

### Edge Cases

- Poprawka, która nie dodała żadnego słowa (tylko usunęła tekst albo zmieniła interpunkcję): kliknięcie pokazuje w menu wyłącznie powód poprawki, bez listy synonimów.
- Podmiana synonimu w poprawionym fragmencie: fragment nadal jest oznaczony jako zmiana względem tekstu wejściowego, a „Dlaczego poprawiono?” dotyczy już nowej wersji (wcześniej pobrany powód przestaje obowiązywać).
- Kliknięcie słowa, gdy trwa jeszcze strumieniowanie wyniku: słowa nie są klikalne, dopóki wynik nie jest gotowy (jak w tłumaczeniu).
- Zmiana akcji, języka albo nowy tekst wejściowy w trakcie ładowania synonimów: spóźniona odpowiedź nie trafia do nowej listy.
- Słowo, które nie ma sensownych synonimów (np. nazwa własna, liczba, spójnik): lista pokazuje „Brak synonimów”.
- Kliknięcie znaku interpunkcyjnego lub odstępu: nic się nie dzieje.
- Dostawca chmurowy przekracza limit albo milczy: obowiązuje to samo przełączenie na model lokalny co dla alternatyw w tłumaczeniu.
- Tryb podzielony (zmiany nad poprawioną wersją): synonimy działają dla słów w widoku zmian; jeśli widok zmian jest ukryty, dla słów w poprawionej wersji.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: W panelu otwieranym podwójnym Cmd+C i w oknie Tłumacz…, przy akcji „Popraw” i gotowym wyniku, każde słowo poprawionego tekstu, także fragmenty zmienione przez poprawkę, MUSI dać się kliknąć i podświetlać się po najechaniu, tak jak słowa w tłumaczeniu.
- **FR-002**: Kliknięcie słowa MUSI otworzyć listę do 6 synonimów w języku poprawionego tekstu, dobranych do kontekstu zdania, bez powtórzenia klikniętego słowa.
- **FR-003**: Lista MUSI pokazywać stan ładowania, stan „Brak synonimów” oraz wyniki, w tym samym wyglądzie co lista alternatyw w tłumaczeniu, z tekstami „Szukam synonimów…” i „Brak synonimów” w obu językach interfejsu.
- **FR-004**: Menu niezmienionego słowa NIE MOŻE zawierać przycisku „Dlaczego tak?”, bo słowo nie pochodzi z tłumaczenia.
- **FR-005**: Wybór synonimu MUSI podmienić słowo w poprawionym tekście i dopasować gramatycznie zdanie, w którym stoi, bez innych zmian w tekście.
- **FR-006**: Przed podmianą system MUSI zapamiętać poprzedni wynik, aby „Cofnij” go przywrócił.
- **FR-007**: Po podmianie widok zmian MUSI porównywać tekst wejściowy z nowym wynikiem.
- **FR-008**: Pobrane synonimy MUSZĄ być pamiętane dla danego słowa do czasu zmiany wyniku, tak jak alternatywy w tłumaczeniu.
- **FR-009**: Menu fragmentu zmienionego przez poprawkę MUSI mieć u góry wiersz „Dlaczego poprawiono?”, a pod nim synonimy całego dodanego fragmentu. Powód MUSI być pobierany dopiero po kliknięciu tego wiersza; widok powodu MUSI mieć strzałkę „wstecz” do listy synonimów. Gdy poprawka nie dodała żadnego słowa (samo usunięcie albo sama interpunkcja), menu MUSI pokazywać od razu sam powód.
- **FR-010**: Zapytania o synonimy MUSZĄ korzystać z aktywnego dostawcy i modelu oraz z tych samych reguł przełączania na model lokalny co alternatywy w tłumaczeniu.
- **FR-011**: Treść tekstu przekazana modelowi MUSI być traktowana jako dane, a nie polecenia, tak jak w obecnych zapytaniach o alternatywy.

### Key Entities

- **Synonim**: słowo lub krótka fraza w języku poprawionego tekstu, zastępująca kliknięte słowo w danym kontekście.
- **Wynik poprawy**: poprawiony tekst wraz z tekstem wejściowym; po wyborze synonimu staje się nową wersją z możliwością cofnięcia.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Na zdaniach z `docs/test-sentences.txt` co najmniej 4 z 5 kliknięć w zwykłe słowa (rzeczowniki, czasowniki, przymiotniki, przysłówki) zwraca co najmniej 2 trafne synonimy w języku tekstu.
- **SC-002**: Lista synonimów pojawia się z wynikami w podobnym czasie co lista alternatyw w tłumaczeniu na tym samym modelu (nie dłużej niż o 20%).
- **SC-003**: W 9 na 10 podmian wynik jest gramatycznie poprawny i różni się od poprzedniej wersji tylko w zdaniu z podmienionym słowem.
- **SC-004**: Użytkownik zmienia słowo na synonim w nie więcej niż 2 kliknięciach od gotowego wyniku.

## Assumptions

- Funkcja działa wszędzie tam, gdzie działa akcja „Popraw”: w panelu po podwójnym Cmd+C i w oknie Tłumacz…. Tłumaczenie w obu miejscach już ma alternatywy słów i się nie zmienia.
- Pokazanie powodu poprawki wymaga teraz jednego kliknięcia więcej niż dotąd; to świadomy koszt jednolitego menu i jednego zapytania do modelu na kliknięcie.
- Synonimy są w języku poprawionego tekstu (akcja „Popraw” nie zmienia języka).
- Cofanie i pamięć podręczna synonimów działają tak jak dla alternatyw w tłumaczeniu.
- Wybór synonimu nie zmienia ustawionej formalności ani nie poprawia ponownie całego tekstu.
