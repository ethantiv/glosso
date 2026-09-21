import Foundation
import Testing
import WebKit
@testable import Glosso

@MainActor
@Suite(.timeLimit(.minutes(1))) struct ReaderWebSecurityTests {
    private func makeWeb() async throws -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let rules = try await WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "GlossoOfflineSecurityTests",
            encodedContentRuleList: #"[{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}}]"#)
        if let rules { configuration.userContentController.add(rules) }
        let web = WKWebView(frame: .zero, configuration: configuration)
        let watcher = NavigationWatcher()
        web.navigationDelegate = watcher
        try await watcher.awaitNavigation(in: web, timeout: .seconds(5)) {
            web.loadHTMLString(ReaderTemplate.html, baseURL: nil)
        }
        _ = try await web.evaluateReaderString(ReaderWebSecurity.bootstrap(
            session: "test-session", sourceURL: URL(string: "https://example.com/path/article")))
        return web
    }

    @Test func rejectsExecutableHTMLBeforeItEntersTheDocument() async throws {
        let web = try await makeWeb()
        let payload = #"<p id="glosso-chat-input" class="glosso-dual" data-glosso-id="3" style="position:fixed">Text<a href="java&#x09;script:window.pwned=1">bad</a><img src="x" onerror="window.pwned=1"></p><iframe src="data:text/html,<script>window.pwned=1</script>"></iframe><svg onload="window.pwned=1"></svg><form><input name="glosso"></form><script>window.pwned=1</script>"#
        _ = try await web.evaluateReaderString(ReaderTemplate.call("glossoSetArticle", "Title", "", payload))
        let result = try await web.evaluateReaderString("""
        JSON.stringify({pwned: !!window.pwned, bad: document.querySelector('#glosso-content').querySelectorAll(
          'script,iframe,svg,form,input,[onerror],[style],[id]').length,
          href: document.querySelector('#glosso-content a').getAttribute('href')})
        """)
        #expect(result == #"{"pwned":false,"bad":0,"href":null}"#)
        #expect(try await web.evaluateReaderString("String(document.querySelectorAll('#glosso-chat-input').length)") == "1")
    }

    @Test func preservesFormattingAndResolvesMediaSafely() async throws {
        let web = try await makeWeb()
        let payload = #"<p>Hello <em>world</em> <a href="../next">next</a></p><table><tr><td>cell</td></tr></table><pre><code>let a = 1</code></pre><img src="/image.png"><iframe src="https://www.youtube-nocookie.com/embed/123" sandbox="allow-top-navigation allow-popups"></iframe><iframe src="https://youtube.com.evil.test/embed/123"></iframe>"#
        _ = try await web.evaluateReaderString(ReaderTemplate.call("glossoSetArticle", "T", "", payload))
        #expect(try await web.evaluateReaderString("document.querySelector('#glosso-content a').href") == "https://example.com/next")
        #expect(try await web.evaluateReaderString("document.querySelector('#glosso-content img').src") == "https://example.com/image.png")
        #expect(try await web.evaluateReaderString("String(document.querySelectorAll('#glosso-content iframe').length)") == "1")
        #expect(try await web.evaluateReaderString("document.querySelector('iframe').getAttribute('sandbox')") == "allow-scripts allow-same-origin")
        #expect(try await web.evaluateReaderString("document.querySelector('code').textContent") == "let a = 1")
        #expect(try await web.evaluateReaderString("document.querySelector('td').textContent") == "cell")
    }

    @Test(arguments: ["javascript:alert(1)", "java\tscript:alert(1)", "file:///tmp/test", "data:text/html,test", "data:image/svg+xml,<svg/>"])
    func unsafeURLsCannotReachLinkOrMediaAttributes(url: String) async throws {
        let web = try await makeWeb()
        let html = "<a href='" + url + "'>link</a><img src='" + url + "'><video src='" + url + "'></video>"
        _ = try await web.evaluateReaderString(ReaderTemplate.call("glossoSetArticle", "T", "", html))
        #expect(try await web.evaluateReaderString("String(document.querySelectorAll('#glosso-content [href], #glosso-content [src]').length)") == "0")
    }

    @Test func linkClicksOpenExternallyAndLeaveTheReaderDocumentIntact() async throws {
        let web = try await makeWeb()
        let navigator = ReaderNavigationDelegate()
        defer { withExtendedLifetime(navigator) {} }
        try #require(navigator.responds(to: NSSelectorFromString("webView:decidePolicyForNavigationAction:decisionHandler:")))
        let opened = StreamGate()
        var destination: URL?
        navigator.openExternal = { destination = $0; opened.release() }
        web.navigationDelegate = navigator
        web.configuration.userContentController.removeAllContentRuleLists()
        _ = try await web.evaluateReaderString(ReaderTemplate.call("glossoSetArticle", "T", "", "<a href='/next'>Next</a>"))
        _ = try await web.evaluateReaderString("document.querySelector('#glosso-content a').click(); 'clicked'")
        await opened.wait()
        #expect(destination?.absoluteString == "https://example.com/next")
        #expect(try await web.evaluateReaderString("document.querySelector('#glosso-title').textContent") == "T")
        #expect(web.url?.absoluteString == "about:blank")
    }

    @Test func translatedAndReplayedHTMLUseTheSameSanitizer() async throws {
        let web = try await makeWeb()
        _ = try await web.evaluateReaderString(ReaderTemplate.call("glossoSetArticle", "T", "", "<p>Original</p>"))
        _ = try await web.evaluateReaderString(ReaderTemplate.call("glossoApply", "0",
            #"<strong>Translated</strong><a href="file:///etc/passwd">x</a><iframe src="data:text/html,bad"></iframe>"#))
        #expect(try await web.evaluateReaderString("String(document.querySelectorAll('#glosso-content iframe, #glosso-content a[href]').length)") == "0")
        #expect(try await web.evaluateReaderString("document.querySelector('strong').textContent") == "Translated")
    }

    @Test func savedLibraryRendersRowsAndRefreshesPinState() async throws {
        let web = try await makeWeb()
        let rows = #"[{"url":"https://example.com/one","title":"First","original":"Original","age":"Today","pinned":false},{"url":"https://example.com/two","title":"Second","pinned":true}]"#
        _ = try await web.evaluateReaderString(ReaderTemplate.call("glossoSetSaved", rows))
        #expect(try await web.evaluateReaderString("String(document.querySelectorAll('.glosso-saved-row').length)") == "2")
        #expect(try await web.evaluateReaderString("document.querySelector('.glosso-saved-title').textContent") == "First")
        #expect(try await web.evaluateReaderString("String(document.querySelectorAll('.glosso-saved-pin svg').length)") == "2")
        #expect(try await web.evaluateReaderString("String(document.querySelectorAll('.glosso-pinned').length)") == "1")
        _ = try await web.evaluateReaderString(ReaderTemplate.call("glossoSetSaved", "[]"))
        #expect(try await web.evaluateReaderString("String(document.querySelectorAll('.glosso-saved-row').length)") == "0")
        #expect(try await web.evaluateReaderString("document.querySelector('#glosso-saved-empty').style.display") == "block")
    }

    @Test func responsiveImagesRetainValidatedSourcesIncludingOnReplay() async throws {
        let web = try await makeWeb()
        var html = #"<picture><source media="(min-width: 800px)" srcset="/wide.webp 800w, /large.webp 1600w"><img srcset="../small.jpg 1x, /large.jpg 2x" sizes="100vw"></picture>"#
        for _ in 0..<2 {
            _ = try await web.evaluateReaderString(ReaderTemplate.call("glossoSetArticle", "T", "", html))
            #expect(try await web.evaluateReaderString("document.querySelector('#glosso-content img').getAttribute('srcset')") == "https://example.com/small.jpg 1x, https://example.com/large.jpg 2x")
            #expect(try await web.evaluateReaderString("document.querySelector('#glosso-content source').getAttribute('srcset')") == "https://example.com/wide.webp 800w, https://example.com/large.webp 1600w")
            html = try #require(await web.evaluateReaderString("document.querySelector('#glosso-content').innerHTML"))
        }
    }

    @Test func srcsetRejectsUnsafeCandidatesAndPreservesRasterDataURLs() async throws {
        let web = try await makeWeb()
        let html = #"<img srcset="javascript:alert(1) 1x, file:///tmp/image.png 2x, data:text/html,bad 3x, data:image/svg+xml,bad 4x, /bad.png nope, /good.png 5x"><img srcset="data:image/png;base64,iVBORw0KGgo= 1x, /fallback.png 2x"><img srcset="/plain.png, /double.png 2x"><img srcset="javascript:alert(1) 1x, file:///tmp/x 2x">"#
        _ = try await web.evaluateReaderString(ReaderTemplate.call("glossoSetArticle", "T", "", html))
        #expect(try await web.evaluateReaderString("document.querySelectorAll('#glosso-content img')[0].getAttribute('srcset')") == "https://example.com/good.png 5x")
        let raster = try await web.evaluateReaderString("document.querySelectorAll('#glosso-content img')[1].getAttribute('srcset')")
        #expect(raster == "data:image/png;base64,iVBORw0KGgo= 1x, https://example.com/fallback.png 2x")
        #expect(try await web.evaluateReaderString("document.querySelectorAll('#glosso-content img')[2].getAttribute('srcset')") == "https://example.com/plain.png, https://example.com/double.png 2x")
        #expect(try await web.evaluateReaderString("document.querySelectorAll('#glosso-content img')[3].getAttribute('srcset')") == nil)
    }

    @Test func pageWorldCannotAccessReaderFunctions() async throws {
        let web = try await makeWeb()
        #expect(try await web.evaluateStringResult("typeof glossoSetArticle") == "undefined")
        #expect(try await web.evaluateReaderString("typeof glossoSetArticle") == "function")
    }

    @Test func nativeBridgeRejectsRealSubframeAndOldSessionMessages() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let events = AsyncStream<Bool>.makeStream()
        let handler = BridgeProbe(continuation: events.continuation)
        configuration.userContentController.add(handler, contentWorld: ReaderWebSecurity.world, name: "glosso")
        // Deliberately grant the test subframe access to the isolated world. Production only bootstraps main.
        configuration.userContentController.addUserScript(WKUserScript(source: """
            window.webkit.messageHandlers.glosso.postMessage({action:'ask',question:'test',session:'current'});
            if (window === window.top) {
                window.webkit.messageHandlers.glosso.postMessage({action:'ask',question:'test',session:'old'});
            }
            """, injectionTime: .atDocumentEnd, forMainFrameOnly: false, in: ReaderWebSecurity.world))
        let web = WKWebView(frame: .zero, configuration: configuration)
        handler.webView = web
        let watcher = NavigationWatcher()
        web.navigationDelegate = watcher
        try await watcher.awaitNavigation(in: web, timeout: .seconds(5)) {
            web.loadHTMLString("<iframe srcdoc='<p>child</p>'></iframe>", baseURL: nil)
        }
        var results: [Bool] = []
        for await accepted in events.stream {
            results.append(accepted)
            if results.count == 3 { break }
        }
        #expect(results.filter { $0 }.count == 1)
        #expect(try await web.evaluateStringResult("typeof window.webkit?.messageHandlers?.glosso") == "undefined")
        configuration.userContentController.removeScriptMessageHandler(forName: "glosso", contentWorld: ReaderWebSecurity.world)
    }

    @Test func bridgeRejectsOtherFramesDocumentsAndMalformedCommands() {
        let body = ["action": "ask", "question": "Question", "session": "current"]
        #expect(ReaderWebSecurity.accepts(body, session: "current", isMainFrame: true, sameWebView: true))
        #expect(!ReaderWebSecurity.accepts(body, session: "current", isMainFrame: false, sameWebView: true))
        #expect(!ReaderWebSecurity.accepts(body, session: "next", isMainFrame: true, sameWebView: true))
        #expect(!ReaderWebSecurity.accepts(body, session: "current", isMainFrame: true, sameWebView: false))
        #expect(!ReaderWebSecurity.accepts(["action": "retention", "days": "0", "session": "current"],
                                          session: "current", isMainFrame: true, sameWebView: true))
        #expect(!ReaderWebSecurity.accepts(["action": "open", "url": "file:///etc/passwd", "session": "current"],
                                          session: "current", isMainFrame: true, sameWebView: true))
    }

    @Test(arguments: ["http://youtube.com/embed/a", "https://youtube.com.evil.test/a", "data:text/html,x",
                      "https://evil.test/?url=https://youtube.com/a", "https://user@youtube.com/a"])
    func framePolicyRejectsUntrustedURLs(raw: String) {
        #expect(!ReaderWebSecurity.allowsFrame(URL(string: raw)!))
    }
}

@MainActor
private final class BridgeProbe: NSObject, WKScriptMessageHandler {
    weak var webView: WKWebView?
    let continuation: AsyncStream<Bool>.Continuation
    init(continuation: AsyncStream<Bool>.Continuation) { self.continuation = continuation }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        let accepted = ReaderWebSecurity.accepts(message.body as? [String: String] ?? [:], session: "current",
            isMainFrame: message.frameInfo.isMainFrame, sameWebView: message.webView === webView)
        continuation.yield(accepted)
    }
}
