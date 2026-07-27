import Foundation

/// Gemma on the Gemini API; only the transport primitives live here (see PromptRunning.swift).
final class GeminiClient: LLMClient, GenerationBackend {
    static let baseURL = URL(string: "https://generativelanguage.googleapis.com/v1beta/models")!

    /// `outputTokenLimit` from GET /v1beta/models — translateBlock's byte-sized cap can overshoot it.
    static let outputTokenLimit = 8192

    private static let maxRetries = 2

    /// Past this the local model answers sooner than the retry would.
    private static let maxRetryDelay: TimeInterval = 5

    private let session: URLSession
    private let limiter: GeminiRateLimiter
    private let keyProvider: @Sendable () -> String?
    private let sleep: @Sendable (Duration) async throws -> Void

    init(
        session: URLSession = .shared,
        limiter: GeminiRateLimiter = GeminiRateLimiter(),
        keyProvider: @escaping @Sendable () -> String? = { APIKeyStore.read() },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.session = session
        self.limiter = limiter
        self.keyProvider = keyProvider
        self.sleep = sleep
    }

    func generate(prompt: String, model: String, timeout: TimeInterval? = nil, numPredict: Int? = nil) async throws -> String {
        // Key first, ticket once: an unsent request must not spend quota, and a retried one is still a single request.
        let request = try makeRequest(prompt: prompt, model: model, stream: false, timeout: timeout, numPredict: numPredict)
        let ticket = try await limiter.acquire(estimatedTokens: GeminiRateLimiter.estimateTokens(prompt))
        var attempt = 0
        while true {
            let (data, response) = try await send(request)
            guard let http = response as? HTTPURLResponse else { throw TranslationError.cloudUnreachable }

            if http.statusCode != 200 {
                if let delay = try retryDelay(status: http.statusCode, body: data, attempt: &attempt) {
                    try await sleep(.milliseconds(Int(delay * 1000)))
                    continue
                }
                throw Self.mapFailure(status: http.statusCode, body: data)
            }

            guard let decoded = try? JSONDecoder().decode(GeminiResponse.self, from: data) else {
                throw TranslationError.malformedStream
            }
            await limiter.settle(ticket: ticket, actualTokens: decoded.usageMetadata?.promptTokenCount)
            // A refusal must never read as a blank success. It arrives in two shapes:
            // per-candidate (SAFETY/RECITATION/PROHIBITED_CONTENT) and prompt-level,
            // where the response carries promptFeedback and no candidates at all.
            if let refusal = decoded.promptRefusal { throw TranslationError.contentBlocked(refusal) }
            switch decoded.finishReason {
            case "MAX_TOKENS": throw TranslationError.malformedStream
            case let reason? where reason != "STOP": throw TranslationError.contentBlocked(reason)
            default: break
            }
            // No reason and nothing to show is a broken response, not a refusal.
            guard decoded.finishReason != nil || !decoded.text.isEmpty else {
                throw TranslationError.malformedStream
            }
            return decoded.text
        }
    }

    func streamGeneration(prompt: String, model: String) -> AsyncThrowingStream<TranslationEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, ticket) = try await openStream(prompt: prompt, model: model)
                    var sawFinish = false
                    for try await line in bytes.lines {
                        if Task.isCancelled {
                            continuation.finish(throwing: TranslationError.cancelled)
                            return
                        }
                        guard let chunk = GeminiSSEParser.parse(line: line) else { continue }
                        await limiter.settle(ticket: ticket, actualTokens: chunk.usageMetadata?.promptTokenCount)
                        if let refusal = chunk.promptRefusal {
                            continuation.finish(throwing: TranslationError.contentBlocked(refusal))
                            return
                        }
                        let text = chunk.text
                        if !text.isEmpty { continuation.yield(.token(text)) }
                        if let reason = chunk.finishReason {
                            guard reason == "STOP" || reason == "MAX_TOKENS" else {
                                continuation.finish(throwing: TranslationError.contentBlocked(reason))
                                return
                            }
                            continuation.yield(.finished(doneReason: reason == "MAX_TOKENS" ? "length" : "stop"))
                            sawFinish = true
                            break
                        }
                    }
                    continuation.finish(throwing: sawFinish ? nil : TranslationError.malformedStream)
                } catch let error as URLError where error.code == .cancelled {
                    continuation.finish(throwing: TranslationError.cancelled)
                } catch is CancellationError {
                    continuation.finish(throwing: TranslationError.cancelled)
                } catch let error as URLError {
                    _ = error
                    continuation.finish(throwing: TranslationError.cloudUnreachable)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    /// No-op: nothing is resident to warm, and start() calls it every launch — that would burn a request.
    func prewarm(model: String) async throws {}

    private func openStream(prompt: String, model: String) async throws -> (URLSession.AsyncBytes, Int) {
        let request = try makeRequest(prompt: prompt, model: model, stream: true, timeout: nil, numPredict: nil)
        let ticket = try await limiter.acquire(estimatedTokens: GeminiRateLimiter.estimateTokens(prompt))
        var attempt = 0
        while true {
            let (bytes, response) = try await sendStream(request)
            guard let http = response as? HTTPURLResponse else { throw TranslationError.cloudUnreachable }
            if http.statusCode == 200 { return (bytes, ticket) }

            var body = Data()
            for try await byte in bytes.prefix(8192) { body.append(byte) }
            if let delay = try retryDelay(status: http.statusCode, body: body, attempt: &attempt) {
                try await sleep(.milliseconds(Int(delay * 1000)))
                continue
            }
            throw Self.mapFailure(status: http.statusCode, body: body)
        }
    }

    /// How long to wait before retrying, nil to map the failure instead; throws once the retries or maxRetryDelay are spent.
    private func retryDelay(status: Int, body: Data, attempt: inout Int) throws -> TimeInterval? {
        guard status == 429 else { return nil }
        let envelope = try? JSONDecoder().decode(GeminiErrorEnvelope.self, from: body)
        attempt += 1
        let delay = envelope?.retryDelay ?? TimeInterval(1 << attempt)
        guard attempt <= Self.maxRetries, delay <= Self.maxRetryDelay else { throw TranslationError.rateLimited(delay) }
        return delay
    }

    private static func mapFailure(status: Int, body: Data) -> TranslationError {
        let envelope = try? JSONDecoder().decode(GeminiErrorEnvelope.self, from: body)
        if envelope?.isInvalidKey == true || status == 403 { return .invalidAPIKey }
        // A 5xx ("model is overloaded") is routine on the free tier and the local engine can serve it.
        if (500...599).contains(status) { return .cloudUnreachable }
        if let message = envelope?.message { return .cloudError(message) }
        return .httpStatus(status)
    }

    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw TranslationError.cancelled
        } catch {
            throw TranslationError.cloudUnreachable
        }
    }

    private func sendStream(_ request: URLRequest) async throws -> (URLSession.AsyncBytes, URLResponse) {
        do {
            return try await session.bytes(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw TranslationError.cancelled
        } catch {
            throw TranslationError.cloudUnreachable
        }
    }

    private func makeRequest(prompt: String, model: String, stream: Bool, timeout: TimeInterval?, numPredict: Int?) throws -> URLRequest {
        guard let key = keyProvider()?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            throw TranslationError.missingAPIKey
        }
        // Concatenated, not URL(string:relativeTo:): the colon in "model:method" parses as a scheme.
        let method = stream ? "\(model):streamGenerateContent?alt=sse" : "\(model):generateContent"
        guard let url = URL(string: "\(Self.baseURL.absoluteString)/\(method)") else {
            throw TranslationError.cloudUnreachable
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if let timeout { request.timeoutInterval = timeout }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Header, not ?key= — the key stays out of proxy and server access logs.
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONEncoder().encode(GeminiRequest(
            prompt: prompt,
            temperature: LLMConfig.default.temperature,
            maxOutputTokens: numPredict.map { min($0, Self.outputTokenLimit) }
        ))
        return request
    }
}
