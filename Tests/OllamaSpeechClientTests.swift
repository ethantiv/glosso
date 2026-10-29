import Foundation
import Testing
@testable import Glosso

@Suite struct OllamaSpeechClientTests {
    private let http = HTTPFixture()
    private let manager = FakePullManager()

    private func makeClient(keepAlive: String = "60m", onDownload: @escaping @Sendable () -> Void = {}) -> OllamaSpeechClient {
        let configuration = URLSessionConfiguration.ephemeral
        http.configure(configuration)
        return OllamaSpeechClient(
            session: URLSession(configuration: configuration),
            endpointProvider: { URL(string: "http://localhost:11434/api/generate")! },
            modelManager: manager,
            keepAliveProvider: { keepAlive },
            onDownload: onDownload
        )
    }

    private static func respond(_ request: URLRequest, _ status: Int, _ body: String) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
    }

    private static func body(of request: URLRequest) -> Data {
        guard let stream = request.httpBodyStream else { return request.httpBody ?? Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(contentsOf: buffer[0..<read])
        }
        return data
    }

    @Test func synthesizeAsksForPCMAndStreamsEvenBuffers() async throws {
        let sent = Locked<String>("")
        http.handler = { request in
            #expect(request.url?.path == "/v1/audio/speech")
            sent.set(String(decoding: Self.body(of: request), as: UTF8.self))
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(repeating: 1, count: 25_001))
        }
        defer { http.handler = nil }

        var sizes: [Int] = []
        for try await buffer in makeClient().synthesize("Dzień dobry", voice: "female-polish") { sizes.append(buffer.count) }

        #expect(sizes == [12_000, 12_000, 1_000])
        #expect(sent.value.contains(#""response_format":"pcm""#))
        #expect(sent.value.contains(#""voice":"female-polish""#))
        #expect(sent.value.contains(#""model":"lfm3-audio""#))
    }

    @Test func synthesizeSurfacesTheServerMessage() async {
        http.handler = { request in
            Self.respond(request, 400, #"{"error":{"message":"voice is not supported","type":"invalid_request_error"}}"#)
        }
        defer { http.handler = nil }

        await #expect(throws: SpeechError.server("voice is not supported")) {
            for try await _ in makeClient().synthesize("Hi", voice: "Zoey") {}
        }
    }

    @Test func prepareRejectsAnOldEngine() async {
        http.handler = { request in Self.respond(request, 200, #"{"version":"0.40.11"}"#) }
        defer { http.handler = nil }

        await #expect(throws: SpeechError.engineTooOld("0.40.11")) {
            try await makeClient().prepare(progress: { _ in })
        }
        #expect(manager.pulled.isEmpty)
    }

    @Test func preparePullsAMissingModelThenWarmsIt() async throws {
        let warmBody = Locked<String>("")
        let progress = Locked<[Double?]>([])
        let downloads = Locked<Int>(0)
        http.handler = { request in
            switch request.url?.path {
            case "/api/version": return Self.respond(request, 200, #"{"version":"0.40.12"}"#)
            case "/api/show": return Self.respond(request, 404, #"{"error":"model 'lfm3-audio:latest' not found"}"#)
            case "/api/generate":
                warmBody.set(String(decoding: Self.body(of: request), as: UTF8.self))
                return Self.respond(request, 200, #"{"done":true,"done_reason":"load"}"#)
            default: return Self.respond(request, 500, "")
            }
        }
        defer { http.handler = nil }

        try await makeClient(keepAlive: "5m", onDownload: { downloads.update { $0 += 1 } })
            .prepare(progress: { value in progress.update { $0.append(value) } })

        #expect(manager.pulled == ["lfm3-audio"])
        #expect(downloads.value == 1)
        #expect(progress.value == [0, 0.5, nil])
        #expect(warmBody.value.contains(#""keep_alive":"5m""#))
    }

    @Test func prepareSkipsThePullWhenTheModelIsThere() async throws {
        http.handler = { request in
            request.url?.path == "/api/version"
                // The extra non-string field must not read as an old engine.
                ? Self.respond(request, 200, #"{"version":"0.41.0","build":{"commit":"abc"}}"#)
                : Self.respond(request, 200, "{}")
        }
        defer { http.handler = nil }

        try await makeClient().prepare(progress: { _ in })

        #expect(manager.pulled.isEmpty)
    }
}

final class FakePullManager: ModelManaging, @unchecked Sendable {
    private let lock = NSLock()
    private var models: [String] = []
    var pulled: [String] { lock.withLock { models } }

    func pull(_ model: String) -> AsyncThrowingStream<PullProgress, Error> {
        lock.withLock { models.append(model) }
        return AsyncThrowingStream { continuation in
            continuation.yield(PullProgress(status: "pulling", completed: 50, total: 100))
            continuation.yield(PullProgress(status: "success", completed: 0, total: 0))
            continuation.finish()
        }
    }

    func delete(_ model: String) async throws {}
}
