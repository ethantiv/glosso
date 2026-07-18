import Foundation
import WebKit

enum ReaderError: Error {
    case fetchFailed
    case extractionFailed

    var message: String {
        switch self {
        case .fetchFailed: loc("Nie udało się wczytać strony.", "Couldn't load the page.")
        case .extractionFailed: loc("Nie udało się znaleźć artykułu na tej stronie.", "Couldn't find an article on this page.")
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
        else {
            // A missing resource is a packaging bug (project.yml's buildPhase:
            // resources wiring) — crash in debug; in release runReadability turns
            // it into extractionFailed instead of a misleading network error.
            assertionFailure("Readability.js missing from the app bundle")
            return ""
        }
        return source
    }()

    // Returns a JSON string, or "" when Readability found no article — never
    // null/undefined, which evaluateJavaScript reports awkwardly.
    //
    // Three pre-passes run before Readability so the extract matches what a
    // human actually sees on real-world pages:
    // - CSS-hidden text removal: Readability judges visibility only by inline
    //   styles and hidden/aria-hidden attributes — stylesheet hiding (a mobile
    //   variant under `.for-mobile { display:none }`, say) is invisible to it,
    //   so phantom text leaks into the extract. We run in a real browser, so
    //   mark elements the engine actually doesn't render (checkVisibility on
    //   the LIVE document — a clone has no computed styles) and drop them from
    //   the clone. Subtrees containing images are exempt: carousels hide
    //   inactive slides and some lazy loaders hide images until loaded, and
    //   losing pictures costs more than a duplicated one — phantom *text*
    //   never contains an <img>.
    // - Lazy-loader promotion: sites park the real image URL in data-src/
    //   data-srcset until the image scrolls into view — which in this hidden,
    //   never-scrolled webview is never. Promote those attributes so the
    //   extracted content carries real URLs.
    // - Gallery rescue: Readability unconditionally strips every <aside>, which
    //   takes image galleries marked up as <aside class="gallery"> with it.
    //   An aside dominated by images (little text, and next to none of it in
    //   links) is a gallery, not boilerplate — convert it to <figure>, which
    //   Readability keeps. Link-heavy asides ("Related Articles") still die.
    // - Lightbox unwrap: Readability cleans every <button> with its subtree,
    //   and sites wrap zoomable photos in buttons — unwrap image-bearing
    //   buttons so the photo survives the clean.
    //
    // And two post-passes on the extracted content:
    // - Link-dominated removal: "related articles" lists survive Readability
    //   when they sit inside the text container. Blocks whose text is ≥80%
    //   anchor text are boilerplate, not content — and each would become a
    //   markup-dense translation block that small models loop on. The ratio is
    //   text-based, so an image-only anchor (no text) is never touched.
    // - Lead-image rescue: a hero image outside Readability's top candidate
    //   (e.g. a separate header container) is lost entirely. If the cleaned
    //   content has no image but the page renders its og:image, prepend it as
    //   a figure — the render check keeps generic og:image logos out.
    private static let driverJS = """
    (function() {
      if (typeof document.body.checkVisibility === 'function') {
        for (const el of document.body.querySelectorAll('*')) {
          if (el.closest('[data-glosso-hidden]')) { continue; }
          if (el.checkVisibility({checkVisibilityCSS: true})) { continue; }
          if (el.tagName === 'IMG' || el.querySelector('img')) { continue; }
          el.setAttribute('data-glosso-hidden', '');
        }
      }
      const doc = document.cloneNode(true);
      for (const el of doc.querySelectorAll('[data-glosso-hidden]')) { el.remove(); }
      const LAZY = ['data-src', 'data-lazy-src', 'data-original', 'data-url'];
      for (const img of doc.querySelectorAll('img')) {
        const candidate = LAZY.map(a => img.getAttribute(a)).find(v => v && /^(https?:|\\/)/.test(v));
        const src = img.getAttribute('src') || '';
        if (candidate && (src === '' || src.startsWith('data:'))) { img.setAttribute('src', candidate); }
        const srcset = img.getAttribute('data-srcset') || img.getAttribute('data-lazy-srcset');
        if (srcset && !img.getAttribute('srcset')) { img.setAttribute('srcset', srcset); }
      }
      for (const aside of doc.querySelectorAll('aside')) {
        if (aside.querySelectorAll('img').length === 0) { continue; }
        const text = aside.textContent.trim();
        const linkText = Array.from(aside.querySelectorAll('a')).map(a => a.textContent.trim()).join('');
        if (text.length - linkText.length <= 120 && linkText.length <= 40) {
          const figure = doc.createElement('figure');
          while (aside.firstChild) { figure.appendChild(aside.firstChild); }
          aside.replaceWith(figure);
        }
      }
      for (const button of doc.querySelectorAll('button')) {
        if (!button.querySelector('img, picture')) { continue; }
        while (button.firstChild) { button.parentNode.insertBefore(button.firstChild, button); }
        button.remove();
      }
      const article = new Readability(doc).parse();
      if (!article || !article.content) { return ""; }
      const tmp = document.implementation.createHTMLDocument('');
      tmp.body.innerHTML = article.content;
      // Block containers only: an inline wrapper (<strong><a>…</a></strong>)
      // inside a paragraph is all-anchor by definition and must stay. Figures
      // are exempt too — a photo with a credit-link caption is content.
      const BLOCKS = 'p, li, ul, ol, div, section, aside, blockquote, h1, h2, h3, h4, h5, h6';
      for (const el of tmp.body.querySelectorAll(BLOCKS)) {
        if (!el.isConnected || el.closest('figure')) { continue; }
        const text = el.textContent.trim();
        if (text.length === 0 || !el.querySelector('a')) { continue; }
        let linkText = 0;
        for (const a of el.querySelectorAll('a')) { linkText += a.textContent.trim().length; }
        if (linkText / text.length >= 0.8) { el.remove(); }
      }
      for (const list of tmp.body.querySelectorAll('ul, ol')) {
        if (!list.querySelector('li')) { list.remove(); }
      }
      if (!tmp.body.querySelector('img')) {
        const og = document.querySelector('meta[property="og:image"], meta[name="twitter:image"]');
        const url = og && og.content;
        if (url && Array.from(document.images).some(i => i.src === url || i.currentSrc === url)) {
          const figure = tmp.createElement('figure');
          const img = tmp.createElement('img');
          img.src = url;
          figure.appendChild(img);
          tmp.body.insertBefore(figure, tmp.body.firstChild);
        }
      }
      return JSON.stringify({
        title: article.title || document.title,
        byline: article.byline,
        content: tmp.body.innerHTML
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
        guard !Self.readabilityJS.isEmpty else { throw ReaderError.extractionFailed }
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
    private var expected: WKNavigation?

    /// Awaits the navigation `start` kicks off (`load`, `loadHTMLString`, …) in
    /// `webView`, whose `navigationDelegate` the caller must have pointed here.
    /// `start` returns that navigation so callbacks for a superseded load in the
    /// same webview (e.g. the reader window's previous show(), cancelled by ours)
    /// can be told apart from ours and ignored.
    func awaitNavigation(in webView: WKWebView, timeout: Duration, start: () -> WKNavigation?) async throws {
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
                self.expected = start()
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(.failure(CancellationError())) }
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        continuation?.resume(with: result)
        continuation = nil
        expected = nil
    }

    // WebKit occasionally hands a nil navigation — accept it rather than strand
    // the continuation (the watchdog would still fire, but seconds later).
    private func matches(_ navigation: WKNavigation!) -> Bool {
        navigation == nil || expected == nil || navigation === expected
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if matches(navigation) { finish(.success(())) }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if matches(navigation) { finish(.failure(ReaderError.fetchFailed)) }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if matches(navigation) { finish(.failure(ReaderError.fetchFailed)) }
    }
}
