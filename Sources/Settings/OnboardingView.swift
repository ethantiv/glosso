import SwiftUI

struct OnboardingView: View {
    @Bindable var store: SettingsStore
    let lister: any ModelListing
    let engine: any EngineProviding
    let modelManager: any ModelManaging
    let appState: AppState
    let onOpenAccessibility: () -> Void
    let onRecheckAccessibility: () -> Void
    let onFinish: () -> Void

    private enum Step: Int, CaseIterable { case model, language, usage }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: Step = .model
    @State private var installed: [String] = []
    @State private var pulling: [String: Double] = [:]

    private let recommended = EmbeddedModelCatalog.recommended

    var body: some View {
        VStack(spacing: 0) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider()
            footer
        }
        .frame(minWidth: 520, minHeight: 470)
        .task { await refresh() }
    }

    // MARK: Header & footer

    private var header: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.title3.weight(.semibold))
            ProgressView(value: Double(step.rawValue + 1), total: Double(Step.allCases.count))
                .frame(maxWidth: 220)
                .accessibilityLabel(loc("Krok \(step.rawValue + 1) z \(Step.allCases.count)",
                                        "Step \(step.rawValue + 1) of \(Step.allCases.count)"))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var footer: some View {
        HStack {
            if step != .model {
                Button(loc("Wstecz", "Back")) { advance(by: -1) }
            }
            Spacer()
            if step == .usage {
                Button(loc("Zakończ", "Finish")) { onFinish() }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(loc("Dalej", "Next")) { advance(by: 1) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var title: String {
        switch step {
        case .model: loc("Wybierz model", "Choose a model")
        case .language: loc("Wybierz języki", "Choose your languages")
        case .usage: loc("Jak to działa", "How it works")
        }
    }

    private func advance(by delta: Int) {
        if let next = Step(rawValue: step.rawValue + delta) {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { step = next }
        }
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        switch step {
        case .model: modelStep
        case .language: languageStep
        case .usage: usageStep
        }
    }

    private var modelStep: some View {
        Form {
            Section {
                Picker(loc("Silnik tłumaczenia", "Translation engine"), selection: $store.provider) {
                    ForEach(LLMProvider.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }
            switch store.provider {
            case .cloud: cloudModelStep
            case .ollamaCloud: ollamaCloudModelStep
            case .local: localModelStep
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var ollamaCloudModelStep: some View {
        Section {
            SecureField(loc("Klucz API", "API key"), text: $store.ollamaAPIKey)
            Link(loc("Utwórz klucz na ollama.com", "Create a key on ollama.com"),
                 destination: URL(string: "https://ollama.com/settings/keys")!)
        } footer: {
            Text(loc("Tłumaczy Gemma działająca w chmurze Ollamy. Nie musisz nic pobierać, ale zaznaczony tekst opuszcza Twój komputer. Darmowy próg wystarcza do lekkiego użycia.",
                     "A Gemma running in Ollama's cloud does the work. Nothing to download, but the selected text leaves your Mac. The free tier covers light use."))
        }
    }

    @ViewBuilder private var cloudModelStep: some View {
        Section {
            SecureField(loc("Klucz API", "API key"), text: $store.apiKey)
            Link(loc("Pobierz darmowy klucz w Google AI Studio",
                     "Get a free key in Google AI Studio"),
                 destination: URL(string: "https://aistudio.google.com/apikey")!)
            Picker(loc("Model", "Model"), selection: $store.cloudModel) {
                ForEach(CloudModelCatalog.models, id: \.id) { entry in
                    Label(entry.displayName, systemImage: entry.icon).tag(entry.id)
                }
            }
            .pickerStyle(.radioGroup)
        } footer: {
            Text(loc("Tłumaczy model działający u Google. Nie musisz nic pobierać, ale zaznaczony tekst opuszcza Twój komputer. Klucz jest darmowy.",
                     "A model running at Google does the work. Nothing to download, but the selected text leaves your Mac. The key is free."))
        }
    }

    @ViewBuilder private var localModelStep: some View {
        Section {
            ModelCatalogList(
                installed: installed,
                activeID: store.modelName,
                pulling: pulling,
                allowsDelete: false,
                download: download,
                delete: { _ in }
            )
            if isLargerThanRecommended(store.modelName) {
                Label(loc("Ten model jest duży jak na Twój komputer. Pobieranie zajmie więcej czasu, a praca może zwolnić.",
                          "This model is large for your Mac. The download takes longer and things may slow down."),
                      systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } footer: {
            Text(loc("Tłumaczenie dzieje się na Twoim komputerze, nic nie wysyłamy do sieci. Najlepiej wybierz ten oznaczony „zalecany”.",
                     "Translation happens on your Mac; nothing is sent to the network. Your best bet is the one marked “recommended”."))
        }
    }

    private var languageStep: some View {
        Form {
            Section {
                Picker(loc("Język główny", "Primary language"), selection: $store.primaryLanguage) {
                    ForEach(PrimaryLanguage.allCases, id: \.self) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
            } footer: {
                Text(loc("Język główny to język aplikacji i strona pary, na którą Glosso tłumaczy obce teksty.",
                         "The primary language is the app's language and the side of the pair Glosso translates foreign text into."))
            }
            Section {
                Picker(loc("Drugi język", "Second language"), selection: $store.secondLanguage) {
                    Text(loc("Automatyczny", "Automatic")).tag(SecondLanguage?.none)
                    ForEach(SecondLanguage.allCases.filter { $0 != store.primaryLanguage.asSecond }, id: \.self) { lang in
                        Text(lang.displayName.capitalized).tag(SecondLanguage?.some(lang))
                    }
                }
            } footer: {
                Text(loc("Glosso tłumaczy w obie strony: z języka głównego na drugi i z powrotem. „Automatyczny” sam rozpoznaje język zaznaczenia.",
                         "Glosso translates both ways: from the primary language to the second and back. “Automatic” detects the selection's language on its own."))
            }
        }
        .formStyle(.grouped)
    }

    private var usageStep: some View {
        Form {
            Section {
                Label(loc("Zaznacz tekst i naciśnij dwa razy Cmd+C. Tłumaczenie pojawi się obok kursora.",
                          "Select text and press Cmd+C twice. The translation appears next to the cursor."),
                      systemImage: "command")
                    .fixedSize(horizontal: false, vertical: true)
                Label(loc("Chcesz poprawić tekst od razu na miejscu? Włącz skróty w Ustawieniach.",
                          "Want text fixed right in place? Enable the shortcuts in Settings."),
                      systemImage: "character.cursor.ibeam")
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section { accessibilityBox }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var accessibilityBox: some View {
        if appState.accessibilityGranted {
            Label(loc("Zgoda nadana. Możesz zaczynać.", "Permission granted. You're all set."), systemImage: "checkmark.circle.fill")
                .symbolRenderingMode(.multicolor)
        } else {
            Label(loc("Glosso potrzebuje Twojej zgody, żeby widzieć zaznaczony tekst i reagować na skróty.",
                      "Glosso needs your permission to see selected text and respond to shortcuts."),
                  systemImage: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.multicolor)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(loc("Otwórz ustawienia dostępności", "Open Accessibility settings")) { onOpenAccessibility() }
                Button(loc("Sprawdź ponownie", "Check again")) { onRecheckAccessibility() }
            }
        }
    }

    // MARK: Actions

    private func isLargerThanRecommended(_ id: String) -> Bool {
        guard let chosen = EmbeddedModelCatalog.models.firstIndex(where: { $0.id == id }),
              let rec = EmbeddedModelCatalog.models.firstIndex(where: { $0.id == recommended.id })
        else { return false }
        return chosen > rec
    }

    private func refresh() async {
        installed = (try? await lister.availableModels()) ?? []
    }

    private func download(_ id: String) {
        pulling[id] = 0
        Task {
            do {
                try await downloadModel(id, engine: engine, modelManager: modelManager) { value in
                    pulling[id] = value
                }
                await refresh()
                store.modelName = id
            } catch {}
            pulling[id] = nil
        }
    }
}
