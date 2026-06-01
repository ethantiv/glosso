import SwiftUI

struct SettingsView: View {
    @Bindable var store: SettingsStore
    let lister: any ModelListing

    @State private var models: [String] = []
    @State private var loadState: LoadState = .idle
    @State private var loadGeneration = 0

    private enum LoadState: Equatable {
        case idle, loading, loaded, failed
    }

    var body: some View {
        Form {
            Section("Model") {
                Picker("Model", selection: $store.modelName) {
                    ForEach(modelOptions, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                HStack(spacing: 6) {
                    switch loadState {
                    case .loading:
                        ProgressView().controlSize(.small)
                        Text("Pobieram listę modeli…").foregroundStyle(.secondary)
                    case .failed:
                        Text("Nie udało się pobrać listy z Ollamy.").foregroundStyle(.secondary)
                    default:
                        EmptyView()
                    }
                    Spacer(minLength: 0)
                    Button("Odśwież") { Task { await loadModels() } }
                }
                .font(.caption)
            }

            Section("Język") {
                Picker("Drugi język", selection: $store.secondLanguage) {
                    ForEach(SecondLanguage.allCases, id: \.self) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                Text("Tłumaczy polski ↔ wybrany język; kierunek wykrywany automatycznie.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Ogólne") {
                Toggle("Uruchamiaj przy logowaniu", isOn: $store.launchAtLogin)
            }
        }
        .formStyle(.grouped)
        .frame(width: 360)
        .task {
            store.refreshLaunchAtLogin()
            await loadModels()
        }
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
}
