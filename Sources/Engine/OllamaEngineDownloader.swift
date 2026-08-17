import Foundation

final class OllamaEngineDownloader: Sendable {
    static let downloadURL = URL(string: "https://ollama.com/download/Ollama-darwin.zip")!

    static func appSupport() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Glosso", isDirectory: true)
    }
    static var engineDir: URL { appSupport().appendingPathComponent("engine", isDirectory: true) }

    static func installedBinary() -> URL? {
        let own = engineDir.appendingPathComponent("ollama")
        if FileManager.default.isExecutableFile(atPath: own.path) { return own }
        let app = URL(fileURLWithPath: "/Applications/Ollama.app/Contents/Resources/ollama")
        if FileManager.default.isExecutableFile(atPath: app.path) { return app }
        return nil
    }

    func download(progress: @escaping @Sendable (Double) -> Void) async throws {
        let fm = FileManager.default
        if fm.isExecutableFile(atPath: Self.engineDir.appendingPathComponent("ollama").path) { return }

        let tmp = fm.temporaryDirectory.appendingPathComponent("glosso-engine-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        let zip = tmp.appendingPathComponent("Ollama-darwin.zip")
        try await Self.downloadFile(from: Self.downloadURL, to: zip, progress: progress)

        // ditto, not unzip: it preserves the metadata the signature covers (scripts/package.sh relies on the
        // same property for our own zip), so a benign extraction artifact can't read as tampering.
        try Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, tmp.path])
        // TLS protects the transfer; this protects against a swapped archive — the binary is about to be
        // executed, so it must carry an intact signature from Ollama's own Developer ID team (a bare
        // --verify would accept any ad-hoc re-sign). Team 3MU9H2V9Y9 = "Infra Technologies, Inc" (Ollama).
        do {
            try Self.run("/usr/bin/codesign", [
                "--verify", "--deep", "--strict",
                "-R=anchor apple generic and certificate leaf[subject.OU] = \"3MU9H2V9Y9\"",
                tmp.appendingPathComponent("Ollama.app").path,
            ])
        } catch {
            SystemUserNotifier.post(loc("Pobrany silnik nie przeszedł weryfikacji podpisu — instalacja przerwana.",
                                        "The downloaded engine failed signature verification — install aborted."))
            throw error
        }
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
                if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
                    cont?.resume(throwing: TranslationError.engineUnavailable)
                    cont = nil
                    return
                }
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
                s.finishTasksAndInvalidate()
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
