import Foundation

/// Provisions the Ollama engine for the "no installed Ollama" path: downloads the
/// official macOS app zip and extracts only its `Contents/Resources/` — the signed
/// `ollama` binary, the MLX runner (`mlx_metal_*`) and the ggml libs — into an
/// app-private directory. Spike-confirmed (2026-06-18): the engine runs relocated
/// from here and serves `-mlx` tags. NOT trimmed: removing the bundled ggml libs
/// (only ~18 MB) kills `ollama serve` at startup, so the whole ~450 MB ships.
final class OllamaEngineDownloader: Sendable {
    static let downloadURL = URL(string: "https://ollama.com/download/Ollama-darwin.zip")!

    static func appSupport() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Glosso", isDirectory: true)
    }
    static var engineDir: URL { appSupport().appendingPathComponent("engine", isDirectory: true) }

    /// A runnable `ollama` binary already on disk, or nil when only a download
    /// would help. Prefers Glosso's own extracted engine, falls back to an
    /// installed Ollama.app.
    static func installedBinary() -> URL? {
        let own = engineDir.appendingPathComponent("ollama")
        if FileManager.default.isExecutableFile(atPath: own.path) { return own }
        let app = URL(fileURLWithPath: "/Applications/Ollama.app/Contents/Resources/ollama")
        if FileManager.default.isExecutableFile(atPath: app.path) { return app }
        return nil
    }

    /// Idempotent: no-op when Glosso's engine is already extracted. Otherwise
    /// downloads the zip (reporting 0…1 progress), unzips, and moves the app's
    /// `Resources/` into `engineDir`.
    func download(progress: @escaping @Sendable (Double) -> Void) async throws {
        let fm = FileManager.default
        if fm.isExecutableFile(atPath: Self.engineDir.appendingPathComponent("ollama").path) { return }

        let tmp = fm.temporaryDirectory.appendingPathComponent("glosso-engine-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        let zip = tmp.appendingPathComponent("Ollama-darwin.zip")
        try await Self.downloadFile(from: Self.downloadURL, to: zip, progress: progress)

        try Self.run("/usr/bin/unzip", ["-q", zip.path, "-d", tmp.path])
        let resources = tmp.appendingPathComponent("Ollama.app/Contents/Resources", isDirectory: true)
        guard fm.isExecutableFile(atPath: resources.appendingPathComponent("ollama").path) else {
            throw TranslationError.engineUnavailable
        }
        try? fm.removeItem(at: Self.engineDir)
        try fm.createDirectory(at: Self.appSupport(), withIntermediateDirectories: true)
        try fm.moveItem(at: resources, to: Self.engineDir)
    }

    private static func run(_ launchPath: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw TranslationError.engineUnavailable }
    }

    private static func downloadFile(from url: URL, to dest: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        final class Delegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
            let dest: URL
            let progress: @Sendable (Double) -> Void
            var cont: CheckedContinuation<Void, Error>?
            init(dest: URL, progress: @escaping @Sendable (Double) -> Void) { self.dest = dest; self.progress = progress }

            func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
                if totalBytesExpectedToWrite > 0 {
                    progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
                }
            }
            func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
                do {
                    try? FileManager.default.removeItem(at: dest)
                    try FileManager.default.moveItem(at: location, to: dest)
                    cont?.resume()
                } catch {
                    cont?.resume(throwing: error)
                }
                cont = nil
            }
            func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
                if let error { cont?.resume(throwing: error); cont = nil }
            }
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let delegate = Delegate(dest: dest, progress: progress)
            delegate.cont = cont
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            session.downloadTask(with: url).resume()
        }
    }
}
