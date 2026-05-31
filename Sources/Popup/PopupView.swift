import AppKit
import SwiftUI

struct PopupView: View {
    let model: PopupModel

    private var canCopy: Bool { model.phase == .done && !model.text.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(model.direction.label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                if model.phase == .streaming {
                    ProgressView()
                        .controlSize(.mini)
                }
                Spacer(minLength: 0)
            }

            content
        }
        .padding(14)
        .frame(maxWidth: 360, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture {
            guard canCopy else { return }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(model.text, forType: .string)
        }
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
            Text(model.text)
                .font(.body)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
