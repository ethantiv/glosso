import AppKit
import SwiftUI

struct PopupView: View {
    let model: PopupModel
    let close: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var copied = false
    @State private var appeared = false

    private static let sourceWidth: CGFloat = 268
    private static let translationWidth: CGFloat = 300
    private static let maxPaneHeight: CGFloat = 400

    private var canCopy: Bool { model.phase == .done && !model.text.isEmpty }
    private var showLiveDot: Bool { model.phase == .capturing || model.phase == .streaming }
    private var showAccentEdge: Bool { model.phase == .streaming || model.phase == .done }

    var body: some View {
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

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            languagePair
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
            if canCopy {
                Button(action: copy) {
                    iconLabel(copied ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                        .foregroundStyle(copied ? PopupTheme.copied : Color.secondary)
                }
                .buttonStyle(IconButtonStyle())
                .help("Kopiuj tłumaczenie")
                .animation(reduceMotion ? nil : .easeOut(duration: PopupTheme.durFast), value: copied)
            }
            Button(action: close) {
                iconLabel("xmark")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(IconButtonStyle())
            .help("Zamknij")
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
                .frame(maxHeight: Self.maxPaneHeight)
                .scrollBounceBehavior(.basedOnSize)
            } else if model.phase == .capturing {
                // Only shimmer while we are still waiting for the selection; an
                // error before capture leaves sourceText empty, and a skeleton
                // there would imply the original is still loading forever.
                SkeletonView()
            }
        }
        .padding(PopupTheme.padPane)
        .frame(width: Self.sourceWidth, alignment: .leading)
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
        .frame(width: Self.translationWidth, alignment: .leading)
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
                Text(model.text)
                    .font(PopupTheme.fontLead)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: Self.maxPaneHeight)
            .scrollBounceBehavior(.basedOnSize)
        }
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
