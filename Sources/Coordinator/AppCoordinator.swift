import Foundation
import AppKit

@MainActor
final class AppCoordinator {
    private let llm: any LLMClient
    private let monitor: any HotkeyMonitor
    private let reader: any PasteboardReading
    private let axReader: any AXSelectionReading
    private let popup: any TranslationPopupPresenting
    private let settings: SettingsStore

    private let pollStepMs: Int
    private let pollMaxAttempts: Int

    private var captureTask: Task<Void, Never>?

    init(
        llm: any LLMClient,
        monitor: any HotkeyMonitor,
        reader: any PasteboardReading,
        axReader: any AXSelectionReading,
        popup: any TranslationPopupPresenting,
        settings: SettingsStore,
        pollStepMs: Int = 12,
        pollMaxAttempts: Int = 40
    ) {
        self.llm = llm
        self.monitor = monitor
        self.reader = reader
        self.axReader = axReader
        self.popup = popup
        self.settings = settings
        self.pollStepMs = pollStepMs
        self.pollMaxAttempts = pollMaxAttempts
    }

    /// Starts pre-warm and the hotkey monitor. Returns whether the monitor
    /// actually started (it throws when Accessibility is not granted).
    @discardableResult
    func start() -> Bool {
        Task { try? await llm.prewarm(model: settings.modelName) }

        monitor.onDoubleCopy = { [weak self] baseline in self?.handleDoubleCopy(baseline: baseline) }
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
        // The popup's Esc/outside-click dismissers are AX-gated global monitors
        // too, so an AX revocation silences them — dismiss it here or a popup
        // mid-translation orphans on screen with a stuck spinner.
        popup.dismiss()
    }

    func handleDoubleCopy(baseline: Int) {
        let mouse = NSEvent.mouseLocation
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
            } catch CaptureError.nothingSelected {
                // clipboard has not updated yet — keep polling.
            } catch {
                // An unexpected reader error (a future permissions/coordination
                // failure, say) must not be silently polled away — surface it.
                present(error: "Nie udało się pobrać zaznaczenia. Spróbuj ponownie.", at: point)
                return
            }
            try? await Task.sleep(for: .milliseconds(pollStepMs))
        }
        if Task.isCancelled { return }
        // The changeCount never rose within the budget: the app didn't copy on
        // Cmd+C (some apps, notably Safari/WebKit, do this inconsistently). Fall
        // back to reading the focused element's selection directly via the
        // Accessibility API, which doesn't depend on the pasteboard at all.
        if let axText = try? SelectionGuard.nonEmptyText(axReader.selectedText()) {
            if Task.isCancelled { return }
            await stream(axText, at: point)
            return
        }
        present(error: "Nie udało się pobrać zaznaczenia. Spróbuj ponownie.", at: point)
    }

    private func stream(_ text: String, at point: CGPoint) async {
        let second = settings.secondLanguage
        popup.present(direction: DirectionDetector.detect(text, second: second), at: point)
        do {
            for try await event in llm.translate(text, model: settings.modelName, second: second) {
                if Task.isCancelled { return }
                switch event {
                case .token(let token):
                    popup.append(token: token)
                case .finished(let reason):
                    // done_reason "length" means the model hit its token ceiling
                    // and the tail was dropped. Keep the partial text visible and
                    // copyable, but mark it truncated so the popup warns instead
                    // of presenting a silently cut-off translation as complete.
                    popup.finish(truncated: reason == "length")
                }
            }
        } catch let error as TranslationError {
            // A cancel from our own captureTask leaves popup teardown to the
            // caller (handleDoubleCopy/stop/onDismiss). A cancel from elsewhere
            // — URLSession suspending, reachability transitions — must still
            // surface, or the popup orphans in .streaming with a stuck spinner.
            if Task.isCancelled { return }
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
