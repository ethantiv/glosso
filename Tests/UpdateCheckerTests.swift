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

    private func respond(tag: String, asset: String = "https://example.invalid/Glosso.zip", assetName: String = "Glosso.zip") {
        MockURLProtocol.handler = { request in
            let json = #"{"tag_name":"\#(tag)","assets":[{"name":"\#(assetName)","browser_download_url":"\#(asset)"}]}"#.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }
    }

    @Test func detectsNewerRelease() async {
        respond(tag: "v0.2.0", asset: "https://example.invalid/Glosso-0.2.0.zip")
        let update = await makeChecker().availableUpdate(currentVersion: "0.1.0")
        #expect(update?.version == "0.2.0")
        #expect(update?.asset.absoluteString == "https://example.invalid/Glosso-0.2.0.zip")
    }

    @Test func ignoresReleaseWithoutZipAsset() async {
        respond(tag: "v0.2.0", asset: "https://example.invalid/notes.txt", assetName: "notes.txt")
        #expect(await makeChecker().availableUpdate(currentVersion: "0.1.0") == nil)
    }

    @Test func ignoresSameOrOlderRelease() async {
        respond(tag: "v0.1.0")
        #expect(await makeChecker().availableUpdate(currentVersion: "0.1.0") == nil)

        respond(tag: "v1.9")
        #expect(await makeChecker().availableUpdate(currentVersion: "1.10") == nil)
    }

    @Test func failsSilentlyOnHTTPError() async {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        #expect(await makeChecker().availableUpdate(currentVersion: "0.1.0") == nil)
    }

    @Test func numericVersionOrdering() {
        #expect(GitHubUpdateChecker.isNewer("1.10", than: "1.9"))
        #expect(GitHubUpdateChecker.isNewer("v0.2.0", than: "0.1.9"))
        #expect(!GitHubUpdateChecker.isNewer("1.9", than: "1.10"))
        #expect(!GitHubUpdateChecker.isNewer("0.1.0", than: "0.1.0"))
    }
}
