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
            translations: [0: "<p>Oryginał</p>", 2: "<p>Drugi</p>"]
        )
    }

    @Test func saveThenLoadRoundTripsEveryField() {
        let entry = makeEntry()
        cache.save(entry)

        let loaded = cache.load(entry.url)
        #expect(loaded?.url == entry.url)
        #expect(loaded?.title == "Original title")
        #expect(loaded?.translatedTitle == "Przetłumaczony tytuł")
        #expect(loaded?.byline == "Jane Doe")
        #expect(loaded?.content == "<p>Original</p><p>Second</p>")
        #expect(loaded?.summary == "Krótkie streszczenie.")
        #expect(loaded?.translations == [0: "<p>Oryginał</p>", 2: "<p>Drugi</p>"])
    }

    @Test func loadMissesForUnknownURL() {
        cache.save(makeEntry())
        #expect(cache.load(URL(string: "https://example.com/other")!) == nil)
    }

    // The 7-day TTL is the whole point of the cache: a stale article must be
    // re-fetched and re-translated, and its file must not linger on disk.
    @Test func expiredEntryIsDeletedOnLoad() {
        let entry = makeEntry(savedAt: .now.addingTimeInterval(-8 * 24 * 3600))
        cache.save(entry)

        #expect(cache.load(entry.url) == nil)
        let files = try? FileManager.default.contentsOfDirectory(atPath: cache.directory.path)
        #expect(files?.isEmpty == true)
    }

    // Never-revisited URLs would otherwise pile up forever; each save sweeps
    // expired siblings by file modification date.
    @Test func saveSweepsExpiredSiblings() throws {
        let old = makeEntry(url: "https://example.com/old")
        cache.save(old)
        let oldFile = try #require(try FileManager.default
            .contentsOfDirectory(at: cache.directory, includingPropertiesForKeys: nil).first)
        try FileManager.default.setAttributes(
            [.modificationDate: Date.now.addingTimeInterval(-8 * 24 * 3600)],
            ofItemAtPath: oldFile.path)

        cache.save(makeEntry(url: "https://example.com/new"))

        #expect(cache.load(old.url) == nil)
        #expect(cache.load(URL(string: "https://example.com/new")!) != nil)
        let files = try FileManager.default.contentsOfDirectory(atPath: cache.directory.path)
        #expect(files.count == 1)
    }

    // Refresh must force a full re-run: after remove the next load is a miss,
    // and removing an absent entry must not disturb its siblings.
    @Test func removeDeletesEntryAndMissesUnknownURL() {
        let entry = makeEntry()
        cache.save(entry)

        cache.remove(URL(string: "https://example.com/absent")!)
        #expect(cache.load(entry.url) != nil)

        cache.remove(entry.url)
        #expect(cache.load(entry.url) == nil)
    }

    // Block ids are deterministic only within one build, so an entry written by
    // another app version must miss — replaying it could land translations on the
    // wrong blocks.
    @Test func entryFromAnotherVersionMisses() {
        let oldVersion = ReaderCache(directory: cache.directory, version: "0.6.0")
        let newVersion = ReaderCache(directory: cache.directory, version: "0.6.1")
        let entry = makeEntry()
        oldVersion.save(entry)

        #expect(newVersion.load(entry.url) == nil)
        #expect(oldVersion.load(entry.url) != nil)
    }

    @Test func distinctURLsGetDistinctFiles() throws {
        cache.save(makeEntry(url: "https://example.com/a"))
        cache.save(makeEntry(url: "https://example.com/b"))

        let files = try FileManager.default.contentsOfDirectory(atPath: cache.directory.path)
        #expect(files.count == 2)
        #expect(cache.load(URL(string: "https://example.com/a")!) != nil)
        #expect(cache.load(URL(string: "https://example.com/b")!) != nil)
    }
}
