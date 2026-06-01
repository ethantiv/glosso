import Foundation
import AppKit

@MainActor
final class AppCoordinator {
    private let llm: any LLMClient
    private let monitor: any HotkeyMonitor
    private let reader: any PasteboardReading
    private let popup: any TranslationPopupPresenting

    private let pollStepMs: Int
    private let pollMaxAttempts: Int

    private var captureTask: Task<Void, Never>?

    init(
        llm: any LLMClient,
        monitor: any HotkeyMonitor,
        reader: any PasteboardReading,
        popup: any TranslationPopupPresenting,
        pollStepMs: Int = 12,
        pollMaxAttempts: Int = 20
    ) {
        self.llm = llm
        self.monitor = monitor
        self.reader = reader
        self.popup = popup
        self.pollStepMs = pollStepMs
        self.pollMaxAttempts = pollMaxAttempts
    }

    /// Starts pre-warm and the hotkey monitor. Returns whether the monitor
    /// actually started (it throws when Accessibility is not granted).
    @discardableResult
    func start() -> Bool {
        Task { try? await llm.prewarm() }

        monitor.onDoubleCopy = { [weak self] in self?.handleDoubleCopy() }
        popup.onDismiss = { [weak self] in self?.captureTask?.cancel() }

        do {
            try monitor.start()
            return true
        } catch {
            return false
        }
    }

    /// Stops the hotkey monitor and cancels any in-flight capture. Used when
    /// Accessibility is revoked at runtime so the app stops claiming it listens.
    func stop() {
        monitor.stop()
        captureTask?.cancel()
    }

    func handleDoubleCopy() {
        let mouse = NSEvent.mouseLocation
        let baseline = reader.currentChangeCount
        captureTask?.cancel()
        // Tear the previous popup down now so its monitors can't fire onDismiss
        // and cancel the new captureTask before it gets to present its own popup.
        popup.dismiss()
        captureTask = Task { @MainActor [weak self] in
            await self?.captureAndTranslate(baseline: baseline, at: mouse)
        }
    }

    /// Polls the pasteboard until the second Cmd+C's copy lands (changeCount
    /// rises above the baseline), then streams the translation. The second
    /// Cmd+C only *triggers* the copy, so the new text is not present yet at
    /// the instant the double-press is detected.
    func captureAndTranslate(baseline: Int, at point: CGPoint) async {
        for _ in 0..<pollMaxAttempts {
            if Task.isCancelled { return }
            do {
                let text = try reader.readSelection(baselineChangeCount: baseline)
                if Task.isCancelled { return }
                await stream(text, at: point)
                return
            } catch CaptureError.emptyOrNonText {
                present(error: "Zaznaczenie nie zawiera tekstu do tłumaczenia.", at: point)
                return
            } catch {
                // .nothingSelected: clipboard has not updated yet — keep polling.
            }
            try? await Task.sleep(for: .milliseconds(pollStepMs))
        }
        if Task.isCancelled { return }
        present(error: "Nic nie zaznaczono do tłumaczenia.", at: point)
    }

    private func stream(_ text: String, at point: CGPoint) async {
        popup.present(direction: DirectionDetector.detect(text), at: point)
        do {
            for try await event in llm.translate(text) {
                if Task.isCancelled { return }
                switch event {
                case .token(let token): popup.append(token: token)
                case .finished: popup.finish()
                }
            }
        } catch let error as TranslationError {
            if error == .cancelled { return }
            popup.showError(error.userMessage)
        } catch {
            if Task.isCancelled { return }
            popup.showError("Błąd tłumaczenia.")
        }
    }

    private func present(error message: String, at point: CGPoint) {
        popup.present(direction: .unknown, at: point)
        popup.showError(message)
    }
}
