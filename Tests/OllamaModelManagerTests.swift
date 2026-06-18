import Foundation
import Testing
@testable import Glosso

// Serialized: shares the process-global MockURLProtocol.handler (see OllamaClientTests).
@Suite(.serialized) struct OllamaModelManagerTests {
    private func makeManager() -> OllamaModelManager {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        return OllamaModelManager(session: session, endpointProvider: {
            URL(string: "http://localhost:11434/api/generate")!
        })
    }

    @Test func pullHitsPullEndpointAndStreamsToSuccess() async throws {
        MockURLProtocol.handler = { request in
            #expect(request.url?.path == "/api/pull")
            #expect(request.httpMethod == "POST")
            let lines = [
                #"{"status":"pulling manifest"}"#,
                #"{"status":"pulling abc","completed":50,"total":100}"#,
                #"{"status":"success"}"#,
            ]
            let body = (lines.joined(separator: "\n") + "\n").data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }
        defer { MockURLProtocol.handler = nil }

        let manager = makeManager()
        var updates: [PullProgress] = []
        for try await progress in manager.pull("gemma4:12b-mlx") { updates.append(progress) }

        #expect(updates.count == 3)
        #expect(updates[1] == PullProgress(status: "pulling abc", completed: 50, total: 100))
        #expect(updates.last?.status == "success")
    }

    @Test func pullSurfacesServerError() async {
        MockURLProtocol.handler = { request in
            let body = (#"{"error":"model not found"}"# + "\n").data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }
        defer { MockURLProtocol.handler = nil }

        let manager = makeManager()
        await #expect(throws: TranslationError.ollamaError("model not found")) {
            for try await _ in manager.pull("bad:model") {}
        }
    }

    @Test func deleteUsesDeleteEndpoint() async throws {
        MockURLProtocol.handler = { request in
            #expect(request.url?.path == "/api/delete")
            #expect(request.httpMethod == "DELETE")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        defer { MockURLProtocol.handler = nil }

        try await makeManager().delete("gemma4:12b-mlx")
    }
}
