# Glosso

Aplikacja na pasek menu macOS, która tłumaczy albo poprawia zaznaczony tekst, gdy dwa razy naciśniesz **Cmd+C**. Wymaga macOS 26 lub nowszego.

## Instalacja

1. Pobierz `Glosso.zip` z [Releases](https://github.com/ethantiv/glosso/releases/latest), rozpakuj go i przeciągnij **Glosso.app** do folderu Aplikacje.
2. Otwórz aplikację. macOS zablokuje pierwsze uruchomienie, bo Apple nie notaryzowało aplikacji. Kliknij **Gotowe**, otwórz **Ustawienia systemowe > Prywatność i ochrona** i kliknij **Otwórz mimo to**.
3. Gdy aplikacja poprosi, przyznaj uprawnienie **Dostępność**.
4. W kreatorze pierwszego uruchomienia wybierz języki i silnik:
   - **Lokalny**: aplikacja pobiera Ollamę i model o rozmiarze 7–20 GB. Jeśli masz już Ollamę, aplikacja jej użyje.
   - **Google AI**: wklej darmowy klucz API z [Google AI Studio](https://aistudio.google.com/apikey). Zaznaczony tekst trafia wtedy poza twojego Maca.

Żeby później zmienić silnik albo użyć **Ollama Cloud** z kluczem z ollama.com, otwórz **Ustawienia** z paska menu.

## Budowanie ze źródeł

Zainstaluj [XcodeGen](https://github.com/yonaskolb/XcodeGen) i Xcode, a potem uruchom:

```bash
scripts/run.sh      # zbuduj i uruchom
scripts/test.sh     # uruchom testy
scripts/package.sh  # zbuduj podpisany .zip
```

Skrypty generują projekt Xcode z `project.yml`, więc nie edytuj ręcznie `*.xcodeproj`. Podpisywanie i wydania opisuje [`docs/DISTRIBUTION.md`](docs/DISTRIBUTION.md).

## Licencja

[MIT](LICENSE)
