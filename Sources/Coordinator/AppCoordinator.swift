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
    private let notify: @MainActor (String) -> Void

    private var captureTask: Task<Void, Never>?
    private var fixTask: Task<Void, Never>?

    // Retained so the popup's tone pill and verb strip can re-run over the same
    // selection without the user copying again. nil until a capture lands; text,
    // point and action are one unit so a new capture can't half-reset them. The
    // action starts at .translate and changes when the user picks another verb
    // (issue #23); a fresh capture always resets it back to .translate.
    private var lastCapture: (text: String, point: CGPoint, action: Action)?

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
        frontmostPID: @escaping @MainActor () -> pid_t? = { NSWorkspace.shared.frontmostApplication?.processIdentifier },
        notify: @escaping @MainActor (String) -> Void = { SystemUserNotifier.post($0) }
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
        self.notify = notify
    }

    /// Starts pre-warm and the hotkey monitor. Returns whether the monitor
    /// actually started (it throws when Accessibility is not granted).
    @discardableResult
    func start() -> Bool {
        Task { try? await llm.prewarm(model: settings.modelName) }

        monitor.onDoubleCopy = { [weak self] baseline in self?.handleDoubleCopy(baseline: baseline) }
        monitor.onFixGrammar = { [weak self] in self?.handleFixGrammar() }
        monitor.onTranslateInPlace = { [weak self] in self?.handleTranslateInPlace() }
        popup.onDismiss = { [weak self] in self?.captureTask?.cancel() }
        popup.onSelectFormality = { [weak self] formality in self?.handleFormalityChange(formality) }
        popup.onSelectAction = { [weak self] action in self?.handleActionChange(action) }
        popup.onFetchAlternatives = { [weak self] word, translation in
            await self?.fetchAlternatives(word: word, translation: translation) ?? []
        }
        popup.onPickAlternative = { [weak self] original, chosen, translation in
            self?.handlePickAlternative(original: original, chosen: chosen, translation: translation)
        }
        popup.onFetchExplanation = { [weak self] word, translation in
            await self?.fetchExplanation(word: word, translation: translation) ?? ""
        }
        popup.onFetchFixReason = { [weak self] before, after, corrected in
            await self?.fetchFixReason(before: before, after: after, corrected: corrected) ?? ""
        }
        popup.onReplace = { [weak self] translation in self?.handleReplace(translation: translation) }
        popup.onRetranslate = { [weak self] source in self?.handleSourceEdit(source) }

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
        fixTask?.cancel()
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
                await stream(text, at: point, action: .translate)
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
            await stream(axText, at: point, action: .translate)
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

    /// Headless "just fix it" path (issue #46): the dedicated chord fires this with
    /// no popup at all. Snapshot the source app's PID up front so a late paste can't
    /// land in a different app the user switched to while the model streamed.
    func handleFixGrammar() {
        let source = frontmostPID()
        fixTask?.cancel()
        fixTask = Task { @MainActor [weak self] in await self?.fixGrammarInPlace(sourcePID: source) }
    }

    /// Headless "translate in place" chord (issue #21): the silent twin of the
    /// popup's Replace button — translate the selection and paste it back, no popup.
    /// Reuses the same in-place pipeline with `action: .translate`.
    func handleTranslateInPlace() {
        let source = frontmostPID()
        fixTask?.cancel()
        fixTask = Task { @MainActor [weak self] in await self?.fixGrammarInPlace(sourcePID: source, action: .translate) }
    }

    /// Reads the focused element's selection via AX (no copy — the chord doesn't
    /// trigger one), runs `fixGrammar` silently into a buffer, then pastes the
    /// corrected text over the selection. On a missing selection or an app switch
    /// mid-stream it notifies instead of pasting; a successful fix is its own
    /// confirmation (the text changes in place).
    func fixGrammarInPlace(sourcePID: pid_t?, action: Action = .fixGrammar) async {
        let isTranslate = action == .translate
        // AX is the fast path (no clipboard touch). Terminals and some web/Electron
        // fields expose no AXSelectedText for reading, so fall back to firing the
        // app's own Cmd+C and reading the pasteboard, restoring the clipboard around it.
        var captured = try? SelectionGuard.nonEmptyText(axReader.selectedText())
        // A successful AX read proves the selection is a real, editable one that
        // Cmd+V will overwrite. When AX reads nothing we copy via Cmd+C instead, but
        // then the selection's replaceability is unknown — in terminals it's a mere
        // mouse highlight the shell won't replace, so a paste would append. Remember
        // that so we hand the result back via the clipboard rather than risk it.
        let usedFallback = captured == nil
        if captured == nil {
            captured = try? SelectionGuard.nonEmptyText(await captureViaSyntheticCopy())
        }
        if Task.isCancelled { return }
        guard let text = captured else {
            notify(isTranslate
                ? "Nie udało się odczytać zaznaczenia do tłumaczenia."
                : "Nie udało się odczytać zaznaczenia do poprawy.")
            return
        }
        var buffer = ""
        do {
            for try await event in llm.run(
                text, action: action, model: settings.modelName,
                second: settings.secondLanguage, formality: settings.formality,
                humanize: settings.humanize) {
                if Task.isCancelled { return }
                if case .token(let token) = event { buffer += token }
            }
        } catch {
            if Task.isCancelled { return }
            notify(isTranslate ? "Nie udało się przetłumaczyć tekstu." : "Nie udało się poprawić tekstu.")
            return
        }
        if Task.isCancelled { return }
        let corrected = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !corrected.isEmpty else { return }
        guard !usedFallback else {
            copyToClipboard(corrected)
            notify(isTranslate
                ? "Przetłumaczono. To zaznaczenie nie pozwala wkleić w miejscu — tłumaczenie jest w schowku (Cmd+V)."
                : "Poprawiono. To zaznaczenie nie pozwala wkleić w miejscu — poprawka jest w schowku (Cmd+V).")
            return
        }
        // ponytail: best-effort paste; no read-only detection — add an AX writability probe if it bites
        guard let sourcePID, sourcePID == frontmostPID() else {
            copyToClipboard(corrected)
            notify(isTranslate
                ? "Aplikacja się zmieniła — tłumaczenie skopiowano do schowka."
                : "Aplikacja się zmieniła — poprawiony tekst skopiowano do schowka.")
            return
        }
        // The selection can collapse to an insertion point while the model streams
        // (a click back into the source); a non-nil but empty AXSelectedText proves
        // it, and Cmd+V would then *insert* the correction at the cursor instead of
        // replacing. Mirror handleReplace: hand it back via the clipboard, don't paste.
        if let selection = axReader.selectedText(),
           selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            copyToClipboard(corrected)
            notify(isTranslate
                ? "Zaznaczenie zniknęło — tłumaczenie skopiowano do schowka."
                : "Zaznaczenie zniknęło — poprawiony tekst skopiowano do schowka.")
            return
        }
        replacer.replace(with: corrected)
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// AX-nil fallback for fix-grammar (issue #46): preserve the user's clipboard,
    /// fire the app's Cmd+C, poll the pasteboard until the copy lands, then restore
    /// the clipboard so the subsequent replace() sees the user's original — not the
    /// copied selection — to save and put back after pasting.
    private func captureViaSyntheticCopy() async -> String? {
        let pasteboard = NSPasteboard.general
        let original = pasteboard.string(forType: .string)
        let baseline = reader.currentChangeCount
        replacer.synthesizeCopy()
        var captured: String?
        for _ in 0..<pollMaxAttempts {
            if Task.isCancelled { break }
            if let text = try? reader.readSelection(baselineChangeCount: baseline) {
                captured = text
                break
            }
            try? await Task.sleep(for: .milliseconds(pollStepMs))
        }
        pasteboard.clearContents()
        if let original { pasteboard.setString(original, forType: .string) }
        return captured
    }

    func handleFormalityChange(_ formality: Formality) {
        settings.formality = formality
        guard let capture = lastCapture else { return }
        captureTask?.cancel()
        popup.restartTranslation()
        captureTask = Task { @MainActor [weak self] in
            await self?.stream(capture.text, at: capture.point, action: capture.action)
        }
    }

    /// The user picked a verb in the palette strip (issue #23): re-run that action
    /// over the same captured selection and stream into the same pane. Mirrors the
    /// formality-change path; the action is not persisted, so a fresh capture
    /// resets it back to .translate.
    func handleActionChange(_ action: Action) {
        guard let capture = lastCapture else { return }
        captureTask?.cancel()
        popup.restartTranslation()
        captureTask = Task { @MainActor [weak self] in
            await self?.stream(capture.text, at: capture.point, action: action)
        }
    }

    /// The user edited the source text and asked to translate it again (issue #44):
    /// re-run over the edited text with the same point and action. Mirrors the
    /// verb/formality re-run path; stream() re-snapshots lastCapture with the new
    /// text. An empty edit is ignored (nothing meaningful to translate).
    func handleSourceEdit(_ text: String) {
        guard let capture = lastCapture, !text.isEmpty else { return }
        captureTask?.cancel()
        popup.restartTranslation()
        captureTask = Task { @MainActor [weak self] in
            await self?.stream(text, at: capture.point, action: capture.action)
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

    /// Asks the model for a one-sentence Polish explanation of a clicked word's
    /// rendering (issue #39). Mirrors `fetchAlternatives`: the word and translation
    /// come from the popup, the source is the last capture, any failure (or no
    /// capture) collapses to "" — the dropdown then shows its fallback message.
    func fetchExplanation(word: String, translation: String) async -> String {
        guard let capture = lastCapture else { return "" }
        return (try? await llm.explain(
            word: word, in: translation, source: capture.text,
            second: settings.secondLanguage, model: settings.modelName)) ?? ""
    }

    /// Asks the model for a one-sentence Polish reason a grammar-diff change was
    /// corrected (issue #51). Mirrors `fetchExplanation`: the struck error, its
    /// correction and the corrected text come from the popup, the original is the
    /// last capture, any failure (or no capture) collapses to "" — the dropdown
    /// then shows its fallback message.
    func fetchFixReason(before: String, after: String, corrected: String) async -> String {
        guard let capture = lastCapture else { return "" }
        return (try? await llm.explainFix(
            error: before, correction: after, original: capture.text, corrected: corrected,
            second: settings.secondLanguage, model: settings.modelName)) ?? ""
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

    private func stream(_ text: String, at point: CGPoint, action: Action) async {
        lastCapture = (text, point, action)
        let second = settings.secondLanguage
        // The direction arrow / language pair only describe a translation; the other
        // verbs don't translate, so the popup hides that header on a .unknown direction.
        let direction = action == .translate
            ? DirectionDetector.detect(text, second: second)
            : .unknown
        popup.update(direction: direction, sourceText: text, action: action)
        await consume(llm.run(
            text, action: action, model: settings.modelName,
            second: second, formality: settings.formality, humanize: settings.humanize))
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
