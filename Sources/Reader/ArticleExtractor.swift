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
            assertionFailure("Readability.js missing from the app bundle")
            return ""
        }
        return source
    }()

    private static let driverJS = """
    (function() {
      // Mirrors Readability's own REGEXPS.videos, so we only ever revive what it already agrees to keep.
      const VIDEO = /\\/\\/(www\\.)?((dailymotion|youtube|youtube-nocookie|player\\.vimeo|v\\.qq)\\.com|player\\.twitch\\.tv)/i;
      const isVideoEmbed = el => Array.from(el.attributes).some(a => VIDEO.test(a.value));
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
      // Consent-gated players carry their URL in data-src only; without this the reader shows an empty box.
      for (const frame of doc.querySelectorAll('iframe')) {
        const src = frame.getAttribute('src') || '';
        if (src !== '' && src !== 'about:blank' && !src.startsWith('data:')) { continue; }
        const source = ['data-src-fallback', 'data-src', 'data-lazy-src']
          .map(a => frame.getAttribute(a)).find(v => v && VIDEO.test(v));
        if (source) { frame.setAttribute('src', source.replace(/\\/\\/(www\\.)?youtube\\.com\\//, '//www.youtube-nocookie.com/')); }
      }
      for (const aside of doc.querySelectorAll('aside')) {
        const embedded = Array.from(aside.querySelectorAll('iframe, object, embed')).some(isVideoEmbed);
        if (!embedded && aside.querySelectorAll('img').length === 0) { continue; }
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

@MainActor
final class NavigationWatcher: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?
    private var expected: WKNavigation?

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
