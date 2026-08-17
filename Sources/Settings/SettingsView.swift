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
    @State private var catalogExpanded = true

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
                // Collapsed under a cloud engine: this is the fallback then, not the model the user picks day to day.
                DisclosureGroup(loc("Modele do pobrania", "Models to download"), isExpanded: $catalogExpanded) {
                    ModelCatalogList(
                        installed: models,
                        activeID: store.modelName,
                        pulling: pulling,
                        allowsDelete: true,
                        download: startPull,
                        delete: deleteModel
                    )
                }
            }

            Section(loc("Ogólne", "General")) {
                LanguagePickers(store: store)
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
        .onChange(of: store.provider, initial: true) { catalogExpanded = store.provider == .local }
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
            } catch {
                SystemUserNotifier.post(loc("Nie udało się pobrać modelu \(model). Sprawdź połączenie i spróbuj ponownie.",
                                            "Couldn't download the model \(model). Check your connection and try again."))
            }
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
    func makeNSView(context: Context) -> ConfiguringView { ConfiguringView() }
    // Every body re-eval lands here, including the 5s quota tick — ConfiguringView no-ops unless the content changed.
    func updateNSView(_ nsView: ConfiguringView, context: Context) { nsView.scheduleFit() }

    final class ConfiguringView: NSView {
        private var lastContentHeight: CGFloat?
        private var fitScheduled = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.collectionBehavior.insert(.moveToActiveSpace)
            window.title = loc("Ustawienia Glosso", "Glosso Settings")
            window.styleMask.insert(.resizable)
            scheduleFit()
        }

        // Never inside the layout pass: resizing a window from within its own layout is the recursion that overflowed
        // the stack in the popup. The next runloop turn is also when the new content is measurable.
        func scheduleFit() {
            guard !fitScheduled else { return }
            fitScheduled = true
            DispatchQueue.main.async { [weak self] in
                self?.fitScheduled = false
                self?.fitWindowToContent()
            }
        }

        private func fitWindowToContent() {
            guard let window, !window.inLiveResize, let root = window.contentView else { return }
            // A window that isn't on a screen yet has no ceiling to clamp to — retry next turn rather than cache a
            // height measured against the window's own current size, which would pin it there for good.
            guard let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
            let content = SettingsWindowSizing.formContentHeight(in: root) ?? SettingsWindowSizing.fallbackHeight
            // The user's own drag survives every re-render; only a changed content height replaces it.
            guard abs((lastContentHeight ?? -1) - content) > 1 else { return }
            lastContentHeight = content
            // Measured off the window itself: frameRect(forContentRect:) reports no title bar here and cuts the last row.
            let chrome = window.frame.height - window.contentLayoutRect.height
            var frame = window.frame
            frame.size.height = min(content + chrome, visible.height)
            // Top-left pinned, then clamped like the popup: growing downward off the screen edge would hide the very
            // rows this sizing exists to show.
            let topLeft = PanelPositioning.clampedTopLeft(
                CGPoint(x: frame.minX, y: window.frame.maxY),
                panelSize: frame.size,
                screenFrame: visible
            )
            frame.origin = CGPoint(x: topLeft.x, y: topLeft.y - frame.height)
            guard frame != window.frame else { return }
            window.setFrame(frame, display: true)
        }
    }
}

/// The grouped Form is scroll-backed, and a scroll view under a concrete proposal reports the window's height, not its
/// content's — so the real number comes from the document view, the one place AppKit keeps it.
@MainActor
enum SettingsWindowSizing {
    static let fallbackHeight: CGFloat = 760

    static func formContentHeight(in root: NSView) -> CGFloat? {
        guard let document = firstScrollView(in: root)?.documentView else { return nil }
        document.layoutSubtreeIfNeeded()
        return document.frame.height
    }

    private static func firstScrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        for subview in view.subviews {
            if let found = firstScrollView(in: subview) { return found }
        }
        return nil
    }
}
