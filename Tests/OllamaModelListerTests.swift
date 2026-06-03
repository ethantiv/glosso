import Foundation
import Testing
@testable import Glosso

// A dedicated URLProtocol (not the shared MockURLProtocol) so this suite's
// process-global handler can't race OllamaClientTests' handler when Swift Testing
// runs the two suites in parallel.
final class MockTagsURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockTagsURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class URLRecorder: @unchecked Sendable {
    var url: URL?
}

@Suite(.serialized) struct OllamaModelListerTests {
    private func makeLister() -> OllamaModelLister {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockTagsURLProtocol.self]
        let session = URLSession(configuration: configuration)
        return OllamaModelLister(session: session)
    }

    // Parses the model names AND proves the lister derives /api/tags from the
    // generate endpoint rather than POSTing to /api/generate.
    @Test func parsesModelNamesAndHitsTagsEndpoint() async throws {
        let recorder = URLRecorder()
        MockTagsURLProtocol.handler = { request in
            recorder.url = request.url
            let body = #"{"models":[{"name":"gemma4:26b-mlx"},{"name":"llama3:8b"}]}"#.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }
        defer { MockTagsURLProtocol.handler = nil }

        let models = try await makeLister().availableModels()

        #expect(models == ["gemma4:26b-mlx", "llama3:8b"])
        #expect(recorder.url?.path == "/api/tags")
    }

    @Test func nonOKStatusThrowsUnreachable() async {
        MockTagsURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        defer { MockTagsURLProtocol.handler = nil }

        await #expect(throws: ModelListingError.unreachable) {
            _ = try await makeLister().availableModels()
        }
    }

    @Test func networkErrorPropagates() async {
        MockTagsURLProtocol.handler = { _ in throw URLError(.cannotConnectToHost) }
        defer { MockTagsURLProtocol.handler = nil }

        await #expect(throws: (any Error).self) {
            _ = try await makeLister().availableModels()
        }
    }
}
