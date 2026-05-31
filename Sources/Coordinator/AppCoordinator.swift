import Foundation
import AppKit

@MainActor
final class AppCoordinator {
    private let llm: any LLMClient
    private let monitor: any HotkeyMonitor
    private let reader: any PasteboardReading
    private let popup: any TranslationPopupPresenting
    private let ax: any AccessibilityAuthorizing

    private var streamTask: Task<Void, Never>?

    init(
        llm: any LLMClient,
        monitor: any HotkeyMonitor,
        reader: any PasteboardReading,
        popup: any TranslationPopupPresenting,
        ax: any AccessibilityAuthorizing
    ) {
        self.llm = llm
        self.monitor = monitor
        self.reader = reader
        self.popup = popup
        self.ax = ax
    }

    func start() {
        Task { try? await llm.prewarm() }
        monitor.onDoubleCopy = { [weak self] in self?.handleDoubleCopy() }
        try? monitor.start()
        popup.onDismiss = { [weak self] in self?.streamTask?.cancel() }
    }

    func handleDoubleCopy() {
        let baseline = reader.currentChangeCount
        let text: String
        do {
            text = try reader.readSelection(baselineChangeCount: baseline - 1)
        } catch {
            popup.present(direction: .unknown, at: NSEvent.mouseLocation)
            popup.showError((error as? CaptureError) == .nothingSelected
                ? CaptureError.nothingSelected.localizedFallback
                : "Brak tekstu do tłumaczenia.")
            return
        }
        translate(text)
    }

    func translate(_ text: String) {
        streamTask?.cancel()
        popup.present(direction: .unknown, at: NSEvent.mouseLocation)
        streamTask = Task { @MainActor in
            do {
                for try await event in llm.translate(text) {
                    switch event {
                    case .token(let token): popup.append(token: token)
                    case .finished: popup.finish()
                    }
                }
            } catch let error as TranslationError {
                popup.showError(error.userMessage)
            } catch {
                popup.showError("Błąd tłumaczenia.")
            }
        }
    }
}

private extension CaptureError {
    var localizedFallback: String { "Nic nie zaznaczono." }
}
