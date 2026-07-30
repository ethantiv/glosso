import Foundation
import Testing
@testable import Glosso

@Suite struct ReaderCacheTests {
    private let cache: ReaderCache

    init() {
        cache = ReaderCache(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true))
    }

    private func makeEntry(url: String = "https://example.com/article",
                           savedAt: Date = .now) -> ReaderCache.Entry {
        ReaderCache.Entry(
            url: URL(string: url)!,
            savedAt: savedAt,
            title: "Original title",
            translatedTitle: "Przetłumaczony tytuł",
            byline: "Jane Doe",
            content: "<p>Original</p><p>Second</p>",
            summary: "Krótkie streszczenie.",
            translations: [0: "<p>Oryginał</p>", 2: "<p>Drugi</p>"],
            engine: "Google AI · gemma-4-31b-it"
        )
    }

    @Test func saveThenLoadRoundTripsEveryField() {
        let entry = makeEntry()
        cache.save(entry, primary: .polish)

        let loaded = cache.load(entry.url, primary: .polish)
        #expect(loaded?.url == entry.url)
        #expect(loaded?.title == "Original title")
        #expect(loaded?.translatedTitle == "Przetłumaczony tytuł")
        #expect(loaded?.byline == "Jane Doe")
        #expect(loaded?.content == "<p>Original</p><p>Second</p>")
        #expect(loaded?.summary == "Krótkie streszczenie.")
        #expect(loaded?.translations == [0: "<p>Oryginał</p>", 2: "<p>Drugi</p>"])
        // The engine that produced the stored text, not the one selected when it is replayed days later.
        #expect(loaded?.engine == "Google AI · gemma-4-31b-it")
    }

    // Entries written before the label existed must still load; the replay then falls back to the current engine.
    @Test func loadsAnEntryWithoutAnEngineLabel() throws {
        var entry = makeEntry()
        entry.engine = nil
        cache.save(entry, primary: .polish)

        let loaded = try #require(cache.load(entry.url, primary: .polish))
        #expect(loaded.engine == nil)
        #expect(loaded.translations == entry.translations)
    }

    @Test func loadMissesForUnknownURL() {
        cache.save(makeEntry(), primary: .polish)
        #expect(cache.load(URL(string: "https://example.com/other")!, primary: .polish) == nil)
    }

    @Test func expiredEntryIsDeletedOnLoad() {
        let entry = makeEntry(savedAt: .now.addingTimeInterval(-8 * 24 * 3600))
        cache.save(entry, primary: .polish)

        #expect(cache.load(entry.url, primary: .polish) == nil)
        let files = try? FileManager.default.contentsOfDirectory(atPath: cache.directory.path)
        #expect(files?.isEmpty == true)
    }

    @Test func saveSweepsExpiredSiblings() throws {
        let old = makeEntry(url: "https://example.com/old")
        cache.save(old, primary: .polish)
        let oldFile = try #require(try FileManager.default
            .contentsOfDirectory(at: cache.directory, includingPropertiesForKeys: nil).first)
        try FileManager.default.setAttributes(
            [.modificationDate: Date.now.addingTimeInterval(-8 * 24 * 3600)],
            ofItemAtPath: oldFile.path)

        cache.save(makeEntry(url: "https://example.com/new"), primary: .polish)

        #expect(cache.load(old.url, primary: .polish) == nil)
        #expect(cache.load(URL(string: "https://example.com/new")!, primary: .polish) != nil)
        let files = try FileManager.default.contentsOfDirectory(atPath: cache.directory.path)
        #expect(files.count == 1)
    }

    @Test func removeDeletesEntryAndMissesUnknownURL() {
        let entry = makeEntry()
        cache.save(entry, primary: .polish)

        cache.remove(URL(string: "https://example.com/absent")!, primary: .polish)
        #expect(cache.load(entry.url, primary: .polish) != nil)

        cache.remove(entry.url, primary: .polish)
        #expect(cache.load(entry.url, primary: .polish) == nil)
    }

    @Test func entryFromAnotherVersionMisses() {
        let oldVersion = ReaderCache(directory: cache.directory, version: "0.6.0")
        let newVersion = ReaderCache(directory: cache.directory, version: "0.6.1")
        let entry = makeEntry()
        oldVersion.save(entry, primary: .polish)

        #expect(newVersion.load(entry.url, primary: .polish) == nil)
        #expect(oldVersion.load(entry.url, primary: .polish) != nil)
    }

    @Test func entryForAnotherPrimaryLanguageMisses() {
        let entry = makeEntry()
        cache.save(entry, primary: .polish)

        #expect(cache.load(entry.url, primary: .english) == nil)
        #expect(cache.load(entry.url, primary: .polish) != nil)
    }

    @Test func distinctURLsGetDistinctFiles() throws {
        cache.save(makeEntry(url: "https://example.com/a"), primary: .polish)
        cache.save(makeEntry(url: "https://example.com/b"), primary: .polish)

        let files = try FileManager.default.contentsOfDirectory(atPath: cache.directory.path)
        #expect(files.count == 2)
        #expect(cache.load(URL(string: "https://example.com/a")!, primary: .polish) != nil)
        #expect(cache.load(URL(string: "https://example.com/b")!, primary: .polish) != nil)
    }
}
