import Foundation
import AppKit

@MainActor
final class AppCoordinator {
    private let llm: any LLMClient
    private let monitor: any HotkeyMonitor
    private let reader: any PasteboardReading
    private let axReader: any AXSelectionReading
    private let popup: any TranslationPopupPresenting
    private let replacer: any SelectionReplacing
    private let settings: SettingsStore

    private let pollStepMs: Int
    private let pollMaxAttempts: Int
    private let frontmostPID: @MainActor () -> pid_t?

    private var captureTask: Task<Void, Never>?

    // Retained so the popup's tone pill can re-translate the same selection with a
    // different formality, without the user copying again. nil until a capture lands;
    // text and point are one unit so a new capture can't half-reset them.
    private var lastCapture: (text: String, point: CGPoint)?

    // The frontmost app's PID at the double-press, retained so Replace can verify
    // the source app hasn't changed before pasting back into it (issue #22).
    private var lastSourcePID: pid_t?

    init(
        llm: any LLMClient,
        monitor: any HotkeyMonitor,
        reader: any PasteboardReading,
        axReader: any AXSelectionReading,
        popup: any TranslationPopupPresenting,
        settings: SettingsStore,
        replacer: any SelectionReplacing = SystemSelectionReplacer(),
        pollStepMs: Int = 12,
        pollMaxAttempts: Int = 40,
        frontmostPID: @escaping @MainActor () -> pid_t? = { NSWorkspace.shared.frontmostApplication?.processIdentifier }
    ) {
        self.llm = llm
        self.monitor = monitor
        self.reader = reader
        self.axReader = axReader
        self.popup = popup
        self.replacer = replacer
        self.settings = settings
        self.pollStepMs = pollStepMs
        self.pollMaxAttempts = pollMaxAttempts
        self.frontmostPID = frontmostPID
    }

    /// Starts pre-warm and the hotkey monitor. Returns whether the monitor
    /// actually started (it throws when Accessibility is not granted).
    @discardableResult
    func start() -> Bool {
        Task { try? await llm.prewarm(model: settings.modelName) }

        monitor.onDoubleCopy = { [weak self] baseline in self?.handleDoubleCopy(baseline: baseline) }
        popup.onDismiss = { [weak self] in self?.captureTask?.cancel() }
        popup.onSelectFormality = { [weak self] formality in self?.handleFormalityChange(formality) }
        popup.onFetchAlternatives = { [weak self] word, translation in
            await self?.fetchAlternatives(word: word, translation: translation) ?? []
        }
        popup.onPickAlternative = { [weak self] original, chosen, translation in
            self?.handlePickAlternative(original: original, chosen: chosen, translation: translation)
        }
        popup.onReplace = { [weak self] translation in self?.handleReplace(translation: translation) }

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
        // The popup's Esc dismisser is an AX-gated global monitor too, so an AX
        // revocation silences it — dismiss it here or a popup mid-translation
        // orphans on screen with a stuck spinner.
        popup.dismiss()
    }

    func handleDoubleCopy(baseline: Int) {
        let mouse = NSEvent.mouseLocation
        let source = frontmostPID()
        captureTask?.cancel()
        // Tear the previous popup down now so its monitors can't fire onDismiss
        // and cancel the new captureTask before it gets to present its own popup.
        popup.dismiss()
        captureTask = Task { @MainActor [weak self] in
            await self?.captureAndTranslate(baseline: baseline, at: mouse, sourcePID: source)
        }
    }

    /// Polls the pasteboard until the second Cmd+C's copy lands (changeCount
    /// rises above the baseline), then streams the translation. The second
    /// Cmd+C only *triggers* the copy, so the new text is not present yet at
    /// the instant the double-press is detected.
    func captureAndTranslate(baseline: Int, at point: CGPoint, sourcePID: pid_t? = nil) async {
        // Show the popup (skeleton state) the instant the double-press fires, before
        // the clipboard poll and the model's first token, so there is immediate
        // feedback; the source text and direction fill in via update() once captured.
        // A rapid third press can cancel this task before it runs, so bail before
        // presenting rather than orphaning a popup the newer task already replaced.
        if Task.isCancelled { return }
        lastCapture = nil
        lastSourcePID = sourcePID
        popup.present(at: point, formality: settings.formality)
        for _ in 0..<pollMaxAttempts {
            if Task.isCancelled { return }
            do {
                let text = try reader.readSelection(baselineChangeCount: baseline)
                if Task.isCancelled { return }
                await stream(text, at: point)
                return
            } catch CaptureError.emptyOrNonText {
                popup.showError("Zaznaczenie nie zawiera tekstu do tłumaczenia.")
                return
            } catch CaptureError.nothingSelected {
                // clipboard has not updated yet — keep polling.
            } catch {
                // An unexpected reader error (a future permissions/coordination
                // failure, say) must not be silently polled away — surface it.
                popup.showError("Nie udało się pobrać zaznaczenia. Spróbuj ponownie.")
                return
            }
            try? await Task.sleep(for: .milliseconds(pollStepMs))
        }
        if Task.isCancelled { return }
        // The changeCount never rose within the budget: the app didn't copy on
        // Cmd+C (some apps, notably Safari/WebKit, do this inconsistently). Fall
        // back to reading the focused element's selection directly via the
        // Accessibility API, which doesn't depend on the pasteboard at all.
        // But the AX read resolves whatever is focused *now* — ~480ms after the
        // press — so if the user switched apps (Cmd+Tab) within the poll window
        // we'd read and translate a different app's selection. Bail in that case
        // rather than touching the wrong app's focus.
        if let sourcePID, sourcePID != frontmostPID() {
            popup.showError("Nie udało się pobrać zaznaczenia. Spróbuj ponownie.")
            return
        }
        if let axText = try? SelectionGuard.nonEmptyText(axReader.selectedText()) {
            if Task.isCancelled { return }
            await stream(axText, at: point)
            return
        }
        popup.showError("Nie udało się pobrać zaznaczenia. Spróbuj ponownie.")
    }

    /// Pastes the finished translation over the still-live source selection (issue
    /// #22). Mirrors the AX-fallback guard: if the frontmost app changed since the
    /// double-press, refuse rather than paste into the wrong app.
    func handleReplace(translation: String) {
        guard let sourcePID = lastSourcePID, sourcePID == frontmostPID() else {
            popup.showError("Aplikacja źródłowa się zmieniła — nie wklejono.")
            return
        }
        // The PID match only proves the source app is still frontmost, not that its
        // selection is still live: clicking back into the source while the
        // translation streamed collapses it to an insertion point, and a synthesized
        // Cmd+V would then *insert* the translation at the cursor instead of replacing.
        // A non-nil but empty AXSelectedText is positive proof the selection
        // collapsed; nil means AX exposes no selection at all (Electron/Chromium),
        // where Cmd+V still works — so only an empty, non-nil read blocks the paste.
        if let selection = axReader.selectedText(),
           selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            popup.showError("Brak zaznaczenia do zastąpienia.")
            return
        }
        replacer.replace(with: translation)
        popup.dismiss()
    }

    func handleFormalityChange(_ formality: Formality) {
        settings.formality = formality
        guard let capture = lastCapture else { return }
        captureTask?.cancel()
        popup.restartTranslation()
        captureTask = Task { @MainActor [weak self] in
            await self?.stream(capture.text, at: capture.point)
        }
    }

    /// Asks the model for alternatives of a clicked word in the finished
    /// translation (issue #17). The clicked word and current translation come from
    /// the popup; the source is the last captured selection. Any failure (or no
    /// alternatives) collapses to an empty list — the dropdown shows "no alternatives".
    func fetchAlternatives(word: String, translation: String) async -> [String] {
        guard let capture = lastCapture else { return [] }
        return (try? await llm.alternatives(
            for: word, in: translation, source: capture.text,
            second: settings.secondLanguage, model: settings.modelName)) ?? []
    }

    /// The user picked an alternative: re-translate the clause with that word in
    /// place and stream the revised result into the same pane — mirroring the
    /// formality-change re-translation path.
    func handlePickAlternative(original: String, chosen: String, translation: String) {
        guard lastCapture != nil else { return }
        captureTask?.cancel()
        popup.restartTranslation()
        captureTask = Task { @MainActor [weak self] in
            await self?.streamReword(original: original, chosen: chosen, translation: translation)
        }
    }

    private func stream(_ text: String, at point: CGPoint) async {
        lastCapture = (text, point)
        let second = settings.secondLanguage
        popup.update(direction: DirectionDetector.detect(text, second: second), sourceText: text)
        await consume(llm.translate(text, model: settings.modelName, second: second, formality: settings.formality))
    }

    // Keeps the existing direction/source in place (only the result pane was reset
    // by restartTranslation); streams the reworded translation into it.
    private func streamReword(original: String, chosen: String, translation: String) async {
        guard let capture = lastCapture else { return }
        await consume(llm.reword(
            original: original, to: chosen, in: translation,
            source: capture.text, second: settings.secondLanguage,
            formality: settings.formality, model: settings.modelName))
    }

    private func consume(_ stream: AsyncThrowingStream<TranslationEvent, Error>) async {
        do {
            for try await event in stream {
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
}
