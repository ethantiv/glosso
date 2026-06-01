import AppKit
import SwiftUI

struct PopupView: View {
    let model: PopupModel

    private static let paneWidth: CGFloat = 280
    private static let maxPaneHeight: CGFloat = 400
    private static let bottomAnchorID = "bottom"

    private var canCopy: Bool { model.phase == .done && !model.text.isEmpty }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            sourcePane
            Divider()
            translationPane
        }
    }

    private var sourcePane: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Oryginał")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            ScrollView {
                Text(model.sourceText)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: Self.maxPaneHeight)
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(14)
        .frame(width: Self.paneWidth, alignment: .leading)
    }

    private var translationPane: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Tłumaczenie")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                if model.phase == .streaming {
                    ProgressView()
                        .controlSize(.mini)
                }
                Spacer(minLength: 0)
                if canCopy {
                    Button {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(model.text, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("Kopiuj tłumaczenie")
                }
            }

            content
        }
        .padding(14)
        .frame(width: Self.paneWidth, alignment: .leading)
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .error:
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text(model.errorMessage ?? "Translation failed")
                    .font(.body)
                    .foregroundStyle(.primary)
            }
        case .streaming, .done:
            VStack(alignment: .leading, spacing: 6) {
                // ScrollViewReader keeps the text top-aligned (so a short
                // translation isn't pushed to the bottom of a stretched pane) while
                // still following the newest tokens once the text exceeds the cap:
                // scrollTo only moves when there is something to scroll.
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(model.text)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Color.clear
                            .frame(height: 1)
                            .id(Self.bottomAnchorID)
                    }
                    .frame(maxHeight: Self.maxPaneHeight)
                    .scrollBounceBehavior(.basedOnSize)
                    .onChange(of: model.text) {
                        proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
                    }
                }

                if model.truncated {
                    Label("Tłumaczenie obcięte (limit modelu). Skróć zaznaczenie.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
