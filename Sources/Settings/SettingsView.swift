import SwiftUI

struct SettingsView: View {
    @Bindable var store: SettingsStore
    let lister: any ModelListing
    /// Ollama's cloud host, listing what it serves — a different lister, not a different protocol.
    let cloudLister: any ModelListing
    let engine: any EngineProviding
    let modelManager: any ModelManaging
    let limiter: GeminiRateLimiter

    @State private var models: [String] = []
    @State private var ollamaCloudModels: [String] = []
    @State private var loadGeneration = 0
    @State private var pulling: [String: Double] = [:]
    @State private var quota: (used: Int, limit: Int)?

    /// The active pick is always in the list, even when it isn't installed yet — otherwise the picker blanks out and nothing on screen names the model in use.
    private var installedModelChoices: [String] {
        var ids = Set(models)
        ids.insert(store.modelName)
        return ids.sorted()
    }

    private var otherOllamaCloudModels: [String] {
        var ids = Set(ollamaCloudModels)
        ids.insert(store.ollamaCloudModel)
        return ids.subtracting([OllamaCloudCatalog.defaultModel]).sorted()
    }

    var body: some View {
        Form {
            Section(loc("Silnik", "Engine")) {
                Picker(loc("Silnik tłumaczenia", "Translation engine"), selection: $store.provider) {
                    ForEach(LLMProvider.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                if store.provider == .cloud { cloudSection }
                if store.provider == .ollamaCloud { ollamaCloudSection }
            }

            // Either cloud falls back to this one on a spent quota or a dead key, so it has to be installable here.
            Section(store.provider == .local ? loc("Model", "Model") : loc("Model zapasowy", "Fallback model")) {
                Picker(loc("Aktywny model", "Active model"), selection: $store.modelName) {
                    ForEach(installedModelChoices, id: \.self) { id in
                        Text(displayName(forInstalled: id)).tag(id)
                    }
                }
                ModelCatalogList(
                    installed: models,
                    activeID: store.modelName,
                    pulling: pulling,
                    allowsDelete: true,
                    download: startPull,
                    delete: deleteModel
                )
            }

            Section(loc("Ogólne", "General")) {
                Picker(loc("Język główny", "Primary language"), selection: $store.primaryLanguage) {
                    ForEach(PrimaryLanguage.allCases, id: \.self) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                Picker(loc("Drugi język", "Second language"), selection: $store.secondLanguage) {
                    Text(loc("Automatyczny", "Automatic")).tag(SecondLanguage?.none)
                    ForEach(SecondLanguage.allCases.filter { $0 != store.primaryLanguage.asSecond }, id: \.self) { lang in
                        Text(lang.displayName).tag(SecondLanguage?.some(lang))
                    }
                }
                Toggle(loc("Uruchamiaj przy logowaniu", "Launch at login"), isOn: $store.launchAtLogin)
            }

            Section(loc("Skróty", "Shortcuts")) {
                // An HStack, not LabeledContent: the recorder is an NSView with a fixed height, and LabeledContent
                // drops it below the label's baseline instead of centring it on the row.
                chordRow(loc("Popraw w miejscu", "Fix in place"),
                         chord: $store.fixChord, other: store.translateInPlaceChord)
                chordRow(loc("Tłumacz w miejscu", "Translate in place"),
                         chord: $store.translateInPlaceChord, other: store.fixChord)
            }
        }
        .formStyle(.grouped)
        .background(SettingsWindowConfigurator())
        .task {
            store.refreshLaunchAtLogin()
            await loadModels()
        }
        .task(id: store.provider) {
            guard store.provider == .ollamaCloud, ollamaCloudModels.isEmpty else { return }
            ollamaCloudModels = (try? await cloudLister.availableModels()) ?? []
        }
        .task {
            // The counter is the point of the row — a value frozen at window-open is worse than none.
            while !Task.isCancelled {
                quota = await limiter.quotaUsage(model: store.cloudModel)
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    @ViewBuilder private var cloudSection: some View {
        // The Keychain read lives here, not on the window: under the local provider this section never renders, and
        // asking for the login password to fill a field nobody can see is the whole bug this avoids.
        SecureField(loc("Klucz API", "API key"), text: $store.apiKey)
            .task { store.loadGoogleAPIKey() }
        Link(loc("Pobierz darmowy klucz w Google AI Studio",
                 "Get a free key in Google AI Studio"),
             destination: URL(string: "https://aistudio.google.com/apikey")!)
        Picker(loc("Model", "Model"), selection: $store.cloudModel) {
            ForEach(CloudModelCatalog.models, id: \.id) { entry in
                Label(entry.displayName, systemImage: entry.icon).tag(entry.id)
            }
        }
        .pickerStyle(.radioGroup)
        LabeledContent(loc("Zapytania dzisiaj", "Requests today")) {
            Text(quota.map { "\($0.used) / \($0.limit)" } ?? "—")
                .foregroundStyle(.secondary)
        }
        privacyNote(loc("W tym trybie zaznaczony tekst jest wysyłany do Google.",
                        "In this mode the selected text is sent to Google."))
    }

    @ViewBuilder private var ollamaCloudSection: some View {
        SecureField(loc("Klucz API", "API key"), text: $store.ollamaAPIKey)
            .task { store.loadOllamaAPIKey() }
        Link(loc("Utwórz klucz na ollama.com", "Create a key on ollama.com"),
             destination: URL(string: "https://ollama.com/settings/keys")!)
        Picker(loc("Model", "Model"), selection: $store.ollamaCloudModel) {
            Text("Gemma — \(OllamaCloudCatalog.defaultModel)").tag(OllamaCloudCatalog.defaultModel)
            ForEach(otherOllamaCloudModels, id: \.self) { name in
                Text(name).tag(name)
            }
        }
        privacyNote(loc("W tym trybie zaznaczony tekst jest wysyłany do Ollamy.",
                        "In this mode the selected text is sent to Ollama."))
    }

    private func chordRow(_ label: String, chord: Binding<KeyChord>, other: KeyChord) -> some View {
        HStack {
            Text(label)
            Spacer(minLength: 12)
            KeyChordRecorder(chord: chord, otherChord: other)
                .frame(width: 96, height: 24)
                .accessibilityLabel(loc("Skrót: \(label)", "Shortcut: \(label)"))
        }
    }

    private func privacyNote(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .symbolRenderingMode(.multicolor)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func displayName(forInstalled id: String) -> String {
        guard let entry = EmbeddedModelCatalog.models.first(where: { $0.id == id }) else { return id }
        return "\(entry.displayName) — \(id)"
    }

    private func loadModels() async {
        loadGeneration += 1
        let generation = loadGeneration
        do {
            let fetched = try await lister.availableModels()
            guard generation == loadGeneration else { return }
            models = fetched
        } catch {
            guard generation == loadGeneration else { return }
            models = []
        }
    }

    private func startPull(_ model: String) {
        pulling[model] = 0
        Task {
            do {
                try await downloadModel(model, engine: engine, modelManager: modelManager) { value in
                    pulling[model] = value
                }
                await loadModels()
                store.modelName = model
            } catch {}
            pulling[model] = nil
        }
    }

    private func deleteModel(_ model: String) {
        Task {
            try? await modelManager.delete(model)
            await loadModels()
        }
    }
}

/// Three things the Settings scene can't say for itself: an `LSUIElement` app's window has to follow to whichever Space
/// is active; the system-composed title ("Glosso Settings") comes from the unlocalized bundle even on a Polish system;
/// and a `Settings` scene ships without `.resizable` whatever `windowResizability` says, so the zoom button stays dead
/// and the form can't be grown — which is exactly what "support arbitrary window sizes" rules out.
private struct SettingsWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ConfiguringView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ConfiguringView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.collectionBehavior.insert(.moveToActiveSpace)
            window.title = loc("Ustawienia Glosso", "Glosso Settings")
            window.styleMask.insert(.resizable)
        }
    }
}
