import Foundation
import WebKit

enum ReaderError: Error {
    case fetchFailed
    case extractionFailed

    var message: String {
        switch self {
        case .fetchFailed: "Nie udało się wczytać strony."
        case .extractionFailed: "Nie udało się znaleźć artykułu na tej stronie."
        }
    }
}

/// Fetches an article URL in a hidden WKWebView and extracts the readable
/// article with the vendored Mozilla Readability.js. The webview does the
/// fetching (so JS-rendered pages work for free) and Readability's
/// `_fixRelativeUris` runs against the live document, so image `src`s in the
/// returned content are already absolute — hotlinking needs no post-processing.
@MainActor
final class ArticleExtractor {
    struct ExtractedArticle: Decodable {
        var title: String
        var byline: String?
        var content: String
    }

    private static let readabilityJS: String = {
        guard let url = Bundle.main.url(forResource: "Readability", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8)
        else { return "" }
        return source
    }()

    // Returns a JSON string, or "" when Readability found no article — never
    // null/undefined, which evaluateJavaScript reports awkwardly.
    private static let driverJS = """
    (function() {
      const article = new Readability(document.cloneNode(true)).parse();
      if (!article || !article.content) { return ""; }
      return JSON.stringify({
        title: article.title || document.title,
        byline: article.byline,
        content: article.content
      });
    })()
    """

    func extract(from url: URL) async throws -> ExtractedArticle {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
        let navigator = NavigationWatcher()
        webView.navigationDelegate = navigator

        try await navigator.awaitNavigation(in: webView, timeout: .seconds(20)) {
            webView.load(URLRequest(url: url))
        }
        // ponytail: fixed 500ms settle for client-side rendering; a readiness
        // probe replaces it if popular pages still come up short.
        try? await Task.sleep(for: .milliseconds(500))

        if let article = try await runReadability(in: webView) { return article }
        // JS-heavy pages may hydrate late — one more chance, then give up.
        try? await Task.sleep(for: .milliseconds(1500))
        if let article = try await runReadability(in: webView) { return article }
        throw ReaderError.extractionFailed
    }

    private func runReadability(in webView: WKWebView) async throws -> ExtractedArticle? {
        let script = Self.readabilityJS + "\n" + Self.driverJS
        guard let json = try await webView.evaluateStringResult(script), !json.isEmpty
        else { return nil }
        return try? JSONDecoder().decode(ExtractedArticle.self, from: Data(json.utf8))
    }
}

extension WKWebView {
    /// evaluateJavaScript narrowed to a String result: the JS value is collapsed
    /// to `String?` inside the completion handler, because resuming a continuation
    /// with the non-Sendable `Any?` trips Swift 6 strict concurrency.
    func evaluateStringResult(_ script: String) async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            evaluateJavaScript(script) { value, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: value as? String)
                }
            }
        }
    }
}

/// Bridges one WKWebView navigation into async/await, resuming exactly once —
/// on didFinish/didFail, on the watchdog timeout, or on task cancellation (a
/// hung navigation must not strand the reader's Task). Kept alive by the caller
/// for the duration of the load (the webview's delegate reference is weak).
/// Shared by the extractor's hidden fetch and the reader window's template load.
@MainActor
final class NavigationWatcher: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    /// Awaits the navigation `start` kicks off (`load`, `loadHTMLString`, …) in
    /// `webView`, whose `navigationDelegate` the caller must have pointed here.
    func awaitNavigation(in webView: WKWebView, timeout: Duration, start: () -> Void) async throws {
        let watchdog = Task { @MainActor [weak self, weak webView] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            webView?.stopLoading()
            self?.finish(.failure(ReaderError.fetchFailed))
        }
        defer { watchdog.cancel() }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                self.continuation = continuation
                start()
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(.failure(CancellationError())) }
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finish(.success(()))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(ReaderError.fetchFailed))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(.failure(ReaderError.fetchFailed))
    }
}
