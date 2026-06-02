import Foundation

final class OllamaClient: LLMClient {
    private let session: URLSession
    private let config: LLMConfig

    init(session: URLSession = .shared, config: LLMConfig = .default) {
        self.session = session
        self.config = config
    }

    func translate(_ text: String, model: String, second: SecondLanguage, formality: Formality) -> AsyncThrowingStream<TranslationEvent, Error> {
        stream(prompt: PromptBuilder.build(for: text, second: second, formality: formality), model: model)
    }

    func reword(original: String, to chosen: String, in translation: String, source: String, second: SecondLanguage, formality: Formality, model: String) -> AsyncThrowingStream<TranslationEvent, Error> {
        stream(prompt: PromptBuilder.buildReword(original: original, chosen: chosen, translation: translation, source: source, second: second, formality: formality), model: model)
    }

    func alternatives(for word: String, in translation: String, source: String, second: SecondLanguage, model: String) async throws -> [String] {
        // Same locked invariants as translate; only the model is user-selectable.
        var config = self.config
        config.model = model
        let prompt = PromptBuilder.buildAlternatives(word: word, translation: translation, source: source, second: second)
        let request = try Self.makeRequest(config: config, prompt: prompt, stream: false)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw TranslationError.cancelled
        } catch {
            throw TranslationError.ollamaUnreachable
        }
        guard let http = response as? HTTPURLResponse else { throw TranslationError.ollamaUnreachable }
        let chunk = try? JSONDecoder().decode(GenerateChunk.self, from: data)
        // An Ollama error body carries the actionable message regardless of status,
        // so it takes precedence over the bare HTTP status.
        if let message = chunk?.error { throw TranslationError.ollamaError(message) }
        guard http.statusCode == 200 else { throw TranslationError.httpStatus(http.statusCode) }
        guard let body = chunk?.response else { throw TranslationError.malformedStream }
        return AlternativesParser.parse(body, original: word)
    }

    // Shared NDJSON streaming used by translate() and reword(): only the model is
    // user-selectable per call; the base config keeps the empirical invariants
    // (think:false, temperature:0, keep_alive, endpoint) locked.
    private func stream(prompt: String, model: String) -> AsyncThrowingStream<TranslationEvent, Error> {
        let session = self.session
        let baseConfig = self.config

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var config = baseConfig
                    config.model = model
                    let request = try Self.makeRequest(config: config, prompt: prompt, stream: true)
                    let (bytes, response) = try await session.bytes(for: request)

                    guard let http = response as? HTTPURLResponse else {
                        continuation.finish(throwing: TranslationError.ollamaUnreachable)
                        return
                    }
                    guard http.statusCode == 200 else {
                        // Ollama returns a JSON body like
                        // {"error":"model ... not found, try pulling it first"} on
                        // 4xx/5xx — surface it so the user gets the actionable
                        // message instead of a bare HTTP status code.
                        for try await line in bytes.lines {
                            if let message = NDJSONStreamParser.parse(line: line)?.error {
                                continuation.finish(throwing: TranslationError.ollamaError(message))
                                return
                            }
                            break
                        }
                        continuation.finish(throwing: TranslationError.httpStatus(http.statusCode))
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
                            continuation.finish(throwing: TranslationError.ollamaError(serverError))
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
                    // A body that ends without a done:true chunk (proxy truncation,
                    // daemon crash, premature EOF) would otherwise leave the popup
                    // spinning forever — surface it instead.
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
                        continuation.finish(throwing: TranslationError.ollamaUnreachable)
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
        do {
            var config = self.config
            config.model = model
            // Empty prompt = load-only: Ollama loads the model and primes
            // keep_alive without running an inference pass, so a real translation
            // never has to queue behind the prewarm's own generation.
            let request = try Self.makeRequest(config: config, prompt: "", stream: false)
            _ = try await session.data(for: request)
        } catch {
            // best-effort: prewarm failures must not surface
        }
    }

    private static func makeRequest(config: LLMConfig, prompt: String, stream: Bool) throws -> URLRequest {
        var request = URLRequest(url: config.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(GenerateRequest(config: config, prompt: prompt, stream: stream))
        return request
    }
}
