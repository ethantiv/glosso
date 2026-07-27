import Foundation

/// Gemma on the Gemini API. Only the transport primitives live here — the prompt
/// layer is shared with OllamaClient through PromptRunning.swift.
final class GeminiClient: LLMClient, GenerationBackend {
    static let baseURL = URL(string: "https://generativelanguage.googleapis.com/v1beta/models")!

    /// `outputTokenLimit` reported by GET /v1beta/models for the Gemma 4 tiers.
    /// translateBlock sizes its cap in UTF-8 bytes, which can overshoot this.
    static let outputTokenLimit = 8192

    private static let maxRetries = 2

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
        var attempt = 0
        while true {
            let ticket = try await limiter.acquire(estimatedTokens: GeminiRateLimiter.estimateTokens(prompt))
            let request = try makeRequest(prompt: prompt, model: model, stream: false, timeout: timeout, numPredict: numPredict)
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
            guard decoded.finishReason != "MAX_TOKENS" else { throw TranslationError.malformedStream }
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
                        let text = chunk.text
                        if !text.isEmpty { continuation.yield(.token(text)) }
                        if let reason = chunk.finishReason {
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

    /// No-op: there is nothing to keep resident, and AppCoordinator.start() calls
    /// this on every launch — on the cloud that would burn a request for nothing.
    func prewarm(model: String) async throws {}

    private func openStream(prompt: String, model: String) async throws -> (URLSession.AsyncBytes, Int) {
        var attempt = 0
        while true {
            let ticket = try await limiter.acquire(estimatedTokens: GeminiRateLimiter.estimateTokens(prompt))
            let request = try makeRequest(prompt: prompt, model: model, stream: true, timeout: nil, numPredict: nil)
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

    /// Returns how long to wait before another try, or nil when the caller should
    /// give up and map the failure. Throws once the retries are spent.
    private func retryDelay(status: Int, body: Data, attempt: inout Int) throws -> TimeInterval? {
        guard status == 429 else { return nil }
        let envelope = try? JSONDecoder().decode(GeminiErrorEnvelope.self, from: body)
        attempt += 1
        let delay = envelope?.retryDelay ?? TimeInterval(1 << attempt)
        guard attempt <= Self.maxRetries else { throw TranslationError.rateLimited(delay) }
        return delay
    }

    private static func mapFailure(status: Int, body: Data) -> TranslationError {
        let envelope = try? JSONDecoder().decode(GeminiErrorEnvelope.self, from: body)
        if envelope?.isInvalidKey == true || status == 403 { return .invalidAPIKey }
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
        // Built by concatenation, not URL(string:relativeTo:): the "model:method"
        // segment has a colon, which relative parsing reads as a scheme.
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
