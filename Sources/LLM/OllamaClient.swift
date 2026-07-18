import Foundation

final class OllamaClient: LLMClient {
    private let session: URLSession
    private let config: LLMConfig
    // Resolved per call so the active engine's host:port (the user's Ollama on
    // 11434, or a private engine we spawned on a free port) can change at runtime
    // without rebuilding the client. The empirical invariants stay in `config`.
    private let endpointProvider: @Sendable () async throws -> URL

    init(session: URLSession = .shared, config: LLMConfig = .default, endpointProvider: @escaping @Sendable () async throws -> URL = { LLMConfig.default.endpoint }) {
        self.session = session
        self.config = config
        self.endpointProvider = endpointProvider
    }

    func run(_ text: String, action: Action, model: String, primary: PrimaryLanguage, second: SecondLanguage, formality: Formality, style: Bool) -> AsyncThrowingStream<TranslationEvent, Error> {
        stream(prompt: PromptBuilder.build(for: text, action: action, primary: primary, second: second, formality: formality, style: style), model: model)
    }

    func reword(original: String, to chosen: String, in translation: String, source: String, primary: PrimaryLanguage, second: SecondLanguage, formality: Formality, model: String) -> AsyncThrowingStream<TranslationEvent, Error> {
        stream(prompt: PromptBuilder.buildReword(original: original, chosen: chosen, translation: translation, source: source, primary: primary, second: second, formality: formality), model: model)
    }

    func alternatives(for word: String, in translation: String, source: String, primary: PrimaryLanguage, second: SecondLanguage, model: String) async throws -> [String] {
        let prompt = PromptBuilder.buildAlternatives(word: word, translation: translation, source: source, primary: primary, second: second)
        return AlternativesParser.parse(try await generate(prompt: prompt, model: model), original: word)
    }

    func reply(to text: String, model: String) async throws -> [String] {
        let prompt = PromptBuilder.buildReply(text: text)
        return ReplyParser.parse(try await generate(prompt: prompt, model: model))
    }

    func translateBlock(html: String, into primary: PrimaryLanguage, model: String) async throws -> String {
        // The cap scales with the input and has no flat ceiling: a faithful
        // translation re-emits the markup plus the text at ~3 bytes/token, so
        // one token per input byte is a ~3× margin even for Polish — a flat
        // ceiling falsely truncated near-cap blocks with heavy markup. Small
        // junk blocks still die in seconds; oversized legitimate ones stay
        // bounded by longFormTimeout, exactly as before this cap existed.
        let cap = max(256, html.utf8.count)
        return try await generate(prompt: PromptBuilder.buildBlockTranslation(html: html, into: primary),
                                  model: model, timeout: Self.longFormTimeout, numPredict: cap)
    }

    func readerSummary(of text: String, into primary: PrimaryLanguage, model: String) async throws -> String {
        try await generate(prompt: PromptBuilder.buildReaderSummary(text: text, into: primary),
                           model: model, timeout: Self.longFormTimeout, numPredict: 512)
    }

    func explain(word: String, in translation: String, source: String, primary: PrimaryLanguage, second: SecondLanguage, model: String) async throws -> String {
        let prompt = PromptBuilder.buildExplain(word: word, translation: translation, source: source, primary: primary, second: second)
        return ExplanationParser.clean(try await generate(prompt: prompt, model: model))
    }

    func explainFix(error: String, correction: String, original: String, corrected: String, primary: PrimaryLanguage, second: SecondLanguage, englishRules: Bool, style: Bool, model: String) async throws -> String {
        let prompt = PromptBuilder.buildExplainFix(error: error, correction: correction, original: original, corrected: corrected, primary: primary, second: second, englishRules: englishRules, style: style)
        return ExplanationParser.clean(try await generate(prompt: prompt, model: model))
    }

    func explainRegister(previous: String, current: String, from: Formality, to: Formality, source: String, primary: PrimaryLanguage, second: SecondLanguage, model: String) async throws -> String {
        let prompt = PromptBuilder.buildExplainRegister(previous: previous, current: current, from: from, to: to, source: source, primary: primary, second: second)
        return ExplanationParser.clean(try await generate(prompt: prompt, model: model))
    }

    // A non-streaming generate receives no bytes until the whole generation is
    // done, so the request timeout is its total budget. The reader's article
    // blocks and summaries legitimately run for minutes on a big model; the
    // popup lookups behind a spinner must fail fast instead. The reader calls
    // also cap the output tokens (num_predict): a small model looping on a
    // markup-dense block would otherwise burn the whole 300 s with the UI
    // frozen — a bounded generation fails in minutes, not the full timeout.
    private static let longFormTimeout: TimeInterval = 300

    // One non-streaming generate, shared by alternatives() and explain() (issue
    // #17/#39). Same locked invariants as translate; only the model is
    // user-selectable per call. Returns the model's raw `response` body; each
    // caller parses it (AlternativesParser / ExplanationParser).
    private func generate(prompt: String, model: String, timeout: TimeInterval? = nil, numPredict: Int? = nil) async throws -> String {
        let endpoint = try await endpointProvider()
        let request = try Self.makeRequest(config: config, model: model, prompt: prompt, stream: false, endpoint: endpoint, timeout: timeout, numPredict: numPredict)
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
        // A generation cut off by num_predict is a runaway, not a result — a
        // truncated HTML fragment must never reach the DOM.
        guard chunk?.doneReason != "length" else { throw TranslationError.malformedStream }
        return body
    }

    // Shared NDJSON streaming used by translate() and reword(): only the model is
    // user-selectable per call; the base config keeps the empirical invariants
    // (think:false, temperature:0, keep_alive, endpoint) locked.
    private func stream(prompt: String, model: String) -> AsyncThrowingStream<TranslationEvent, Error> {
        let session = self.session
        let baseConfig = self.config
        let endpointProvider = self.endpointProvider

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let endpoint = try await endpointProvider()
                    let request = try Self.makeRequest(config: baseConfig, model: model, prompt: prompt, stream: true, endpoint: endpoint)
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
            // Empty prompt = load-only: Ollama loads the model and primes
            // keep_alive without running an inference pass, so a real translation
            // never has to queue behind the prewarm's own generation.
            let endpoint = try await endpointProvider()
            let request = try Self.makeRequest(config: config, model: model, prompt: "", stream: false, endpoint: endpoint)
            _ = try await session.data(for: request)
        } catch {
            // best-effort: prewarm failures must not surface
        }
    }

    // Applies the per-call model over the base config (whose empirical invariants
    // — think:false, temperature:0, keep_alive — stay locked) in one place, so no
    // caller hand-copies the config to swap the model. The endpoint is resolved by
    // the caller via `endpointProvider`, not taken from the config.
    private static func makeRequest(config baseConfig: LLMConfig, model: String, prompt: String, stream: Bool, endpoint: URL, timeout: TimeInterval? = nil, numPredict: Int? = nil) throws -> URLRequest {
        var config = baseConfig
        config.model = model
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        if let timeout { request.timeoutInterval = timeout }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(GenerateRequest(config: config, prompt: prompt, stream: stream, numPredict: numPredict))
        return request
    }
}
