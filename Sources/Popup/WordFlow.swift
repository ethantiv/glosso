import SwiftUI

/// One run of the finished translation: either a clickable word or a separator
/// (whitespace/punctuation) rendered inline but not clickable. Splitting is
/// lossless — `segments(_:).map(\.text).joined()` reproduces the input — so the
/// canonical `model.text` (used by Copy and reword) never drifts from the display.
struct TextSegment: Identifiable, Hashable {
    let id: Int
    let text: String
    let isWord: Bool
    // True only for a non-word run that is pure whitespace (collapses to a single
    // space and to a wrap-collapsible `.space` in the flow); punctuation runs and
    // words are false. Classified once here so display and layout can't disagree.
    let isWhitespace: Bool
}

enum Tokenizer {
    /// Alternates word / separator runs. Letters, digits and apostrophes (so
    /// English contractions like "don't" stay one token) are word characters;
    /// everything else — spaces, newlines, punctuation, hyphens — is a separator.
    /// Iterates `Character` (graphemes) so Polish diacritics stay intact.
    static func segments(_ string: String) -> [TextSegment] {
        var out: [TextSegment] = []
        var buffer = ""
        var bufferIsWord: Bool?

        func flush() {
            guard let isWord = bufferIsWord, !buffer.isEmpty else { return }
            let isWhitespace = !isWord && buffer.allSatisfy(\.isWhitespace)
            out.append(TextSegment(id: out.count, text: buffer, isWord: isWord, isWhitespace: isWhitespace))
            buffer = ""
        }

        for character in string {
            let isWordChar = character.isLetter || character.isNumber || character == "'" || character == "\u{2019}"
            if bufferIsWord == nil { bufferIsWord = isWordChar }
            if isWordChar != bufferIsWord {
                flush()
                bufferIsWord = isWordChar
            }
            buffer.append(character)
        }
        flush()
        return out
    }
}

/// One item laid out by `FlowLayout`: either a word with its hugging punctuation
/// (a `.chunk`, never split across lines) or a `.gap` between words (whitespace,
/// which collapses at a wrap, or a spaced separator like an em-dash).
enum FlowRun: Identifiable {
    case chunk(id: Int, leading: String, word: TextSegment, trailing: String)
    case gap(id: Int, text: String, isWhitespace: Bool)

    var id: Int {
        switch self {
        case .chunk(let id, _, _, _): id
        case .gap(let id, _, _): id
        }
    }
}

/// Groups `Tokenizer` segments into flow runs so punctuation never wraps onto a new
/// line on its own: closing punctuation (",.;:!?)" etc.) rides with the preceding
/// word, opening punctuation ("([" etc.) with the following word, and only the
/// whitespace between them is a break opportunity. Stays lossless — concatenating
/// every run's text reproduces the input — so Copy/reword never drift.
enum FlowComposer {
    // A separator run splits at its whitespace: text before the first space hugs the
    // previous word, text after the last space hugs the next, the rest is the gap.
    // No whitespace at all (e.g. a hyphen) means no break — it hugs the previous word.
    private static func split(_ s: String) -> (closing: String, gap: String, opening: String) {
        guard let firstWS = s.firstIndex(where: \.isWhitespace),
              let lastWS = s.lastIndex(where: \.isWhitespace) else {
            return (s, "", "")
        }
        return (
            String(s[s.startIndex..<firstWS]),
            String(s[firstWS...lastWS]),
            String(s[s.index(after: lastWS)...])
        )
    }

    static func runs(_ segments: [TextSegment]) -> [FlowRun] {
        var runs: [FlowRun] = []
        let n = segments.count

        for i in 0..<n {
            let seg = segments[i]
            if seg.isWord {
                let leading = (i > 0 && !segments[i - 1].isWord) ? split(segments[i - 1].text).opening : ""
                let trailing = (i + 1 < n && !segments[i + 1].isWord) ? split(segments[i + 1].text).closing : ""
                runs.append(.chunk(id: runs.count, leading: leading, word: seg, trailing: trailing))
            } else {
                let parts = split(seg.text)
                var gap = parts.gap
                // A leading/trailing separator (no word on that side) keeps the punctuation
                // the adjacent word didn't consume, so nothing is dropped.
                if !(i > 0 && segments[i - 1].isWord) { gap = parts.closing + gap }
                if !(i + 1 < n && segments[i + 1].isWord) { gap += parts.opening }
                if !gap.isEmpty {
                    runs.append(.gap(id: runs.count, text: gap, isWhitespace: gap.allSatisfy(\.isWhitespace)))
                }
            }
        }
        return runs
    }
}

/// How a flow subview behaves at wrap points. Whitespace collapses when it would
/// land at the start of a wrapped line (no leading indent); words and punctuation
/// keep their width.
enum FlowItemKind {
    case word
    case space
    case other
}

struct FlowItemKindKey: LayoutValueKey {
    static let defaultValue: FlowItemKind = .other
}

/// A wrapping flow of inline items (macOS-native `Layout`). Reports a correct
/// `sizeThatFits` so the controller-owned window sizing (PopupView's ideal-size
/// measuring) keeps working. A `.popover`/`Menu` is deliberately NOT used for the dropdown
/// (see AlternativesDropdown) — it would force key-window status and break the
/// non-activating panel's focus model.
struct FlowLayout: Layout {
    var lineSpacing: CGFloat = 5

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        computed(maxWidth: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computed(maxWidth: bounds.width, subviews: subviews)
        for index in subviews.indices {
            let point = result.points[index]
            subviews[index].place(
                at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                anchor: .topLeading,
                proposal: ProposedViewSize(result.sizes[index])
            )
        }
    }

    private func computed(maxWidth: CGFloat, subviews: Subviews) -> (points: [CGPoint], sizes: [CGSize], size: CGSize) {
        var points: [CGPoint] = []
        var sizes: [CGSize] = []
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let kind = subview[FlowItemKindKey.self]

            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
                if kind == .space {
                    points.append(CGPoint(x: x, y: y))
                    sizes.append(.zero)
                    continue
                }
            }
            points.append(CGPoint(x: x, y: y))
            sizes.append(size)
            x += size.width
            lineHeight = max(lineHeight, size.height)
            maxX = max(maxX, x)
        }
        let width = maxWidth.isFinite ? min(maxX, maxWidth) : maxX
        return (points, sizes, CGSize(width: width, height: y + lineHeight))
    }
}

/// Per-word frames, captured via `.anchorPreference`, so the alternatives dropdown
/// can anchor itself just below the clicked word.
struct WordAnchorKey: PreferenceKey {
    static let defaultValue: [Int: Anchor<CGRect>] = [:]
    static func reduce(value: inout [Int: Anchor<CGRect>], nextValue: () -> [Int: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// The small floating list anchored under a clicked word. An in-window SwiftUI
/// overlay — NOT an NSPopover/Menu, which would force the panel to become key and
/// steal focus from the foreground app, breaking the whole non-activating model.
struct AlternativesDropdown: View {
    let model: PopupModel
    let onPick: (String) -> Void
    let onExplain: () -> Void
    let onBack: () -> Void

    static let width: CGFloat = 200
    // Safety cap for the reason height (#73): PopupView grows the window to fit the
    // measured reason, but a pathologically long one is capped here and scrolls
    // instead of growing the window past the screen. PopupView reserves the same
    // min(measured, cap), so the two stay in lockstep and nothing clips.
    static let reasonMaxHeight: CGFloat = 300

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.fixReasonMode {
                fixReasonContent
            } else if model.showingExplanation {
                explanationContent
            } else {
                alternativesContent
            }
        }
        .frame(width: Self.width, alignment: .leading)
        .background(PopupTheme.menuSurface)
        .clipShape(RoundedRectangle(cornerRadius: PopupTheme.rPane))
        .overlay(
            RoundedRectangle(cornerRadius: PopupTheme.rPane)
                .strokeBorder(PopupTheme.hairline, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
    }

    // The grammar-diff reason view (issue #51): a non-interactive header (there is
    // no alternatives list to go back to), then the spinner or the one-line Polish
    // reason for the tapped correction (or a fallback when the fetch failed).
    @ViewBuilder
    private var fixReasonContent: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 11.5, weight: .semibold))
            Text("Dlaczego poprawiono?")
                .font(PopupTheme.fontControl)
            Spacer(minLength: 0)
        }
        .foregroundStyle(PopupTheme.accent)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        Divider()
        if model.explanationLoading {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Szukam powodu…")
                    .font(PopupTheme.fontMeta)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        } else {
            ScrollView {
                Text(model.explanationText.isEmpty ? "Nie udało się pobrać powodu." : model.explanationText)
                    .font(PopupTheme.fontLead)
                    .foregroundStyle(model.explanationText.isEmpty ? Color.secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { model.fixReasonContentHeight = $0 }
            }
            .frame(height: min(model.fixReasonContentHeight, Self.reasonMaxHeight))
        }
    }

    // The learner-facing "Dlaczego tak?" view (issue #39): a back row, then the
    // spinner or the one-line explanation (or a fallback when the fetch failed).
    @ViewBuilder
    private var explanationContent: some View {
        Button(action: onBack) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11.5, weight: .semibold))
                Text("Dlaczego tak?")
                    .font(PopupTheme.fontControl)
                Spacer(minLength: 0)
            }
            .foregroundStyle(PopupTheme.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        Divider()
        if model.explanationLoading {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Szukam wyjaśnienia…")
                    .font(PopupTheme.fontMeta)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        } else {
            Text(model.explanationText.isEmpty ? "Nie udało się pobrać wyjaśnienia." : model.explanationText)
                .font(PopupTheme.fontLead)
                .foregroundStyle(model.explanationText.isEmpty ? Color.secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
        }
    }

    @ViewBuilder
    private var alternativesContent: some View {
        // Always offered (it explains the word, not the list), so it sits above
        // whatever state the alternatives fetch is in.
        Button(action: onExplain) {
            HStack(spacing: 6) {
                Image(systemName: "lightbulb")
                    .font(.system(size: 11.5, weight: .semibold))
                Text("Dlaczego tak?")
                    .font(PopupTheme.fontControl)
                Spacer(minLength: 0)
            }
            .foregroundStyle(PopupTheme.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        Divider()
        if model.altsLoading {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Szukam alternatyw…")
                    .font(PopupTheme.fontMeta)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        } else if model.alternatives.isEmpty {
            Text("Brak alternatyw")
                .font(PopupTheme.fontMeta)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
        } else {
            ForEach(Array(model.alternatives.enumerated()), id: \.offset) { _, alternative in
                AlternativeRow(text: alternative) { onPick(alternative) }
            }
        }
    }
}

private struct AlternativeRow: View {
    let text: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(PopupTheme.fontLead)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(hovering ? PopupTheme.accentTintStrong : .clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
