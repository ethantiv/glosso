import SwiftUI

/// The local-model catalog, shared by Settings and onboarding — both list the same tiers and drive the same `downloadModel` flow.
struct ModelCatalogList: View {
    let installed: [String]
    let activeID: String
    let pulling: [String: Double]
    /// Settings manages installed models; onboarding only adds them.
    let allowsDelete: Bool
    let download: (String) -> Void
    let delete: (String) -> Void

    private let recommendedID = EmbeddedModelCatalog.recommended.id

    var body: some View {
        // An HStack, not LabeledContent: LabeledContent hands the row's label to its controls as their accessibility
        // name, so every Download and Delete button would read out as the model's name instead of the action.
        ForEach(EmbeddedModelCatalog.models, id: \.id) { entry in
            HStack {
                Label {
                    Text(entry.displayName)
                    Text(subtitle(for: entry))
                } icon: {
                    Image(systemName: entry.icon)
                }
                Spacer(minLength: 12)
                trailing(for: entry)
            }
        }
    }

    @ViewBuilder
    private func trailing(for entry: EmbeddedModelCatalog.Entry) -> some View {
        if let progress = pulling[entry.id] {
            ProgressView(value: progress)
                .controlSize(.small)
                .frame(maxWidth: 140)
                .accessibilityLabel(loc("Pobieranie \(entry.displayName)", "Downloading \(entry.displayName)"))
        } else if installed.contains(entry.id) {
            if allowsDelete {
                Button(loc("Usuń", "Delete")) { delete(entry.id) }
                    .disabled(entry.id == activeID)
                    .accessibilityLabel(loc("Usuń \(entry.displayName)", "Delete \(entry.displayName)"))
            } else {
                Text(entry.id == activeID ? loc("Aktywny", "Active") : loc("Pobrany", "Downloaded"))
                    .foregroundStyle(.secondary)
            }
        } else {
            Button(loc("Pobierz", "Download")) { download(entry.id) }
                .accessibilityLabel(loc("Pobierz \(entry.displayName)", "Download \(entry.displayName)"))
        }
    }

    private func subtitle(for entry: EmbeddedModelCatalog.Entry) -> String {
        entry.id == recommendedID
            ? loc("\(entry.id) · \(entry.size) · zalecany", "\(entry.id) · \(entry.size) · recommended")
            : "\(entry.id) · \(entry.size)"
    }
}
