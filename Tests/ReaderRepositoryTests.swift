import Foundation
import Synchronization
import Testing
@testable import Glosso

@Suite struct ReaderRepositoryTests {
    private func entry(_ n: Int = 0, bytes: Int = 20) -> ReaderCache.Entry {
        ReaderCache.Entry(url: URL(string: "https://example.com/\(n)")!, savedAt: .now,
                          title: "Title \(n)", translatedTitle: "Tytuł \(n)", byline: "",
                          content: String(repeating: "x", count: bytes), summary: "", translations: [0: "translated"])
    }

    @Test(arguments: [100, 1000])
    func libraryIndexAvoidsRepeatedIOAndRunsOffMain(count: Int) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SavedArticleStore(directory: root.appendingPathComponent("saved"))
        for n in 0..<count { try store.save(entry(n, bytes: 16_384), sweeping: false) }
        let calls = Mutex(0)
        let mainThreadIO = Mutex(false)
        let repository = ReaderRepository(cache: ReaderCache(directory: root.appendingPathComponent("cache")), saved: store,
            observeIO: { calls.withLock { $0 += 1 }; if Thread.isMainThread { mainThreadIO.withLock { $0 = true } } })
        let clock = ContinuousClock()
        let coldStart = clock.now
        let first = await repository.list()
        let coldTime = coldStart.duration(to: clock.now)
        let before = calls.withLock { $0 }
        let warmStart = clock.now
        for _ in 0..<10 { #expect(await repository.list().count == count) }
        let warmTime = warmStart.duration(to: clock.now)
        #expect(first.count == count)
        #expect(await repository.indexBuildCount == 1)
        #expect(calls.withLock { $0 } == before)
        #expect(!mainThreadIO.withLock { $0 })
        print("READER_BENCH count=\(count) cold=\(coldTime) warm10=\(warmTime) repeatedIO=0 mainThreadIO=false")
    }

    @Test func writesPinsAndRetentionKeepMetadataConsistent() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = ReaderRepository(cache: ReaderCache(directory: root.appendingPathComponent("cache")),
                                          saved: SavedArticleStore(directory: root.appendingPathComponent("saved")))
        let source = entry()
        _ = try await repository.save(source, primary: .polish)
        _ = try await repository.setPinned(true, for: source.url)
        #expect(await repository.list().first?.pinned == true)
        #expect(await repository.loadSaved(source.url)?.pinned == true)
        _ = try await repository.save(source, primary: .polish)
        #expect(await repository.list().first?.pinned == true)
        try await repository.setRetention(days: 7)
        #expect(await repository.list().count == 1)
        #expect(await repository.cached(source.url, primary: .english) == nil)
        #expect(await repository.cached(source.url, primary: .polish) != nil)
    }

    @Test func corruptFilesAreSkippedAndWriteErrorsAreReported() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bad = root.appendingPathComponent("bad.json")
        try Data("invalid".utf8).write(to: bad)
        let repository = ReaderRepository(saved: SavedArticleStore(directory: root))
        #expect(await repository.list().isEmpty)
        let unwritable = ReaderRepository(saved: SavedArticleStore(directory: bad))
        await #expect(throws: (any Error).self) { _ = try await unwritable.save(entry(), primary: .polish) }
        #expect(await unwritable.list().isEmpty)
    }
}
