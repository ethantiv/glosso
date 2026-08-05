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
                    withAnimation(.snappy(duration: 0.2)) { appeared = true }
                }
            }
    }

    private var panelBox: some View {
        VStack(spacing: 0) {
            header
            if model.action == .translate { translateControls }
            if model.toneNoteVisible { toneNoteRow.transition(.opacity) }
            HStack(alignment: .top, spacing: 0) {
                sourcePane
                Divider()
                translationPane
            }
            if model.phase == .done && model.truncated {
                truncatedFooter.transition(.opacity)
            }
        }
        // The one Liquid Glass surface in the app: a floating panel over another app's content is the functional layer,
        // and the regular variant is what Apple prescribes for text-heavy floating surfaces. Everything inside it stays
        // a standard control on plain backgrounds — glass on glass is not allowed.
        .glassEffect(.regular, in: .rect(cornerRadius: PopupTheme.rWindow))
        .clipShape(RoundedRectangle(cornerRadius: PopupTheme.rWindow))
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
        HStack(spacing: 8) {
            verbPicker
            Spacer(minLength: 0)
            headerButtons
        }
        .padding(.leading, 13)
        .padding(.trailing, PopupTheme.padWindow)
        .padding(.vertical, PopupTheme.padWindow)
    }

    // Second row, Translate-only: the language pair and the tone picker.
    private var translateControls: some View {
        HStack(spacing: 10) {
            languagePair
            tonePicker
            if model.phase == .done && model.toneChange != nil { toneNoteButton }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .padding(.bottom, PopupTheme.padWindow)
    }

    /// Four mutually exclusive verbs are a segmented control; the case order is load-bearing (it drives prefetch too).
    private var verbPicker: some View {
        Picker(loc("Co zrobić z zaznaczeniem", "What to do with the selection"), selection: verbSelection) {
            ForEach(Action.allCases, id: \.self) { action in
                Label(action.displayName, systemImage: action.systemImage).tag(action)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }

    private var verbSelection: Binding<Action> {
        Binding {
            model.action
        } set: { action in
            guard model.action != action else { return }
            model.action = action
            model.clearUndo()
            model.clearToneNote()
            selectAction(action)
        }
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

    /// A menu, not a click-to-cycle pill: cycling through N states hides the options a person is choosing between.
    private var tonePicker: some View {
        Picker(loc("Ton wypowiedzi", "Tone"), selection: toneSelection) {
            ForEach(Formality.allCases, id: \.self) { formality in
                Text(formality.displayName).tag(formality)
            }
        }
        .labelsHidden()
        .fixedSize()
        .accessibilityLabel(loc("Ton wypowiedzi", "Tone"))
    }

    private var toneSelection: Binding<Formality> {
        Binding {
            model.formality
        } set: { next in
            guard model.formality != next else { return }
            model.noteToneChange(from: model.formality, to: next)
            model.formality = next
            model.clearUndo()
            selectFormality(next)
        }
    }

    private var toneNoteButton: some View {
        Button(loc("Co się zmieniło?", "What changed?"), systemImage: "arrow.left.arrow.right", action: toggleToneNote)
            .buttonStyle(.borderless)
            .help(loc("Pokaż, co zmieniła zmiana tonu wypowiedzi.", "Show what the tone change did."))
            .accessibilityAddTraits(model.toneNoteVisible ? .isSelected : [])
    }

    private var toneNoteRow: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "info.circle")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)
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

    /// The direction is a readout, not a control — it says which way the model translated, and nothing here is clickable.
    private func pill(_ code: String, accent: Bool) -> some View {
        Text(code)
            .font(PopupTheme.fontControl)
            .tracking(0.2)
            .foregroundStyle(accent ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
    }

    private func directionArrow(reversed: Bool) -> some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .scaleEffect(x: reversed ? -1 : 1, anchor: .center)
    }

    private var headerButtons: some View {
        HStack(spacing: 2) {
            if canReplace {
                Button(action: { replace(model.text) }) {
                    Image(systemName: "text.insert")
                }
                .help(loc("Zastąp zaznaczenie tłumaczeniem", "Replace the selection with the translation"))
                .accessibilityLabel(loc("Zastąp zaznaczenie tłumaczeniem", "Replace the selection with the translation"))
            }
            if canCopy {
                Button(action: copy) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                        .foregroundStyle(copied ? AnyShapeStyle(Color.green) : AnyShapeStyle(.primary))
                }
                .help(loc("Kopiuj tłumaczenie", "Copy the translation"))
                .accessibilityLabel(loc("Kopiuj tłumaczenie", "Copy the translation"))
            }
            if canUndo {
                Button(action: undo) {
                    Image(systemName: "arrow.uturn.backward")
                }
                .help(loc("Przywróć poprzednie tłumaczenie", "Restore the previous translation"))
                .accessibilityLabel(loc("Przywróć poprzednie tłumaczenie", "Restore the previous translation"))
            }
            Button(action: close) {
                Image(systemName: "xmark")
            }
            .help(loc("Zamknij", "Close"))
            .accessibilityLabel(loc("Zamknij", "Close"))
        }
        .buttonStyle(.borderless)
        .controlSize(.large)
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
                        .font(PopupTheme.fontLead)
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
                .scrollEdgeEffectStyle(.soft, for: .all)
            } else if model.phase == .capturing {
                SkeletonView()
            }
        }
        .padding(PopupTheme.padPane)
        .frame(width: Self.sourceWidth + paneWidthDelta, alignment: .leading)
    }

    private var retranslateButton: some View {
        Button(model.action.displayName, systemImage: "arrow.trianglehead.clockwise", action: runRetranslate)
            .buttonStyle(.bordered)
            .controlSize(.small)
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
                if showLiveDot {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(loc("Trwa tłumaczenie", "Translating"))
                }
                Spacer(minLength: 0)
            }
            content
        }
        .padding(PopupTheme.padPane)
        .frame(width: Self.translationWidth + paneWidthDelta, alignment: .leading)
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .capturing, .streaming:
            SkeletonView()
        case .error:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
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
            .scrollEdgeEffectStyle(.soft, for: .all)
        }
    }

    private var replyDrafts: some View {
        Picker(loc("Wybierz odpowiedź", "Pick a reply"), selection: draftSelection) {
            ForEach(Array(model.replyDrafts.enumerated()), id: \.offset) { index, draft in
                Text(draft).tag(index)
            }
        }
        .pickerStyle(.radioGroup)
        .labelsHidden()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var draftSelection: Binding<Int> {
        Binding { model.selectedDraftIndex ?? -1 } set: { model.selectDraft($0) }
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
        // The highlight is inset outward instead of padding the text: horizontal padding here widened every word and
        // showed up as a double space between words and a gap before punctuation.
        return Text(segment.text)
            .font(PopupTheme.fontLead)
            .foregroundStyle(.primary)
            .background {
                RoundedRectangle(cornerRadius: 4)
                    .fill(selected ? AnyShapeStyle(.selection)
                          : (hoverWordID == segment.id ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear)))
                    .padding(.horizontal, -2)
            }
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
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.15)) {
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
                    .strikethrough(true, color: .red)
                    .foregroundStyle(.red)
            }
            if !added.isEmpty {
                // Bold as well as green: colour alone must never be the only channel carrying the change.
                Text(added)
                    .fontWeight(.semibold)
                    .foregroundStyle(.green)
            }
        }
        .font(PopupTheme.fontLead)
        .background {
            RoundedRectangle(cornerRadius: 4)
                .fill(selected ? AnyShapeStyle(.selection)
                      : (hoverWordID == id ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear)))
                .padding(.horizontal, -2)
        }
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
        if model.fixReasonMode {
            return FixReasonLayout.estimatedDropdownHeight(
                content: model.fixReasonContentHeight, loading: model.explanationLoading)
        }
        if model.showingExplanation {
            return AlternativesLayout.explanationHeight(
                content: model.explanationContentHeight, loading: model.explanationLoading)
        }
        return AlternativesLayout.estimatedHeight(
            count: model.alternatives.count, loading: model.altsLoading)
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
        .symbolRenderingMode(.multicolor)
        .font(PopupTheme.fontControl)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, PopupTheme.padPane)
        .padding(.vertical, 8)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(PopupTheme.fontLabel)
            .tracking(1.0)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
    }
}

/// Placeholder bars while the model works. The system's own placeholder redaction replaced a hand-rolled shimmer whose
/// additive white sweep only read correctly in light mode and never followed the panel's resizable width.
private struct SkeletonView: View {
    /// Trailing insets in points, not a horizontal scale: scaling the drawn bar squashes its corner radius with it.
    private let trailingInsets: [CGFloat] = [0, 40, 16, 96]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(trailingInsets.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: PopupTheme.rControl)
                    .fill(.quaternary)
                    .frame(height: 11)
                    .padding(.trailing, trailingInsets[index])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(loc("Trwa tłumaczenie", "Translating"))
    }
}
