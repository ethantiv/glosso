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
    // Destination of the in-flight chat resize animation, nil when settled.
    private var chatFrameTarget: NSRect?
    private var chatAnimSeq = 0
    private static let chatPanelWidth: CGFloat = 340
    // Blocks per cloud request. Batching only buys anything against a per-minute request cap, which the local engine has none of.
    private static let cloudBatchSize = 5
    private var closeObserver: NSObjectProtocol?
    private var currentURL: URL?
    // True only while the pipeline is issuing model calls, so a popup's rate-limit wait can't paint over an idle reader.
    private var translating = false
    // Guards the flag against a superseded run's unwind clearing it out from under the live one.
    private var runSeq = 0

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
        setChatPanel(open: false)
        let webView = ensureWindow(titled: url.host() ?? loc("Artykuł", "Article"))
        translationTask = Task { @MainActor [weak self] in
            await self?.run(url: url, in: webView)
        }
    }

    fileprivate func refreshCurrentArticle() {
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
            setStatus(loc("Wczytuję artykuł…", "Loading article…"), in: webView)
            let article = try await extractor.extract(from: url)
            if Task.isCancelled { return }
            window?.title = article.title
            let blocks = try await insertArticle(article, in: webView)
            let translatedTitle = await translateTitle(article.title, in: webView)
            if Task.isCancelled { return }
            let summary = await summarize(in: webView)
            if Task.isCancelled { return }
            if let translations = try await translate(blocks: blocks, in: webView), !Task.isCancelled {
                cache.save(.init(
                    url: url, savedAt: .now, title: article.title,
                    translatedTitle: translatedTitle, byline: article.byline ?? "",
                    content: article.content, summary: summary, translations: translations),
                    primary: settings.primaryLanguage)
            }
        } catch is CancellationError {
        } catch let error as ReaderError {
            if !Task.isCancelled { setStatus(error.message, in: webView) }
        } catch {
            if !Task.isCancelled { setStatus(ReaderError.fetchFailed.message, in: webView) }
        }
    }

    private func replay(_ entry: ReaderCache.Entry, in webView: WKWebView) async throws {
        let article = ArticleExtractor.ExtractedArticle(
            title: entry.title, byline: entry.byline, content: entry.content)
        _ = try await insertArticle(article, in: webView)
        if Task.isCancelled { return }
        await applyTitle(entry.translatedTitle, in: webView)
        if !entry.summary.isEmpty {
            _ = try? await webView.evaluateStringResult(ReaderTemplate.call("glossoSetSummary", entry.summary))
        }
        for (id, html) in entry.translations.sorted(by: { $0.key < $1.key }) {
            if Task.isCancelled { return }
            _ = try? await webView.evaluateStringResult(ReaderTemplate.call("glossoApply", String(id), html))
        }
        setStatus("", in: webView)
    }

    private func insertArticle(_ article: ArticleExtractor.ExtractedArticle, in webView: WKWebView) async throws -> [ReaderTemplate.Block] {
        let call = ReaderTemplate.call("glossoSetArticle", article.title, article.byline ?? "", article.content)
        guard let json = try await webView.evaluateStringResult(call),
              let blocks = try? JSONDecoder().decode([ReaderTemplate.Block].self, from: Data(json.utf8))
        else { throw ReaderError.extractionFailed }
        if let labels = Self.languageLabels(primary: settings.primaryLanguage, content: article.content) {
            _ = try? await webView.evaluateStringResult(
                ReaderTemplate.call("glossoSetLanguages", labels.translated, labels.original))
        }
        return blocks
    }

    nonisolated static func languageLabels(
        primary: PrimaryLanguage, content: String
    ) -> (translated: String, original: String)? {
        let text = content
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 40 else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(text.prefix(6000)))
        guard let (source, confidence) = recognizer.languageHypotheses(withMaximum: 3)
                .max(by: { $0.value < $1.value }),
              confidence >= 0.8, source != primary.nl else { return nil }
        // "zh-Hans" → "ZH": the region/script tail is noise at pill size.
        let code = { (language: NLLanguage) -> String in
            language.rawValue.split(separator: "-").first.map(String.init)?.uppercased()
                ?? language.rawValue.uppercased()
        }
        return (code(primary.nl), code(source))
    }

    private func translateTitle(_ title: String, in webView: WKWebView) async -> String {
        var final = title
        let hasTitle = !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasTitle, !Self.isConfidently(in: settings.primaryLanguage, title) {
            setStatus(loc("Tłumaczę tytuł…", "Translating title…"), in: webView)
            let translated = ReaderTemplate.unwrap(
                (try? await llm.translateBlock(html: title, into: settings.primaryLanguage, model: settings.activeModel)) ?? "")
            if Task.isCancelled { return final }
            if !translated.isEmpty { final = translated }
        }
        await applyTitle(final, in: webView)
        return final
    }

    private func applyTitle(_ title: String, in webView: WKWebView) async {
        _ = try? await webView.evaluateStringResult(ReaderTemplate.call("glossoSetTitle", title))
        window?.title = title
    }

    private func summarize(in webView: WKWebView) async -> String {
        // ponytail: 6000-char cap — the summary reads the article's head; raise
        // it if long-article summaries come out thin. Sliced in JS so a long
        // article isn't bridged out of the web process just to be truncated.
        guard let text = try? await webView.evaluateStringResult(
                "document.getElementById('glosso-content').textContent.slice(0, 6000)"),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return "" }
        setStatus(loc("Streszczam…", "Summarizing…"), in: webView)
        guard let summary = try? await llm.readerSummary(of: text, into: settings.primaryLanguage, model: settings.activeModel) else { return "" }
        if Task.isCancelled { return "" }
        let cleaned = ReaderTemplate.unwrap(summary)
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

    /// The limiter blocks rather than failing, so without this the status bar would simply stop moving mid-article.
    func cloudWait(_ seconds: TimeInterval) {
        guard translating, let webView else { return }
        setStatus(loc("Czekam na limit Google AI… (\(Int(seconds.rounded(.up))) s)",
                      "Waiting for the Google AI rate limit… (\(Int(seconds.rounded(.up))) s)"), in: webView)
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
            setStatus("", in: webView)
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
        var done = translatable.count - pending.count
        let batchSize = settings.provider == .cloud ? Self.cloudBatchSize : 1
        for batch in ReaderTemplate.batches(pending, maxCount: batchSize) {
            if Task.isCancelled { return nil }
            setStatus(loc("Tłumaczę… (\(done + 1)/\(translatable.count))",
                          "Translating… (\(done + 1)/\(translatable.count))"), in: webView)
            var batched: [Int: String] = [:]
            if batch.count > 1 {
                // A batch that throws or fails the round trip is discarded whole and costs no failure — its blocks retry one by one below.
                batched = (try? await llm.translateBlocks(batch.map { (id: $0.id, html: $0.html) },
                                                          into: settings.primaryLanguage,
                                                          model: settings.activeModel)) ?? [:]
                if Task.isCancelled { return nil }
            }
            for block in batch {
                if Task.isCancelled { return nil }
                let translated: String
                if let fromBatch = batched[block.id] {
                    translated = ReaderTemplate.unwrap(fromBatch)
                } else {
                    do {
                        translated = ReaderTemplate.unwrap(
                            try await llm.translateBlock(html: block.html, into: settings.primaryLanguage, model: settings.activeModel))
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
                                          "Translation stopped — the rest stays in the original language.") + detail, in: webView)
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
                          "Translated with \(failed) blocks skipped (kept in the original language)."), in: webView)
            return nil
        }
        setStatus("", in: webView)
        return applied
    }

    private static func isConfidently(in primary: PrimaryLanguage, _ html: String) -> Bool {
        let text = html
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 40 else { return false }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return (recognizer.languageHypotheses(withMaximum: 3)[primary.nl] ?? 0) >= 0.8
    }

    fileprivate func setChatPanel(open: Bool, animated: Bool = true) {
        guard open != chatPanelOpen, let window else { return }
        chatPanelOpen = open
        var frame = chatFrameTarget ?? window.frame
        if open {
            let visible = window.screen?.visibleFrame
            let target = min(frame.width + Self.chatPanelWidth, visible?.width ?? .greatestFiniteMagnitude)
            chatWidthDelta = target - frame.width
            frame.size.width = target
            if let visible, frame.maxX > visible.maxX {
                frame.origin.x = max(visible.minX, visible.maxX - frame.width)
            }
        } else {
            frame.size.width -= chatWidthDelta
            chatWidthDelta = 0
        }
        if animated {
            let target = frame
            chatAnimSeq += 1
            let seq = chatAnimSeq
            chatFrameTarget = target
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(target, display: true)
            }, completionHandler: { [weak self] in
                if self?.chatAnimSeq == seq { self?.chatFrameTarget = nil }
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

    fileprivate func suggestQuestions() {
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
                let answer = ReaderTemplate.unwrap(try await self.llm.askArticle(
                    question: question, history: Array(self.chatHistory.suffix(4)), article: context,
                    into: self.settings.primaryLanguage, model: self.settings.activeModel))
                if Task.isCancelled { return }
                self.chatHistory.append((question, answer))
                _ = try? await webView.evaluateStringResult(ReaderTemplate.call("glossoAnswer", answer, ""))
            } catch {
                if Task.isCancelled { return }
                let message = (error as? TranslationError)?.userMessage
                    ?? loc("Nie udało się uzyskać odpowiedzi.", "Could not get an answer.")
                _ = try? await webView.evaluateStringResult(ReaderTemplate.call("glossoAnswer", "", message))
            }
        }
    }

    private func setStatus(_ message: String, in webView: WKWebView) {
        webView.evaluateJavaScript(ReaderTemplate.call("glossoStatus", message), completionHandler: nil)
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
        // Legacy bare-string form kept for the refresh pill; the chat posts dicts.
        if message.body as? String == "refresh" { controller?.refreshCurrentArticle(); return }
        guard let dict = message.body as? [String: String] else { return }
        switch dict["action"] {
        case "suggest": controller?.suggestQuestions()
        case "ask": if let question = dict["question"], !question.isEmpty { controller?.answer(question: question) }
        case "panel": controller?.setChatPanel(open: dict["open"] == "1")
        default: break
        }
    }
}
