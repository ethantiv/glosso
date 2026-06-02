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
/// `sizeThatFits` so the panel's `preferredContentSize` sizing and top-left re-pin
/// keep working. A `.popover`/`Menu` is deliberately NOT used for the dropdown
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

    static let width: CGFloat = 200

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
        .frame(width: Self.width, alignment: .leading)
        .background(VisualEffectBackground(material: .popover))
        .clipShape(RoundedRectangle(cornerRadius: PopupTheme.rPane))
        .overlay(
            RoundedRectangle(cornerRadius: PopupTheme.rPane)
                .strokeBorder(PopupTheme.hairline, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
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
