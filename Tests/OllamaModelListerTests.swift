import Foundation
import Testing
@testable import Glosso

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

    @Test func theCloudListerAsksOllamasOwnHost() async throws {
        // The cloud catalog is not hardcoded — it is whatever ollama.com serves today, and that endpoint needs no key.
        let recorder = URLRecorder()
        MockTagsURLProtocol.handler = { request in
            recorder.url = request.url
            let body = #"{"models":[{"name":"gemma4:31b"},{"name":"gpt-oss:120b"}]}"#.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }
        defer { MockTagsURLProtocol.handler = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockTagsURLProtocol.self]
        let lister = OllamaModelLister(session: URLSession(configuration: configuration),
                                       endpointProvider: { OllamaCloudCatalog.baseURL })
        let models = try await lister.availableModels()

        #expect(models == ["gemma4:31b", "gpt-oss:120b"])
        #expect(recorder.url?.absoluteString == "https://ollama.com/api/tags")
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
