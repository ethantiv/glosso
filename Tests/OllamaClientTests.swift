import Foundation
import Testing
@testable import Glosso

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
        for try await event in client.run("Cześć", action: .translate, model: "m", primary: .polish, second: .english, formality: .automatic, style: false) {
            if case let .token(value) = event {
                tokens.append(value)
            }
        }

        #expect(tokens == ["Hel", "lo"])
    }

    @Test func translateBlockReturnsResponseBody() async throws {
        MockURLProtocol.handler = { request in
            let body = #"{"model":"m","response":"<b>Cześć</b>","done":true}"#.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }
        defer { MockURLProtocol.handler = nil }

        let client = makeClient()
        let result = try await client.translateBlock(html: "<b>Hello</b>", into: .polish, model: "m")
        #expect(result == "<b>Cześć</b>")
    }

    @Test func translateBlockSurfacesOllamaErrorBody() async {
        MockURLProtocol.handler = { request in
            let body = #"{"error":"model 'm' not found"}"#.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }
        defer { MockURLProtocol.handler = nil }

        let client = makeClient()
        await #expect(throws: TranslationError.ollamaError("model 'm' not found")) {
            _ = try await client.translateBlock(html: "<b>Hello</b>", into: .polish, model: "m")
        }
    }

    @Test func translateBlockTreatsLengthTruncationAsError() async {
        MockURLProtocol.handler = { request in
            let body = #"{"model":"m","response":"<b>Cześć","done":true,"done_reason":"length"}"#.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }
        defer { MockURLProtocol.handler = nil }

        let client = makeClient()
        await #expect(throws: TranslationError.malformedStream) {
            _ = try await client.translateBlock(html: "<b>Hello</b>", into: .polish, model: "m")
        }
    }

    @Test func generateRequestEncodesNumPredictOnlyWhenSet() throws {
        let capped = try JSONEncoder().encode(GenerateRequest(config: .default, prompt: "p", stream: false, numPredict: 2048))
        #expect(String(decoding: capped, as: UTF8.self).contains(#""num_predict":2048"#))

        let uncapped = try JSONEncoder().encode(GenerateRequest(config: .default, prompt: "p", stream: false))
        #expect(!String(decoding: uncapped, as: UTF8.self).contains("num_predict"))
    }

    @Test func readerSummaryReturnsResponseBody() async throws {
        MockURLProtocol.handler = { request in
            let body = #"{"model":"m","response":"Krótkie streszczenie.","done":true}"#.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }
        defer { MockURLProtocol.handler = nil }

        let client = makeClient()
        let result = try await client.readerSummary(of: "A long article.", into: .polish, model: "m")
        #expect(result == "Krótkie streszczenie.")
    }

    @Test func askArticleReturnsResponseBody() async throws {
        MockURLProtocol.handler = { request in
            let body = #"{"model":"m","response":"Autor mówi, że tak.","done":true}"#.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }
        defer { MockURLProtocol.handler = nil }

        let client = makeClient()
        let result = try await client.askArticle(question: "Co mówi autor?", history: [], article: "A long article.", into: .polish, model: "m")
        #expect(result == "Autor mówi, że tak.")
    }

    @Test func askArticleWithHistoryReturnsResponseBody() async throws {
        MockURLProtocol.handler = { request in
            let body = #"{"model":"m","response":"Tak, nawiązuje do poprzedniej odpowiedzi.","done":true}"#.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }
        defer { MockURLProtocol.handler = nil }

        let client = makeClient()
        let result = try await client.askArticle(
            question: "A dlaczego?", history: [("Co mówi autor?", "Autor mówi, że tak.")],
            article: "A long article.", into: .polish, model: "m")
        #expect(result == "Tak, nawiązuje do poprzedniej odpowiedzi.")
    }

    @Test func askArticleSurfacesOllamaErrorBody() async {
        MockURLProtocol.handler = { request in
            let body = #"{"error":"model 'm' not found"}"#.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }
        defer { MockURLProtocol.handler = nil }

        let client = makeClient()
        await #expect(throws: TranslationError.ollamaError("model 'm' not found")) {
            _ = try await client.askArticle(question: "Co mówi autor?", history: [], article: "A long article.", into: .polish, model: "m")
        }
    }

    @Test func articleQuestionsParsesOnePerLineAndStripsMarkers() async throws {
        MockURLProtocol.handler = { request in
            let body = #"{"model":"m","response":"1. Jak działa bateria?\n- Kto ją wynalazł?\nCo dalej?","done":true}"#.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }
        defer { MockURLProtocol.handler = nil }

        let client = makeClient()
        let result = try await client.articleQuestions(about: "A long article.", into: .polish, model: "m")
        #expect(result == ["Jak działa bateria?", "Kto ją wynalazł?", "Co dalej?"])
    }

    @Test func articleQuestionsCapsAtFive() async throws {
        MockURLProtocol.handler = { request in
            let lines = (1...7).map { "Pytanie numer \($0)?" }.joined(separator: #"\n"#)
            let body = #"{"model":"m","response":""#.appending(lines).appending(#"","done":true}"#).data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }
        defer { MockURLProtocol.handler = nil }

        let client = makeClient()
        let result = try await client.articleQuestions(about: "A long article.", into: .polish, model: "m")
        #expect(result.count == 5)
        #expect(result.first == "Pytanie numer 1?")
    }

    @Test func unreachableHostMapsToOllamaUnreachable() async {
        MockURLProtocol.handler = { _ in
            throw URLError(.cannotConnectToHost)
        }
        defer { MockURLProtocol.handler = nil }

        let client = makeClient()
        await #expect(throws: TranslationError.ollamaUnreachable) {
            for try await _ in client.run("Cześć", action: .translate, model: "m", primary: .polish, second: .english, formality: .automatic, style: false) {}
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
            for try await _ in client.run("Cześć", action: .translate, model: "m", primary: .polish, second: .english, formality: .automatic, style: false) {}
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
            for try await _ in client.run("Cześć", action: .translate, model: "m", primary: .polish, second: .english, formality: .automatic, style: false) {}
        }
    }

    @Test func unexpectedURLErrorMapsToOllamaUnreachable() async {
        MockURLProtocol.handler = { _ in
            throw URLError(.networkConnectionLost)
        }
        defer { MockURLProtocol.handler = nil }

        let client = makeClient()
        await #expect(throws: TranslationError.ollamaUnreachable) {
            for try await _ in client.run("Cześć", action: .translate, model: "m", primary: .polish, second: .english, formality: .automatic, style: false) {}
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
            for try await _ in client.run("Cześć", action: .translate, model: "m", primary: .polish, second: .english, formality: .automatic, style: false) {}
        }
    }

    @Test func nonOKStatusWithErrorBodySurfacesOllamaError() async {
        MockURLProtocol.handler = { request in
            let body = (#"{"error":"model not found, try pulling it first"}"# + "\n").data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }
        defer { MockURLProtocol.handler = nil }

        let client = makeClient()
        await #expect(throws: TranslationError.ollamaError("model not found, try pulling it first")) {
            for try await _ in client.run("Cześć", action: .translate, model: "m", primary: .polish, second: .english, formality: .automatic, style: false) {}
        }
    }
}

/// The same client pointed at Ollama's cloud host. What matters here is that its failures land on the cases `RoutingLLMClient.fallsBack` accepts — otherwise a dead key would strand the user instead of handing over to the local engine.
@Suite(.serialized) struct OllamaCloudClientTests {
    private func makeClient(key: String? = "sk-test") -> OllamaClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        return OllamaClient(session: session,
                            endpointProvider: { OllamaCloudCatalog.baseURL },
                            keyProvider: { key })
    }

    private func ok(_ request: URLRequest) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
         #"{"model":"m","response":"ok","done":true}"#.data(using: .utf8)!)
    }

    @Test func signsTheRequestAndSendsItToOllamasHost() async throws {
        let captured = HeaderBox()
        MockURLProtocol.handler = { request in
            captured.store(url: request.url, header: request.value(forHTTPHeaderField: "Authorization"))
            return self.ok(request)
        }
        defer { MockURLProtocol.handler = nil }

        _ = try await makeClient().translateBlock(html: "<b>Hello</b>", into: .polish, model: "m")
        #expect(captured.header == "Bearer sk-test")
        #expect(captured.url?.absoluteString == "https://ollama.com/api/generate")
    }

    @Test func theLocalEngineIsNeverSignedIn() async throws {
        let captured = HeaderBox()
        MockURLProtocol.handler = { request in
            captured.store(url: request.url, header: request.value(forHTTPHeaderField: "Authorization"))
            return self.ok(request)
        }
        defer { MockURLProtocol.handler = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let local = OllamaClient(session: URLSession(configuration: configuration))
        _ = try await local.translateBlock(html: "<b>Hello</b>", into: .polish, model: "m")
        #expect(captured.header == nil)
    }

    @Test func missingKeyFailsWithoutTouchingTheNetwork() async {
        MockURLProtocol.handler = { _ in
            Issue.record("a keyless cloud client must not reach the network")
            throw URLError(.unknown)
        }
        defer { MockURLProtocol.handler = nil }

        await #expect(throws: TranslationError.missingAPIKey) {
            _ = try await makeClient(key: "  ").translateBlock(html: "<b>Hello</b>", into: .polish, model: "m")
        }
    }

    @Test func aRejectedKeyIsReportedAsInvalidNotAsAnOllamaError() async {
        // The cloud answers 401 with {"error":"Unauthorized"}, which would decode into `.ollamaError` — and that never falls back.
        MockURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!,
             #"{"error":"Unauthorized"}"#.data(using: .utf8)!)
        }
        defer { MockURLProtocol.handler = nil }

        await #expect(throws: TranslationError.invalidAPIKey) {
            _ = try await makeClient().translateBlock(html: "<b>Hello</b>", into: .polish, model: "m")
        }
    }

    @Test func aRejectedKeyStopsTheStreamWithInvalidKeyToo() async {
        MockURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!,
             (#"{"error":"Unauthorized"}"# + "\n").data(using: .utf8)!)
        }
        defer { MockURLProtocol.handler = nil }

        let client = makeClient()
        await #expect(throws: TranslationError.invalidAPIKey) {
            for try await _ in client.run("Cześć", action: .translate, model: "m", primary: .polish, second: .english, formality: .automatic, style: false) {}
        }
    }

    @Test func aThrottledCloudIsReportedAsRateLimited() async {
        MockURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!, Data())
        }
        defer { MockURLProtocol.handler = nil }

        await #expect(throws: TranslationError.rateLimited(nil)) {
            _ = try await makeClient().translateBlock(html: "<b>Hello</b>", into: .polish, model: "m")
        }
    }

    @Test func networkFailureIsReportedAsCloudNotOllama() async {
        MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        defer { MockURLProtocol.handler = nil }

        await #expect(throws: TranslationError.cloudUnreachable) {
            _ = try await makeClient().translateBlock(html: "<b>Hello</b>", into: .polish, model: "m")
        }
    }

    @Test func prewarmSendsNothing() async throws {
        // Nothing is resident to warm, and this runs on every launch — it would only spend GPU time.
        MockURLProtocol.handler = { _ in
            Issue.record("prewarm must not spend a request on the cloud")
            throw URLError(.unknown)
        }
        defer { MockURLProtocol.handler = nil }

        try await makeClient().prewarm(model: "m")
    }
}

private final class HeaderBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedURL: URL?
    private var storedHeader: String?

    func store(url: URL?, header: String?) { lock.withLock { storedURL = url; storedHeader = header } }
    var url: URL? { lock.withLock { storedURL } }
    var header: String? { lock.withLock { storedHeader } }
}
