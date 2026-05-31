import Foundation
import Testing
@testable import TranslatorMenuBar

@Suite struct OllamaClientTests {
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
        for try await event in client.translate("Cześć") {
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
            for try await _ in client.translate("Cześć") {}
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
            for try await _ in client.translate("Cześć") {}
        }
    }
}
