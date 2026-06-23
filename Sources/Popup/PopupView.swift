import AppKit
import SwiftUI

struct PopupView: View {
    // @Bindable, not let: the source pane is an editable TextField bound to
    // $model.sourceText (issue #44).
    @Bindable var model: PopupModel
    let close: () -> Void
    let selectFormality: (Formality) -> Void
    let selectAction: (Action) -> Void
    let fetchAlternatives: (_ word: String, _ translation: String) async -> [String]
    let fetchExplanation: (_ word: String, _ translation: String) async -> String
    let fetchFixReason: (_ before: String, _ after: String, _ corrected: String) async -> String
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

    // Transparent inset reserved inside the window for the panel's SwiftUI shadow to
    // render unclipped (radius 4 + y 1 = 5 below, less on the sides/top). The panel
    // sits this far from the window edges, so the controller shifts the window
    // top-left by the same amount to keep the visible panel under the cursor.
    static let shadowMargin: CGFloat = 6

    // The resize grip stretches the content, not the window: each pane gets half
    // of the dragged width (rounded down — fractional widths destabilize the
    // window's ideal-size pipeline), and the height cap rises by the dragged
    // height; the window then follows the grown content (see
    // PopupModel.sizeDelta). Dragging down is only visible once the text is
    // tall enough to hit the cap.
    private var paneWidthDelta: CGFloat { (model.sizeDelta.width / 2).rounded(.down) }
    private var paneMaxHeight: CGFloat { Self.maxPaneHeight + model.sizeDelta.height }

    private var resultLabel: String {
        switch model.action {
        case .translate: "Tłumaczenie"
        case .summarize: "Streszczenie"
        case .fixGrammar: "Poprawka"
        case .reply: "Odpowiedź"
        }
    }

    private var canCopy: Bool { model.phase == .done && !model.text.isEmpty }
    // Replace overwrites the still-selected source in place, so unlike the
    // non-destructive Copy it must not be offered for a truncated result — one
    // click would replace the original selection with the partial translation
    // (the source app has no undo for the lost selection), issue #22. It is also
    // suppressed for Reply (#60): a reply is a new message, not a transform of the
    // selection, so pasting it back would destroy the message being replied to.
    private var canReplace: Bool { canCopy && !model.truncated && model.action != .reply }
    private var canUndo: Bool {
        model.canUndo && (model.phase == .done || model.phase == .error)
    }
    // The re-translate button (issue #44) lights up only once the user has actually
    // edited the source away from what was last sent to the model.
    private var canRetranslate: Bool {
        !model.sourceText.isEmpty && model.sourceText != model.capturedSource
    }
    private var showLiveDot: Bool { model.phase == .capturing || model.phase == .streaming }
    private var showAccentEdge: Bool { model.phase == .streaming || model.phase == .done }

    var body: some View {
        // The open dropdown is an in-window overlay, so the window must be tall
        // enough to show it; for a short translation it isn't. Reserve transparent
        // space below the (unchanged) panel box only while a dropdown is open, so
        // it grows the window downward and the dropdown floats there unclipped
        // (issue #32). The dropdown is always placed below the word into this space.
        panelBox
            .overlay(alignment: .bottomTrailing) { resizeGrip }
            .shadow(color: .black.opacity(0.10), radius: 4, y: 1)
            .padding(.bottom, reservedBottom)
            .overlayPreferenceValue(WordAnchorKey.self) { anchors in
                dropdownOverlay(anchors: anchors)
            }
            .padding(Self.shadowMargin)
            // fixedSize lays the card out at its IDEAL size regardless of the
            // window: under a concrete proposal the panes' ScrollViews greedily
            // fill the window instead of reporting their content size. The
            // measured ideal goes to the controller, which owns the window frame.
            // Pinned top-leading: while the window catches up (one runloop turn),
            // the card must not float centered with a detached shadow halo.
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
            // Only Translate carries a language pair and tone, so this second row
            // shows for it alone — the other verbs drop it rather than leave an
            // empty band (issue #23).
            if model.action == .translate { translateControls }
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
        // Drag-to-move lives here, not in isMovableByWindowBackground (see
        // FloatingPanel): interactive children (buttons, words, the tone pill)
        // win SwiftUI's gesture arbitration over this ancestor gesture, and it
        // cannot fire over the resize grip — events over an NSViewRepresentable
        // never reach SwiftUI's gesture graph. The panel never becomes key, so
        // the gesture only receives events with window-activation events allowed.
        .gesture(WindowDragGesture())
        .allowsWindowActivationEvents()
    }

    // Window growth that hosts the open dropdown. Not animated: animating it would
    // report a new ideal size (and a window setFrame) every frame mid-grow.
    private var reservedBottom: CGFloat {
        model.dropdownVisible ? estimatedDropdownHeight + dropdownGap + dropdownShadowPad : 0
    }

    // MARK: Resize grip

    // The window has no system resize edges (see FloatingPanel), so this grip in
    // the card's bottom-right corner is the only resize affordance. The hit area
    // and cursor live in ResizeGripArea (an NSView): a SwiftUI DragGesture here
    // never receives the drag (see ResizeGripArea).
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
            .accessibilityLabel("Zmień rozmiar okna")
    }

    // MARK: Header

    // First row: the verb strip (issue #23) and the action buttons. The strip is
    // always present, so non-translate modes never show an empty header band.
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
            // Switching verbs re-runs from scratch, so the pre-reword result no
            // longer applies — drop the undo snapshot (mirrors the tone pill).
            model.clearUndo()
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
            .background(active ? PopupTheme.accentTintStrong : PopupTheme.chipNeutralBg, in: Capsule())
            .foregroundStyle(active ? PopupTheme.accent : Color.secondary)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("\(action.displayName) zaznaczenie")
        .accessibilityLabel("\(action.displayName) zaznaczenie")
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    @ViewBuilder
    private var languagePair: some View {
        switch model.direction {
        case .fromPolish(let second):
            HStack(spacing: 7) {
                pill("PL", accent: false)
                directionArrow(reversed: false)
                pill(second.code, accent: true)
            }
        case .toPolish(let second):
            HStack(spacing: 7) {
                pill("PL", accent: true)
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
            withAnimation(reduceMotion ? nil : .easeOut(duration: PopupTheme.durFast)) {
                model.formality = nextF
            }
            // A tone change re-translates from scratch, so the pre-reword result no
            // longer applies — drop the undo snapshot (issue #25).
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
            .background(active ? PopupTheme.accentTintStrong : PopupTheme.chipNeutralBg, in: Capsule())
            .foregroundStyle(active ? PopupTheme.accent : Color.secondary)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Ton wypowiedzi: \(model.formality.displayName). Kliknij, aby zmienić.")
        .accessibilityLabel("Ton wypowiedzi: \(model.formality.displayName). Kliknij, aby zmienić.")
    }

    private func pill(_ code: String, accent: Bool) -> some View {
        Text(code)
            .font(PopupTheme.fontControl)
            .tracking(0.2)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(accent ? PopupTheme.accentTintStrong : PopupTheme.chipNeutralBg, in: Capsule())
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
                .help("Zastąp zaznaczenie tłumaczeniem")
                .accessibilityLabel("Zastąp zaznaczenie tłumaczeniem")
            }
            if canCopy {
                Button(action: copy) {
                    iconLabel(copied ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                        .foregroundStyle(copied ? PopupTheme.copied : Color.secondary)
                }
                .buttonStyle(IconButtonStyle())
                .help("Kopiuj tłumaczenie")
                .accessibilityLabel("Kopiuj tłumaczenie")
                .animation(reduceMotion ? nil : .easeOut(duration: PopupTheme.durFast), value: copied)
            }
            if canUndo {
                Button(action: undo) {
                    iconLabel("arrow.uturn.backward")
                        .foregroundStyle(Color.secondary)
                }
                .buttonStyle(IconButtonStyle())
                .help("Przywróć poprzednie tłumaczenie")
                .accessibilityLabel("Przywróć poprzednie tłumaczenie")
            }
            Button(action: close) {
                iconLabel("xmark")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(IconButtonStyle())
            .help("Zamknij")
            .accessibilityLabel("Zamknij")
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
                label("Oryginał")
                Spacer(minLength: 0)
                retranslateButton
            }
            if !model.sourceText.isEmpty {
                ScrollView {
                    // Editable source (issue #44): axis: .vertical grows the field
                    // with its content (and reports an intrinsic height) instead of
                    // greedily filling like TextEditor, which the window auto-sizing
                    // relies on. The ScrollView caps it at paneMaxHeight.
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
                // Only shimmer while we are still waiting for the selection; an
                // error before capture leaves sourceText empty, and a skeleton
                // there would imply the original is still loading forever. Keying
                // on emptiness (not phase) keeps the source visible during a
                // tone/verb/alternative re-run, which resets phase to .capturing
                // while the already-captured source stays put.
                SkeletonView()
            }
        }
        .padding(PopupTheme.padPane)
        .frame(width: Self.sourceWidth + paneWidthDelta, alignment: .leading)
        // A whisper-thin top rule mirrors the translation pane's accent edge — same
        // leading-to-clear gradient, just neutral — so both panes read as starting on
        // the same top line (the source has no accent of its own).
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
            .background(PopupTheme.accentTintStrong, in: Capsule())
            .foregroundStyle(PopupTheme.accent)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!canRetranslate)
        .opacity(canRetranslate ? 1 : 0)
        .help("Uruchom ponownie na poprawionym tekście (⌘↩)")
        .accessibilityLabel("Uruchom ponownie na poprawionym tekście")
    }

    // Editing re-runs from scratch, so the open word dropdown and the pre-edit undo
    // snapshot no longer apply — drop both, mirroring the tone/verb pills.
    private func runRetranslate() {
        guard canRetranslate else { return }
        model.closeDropdown()
        model.clearUndo()
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
            // The translation is revealed only once complete; while it is still
            // being produced the pane stays a shimmering skeleton (the live-dot on
            // the label signals progress), rather than showing half-formed tokens.
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
                // Per-word alternatives (#17/#39) only make sense for a translation,
                // so only Translate gets the clickable word flow (which drops
                // drag-to-select); the other verbs render plain selectable text.
                if model.action == .translate {
                    wordFlow
                } else if model.action == .fixGrammar {
                    grammarDiffFlow
                } else if model.action == .reply {
                    replyDrafts
                } else {
                    Text(model.text)
                        .font(PopupTheme.fontLead)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxHeight: paneMaxHeight)
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    // The reply drafts (issue #60) as a pick-one list: tapping a card selects it
    // (highlighted) and mirrors it into model.text so Copy copies the chosen draft.
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
                    // The word stays the only clickable target; its hugging
                    // punctuation rides in the same flow item so it can never wrap
                    // onto a new line on its own.
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
            // The dropdown may have closed or reopened on another word while the
            // fetch ran; only land if this is still the request the user is waiting on.
            guard model.explanationRequestToken == token,
                  model.dropdownVisible, model.showingExplanation else { return }
            model.explanationText = explanation
            model.explanationLoading = false
            if let wordID, !explanation.isEmpty { model.explanationCache[wordID] = explanation }
        }
    }

    // Grammar-diff for fixGrammar results (issue #51): the corrected text rendered
    // word-by-word with each change shown as a struck error → correction, tappable
    // for a one-line Polish reason. Unchanged spans tokenize into the same wrapping
    // flow as wordFlow; only the changes are clickable. When nothing changed it is
    // just the plain corrected text (all .same parts).
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

    // One clickable diff change: the struck error and its correction side by side,
    // anchored (like wordView) so the reason dropdown can sit below it. removed or
    // added may be empty for a pure deletion or insertion.
    private func changeChunk(id: Int, removed: String, added: String) -> some View {
        let selected = model.dropdownVisible && model.selectedWordID == id
        let hasBoth = !removed.isEmpty && !added.isEmpty
        return HStack(spacing: hasBoth ? 3 : 0) {
            if !removed.isEmpty {
                Text(removed)
                    .strikethrough(true, color: PopupTheme.warn)
                    .foregroundStyle(PopupTheme.warn)
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
            // The dropdown may have closed or reopened on another change while the
            // fetch ran; only land if this is still the request the user awaits.
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
                        // Snapshot the current result before the reword replaces it, so the
                        // header Undo button can restore it (issue #25).
                        model.snapshotForUndo()
                        // The coordinator's restart resets the pane (closing this dropdown
                        // via resetTranslationPane), so the reworded result can't reappear
                        // under a stale dropdown.
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

    // Slack around the dropdown so its .shadow(radius:10, y:4) renders inside the
    // window instead of clipping at the edge when the word sits near the panel's
    // bottom/right (the AlternativesDropdown shadow extends ~14pt down, ~10pt side).
    private let dropdownShadowPad: CGFloat = 14

    // Estimate, not a measurement; drives how far reservedBottom grows the window.
    // 32pt/row fits a single-line alternative with a little slack. buildAlternatives
    // may return short phrases, which can wrap in the 200pt-wide dropdown and exceed
    // this — then the overflow rows clip at the grown window's edge. Acceptable for
    // now because alternatives are overwhelmingly single words; revisit with a real
    // measurement if multi-line alternatives become common.
    private var estimatedDropdownHeight: CGFloat {
        // The "Dlaczego tak?" header row (issue #39) adds one row above either view.
        let explainRow: CGFloat = 36
        // The grammar-diff reason (issue #51) is a header row plus the one-line
        // reason, sized like the explanation view below.
        // Reserve the reason's actual measured height (#73) so the window grows to
        // fit it instead of clipping a long reason; AlternativesDropdown frames and
        // scrolls the same min(measured, cap) via FixReasonLayout, so reserve and
        // dropdown stay in lockstep (the no-clip invariant is tested).
        if model.fixReasonMode {
            return FixReasonLayout.estimatedDropdownHeight(
                content: model.fixReasonContentHeight, loading: model.explanationLoading)
        }
        if model.showingExplanation {
            // A one-sentence explanation wraps to a few lines in the 200pt dropdown;
            // reserve generously so the grown window doesn't clip it (estimate, not a
            // measurement — same caveat as the alternatives path below).
            return explainRow + (model.explanationLoading ? 40 : 132)
        }
        let list = model.altsLoading || model.alternatives.isEmpty
            ? 40 : CGFloat(model.alternatives.count) * 32 + 8
        return explainRow + list
    }

    private func dropdownOffset(wordRect: CGRect, container: CGSize) -> CGSize {
        // reservedBottom always leaves room below the word, so place the dropdown
        // there — no upward flip needed (issue #32).
        let maxX = max(dropdownShadowPad, container.width - AlternativesDropdown.width - dropdownShadowPad)
        let x = min(max(dropdownShadowPad, wordRect.minX), maxX)
        let y = max(dropdownShadowPad, wordRect.maxY + dropdownGap)
        return CGSize(width: x, height: y)
    }

    // MARK: Footer

    private var truncatedFooter: some View {
        HStack(spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("Tłumaczenie obcięte (limit modelu). Skróć zaznaczenie.")
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
            .tracking(0.5)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
    }
}

// One reply draft in the pick-one list (issue #60). Mirrors AlternativeRow's hover
// affordance but renders a full multi-line draft as a bordered card and shows the
// selected state (the chosen draft is what Copy copies).
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
