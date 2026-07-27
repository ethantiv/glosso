import Foundation

final class OllamaClient: LLMClient {
    private let session: URLSession
    private let config: LLMConfig
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
        let cap = max(256, html.utf8.count)
        return try await generate(prompt: PromptBuilder.buildBlockTranslation(html: html, into: primary),
                                  model: model, timeout: Self.longFormTimeout, numPredict: cap)
    }

    func readerSummary(of text: String, into primary: PrimaryLanguage, model: String) async throws -> String {
        try await generate(prompt: PromptBuilder.buildReaderSummary(text: text, into: primary),
                           model: model, timeout: Self.longFormTimeout, numPredict: 512)
    }

    func askArticle(question: String, history: [(question: String, answer: String)], article: String, into primary: PrimaryLanguage, model: String) async throws -> String {
        try await generate(prompt: PromptBuilder.buildAskArticle(question: question, history: history, article: article, into: primary),
                           model: model, timeout: Self.longFormTimeout, numPredict: 1024)
    }

    func articleQuestions(about article: String, into primary: PrimaryLanguage, model: String) async throws -> [String] {
        let raw = try await generate(prompt: PromptBuilder.buildArticleQuestions(article: article, into: primary),
                                     model: model, timeout: Self.longFormTimeout, numPredict: 256)
        return Array(AlternativesParser.parse(raw, original: "").prefix(5))
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

    private static let longFormTimeout: TimeInterval = 300

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
        if let message = chunk?.error { throw TranslationError.ollamaError(message) }
        guard http.statusCode == 200 else { throw TranslationError.httpStatus(http.statusCode) }
        guard let body = chunk?.response else { throw TranslationError.malformedStream }
        guard chunk?.doneReason != "length" else { throw TranslationError.malformedStream }
        return body
    }

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
            let endpoint = try await endpointProvider()
            let request = try Self.makeRequest(config: config, model: model, prompt: "", stream: false, endpoint: endpoint)
            _ = try await session.data(for: request)
        } catch {
            // best-effort: prewarm failures must not surface
        }
    }

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
