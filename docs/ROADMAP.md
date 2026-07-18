## Propozycje

### P1 — flagowe

#### Tryb „Pismo urzędowe" — list z urzędu wyjaśniony po ludzku

Polak za granicą kopiuje list z Finanzamt, Belastingdienst czy banku podwójnym Cmd+C i zamiast surowego tłumaczenia dostaje kartę po polsku: kto pisze, czego żąda, do kiedy, co grozi za brak reakcji i co konkretnie zrobić. Pełne tłumaczenie zostaje pod spodem jako siatka bezpieczeństwa — model może pomylić termin, więc źródło musi być na wyciągnięcie ręki. Technicznie to nowy czasownik w istniejącej palecie (`Action`), z parsowaniem sekcji wzorem `ReplyParser`.

**Dlaczego wygrywa:** List z urzędu to moment paniki — DeepL zamieni urzędniczy bełkot na polski urzędniczy bełkot, a tu dostajesz „masz 14 dni na odwołanie, inaczej 250 EUR". Pismo z PESEL-em i kwotami nigdy nie opuszcza komputera, więc lokalność przestaje być hasłem i staje się warunkiem.

### P2 — mocna wartość

#### Tryb dwujęzyczny w Readerze

Zamiast przełącznika „oryginał albo tłumaczenie" — widok przeplatany: pod każdym polskim akapitem oryginał mniejszą, przygaszoną czcionką. Czytasz po polsku, a gdy coś brzmi podejrzanie, źródło jest zdanie niżej, bez klikania. Dane oryginał/tłumaczenie już leżą per blok w `ReaderTemplate`, więc to głównie nowy tryb renderowania w JS.

**Dlaczego wygrywa:** To sztandarowa funkcja immersive-translate, tylko że tam wymaga rozszerzenia przeglądarki, konta i chmury. Demo „wklej URL w samolocie bez Wi-Fi, czytaj dwujęzycznie" jest nie do powtórzenia przez żadnego konkurenta.

#### Profil moich błędów — dziennik poprawek z powtórkami

Każda poprawka z widoku diff w „Popraw" trafia do lokalnego dziennika z kategorią błędu dopasowaną do istniejących baz reguł (RJP, typowe błędy Polaków). Po tygodniu Glosso pokazuje „ten błąd robisz piąty raz", raportuje trzy najczęstsze wzorce z przykładami z własnych tekstów i generuje krótki quiz z prawdziwych pomyłek — nie z podręcznikowych zdań.

**Dlaczego wygrywa:** Grammarly buduje taki profil w chmurze z twoich maili, Glosso robi to w pliku na dysku — to jedno zdanie sprzedaje cały produkt. Zamienia poprawianie błędów w oduczanie się ich i daje powód, by wracać co tydzień.

#### Ton dopasowany do aplikacji źródłowej

Glosso zapamiętuje, jaki ton wybierasz w której aplikacji: kopiujesz w Slacku — dostajesz luz, w Mailu — formalnie, bez klikania pigułki za każdym razem. Pierwsze ręczne przełączenie w danej aplikacji uczy regułę; potem pigułka ustawia się sama i nadal można ją zmienić.

**Dlaczego wygrywa:** DeepL ma globalny przełącznik, który trzeba pstrykać ręcznie; Apple Translate nie ma żadnego. Systemowy agent wie, skąd pochodzi tekst — to przewaga, której okno tłumacza fizycznie nie ma. Koszt: słownik bundleId→ton, kilkadziesiąt linii bez LLM.

### P3 — obiecujący zakład

#### Osobisty glosariusz — uczony kliknięciami, edytowalny ręcznie

Wybór alternatywy słowa (reword) dziś znika wraz z popupem i model znów proponuje odrzucony wariant. Zapisujemy pary „wolę X zamiast Y" lokalnie i doklejamy pasujące do promptu w `PromptBuilder`, wzorem istniejącego groundingu reguł. Do tego ręczny edytor par „termin → zawsze tłumacz jako" w Ustawieniach — dla tłumaczy i copywriterów pracujących pod NDA, którzy nie mogą legalnie wkleić tekstu klienta do DeepL.

**Dlaczego wygrywa:** Glosariusz buduje się sam z kliknięć, które użytkownik i tak wykonuje, a wariant ręczny robi z Glosso jedyny konsumencki tłumacz honorujący prywatną terminologię jak profesjonalne CAT-y — offline i bez ich ceny. Im dłużej używasz, tym trudniej odejść.

#### Zapytaj artykuł — lokalny czat z przeczytanym tekstem

Reader ma już cały artykuł w cache: bloki oryginału, tłumaczenia i tl;dr. Pod artykułem pojawia się pole pytania: „co autor mówi o X?", „wyjaśnij ten akapit prościej". Gemma odpowiada po polsku, dostając zcache'owane bloki jako kontekst — bez ponownego fetchu, offline, w tym samym oknie.

**Dlaczego wygrywa:** Chmurowe czaty wymagają wklejania i wysyłają treść na serwer; tu pytasz o to, co właśnie czytasz, bez opuszczania okna. Infrastruktura (cache bloków, kanał JS→Swift, non-streaming call) już leży w repo.
