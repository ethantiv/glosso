import AppKit
import NaturalLanguage
import QuartzCore
import WebKit

@MainActor
final class ReaderController: ReaderPresenting {
    private let llm: any LLMClient
    private let settings: SettingsStore
    private let extractor = ArticleExtractor()
    private let cache = ReaderCache()

    private var window: NSWindow?
    private var webView: WKWebView?
    private var translationTask: Task<Void, Never>?
    private var suggestTask: Task<Void, Never>?
    private var askTask: Task<Void, Never>?
    private var chatHistory: [(question: String, answer: String)] = []
    private var chatPanelOpen = false
    private var chatWidthDelta: CGFloat = 0
    // How far the open shifted origin.x left (window flush with the screen edge) — undone on close.
    private var chatShiftX: CGFloat = 0
    // Destination of the in-flight chat resize animation, nil when settled.
    private var chatFrameTarget: NSRect?
    private var chatAnimSeq = 0
    private static let chatPanelWidth: CGFloat = 340
    private var toolbarProxy: ReaderToolbarProxy?
    private var mode: ReaderMode = .translated
    private var closeObserver: NSObjectProtocol?
    private var currentURL: URL?
    private var statusText = ""
    private var engineLabelText = ""
    // Suggested questions are generated once per article, on first chat open.
    private var questionsRequested = false
    // True only while the pipeline is issuing model calls, so a popup's rate-limit wait can't paint over an idle reader.
    private var translating = false {
        didSet { toolbarProxy?.refreshItem?.isEnabled = !translating }
    }
    // Guards the flag against a superseded run's unwind clearing it out from under the live one.
    private var runSeq = 0
    // Set when RoutingLLMClient hands this article's calls to the local engine, so the footer stops claiming the cloud.
    private var localFallback = false

    init(llm: any LLMClient, settings: SettingsStore) {
        self.llm = llm
        self.settings = settings
    }

    func show(_ url: URL) {
        currentURL = url
        translationTask?.cancel()
        suggestTask?.cancel()
        askTask?.cancel()
        chatHistory = []
        localFallback = false
        questionsRequested = false
        statusText = ""
        mode = .translated
        toolbarProxy?.modeControl?.selectedSegment = ReaderMode.translated.rawValue
        setChatPanel(open: false)
        showChatItemOpen(false)
        let webView = ensureWindow(titled: url.host() ?? loc("Artykuł", "Article"))
        translationTask = Task { @MainActor [weak self] in
            await self?.run(url: url, in: webView)
        }
    }

    func refreshCurrentArticle() {
        guard let currentURL else { return }
        cache.remove(currentURL, primary: settings.primaryLanguage)
        show(currentURL)
    }

    private func run(url: URL, in webView: WKWebView) async {
        do {
            let watcher = NavigationWatcher()
            webView.navigationDelegate = watcher
            try await watcher.awaitNavigation(in: webView, timeout: .seconds(5)) {
                webView.loadHTMLString(ReaderTemplate.html, baseURL: url)
            }
            if let entry = cache.load(url, primary: settings.primaryLanguage) {
                try await replay(entry, in: webView)
                return
            }
            runSeq += 1
            let seq = runSeq
            translating = true
            defer { if runSeq == seq { translating = false } }
            setStatus(loc("Wczytuję artykuł…", "Loading article…"))
            let article = try await extractor.extract(from: url)
            if Task.isCancelled { return }
            window?.title = article.title
            let blocks = try await insertArticle(article, engine: nil, in: webView)
            // Read before anything translates: `summarize` used to scrape the live DOM, which under a
            // concurrent block pass would summarise a half-translated article.
            let head = await headText(in: webView)
            if Task.isCancelled { return }
            // Title and summary paint into their own slots, so they have no business holding up the blocks —
            // they were the larger part of the wait to first paragraph on every engine but Flash Lite.
            async let heading = translateHead(article.title, summarizing: head, in: webView)
            let translated = try await translate(blocks: blocks, in: webView)
            let (translatedTitle, summary) = await heading
            if let translations = translated, !Task.isCancelled {
                cache.save(.init(
                    url: url, savedAt: .now, title: article.title,
                    translatedTitle: translatedTitle, byline: article.byline ?? "",
                    content: article.content, summary: summary, translations: translations,
                    engine: currentEngineLabel),
                    primary: settings.primaryLanguage)
            }
        } catch is CancellationError {
        } catch let error as ReaderError {
            if !Task.isCancelled { setStatus(error.message) }
        } catch {
            if !Task.isCancelled { setStatus(ReaderError.fetchFailed.message) }
        }
    }

    private func replay(_ entry: ReaderCache.Entry, in webView: WKWebView) async throws {
        let article = ArticleExtractor.ExtractedArticle(
            title: entry.title, byline: entry.byline, content: entry.content)
        _ = try await insertArticle(article, engine: entry.engine, in: webView)
        if Task.isCancelled { return }
        await applyTitle(entry.translatedTitle, in: webView)
        if !entry.summary.isEmpty {
            _ = try? await webView.evaluateStringResult(ReaderTemplate.call("glossoSetSummary", entry.summary))
        }
        for (id, html) in entry.translations.sorted(by: { $0.key < $1.key }) {
            if Task.isCancelled { return }
            _ = try? await webView.evaluateStringResult(ReaderTemplate.call("glossoApply", String(id), html))
        }
        setStatus("")
    }

    /// `engine` is the cached label of whatever translated the stored text; nil asks for the engine in use now.
    private func insertArticle(
        _ article: ArticleExtractor.ExtractedArticle, engine: String?, in webView: WKWebView
    ) async throws -> [ReaderTemplate.Block] {
        let call = ReaderTemplate.call("glossoSetArticle", article.title, article.byline ?? "", article.content)
        guard let json = try await webView.evaluateStringResult(call),
              let blocks = try? JSONDecoder().decode([ReaderTemplate.Block].self, from: Data(json.utf8))
        else { throw ReaderError.extractionFailed }
        // Always set both, never only on a hit: the control outlives the article, so a nil detection would otherwise
        // leave the previous article's codes claiming a language pair this one doesn't have.
        let labels = Self.languageLabels(primary: settings.primaryLanguage, content: article.content)
            ?? (loc("Tłumaczenie", "Translation"), loc("Oryginał", "Original"))
        toolbarProxy?.modeControl?.setLabel(labels.translated, forSegment: ReaderMode.translated.rawValue)
        toolbarProxy?.modeControl?.setLabel(labels.original, forSegment: ReaderMode.original.rawValue)
        setEngine(engine ?? currentEngineLabel)
        return blocks
    }

    private func showChatItemOpen(_ open: Bool) {
        let label = open
            ? loc("Zamknij pytania do artykułu", "Close the article chat")
            : loc("Zapytaj artykuł", "Ask the article")
        toolbarProxy?.chatItem?.image = NSImage(
            systemSymbolName: open ? "bubble.left.and.text.bubble.right.fill" : "bubble.left.and.text.bubble.right",
            accessibilityDescription: label)
        toolbarProxy?.chatItem?.label = label
        toolbarProxy?.chatItem?.toolTip = label
    }

    /// Who translated *this* text, kept in the window's subtitle — a cached replay can outlive a provider switch.
    private func setEngine(_ label: String) {
        engineLabelText = label
        refreshSubtitle()
    }

    /// What is serving this run — the local engine once `RoutingLLMClient` has handed the article over.
    private var currentEngineLabel: String {
        Self.engineLabel(provider: localFallback ? .local : settings.provider,
                         model: localFallback ? settings.modelName : settings.activeModel)
    }

    nonisolated static func engineLabel(provider: LLMProvider, model: String) -> String {
        "\(provider.displayName) · \(model)"
    }

    /// The one recognition recipe (tag strip, 40-char floor, 6000-char cap, 3 hypotheses) — `languageLabels`
    /// and `isConfidently` both read from it, so a tuning change can't leave the two gates disagreeing.
    nonisolated private static func languageHypotheses(in html: String) -> [NLLanguage: Double]? {
        let text = html
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 40 else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(text.prefix(6000)))
        return recognizer.languageHypotheses(withMaximum: 3)
    }

    nonisolated static func languageLabels(
        primary: PrimaryLanguage, content: String
    ) -> (translated: String, original: String)? {
        guard let (source, confidence) = Self.languageHypotheses(in: content)?
                .max(by: { $0.value < $1.value }),
              confidence >= 0.8, source != primary.nl else { return nil }
        // "zh-Hans" → "ZH": the region/script tail is noise at pill size.
        let code = { (language: NLLanguage) -> String in
            language.rawValue.split(separator: "-").first.map(String.init)?.uppercased()
                ?? language.rawValue.uppercased()
        }
        return (code(primary.nl), code(source))
    }

    /// Runs alongside the block pass, so it never writes the status line — the block counter owns it.
    ///
    /// The two calls stay **sequential on purpose**, and the order is load-bearing on a backend that serves one request
    /// at a time (Ollama Cloud's free tier). The short title call goes out first, so by the time the slow summary is
    /// issued the first block request is already queued ahead of it. Issuing both at once would let the summary — 41.7s
    /// for 91 tokens, measured there — win the single slot and hold up the first paragraph, which is the whole thing
    /// this concurrency exists to prevent.
    private func translateHead(_ title: String, summarizing text: String, in webView: WKWebView) async -> (title: String, summary: String) {
        let translated = await translateTitle(title, in: webView)
        if Task.isCancelled { return (translated, "") }
        return (translated, await summarize(text, in: webView))
    }

    private func translateTitle(_ title: String, in webView: WKWebView) async -> String {
        var final = title
        let hasTitle = !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasTitle, !Self.isConfidently(in: settings.primaryLanguage, title) {
            let translated = (try? await llm.translateBlock(
                html: title, into: settings.primaryLanguage, model: settings.activeModel)) ?? ""
            if Task.isCancelled { return final }
            if !translated.isEmpty { final = translated }
        }
        await applyTitle(final, in: webView)
        return final
    }

    private func applyTitle(_ title: String, in webView: WKWebView) async {
        // The window and webview are shared across runs — a superseded run resuming here after its await
        // would paint the previous article's title onto the next one's page.
        guard !Task.isCancelled else { return }
        _ = try? await webView.evaluateStringResult(ReaderTemplate.call("glossoSetTitle", title))
        guard !Task.isCancelled else { return }
        window?.title = title
    }

    // ponytail: 6000-char cap — the summary reads the article's head; raise
    // it if long-article summaries come out thin. Sliced in JS so a long
    // article isn't bridged out of the web process just to be truncated.
    private func headText(in webView: WKWebView) async -> String {
        (try? await webView.evaluateStringResult(
            "document.getElementById('glosso-content').textContent.slice(0, 6000)")) ?? ""
    }

    private func summarize(_ text: String, in webView: WKWebView) async -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        guard let cleaned = try? await llm.readerSummary(of: text, into: settings.primaryLanguage, model: settings.activeModel) else { return "" }
        if Task.isCancelled { return "" }
        if !cleaned.isEmpty {
            _ = try? await webView.evaluateStringResult(ReaderTemplate.call("glossoSetSummary", cleaned))
        }
        return cleaned
    }

    /// Two consecutive failures abort the whole article, which is right when the
    /// engine is down and wrong when the model merely refused a passage: RECITATION
    /// on adjacent verbatim paragraphs would stop an article that translates fine.
    nonisolated static func countsTowardAbort(_ error: Error) -> Bool {
        if case TranslationError.contentBlocked = error { return false }
        return true
    }

    /// Per model, not per provider — a live sweep over the real reader corpus showed the two Gemini models are bound by
    /// opposite things, so one number cannot serve both. The per-model values and their reasons live in the catalogs.
    /// Local stays at 1: measured per-block wall clock is flat (2.95s at one block, 2.28s at ten, 2.87s at twenty), and
    /// that best point sits inside a noise band the sweep itself measured, so batching buys nothing here while
    /// multiplying the blast radius of a discarded batch.
    nonisolated static func batchSize(provider: LLMProvider, model: String) -> Int {
        switch provider {
        case .local: 1
        case .cloud: CloudModelCatalog.batch(for: model)
        case .ollamaCloud: OllamaCloudCatalog.batch
        }
    }

    /// Gated on `translating` like `cloudWait`: the same closure fires for popup captures, and only a running
    /// pipeline means the article itself is being served locally.
    func engineFallback() {
        guard translating else { return }
        localFallback = true
        setEngine(currentEngineLabel)
    }

    /// The limiter blocks rather than failing, so without this the status bar would simply stop moving mid-article.
    func cloudWait(_ seconds: TimeInterval) {
        guard translating else { return }
        setStatus(loc("Czekam na limit Google AI… (\(Int(seconds.rounded(.up))) s)",
                      "Waiting for the Google AI rate limit… (\(Int(seconds.rounded(.up))) s)"))
    }

    private func translate(blocks: [ReaderTemplate.Block], in webView: WKWebView) async throws -> [Int: String]? {
        var applied: [Int: String] = [:]
        let translatable = blocks.filter(\.translate)
        if Self.isConfidently(in: settings.primaryLanguage,
                              String(translatable.map(\.html).joined(separator: " ").prefix(6000))) {
            for block in translatable {
                if Task.isCancelled { return nil }
                _ = try? await webView.evaluateStringResult(
                    ReaderTemplate.call("glossoApply", String(block.id), block.html))
                applied[block.id] = block.html
            }
            setStatus("")
            return applied
        }
        // Applied up front so they never take up room in a batch, and never get sent.
        var pending: [ReaderTemplate.Block] = []
        for block in translatable {
            if Task.isCancelled { return nil }
            if Self.isConfidently(in: settings.primaryLanguage, block.html) {
                _ = try? await webView.evaluateStringResult(
                    ReaderTemplate.call("glossoApply", String(block.id), block.html))
                applied[block.id] = block.html
            } else {
                pending.append(block)
            }
        }
        var failed = 0
        var consecutiveFailures = 0
        // The setting says cloud, but RoutingLLMClient may be quietly serving from Ollama, which holds the format far worse.
        var consecutiveBatchFailures = 0
        var done = translatable.count - pending.count
        let batchSize = Self.batchSize(provider: settings.provider, model: settings.activeModel)
        for batch in ReaderTemplate.batches(pending, maxCount: batchSize) {
            if Task.isCancelled { return nil }
            setStatus(loc("Tłumaczę… (\(done + 1)/\(translatable.count))",
                          "Translating… (\(done + 1)/\(translatable.count))"))
            var batched: [Int: String] = [:]
            // Two batches in a row failing means whatever is answering can't hold the format; stop paying for the attempt.
            if batch.count > 1, consecutiveBatchFailures < 2 {
                // A batch that throws or fails the round trip is discarded whole and costs no failure — its blocks retry one by one below.
                batched = (try? await llm.translateBlocks(batch.map { (id: $0.id, html: $0.html) },
                                                          into: settings.primaryLanguage,
                                                          model: settings.activeModel)) ?? [:]
                if Task.isCancelled { return nil }
                consecutiveBatchFailures = batched.isEmpty ? consecutiveBatchFailures + 1 : 0
            }
            for block in batch {
                if Task.isCancelled { return nil }
                // Repainted per block, so a rate-limit message painted while this batch was waiting cannot outlive the wait.
                setStatus(loc("Tłumaczę… (\(done + 1)/\(translatable.count))",
                              "Translating… (\(done + 1)/\(translatable.count))"))
                let translated: String
                if let fromBatch = batched[block.id] {
                    translated = fromBatch
                } else {
                    do {
                        translated = try await llm.translateBlock(
                            html: block.html, into: settings.primaryLanguage, model: settings.activeModel)
                    } catch is CancellationError {
                        return nil
                    } catch TranslationError.cancelled {
                        return nil
                    } catch {
                        if Task.isCancelled { return nil }
                        failed += 1
                        done += 1
                        consecutiveFailures = Self.countsTowardAbort(error) ? consecutiveFailures + 1 : 0
                        if consecutiveFailures >= 2 {
                            _ = try? await webView.evaluateStringResult("glossoAbort()")
                            let detail = (error as? TranslationError).map { " " + $0.userMessage } ?? ""
                            setStatus(loc("Tłumaczenie przerwane — reszta w oryginale.",
                                          "Translation stopped — the rest stays in the original language.") + detail)
                            return nil
                        }
                        _ = try? await webView.evaluateStringResult(ReaderTemplate.call(
                            "glossoApply", String(block.id), block.html))
                        continue
                    }
                }
                consecutiveFailures = 0
                if Task.isCancelled { return nil }
                // An empty result must still un-dim its block — re-apply the original.
                let html = translated.isEmpty ? block.html : translated
                _ = try? await webView.evaluateStringResult(ReaderTemplate.call(
                    "glossoApply", String(block.id), html))
                applied[block.id] = html
                done += 1
            }
        }
        if Task.isCancelled { return nil }
        if failed > 0 {
            setStatus(loc("Przetłumaczono z pominięciem \(failed) bloków (zostały w oryginale).",
                          "Translated with \(failed) blocks skipped (kept in the original language)."))
            return nil
        }
        setStatus("")
        return applied
    }

    private static func isConfidently(in primary: PrimaryLanguage, _ html: String) -> Bool {
        (Self.languageHypotheses(in: html)?[primary.nl] ?? 0) >= 0.8
    }

    private func setChatPanel(open: Bool, animated: Bool = true) {
        guard open != chatPanelOpen, let window else { return }
        chatPanelOpen = open
        var frame = chatFrameTarget ?? window.frame
        if open {
            let visible = window.screen?.visibleFrame
            let target = min(frame.width + Self.chatPanelWidth, visible?.width ?? .greatestFiniteMagnitude)
            chatWidthDelta = target - frame.width
            frame.size.width = target
            let before = frame.origin.x
            if let visible, frame.maxX > visible.maxX {
                frame.origin.x = max(visible.minX, visible.maxX - frame.width)
            }
            chatShiftX = before - frame.origin.x
        } else {
            frame.size.width -= chatWidthDelta
            chatWidthDelta = 0
            // Undo the open's left shift, clamped to the screen — otherwise every open/close at the right
            // edge walks the window left by a panel width.
            frame.origin.x += chatShiftX
            chatShiftX = 0
            if let visible = window.screen?.visibleFrame {
                frame.origin.x = min(frame.origin.x, visible.maxX - frame.width)
                frame.origin.x = max(frame.origin.x, visible.minX)
            }
        }
        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let target = frame
            chatAnimSeq += 1
            let seq = chatAnimSeq
            chatFrameTarget = target
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(target, display: true)
            }, completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    if self?.chatAnimSeq == seq { self?.chatFrameTarget = nil }
                }
            })
        } else {
            chatFrameTarget = nil
            window.setFrame(frame, display: true)
        }
    }

    // ponytail: 12000-char cap, double the summary's — answers reach deeper into
    // the article; raise it if questions about article tails come back "not in
    // the article". Sliced in JS like summarize(), read fresh per request so the
    // chat always sees the currently displayed text.
    private func chatContext(in webView: WKWebView) async -> String {
        (try? await webView.evaluateStringResult(
            "document.getElementById('glosso-content').textContent.slice(0, 12000)")) ?? ""
    }

    private func suggestQuestions() {
        guard let webView else { return }
        suggestTask?.cancel()
        suggestTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let context = await self.chatContext(in: webView)
            var questions: [String] = []
            if !context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                questions = (try? await self.llm.articleQuestions(
                    about: context, into: self.settings.primaryLanguage, model: self.settings.activeModel)) ?? []
            }
            if Task.isCancelled { return }
            // Nothing came back — let the next open try again, the way the page's own flag used to.
            if questions.isEmpty { self.questionsRequested = false }
            let json = (try? JSONEncoder().encode(questions))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            _ = try? await webView.evaluateStringResult(ReaderTemplate.call("glossoSetQuestions", json))
        }
    }

    fileprivate func answer(question: String) {
        guard let webView else { return }
        askTask?.cancel()
        askTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let context = await self.chatContext(in: webView)
            do {
                // ponytail: last 4 turns cap the prompt; raise if follow-ups lose thread
                let answer = try await self.llm.askArticle(
                    question: question, history: Array(self.chatHistory.suffix(4)), article: context,
                    into: self.settings.primaryLanguage, model: self.settings.activeModel)
                if Task.isCancelled { return }
                self.chatHistory.append((question, answer))
                _ = try? await webView.evaluateStringResult(
                    ReaderTemplate.call("glossoAnswer", ReaderTemplate.markdown(answer), ""))
            } catch {
                if Task.isCancelled { return }
                let message = (error as? TranslationError)?.userMessage
                    ?? loc("Nie udało się uzyskać odpowiedzi.", "Could not get an answer.")
                _ = try? await webView.evaluateStringResult(ReaderTemplate.call("glossoAnswer", "", message))
            }
        }
    }

    /// The status and the engine label share the window's subtitle: two slots in a bar the page had to lay out itself,
    /// and one line the system already draws under the title.
    private func setStatus(_ message: String) {
        statusText = message
        refreshSubtitle()
    }

    private func refreshSubtitle() {
        window?.subtitle = [statusText, engineLabelText]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    func setMode(_ newMode: ReaderMode) {
        guard mode != newMode else { return }
        // Record it even with no webview to talk to, or the control and this flag disagree and the next click no-ops.
        mode = newMode
        webView?.evaluateJavaScript(ReaderTemplate.call("glossoSetMode", newMode.jsValue), completionHandler: nil)
    }

    func toggleChatPanel() {
        guard let webView else { return }
        let open = !chatPanelOpen
        setChatPanel(open: open)
        // The real width granted by the screen clamp — a fixed page margin squeezed the article by the full
        // panel width even when the window could only grow a fraction of it. Below half the nominal width the
        // measured value is unusable ("0px" is truthy in JS and would zero the panel out entirely, e.g. on an
        // already-maximized window) — send nothing and let the page's 340px default overlay the article instead.
        let usable = chatWidthDelta >= Self.chatPanelWidth * 0.5
        let width = open && usable ? "\(Int(chatWidthDelta))px" : ""
        webView.evaluateJavaScript(ReaderTemplate.call("glossoSetChat", open ? "1" : "", width), completionHandler: nil)
        showChatItemOpen(open)
        if open, !questionsRequested {
            questionsRequested = true
            webView.evaluateJavaScript(ReaderTemplate.call("glossoSuggesting"), completionHandler: nil)
            suggestQuestions()
        }
    }

    private func ensureWindow(titled title: String) -> WKWebView {
        let (window, webView) = existingOrNewWindow()
        window.title = title
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return webView
    }

    private func existingOrNewWindow() -> (NSWindow, WKWebView) {
        if let window, let webView { return (window, webView) }
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(ReaderScriptMessageProxy(controller: self), name: "glosso")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = webView
        window.isReleasedWhenClosed = false
        let proxy = ReaderToolbarProxy(controller: self)
        let toolbar = NSToolbar(identifier: "GlossoReader")
        toolbar.delegate = proxy
        toolbar.allowsUserCustomization = false
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.subtitle = ""
        toolbarProxy = proxy
        window.center()
        window.setFrameAutosaveName("GlossoReader")
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.windowWillClose() }
        }
        self.window = window
        self.webView = webView
        return (window, webView)
    }

    private func windowWillClose() {
        translationTask?.cancel()
        toolbarProxy = nil
        suggestTask?.cancel()
        askTask?.cancel()
        chatHistory = []
        setChatPanel(open: false, animated: false)
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = nil
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "glosso")
        window = nil
        webView = nil
    }
}

@MainActor
private final class ReaderScriptMessageProxy: NSObject, WKScriptMessageHandler {
    private weak var controller: ReaderController?

    init(controller: ReaderController) {
        self.controller = controller
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        // The toolbar owns refresh, the view switch and the chat panel now, so asking is all that's left to post up.
        guard let dict = message.body as? [String: String], dict["action"] == "ask",
              let question = dict["question"], !question.isEmpty else { return }
        controller?.answer(question: question)
    }
}
