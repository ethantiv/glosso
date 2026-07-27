import Foundation
import Testing
@testable import Glosso

private struct StubBackend: GenerationBackend {
    var text: String = ""
    var failure: TranslationError?
    /// Tokens to emit before failing, so a mid-stream failure can be exercised.
    var tokensBeforeFailure: [String] = []
    var seenModels: ModelLog = ModelLog()

    func generate(prompt: String, model: String, timeout: TimeInterval?, numPredict: Int?) async throws -> String {
        seenModels.record(model)
        if let failure { throw failure }
        return text
    }

    func streamGeneration(prompt: String, model: String) -> AsyncThrowingStream<TranslationEvent, Error> {
        seenModels.record(model)
        return AsyncThrowingStream { continuation in
            for token in tokensBeforeFailure { continuation.yield(.token(token)) }
            if let failure {
                continuation.finish(throwing: failure)
            } else {
                continuation.yield(.token(text))
                continuation.yield(.finished(doneReason: "stop"))
                continuation.finish()
            }
        }
    }

    func prewarm(model: String) async throws {}
}

private final class ModelLog: @unchecked Sendable {
    private let lock = NSLock()
    private var models: [String] = []

    func record(_ model: String) { lock.withLock { models.append(model) } }
    var all: [String] { lock.withLock { models } }
}

private final class FallbackLog: @unchecked Sendable {
    private let lock = NSLock()
    private var errors: [TranslationError] = []

    func record(_ error: TranslationError) { lock.withLock { errors.append(error) } }
    var all: [TranslationError] { lock.withLock { errors } }
}

@Suite struct RoutingLLMClientTests {
    private func makeClient(
        local: StubBackend,
        cloud: StubBackend,
        provider: LLMProvider,
        fallbacks: FallbackLog = FallbackLog()
    ) -> RoutingLLMClient {
        RoutingLLMClient(
            local: local,
            cloud: cloud,
            provider: { provider },
            localModel: { "gemma4:26b-mlx" },
            onFallback: { fallbacks.record($0) }
        )
    }

    private func collect(_ stream: AsyncThrowingStream<TranslationEvent, Error>) async throws -> [String] {
        var tokens: [String] = []
        for try await event in stream {
            if case let .token(value) = event { tokens.append(value) }
        }
        return tokens
    }

    @Test func localProviderNeverTouchesTheCloud() async throws {
        let cloud = StubBackend(text: "cloud")
        let client = makeClient(local: StubBackend(text: "local"), cloud: cloud, provider: .local)

        #expect(try await client.translateBlock(html: "<b>Hi</b>", into: .polish, model: "gemma4:26b-mlx") == "local")
        #expect(cloud.seenModels.all.isEmpty)
    }

    @Test func exhaustedQuotaFallsBackToTheLocalModelName() async throws {
        // The caller passes the cloud model id; Ollama would fail with "model not found" unless the router swaps it.
        let local = StubBackend(text: "local")
        let fallbacks = FallbackLog()
        let client = makeClient(
            local: local,
            cloud: StubBackend(failure: .quotaExhausted),
            provider: .cloud,
            fallbacks: fallbacks
        )

        #expect(try await client.translateBlock(html: "<b>Hi</b>", into: .polish, model: "gemma-4-31b-it") == "local")
        #expect(local.seenModels.all == ["gemma4:26b-mlx"])
        #expect(fallbacks.all == [.quotaExhausted])
    }

    @Test func aBadRequestIsNotMaskedByTheFallback() async {
        // Only cloud-availability failures fall back; a malformed response means the request itself is wrong.
        let local = StubBackend(text: "local")
        let client = makeClient(local: local, cloud: StubBackend(failure: .malformedStream), provider: .cloud)

        await #expect(throws: TranslationError.malformedStream) {
            _ = try await client.translateBlock(html: "<b>Hi</b>", into: .polish, model: "gemma-4-31b-it")
        }
        #expect(local.seenModels.all.isEmpty)
    }

    @Test func streamFallsBackWhenTheCloudFailsBeforeAnyToken() async throws {
        let fallbacks = FallbackLog()
        let client = makeClient(
            local: StubBackend(text: "lokalnie"),
            cloud: StubBackend(failure: .missingAPIKey),
            provider: .cloud,
            fallbacks: fallbacks
        )

        let tokens = try await collect(client.run("Hi", action: .translate, model: "gemma-4-31b-it", primary: .polish, second: .english, formality: .automatic, style: false))
        #expect(tokens == ["lokalnie"])
        #expect(fallbacks.all == [.missingAPIKey])
    }

    @Test func streamThatAlreadyEmittedTokensDoesNotRestartLocally() async {
        // Restarting here would replay the translation into a popup already showing its first half.
        let local = StubBackend(text: "lokalnie")
        let fallbacks = FallbackLog()
        let client = makeClient(
            local: local,
            cloud: StubBackend(failure: .cloudUnreachable, tokensBeforeFailure: ["Dzień "]),
            provider: .cloud,
            fallbacks: fallbacks
        )

        await #expect(throws: TranslationError.cloudUnreachable) {
            _ = try await collect(client.run("Hi", action: .translate, model: "gemma-4-31b-it", primary: .polish, second: .english, formality: .automatic, style: false))
        }
        #expect(local.seenModels.all.isEmpty)
        #expect(fallbacks.all.isEmpty)
    }
}
