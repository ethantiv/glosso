import Foundation
import Testing
@testable import Glosso

@Suite(.serialized) struct GeminiClientTests {
    private func makeClient(key: String? = "test-key", limiter: GeminiRateLimiter? = nil) -> GeminiClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return GeminiClient(
            session: URLSession(configuration: configuration),
            limiter: limiter ?? GeminiRateLimiter(store: DefaultsRef(UserDefaults(suiteName: UUID().uuidString)!)),
            keyProvider: { key },
            sleep: { _ in }
        )
    }

    private func respond(_ status: Int, _ body: String) {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (response, body.data(using: .utf8)!)
        }
    }

    private static func sse(_ lines: [String]) -> String {
        lines.map { "data: \($0)\n\n" }.joined()
    }

    @Test func streamsTokensAndStopsOnFinishReason() async throws {
        respond(200, Self.sse([
            #"{"candidates":[{"content":{"parts":[{"text":"Dzień "}]}}]}"#,
            #"{"candidates":[{"content":{"parts":[{"text":"dobry"}]},"finishReason":"STOP"}]}"#,
        ]))
        defer { MockURLProtocol.handler = nil }

        var tokens: [String] = []
        for try await event in makeClient().run("Good morning", action: .translate, model: "gemma-4-31b-it", primary: .polish, second: .english, formality: .automatic, style: false) {
            if case let .token(value) = event { tokens.append(value) }
        }

        #expect(tokens == ["Dzień ", "dobry"])
    }

    @Test func streamEndingWithoutFinishReasonMapsToMalformedStream() async {
        respond(200, Self.sse([#"{"candidates":[{"content":{"parts":[{"text":"Dzień"}]}}]}"#]))
        defer { MockURLProtocol.handler = nil }

        await #expect(throws: TranslationError.malformedStream) {
            for try await _ in makeClient().run("Good morning", action: .translate, model: "m", primary: .polish, second: .english, formality: .automatic, style: false) {}
        }
    }

    @Test func generateReturnsTheJoinedText() async throws {
        respond(200, #"{"candidates":[{"content":{"parts":[{"text":"<b>Cześć</b>"}]},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":12}}"#)
        defer { MockURLProtocol.handler = nil }

        let result = try await makeClient().translateBlock(html: "<b>Hello</b>", into: .polish, model: "m")
        #expect(result == "<b>Cześć</b>")
    }

    @Test func truncatedGenerationIsAnError() async {
        // Parity with Ollama's done_reason == "length": a half-translated block must not be applied as if complete.
        respond(200, #"{"candidates":[{"content":{"parts":[{"text":"<b>Cześć"}]},"finishReason":"MAX_TOKENS"}]}"#)
        defer { MockURLProtocol.handler = nil }

        await #expect(throws: TranslationError.malformedStream) {
            _ = try await makeClient().translateBlock(html: "<b>Hello</b>", into: .polish, model: "m")
        }
    }

    @Test func promptLevelRefusalIsNotABlankSuccess() async {
        // A refused prompt comes back with promptFeedback and no candidates at all,
        // so finishReason is nil and the text is "" — returning that would paint an
        // empty translation with no error.
        respond(200, #"{"promptFeedback":{"blockReason":"SAFETY"}}"#)
        defer { MockURLProtocol.handler = nil }

        await #expect(throws: TranslationError.contentBlocked("SAFETY")) {
            _ = try await makeClient().translateBlock(html: "<b>Hello</b>", into: .polish, model: "m")
        }
    }

    @Test func emptyResponseWithoutAReasonIsMalformedNotBlocked() async {
        // Nothing says the model refused, so this is a broken response — the reader
        // is right to count it toward its abort, unlike a refusal.
        respond(200, #"{"candidates":[]}"#)
        defer { MockURLProtocol.handler = nil }

        await #expect(throws: TranslationError.malformedStream) {
            _ = try await makeClient().translateBlock(html: "<b>Hello</b>", into: .polish, model: "m")
        }
    }

    @Test func streamSurfacesAPromptLevelRefusal() async {
        respond(200, Self.sse([#"{"promptFeedback":{"blockReason":"PROHIBITED_CONTENT"}}"#]))
        defer { MockURLProtocol.handler = nil }

        await #expect(throws: TranslationError.contentBlocked("PROHIBITED_CONTENT")) {
            for try await _ in makeClient().run("Hi", action: .translate, model: "m", primary: .polish, second: .english, formality: .automatic, style: false) {}
        }
    }

    @Test func missingKeyFailsWithoutTouchingTheNetwork() async {
        MockURLProtocol.handler = { _ in
            Issue.record("no request should be sent without an API key")
            throw URLError(.unknown)
        }
        defer { MockURLProtocol.handler = nil }

        await #expect(throws: TranslationError.missingAPIKey) {
            _ = try await makeClient(key: "  ").translateBlock(html: "<b>Hello</b>", into: .polish, model: "m")
        }
    }

    @Test func badKeyIsReportedAsInvalidNotAsAGenericHTTPError() async {
        // Google answers a bad key with 400 INVALID_ARGUMENT, not 403 — the status alone would tell the user nothing.
        respond(400, #"{"error":{"code":400,"message":"API key not valid. Please pass a valid API key.","status":"INVALID_ARGUMENT","details":[{"reason":"API_KEY_INVALID"}]}}"#)
        defer { MockURLProtocol.handler = nil }

        await #expect(throws: TranslationError.invalidAPIKey) {
            _ = try await makeClient().translateBlock(html: "<b>Hello</b>", into: .polish, model: "m")
        }
    }

    @Test func rateLimitIsRetriedAndThenSucceeds() async throws {
        let attempts = Counter()
        MockURLProtocol.handler = { request in
            let first = attempts.next() == 0
            let body = first
                ? #"{"error":{"code":429,"message":"quota","status":"RESOURCE_EXHAUSTED","details":[{"retryDelay":"2s"}]}}"#
                : #"{"candidates":[{"content":{"parts":[{"text":"Cześć"}]},"finishReason":"STOP"}]}"#
            let response = HTTPURLResponse(url: request.url!, statusCode: first ? 429 : 200, httpVersion: nil, headerFields: nil)!
            return (response, body.data(using: .utf8)!)
        }
        defer { MockURLProtocol.handler = nil }

        let result = try await makeClient().translateBlock(html: "<b>Hello</b>", into: .polish, model: "m")
        #expect(result == "Cześć")
        #expect(attempts.value == 2)
    }

    @Test func persistentRateLimitSurfacesAsRateLimited() async {
        respond(429, #"{"error":{"code":429,"message":"quota","status":"RESOURCE_EXHAUSTED","details":[{"retryDelay":"2s"}]}}"#)
        defer { MockURLProtocol.handler = nil }

        await #expect(throws: TranslationError.rateLimited(2)) {
            _ = try await makeClient().translateBlock(html: "<b>Hello</b>", into: .polish, model: "m")
        }
    }

    @Test func overloadedServerLooksLikeAnUnreachableCloud() async {
        // 503 "model is overloaded" is routine on the free tier; only the errors RoutingLLMClient
        // treats as fallbackable keep the local engine as an escape hatch.
        respond(503, #"{"error":{"code":503,"message":"The model is overloaded.","status":"UNAVAILABLE"}}"#)
        defer { MockURLProtocol.handler = nil }

        await #expect(throws: TranslationError.cloudUnreachable) {
            _ = try await makeClient().translateBlock(html: "<b>Hello</b>", into: .polish, model: "m")
        }
        #expect(RoutingLLMClient.fallsBack(.cloudUnreachable))
    }

    @Test func blockedGenerationIsAnErrorNotAnEmptyTranslation() async {
        // A SAFETY candidate carries no parts; returning its empty text would paint a blank popup.
        respond(200, #"{"candidates":[{"finishReason":"SAFETY"}]}"#)
        defer { MockURLProtocol.handler = nil }

        await #expect(throws: TranslationError.contentBlocked("SAFETY")) {
            _ = try await makeClient().translateBlock(html: "<b>Hello</b>", into: .polish, model: "m")
        }
    }

    @Test func aRefusedRequestSpendsNoQuota() async {
        // The key is checked on this machine, so the daily counter must not move for a call Google never saw.
        let limiter = GeminiRateLimiter(store: DefaultsRef(UserDefaults(suiteName: UUID().uuidString)!))
        MockURLProtocol.handler = { _ in
            Issue.record("no request should be sent without an API key")
            throw URLError(.unknown)
        }
        defer { MockURLProtocol.handler = nil }

        _ = try? await makeClient(key: "", limiter: limiter).translateBlock(html: "<b>Hello</b>", into: .polish, model: "m")
        let used = await limiter.quotaUsage().used
        #expect(used == 0)
    }

    @Test func aLongRetryDelayFallsBackInsteadOfStalling() async {
        // Waiting out Google's 40s is worse than the local model answering now.
        respond(429, #"{"error":{"code":429,"message":"quota","status":"RESOURCE_EXHAUSTED","details":[{"retryDelay":"40s"}]}}"#)
        defer { MockURLProtocol.handler = nil }

        await #expect(throws: TranslationError.rateLimited(40)) {
            _ = try await makeClient().translateBlock(html: "<b>Hello</b>", into: .polish, model: "m")
        }
    }

    @Test func requestPinsTemperatureAndDisablesThinking() async throws {
        // Both are load-bearing: thinking left on costs 10–26s per lookup, and a non-zero temperature makes output unrepeatable.
        let captured = BodyBox()
        MockURLProtocol.handler = { request in
            captured.store(request.httpBodyStream.map { stream in
                stream.open()
                defer { stream.close() }
                var data = Data()
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let read = stream.read(&buffer, maxLength: buffer.count)
                    if read <= 0 { break }
                    data.append(contentsOf: buffer[0..<read])
                }
                return data
            } ?? request.httpBody ?? Data())
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, #"{"candidates":[{"content":{"parts":[{"text":"ok"}]},"finishReason":"STOP"}]}"#.data(using: .utf8)!)
        }
        defer { MockURLProtocol.handler = nil }

        _ = try await makeClient().translateBlock(html: "<b>Hello</b>", into: .polish, model: "m")
        let body = String(decoding: captured.value, as: UTF8.self)
        #expect(body.contains(#""thinkingLevel":"minimal""#))
        #expect(body.contains(#""temperature":0"#))
    }

    @Test func networkFailureIsReportedAsCloudNotOllama() async {
        MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        defer { MockURLProtocol.handler = nil }

        await #expect(throws: TranslationError.cloudUnreachable) {
            _ = try await makeClient().translateBlock(html: "<b>Hello</b>", into: .polish, model: "m")
        }
    }

    @Test func prewarmSendsNothing() async throws {
        MockURLProtocol.handler = { _ in
            Issue.record("prewarm must not spend a request on the cloud")
            throw URLError(.unknown)
        }
        defer { MockURLProtocol.handler = nil }

        try await makeClient().prewarm(model: "m")
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func next() -> Int { lock.withLock { defer { count += 1 }; return count } }
    var value: Int { lock.withLock { count } }
}

private final class BodyBox: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func store(_ new: Data) { lock.withLock { data = new } }
    var value: Data { lock.withLock { data } }
}
