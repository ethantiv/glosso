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

    @Test func detectsNewerRelease() async throws {
        respond(tag: "v0.2.0", asset: "https://example.invalid/Glosso-0.2.0.zip")
        let update = try await makeChecker().check(currentVersion: "0.1.0")
        #expect(update?.version == "0.2.0")
        #expect(update?.asset.absoluteString == "https://example.invalid/Glosso-0.2.0.zip")
    }

    // A release whose .zip isn't there yet is an inconclusive check, not "you're up to date" — nil is reserved
    // for the latter, because the manual check's alert reads the two differently.
    @Test func failsOnReleaseWithoutZipAsset() async {
        respond(tag: "v0.2.0", asset: "https://example.invalid/notes.txt", assetName: "notes.txt")
        await #expect(throws: (any Error).self) {
            try await makeChecker().check(currentVersion: "0.1.0")
        }
    }

    @Test func ignoresSameOrOlderRelease() async throws {
        respond(tag: "v0.1.0")
        #expect(try await makeChecker().check(currentVersion: "0.1.0") == nil)

        respond(tag: "v1.9")
        #expect(try await makeChecker().check(currentVersion: "1.10") == nil)
    }

    // The alert must not claim "you're up to date" when GitHub was simply unreachable.
    @Test func throwsOnHTTPError() async {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        await #expect(throws: (any Error).self) {
            try await makeChecker().check(currentVersion: "0.1.0")
        }
    }

    @Test func numericVersionOrdering() {
        #expect(GitHubUpdateChecker.isNewer("1.10", than: "1.9"))
        #expect(GitHubUpdateChecker.isNewer("v0.2.0", than: "0.1.9"))
        #expect(!GitHubUpdateChecker.isNewer("1.9", than: "1.10"))
        #expect(!GitHubUpdateChecker.isNewer("0.1.0", than: "0.1.0"))
    }
}
