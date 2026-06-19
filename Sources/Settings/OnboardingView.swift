import SwiftUI

/// First-run setup wizard: pick & download a model, choose the second language, and
/// read the how-to (including the one-time Accessibility grant). Reuses the same
/// catalog, store and download flow as Settings — it's a guided front door, not new
/// machinery. Shown once; `onFinish` closes the window and marks onboarding done.
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

    @State private var step: Step = .model
    @State private var installed: [String] = []
    @State private var pulling: [String: Double] = [:]

    private let recommended = EmbeddedModelCatalog.recommended

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(20)
            Divider()
            footer
        }
        .frame(width: 520, height: 470)
        .tint(PopupTheme.accent)
        .task { await refresh() }
    }

    // MARK: Header & footer

    private var header: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.rawValue) { s in
                    Circle()
                        .fill(s == step ? PopupTheme.accent : PopupTheme.hairline)
                        .frame(width: 7, height: 7)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var footer: some View {
        HStack {
            if step != .model {
                Button("Wstecz") { advance(by: -1) }
            }
            Spacer()
            if step == .usage {
                Button("Zakończ") {
                    store.hasCompletedOnboarding = true
                    onFinish()
                }
                .keyboardShortcut(.defaultAction)
            } else {
                Button("Dalej") { advance(by: 1) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var title: String {
        switch step {
        case .model: "Wybierz model"
        case .language: "Wybierz drugi język"
        case .usage: "Jak to działa"
        }
    }

    private func advance(by delta: Int) {
        if let next = Step(rawValue: step.rawValue + delta) {
            withAnimation(PopupTheme.enterCurve) { step = next }
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
        VStack(alignment: .leading, spacing: 12) {
            Text("Tłumaczenie dzieje się na Twoim komputerze, nic nie wysyłamy do sieci. Najlepiej wybierz ten oznaczony „Zalecany”.")
                .font(PopupTheme.fontSource)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(EmbeddedModelCatalog.models) { entry in
                modelRow(entry)
            }

            if isLargerThanRecommended(store.modelName) {
                Label("Ten model jest duży jak na Twój komputer. Pobieranie zajmie więcej czasu, a praca może zwolnić.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(PopupTheme.fontMeta)
                    .foregroundStyle(PopupTheme.warn)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PopupTheme.warnBg, in: RoundedRectangle(cornerRadius: PopupTheme.rControl))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func modelRow(_ entry: EmbeddedModelCatalog.Entry) -> some View {
        let isDownloaded = installed.contains(entry.id)
        let isActive = store.modelName == entry.id
        return HStack(spacing: 12) {
            Button { store.modelName = entry.id } label: {
                Image(systemName: isActive ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isActive ? PopupTheme.accent : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(!isDownloaded || isActive)

            Image(systemName: entry.icon)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.displayName).font(PopupTheme.fontControl)
                Text(entry.size).font(PopupTheme.fontMeta).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)

            if entry.id == recommended.id {
                Text("Zalecany")
                    .font(PopupTheme.fontLabel)
                    .foregroundStyle(PopupTheme.accent)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(PopupTheme.accent.opacity(0.12), in: Capsule())
            }

            if let progress = pulling[entry.id] {
                ProgressView(value: progress).controlSize(.small).frame(width: 90)
            } else if isDownloaded {
                Text(isActive ? "Aktywny" : "Pobrany")
                    .font(PopupTheme.fontMeta)
                    .foregroundStyle(.secondary)
            } else {
                Button("Pobierz") { download(entry.id) }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(PopupTheme.groupedCard, in: RoundedRectangle(cornerRadius: PopupTheme.rPane))
        .overlay(
            RoundedRectangle(cornerRadius: PopupTheme.rPane)
                .strokeBorder(isActive ? PopupTheme.accent.opacity(0.5) : PopupTheme.hairline, lineWidth: 0.5)
        )
    }

    private var languageStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Glosso tłumaczy w obie strony: z polskiego na wybrany język i z powrotem.")
                .font(PopupTheme.fontSource)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Drugi język", selection: $store.secondLanguage) {
                ForEach(SecondLanguage.allCases, id: \.self) { lang in
                    Text(lang.displayName.capitalized).tag(lang)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
        }
    }

    private var usageStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            instruction("command", "Zaznacz tekst i naciśnij dwa razy Cmd+C. Tłumaczenie pojawi się obok kursora.")
            instruction("character.cursor.ibeam", "Chcesz poprawić tekst od razu na miejscu? Włącz skróty w Ustawieniach.")
            accessibilityBox
        }
    }

    private func instruction(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(PopupTheme.accent)
                .frame(width: 22)
            Text(text)
                .font(PopupTheme.fontSource)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var accessibilityBox: some View {
        if appState.accessibilityGranted {
            Label("Zgoda nadana. Możesz zaczynać.", systemImage: "checkmark.circle.fill")
                .font(PopupTheme.fontSource)
                .foregroundStyle(PopupTheme.copied)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PopupTheme.copied.opacity(0.10), in: RoundedRectangle(cornerRadius: PopupTheme.rControl))
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Label("Glosso potrzebuje Twojej zgody, żeby widzieć zaznaczony tekst i reagować na skróty.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(PopupTheme.fontSource)
                    .foregroundStyle(PopupTheme.warn)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Otwórz ustawienia dostępności") { onOpenAccessibility() }
                    Button("Sprawdź ponownie") { onRecheckAccessibility() }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PopupTheme.warnBg, in: RoundedRectangle(cornerRadius: PopupTheme.rControl))
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
