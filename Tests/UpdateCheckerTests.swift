import Foundation
import Testing
@testable import Glosso

// MockURLProtocol.handler is shared global state, so these run serialized.
@Suite(.serialized) struct UpdateCheckerTests {
    private func makeChecker() -> GitHubUpdateChecker {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return GitHubUpdateChecker(
            session: URLSession(configuration: config),
            releasesURL: URL(string: "https://example.invalid/releases/latest")!
        )
    }

    private func respond(tag: String, page: String = "https://example.invalid/r") {
        MockURLProtocol.handler = { request in
            let json = #"{"tag_name":"\#(tag)","html_url":"\#(page)"}"#.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }
    }

    // A newer tag surfaces as an available update, with the leading "v" stripped for
    // display and the release page carried through for the menu's download link.
    @Test func detectsNewerRelease() async {
        respond(tag: "v0.2.0", page: "https://example.invalid/v0.2.0")
        let update = await makeChecker().availableUpdate(currentVersion: "0.1.0")
        #expect(update?.version == "0.2.0")
        #expect(update?.page.absoluteString == "https://example.invalid/v0.2.0")
    }

    // Same or older must not nag — and the compare must be numeric, so 1.9 is NOT
    // newer than 1.10 (a plain string compare would order these backwards).
    @Test func ignoresSameOrOlderRelease() async {
        respond(tag: "v0.1.0")
        #expect(await makeChecker().availableUpdate(currentVersion: "0.1.0") == nil)

        respond(tag: "v1.9")
        #expect(await makeChecker().availableUpdate(currentVersion: "1.10") == nil)
    }

    // An update check must never raise an error in the user's face: a non-200 (and,
    // by the same path, a dead network) resolves to "no update", not a throw.
    @Test func failsSilentlyOnHTTPError() async {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        #expect(await makeChecker().availableUpdate(currentVersion: "0.1.0") == nil)
    }

    // The ordering rule on its own — the load-bearing reason the compare uses
    // .numeric: 1.10 is newer than 1.9, "v" is ignored, and equal is not newer.
    @Test func numericVersionOrdering() {
        #expect(GitHubUpdateChecker.isNewer("1.10", than: "1.9"))
        #expect(GitHubUpdateChecker.isNewer("v0.2.0", than: "0.1.9"))
        #expect(!GitHubUpdateChecker.isNewer("1.9", than: "1.10"))
        #expect(!GitHubUpdateChecker.isNewer("0.1.0", than: "0.1.0"))
    }
}
