import AppKit
import SwiftUI

struct PopupView: View {
    let model: PopupModel
    let close: () -> Void
    let selectFormality: (Formality) -> Void
    let fetchAlternatives: (_ word: String, _ translation: String) async -> [String]
    let fetchExplanation: (_ word: String, _ translation: String) async -> String
    let pickAlternative: (_ original: String, _ chosen: String, _ translation: String) -> Void
    let replace: (String) -> Void
    let resizeBy: (_ translation: CGSize, _ ended: Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var copied = false
    @State private var appeared = false
    @State private var hoverWordID: Int?
    @State private var hoverGrip = false

    private static let sourceWidth: CGFloat = 268
    private static let translationWidth: CGFloat = 300
    private static let maxPaneHeight: CGFloat = 400

    // Transparent inset reserved inside the window for the panel's SwiftUI shadow to
    // render unclipped (radius 16 + y 6 ≈ 22 below, less on the sides/top). The panel
    // sits this far from the window edges, so the controller shifts the window
    // top-left by the same amount to keep the visible panel under the cursor.
    static let shadowMargin: CGFloat = 24

    // Floor for user resizing (panel.contentMinSize): the panes at their design
    // widths plus the Divider and the shadow margins, so the card never clips at
    // minimum width; 160 is the controller's initial content height.
    static var minWindowSize: CGSize {
        CGSize(
            width: sourceWidth + translationWidth + 1 + 2 * shadowMargin,
            height: 160 + 2 * shadowMargin
        )
    }

    private var canCopy: Bool { model.phase == .done && !model.text.isEmpty }
    // Replace overwrites the still-selected source in place, so unlike the
    // non-destructive Copy it must not be offered for a truncated result — one
    // click would replace the original selection with the partial translation
    // (the source app has no undo for the lost selection), issue #22.
    private var canReplace: Bool { canCopy && !model.truncated }
    private var canUndo: Bool {
        model.canUndo && (model.phase == .done || model.phase == .error)
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
            .shadow(color: .black.opacity(0.20), radius: 16, y: 6)
            .padding(.bottom, reservedBottom)
            .overlayPreferenceValue(WordAnchorKey.self) { anchors in
                dropdownOverlay(anchors: anchors)
            }
            .padding(Self.shadowMargin)
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
            HStack(alignment: .top, spacing: 0) {
                sourcePane
                Divider()
                translationPane
            }
            if model.phase == .done && model.truncated {
                truncatedFooter
            }
        }
        .background(PopupTheme.accentWash)
        .background(VisualEffectBackground(material: .popover))
        .clipShape(RoundedRectangle(cornerRadius: PopupTheme.rWindow))
        .overlay(
            RoundedRectangle(cornerRadius: PopupTheme.rWindow)
                .strokeBorder(PopupTheme.hairline, lineWidth: 0.5)
        )
    }

    // Window growth that hosts the open dropdown. Not animated: animating it would
    // fire didResizeNotification (and its top-left re-pin) every frame mid-grow.
    // Once the user has resized the window (sizingOptions cleared) it no longer
    // grows for this reservation — the card squeezes inside the fixed window
    // instead, clipping only near minimum height with a tall dropdown.
    private var reservedBottom: CGFloat {
        model.dropdownVisible ? estimatedDropdownHeight + dropdownGap + dropdownShadowPad : 0
    }

    // MARK: Resize grip

    // The window has no system resize edges (see FloatingPanel), so this grip in
    // the card's bottom-right corner is the only resize affordance. The hit area
    // and cursor live in ResizeGripArea (an NSView): a SwiftUI DragGesture here
    // would never fire — window-background dragging claims the mouseDown first.
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
                    hoverGrip ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                )
                .frame(width: 14, height: 14)
                .allowsHitTesting(false)
            )
            .onHover { hoverGrip = $0 }
            .accessibilityLabel("Zmień rozmiar okna")
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            languagePair
            tonePill
            Spacer(minLength: 0)
            headerButtons
        }
        .padding(.leading, 13)
        .padding(.trailing, PopupTheme.padWindow)
        .padding(.vertical, PopupTheme.padWindow)
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
                    .font(.system(size: 10.5, weight: .semibold))
                Text(model.formality.displayName)
                    .font(PopupTheme.fontMeta)
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
            .font(PopupTheme.fontMeta)
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
                Button(action: { model.undo() }) {
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
            label("Oryginał")
            if !model.sourceText.isEmpty {
                ScrollView {
                    Text(model.sourceText)
                        .font(PopupTheme.fontSource)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: model.userResized ? .infinity : Self.maxPaneHeight)
                .scrollBounceBehavior(.basedOnSize)
            } else if model.phase == .capturing {
                // Only shimmer while we are still waiting for the selection; an
                // error before capture leaves sourceText empty, and a skeleton
                // there would imply the original is still loading forever.
                SkeletonView()
            }
        }
        .padding(PopupTheme.padPane)
        .frame(
            minWidth: Self.sourceWidth,
            maxWidth: model.userResized ? .infinity : Self.sourceWidth,
            alignment: .leading
        )
        .background(PopupTheme.paneRecessed)
    }

    // MARK: Translation pane

    private var translationPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                label("Tłumaczenie")
                if showLiveDot { LiveDot() }
                Spacer(minLength: 0)
            }
            content
        }
        .padding(PopupTheme.padPane)
        .frame(
            minWidth: Self.translationWidth,
            maxWidth: model.userResized ? .infinity : Self.translationWidth,
            alignment: .leading
        )
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
            // Words become individually clickable (issue #17); this drops
            // drag-to-select on the result, but the header Copy button still
            // copies the whole translation.
            ScrollView {
                wordFlow
            }
            .frame(maxHeight: model.userResized ? .infinity : Self.maxPaneHeight)
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var wordFlow: some View {
        FlowLayout(lineSpacing: 5) {
            ForEach(model.segments) { segment in
                if segment.isWord {
                    wordView(segment)
                } else {
                    Text(separatorDisplay(segment))
                        .font(PopupTheme.fontLead)
                        .foregroundStyle(.primary)
                        .layoutValue(key: FlowItemKindKey.self, value: separatorKind(segment))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private func separatorDisplay(_ segment: TextSegment) -> String {
        // Collapse any whitespace run (spaces, tabs, newlines) to a single space
        // for display; the real text lives in model.text and is what Copy/reword use.
        segment.isWhitespace ? " " : segment.text
    }

    private func separatorKind(_ segment: TextSegment) -> FlowItemKind {
        segment.isWhitespace ? .space : .other
    }

    private func onTapWord(_ segment: TextSegment) {
        model.openDropdown(for: segment.id)
        let token = model.altsRequestToken
        let word = segment.text
        let translation = model.text
        Task { @MainActor in
            let alternatives = await fetchAlternatives(word, translation)
            guard model.altsRequestToken == token, model.dropdownVisible else { return }
            model.alternatives = alternatives
            model.altsLoading = false
        }
    }

    private func onTapExplain(word: String, translation: String) {
        model.openExplanation()
        let token = model.explanationRequestToken
        Task { @MainActor in
            let explanation = await fetchExplanation(word, translation)
            // The dropdown may have closed or reopened on another word while the
            // fetch ran; only land if this is still the request the user is waiting on.
            guard model.explanationRequestToken == token,
                  model.dropdownVisible, model.showingExplanation else { return }
            model.explanationText = explanation
            model.explanationLoading = false
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
        .font(PopupTheme.fontMeta)
        .foregroundStyle(PopupTheme.warn)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, PopupTheme.padPane)
        .padding(.vertical, 8)
        .background(PopupTheme.warnBg)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(PopupTheme.fontLabel)
            .tracking(0.5)
            .textCase(.uppercase)
            .foregroundStyle(.tertiary)
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
