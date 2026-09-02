import Foundation
import Testing
@testable import Glosso

@Suite struct SavedArticleStoreTests {
    private let store: SavedArticleStore

    init() {
        store = SavedArticleStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true))
    }

    private func makeEntry(url: String = "https://example.com/article",
                           pinned: Bool? = nil) -> ReaderCache.Entry {
        ReaderCache.Entry(
            url: URL(string: url)!,
            savedAt: .now,
            title: "Original title",
            translatedTitle: "Przetłumaczony tytuł",
            byline: "Jane Doe",
            content: "<p>Original</p><p>Second</p>",
            summary: "Krótkie streszczenie.",
            translations: [0: "<p>Oryginał</p>", 2: "<p>Drugi</p>"],
            engine: "Google AI · gemma-4-31b-it",
            pinned: pinned
        )
    }

    /// The store stamps `savedAt` on save, so expiry tests rewrite the stored file's date directly.
    private func backdate(_ url: URL, by interval: TimeInterval) throws {
        let file = try #require(try FileManager.default
            .contentsOfDirectory(at: store.directory, includingPropertiesForKeys: nil)
            .first { (try? JSONDecoder().decode(ReaderCache.Entry.self, from: Data(contentsOf: $0)))?.url == url })
        var entry = try JSONDecoder().decode(ReaderCache.Entry.self, from: Data(contentsOf: file))
        entry.savedAt = .now.addingTimeInterval(-interval)
        try JSONEncoder().encode(entry).write(to: file)
        // The sweep pre-filters on mtime, so an aged entry must look aged on disk too.
        try FileManager.default.setAttributes(
            [.modificationDate: Date.now.addingTimeInterval(-interval)], ofItemAtPath: file.path)
    }

    @Test func saveThenLoadRoundTripsEveryField() {
        let entry = makeEntry(pinned: true)
        store.save(entry)

        let loaded = store.load(entry.url)
        #expect(loaded?.url == entry.url)
        #expect(loaded?.title == "Original title")
        #expect(loaded?.translatedTitle == "Przetłumaczony tytuł")
        #expect(loaded?.byline == "Jane Doe")
        #expect(loaded?.content == "<p>Original</p><p>Second</p>")
        #expect(loaded?.summary == "Krótkie streszczenie.")
        #expect(loaded?.translations == [0: "<p>Oryginał</p>", 2: "<p>Drugi</p>"])
        #expect(loaded?.engine == "Google AI · gemma-4-31b-it")
        #expect(loaded?.pinned == true)
    }

    // The retention window starts at translation time — a stale in-memory date must not shorten it.
    @Test func saveStampsAFreshSavedAt() throws {
        var entry = makeEntry()
        entry.savedAt = .now.addingTimeInterval(-30 * 24 * 3600)
        store.save(entry)

        let loaded = try #require(store.load(entry.url))
        #expect(abs(loaded.savedAt.timeIntervalSinceNow) < 60)
    }

    @Test func entryWithoutThePinnedFieldStillDecodes() throws {
        store.save(makeEntry())
        try backdate(makeEntry().url, by: 0)

        let loaded = try #require(store.load(makeEntry().url))
        #expect(loaded.pinned == nil)
        #expect(store.isPinned(loaded.url) == false)
    }

    @Test func setPinnedFlipsTheFlagWithoutTouchingSavedAt() throws {
        let entry = makeEntry()
        store.save(entry)
        let before = try #require(store.load(entry.url)).savedAt

        store.setPinned(true, for: entry.url)
        #expect(store.isPinned(entry.url))
        #expect(store.load(entry.url)?.savedAt == before)

        store.setPinned(false, for: entry.url)
        #expect(!store.isPinned(entry.url))
    }

    // Un-pinning must not silently destroy an article the TTL already outlived — it restarts the window.
    @Test func unpinningAnExpiredEntryRestartsItsRetentionWindow() throws {
        let entry = makeEntry(pinned: true)
        store.save(entry)
        try backdate(entry.url, by: 30 * 24 * 3600)

        store.setPinned(false, for: entry.url)

        let loaded = try #require(store.load(entry.url))
        #expect(loaded.pinned == false)
        #expect(abs(loaded.savedAt.timeIntervalSinceNow) < 60)
    }

    @Test func expiredUnpinnedEntryIsDeletedOnLoad() throws {
        let entry = makeEntry()
        store.save(entry)
        try backdate(entry.url, by: 8 * 24 * 3600)

        #expect(store.load(entry.url) == nil)
        let files = try FileManager.default.contentsOfDirectory(atPath: store.directory.path)
        #expect(files.isEmpty)
    }

    @Test func pinnedEntryNeverExpires() throws {
        let entry = makeEntry(pinned: true)
        store.save(entry)
        try backdate(entry.url, by: 30 * 24 * 3600)

        #expect(store.load(entry.url) != nil)

        store.save(makeEntry(url: "https://example.com/new"))
        #expect(store.load(entry.url) != nil)
    }

    @Test func pinnedEntrySurvivesShortenedRetentionSweep() throws {
        let long = SavedArticleStore(directory: store.directory, ttl: 90 * 24 * 3600)
        let entry = makeEntry(pinned: true)
        long.save(entry)
        try backdate(entry.url, by: 10 * 24 * 3600)

        store.sweep()

        #expect(store.load(entry.url)?.pinned == true)
    }

    // A re-translation saves an entry that says nothing about the pin — the stored flag must win.
    @Test func saveWithoutPinKeepsTheStoredPin() {
        let entry = makeEntry(pinned: true)
        store.save(entry)

        store.save(makeEntry(pinned: nil))

        #expect(store.isPinned(entry.url))
    }

    @Test func saveSweepsExpiredUnpinnedSiblings() throws {
        let old = makeEntry(url: "https://example.com/old")
        store.save(old)
        try backdate(old.url, by: 8 * 24 * 3600)

        store.save(makeEntry(url: "https://example.com/new"))

        #expect(store.load(old.url) == nil)
        let files = try FileManager.default.contentsOfDirectory(atPath: store.directory.path)
        #expect(files.count == 1)
    }

    @Test func listPutsPinnedFirstThenNewestFirst() throws {
        store.save(makeEntry(url: "https://example.com/a"))
        try backdate(URL(string: "https://example.com/a")!, by: 3600)
        store.save(makeEntry(url: "https://example.com/b"))
        store.save(makeEntry(url: "https://example.com/c", pinned: true))
        try backdate(URL(string: "https://example.com/c")!, by: 2 * 3600)

        let urls = store.list().map(\.url.absoluteString)
        #expect(urls == ["https://example.com/c", "https://example.com/b", "https://example.com/a"])
    }

    @Test func longerRetentionKeepsAnEntryTheDefaultWouldExpire() throws {
        let long = SavedArticleStore(directory: store.directory, ttl: 30 * 24 * 3600)
        let entry = makeEntry()
        long.save(entry)
        try backdate(entry.url, by: 10 * 24 * 3600)

        #expect(long.load(entry.url) != nil)
        #expect(store.load(entry.url) == nil)
    }

    // Shortening the period deletes immediately via sweep(), not at the next translation.
    @Test func sweepAppliesAShortenedRetentionAtOnce() throws {
        let long = SavedArticleStore(directory: store.directory, ttl: 90 * 24 * 3600)
        let entry = makeEntry()
        long.save(entry)
        try backdate(entry.url, by: 10 * 24 * 3600)

        store.sweep()

        let files = try FileManager.default.contentsOfDirectory(atPath: store.directory.path)
        #expect(files.isEmpty)
    }

    // The key deliberately carries no app version or language — a saved article survives updates.
    @Test func aSecondInstanceOverTheSameDirectoryLoadsTheEntry() {
        let entry = makeEntry()
        store.save(entry)

        let second = SavedArticleStore(directory: store.directory)
        #expect(second.load(entry.url) != nil)
    }
}
