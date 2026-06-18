import SwiftUI

struct SettingsView: View {
    @Bindable var store: SettingsStore
    let lister: any ModelListing
    let engine: any EngineProviding
    let modelManager: any ModelManaging

    @State private var models: [String] = []
    @State private var loadState: LoadState = .idle
    @State private var loadGeneration = 0
    @State private var engineStatus: EngineStatus?
    @State private var engineDownload: Double?
    @State private var pulling: [String: Double] = [:]

    private enum LoadState: Equatable {
        case idle, loading, loaded, failed
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            settingsGroups
        }
        .frame(width: 420, alignment: .top)
        .ignoresSafeArea(.container, edges: .top)
        .tint(PopupTheme.accent)
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .containerBackground(for: .window) {
            PopupTheme.surface
        }
        .background(SettingsWindowConfigurator())
        .task {
            store.refreshLaunchAtLogin()
            engineStatus = await engine.status()
            await loadModels()
        }
    }

    // The macOS Settings window's titlebar is made transparent and full-size (see
    // SettingsWindowConfigurator) so the material runs edge to edge; this draws the
    // mockup's centered "Ustawienia" title in that zone, with the traffic lights
    // floating over its left.
    private var titleBar: some View {
        Text("Ustawienia")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .overlay(alignment: .bottom) {
                Rectangle().fill(PopupTheme.hairline).frame(height: 0.5)
            }
    }

    private var settingsGroups: some View {
        VStack(spacing: 14) {
            engineGroup

            group("Model") {
                row("Model Ollama", "Lokalny model do tłumaczenia") {
                    Picker("", selection: $store.modelName) {
                        ForEach(modelOptions, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .labelsHidden()
                    .accessibilityLabel("Model Ollama")
                    .frame(maxWidth: 200)
                }
                rowDivider
                row("Lista modeli", nil) {
                    switch loadState {
                    case .loading:
                        ProgressView().controlSize(.small)
                    case .failed:
                        Text("Nie udało się pobrać")
                            .font(PopupTheme.fontMeta)
                            .foregroundStyle(.secondary)
                    case .loaded:
                        Text("\(models.count) dostępne")
                            .font(PopupTheme.fontMeta)
                            .foregroundStyle(.secondary)
                    case .idle:
                        EmptyView()
                    }
                    Button("Odśwież") { Task { await loadModels() } }
                        .buttonStyle(.link)
                }
                rowDivider
                ForEach(Array(EmbeddedModelCatalog.models.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { rowDivider }
                    catalogRow(entry)
                }
            }

            group("Język") {
                row("Drugi język", "Polski ↔ wybrany język, kierunek wykrywany automatycznie") {
                    Picker("", selection: $store.secondLanguage) {
                        ForEach(SecondLanguage.allCases, id: \.self) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .labelsHidden()
                    .accessibilityLabel("Drugi język")
                    .fixedSize()
                }
            }

            group("Ogólne") {
                row("Naturalny styl", "Brzmi naturalnie, nie jak z AI") {
                    Toggle("", isOn: $store.humanize)
                        .labelsHidden()
                        .accessibilityLabel("Naturalny styl")
                        .toggleStyle(.switch)
                }
                rowDivider
                row("Uruchamiaj przy logowaniu", "Startuje cicho w menu barze po zalogowaniu") {
                    Toggle("", isOn: $store.launchAtLogin)
                        .labelsHidden()
                        .accessibilityLabel("Uruchamiaj przy logowaniu")
                        .toggleStyle(.switch)
                }
            }

            group("Skróty") {
                row("Popraw w miejscu", "Poprawia gramatykę zaznaczenia") {
                    KeyChordRecorder(chord: $store.fixChord, otherChord: store.translateInPlaceChord)
                        .frame(width: 96, height: 24)
                        .accessibilityLabel("Skrót: popraw w miejscu")
                }
                rowDivider
                row("Tłumacz w miejscu", "Tłumaczy zaznaczenie i wkleja wynik") {
                    KeyChordRecorder(chord: $store.translateInPlaceChord, otherChord: store.fixChord)
                        .frame(width: 96, height: 24)
                        .accessibilityLabel("Skrót: tłumacz w miejscu")
                }
            }
        }
        .padding(16)
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(PopupTheme.fontLabel)
                .tracking(0.5)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 13)
                .padding(.top, 10)
                .padding(.bottom, 2)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PopupTheme.groupedCard, in: RoundedRectangle(cornerRadius: PopupTheme.rPane))
        .overlay(
            RoundedRectangle(cornerRadius: PopupTheme.rPane)
                .strokeBorder(PopupTheme.hairline, lineWidth: 0.5)
        )
    }

    private func row<Control: View>(
        _ label: String,
        _ sub: String?,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(PopupTheme.fontSource)
                    .foregroundStyle(.primary)
                if let sub {
                    Text(sub)
                        .font(PopupTheme.fontMeta)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) { control() }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(PopupTheme.hairline)
            .frame(height: 0.5)
    }

    /// Always include the saved model so the current selection stays visible even
    /// when the live list omits it or the fetch failed.
    private var modelOptions: [String] {
        models.contains(store.modelName) ? models : [store.modelName] + models
    }

    private func loadModels() async {
        // Tag this load so a slow earlier fetch (e.g. .task) can't overwrite the
        // result of a later one (e.g. an "Odśwież" tap) once it finally resolves.
        loadGeneration += 1
        let generation = loadGeneration
        loadState = .loading
        do {
            let fetched = try await lister.availableModels()
            guard generation == loadGeneration else { return }
            models = fetched
            loadState = .loaded
        } catch {
            guard generation == loadGeneration else { return }
            models = []
            loadState = .failed
        }
    }

    private var engineGroup: some View {
        group("Silnik") {
            row("Silnik Ollamy", engineStatusSub) {
                if let progress = engineDownload {
                    ProgressView(value: progress).controlSize(.small).frame(width: 120)
                } else if engineStatus == .needsDownload {
                    Button("Pobierz silnik") { downloadEngine() }
                        .buttonStyle(.link)
                } else {
                    Text(engineStatusLabel)
                        .font(PopupTheme.fontMeta)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func catalogRow(_ entry: EmbeddedModelCatalog.Entry) -> some View {
        row(entry.name, entry.size) {
            if let progress = pulling[entry.id] {
                ProgressView(value: progress).controlSize(.small).frame(width: 120)
            } else if models.contains(entry.id) {
                Button("Usuń") { deleteModel(entry.id) }
                    .buttonStyle(.link)
            } else {
                Button("Pobierz") { startPull(entry.id) }
                    .buttonStyle(.link)
                    .disabled(engineStatus == .needsDownload)
            }
        }
    }

    private var engineStatusLabel: String {
        switch engineStatus {
        case .ready: "Gotowy"
        case .installable: "Gotowy do uruchomienia"
        case .needsDownload, nil: "Brak"
        }
    }

    private var engineStatusSub: String {
        switch engineStatus {
        case .ready: "Tłumaczy przez wykrytą Ollamę"
        case .installable: "Uruchomi się przy pierwszym tłumaczeniu"
        case .needsDownload: "Pobierz, by działać bez Ollamy (177 MB)"
        case nil: "Sprawdzanie…"
        }
    }

    private func downloadEngine() {
        engineDownload = 0
        Task {
            do {
                try await engine.ensureEngine(progress: { value in
                    Task { @MainActor in engineDownload = value }
                })
                engineStatus = await engine.status()
                await loadModels()
            } catch {}
            engineDownload = nil
        }
    }

    private func startPull(_ model: String) {
        pulling[model] = 0
        Task {
            do {
                for try await progress in modelManager.pull(model) {
                    if progress.total > 0 {
                        pulling[model] = Double(progress.completed) / Double(progress.total)
                    }
                }
                await loadModels()
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

// The Settings scene ignores `.windowStyle(.hiddenTitleBar)`, so the AppKit window
// is configured directly to drop the opaque titlebar backing/title and let the
// `.containerBackground` material run continuously through the titlebar zone.
// SwiftUI re-imposes the standard Settings window treatment *after* the view first
// attaches, so a one-shot set in viewDidMoveToWindow gets clobbered — the config is
// deferred to the next runloop and reapplied whenever the window becomes key/main.
private struct SettingsWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ConfiguringView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ConfiguringView: NSView {
        private var observers: [NSObjectProtocol] = []

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            if newWindow == nil {
                observers.forEach(NotificationCenter.default.removeObserver)
                observers.removeAll()
            }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, observers.isEmpty else { return }
            DispatchQueue.main.async { [weak self] in self?.configure(window) }

            let center = NotificationCenter.default
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didBecomeMainNotification] {
                observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] note in
                    guard let window = note.object as? NSWindow else { return }
                    MainActor.assumeIsolated { self?.configure(window) }
                })
            }
        }

        private func configure(_ window: NSWindow) {
            window.collectionBehavior.insert(.moveToActiveSpace)
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.title = ""
            window.titlebarSeparatorStyle = .none
            window.isMovableByWindowBackground = true
        }
    }
}
