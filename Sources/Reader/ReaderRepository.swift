import Foundation

struct SavedArticleMetadata: Codable, Sendable {
    let url: URL
    let savedAt: Date
    let title: String
    let translatedTitle: String
    var pinned: Bool?

    init(_ entry: ReaderCache.Entry) {
        url = entry.url; savedAt = entry.savedAt; title = entry.title
        translatedTitle = entry.translatedTitle; pinned = entry.pinned
    }
}

/// Owns every filesystem operation the reader performs. UI receives values, never file handles.
actor ReaderRepository {
    private let cache: ReaderCache
    private var saved: SavedArticleStore
    private var index: [URL: SavedArticleMetadata]?
    private let observeIO: @Sendable () -> Void
    private(set) var indexBuildCount = 0

    init(cache: ReaderCache = ReaderCache(), saved: SavedArticleStore = SavedArticleStore(),
         observeIO: @escaping @Sendable () -> Void = {}) {
        self.cache = cache; self.saved = saved; self.observeIO = observeIO
    }

    private func ensureIndex() {
        guard index == nil else { return }
        observeIO()
        index = Dictionary(saved.metadata().map { ($0.url, $0) }, uniquingKeysWith: { _, newest in newest })
        indexBuildCount += 1
    }

    func cached(_ url: URL, primary: PrimaryLanguage) -> ReaderCache.Entry? {
        ensureIndex(); observeIO()
        guard var entry = cache.load(url, primary: primary) else { return nil }
        entry.pinned = index?[url]?.pinned == true
        return entry
    }
    func removeCached(_ url: URL, primary: PrimaryLanguage) {
        observeIO()
        cache.remove(url, primary: primary)
    }
    func loadSaved(_ url: URL) -> ReaderCache.Entry? {
        ensureIndex(); observeIO()
        let entry = saved.load(url)
        index?[url] = entry.map(SavedArticleMetadata.init)
        return entry
    }
    @discardableResult
    func save(_ entry: ReaderCache.Entry, primary: PrimaryLanguage) throws -> ReaderCache.Entry {
        ensureIndex(); observeIO()
        let stored = try saved.save(entry, sweeping: false)
        index?[entry.url] = SavedArticleMetadata(stored)
        try sweep()
        try cache.save(stored, primary: primary)
        return stored
    }
    func setPinned(_ on: Bool, for url: URL, fallback: ReaderCache.Entry? = nil) throws -> ReaderCache.Entry? {
        ensureIndex(); observeIO()
        if saved.load(url) == nil, var fallback, fallback.url == url {
            fallback.pinned = on
            let stored = try saved.save(fallback, sweeping: false)
            index?[url] = SavedArticleMetadata(stored)
            return stored
        }
        try saved.setPinned(on, for: url)
        let entry = saved.load(url)
        index?[url] = entry.map(SavedArticleMetadata.init)
        return entry
    }
    func list() -> [SavedArticleMetadata] {
        ensureIndex()
        return (index ?? [:]).values.filter(isLive).sorted {
            if ($0.pinned == true) != ($1.pinned == true) { return $0.pinned == true }
            return $0.savedAt > $1.savedAt
        }
    }
    func setRetention(days: Int) throws {
        ensureIndex()
        guard SettingsStore.retentionChoices.contains(days) else { return }
        saved = SavedArticleStore(directory: saved.directory, ttl: TimeInterval(days) * 86400)
        try sweep()
    }
    private func isLive(_ entry: SavedArticleMetadata) -> Bool {
        entry.pinned == true || Date.now.timeIntervalSince(entry.savedAt) <= saved.ttl
    }
    private func sweep() throws {
        for entry in (index ?? [:]).values where !isLive(entry) {
            observeIO()
            try saved.remove(entry.url)
            index?.removeValue(forKey: entry.url)
        }
    }
}
