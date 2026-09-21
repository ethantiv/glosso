import Foundation
import Testing
import WebKit
@testable import Glosso

@MainActor
@Suite struct ReaderWebSecurityTests {
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

    @Test func translatedAndReplayedHTMLUseTheSameSanitizer() async throws {
        let web = try await makeWeb()
        _ = try await web.evaluateReaderString(ReaderTemplate.call("glossoSetArticle", "T", "", "<p>Original</p>"))
        _ = try await web.evaluateReaderString(ReaderTemplate.call("glossoApply", "0",
            #"<strong>Translated</strong><a href="file:///etc/passwd">x</a><iframe src="data:text/html,bad"></iframe>"#))
        #expect(try await web.evaluateReaderString("String(document.querySelectorAll('#glosso-content iframe, #glosso-content a[href]').length)") == "0")
        #expect(try await web.evaluateReaderString("document.querySelector('strong').textContent") == "Translated")
    }

    @Test func pageWorldCannotAccessReaderFunctions() async throws {
        let web = try await makeWeb()
        #expect(try await web.evaluateStringResult("typeof glossoSetArticle") == "undefined")
        #expect(try await web.evaluateReaderString("typeof glossoSetArticle") == "function")
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
