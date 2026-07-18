import AppKit
import NaturalLanguage
import WebKit

/// The reader window (feature: double Cmd+C on an article URL). A normal titled,
/// resizable NSWindow — unlike the popup's borderless FloatingPanel — showing the
/// reader template in a WKWebView. One window: a new show() cancels the in-flight
/// translation and reuses it. The window is also the error surface; there is no
/// fallback to the translation popup.
@MainActor
final class ReaderController: ReaderPresenting {
    private let llm: any LLMClient
    private let settings: SettingsStore
    private let extractor = ArticleExtractor()
    private let cache = ReaderCache()

    private var window: NSWindow?
    private var webView: WKWebView?
    private var translationTask: Task<Void, Never>?
    private var closeObserver: NSObjectProtocol?
    private var currentURL: URL?

    init(llm: any LLMClient, settings: SettingsStore) {
        self.llm = llm
        self.settings = settings
    }

    func show(_ url: URL) {
        currentURL = url
        translationTask?.cancel()
        let webView = ensureWindow(titled: url.host() ?? loc("Artykuł", "Article"))
        translationTask = Task { @MainActor [weak self] in
            await self?.run(url: url, in: webView)
        }
    }

    // The template's re-translate pill: drop the cached entry and re-run the
    // full pipeline (show() cancels the in-flight task; post-remove it's a miss).
    fileprivate func refreshCurrentArticle() {
        guard let currentURL else { return }
        cache.remove(currentURL, primary: settings.primaryLanguage)
        show(currentURL)
    }

    private func run(url: URL, in webView: WKWebView) async {
        do {
            let watcher = NavigationWatcher()
            webView.navigationDelegate = watcher
            // baseURL = the article URL: costs nothing and resolves any relative
            // URL Readability missed (images come back absolute anyway).
            try await watcher.awaitNavigation(in: webView, timeout: .seconds(5)) {
                webView.loadHTMLString(ReaderTemplate.html, baseURL: url)
            }
            if let entry = cache.load(url, primary: settings.primaryLanguage) {
                try await replay(entry, in: webView)
                return
            }
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
            // A superseded task can reach here with a real error (cancellation is
            // swallowed inside extract's sleeps) — it must not paint over the new
            // show()'s content in the shared webview.
            if !Task.isCancelled { setStatus(error.message, in: webView) }
        } catch {
            if !Task.isCancelled { setStatus(ReaderError.fetchFailed.message, in: webView) }
        }
    }

    // A cache hit re-runs the exact insert path (sanitization, deterministic block
    // ids) over the stored original, then paints the stored title/summary/blocks —
    // zero fetch, zero LLM.
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
        return blocks
    }

    // Best-effort: any failure leaves the original title in place (and un-dims
    // it) — a title must never block the article's translation. Returns the title
    // it applied, so the caller can cache it.
    private func translateTitle(_ title: String, in webView: WKWebView) async -> String {
        var final = title
        // An empty title must not reach the model: it answers an empty block with
        // whatever it likes, and that would become the article's heading.
        let hasTitle = !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasTitle, !Self.isConfidently(in: settings.primaryLanguage, title) {
            setStatus(loc("Tłumaczę tytuł…", "Translating title…"), in: webView)
            let translated = ReaderTemplate.stripFences(
                (try? await llm.translateBlock(html: title, into: settings.primaryLanguage, model: settings.modelName)) ?? "")
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

    // Best-effort tl;dr under the title: a failure just leaves the section
    // hidden, never blocks the block translation. Returns the applied summary
    // ("" when none), so the caller can cache it.
    private func summarize(in webView: WKWebView) async -> String {
        // ponytail: 6000-char cap — the summary reads the article's head; raise
        // it if long-article summaries come out thin. Sliced in JS so a long
        // article isn't bridged out of the web process just to be truncated.
        guard let text = try? await webView.evaluateStringResult(
                "document.getElementById('glosso-content').textContent.slice(0, 6000)"),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return "" }
        setStatus(loc("Streszczam…", "Summarizing…"), in: webView)
        guard let summary = try? await llm.readerSummary(of: text, into: settings.primaryLanguage, model: settings.modelName) else { return "" }
        if Task.isCancelled { return "" }
        let cleaned = ReaderTemplate.stripFences(summary)
        if !cleaned.isEmpty {
            _ = try? await webView.evaluateStringResult(ReaderTemplate.call("glossoSetSummary", cleaned))
        }
        return cleaned
    }

    // Returns the applied HTML per block id on a complete run, nil on any early
    // exit (cancel, model failure) — only a complete run is cacheable.
    private func translate(blocks: [ReaderTemplate.Block], in webView: WKWebView) async throws -> [Int: String]? {
        var applied: [Int: String] = [:]
        let translatable = blocks.filter(\.translate)
        // An article already in the primary language would go to the model block
        // by block as a degenerate "output it unchanged" self-translation — the
        // per-block guard below misses short blocks (<40 chars), and small models
        // loop on exactly those calls. One confident article-level read skips the
        // model entirely.
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
        var failed = 0
        var consecutiveFailures = 0
        for (index, block) in translatable.enumerated() {
            if Task.isCancelled { return nil }
            setStatus(loc("Tłumaczę… (\(index + 1)/\(translatable.count))",
                          "Translating… (\(index + 1)/\(translatable.count))"), in: webView)
            if Self.isConfidently(in: settings.primaryLanguage, block.html) {
                _ = try? await webView.evaluateStringResult(
                    ReaderTemplate.call("glossoApply", String(block.id), block.html))
                applied[block.id] = block.html
                continue
            }
            let translated: String
            do {
                translated = ReaderTemplate.stripFences(
                    try await llm.translateBlock(html: block.html, into: settings.primaryLanguage, model: settings.modelName))
            } catch is CancellationError {
                return nil
            } catch TranslationError.cancelled {
                return nil
            } catch {
                // One misbehaving block (runaway generation, truncation) must not
                // cost the rest of the article: it keeps its original, un-dimmed,
                // and the loop moves on. Two failures in a row mean the engine
                // itself is gone — then stop instead of grinding through every
                // remaining block at full timeout. A superseded task must not
                // paint over its successor in the shared webview.
                if Task.isCancelled { return nil }
                failed += 1
                consecutiveFailures += 1
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
            consecutiveFailures = 0
            if Task.isCancelled { return nil }
            // An empty result must still un-dim its block — re-apply the original.
            let html = translated.isEmpty ? block.html : translated
            _ = try? await webView.evaluateStringResult(ReaderTemplate.call(
                "glossoApply", String(block.id), html))
            applied[block.id] = html
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

    // The prompt's "already in the target → unchanged" costs a full generation per
    // block; a confident local read skips that round-trip entirely. Unconstrained
    // recognition (not DirectionDetector's constrained set) so kindred languages
    // can't masquerade as the target, and only on text long enough to trust —
    // short or ambiguous blocks still go to the model.
    private static func isConfidently(in primary: PrimaryLanguage, _ html: String) -> Bool {
        let text = html
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 40 else { return false }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return (recognizer.languageHypotheses(withMaximum: 3)[primary.nl] ?? 0) >= 0.8
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

    // Dropping the strong refs on close lets the window, the webview and its
    // WebContent process (the whole rendered article) deallocate — a menu-bar
    // app must not keep a closed page resident. The next show() recreates the
    // pair; the frame autosave name preserves size and position.
    private func windowWillClose() {
        translationTask?.cancel()
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = nil
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "glosso")
        window = nil
        webView = nil
    }
}

// WKUserContentController retains its handler strongly — this proxy holds the
// controller weakly so the pair can't retain-cycle.
@MainActor
private final class ReaderScriptMessageProxy: NSObject, WKScriptMessageHandler {
    private weak var controller: ReaderController?

    init(controller: ReaderController) {
        self.controller = controller
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.body as? String == "refresh" else { return }
        controller?.refreshCurrentArticle()
    }
}
