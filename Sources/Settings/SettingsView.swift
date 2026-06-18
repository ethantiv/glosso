import SwiftUI

struct SettingsView: View {
    @Bindable var store: SettingsStore
    let lister: any ModelListing
    let engine: any EngineProviding
    let modelManager: any ModelManaging

    @State private var models: [String] = []
    @State private var loadGeneration = 0
    @State private var pulling: [String: Double] = [:]

    private let recommendedModel = EmbeddedModelCatalog.recommended.id

    private var otherInstalledModels: [String] {
        let catalogIDs = Set(EmbeddedModelCatalog.models.map(\.id))
        return models.filter { !catalogIDs.contains($0) }.sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            settingsGroups
        }
        .frame(width: 460, alignment: .top)
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
            group("Model") {
                ForEach(Array(EmbeddedModelCatalog.models.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { rowDivider }
                    modelRow(
                        id: entry.id,
                        title: entry.displayName,
                        icon: entry.icon,
                        size: entry.size,
                        isDownloaded: models.contains(entry.id),
                        isRecommended: entry.id == recommendedModel
                    )
                }
                if !otherInstalledModels.isEmpty {
                    rowDivider
                    otherModelsRow
                }
            }

            group("Ogólne") {
                row("Drugi język") {
                    Picker("", selection: $store.secondLanguage) {
                        ForEach(SecondLanguage.allCases, id: \.self) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .labelsHidden()
                    .accessibilityLabel("Drugi język")
                    .fixedSize()
                }
                rowDivider
                row("Naturalny styl") {
                    Toggle("", isOn: $store.humanize)
                        .labelsHidden()
                        .accessibilityLabel("Naturalny styl")
                        .toggleStyle(.switch)
                }
                rowDivider
                row("Uruchamiaj przy logowaniu") {
                    Toggle("", isOn: $store.launchAtLogin)
                        .labelsHidden()
                        .accessibilityLabel("Uruchamiaj przy logowaniu")
                        .toggleStyle(.switch)
                }
            }

            group("Skróty") {
                row("Popraw w miejscu") {
                    KeyChordRecorder(chord: $store.fixChord, otherChord: store.translateInPlaceChord)
                        .frame(width: 96, height: 24)
                        .accessibilityLabel("Skrót: popraw w miejscu")
                }
                rowDivider
                row("Tłumacz w miejscu") {
                    KeyChordRecorder(chord: $store.translateInPlaceChord, otherChord: store.fixChord)
                        .frame(width: 96, height: 24)
                        .accessibilityLabel("Skrót: tłumacz w miejscu")
                }
            }
        }
        .padding(16)
    }

    // The user's own non-catalog Ollama models can grow unbounded, so they collapse
    // into one picker instead of a row each. Selecting one makes it the active model;
    // when a catalog Gemma is active the picker shows no selection (the radios above
    // carry it). Glosso manages only its own Gemmas, so there's no delete here.
    private var otherModelsRow: some View {
        row("Inne zainstalowane") {
            Picker("", selection: $store.modelName) {
                ForEach(otherInstalledModels, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .labelsHidden()
            .accessibilityLabel("Inny zainstalowany model")
            .fixedSize()
        }
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
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(PopupTheme.fontSource)
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            HStack(spacing: 8) { control() }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(PopupTheme.hairline)
            .frame(height: 0.5)
    }

    private func loadModels() async {
        // Tag this load so a slow earlier fetch (e.g. .task) can't overwrite the
        // result of a later one (e.g. one triggered after a pull) once it finally
        // resolves.
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

    private func modelRow(
        id: String,
        title: String,
        icon: String,
        size: String,
        isDownloaded: Bool,
        isRecommended: Bool
    ) -> some View {
        let isActive = store.modelName == id
        return HStack(spacing: 12) {
            Button { store.modelName = id } label: {
                Image(systemName: isActive ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isActive ? PopupTheme.accent : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(!isDownloaded || isActive)
            .accessibilityLabel("Użyj modelu \(title)")
            .accessibilityAddTraits(isActive ? .isSelected : [])

            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .help(title)
                .accessibilityLabel(title)
            Text(id)
                .font(PopupTheme.fontMeta)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)

            // Fixed-width trailing columns so size and action line up across rows;
            // the badge slot is reserved even when empty so the size column's left
            // edge stays put whether or not a row is recommended.
            Group { if isRecommended { recommendedBadge } }
                .frame(width: 64, alignment: .trailing)
            if let progress = pulling[id] {
                ProgressView(value: progress)
                    .controlSize(.small)
                    .frame(width: 116)
            } else {
                Text(size)
                    .font(PopupTheme.fontMeta)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 52, alignment: .leading)
                Group {
                    if isDownloaded {
                        Button("Usuń") { deleteModel(id) }
                            .buttonStyle(.link)
                            .disabled(isActive)
                    } else {
                        Button("Pobierz") { startPull(id) }
                            .buttonStyle(.link)
                    }
                }
                .lineLimit(1)
                .frame(width: 60, alignment: .trailing)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
    }

    private var recommendedBadge: some View {
        Text("Zalecany")
            .font(PopupTheme.fontLabel)
            .foregroundStyle(PopupTheme.accent)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(PopupTheme.accent.opacity(0.12), in: Capsule())
    }

    private func startPull(_ model: String) {
        pulling[model] = 0
        Task {
            do {
                // Provision the engine first (idempotent — a no-op when the user's
                // Ollama is reachable or a binary is already on disk). On a fresh Mac
                // this pulls the ~177 MB engine; the user clicked "Pobierz", so it's
                // consented, and it's negligible beside the multi-GB model that follows.
                try await engine.ensureEngine(progress: { _ in })
                for try await progress in modelManager.pull(model) {
                    if progress.total > 0 {
                        // /api/pull restarts completed/total per layer; clamp so the
                        // bar can't snap backward as each new layer reports from 0.
                        let value = Double(progress.completed) / Double(progress.total)
                        pulling[model] = max(pulling[model] ?? 0, value)
                    }
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
