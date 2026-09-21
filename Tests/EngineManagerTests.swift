import Foundation
import Testing
@testable import Glosso

// Each test owns an isolated HTTP fixture.
@Suite struct EngineManagerTests {
    private let http = HTTPFixture()
    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        http.configure(configuration)
        return URLSession(configuration: configuration)
    }

    private func reachableHandler() {
        http.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, #"{"version":"0.30.10"}"#.data(using: .utf8)!)
        }
    }

    @Test func statusIsReadyWhenOllamaReachable() async {
        reachableHandler()
        defer { http.handler = nil }
        let engine = EngineManager(session: makeSession())
        #expect(await engine.status() == .ready)
    }

    @Test func resolvedBaseURLNeverProvisions() async {
        // No handler installed: any request would fail, and a spawn would need a binary — neither happens.
        let engine = EngineManager(session: makeSession())
        #expect(await engine.resolvedBaseURL().absoluteString == "http://localhost:11434/api/generate")
    }

    @Test func activeBaseURLReusesReachableOllama() async throws {
        reachableHandler()
        defer { http.handler = nil }
        let engine = EngineManager(session: makeSession())
        let url = try await engine.activeBaseURL()
        #expect(url.absoluteString == "http://localhost:11434/api/generate")
    }
}
