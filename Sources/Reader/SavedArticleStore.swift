import CryptoKit
import Foundation

/// Durable article history: every completed translation lands here for the configured retention (7 days by
/// default, the panel offers 7/30/90); a pinned entry stays until unpinned.
/// Unlike `ReaderCache`, the key carries no app version or language and the files live in Application Support —
/// a saved article must survive updates and never be purged by the OS.
struct SavedArticleStore: Sendable {
    let directory: URL
    /// Retention of unpinned entries; the reader passes the user's 7/30/90-day choice in.
    let ttl: TimeInterval

    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Glosso/saved-articles", isDirectory: true),
         ttl: TimeInterval = 7 * 24 * 3600) {
        self.directory = directory
        self.ttl = ttl
    }

    /// Deletes what the current retention no longer covers — called when the user shortens the period.
    func sweep() {
        sweepExpired()
    }

    /// nil on miss or decode failure; an expired unpinned entry is deleted and reported as a miss.
    func load(_ url: URL) -> ReaderCache.Entry? {
        let file = fileURL(for: url)
        guard let entry = decode(file) else { return nil }
        guard isLive(entry) else {
            try? FileManager.default.removeItem(at: file)
            return nil
        }
        return entry
    }

    /// The one retention rule — load, list and the sweep must agree on it.
    private func isLive(_ entry: ReaderCache.Entry) -> Bool {
        entry.pinned == true || Date.now.timeIntervalSince(entry.savedAt) <= ttl
    }

    func isPinned(_ url: URL) -> Bool {
        decode(fileURL(for: url))?.pinned == true
    }

    /// Stamps a fresh `savedAt` — the retention window starts at translation time.
    func save(_ entry: ReaderCache.Entry) {
        var entry = entry
        entry.savedAt = .now
        write(entry)
        sweepExpired()
    }

    /// Flips the flag without touching `savedAt` — pinning is not a re-translation. Un-pinning an entry that
    /// already outlived the TTL does restart it, or the click would silently destroy the article.
    func setPinned(_ on: Bool, for url: URL) {
        guard var entry = decode(fileURL(for: url)) else { return }
        entry.pinned = on
        if !on, !isLive(entry) { entry.savedAt = .now }
        write(entry)
    }

    /// Pinned first, then newest first. Expired entries are filtered, not deleted — the sweep owns deletion.
    /// ponytail: decodes full entries (content included); a sidecar index if the panel ever hitches.
    func list() -> [ReaderCache.Entry] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.compactMap(decode).filter(isLive).sorted {
            if ($0.pinned == true) != ($1.pinned == true) { return $0.pinned == true }
            return $0.savedAt > $1.savedAt
        }
    }

    private func write(_ entry: ReaderCache.Entry) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(entry) else { return }
        // Atomic, because a truncated file silently loses a pinned entry with no recovery path.
        try? data.write(to: fileURL(for: entry.url), options: .atomic)
    }

    private func decode(_ file: URL) -> ReaderCache.Entry? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(ReaderCache.Entry.self, from: data)
    }

    /// Only files whose mtime already passed the TTL are decoded (to check the pin) — the mtime is never
    /// older than `savedAt`, so the pre-filter can't sweep a live entry, and fresh files cost no decode.
    private func sweepExpired() {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files {
            guard let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate,
                Date.now.timeIntervalSince(modified) > ttl else { continue }
            guard let entry = decode(file), !isLive(entry) else { continue }
            try? fm.removeItem(at: file)
        }
    }

    private func fileURL(for url: URL) -> URL {
        let hash = SHA256.hash(data: Data(url.absoluteString.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash + ".json")
    }
}
