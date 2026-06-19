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

    // A newer tag surfaces as an available update, with the leading "v" stripped for
    // display and the .zip asset's direct download URL carried through for fetching.
    @Test func detectsNewerRelease() async {
        respond(tag: "v0.2.0", asset: "https://example.invalid/Glosso-0.2.0.zip")
        let update = await makeChecker().availableUpdate(currentVersion: "0.1.0")
        #expect(update?.version == "0.2.0")
        #expect(update?.asset.absoluteString == "https://example.invalid/Glosso-0.2.0.zip")
    }

    // A newer release with no .zip asset has nothing to download, so it must not
    // surface as an update (it would otherwise drive a dead menu item and badge).
    @Test func ignoresReleaseWithoutZipAsset() async {
        respond(tag: "v0.2.0", asset: "https://example.invalid/notes.txt", assetName: "notes.txt")
        #expect(await makeChecker().availableUpdate(currentVersion: "0.1.0") == nil)
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
