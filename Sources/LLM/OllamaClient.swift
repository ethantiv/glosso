import Foundation

final class OllamaClient: LLMClient, GenerationBackend {
    private let session: URLSession
    private let config: LLMConfig
    private let endpointProvider: @Sendable () async throws -> URL

    init(session: URLSession = .shared, config: LLMConfig = .default, endpointProvider: @escaping @Sendable () async throws -> URL = { LLMConfig.default.endpoint }) {
        self.session = session
        self.config = config
        self.endpointProvider = endpointProvider
    }

    func generate(prompt: String, model: String, timeout: TimeInterval? = nil, numPredict: Int? = nil) async throws -> String {
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

    func streamGeneration(prompt: String, model: String) -> AsyncThrowingStream<TranslationEvent, Error> {
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
