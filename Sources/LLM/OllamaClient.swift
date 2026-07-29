import Foundation

final class OllamaClient: LLMClient, GenerationBackend {
    private let session: URLSession
    private let config: LLMConfig
    private let endpointProvider: @Sendable () async throws -> URL
    /// Non-nil marks a cloud instance: it signs every request and reports failures as the cloud errors `RoutingLLMClient.fallsBack` accepts, so a dead key hands over to the local engine instead of surfacing a raw 401.
    private let keyProvider: (@Sendable () -> String?)?

    init(session: URLSession = .shared, config: LLMConfig = .default, endpointProvider: @escaping @Sendable () async throws -> URL = { LLMConfig.default.endpoint }, keyProvider: (@Sendable () -> String?)? = nil) {
        self.session = session
        self.config = config
        self.endpointProvider = endpointProvider
        self.keyProvider = keyProvider
    }

    private var isCloud: Bool { keyProvider != nil }

    private func resolveKey() throws -> String? { try Self.resolveKey(keyProvider) }

    /// nil for the local engine; a cloud instance with no key fails before any network work.
    private static func resolveKey(_ provider: (@Sendable () -> String?)?) throws -> String? {
        guard let provider else { return nil }
        let key = provider()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !key.isEmpty else { throw TranslationError.missingAPIKey }
        return key
    }

    private static func unreachable(isCloud: Bool) -> TranslationError {
        isCloud ? .cloudUnreachable : .ollamaUnreachable
    }

    /// A 200 carrying `{"error":…}` is Ollama's shape for a *generation-time* failure: headers are flushed as soon as the request is accepted, so capacity and model-load trouble arrives in the body. The request itself was fine, so on the cloud this has to land on a case `fallsBack` accepts — none of which carry a message, which is why the text is dropped there.
    private static func bodyError(_ message: String, isCloud: Bool) -> TranslationError {
        isCloud ? .cloudUnreachable : .ollamaError(message)
    }

    /// `message` is the server's own `{"error":…}` body — the only thing that names a retired or misspelled model, which is the failure the hardcoded cloud default is most likely to hit. A 4xx says the request is wrong, so it deliberately does **not** fall back: handing over would hide a dead model id forever.
    private static func statusError(_ code: Int, isCloud: Bool, message: String?) -> TranslationError {
        guard isCloud else { return message.map(TranslationError.ollamaError) ?? .httpStatus(code) }
        switch code {
        case 401, 403: return .invalidAPIKey
        case 429: return .rateLimited(nil)
        case 500...599: return .cloudUnreachable
        default: return message.map(TranslationError.cloudError) ?? .httpStatus(code)
        }
    }

    func generate(prompt: String, model: String, timeout: TimeInterval? = nil, numPredict: Int? = nil) async throws -> String {
        let key = try resolveKey()
        let endpoint = try await endpointProvider()
        let request = try Self.makeRequest(config: config, model: model, prompt: prompt, stream: false, endpoint: endpoint, key: key, timeout: timeout, numPredict: numPredict)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw TranslationError.cancelled
        } catch {
            throw Self.unreachable(isCloud: isCloud)
        }
        guard let http = response as? HTTPURLResponse else { throw Self.unreachable(isCloud: isCloud) }
        let chunk = try? JSONDecoder().decode(GenerateChunk.self, from: data)
        // The status decides first: the cloud's 401 body decodes as an error message too, and `.ollamaError` never falls back.
        guard http.statusCode == 200 else { throw Self.statusError(http.statusCode, isCloud: isCloud, message: chunk?.error) }
        if let message = chunk?.error { throw Self.bodyError(message, isCloud: isCloud) }
        guard let body = chunk?.response else { throw TranslationError.malformedStream }
        guard chunk?.doneReason != "length" else { throw TranslationError.malformedStream }
        return body
    }

    func streamGeneration(prompt: String, model: String) -> AsyncThrowingStream<TranslationEvent, Error> {
        let session = self.session
        let baseConfig = self.config
        let endpointProvider = self.endpointProvider
        let keyProvider = self.keyProvider
        let isCloud = self.isCloud

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let key = try Self.resolveKey(keyProvider)
                    let endpoint = try await endpointProvider()
                    let request = try Self.makeRequest(config: baseConfig, model: model, prompt: prompt, stream: true, endpoint: endpoint, key: key)
                    let (bytes, response) = try await session.bytes(for: request)

                    guard let http = response as? HTTPURLResponse else {
                        continuation.finish(throwing: Self.unreachable(isCloud: isCloud))
                        return
                    }
                    guard http.statusCode == 200 else {
                        var message: String?
                        for try await line in bytes.lines {
                            message = NDJSONStreamParser.parse(line: line)?.error
                            break
                        }
                        continuation.finish(throwing: Self.statusError(http.statusCode, isCloud: isCloud, message: message))
                        return
                    }

                    var sawDone = false
                    for try await line in bytes.lines {
                        if Task.isCancelled {
                            continuation.finish(throwing: TranslationError.cancelled)
                            return
                        }
                        guard let chunk = NDJSONStreamParser.parse(line: line) else { continue }
                        if let serverError = chunk.error {
                            continuation.finish(throwing: Self.bodyError(serverError, isCloud: isCloud))
                            return
                        }
                        if let response = chunk.response, !response.isEmpty {
                            continuation.yield(.token(response))
                        }
                        if chunk.done {
                            continuation.yield(.finished(doneReason: chunk.doneReason))
                            sawDone = true
                            break
                        }
                    }
                    if sawDone {
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: TranslationError.malformedStream)
                    }
                } catch let error as URLError {
                    switch error.code {
                    case .cancelled:
                        continuation.finish(throwing: TranslationError.cancelled)
                    default:
                        continuation.finish(throwing: Self.unreachable(isCloud: isCloud))
                    }
                } catch is CancellationError {
                    continuation.finish(throwing: TranslationError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    func prewarm(model: String) async throws {
        // Nothing is resident in the cloud to warm, and this runs on every launch — it would just spend GPU time.
        guard !isCloud else { return }
        do {
            let endpoint = try await endpointProvider()
            let request = try Self.makeRequest(config: config, model: model, prompt: "", stream: false, endpoint: endpoint, key: nil)
            _ = try await session.data(for: request)
        } catch {
            // best-effort: prewarm failures must not surface
        }
    }

    private static func makeRequest(config baseConfig: LLMConfig, model: String, prompt: String, stream: Bool, endpoint: URL, key: String?, timeout: TimeInterval? = nil, numPredict: Int? = nil) throws -> URLRequest {
        var config = baseConfig
        config.model = model
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        if let timeout { request.timeoutInterval = timeout }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Header, not a query item — the key stays out of proxy and server access logs.
        if let key { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONEncoder().encode(GenerateRequest(config: config, prompt: prompt, stream: stream, numPredict: numPredict))
        return request
    }
}
