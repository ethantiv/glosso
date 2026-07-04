import Foundation
import Testing
@testable import Glosso

// Serialized: every case mutates the process-global MockURLProtocol.handler,
// so Swift Testing's default parallelism would let one case's request read
// another's handler (or nil), flaking the suite.
@Suite(.serialized) struct OllamaClientTests {
    private func makeClient() -> OllamaClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        return OllamaClient(session: session)
    }

    @Test func streamsTokensAndStopsOnDone() async throws {
        MockURLProtocol.handler = { request in
            let lines = [
                #"{"model":"m","response":"Hel","done":false}"#,
                #"{"model":"m","response":"lo","done":false}"#,
                #"{"model":"m","response":"","done":true,"done_reason":"stop"}"#,
            ]
            let body = (lines.joined(separator: "\n") + "\n").data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }
        defer { MockURLProtocol.handler = nil }

        let client = makeClient()
        var tokens: [String] = []
        for try await event in client.run("Cześć", action: .translate, model: "m", second: .english, formality: .automatic, humanize: false, style: false) {
            if case let .token(value) = event {
                tokens.append(value)
            }
        }

        #expect(tokens == ["Hel", "lo"])
    }

    @Test func unreachableHostMapsToOllamaUnreachable() async {
        MockURLProtocol.handler = { _ in
            throw URLError(.cannotConnectToHost)
        }
        defer { MockURLProtocol.handler = nil }

        let client = makeClient()
        await #expect(throws: TranslationError.ollamaUnreachable) {
            for try await _ in client.run("Cześć", action: .translate, model: "m", second: .english, formality: .automatic, humanize: false, style: false) {}
        }
    }

    @Test func errorFrameSurfacesAsOllamaError() async {
        MockURLProtocol.handler = { request in
            let body = (#"{"error":"model 'gemma4:26b-mlx' not found"}"# + "\n").data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }
        defer { MockURLProtocol.handler = nil }

        let client = makeClient()
        await #expect(throws: TranslationError.ollamaError("model 'gemma4:26b-mlx' not found")) {
            for try await _ in client.run("Cześć", action: .translate, model: "m", second: .english, formality: .automatic, humanize: false, style: false) {}
        }
    }

    @Test func streamEndingWithoutDoneMapsToMalformedStream() async {
        MockURLProtocol.handler = { request in
            let lines = [
                #"{"model":"m","response":"Hel","done":false}"#,
                #"{"model":"m","response":"lo","done":false}"#,
            ]
            let body = (lines.joined(separator: "\n") + "\n").data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }
        defer { MockURLProtocol.handler = nil }

        let client = makeClient()
        await #expect(throws: TranslationError.malformedStream) {
            for try await _ in client.run("Cześć", action: .translate, model: "m", second: .english, formality: .automatic, humanize: false, style: false) {}
        }
    }

    @Test func unexpectedURLErrorMapsToOllamaUnreachable() async {
        MockURLProtocol.handler = { _ in
            throw URLError(.networkConnectionLost)
        }
        defer { MockURLProtocol.handler = nil }

        let client = makeClient()
        await #expect(throws: TranslationError.ollamaUnreachable) {
            for try await _ in client.run("Cześć", action: .translate, model: "m", second: .english, formality: .automatic, humanize: false, style: false) {}
        }
    }

    @Test func nonOKStatusMapsToHTTPStatus() async {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        defer { MockURLProtocol.handler = nil }

        let client = makeClient()
        await #expect(throws: TranslationError.httpStatus(500)) {
            for try await _ in client.run("Cześć", action: .translate, model: "m", second: .english, formality: .automatic, humanize: false, style: false) {}
        }
    }

    // A 404 carries Ollama's actionable "model not found, try pulling it first"
    // in the body; surface it instead of a bare HTTP code so the user knows to
    // `ollama pull` rather than assuming the daemon is broken.
    @Test func nonOKStatusWithErrorBodySurfacesOllamaError() async {
        MockURLProtocol.handler = { request in
            let body = (#"{"error":"model not found, try pulling it first"}"# + "\n").data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }
        defer { MockURLProtocol.handler = nil }

        let client = makeClient()
        await #expect(throws: TranslationError.ollamaError("model not found, try pulling it first")) {
            for try await _ in client.run("Cześć", action: .translate, model: "m", second: .english, formality: .automatic, humanize: false, style: false) {}
        }
    }
}
