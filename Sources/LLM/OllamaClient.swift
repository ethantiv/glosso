import Foundation

final class OllamaClient: LLMClient {
    private let session: URLSession
    private let config: LLMConfig

    init(session: URLSession = .shared, config: LLMConfig = .default) {
        self.session = session
        self.config = config
    }

    func translate(_ text: String) -> AsyncThrowingStream<TranslationEvent, Error> {
        let session = self.session
        let config = self.config

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let prompt = PromptBuilder.build(for: text)
                    let request = try Self.makeRequest(config: config, prompt: prompt, stream: true)
                    let (bytes, response) = try await session.bytes(for: request)

                    guard let http = response as? HTTPURLResponse else {
                        continuation.finish(throwing: TranslationError.ollamaUnreachable)
                        return
                    }
                    guard http.statusCode == 200 else {
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

    func prewarm() async throws {
        do {
            let request = try Self.makeRequest(config: config, prompt: " ", stream: false)
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
