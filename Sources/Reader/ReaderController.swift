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

    private var window: NSWindow?
    private var webView: WKWebView?
    private var translationTask: Task<Void, Never>?
    private var closeObserver: NSObjectProtocol?

    init(llm: any LLMClient, settings: SettingsStore) {
        self.llm = llm
        self.settings = settings
    }

    func show(_ url: URL) {
        translationTask?.cancel()
        let webView = ensureWindow(titled: url.host() ?? "Artykuł")
        translationTask = Task { @MainActor [weak self] in
            await self?.run(url: url, in: webView)
        }
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
            setStatus("Wczytuję artykuł…", in: webView)
            let article = try await extractor.extract(from: url)
            if Task.isCancelled { return }
            window?.title = article.title
            let blocks = try await insertArticle(article, in: webView)
            await translateTitle(article.title, in: webView)
            if Task.isCancelled { return }
            await summarize(in: webView)
            if Task.isCancelled { return }
            try await translate(blocks: blocks, in: webView)
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

    private func insertArticle(_ article: ArticleExtractor.ExtractedArticle, in webView: WKWebView) async throws -> [ReaderTemplate.Block] {
        let call = ReaderTemplate.call("glossoSetArticle", article.title, article.byline ?? "", article.content)
        guard let json = try await webView.evaluateStringResult(call),
              let blocks = try? JSONDecoder().decode([ReaderTemplate.Block].self, from: Data(json.utf8))
        else { throw ReaderError.extractionFailed }
        return blocks
    }

    // Best-effort: any failure leaves the original title in place (and un-dims
    // it) — a title must never block the article's translation.
    private func translateTitle(_ title: String, in webView: WKWebView) async {
        var final = title
        if !Self.isConfidentlyPolish(title) {
            setStatus("Tłumaczę tytuł…", in: webView)
            let translated = ReaderTemplate.stripFences(
                (try? await llm.translateBlock(html: title, model: settings.modelName)) ?? "")
            if Task.isCancelled { return }
            if !translated.isEmpty { final = translated }
        }
        _ = try? await webView.evaluateStringResult(ReaderTemplate.call("glossoSetTitle", final))
        window?.title = final
    }

    // Best-effort tl;dr under the title: a failure just leaves the section
    // hidden, never blocks the block translation.
    private func summarize(in webView: WKWebView) async {
        guard let text = try? await webView.evaluateStringResult(
                "document.getElementById('glosso-content').textContent"),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        setStatus("Streszczam…", in: webView)
        // ponytail: 6000-char cap — the summary reads the article's head; raise
        // it if long-article summaries come out thin.
        guard let summary = try? await llm.readerSummary(of: String(text.prefix(6000)), model: settings.modelName) else { return }
        if Task.isCancelled { return }
        let cleaned = ReaderTemplate.stripFences(summary)
        if !cleaned.isEmpty {
            _ = try? await webView.evaluateStringResult(ReaderTemplate.call("glossoSetSummary", cleaned))
        }
    }

    private func translate(blocks: [ReaderTemplate.Block], in webView: WKWebView) async throws {
        let translatable = blocks.filter(\.translate)
        for (index, block) in translatable.enumerated() {
            if Task.isCancelled { return }
            setStatus("Tłumaczę… (\(index + 1)/\(translatable.count))", in: webView)
            if Self.isConfidentlyPolish(block.html) {
                _ = try? await webView.evaluateStringResult(
                    ReaderTemplate.call("glossoApply", String(block.id), block.html))
                continue
            }
            let translated: String
            do {
                translated = ReaderTemplate.stripFences(
                    try await llm.translateBlock(html: block.html, model: settings.modelName))
            } catch is CancellationError {
                return
            } catch TranslationError.cancelled {
                return
            } catch {
                // A mid-article model failure keeps what's done; the untranslated
                // tail stays readable in the original language — un-dimmed, or the
                // "readable" claim is a lie. A superseded task must not paint over
                // its successor in the shared webview.
                if Task.isCancelled { return }
                _ = try? await webView.evaluateStringResult("glossoAbort()")
                let detail = (error as? TranslationError).map { " " + $0.userMessage } ?? ""
                setStatus("Tłumaczenie przerwane — reszta w oryginale." + detail, in: webView)
                return
            }
            if Task.isCancelled { return }
            // An empty result must still un-dim its block — re-apply the original.
            _ = try? await webView.evaluateStringResult(ReaderTemplate.call(
                "glossoApply", String(block.id), translated.isEmpty ? block.html : translated))
        }
        if !Task.isCancelled { setStatus("", in: webView) }
    }

    // The prompt's "already Polish → unchanged" costs a full generation per block;
    // a confident local read skips that round-trip entirely. Unconstrained
    // recognition (not DirectionDetector's PL-vs-second constraint) so kindred
    // Slavic languages can't masquerade as Polish, and only on text long enough
    // to trust — short or ambiguous blocks still go to the model.
    private static func isConfidentlyPolish(_ html: String) -> Bool {
        let text = html
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 40 else { return false }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return (recognizer.languageHypotheses(withMaximum: 3)[.polish] ?? 0) >= 0.8
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
        let webView = WKWebView(frame: .zero)
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
        window = nil
        webView = nil
    }
}
