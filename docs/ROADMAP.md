# Roadmapa

Propozycje produktowe dla Glosso. Powstały z roju ideacyjnego (6 perspektyw, każda na ślepo), a potem przesiał je panel trzech product-managerów. Z 24 pomysłów zostało 17, które po scaleniu duplikatów i uszeregowaniu dały 7 propozycji poniżej. Podział na poziomy odzwierciedla wartość dla użytkownika (wow razy użyteczność), nie trudność wdrożenia.

## Propozycje

### P1 — Flagowe

#### Snap-to-translate: OCR dowolnego tekstu na ekranie
Czasem tekstu nie da się zaznaczyć: zrzut ekranu od kolegi, PDF będący obrazem, obcojęzyczny interfejs aplikacji, mem, zatrzymana klatka filmu. Użytkownik zaznacza fragment ekranu znanym gestem zrzutu z macOS, a ten sam pływający panel streamuje tłumaczenie pod kursorem. Rozpoznawanie tekstu działa lokalnie przez Vision (`VNRecognizeTextRequest`), więc zawartość ekranu nigdy nie opuszcza komputera. Moduł przechwytywania jest już ukryty za protokołem, więc trzecie źródło zasila niezmieniony łańcuch LLM → popup → paleta akcji.
**Dlaczego wygrywa:** rozbija jedyny twardy limit Glosso, czyli tylko zaznaczalny tekst. „Prywatne tłumaczenie zrzutów ekranu, w całości na urządzeniu" to jednozdaniowe demo, którego nie powtórzy żaden rywal z OCR-em w chmurze (DeepL, Google, Apple), a wykorzystanie całego istniejącego łańcucha sprawia, że jest tanie.

#### Grammar-diff: pokaż uczącemu się, *co* poprawka zmieniła i *dlaczego*
Gdy uczący się uruchamia **Popraw** na swoim tekście w drugim języku, Glosso nie podmienia po cichu czystego tekstu, tylko pokazuje różnicę w linii (przekreślony błąd → poprawka) i pozwala dotknąć każdej zmiany, żeby zobaczyć jednozdaniowy powód po polsku ("brak rodzajnika", "zła forma czasu przeszłego"). Ten sam audyt sprawia, że bezgłowa poprawka Cmd+Ctrl+G staje się godna zaufania: krótkie mignięcie różnicy pokazuje dokładnie, co zostało zmienione, bez pytania. Korzysta z gotowej maszynerii klikalnych słów i objaśnień per-słowo, która działa już przy tłumaczeniach.
**Dlaczego wygrywa:** zamienia najczęściej używany czasownik dla uczących się z cichego autokorektora w prywatną, lokalną informację zwrotną typu „dotknij i ucz się". Przy okazji zdejmuje jedyną straszną rzecz z najodważniejszej funkcji (cicha edycja w miejscu), dając możliwość weryfikacji. Tego połączenia nie da offline ani chmurowy Grammarly, ani DeepL czy Apple podające sam czysty tekst.

### P2 — Mocna wartość

#### Gotowość przy pierwszym uruchomieniu i pewne pierwsze tłumaczenie
Lokalny LLM to atut Glosso, ale też jego pułapka cichej awarii. Nowy użytkownik kopiuje tekst i nic nie widzi (Ollama nie działa, brak pobranego modelu albo domyślny model ~26B nie jest zainstalowany), więc rezygnuje, zanim dotrze do magicznego momentu. Zamień zawsze pokazywane „aktywny" na prawdziwy panel gotowości (Accessibility / Ollama osiągalna / wczytany działający model, każde jako kropka plus jednolinijkowa podpowiedź), zamień błąd „model not found" na klikalne podpowiedzi z modeli, które użytkownik *ma*, i dodaj przycisk „Przetłumacz przykład", który streamuje wbudowane zdanie, żeby pokazać, że to działa, zanim ktoś zacznie szukać tekstu. Podpis na zimnym starcie ("Ładuję model — pierwsze uruchomienie bywa wolniejsze…") obsłuży 10–30 s pierwszego wczytania. Cała instalacja (lister modeli, błąd osiągalności, prewarm) już istnieje; to składanie UI.
**Dlaczego wygrywa:** chroni najbardziej ryzykowne pięć minut aplikacji z lokalnym LLM, zamieniając najbardziej prawdopodobną porażkę świeżej instalacji w pewną aktywację. To dokładnie ten próg wejścia, którego rywale z chmury nie muszą rozwiązywać.

#### Trener rejestru: wyjaśnij zmianę tonu, nie tylko ją przełącz
Gdy użytkownik przełącza pigułkę tonu (Automatyczny → Formalny → Nieformalny) i tekst tłumaczy się na nowo, dodaj małą opcję „co się zmieniło?", która po polsku wyjaśnia, które słowa i zaimki się zmieniły i dlaczego: niemieckie Sie→du, francuskie vous→tu, porzucone złagodzenia. Ślepe ponowne tłumaczenie staje się czytelnym kontrastem w systemie grzecznościowym języka z rozróżnieniem ty/pan. Korzysta niemal w całości z istniejących mechanizmów formalności, ponownego tłumaczenia i wyjaśniania.
**Dlaczego wygrywa:** cała teza Glosso w jednej funkcji. To jedyny tłumacz, który *uczy* systemu grzecznościowego, pokazując konkretne zmiany zaimków i rejestru. Tej korzyści dla uczących się nie da cichy przełącznik formal/informal w DeepL ani Apple czy Google.

### P3 — Obiecujący zakład

#### Posłuchaj: dotknij, żeby usłyszeć słowo lub całe tłumaczenie
Mały przycisk głośnika przy wyniku, a także w rozwijanej liście klikniętego słowa obok „Dlaczego tak?", odczytuje tekst na głos przez wbudowany w macOS `AVSpeechSynthesizer` głosem języka docelowego. Uczący się, który właśnie dostał niemieckie albo francuskie tłumaczenie, od razu słyszy, jak to brzmi, bez wychodzenia z panelu i otwierania innej aplikacji. Kody `SecondLanguage` (en/de/ru/es/nl/fr) zasilają `AVSpeechSynthesisVoice` wprost, a żaden istniejący kod audio nie wejdzie tu w konflikt.
**Dlaczego wygrywa:** domyka pętlę nauki, którą produkt już realizuje: przeczytaj, zrozum *dlaczego*, a potem *usłysz*. Wszystko offline, w miejscu, bez nowych uprawnień i bardzo tanie do zrobienia.

#### Glosso jako element automatyzacji macOS (App Intents / Skróty)
Wystaw istniejące czasowniki jako App Intents („Przetłumacz tekst", „Popraw gramatykę", „Streść", „Wyjaśnij słowo"), które przyjmują tekst, język docelowy i ton, a zwracają wynik lokalnie. Użytkownik wrzuca Glosso do Skrótu, do Quick Action na zaznaczonym tekście w Finderze, pod przycisk Stream Decka albo do automatyzacji trybu skupienia. Dziennikarz przerabia Quick Action niemiecki cytat na polski, nauczyciel streszcza hurtem odpowiedzi uczniów. Czasowniki są już czystymi funkcjami odciętymi od popupu, więc robota to okablowanie, nie nowa logika.
**Dlaczego wygrywa:** zamienia popup z jednym wyzwalaczem w prywatny klocek do automatyzacji na urządzeniu. Wystawienie `explain` i `alternatives` na poziomie dla uczących się jako Intentów to powierzchnia, której DeepL i Google nie wydadzą bez rundy do chmury.
