import AppKit
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
            try await translate(blocks: blocks, in: webView)
        } catch is CancellationError {
        } catch let error as ReaderError {
            setStatus(error.message, in: webView)
        } catch {
            setStatus(ReaderError.fetchFailed.message, in: webView)
        }
    }

    private func insertArticle(_ article: ArticleExtractor.ExtractedArticle, in webView: WKWebView) async throws -> [ReaderTemplate.Block] {
        let call = ReaderTemplate.call("glossoSetArticle", article.title, article.byline ?? "", article.content)
        guard let json = try await webView.evaluateStringResult(call),
              let blocks = try? JSONDecoder().decode([ReaderTemplate.Block].self, from: Data(json.utf8))
        else { throw ReaderError.extractionFailed }
        return blocks
    }

    private func translate(blocks: [ReaderTemplate.Block], in webView: WKWebView) async throws {
        let translatable = blocks.filter(\.translate)
        for (index, block) in translatable.enumerated() {
            if Task.isCancelled { return }
            setStatus("Tłumaczę… (\(index + 1)/\(translatable.count))", in: webView)
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
                // tail stays readable in the original language.
                setStatus("Tłumaczenie przerwane — reszta w oryginale.", in: webView)
                return
            }
            if Task.isCancelled { return }
            if !translated.isEmpty {
                _ = try? await webView.evaluateStringResult(ReaderTemplate.call("glossoApply", String(block.id), translated))
            }
        }
        setStatus("", in: webView)
    }

    private func setStatus(_ message: String, in webView: WKWebView) {
        webView.evaluateJavaScript(ReaderTemplate.call("glossoStatus", message), completionHandler: nil)
    }

    private func ensureWindow(titled title: String) -> WKWebView {
        if let window, let webView {
            window.title = title
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return webView
        }
        let webView = WKWebView(frame: .zero)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = webView
        window.title = title
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("GlossoReader")
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.translationTask?.cancel() }
        }
        self.window = window
        self.webView = webView
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return webView
    }
}
