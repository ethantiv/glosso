import Foundation
import Synchronization
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

    @Test func concurrentEnsureAndTranslationShareOneStart() async throws {
        let probes = Mutex(0)
        http.handler = { request in
            probes.withLock { $0 += 1 }
            // Slow enough that the second caller arrives while the first start is still in flight.
            Thread.sleep(forTimeInterval: 0.2)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, #"{"version":"0.30.10"}"#.data(using: .utf8)!)
        }
        defer { http.handler = nil }
        let engine = EngineManager(session: makeSession())
        async let ensured: Void = engine.ensureEngine(progress: { _ in })
        async let url = engine.activeBaseURL()
        _ = try await (ensured, url)
        // Two starts would each probe (and, without a reachable Ollama, each spawn a `serve` that kills the other).
        #expect(probes.withLock { $0 } == 1)
    }
}
