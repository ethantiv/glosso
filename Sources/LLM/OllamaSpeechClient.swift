import Foundation

/// The local engine's speech side (`lfm3-audio`). Audio only travels through Ollama's OpenAI-compatible
/// `/v1/audio/*` routes — the native `/api/chat` and `/api/generate` have no audio fields. The native API still
/// answers the version, model and keep_alive checks, which `/v1` can't.
final class OllamaSpeechClient: SpeechSynthesizing {
    /// ~0.25 s of 24 kHz 16-bit mono: playback starts on the first one, and an even size keeps samples whole.
    static let bufferBytes = 12_000

    private let session: URLSession
    private let endpointProvider: @Sendable () async throws -> URL
    private let modelManager: any ModelManaging
    private let keepAliveProvider: @Sendable () async -> String
    /// Called once when a pull starts, so the user learns why the first use takes minutes.
    private let onDownload: @Sendable () -> Void

    init(session: URLSession = .shared,
         endpointProvider: @escaping @Sendable () async throws -> URL,
         modelManager: any ModelManaging,
         keepAliveProvider: @escaping @Sendable () async -> String = { LLMConfig.default.keepAlive },
         onDownload: @escaping @Sendable () -> Void = {}) {
        self.session = session
        self.endpointProvider = endpointProvider
        self.modelManager = modelManager
        self.keepAliveProvider = keepAliveProvider
        self.onDownload = onDownload
    }

    func prepare(progress: @escaping @Sendable (Double?) -> Void) async throws {
        let base = try await baseURL()
        let (versionData, _) = try await send(URLRequest(url: base.appending(path: "api/version")))
        // A struct, not [String: String]: one extra non-string field would otherwise read as "engine too old".
        struct Version: Decodable { let version: String }
        let version = (try? JSONDecoder().decode(Version.self, from: versionData))?.version ?? "?"
        // An older server answers /v1/audio/* with a bare-text 404, indistinguishable from a missing model.
        guard SpeechAudio.isSupported(version: version) else { throw SpeechError.engineTooOld(version) }

        let (showData, show) = try await send(Self.post(base.appending(path: "api/show"), ["model": SpeechAudio.speechModel]))
        switch show.statusCode {
        case 200:
            break
        case 404:
            onDownload()
            progress(0)
            for try await step in modelManager.pull(SpeechAudio.speechModel) where step.total > 0 {
                progress(Double(step.completed) / Double(step.total))
            }
        default:
            throw Self.serverError(showData, status: show.statusCode)
        }
        progress(nil)

        // `/v1/audio/*` takes no keep_alive; an empty native generate loads the model and sets how long it stays.
        let warm = Self.post(base.appending(path: "api/generate"),
                             ["model": SpeechAudio.speechModel, "keep_alive": await keepAliveProvider()])
        _ = try? await session.data(for: warm)
    }

    func synthesize(_ text: String, voice: String) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = Self.post(try await self.baseURL().appending(path: "v1/audio/speech"), [
                        "model": SpeechAudio.speechModel, "input": text, "voice": voice, "response_format": "pcm",
                    ])
                    let (bytes, response) = try await self.session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else { throw TranslationError.ollamaUnreachable }
                    guard http.statusCode == 200 else {
                        var body = Data()
                        for try await byte in bytes where body.count < 4096 { body.append(byte) }
                        throw Self.serverError(body, status: http.statusCode)
                    }
                    var buffer = Data()
                    for try await byte in bytes {
                        buffer.append(byte)
                        if buffer.count >= Self.bufferBytes {
                            continuation.yield(buffer)
                            buffer = Data()
                        }
                    }
                    // A dangling odd byte is half a sample.
                    if buffer.count > 1 { continuation.yield(buffer.prefix(buffer.count & ~1)) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.mapped(error))
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    /// The `/v1` routes wrap errors OpenAI-style (`{"error":{"message":…}}`), the native ones as `{"error":"…"}`.
    static func serverError(_ data: Data, status: Int) -> SpeechError {
        struct OpenAIEnvelope: Decodable {
            struct Body: Decodable { let message: String }
            let error: Body
        }
        if let message = try? JSONDecoder().decode(OpenAIEnvelope.self, from: data).error.message { return .server(message) }
        if let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"] { return .server(message) }
        return .server("HTTP \(status)")
    }

    /// The engine's own URL is `…/api/generate`; the speech routes hang off its root.
    private func baseURL() async throws -> URL {
        try await endpointProvider().deletingLastPathComponent().deletingLastPathComponent()
    }

    private static func post(_ url: URL, _ body: [String: String]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(body)
        return request
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw TranslationError.ollamaUnreachable }
            return (data, http)
        } catch {
            throw Self.mapped(error)
        }
    }

    private static func mapped(_ error: Error) -> Error {
        if let error = error as? URLError, error.code == .cancelled { return TranslationError.cancelled }
        if error is CancellationError { return TranslationError.cancelled }
        if error is TranslationError || error is SpeechError { return error }
        return TranslationError.ollamaUnreachable
    }
}
