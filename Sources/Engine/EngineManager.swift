import Foundation
import Darwin

final class EngineProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?

    func set(_ p: Process?) {
        lock.lock(); defer { lock.unlock() }
        if process !== p { process?.terminate() }
        process = p
    }
    func terminate() {
        lock.lock(); defer { lock.unlock() }
        process?.terminate()
        process = nil
    }
}

actor EngineManager: EngineProviding {
    private let session: URLSession
    private let downloader: OllamaEngineDownloader
    private let box: EngineProcessBox
    /// The resolved engine, kept with its base so liveness can be re-probed: the user can quit Ollama.app,
    /// and a spawned `serve` can die — a cached URL served blindly would fail every call until relaunch.
    private var resolved: (base: String, url: URL)?
    private var resolveTask: Task<URL, Error>?
    private var ensureTask: Task<Void, Error>?

    private static let reuseBase = "http://localhost:11434"

    init(session: URLSession = .shared,
         downloader: OllamaEngineDownloader = OllamaEngineDownloader(),
         box: EngineProcessBox = EngineProcessBox()) {
        self.session = session
        self.downloader = downloader
        self.box = box
    }

    func activeBaseURL() async throws -> URL {
        if let resolved {
            if await reachable(resolved.base) { return resolved.url }
            self.resolved = nil
        }
        if let resolveTask { return try await resolveTask.value }
        let task = Task { try await self.resolve() }
        resolveTask = task
        defer { resolveTask = nil }
        let url = try await task.value
        return url
    }

    func ensureEngine(progress: @escaping @Sendable (Double) -> Void) async throws {
        // Idempotent for real: a live engine — reused *or already spawned* — must not be respawned,
        // and a second concurrent caller joins the first instead of racing it past the reachability check.
        if let resolved, await reachable(resolved.base) { return }
        if let ensureTask { return try await ensureTask.value }
        let task = Task { try await self.provision(progress: progress) }
        ensureTask = task
        defer { ensureTask = nil }
        try await task.value
    }

    private func provision(progress: @escaping @Sendable (Double) -> Void) async throws {
        if await reachable(Self.reuseBase) {
            resolved = (Self.reuseBase, Self.generate(Self.reuseBase))
            return
        }
        if OllamaEngineDownloader.installedBinary() == nil {
            try await downloader.download(progress: progress)
        }
        guard let binary = OllamaEngineDownloader.installedBinary() else {
            throw TranslationError.engineUnavailable
        }
        _ = try await spawnAndRemember(binary: binary)
    }

    func status() async -> EngineStatus {
        if resolved != nil { return .ready }
        if await reachable(Self.reuseBase) { return .ready }
        if OllamaEngineDownloader.installedBinary() != nil { return .installable }
        return .needsDownload
    }

    private func resolve() async throws -> URL {
        if await reachable(Self.reuseBase) {
            resolved = (Self.reuseBase, Self.generate(Self.reuseBase))
            return Self.generate(Self.reuseBase)
        }
        guard let binary = OllamaEngineDownloader.installedBinary() else {
            throw TranslationError.engineUnavailable
        }
        return try await spawnAndRemember(binary: binary)
    }

    private func spawnAndRemember(binary: URL) async throws -> URL {
        let (base, url) = try await spawn(binary: binary)
        resolved = (base, url)
        return url
    }

    private func spawn(binary: URL) async throws -> (base: String, url: URL) {
        let port = Self.freePort()
        let p = Process()
        p.executableURL = binary
        p.arguments = ["serve"]
        var env = ProcessInfo.processInfo.environment
        env["OLLAMA_HOST"] = "127.0.0.1:\(port)"
        env["OLLAMA_KEEP_ALIVE"] = "30m"
        env["OLLAMA_MODELS"] = Self.modelsDir()
        p.environment = env
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { throw TranslationError.engineUnavailable }
        box.set(p)

        let base = "http://127.0.0.1:\(port)"
        guard await waitUntilReady(base) else {
            box.terminate()
            throw TranslationError.engineUnavailable
        }
        return (base, Self.generate(base))
    }

    private func reachable(_ base: String) async -> Bool {
        guard let url = URL(string: base + "/api/version") else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = 1.5
        do {
            let (_, response) = try await session.data(for: req)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    private func waitUntilReady(_ base: String) async -> Bool {
        for _ in 0..<60 {
            if await reachable(base) { return true }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return false
    }

    private static func generate(_ base: String) -> URL { URL(string: base + "/api/generate")! }

    private static func modelsDir() -> String {
        let shared = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ollama/models")
        if FileManager.default.fileExists(atPath: shared.path) { return shared.path }
        let priv = OllamaEngineDownloader.appSupport().appendingPathComponent("models")
        try? FileManager.default.createDirectory(at: priv, withIntermediateDirectories: true)
        return priv.path
    }

    private static func freePort() -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return 11435 }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { return 11435 }
        var assigned = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let got = withUnsafeMutablePointer(to: &assigned) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &len)
            }
        }
        guard got == 0 else { return 11435 }
        return Int(UInt16(bigEndian: assigned.sin_port))
    }
}
