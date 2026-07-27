import AppKit
import SwiftUI

struct PopupView: View {
    @Bindable var model: PopupModel
    let close: () -> Void
    let selectFormality: (Formality) -> Void
    let selectAction: (Action) -> Void
    let fetchAlternatives: (_ word: String, _ translation: String) async -> [String]
    let fetchExplanation: (_ word: String, _ translation: String) async -> String
    let fetchFixReason: (_ before: String, _ after: String, _ corrected: String) async -> String
    let fetchToneNote: (_ previous: String, _ current: String, _ from: Formality, _ to: Formality) async -> String
    let pickAlternative: (_ original: String, _ chosen: String, _ translation: String) -> Void
    let replace: (String) -> Void
    let retranslate: (_ source: String) -> Void
    let undo: () -> Void
    let resizeBy: (_ translation: CGSize, _ ended: Bool) -> Void
    let reportSize: (CGSize) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var copied = false
    @State private var appeared = false
    @State private var hoverWordID: Int?
    @State private var hoverGrip = false

    private static let sourceWidth: CGFloat = 268
    private static let translationWidth: CGFloat = 300
    private static let maxPaneHeight: CGFloat = 400

    static let shadowMargin: CGFloat = 14

    private var paneWidthDelta: CGFloat { (model.sizeDelta.width / 2).rounded(.down) }
    private var paneMaxHeight: CGFloat { Self.maxPaneHeight + model.sizeDelta.height }

    private var resultLabel: String {
        switch model.action {
        case .translate: loc("Tłumaczenie", "Translation")
        case .summarize: loc("Streszczenie", "Summary")
        case .fixGrammar: loc("Poprawka", "Correction")
        case .reply: loc("Odpowiedź", "Reply")
        }
    }

    private var canCopy: Bool { model.phase == .done && !model.text.isEmpty }
    private var canReplace: Bool { canCopy && !model.truncated && model.action != .reply }
    private var canUndo: Bool {
        model.canUndo && (model.phase == .done || model.phase == .error)
    }
    private var canRetranslate: Bool {
        !model.sourceText.isEmpty && model.sourceText != model.capturedSource
    }
    private var showLiveDot: Bool { model.phase == .capturing || model.phase == .streaming }
    private var showAccentEdge: Bool { model.phase == .streaming || model.phase == .done }

    var body: some View {
        panelBox
            .overlay(alignment: .bottomTrailing) { resizeGrip }
            .shadow(color: .black.opacity(0.16), radius: 12, y: 5)
            .padding(.bottom, reservedBottom)
            .overlayPreferenceValue(WordAnchorKey.self) { anchors in
                dropdownOverlay(anchors: anchors)
            }
            .padding(Self.shadowMargin)
            .fixedSize()
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { size in
                reportSize(size)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .scaleEffect(appeared ? 1 : 0.965)
            .opacity(appeared ? 1 : 0)
            .onAppear {
                if reduceMotion {
                    appeared = true
                } else {
                    withAnimation(PopupTheme.enterCurve) { appeared = true }
                }
            }
    }

    private var panelBox: some View {
        VStack(spacing: 0) {
            header
            if model.action == .translate { translateControls }
            if model.toneNoteVisible { toneNoteRow }
            HStack(alignment: .top, spacing: 0) {
                sourcePane
                Divider()
                translationPane
            }
            if model.phase == .done && model.truncated {
                truncatedFooter
            }
        }
        .background(PopupTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: PopupTheme.rWindow))
        .overlay(
            RoundedRectangle(cornerRadius: PopupTheme.rWindow)
                .strokeBorder(PopupTheme.hairline, lineWidth: 0.5)
        )
        .gesture(WindowDragGesture())
        .allowsWindowActivationEvents()
    }

    private var reservedBottom: CGFloat {
        model.dropdownVisible ? estimatedDropdownHeight + dropdownGap + dropdownShadowPad : 0
    }

    // MARK: Resize grip

    private var resizeGrip: some View {
        ResizeGripArea(resizeBy: resizeBy)
            .frame(width: 22, height: 22)
            .overlay(
                Path { path in
                    path.move(to: CGPoint(x: 11, y: 3))
                    path.addLine(to: CGPoint(x: 3, y: 11))
                    path.move(to: CGPoint(x: 11, y: 7))
                    path.addLine(to: CGPoint(x: 7, y: 11))
                }
                .stroke(
                    hoverGrip ? HierarchicalShapeStyle.secondary : .tertiary,
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                )
                .frame(width: 14, height: 14)
                .allowsHitTesting(false)
            )
            .onHover { hoverGrip = $0 }
            .accessibilityLabel(loc("Zmień rozmiar okna", "Resize window"))
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            ForEach(Action.allCases, id: \.self) { action in
                verbPill(action)
            }
            Spacer(minLength: 0)
            headerButtons
        }
        .padding(.leading, 13)
        .padding(.trailing, PopupTheme.padWindow)
        .padding(.vertical, PopupTheme.padWindow)
    }

    // Second row, Translate-only: the language pair and tone pill.
    private var translateControls: some View {
        HStack(spacing: 10) {
            languagePair
            tonePill
            if model.phase == .done && model.toneChange != nil { toneNotePill }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .padding(.bottom, PopupTheme.padWindow)
    }

    private func verbPill(_ action: Action) -> some View {
        let active = model.action == action
        return Button {
            guard model.action != action else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: PopupTheme.durFast)) {
                model.action = action
            }
            model.clearUndo()
            model.clearToneNote()
            selectAction(action)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: action.systemImage)
                    .font(.system(size: 11.5, weight: .semibold))
                Text(action.displayName)
                    .font(PopupTheme.fontControl)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(active ? PopupTheme.accentTintStrong : PopupTheme.chipNeutralBg, in: RoundedRectangle(cornerRadius: PopupTheme.rPill))
            .foregroundStyle(active ? PopupTheme.accent : Color.secondary)
            .contentShape(RoundedRectangle(cornerRadius: PopupTheme.rPill))
        }
        .buttonStyle(.plain)
        .help(loc("\(action.displayName) zaznaczenie", "\(action.displayName) the selection"))
        .accessibilityLabel(loc("\(action.displayName) zaznaczenie", "\(action.displayName) the selection"))
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    @ViewBuilder
    private var languagePair: some View {
        switch model.direction {
        case .fromPrimary(let primary, let second):
            HStack(spacing: 7) {
                pill(primary.code, accent: false)
                directionArrow(reversed: false)
                pill(second.code, accent: true)
            }
        case .toPrimary(let primary, let second):
            HStack(spacing: 7) {
                pill(primary.code, accent: true)
                directionArrow(reversed: true)
                pill(second.code, accent: false)
            }
        case .unknown:
            pill("…", accent: false)
        }
    }

    private var tonePill: some View {
        let active = model.formality != .automatic
        return Button {
            let nextF = model.formality.next
            model.noteToneChange(from: model.formality, to: nextF)
            withAnimation(reduceMotion ? nil : .easeOut(duration: PopupTheme.durFast)) {
                model.formality = nextF
            }
            model.clearUndo()
            selectFormality(nextF)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "person.bubble")
                    .font(.system(size: 11.5, weight: .semibold))
                Text(model.formality.displayName)
                    .font(PopupTheme.fontControl)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(active ? PopupTheme.accentTintStrong : PopupTheme.chipNeutralBg, in: RoundedRectangle(cornerRadius: PopupTheme.rPill))
            .foregroundStyle(active ? PopupTheme.accent : Color.secondary)
            .contentShape(RoundedRectangle(cornerRadius: PopupTheme.rPill))
        }
        .buttonStyle(.plain)
        .help(loc("Ton wypowiedzi: \(model.formality.displayName). Kliknij, aby zmienić.", "Tone: \(model.formality.displayName). Click to change."))
        .accessibilityLabel(loc("Ton wypowiedzi: \(model.formality.displayName). Kliknij, aby zmienić.", "Tone: \(model.formality.displayName). Click to change."))
    }

    private var toneNotePill: some View {
        Button(action: toggleToneNote) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 11.5, weight: .semibold))
                Text(loc("Co się zmieniło?", "What changed?"))
                    .font(PopupTheme.fontControl)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(model.toneNoteVisible ? PopupTheme.accentTintStrong : PopupTheme.chipNeutralBg, in: RoundedRectangle(cornerRadius: PopupTheme.rPill))
            .foregroundStyle(model.toneNoteVisible ? PopupTheme.accent : Color.secondary)
            .contentShape(RoundedRectangle(cornerRadius: PopupTheme.rPill))
        }
        .buttonStyle(.plain)
        .help(loc("Pokaż, co zmieniła zmiana tonu wypowiedzi.", "Show what the tone change did."))
        .accessibilityLabel(loc("Pokaż, co zmieniła zmiana tonu wypowiedzi.", "Show what the tone change did."))
        .accessibilityAddTraits(model.toneNoteVisible ? .isSelected : [])
    }

    private var toneNoteRow: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "info.circle")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(PopupTheme.accent)
            if model.toneNoteLoading {
                ProgressView().controlSize(.small)
                Text(loc("Analizuję zmianę tonu…", "Analyzing the tone change…"))
                    .font(PopupTheme.fontControl)
                    .foregroundStyle(.secondary)
            } else {
                Text(model.toneNoteText.isEmpty ? loc("Nie udało się pobrać wyjaśnienia.", "Couldn't fetch the explanation.") : model.toneNoteText)
                    .font(PopupTheme.fontControl)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .frame(width: Self.sourceWidth + Self.translationWidth + 2 * paneWidthDelta, alignment: .leading)
        .padding(.bottom, PopupTheme.padWindow)
    }

    private func toggleToneNote() {
        guard let change = model.toneChange else { return }
        if model.toneNoteVisible {
            model.toneNoteVisible = false
            return
        }
        model.toneNoteVisible = true
        // Already fetched for this tone change — show it again for free.
        guard model.toneNoteText.isEmpty else { return }
        guard change.previous != model.text else {
            model.toneNoteText = loc("Tłumaczenie nie zmieniło się po zmianie tonu.", "The translation didn't change with the tone.")
            return
        }
        model.toneNoteLoading = true
        model.toneNoteRequestToken &+= 1
        let token = model.toneNoteRequestToken
        let current = model.text
        Task { @MainActor in
            let note = await fetchToneNote(change.previous, current, change.from, change.to)
            // A fresh capture or another tone cycle may have moved on while the model ran.
            guard model.toneNoteRequestToken == token, model.toneNoteVisible else { return }
            model.toneNoteText = note
            model.toneNoteLoading = false
        }
    }

    private func pill(_ code: String, accent: Bool) -> some View {
        Text(code)
            .font(PopupTheme.fontControl)
            .tracking(0.2)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(accent ? PopupTheme.accentTintStrong : PopupTheme.chipNeutralBg, in: RoundedRectangle(cornerRadius: PopupTheme.rPill))
            .foregroundStyle(accent ? PopupTheme.accent : Color.secondary)
    }

    private func directionArrow(reversed: Bool) -> some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(PopupTheme.accent)
            .scaleEffect(x: reversed ? -1 : 1, anchor: .center)
    }

    private var headerButtons: some View {
        HStack(spacing: 2) {
            if canReplace {
                Button(action: { replace(model.text) }) {
                    iconLabel("text.insert")
                        .foregroundStyle(Color.secondary)
                }
                .buttonStyle(IconButtonStyle())
                .help(loc("Zastąp zaznaczenie tłumaczeniem", "Replace the selection with the translation"))
                .accessibilityLabel(loc("Zastąp zaznaczenie tłumaczeniem", "Replace the selection with the translation"))
            }
            if canCopy {
                Button(action: copy) {
                    iconLabel(copied ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                        .foregroundStyle(copied ? PopupTheme.copied : Color.secondary)
                }
                .buttonStyle(IconButtonStyle())
                .help(loc("Kopiuj tłumaczenie", "Copy the translation"))
                .accessibilityLabel(loc("Kopiuj tłumaczenie", "Copy the translation"))
                .animation(reduceMotion ? nil : .easeOut(duration: PopupTheme.durFast), value: copied)
            }
            if canUndo {
                Button(action: undo) {
                    iconLabel("arrow.uturn.backward")
                        .foregroundStyle(Color.secondary)
                }
                .buttonStyle(IconButtonStyle())
                .help(loc("Przywróć poprzednie tłumaczenie", "Restore the previous translation"))
                .accessibilityLabel(loc("Przywróć poprzednie tłumaczenie", "Restore the previous translation"))
            }
            Button(action: close) {
                iconLabel("xmark")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(IconButtonStyle())
            .help(loc("Zamknij", "Close"))
            .accessibilityLabel(loc("Zamknij", "Close"))
        }
    }

    private func iconLabel(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 12.5, weight: .medium))
            .frame(width: 24, height: 24)
    }

    private func copy() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(model.text, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            copied = false
        }
    }

    // MARK: Source pane

    private var sourcePane: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                label(loc("Oryginał", "Original"))
                Spacer(minLength: 0)
                retranslateButton
            }
            if !model.sourceText.isEmpty {
                ScrollView {
                    TextField("", text: $model.sourceText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(PopupTheme.fontSourceText)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onKeyPress(.return, phases: .down) { press in
                            guard press.modifiers.contains(.command), canRetranslate else {
                                return .ignored
                            }
                            runRetranslate()
                            return .handled
                        }
                }
                .frame(maxHeight: paneMaxHeight)
                .scrollBounceBehavior(.basedOnSize)
            } else if model.phase == .capturing {
                SkeletonView()
            }
        }
        .padding(PopupTheme.padPane)
        .frame(width: Self.sourceWidth + paneWidthDelta, alignment: .leading)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(LinearGradient(
                    colors: [Color.primary.opacity(0.18), .clear],
                    startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)
                .opacity(0.7)
        }
    }

    private var retranslateButton: some View {
        Button(action: runRetranslate) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.trianglehead.clockwise")
                    .font(.system(size: 10.5, weight: .semibold))
                Text(model.action.displayName)
                    .font(PopupTheme.fontControl)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(PopupTheme.accentTintStrong, in: RoundedRectangle(cornerRadius: PopupTheme.rPill))
            .foregroundStyle(PopupTheme.accent)
            .contentShape(RoundedRectangle(cornerRadius: PopupTheme.rPill))
        }
        .buttonStyle(.plain)
        .disabled(!canRetranslate)
        .opacity(canRetranslate ? 1 : 0)
        .help(loc("Uruchom ponownie na poprawionym tekście (⌘↩)", "Run again on the edited text (⌘↩)"))
        .accessibilityLabel(loc("Uruchom ponownie na poprawionym tekście", "Run again on the edited text"))
    }

    private func runRetranslate() {
        guard canRetranslate else { return }
        model.closeDropdown()
        model.clearUndo()
        model.clearToneNote()
        retranslate(model.sourceText)
    }

    // MARK: Translation pane

    private var translationPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                label(resultLabel)
                if showLiveDot { LiveDot() }
                Spacer(minLength: 0)
            }
            content
        }
        .padding(PopupTheme.padPane)
        .frame(width: Self.translationWidth + paneWidthDelta, alignment: .leading)
        .overlay(alignment: .top) {
            if showAccentEdge {
                Rectangle()
                    .fill(LinearGradient(
                        colors: [PopupTheme.accent, .clear],
                        startPoint: .leading, endPoint: .trailing))
                    .frame(height: 2)
                    .opacity(0.7)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .capturing, .streaming:
            SkeletonView()
        case .error:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(PopupTheme.warn)
                Text(model.errorMessage ?? "Translation failed")
                    .font(PopupTheme.fontLead)
                    .foregroundStyle(.primary)
            }
        case .done:
            ScrollView {
                if model.action == .translate {
                    wordFlow
                } else if model.action == .fixGrammar {
                    if model.splitFixView { fixSplitContent } else { grammarDiffFlow }
                } else if model.action == .reply {
                    replyDrafts
                } else {
                    plainResultText
                }
            }
            .frame(maxHeight: paneMaxHeight)
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var replyDrafts: some View {
        VStack(spacing: 6) {
            ForEach(Array(model.replyDrafts.enumerated()), id: \.offset) { index, draft in
                ReplyDraftCard(
                    text: draft,
                    selected: model.selectedDraftIndex == index
                ) { model.selectDraft(index) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var wordFlow: some View {
        FlowLayout(lineSpacing: 5) {
            ForEach(FlowComposer.runs(model.segments)) { run in
                switch run {
                case .chunk(_, let leading, let word, let trailing):
                    HStack(spacing: 0) {
                        if !leading.isEmpty { punctuation(leading) }
                        wordView(word)
                        if !trailing.isEmpty { punctuation(trailing) }
                    }
                    .layoutValue(key: FlowItemKindKey.self, value: .word)
                case .gap(_, let text, let isWhitespace):
                    Text(isWhitespace ? " " : text)
                        .font(PopupTheme.fontLead)
                        .foregroundStyle(.primary)
                        .layoutValue(key: FlowItemKindKey.self, value: isWhitespace ? .space : .other)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func punctuation(_ text: String) -> some View {
        Text(text)
            .font(PopupTheme.fontLead)
            .foregroundStyle(.primary)
    }

    private func wordView(_ segment: TextSegment) -> some View {
        let selected = model.dropdownVisible && model.selectedWordID == segment.id
        return Text(segment.text)
            .font(PopupTheme.fontLead)
            .foregroundStyle(.primary)
            .padding(.horizontal, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(selected ? PopupTheme.accentTintStrong
                          : (hoverWordID == segment.id ? PopupTheme.chipNeutralBg : .clear))
            )
            .contentShape(Rectangle())
            .layoutValue(key: FlowItemKindKey.self, value: .word)
            .anchorPreference(key: WordAnchorKey.self, value: .bounds) { [segment.id: $0] }
            .onHover { hovering in
                if hovering { hoverWordID = segment.id }
                else if hoverWordID == segment.id { hoverWordID = nil }
            }
            .onTapGesture { onTapWord(segment) }
    }

    private func onTapWord(_ segment: TextSegment) {
        model.openDropdown(for: segment.id)
        if let cached = model.altsCache[segment.id] {
            model.alternatives = cached
            model.altsLoading = false
            return
        }
        let token = model.altsRequestToken
        let word = segment.text
        let translation = model.text
        Task { @MainActor in
            let alternatives = await fetchAlternatives(word, translation)
            guard model.altsRequestToken == token, model.dropdownVisible else { return }
            model.alternatives = alternatives
            model.altsLoading = false
            if !alternatives.isEmpty { model.altsCache[segment.id] = alternatives }
        }
    }

    private func onTapExplain(word: String, translation: String) {
        model.openExplanation()
        let wordID = model.selectedWordID
        if let wordID, let cached = model.explanationCache[wordID] {
            model.explanationText = cached
            model.explanationLoading = false
            return
        }
        let token = model.explanationRequestToken
        Task { @MainActor in
            let explanation = await fetchExplanation(word, translation)
            guard model.explanationRequestToken == token,
                  model.dropdownVisible, model.showingExplanation else { return }
            model.explanationText = explanation
            model.explanationLoading = false
            if let wordID, !explanation.isEmpty { model.explanationCache[wordID] = explanation }
        }
    }

    private var fixSplitContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                label(loc("Zmiany (\(model.diffChangeCount))", "Changes (\(model.diffChangeCount))"))
                Spacer(minLength: 0)
                diffEyeButton
            }
            if !model.diffHidden {
                grammarDiffFlow
                Divider()
                label(loc("Poprawiona wersja", "Corrected version"))
            }
            plainResultText
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var plainResultText: some View {
        Text(model.text)
            .font(PopupTheme.fontLead)
            .foregroundStyle(.primary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var diffEyeButton: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeOut(duration: PopupTheme.durFast)) {
                model.toggleDiffHidden()
            }
        } label: {
            Image(systemName: model.diffHidden ? "eye.slash" : "eye")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Color.secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(model.diffHidden ? loc("Pokaż zmiany", "Show changes") : loc("Ukryj zmiany", "Hide changes"))
        .accessibilityLabel(model.diffHidden ? loc("Pokaż zmiany", "Show changes") : loc("Ukryj zmiany", "Hide changes"))
    }

    private var grammarDiffFlow: some View {
        FlowLayout(lineSpacing: 5) {
            ForEach(model.diffParts) { part in
                switch part {
                case .same(_, let sameText):
                    ForEach(FlowComposer.runs(Tokenizer.segments(sameText))) { run in
                        switch run {
                        case .chunk(_, let leading, let word, let trailing):
                            Text(leading + word.text + trailing)
                                .font(PopupTheme.fontLead)
                                .foregroundStyle(.primary)
                                .layoutValue(key: FlowItemKindKey.self, value: .word)
                        case .gap(_, let gapText, let isWhitespace):
                            Text(isWhitespace ? " " : gapText)
                                .font(PopupTheme.fontLead)
                                .foregroundStyle(.primary)
                                .layoutValue(key: FlowItemKindKey.self, value: isWhitespace ? .space : .other)
                        }
                    }
                case .change(let id, let removed, let added):
                    changeChunk(id: id, removed: removed, added: added)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func changeChunk(id: Int, removed: String, added: String) -> some View {
        let selected = model.dropdownVisible && model.selectedWordID == id
        let hasBoth = !removed.isEmpty && !added.isEmpty
        return HStack(spacing: hasBoth ? 3 : 0) {
            if !removed.isEmpty {
                Text(removed)
                    .strikethrough(true, color: PopupTheme.diffDel)
                    .foregroundStyle(PopupTheme.diffDel)
            }
            if !added.isEmpty {
                Text(added)
                    .foregroundStyle(PopupTheme.accent)
            }
        }
        .font(PopupTheme.fontLead)
        .padding(.horizontal, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(selected ? PopupTheme.accentTintStrong
                      : (hoverWordID == id ? PopupTheme.chipNeutralBg : .clear))
        )
        .contentShape(Rectangle())
        .layoutValue(key: FlowItemKindKey.self, value: .word)
        .anchorPreference(key: WordAnchorKey.self, value: .bounds) { [id: $0] }
        .onHover { hovering in
            if hovering { hoverWordID = id }
            else if hoverWordID == id { hoverWordID = nil }
        }
        .onTapGesture { onTapFixChange(id: id, before: removed, after: added) }
    }

    private func onTapFixChange(id: Int, before: String, after: String) {
        guard !model.diffHidden else { return }
        model.openFixReason(id: id, before: before, after: after)
        if let cached = model.fixReasonCache[id] {
            model.explanationText = cached
            model.explanationLoading = false
            return
        }
        let token = model.explanationRequestToken
        let corrected = model.text
        Task { @MainActor in
            let reason = await fetchFixReason(before, after, corrected)
            guard model.explanationRequestToken == token,
                  model.dropdownVisible, model.fixReasonMode else { return }
            model.explanationText = reason
            model.explanationLoading = false
            if !reason.isEmpty { model.fixReasonCache[id] = reason }
        }
    }

    @ViewBuilder
    private func dropdownOverlay(anchors: [Int: Anchor<CGRect>]) -> some View {
        GeometryReader { proxy in
            if model.dropdownVisible, let id = model.selectedWordID, let anchor = anchors[id] {
                let wordRect = proxy[anchor]
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { model.closeDropdown() }
                AlternativesDropdown(
                    model: model,
                    onPick: { chosen in
                        let original = model.segments.first { $0.id == id }?.text ?? ""
                        model.snapshotForUndo()
                        pickAlternative(original, chosen, model.text)
                    },
                    onExplain: {
                        let word = model.segments.first { $0.id == id }?.text ?? ""
                        onTapExplain(word: word, translation: model.text)
                    },
                    onBack: { model.closeExplanation() }
                )
                .fixedSize()
                .offset(dropdownOffset(wordRect: wordRect, container: proxy.size))
            }
        }
    }

    private let dropdownGap: CGFloat = 4

    private let dropdownShadowPad: CGFloat = 14

    private var estimatedDropdownHeight: CGFloat {
        // The "Dlaczego tak?" header row (issue #39) adds one row above either view.
        let explainRow: CGFloat = 36
        if model.fixReasonMode {
            return FixReasonLayout.estimatedDropdownHeight(
                content: model.fixReasonContentHeight, loading: model.explanationLoading)
        }
        if model.showingExplanation {
            return explainRow + (model.explanationLoading ? 40 : 132)
        }
        let list = model.altsLoading || model.alternatives.isEmpty
            ? 40 : CGFloat(model.alternatives.count) * 32 + 8
        return explainRow + list
    }

    private func dropdownOffset(wordRect: CGRect, container: CGSize) -> CGSize {
        let maxX = max(dropdownShadowPad, container.width - AlternativesDropdown.width - dropdownShadowPad)
        let x = min(max(dropdownShadowPad, wordRect.minX), maxX)
        let y = max(dropdownShadowPad, wordRect.maxY + dropdownGap)
        return CGSize(width: x, height: y)
    }

    // MARK: Footer

    private var truncatedFooter: some View {
        HStack(spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(loc("Tłumaczenie obcięte (limit modelu). Skróć zaznaczenie.", "Translation truncated (model limit). Shorten the selection."))
        }
        .font(PopupTheme.fontControl)
        .foregroundStyle(PopupTheme.warn)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, PopupTheme.padPane)
        .padding(.vertical, 8)
        .background(PopupTheme.warnBg)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(PopupTheme.fontSectionLabel)
            .tracking(1.0)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
    }
}

private struct ReplyDraftCard: View {
    let text: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(selected ? PopupTheme.accent : Color.secondary)
                Text(text)
                    .font(PopupTheme.fontLead)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: PopupTheme.rPane)
                    .fill(selected ? PopupTheme.accentTintStrong : (hovering ? PopupTheme.chipNeutralBg : .clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: PopupTheme.rPane)
                    .strokeBorder(selected ? PopupTheme.accent.opacity(0.5) : Color.primary.opacity(0.10))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Hoverable(configuration: configuration)
    }

    private struct Hoverable: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: PopupTheme.rControl)
                        .fill(Color.primary.opacity(hovering ? 0.09 : 0))
                )
                .opacity(configuration.isPressed ? 0.55 : 1)
                .onHover { hovering = $0 }
        }
    }
}

private struct LiveDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(PopupTheme.accent)
            .frame(width: 6, height: 6)
            .scaleEffect(pulsing ? 1.0 : 0.55)
            .opacity(pulsing ? 1.0 : 0.45)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
    }
}

private struct SkeletonView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep = false

    private let trailingInsets: [CGFloat] = [0, 40, 16, 96]

    var body: some View {
        let bars = VStack(alignment: .leading, spacing: 10) {
            ForEach(trailingInsets.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: PopupTheme.rControl)
                    .fill(PopupTheme.chipNeutralBg)
                    .frame(height: 11)
                    .padding(.trailing, trailingInsets[index])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        bars
            .overlay {
                if !reduceMotion {
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(0.45), .clear],
                        startPoint: .leading, endPoint: .trailing)
                        .frame(width: 90)
                        .offset(x: sweep ? 260 : -90)
                        .mask(bars)
                        .blendMode(.plusLighter)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                    sweep = true
                }
            }
    }
}
