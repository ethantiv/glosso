import AppKit
import WebKit

@MainActor
enum ReaderWebSecurity {
    static let world = WKContentWorld.world(name: "GlossoReader")
    static let videoHosts: Set<String> = [
        "dailymotion.com", "www.dailymotion.com", "youtube.com", "www.youtube.com",
        "youtube-nocookie.com", "www.youtube-nocookie.com", "player.vimeo.com", "www.player.vimeo.com",
        "v.qq.com", "www.v.qq.com", "player.twitch.tv", "www.player.twitch.tv",
    ]

    static func allowsFrame(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && videoHosts.contains(url.host?.lowercased() ?? "") &&
        url.user == nil && url.password == nil && (url.port == nil || url.port == 443)
    }

    static func bootstrap(session: String, sourceURL: URL?) throws -> String {
        func resource(_ name: String) throws -> String {
            guard let url = Bundle.main.url(forResource: name, withExtension: "js") else {
                throw ReaderError.extractionFailed
            }
            return try String(contentsOf: url, encoding: .utf8)
        }
        let config = [session, sourceURL?.absoluteString ?? "about:blank"]
        let json = String(decoding: try JSONEncoder().encode(config), as: UTF8.self)
        return "const [glossoDocumentID, glossoSourceURL] = \(json);\n" +
            (try resource("purify.min")) + "\n" + (try resource("ReaderSanitizer")) + "\n" + ReaderTemplate.script
    }

    static func accepts(_ body: [String: String], session: String?, isMainFrame: Bool, sameWebView: Bool) -> Bool {
        guard isMainFrame, sameWebView, let session, body["session"] == session else { return false }
        switch body["action"] {
        case "ask": return Set(body.keys) == ["action", "session", "question"] && !(body["question"] ?? "").isEmpty
        case "open": return Set(body.keys) == ["action", "session", "url"] && validArticleURL(body["url"])
        case "pin": return Set(body.keys) == ["action", "session", "url", "on"] && validArticleURL(body["url"]) && ["", "1"].contains(body["on"] ?? "invalid")
        case "retention": return Set(body.keys) == ["action", "session", "days"] && ["7", "30", "90"].contains(body["days"] ?? "")
        default: return false
        }
    }

    private static func validArticleURL(_ raw: String?) -> Bool { raw.flatMap(URLDetector.articleURL) != nil }
}

@MainActor
final class ReaderNavigationDelegate: NavigationWatcher {
    var loadingTemplate = false
    var openExternal: (URL) -> Void = { NSWorkspace.shared.open($0) }

    // WKNavigationDelegate conformance is inherited; expose the optional callback to WebKit explicitly.
    @objc(webView:decidePolicyForNavigationAction:decisionHandler:)
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        if action.targetFrame?.isMainFrame == false {
            decisionHandler(ReaderWebSecurity.allowsFrame(url) ? .allow : .cancel)
            return
        }
        if loadingTemplate, url.absoluteString == "about:blank", action.navigationType == .other {
            decisionHandler(.allow)
            return
        }
        if action.navigationType == .linkActivated,
           ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") {
            openExternal(url)
        }
        decisionHandler(.cancel)
    }
}

extension WKWebView {
    func evaluateReaderString(_ script: String) async throws -> String? {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            evaluateJavaScript(script, in: nil, in: ReaderWebSecurity.world) { result in
                continuation.resume(with: result.map { $0 as? String })
            }
        }
    }
    func evaluateReaderJavaScript(_ script: String, completionHandler: ((Any?, Error?) -> Void)? = nil) {
        evaluateJavaScript(script, in: nil, in: ReaderWebSecurity.world) { result in
            switch result {
            case .success(let value): completionHandler?(value, nil)
            case .failure(let error): completionHandler?(nil, error)
            }
        }
    }
}
