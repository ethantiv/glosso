import Foundation
import Testing
@testable import Glosso

private final class URLRecorder: @unchecked Sendable {
    var url: URL?
}

@Suite struct OllamaModelListerTests {
    private let http = HTTPFixture()
    private func makeLister() -> OllamaModelLister {
        let configuration = URLSessionConfiguration.ephemeral
        http.configure(configuration)
        let session = URLSession(configuration: configuration)
        return OllamaModelLister(session: session)
    }

    @Test func parsesModelNamesAndHitsTagsEndpoint() async throws {
        let recorder = URLRecorder()
        http.handler = { request in
            recorder.url = request.url
            let body = #"{"models":[{"name":"gemma4:26b-mlx"},{"name":"llama3:8b"}]}"#.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }
        defer { http.handler = nil }

        let models = try await makeLister().availableModels()

        #expect(models == ["gemma4:26b-mlx", "llama3:8b"])
        #expect(recorder.url?.path == "/api/tags")
    }

    @Test func loadedModelsHitsPsAndParsesExpiry() async throws {
        let recorder = URLRecorder()
        http.handler = { request in
            recorder.url = request.url
            let body = #"{"models":[{"name":"gemma4:26b-mlx","expires_at":"2026-09-17T14:38:31.83753+02:00"}]}"#.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }
        defer { http.handler = nil }

        let models = try await makeLister().loadedModels()

        #expect(recorder.url?.path == "/api/ps")
        #expect(models == [LoadedModel(name: "gemma4:26b-mlx",
                                       expiresAt: ISO8601DateFormatter().date(from: "2026-09-17T12:38:31Z"))])
    }

    @Test func theCloudListerAsksOllamasOwnHost() async throws {
        // The cloud catalog is not hardcoded — it is whatever ollama.com serves today, and that endpoint needs no key.
        let recorder = URLRecorder()
        http.handler = { request in
            recorder.url = request.url
            let body = #"{"models":[{"name":"gemma4:31b"},{"name":"gpt-oss:120b"}]}"#.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }
        defer { http.handler = nil }

        let configuration = URLSessionConfiguration.ephemeral
        http.configure(configuration)
        let lister = OllamaModelLister(session: URLSession(configuration: configuration),
                                       endpointProvider: { OllamaCloudCatalog.baseURL })
        let models = try await lister.availableModels()

        #expect(models == ["gemma4:31b", "gpt-oss:120b"])
        #expect(recorder.url?.absoluteString == "https://ollama.com/api/tags")
    }

    @Test func nonOKStatusThrowsUnreachable() async {
        http.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        defer { http.handler = nil }

        await #expect(throws: ModelListingError.unreachable) {
            _ = try await makeLister().availableModels()
        }
    }

    @Test func networkErrorPropagates() async {
        http.handler = { _ in throw URLError(.cannotConnectToHost) }
        defer { http.handler = nil }

        await #expect(throws: (any Error).self) {
            _ = try await makeLister().availableModels()
        }
    }
}
