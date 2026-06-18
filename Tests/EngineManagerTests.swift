import Foundation
import Testing
@testable import Glosso

// Serialized: shares the process-global MockURLProtocol.handler.
@Suite(.serialized) struct EngineManagerTests {
    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func reachableHandler() {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, #"{"version":"0.30.10"}"#.data(using: .utf8)!)
        }
    }

    @Test func statusIsReadyWhenOllamaReachable() async {
        reachableHandler()
        defer { MockURLProtocol.handler = nil }
        let engine = EngineManager(session: makeSession())
        #expect(await engine.status() == .ready)
    }

    @Test func activeBaseURLReusesReachableOllama() async throws {
        reachableHandler()
        defer { MockURLProtocol.handler = nil }
        let engine = EngineManager(session: makeSession())
        let url = try await engine.activeBaseURL()
        #expect(url.absoluteString == "http://localhost:11434/api/generate")
    }
}
