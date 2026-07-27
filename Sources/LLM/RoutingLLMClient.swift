import Foundation

/// Picks the engine per call and falls back to the local one when the cloud can't
/// serve — an exhausted free quota must not take the whole app down with it.
final class RoutingLLMClient: LLMClient, GenerationBackend {
    private let local: any GenerationBackend
    private let cloud: any GenerationBackend
    private let provider: @Sendable () async -> LLMProvider
    /// Callers pass the active (possibly cloud) model name, which Ollama wouldn't
    /// recognise — the fallback needs the locally installed one.
    private let localModel: @Sendable () async -> String
    private let onFallback: @Sendable (TranslationError) -> Void

    init(
        local: any GenerationBackend,
        cloud: any GenerationBackend,
        provider: @escaping @Sendable () async -> LLMProvider,
        localModel: @escaping @Sendable () async -> String,
        onFallback: @escaping @Sendable (TranslationError) -> Void
    ) {
        self.local = local
        self.cloud = cloud
        self.provider = provider
        self.localModel = localModel
        self.onFallback = onFallback
    }

    /// Failures the local engine can still answer. Anything else is a genuine
    /// problem with the request and must surface as-is.
    static func fallsBack(_ error: TranslationError) -> Bool {
        switch error {
        case .quotaExhausted, .rateLimited, .missingAPIKey, .invalidAPIKey, .cloudUnreachable: true
        default: false
        }
    }

    func generate(prompt: String, model: String, timeout: TimeInterval? = nil, numPredict: Int? = nil) async throws -> String {
        guard await provider() == .cloud else {
            return try await local.generate(prompt: prompt, model: model, timeout: timeout, numPredict: numPredict)
        }
        do {
            return try await cloud.generate(prompt: prompt, model: model, timeout: timeout, numPredict: numPredict)
        } catch let error as TranslationError where Self.fallsBack(error) {
            onFallback(error)
            return try await local.generate(prompt: prompt, model: await localModel(), timeout: timeout, numPredict: numPredict)
        }
    }

    func streamGeneration(prompt: String, model: String) -> AsyncThrowingStream<TranslationEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let useCloud = await provider() == .cloud
                if useCloud {
                    var yielded = false
                    do {
                        for try await event in cloud.streamGeneration(prompt: prompt, model: model) {
                            yielded = true
                            continuation.yield(event)
                        }
                        continuation.finish()
                        return
                    } catch let error as TranslationError where Self.fallsBack(error) && !yielded {
                        // Restarting mid-stream would duplicate what the popup already shows,
                        // so a failure after the first token propagates instead.
                        onFallback(error)
                    } catch {
                        continuation.finish(throwing: error)
                        return
                    }
                }
                do {
                    let fallbackModel = useCloud ? await localModel() : model
                    for try await event in local.streamGeneration(prompt: prompt, model: fallbackModel) {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    func prewarm(model: String) async throws {
        if await provider() == .cloud {
            try await cloud.prewarm(model: model)
        } else {
            try await local.prewarm(model: model)
        }
    }
}
