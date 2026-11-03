# Quickstart: walidacja synonimów w akcji „Popraw”

## Testy automatyczne (offline)

```bash
scripts/test.sh --adhoc
```

Oczekiwany wynik: wszystkie testy przechodzą, w tym nowe przypadki w `PromptBuilderTests`, `AppCoordinatorTests`, `PopupModelTests` i `PopupLayoutTests`. Liczniki pokazuje `xcrun xcresulttool get test-results summary --path <result.xcresult>`.

## Sprawdzenie ręczne (macOS, lokalny model)

1. `scripts/run.sh`.
2. Zaznacz w dowolnej aplikacji zdanie z błędem z `docs/test-sentences.txt`, wciśnij dwa razy Cmd+C i wybierz „Popraw”.
3. Kliknij niezmienione słowo. Pod nim pojawia się „Szukam synonimów…”, a potem do 6 synonimów w języku tekstu, bez wiersza „Dlaczego…”.
4. Kliknij zielony (poprawiony) fragment. U góry menu jest „Dlaczego poprawiono?”, a pod nim synonimy fragmentu. Kliknij nagłówek: pojawia się powód ze strzałką „wstecz”. Strzałka i Esc wracają do listy bez ponownego ładowania.
5. Kliknij poprawkę, która tylko usunęła tekst albo zmieniła interpunkcję. Menu pokazuje od razu sam powód.
6. Wybierz synonim. Tekst przepisuje się z dopasowaną odmianą, a w widoku zmian słowo widać jako zmianę. „Cofnij” przywraca poprzednią wersję.
7. Powtórz kroki 3–6 w oknie Tłumacz… (menu paska → Tłumacz…, akcja „Popraw”).
8. Przy więcej niż 3 zmianach (tryb podzielony) ukryj widok zmian ikoną oka. Słowa poprawionej wersji też otwierają synonimy.
9. W „Tłumacz” kliknięcie słowa dalej pokazuje alternatywy tłumaczenia i „Dlaczego tak?”.
