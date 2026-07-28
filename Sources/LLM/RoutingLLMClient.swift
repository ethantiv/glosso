import Foundation
import Synchronization

/// Shared one-way flag: Mutex is noncopyable, so the deadline and the stream reach it through a reference.
private final class StreamProgress: Sendable {
    private let started = Mutex(false)

    var hasStarted: Bool { started.withLock { $0 } }

    func markStarted() { started.withLock { $0 = true } }
}

/// Picks the engine per call, falling back to the local one when the cloud can't serve.
final class RoutingLLMClient: LLMClient, GenerationBackend {
    private let local: any GenerationBackend
    private let cloud: any GenerationBackend
    private let provider: @Sendable () async -> LLMProvider
    /// Callers pass the active (possibly cloud) model name, which Ollama wouldn't recognise.
    private let localModel: @Sendable () async -> String
    private let onFallback: @Sendable (TranslationError) -> Void
    /// A cloud model that says nothing for this long is worse than the local one: gemini-3.5-flash-lite answers a 43-token prompt in ~30s and delivers its whole stream in one shot, so nothing errors and the popup just sits there.
    private let deadline: TimeInterval

    init(
        local: any GenerationBackend,
        cloud: any GenerationBackend,
        provider: @escaping @Sendable () async -> LLMProvider,
        localModel: @escaping @Sendable () async -> String,
        onFallback: @escaping @Sendable (TranslationError) -> Void,
        deadline: TimeInterval = 6
    ) {
        self.local = local
        self.cloud = cloud
        self.provider = provider
        self.localModel = localModel
        self.onFallback = onFallback
        self.deadline = deadline
    }

    /// Failures the local engine can still answer; anything else is a genuine problem with the request.
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
            // Long-form reader calls bring their own timeout and legitimately run for minutes; only interactive lookups get the deadline.
            return try await withDeadline(timeout == nil) {
                try await self.cloud.generate(prompt: prompt, model: model, timeout: timeout, numPredict: numPredict)
            }
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
                    let progress = StreamProgress()
                    do {
                        try await withThrowingTaskGroup(of: Void.self) { group in
                            group.addTask {
                                for try await event in self.cloud.streamGeneration(prompt: prompt, model: model) {
                                    progress.markStarted()
                                    continuation.yield(event)
                                }
                            }
                            // Deadline only on the first token: a stream that already speaks may pause as long as it likes.
                            group.addTask {
                                try await Task.sleep(for: .seconds(self.deadline))
                                guard progress.hasStarted else { throw TranslationError.cloudUnreachable }
                            }
                            for try await _ in group {}
                        }
                        continuation.finish()
                        return
                    } catch let error as TranslationError where Self.fallsBack(error) && !progress.hasStarted {
                        // Restarting mid-stream would duplicate what the popup already shows.
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

    /// Runs `work` under the deadline, reporting a silent cloud as `.cloudUnreachable` so the caller's fallback path takes over.
    private func withDeadline<T: Sendable>(_ enabled: Bool, _ work: @escaping @Sendable () async throws -> T) async throws -> T {
        guard enabled else { return try await work() }
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await Task.sleep(for: .seconds(self.deadline))
                throw TranslationError.cloudUnreachable
            }
            defer { group.cancelAll() }
            return try await group.next()!
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
