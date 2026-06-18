import Foundation

/// Pulls and deletes models on the active engine (see `ModelManaging`). The
/// `/api/pull` and `/api/delete` URLs are derived per call from the resolved
/// `/api/generate` endpoint, so they track whichever engine is active.
final class OllamaModelManager: ModelManaging {
    private let session: URLSession
    private let endpointProvider: @Sendable () async throws -> URL

    init(session: URLSession = .shared, endpointProvider: @escaping @Sendable () async throws -> URL = { LLMConfig.default.endpoint }) {
        self.session = session
        self.endpointProvider = endpointProvider
    }

    func pull(_ model: String) -> AsyncThrowingStream<PullProgress, Error> {
        let session = self.session
        let endpointProvider = self.endpointProvider
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = try await Self.makeRequest("pull", method: "POST", model: model, endpointProvider: endpointProvider)
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        continuation.finish(throwing: TranslationError.ollamaUnreachable); return
                    }
                    guard http.statusCode == 200 else {
                        continuation.finish(throwing: TranslationError.httpStatus(http.statusCode)); return
                    }
                    for try await line in bytes.lines {
                        if Task.isCancelled { continuation.finish(throwing: TranslationError.cancelled); return }
                        guard let parsed = PullProgressParser.parse(line: line) else { continue }
                        if let error = parsed.error {
                            continuation.finish(throwing: TranslationError.ollamaError(error)); return
                        }
                        continuation.yield(parsed.progress)
                        if parsed.success { break }
                    }
                    continuation.finish()
                } catch let error as URLError where error.code == .cancelled {
                    continuation.finish(throwing: TranslationError.cancelled)
                } catch is CancellationError {
                    continuation.finish(throwing: TranslationError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    func delete(_ model: String) async throws {
        var request = try await Self.makeRequest("delete", method: "DELETE", model: model, endpointProvider: endpointProvider)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw TranslationError.ollamaUnreachable
        }
    }

    // .../api/generate -> .../api/<path>
    private static func makeRequest(_ path: String, method: String, model: String, endpointProvider: @Sendable () async throws -> URL) async throws -> URLRequest {
        let url = try await endpointProvider().deletingLastPathComponent().appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = try JSONEncoder().encode(["model": model])
        return request
    }
}
