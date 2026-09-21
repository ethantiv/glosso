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
    var clock: ManualTestClock? = nil
    var seenModels: ModelLog = ModelLog()

    func generate(prompt: String, model: String, timeout: TimeInterval?, numPredict: Int?) async throws -> String {
        seenModels.record(model)
        if delay > 0, let clock { try await clock.sleep(for: .seconds(delay)) }
        if let failure { throw failure }
        return text
    }

    func streamGeneration(prompt: String, model: String) -> AsyncThrowingStream<TranslationEvent, Error> {
        seenModels.record(model)
        return AsyncThrowingStream { continuation in
            let task = Task {
                for token in tokensBeforeFailure { continuation.yield(.token(token)) }
                if delay > 0, let clock { try await clock.sleep(for: .seconds(delay)) }
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
    private var reported: [(error: TranslationError, longForm: Bool)] = []

    func record(_ error: TranslationError, longForm: Bool) {
        lock.withLock { reported.append((error, longForm)) }
    }
    var all: [TranslationError] { lock.withLock { reported.map(\.error) } }
    var longFormFlags: [Bool] { lock.withLock { reported.map(\.longForm) } }
}

@Suite(.timeLimit(.minutes(1))) struct RoutingLLMClientTests {
    private func makeClient(
        local: StubBackend,
        cloud: StubBackend,
        ollamaCloud: StubBackend = StubBackend(text: "ollama-cloud"),
        provider: LLMProvider,
        fallbacks: FallbackLog = FallbackLog(),
        deadline: TimeInterval = 0.05,
        clock: ManualTestClock = ManualTestClock(),
        localReady: @escaping @Sendable () async -> Bool = { true }
    ) -> RoutingLLMClient {
        RoutingLLMClient(
            local: local,
            cloud: cloud,
            ollamaCloud: ollamaCloud,
            provider: { provider },
            localModel: { "gemma4:26b-mlx" },
            onFallback: { fallbacks.record($0, longForm: $1) },
            deadline: deadline,
            sleep: { try await clock.sleep(for: $0) },
            localReady: localReady
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

    @Test func ollamaCloudProviderUsesItsOwnBackendNotGoogles() async throws {
        // Two cloud backends share one router; picking the wrong one would silently send the text to the other vendor.
        let google = StubBackend(text: "google")
        let ollama = StubBackend(text: "ollama-cloud")
        let client = makeClient(local: StubBackend(text: "local"), cloud: google,
                                ollamaCloud: ollama, provider: .ollamaCloud)

        #expect(try await client.translateBlock(html: "<b>Hi</b>", into: .polish, model: "gemma4:31b") == "ollama-cloud")
        #expect(google.seenModels.all.isEmpty)
        #expect(ollama.seenModels.all == ["gemma4:31b"])
    }

    @Test func aRejectedOllamaCloudKeyFallsBackToTheLocalModelName() async throws {
        // Callers pass `gemma4:31b`, which the local engine has never pulled — the router must swap in the local model.
        let local = StubBackend(text: "local")
        let fallbacks = FallbackLog()
        let client = makeClient(local: local, cloud: StubBackend(text: "google"),
                                ollamaCloud: StubBackend(failure: .invalidAPIKey),
                                provider: .ollamaCloud, fallbacks: fallbacks)

        #expect(try await client.translateBlock(html: "<b>Hi</b>", into: .polish, model: "gemma4:31b") == "local")
        #expect(local.seenModels.all == ["gemma4:26b-mlx"])
        #expect(fallbacks.all == [.invalidAPIKey])
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

    // The reader repaints its footer as "local" on a fallback, so it must hear only about its own calls: a popup
    // lookup handing over says nothing about the engine still translating the open article.
    @Test func onlyLongFormCallsReportThemselvesAsSuch() async throws {
        let fallbacks = FallbackLog()
        let client = makeClient(
            local: StubBackend(text: "local"),
            cloud: StubBackend(failure: .quotaExhausted),
            provider: .cloud,
            fallbacks: fallbacks
        )

        _ = try await client.translateBlock(html: "<b>Hi</b>", into: .polish, model: "gemma-4-31b-it")
        _ = try await client.alternatives(for: "dom", in: "Ten dom", source: "This house",
                                          primary: .polish, second: .english, model: "gemma-4-31b-it")
        #expect(fallbacks.longFormFlags == [true, false])
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

    @Test(arguments: [LLMProvider.cloud, .ollamaCloud])
    func aSilentCloudStreamHandsOverToTheLocalModel(provider: LLMProvider) async throws {
        let clock = ManualTestClock()
        let fallbacks = FallbackLog()
        let client = makeClient(local: StubBackend(text: "local"),
            cloud: StubBackend(text: "cloud", delay: 5, clock: clock),
            ollamaCloud: StubBackend(text: "ollama-cloud", delay: 5, clock: clock),
            provider: provider, fallbacks: fallbacks, clock: clock)
        let task = Task { try await collect(client.streamGeneration(prompt: "Hi", model: "m")) }
        await clock.waitForSleepers(2)
        await clock.advance(by: .milliseconds(50))
        #expect(try await task.value == ["local"])
        #expect(fallbacks.all == [.cloudUnreachable])
        #expect(await clock.cancellations >= 1)
    }

    @Test func aStreamThatSpokeInTimeMayPausePastTheDeadline() async throws {
        let clock = ManualTestClock()
        let local = StubBackend(text: "local")
        let client = makeClient(local: local,
            cloud: StubBackend(text: "rest", tokensBeforeFailure: ["first"], delay: 1, clock: clock), provider: .cloud, clock: clock)
        let firstToken = StreamGate()
        let task = Task { () throws -> [String] in
            var result: [String] = []
            for try await event in client.streamGeneration(prompt: "Hi", model: "m") {
                if case .token(let token) = event { result.append(token); firstToken.release() }
            }
            return result
        }
        await clock.waitForSleepers(2)
        await firstToken.wait()
        await clock.advance(by: .seconds(1))
        #expect(try await task.value == ["first", "rest"])
        #expect(local.seenModels.all.isEmpty)
    }

    @Test func aSilentInteractiveLookupHandsOverToTheLocalModel() async throws {
        let clock = ManualTestClock()
        let local = StubBackend(text: "word")
        let fallbacks = FallbackLog()
        let client = makeClient(local: local, cloud: StubBackend(text: "cloud", delay: 5, clock: clock),
                                provider: .cloud, fallbacks: fallbacks, clock: clock)
        let task = Task { try await client.reply(to: "Hi", model: "m") }
        await clock.waitForSleepers(2)
        await clock.advance(by: .milliseconds(50))
        _ = try await task.value
        #expect(local.seenModels.all == ["gemma4:26b-mlx"])
        #expect(fallbacks.all == [.cloudUnreachable])
    }

    @Test func theReaderKeepsItsOwnTimeoutInsteadOfTheDeadline() async throws {
        let clock = ManualTestClock()
        let local = StubBackend(text: "local")
        let client = makeClient(local: local, cloud: StubBackend(text: "cloud", delay: 1, clock: clock), provider: .cloud, clock: clock)
        let task = Task { try await client.translateBlock(html: "Hi", into: .polish, model: "m") }
        await clock.waitForSleepers(1)
        await clock.advance(by: .seconds(1))
        #expect(try await task.value == "cloud")
        #expect(local.seenModels.all.isEmpty)
    }

    @Test(arguments: [false, true])
    func withNoLocalEngineTheSlowCloudKeepsTheRequest(stream: Bool) async throws {
        let clock = ManualTestClock()
        let probed = StreamGate()
        let local = StubBackend(text: "local")
        let client = makeClient(local: local, cloud: StubBackend(text: "cloud", delay: 1, clock: clock),
            provider: .cloud, clock: clock, localReady: { probed.release(); return false })
        let task = Task {
            if stream { return try await collect(client.streamGeneration(prompt: "Hi", model: "m")) }
            return [try await client.generate(prompt: "Hi", model: "m")]
        }
        await clock.waitForSleepers(2)
        await clock.advance(by: .milliseconds(50))
        await probed.wait()
        await clock.advance(by: .seconds(1))
        #expect(try await task.value == ["cloud"])
        #expect(local.seenModels.all.isEmpty)
    }

    @Test func aSlowReadinessProbeDoesNotHoldTheCloudAnswer() async throws {
        let clock = ManualTestClock()
        let probed = StreamGate()
        let client = makeClient(local: StubBackend(text: "local"),
            cloud: StubBackend(text: "cloud", delay: 1, clock: clock), provider: .cloud, clock: clock,
            localReady: { probed.release(); try? await clock.sleep(for: .seconds(5)); return true })
        let task = Task { try await collect(client.streamGeneration(prompt: "Hi", model: "m")) }
        await clock.waitForSleepers(2)
        await clock.advance(by: .milliseconds(50))
        await probed.wait()
        await clock.waitForSleepers(2)
        await clock.advance(by: .seconds(1))
        #expect(try await task.value == ["cloud"])
        #expect(await clock.cancellations >= 1)
    }

    @Test func aFinishedCloudStreamDoesNotWaitOutTheDeadline() async throws {
        let clock = ManualTestClock()
        let client = makeClient(local: StubBackend(text: "local"), cloud: StubBackend(text: "cloud"), provider: .cloud, clock: clock)
        // No clock advance: this would hang if a finished stream waited for the deadline.
        #expect(try await collect(client.streamGeneration(prompt: "Hi", model: "m")) == ["cloud"])
    }
}
