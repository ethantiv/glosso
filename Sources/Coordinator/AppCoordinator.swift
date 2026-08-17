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
    private let articleReader: (any ReaderPresenting)?

    private let pollStepMs: Int
    private let pollMaxAttempts: Int
    private let prefetchLingerMs: Int
    private let frontmostPID: @MainActor () -> pid_t?
    private let frontmostBundleID: @MainActor () -> String?
    private let notify: @MainActor (String) -> Void

    // A terminal's "selection" is a mouse highlight the shell won't replace — Cmd+V
    // appends at the prompt — so even a provably fresh synthetic copy must not be
    // pasted back there.
    // ponytail: VS Code's *integrated* terminal shares com.microsoft.VSCode with the
    // editor — indistinguishable by bundle id; add an AX-role probe if it bites.
    private static let terminalBundleIDs: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "net.kovidgoyal.kitty",
        "org.alacritty", "com.github.wez.wezterm", "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable", "co.zeit.hyper",
    ]

    private var captureTask: Task<Void, Never>?
    private var fixTask: Task<Void, Never>?

    private var prefetchTask: Task<Void, Never>?

    private enum ActionResult { case text(String, truncated: Bool); case replies([String]) }
    private var actionCache: [Action: ActionResult] = [:]

    private var cacheSignature: String?
    private func currentCacheSignature() -> String {
        "\(settings.activeModel)|\(settings.primaryLanguage.rawValue)|\(settings.secondLanguage?.rawValue ?? "auto")"
    }

    private func resolvedSecond(for direction: TranslationDirection) -> SecondLanguage {
        switch direction {
        case .fromPrimary(_, let second), .toPrimary(_, let second): second
        case .unknown: settings.secondLanguage ?? settings.primaryLanguage.counterpart.asSecond
        }
    }

    private var lastCapture: (text: String, point: CGPoint, action: Action, direction: TranslationDirection)?

    private var lastSourcePID: pid_t?

    // Ring of pasteboard changeCounts sampled every 2s (newest last, 3 deep), so
    // the oldest is 4–6s old once warm. It backs the capture's second chance: when
    // event delivery lags behind the gesture's own copy (the VS Code case — see
    // the retry in captureAndTranslate),
    // every callback-sampled baseline is already post-copy, and only a snapshot
    // predating the whole gesture can prove the pasteboard changed. Internal (not
    // private) so tests can seed it without running the timer.
    // ponytail: 4–6s freshness ceiling; if event lag ever exceeds it, deepen the ring.
    var trailingChangeCounts: [Int] = []
    private var snapshotTask: Task<Void, Never>?

    private func startPasteboardSnapshots() {
        snapshotTask?.cancel()
        trailingChangeCounts = [reader.currentChangeCount]
        snapshotTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, !Task.isCancelled else { return }
                trailingChangeCounts = Array((trailingChangeCounts + [reader.currentChangeCount]).suffix(3))
            }
        }
    }

    init(
        llm: any LLMClient,
        monitor: any HotkeyMonitor,
        reader: any PasteboardReading,
        axReader: any AXSelectionReading,
        popup: any TranslationPopupPresenting,
        settings: SettingsStore,
        articleReader: (any ReaderPresenting)? = nil,
        replacer: any SelectionReplacing = SystemSelectionReplacer(),
        pollStepMs: Int = 12,
        pollMaxAttempts: Int = 40,
        prefetchLingerMs: Int = 800,
        frontmostPID: @escaping @MainActor () -> pid_t? = { NSWorkspace.shared.frontmostApplication?.processIdentifier },
        frontmostBundleID: @escaping @MainActor () -> String? = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier },
        notify: @escaping @MainActor (String) -> Void = { SystemUserNotifier.post($0) }
    ) {
        self.llm = llm
        self.monitor = monitor
        self.reader = reader
        self.axReader = axReader
        self.popup = popup
        self.replacer = replacer
        self.settings = settings
        self.articleReader = articleReader
        self.pollStepMs = pollStepMs
        self.pollMaxAttempts = pollMaxAttempts
        self.prefetchLingerMs = prefetchLingerMs
        self.frontmostPID = frontmostPID
        self.frontmostBundleID = frontmostBundleID
        self.notify = notify
    }

    @discardableResult
    func start() -> Bool {
        Task { try? await llm.prewarm(model: settings.activeModel) }

        startPasteboardSnapshots()
        monitor.onDoubleCopy = { [weak self] baseline in self?.handleDoubleCopy(baseline: baseline) }
        monitor.onFixGrammar = { [weak self] in self?.handleFixGrammar() }
        monitor.onTranslateInPlace = { [weak self] in self?.handleTranslateInPlace() }
        popup.onDismiss = { [weak self] in
            self?.captureTask?.cancel()
            self?.prefetchTask?.cancel()
            self?.lastCapture = nil
        }
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
        popup.onFetchToneNote = { [weak self] previous, current, from, to in
            await self?.fetchToneNote(previous: previous, current: current, from: from, to: to) ?? ""
        }
        popup.onReplace = { [weak self] translation in self?.handleReplace(translation: translation) }
        popup.onRetranslate = { [weak self] source in self?.handleSourceEdit(source) }
        popup.onUndo = { [weak self] in self?.handleUndo() }

        do {
            try monitor.start()
            return true
        } catch {
            return false
        }
    }

    func stop() {
        monitor.stop()
        captureTask?.cancel()
        prefetchTask?.cancel()
        fixTask?.cancel()
        snapshotTask?.cancel()
        popup.dismiss()
    }

    func handleDoubleCopy(baseline: Int) {
        let mouse = NSEvent.mouseLocation
        let source = frontmostPID()
        captureTask?.cancel()
        prefetchTask?.cancel()
        popup.dismiss()
        captureTask = Task { @MainActor [weak self] in
            await self?.captureAndTranslate(baseline: baseline, at: mouse, sourcePID: source)
        }
    }

    func captureAndTranslate(baseline: Int, at point: CGPoint, sourcePID: pid_t? = nil) async {
        if Task.isCancelled { return }
        lastCapture = nil
        // A fresh selection invalidates every cached action result.
        actionCache.removeAll()
        lastSourcePID = sourcePID
        popup.present(at: point, formality: settings.formality)
        var sawEmptyCopy = false
        for _ in 0..<pollMaxAttempts {
            if Task.isCancelled { return }
            do {
                let text = try reader.readSelection(baselineChangeCount: baseline)
                if Task.isCancelled { return }
                await route(text, at: point)
                return
            } catch CaptureError.emptyOrNonText {
                // A copying app clears and writes in two steps; a poll landing between them sees a risen
                // changeCount with no string yet. Keep polling — only a timeout makes "no text" true.
                sawEmptyCopy = true
            } catch CaptureError.nothingSelected {
                // clipboard has not updated yet — keep polling.
            } catch {
                popup.showError(loc("Nie udało się pobrać zaznaczenia. Spróbuj ponownie.",
                                    "Couldn't read the selection. Try again."))
                return
            }
            try? await Task.sleep(for: .milliseconds(pollStepMs))
        }
        if Task.isCancelled { return }
        // A copy landed and stayed non-text for the whole window — proof the selection isn't text.
        // Deliberately no AX consultation here (see emptyOrNonTextSelectionDoesNotConsultAX).
        if sawEmptyCopy {
            popup.showError(loc("Zaznaczenie nie zawiera tekstu do tłumaczenia.",
                                "The selection contains no text to translate."))
            return
        }
        if sourcePID == nil || sourcePID == frontmostPID(),
           let axText = try? SelectionGuard.nonEmptyText(axReader.selectedText()) {
            if Task.isCancelled { return }
            await route(axText, at: point)
            return
        }
        if let trailing = trailingChangeCounts.first,
           let text = try? reader.readSelection(baselineChangeCount: trailing) {
            if Task.isCancelled { return }
            await stream(text, at: point, action: .translate)
            return
        }
        popup.showError(loc("Nie udało się pobrać zaznaczenia. Spróbuj ponownie.",
                            "Couldn't read the selection. Try again."))
    }

    private func frontmostIsTerminal() -> Bool {
        frontmostBundleID().map { Self.terminalBundleIDs.contains($0) } ?? false
    }

    func handleReplace(translation: String) {
        guard let sourcePID = lastSourcePID, sourcePID == frontmostPID() else {
            popup.showError(loc("Aplikacja źródłowa się zmieniła — nie wklejono.",
                                "The source app changed — nothing was pasted."))
            return
        }
        guard !frontmostIsTerminal() else {
            copyToClipboard(translation)
            popup.showError(loc("Terminal nie pozwala zastąpić zaznaczenia — tłumaczenie jest w schowku (Cmd+V).",
                                "A terminal can't replace the selection — the translation is on the clipboard (Cmd+V)."))
            return
        }
        if let selection = axReader.selectedText(),
           selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            popup.showError(loc("Brak zaznaczenia do zastąpienia.",
                                "No selection left to replace."))
            return
        }
        replacer.replace(with: translation)
        popup.dismiss()
    }

    func handleFixGrammar() {
        let source = frontmostPID()
        fixTask?.cancel()
        fixTask = Task { @MainActor [weak self] in await self?.fixGrammarInPlace(sourcePID: source) }
    }

    func handleTranslateInPlace() {
        let source = frontmostPID()
        fixTask?.cancel()
        fixTask = Task { @MainActor [weak self] in await self?.fixGrammarInPlace(sourcePID: source, action: .translate) }
    }

    func fixGrammarInPlace(sourcePID: pid_t?, action: Action = .fixGrammar) async {
        let isTranslate = action == .translate
        var captured = try? SelectionGuard.nonEmptyText(axReader.selectedText())
        let usedFallback = captured == nil
        var freshSyntheticCopy = false
        if captured == nil, let fallback = await captureViaSyntheticCopy() {
            captured = try? SelectionGuard.nonEmptyText(fallback.text)
            freshSyntheticCopy = fallback.fresh
        }
        if Task.isCancelled { return }
        guard let text = captured else {
            notify(isTranslate
                ? loc("Nie udało się odczytać zaznaczenia do tłumaczenia.",
                      "Couldn't read the selection to translate.")
                : loc("Nie udało się odczytać zaznaczenia do poprawy.",
                      "Couldn't read the selection to fix."))
            return
        }
        var buffer = ""
        let detected = DirectionDetector.detect(text, primary: settings.primaryLanguage, second: settings.secondLanguage)
        do {
            for try await event in llm.run(
                text, action: action, model: settings.activeModel,
                primary: settings.primaryLanguage, second: resolvedSecond(for: detected),
                formality: settings.formality,
                style: detected.supportsStyleFix) {
                if Task.isCancelled { return }
                if case .token(let token) = event { buffer += token }
            }
        } catch {
            if Task.isCancelled { return }
            notify(isTranslate
                ? loc("Nie udało się przetłumaczyć tekstu.", "Couldn't translate the text.")
                : loc("Nie udało się poprawić tekstu.", "Couldn't fix the text."))
            return
        }
        if Task.isCancelled { return }
        let corrected = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !corrected.isEmpty else { return }
        // The terminal check covers the AX path too: Terminal/iTerm expose AXSelectedText, so a successful
        // AX read must not become a licence to paste where Cmd+V appends at the prompt. The fallback path
        // additionally demands a *known* non-terminal bundle — an unknown frontmost app is not worth the risk.
        let bundleID = frontmostBundleID()
        let isTerminal = bundleID.map { Self.terminalBundleIDs.contains($0) } ?? false
        if usedFallback || isTerminal {
            let pasteable = !isTerminal && (!usedFallback || (freshSyntheticCopy && bundleID != nil))
            guard pasteable else {
                copyToClipboard(corrected)
                notify(isTranslate
                    ? loc("Przetłumaczono. To zaznaczenie nie pozwala wkleić w miejscu — tłumaczenie jest w schowku (Cmd+V).",
                          "Translated. This selection can't be pasted over in place — the translation is on the clipboard (Cmd+V).")
                    : loc("Poprawiono. To zaznaczenie nie pozwala wkleić w miejscu — poprawka jest w schowku (Cmd+V).",
                          "Fixed. This selection can't be pasted over in place — the fix is on the clipboard (Cmd+V)."))
                return
            }
        }
        // ponytail: best-effort paste; no read-only detection — add an AX writability probe if it bites
        guard let sourcePID, sourcePID == frontmostPID() else {
            copyToClipboard(corrected)
            notify(isTranslate
                ? loc("Aplikacja się zmieniła — tłumaczenie skopiowano do schowka.",
                      "The app changed — the translation was copied to the clipboard.")
                : loc("Aplikacja się zmieniła — poprawiony tekst skopiowano do schowka.",
                      "The app changed — the fixed text was copied to the clipboard."))
            return
        }
        if !usedFallback, let selection = axReader.selectedText(),
           selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            copyToClipboard(corrected)
            notify(isTranslate
                ? loc("Zaznaczenie zniknęło — tłumaczenie skopiowano do schowka.",
                      "The selection disappeared — the translation was copied to the clipboard.")
                : loc("Zaznaczenie zniknęło — poprawiony tekst skopiowano do schowka.",
                      "The selection disappeared — the fixed text was copied to the clipboard."))
            return
        }
        replacer.replace(with: corrected)
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func captureViaSyntheticCopy() async -> (text: String, fresh: Bool)? {
        let pasteboard = NSPasteboard.general
        // Every flavor, not just the string: restoring only text would destroy a copied image or file list.
        let original = PasteboardSnapshot.capture(pasteboard)
        let baseline = reader.currentChangeCount
        replacer.synthesizeCopy()
        var captured: String?
        var fresh = true
        for _ in 0..<pollMaxAttempts {
            if Task.isCancelled { break }
            if let text = try? reader.readSelection(baselineChangeCount: baseline) {
                captured = text
                break
            }
            try? await Task.sleep(for: .milliseconds(pollStepMs))
        }
        // The Cmd+C may legitimately write nothing: a terminal with copy-on-selection
        // (VS Code's default) already copied the text the moment the mouse selected it,
        // and re-copying identical content is a no-op that never bumps changeCount. The
        // strict baseline can then never rise, even though the selection is right there
        // on the clipboard. Mirror the double-Cmd+C retry (captureAndTranslate) and give
        // it a second chance against a snapshot predating the whole gesture: that accepts
        // the selection's own copy while still refusing a clipboard older than the ring.
        // ponytail: the ring's ~4-6s window is the whole guard — a copy-on-selection
        // older than it fails, an unrelated copy inside it is accepted. Nothing on the
        // pasteboard can tell the two apart; only a real selection read (AX) could.
        if captured == nil, let trailing = trailingChangeCounts.first {
            captured = try? reader.readSelection(baselineChangeCount: trailing)
            fresh = false
        }
        PasteboardSnapshot.restore(original, to: pasteboard)
        guard let captured else { return nil }
        return (captured, fresh)
    }

    private func rerunLastCapture(text: String? = nil, action: Action? = nil, invalidatingCache: Bool = true) {
        guard let capture = lastCapture else { return }
        captureTask?.cancel()
        prefetchTask?.cancel()
        if invalidatingCache { actionCache.removeAll() }
        popup.restartTranslation()
        captureTask = Task { @MainActor [weak self] in
            await self?.stream(text ?? capture.text, at: capture.point, action: action ?? capture.action)
        }
    }

    func handleFormalityChange(_ formality: Formality) {
        settings.formality = formality
        rerunLastCapture()
    }

    func handleActionChange(_ action: Action) {
        rerunLastCapture(action: action, invalidatingCache: false)
    }

    func handleSourceEdit(_ text: String) {
        guard !text.isEmpty else { return }
        rerunLastCapture(text: text)
    }

    private typealias Capture = (text: String, point: CGPoint, action: Action, direction: TranslationDirection)

    /// The shared scaffold of every per-word lookup: pause the prefetch around the call, resume it after.
    private func pausingPrefetch<T: Sendable>(
        _ fallback: T, _ op: (Capture) async throws -> T
    ) async -> T {
        guard let capture = lastCapture else { return fallback }
        prefetchTask?.cancel()
        let result = (try? await op(capture)) ?? fallback
        schedulePrefetch()
        return result
    }

    func fetchAlternatives(word: String, translation: String) async -> [String] {
        await pausingPrefetch([]) { capture in
            try await llm.alternatives(
                for: word, in: translation, source: capture.text,
                primary: settings.primaryLanguage, second: resolvedSecond(for: capture.direction),
                model: settings.activeModel)
        }
    }

    func fetchExplanation(word: String, translation: String) async -> String {
        await pausingPrefetch("") { capture in
            try await llm.explain(
                word: word, in: translation, source: capture.text,
                primary: settings.primaryLanguage, second: resolvedSecond(for: capture.direction),
                model: settings.activeModel)
        }
    }

    func fetchFixReason(before: String, after: String, corrected: String) async -> String {
        await pausingPrefetch("") { capture in
            try await llm.explainFix(
                error: before, correction: after, original: capture.text, corrected: corrected,
                primary: settings.primaryLanguage, second: resolvedSecond(for: capture.direction),
                englishRules: capture.direction == .toPrimary(.polish, .english),
                style: capture.direction.supportsStyleFix,
                model: settings.activeModel)
        }
    }

    func fetchToneNote(previous: String, current: String, from: Formality, to: Formality) async -> String {
        await pausingPrefetch("") { capture in
            try await llm.explainRegister(
                previous: previous, current: current, from: from, to: to,
                source: capture.text,
                primary: settings.primaryLanguage, second: resolvedSecond(for: capture.direction),
                model: settings.activeModel)
        }
    }

    func handlePickAlternative(original: String, chosen: String, translation: String) {
        guard lastCapture != nil else { return }
        captureTask?.cancel()
        prefetchTask?.cancel()
        popup.restartTranslation()
        captureTask = Task { @MainActor [weak self] in
            await self?.streamReword(original: original, chosen: chosen, translation: translation)
        }
    }

    func handleUndo() {
        actionCache.removeValue(forKey: .translate)
    }

    private func route(_ text: String, at point: CGPoint) async {
        if let articleReader, let url = URLDetector.articleURL(in: text) {
            articleReader.show(url)
            popup.dismiss()
            return
        }
        await stream(text, at: point, action: .translate)
    }

    private func stream(_ text: String, at point: CGPoint, action: Action) async {
        // A cancelled predecessor must not paint: its synchronous prefix (update + a cached append/finish)
        // would land after the successor's restartTranslation and corrupt the pane.
        if Task.isCancelled { return }
        let detected = DirectionDetector.detect(text, primary: settings.primaryLanguage, second: settings.secondLanguage)
        lastCapture = (text, point, action, detected)
        let direction = action == .translate || action == .fixGrammar ? detected : .unknown
        popup.update(direction: direction, sourceText: text, action: action)

        let signature = currentCacheSignature()
        if signature != cacheSignature {
            actionCache.removeAll()
            cacheSignature = signature
        }

        if let cached = actionCache[action] {
            switch cached {
            case .text(let result, let truncated):
                popup.append(token: result)
                popup.finish(truncated: truncated)
            case .replies(let drafts):
                popup.showReplies(drafts)
            }
            schedulePrefetch()
            return
        }

        if action == .reply {
            let drafts = (try? await llm.reply(to: text, model: settings.activeModel)) ?? []
            if Task.isCancelled { return }
            if drafts.isEmpty {
                popup.showError(loc("Nie udało się wygenerować odpowiedzi.",
                                    "Couldn't generate replies."))
            } else {
                popup.showReplies(drafts)
                actionCache[.reply] = .replies(drafts)
            }
            schedulePrefetch()
            return
        }
        await consume(llm.run(
            text, action: action, model: settings.activeModel,
            primary: settings.primaryLanguage, second: resolvedSecond(for: detected),
            formality: settings.formality,
            style: detected.supportsStyleFix),
            bucket: action)
        if !Task.isCancelled { schedulePrefetch() }
    }

    private func streamReword(original: String, chosen: String, translation: String) async {
        guard let capture = lastCapture else { return }
        await consume(llm.reword(
            original: original, to: chosen, in: translation,
            source: capture.text,
            primary: settings.primaryLanguage, second: resolvedSecond(for: capture.direction),
            formality: settings.formality, model: settings.activeModel),
            bucket: .translate)
        if !Task.isCancelled { schedulePrefetch() }
    }

    private func consume(_ stream: AsyncThrowingStream<TranslationEvent, Error>, bucket: Action? = nil) async {
        var accumulated = ""
        do {
            for try await event in stream {
                if Task.isCancelled { return }
                switch event {
                case .token(let token):
                    accumulated += token
                    popup.append(token: token)
                case .finished(let reason):
                    let truncated = reason == "length"
                    popup.finish(truncated: truncated)
                    if let bucket { actionCache[bucket] = .text(accumulated, truncated: truncated) }
                }
            }
        } catch let error as TranslationError {
            if Task.isCancelled { return }
            popup.showError(error.userMessage)
        } catch {
            if Task.isCancelled { return }
            popup.showError(loc("Błąd tłumaczenia.", "Translation failed."))
        }
    }

    private func schedulePrefetch() {
        if Task.isCancelled { return }
        prefetchTask?.cancel()
        // Free against a resident local model, but the cloud meters every call: three guessed verbs per capture spend 4x the day's budget.
        guard settings.provider == .local else { return }
        guard let source = lastCapture?.text else { return }
        let signature = currentCacheSignature()
        prefetchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(self.prefetchLingerMs))
            if Task.isCancelled { return }
            for action in Action.allCases where action != .translate {
                if Task.isCancelled { return }
                if self.actionCache[action] != nil { continue }
                await self.prefetchOne(action, source: source, signature: signature)
            }
        }
    }

    /// `signature` pins the settings snapshot this prefetch runs under: a result generated after a mid-flight
    /// model/language switch must not land in the cache under the old stamp.
    private func prefetchOne(_ action: Action, source: String, signature: String) async {
        if action == .reply {
            guard let drafts = try? await llm.reply(to: source, model: settings.activeModel),
                  !drafts.isEmpty, !Task.isCancelled,
                  currentCacheSignature() == signature else { return }
            actionCache[.reply] = .replies(drafts)
            return
        }
        var accumulated = ""
        do {
            for try await event in llm.run(
                source, action: action, model: settings.activeModel,
                primary: settings.primaryLanguage,
                second: resolvedSecond(for: lastCapture?.direction ?? .unknown),
                formality: settings.formality,
                style: (lastCapture?.direction ?? .unknown).supportsStyleFix) {
                if Task.isCancelled { return }
                switch event {
                case .token(let token): accumulated += token
                case .finished(let reason):
                    guard currentCacheSignature() == signature else { return }
                    actionCache[action] = .text(accumulated, truncated: reason == "length")
                }
            }
        } catch {
            // best-effort prefetch
        }
    }
}
