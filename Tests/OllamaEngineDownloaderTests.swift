import Foundation
import Synchronization
import Testing
@testable import Glosso

@Suite struct OllamaEngineDownloaderTests {
    @Test(arguments: [false, true])
    func onlyVerifiedArchivesCanBeInstalled(signatureAccepted: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let staging = root.appendingPathComponent("staging")
        let destination = root.appendingPathComponent("engine")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let commands = Mutex<[(String, [String])]>([])
        let downloader = OllamaEngineDownloader(directory: destination, temporaryDirectory: staging,
            downloadFile: { _, to, progress in try Data().write(to: to); progress(1) },
            runCommand: { executable, args in
                commands.withLock { $0.append((executable, args)) }
                if executable == "/usr/bin/ditto" {
                    let resources = URL(fileURLWithPath: args.last!).appendingPathComponent("Ollama.app/Contents/Resources")
                    try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
                    let binary = resources.appendingPathComponent("ollama")
                    try Data("test fixture, never executed".utf8).write(to: binary)
                    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: binary.path)
                } else if !signatureAccepted { throw TranslationError.engineUnavailable }
            }, notify: { _ in })
        if signatureAccepted {
            try await downloader.download(progress: { _ in })
        } else {
            await #expect(throws: TranslationError.engineUnavailable) { try await downloader.download(progress: { _ in }) }
        }
        let calls = commands.withLock { $0 }
        #expect(calls.map(\.0) == ["/usr/bin/ditto", "/usr/bin/codesign"])
        #expect(calls[1].1.contains("-R=anchor apple generic and certificate leaf[subject.OU] = \"3MU9H2V9Y9\""))
        #expect(calls[1].1.contains("--strict"))
        #expect(calls[1].1.contains("--deep"))
        #expect(FileManager.default.isExecutableFile(atPath: destination.appendingPathComponent("ollama").path) == signatureAccepted)
        #expect(try FileManager.default.contentsOfDirectory(atPath: staging.path).isEmpty)
    }

    @Test func downloadFailureNeverExtractsOrInstallsAndCleansStaging() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let commands = Mutex(0)
        let downloader = OllamaEngineDownloader(directory: root.appendingPathComponent("engine"), temporaryDirectory: root,
            downloadFile: { _, _, _ in throw URLError(.badServerResponse) },
            runCommand: { _, _ in commands.withLock { $0 += 1 } }, notify: { _ in })
        await #expect(throws: URLError.self) { try await downloader.download(progress: { _ in }) }
        #expect(commands.withLock { $0 } == 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }
}
