import Foundation
import Testing
@testable import Glosso

private struct StubBackend: GenerationBackend {
    var text: String = ""
    var failure: TranslationError?
    /// Tokens to emit before failing, so a mid-stream failure can be exercised.
    var tokensBeforeFailure: [String] = []
    /// Silence before anything is produced — how a slow cloud model looks from here.
    var delay: TimeInterval = 0
    var seenModels: ModelLog = ModelLog()

    func generate(prompt: String, model: String, timeout: TimeInterval?, numPredict: Int?) async throws -> String {
        seenModels.record(model)
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        if let failure { throw failure }
        return text
    }

    func streamGeneration(prompt: String, model: String) -> AsyncThrowingStream<TranslationEvent, Error> {
        seenModels.record(model)
        return AsyncThrowingStream { continuation in
            let task = Task {
                for token in tokensBeforeFailure { continuation.yield(.token(token)) }
                if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
                if let failure {
                    continuation.finish(throwing: failure)
                } else {
                    continuation.yield(.token(text))
                    continuation.yield(.finished(doneReason: "stop"))
                    continuation.finish()
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
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
        fallbacks: FallbackLog = FallbackLog(),
        deadline: TimeInterval = 0.05
    ) -> RoutingLLMClient {
        RoutingLLMClient(
            local: local,
            cloud: cloud,
            provider: { provider },
            localModel: { "gemma4:26b-mlx" },
            onFallback: { fallbacks.record($0) },
            deadline: deadline
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

    @Test func aSilentCloudStreamHandsOverToTheLocalModel() async throws {
        // gemini-3.5-flash-lite answers a trivial prompt in ~30s and nothing errors, so without the deadline the popup just sits on its skeleton.
        let fallbacks = FallbackLog()
        let client = makeClient(
            local: StubBackend(text: "lokalnie"),
            cloud: StubBackend(text: "z chmury", delay: 5),
            provider: .cloud,
            fallbacks: fallbacks
        )

        let tokens = try await collect(client.run("Hi", action: .translate, model: "gemma-4-31b-it", primary: .polish, second: .english, formality: .automatic, style: false))
        #expect(tokens == ["lokalnie"])
        #expect(fallbacks.all == [.cloudUnreachable])
    }

    @Test func aStreamThatSpokeInTimeMayPausePastTheDeadline() async throws {
        // The deadline covers the first token only; killing a live stream over a slow middle would lose what the popup shows.
        let local = StubBackend(text: "lokalnie")
        let client = makeClient(
            local: local,
            cloud: StubBackend(text: "reszta", tokensBeforeFailure: ["Dzień "], delay: 0.3),
            provider: .cloud
        )

        let tokens = try await collect(client.run("Hi", action: .translate, model: "gemma-4-31b-it", primary: .polish, second: .english, formality: .automatic, style: false))
        #expect(tokens == ["Dzień ", "reszta"])
        #expect(local.seenModels.all.isEmpty)
    }

    @Test func aSilentInteractiveLookupHandsOverToTheLocalModel() async throws {
        // Non-streaming lookups (alternatives, why, replies) hang the same way; only the whole answer counts as a response there.
        let local = StubBackend(text: "słowo")
        let fallbacks = FallbackLog()
        let client = makeClient(
            local: local,
            cloud: StubBackend(text: "z chmury", delay: 5),
            provider: .cloud,
            fallbacks: fallbacks
        )

        _ = try await client.reply(to: "Hi", model: "gemma-4-31b-it")
        #expect(local.seenModels.all == ["gemma4:26b-mlx"])
        #expect(fallbacks.all == [.cloudUnreachable])
    }

    @Test func theReaderKeepsItsOwnTimeoutInsteadOfTheDeadline() async throws {
        // Translating a block legitimately outruns the deadline; applying it there would send every article to the local model.
        let client = makeClient(
            local: StubBackend(text: "lokalnie"),
            cloud: StubBackend(text: "z chmury", delay: 0.3),
            provider: .cloud
        )

        #expect(try await client.translateBlock(html: "<b>Hi</b>", into: .polish, model: "gemma-4-31b-it") == "z chmury")
    }

    @Test func aFinishedCloudStreamDoesNotWaitOutTheDeadline() async throws {
        // Waiting for the timer too would hold the popup's task open for 6s after the answer is complete, delaying everything the caller does once the stream ends.
        let client = makeClient(local: StubBackend(text: "lokalnie"), cloud: StubBackend(text: "z chmury"), provider: .cloud, deadline: 2)

        let start = ContinuousClock.now
        let tokens = try await collect(client.run("Hi", action: .translate, model: "gemma-4-31b-it", primary: .polish, second: .english, formality: .automatic, style: false))
        let elapsed = ContinuousClock.now - start

        #expect(tokens == ["z chmury"])
        #expect(elapsed < .milliseconds(500), "the stream stayed open for \(elapsed)")
    }
}
