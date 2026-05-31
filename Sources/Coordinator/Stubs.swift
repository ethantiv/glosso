import Foundation
import AppKit
import SwiftUI

// Tymczasowe atrapy dla Fazy 0 (walking skeleton). W Fazie 2 zastępujemy je
// prawdziwymi implementacjami z modułów i USUWAMY ten plik.

struct StubLLMClient: LLMClient {
    func translate(_ text: String) -> AsyncThrowingStream<TranslationEvent, Error> {
        AsyncThrowingStream { continuation in
            for character in "[demo] " + text {
                continuation.yield(.token(String(character)))
            }
            continuation.yield(.finished(doneReason: "stub"))
            continuation.finish()
        }
    }

    func prewarm() async throws {}
}

@MainActor
final class StubHotkeyMonitor: HotkeyMonitor {
    var onDoubleCopy: (@MainActor () -> Void)?
    func start() throws {}
    func stop() {}
}

@MainActor
final class StubPasteboardReader: PasteboardReading {
    var currentChangeCount: Int { 1 }
    func readSelection(baselineChangeCount: Int) throws -> String { "Cześć, świecie" }
}

@MainActor
final class StubAccessibilityAuthorizer: AccessibilityAuthorizing {
    var isTrusted: Bool { true }
    func requestAccess(prompt: Bool) {}
    func openSystemSettings() {}
}

@MainActor
final class StubPopupModel: ObservableObject {
    @Published var header: String = ""
    @Published var text: String = ""
}

@MainActor
final class StubPopupPresenter: TranslationPopupPresenting {
    var onDismiss: (@MainActor () -> Void)?
    private var panel: NSPanel?
    private let model = StubPopupModel()

    func present(direction: TranslationDirection, at screenPoint: CGPoint) {
        model.header = direction.label
        model.text = ""
        let host = NSHostingController(rootView: StubPopupView(model: model))
        let panel = NSPanel(contentViewController: host)
        panel.styleMask = [.nonactivatingPanel, .titled, .closable]
        panel.title = "Translator (demo)"
        panel.level = .floating
        panel.setContentSize(NSSize(width: 340, height: 160))
        panel.setFrameTopLeftPoint(NSPoint(x: screenPoint.x, y: screenPoint.y))
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func append(token: String) { model.text += token }
    func showError(_ message: String) { model.text = "⚠️ " + message }
    func finish() {}

    func dismiss() {
        panel?.close()
        panel = nil
        onDismiss?()
    }
}

private struct StubPopupView: View {
    @ObservedObject var model: StubPopupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.header)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(model.text)
                .font(.body)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
