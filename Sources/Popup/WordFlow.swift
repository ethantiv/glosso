import SwiftUI

struct TextSegment: Identifiable, Hashable {
    let id: Int
    let text: String
    let isWord: Bool
    let isWhitespace: Bool
}

enum Tokenizer {
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

enum FlowComposer {
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

enum FlowItemKind {
    case word
    case space
    case other
}

struct FlowItemKindKey: LayoutValueKey {
    static let defaultValue: FlowItemKind = .other
}

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

struct WordAnchorKey: PreferenceKey {
    static let defaultValue: [Int: Anchor<CGRect>] = [:]
    static func reduce(value: inout [Int: Anchor<CGRect>], nextValue: () -> [Int: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct AlternativesDropdown: View {
    let model: PopupModel
    let onPick: (String) -> Void
    let onExplain: () -> Void
    let onBack: () -> Void

    static let width: CGFloat = 200

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
        // Opaque, not glass: this overlay protrudes past the panel, so half of it would sample the glass card and half
        // the desktop — one popover, two materials, split by a line. A menu is opaque on macOS anyway.
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: PopupTheme.rPane))
        .overlay(
            RoundedRectangle(cornerRadius: PopupTheme.rPane)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
    }

    @ViewBuilder
    private var fixReasonContent: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 11.5, weight: .semibold))
            Text(loc("Dlaczego poprawiono?", "Why was this corrected?"))
                .font(PopupTheme.fontControl)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.tint)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        Divider()
        if model.explanationLoading {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(loc("Szukam powodu…", "Finding the reason…"))
                    .font(PopupTheme.fontMeta)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        } else {
            ScrollView {
                Text(model.explanationText.isEmpty ? loc("Nie udało się pobrać powodu.", "Couldn't fetch the reason.") : model.explanationText)
                    .font(PopupTheme.fontLead)
                    .foregroundStyle(model.explanationText.isEmpty ? Color.secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { model.fixReasonContentHeight = $0 }
            }
            .frame(height: FixReasonLayout.reasonPaneHeight(content: model.fixReasonContentHeight))
        }
    }

    @ViewBuilder
    private var explanationContent: some View {
        Button(action: onBack) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11.5, weight: .semibold))
                Text(loc("Dlaczego tak?", "Why this?"))
                    .font(PopupTheme.fontControl)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        Divider()
        if model.explanationLoading {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(loc("Szukam wyjaśnienia…", "Finding an explanation…"))
                    .font(PopupTheme.fontMeta)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        } else {
            Text(model.explanationText.isEmpty ? loc("Nie udało się pobrać wyjaśnienia.", "Couldn't fetch the explanation.") : model.explanationText)
                .font(PopupTheme.fontLead)
                .foregroundStyle(model.explanationText.isEmpty ? Color.secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { model.explanationContentHeight = $0 }
        }
    }

    @ViewBuilder
    private var alternativesContent: some View {
        Button(action: onExplain) {
            HStack(spacing: 6) {
                Image(systemName: "lightbulb")
                    .font(.system(size: 11.5, weight: .semibold))
                Text(loc("Dlaczego tak?", "Why this?"))
                    .font(PopupTheme.fontControl)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        Divider()
        if model.altsLoading {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(loc("Szukam alternatyw…", "Finding alternatives…"))
                    .font(PopupTheme.fontMeta)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        } else if model.alternatives.isEmpty {
            Text(loc("Brak alternatyw", "No alternatives"))
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
                .background(hovering ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
