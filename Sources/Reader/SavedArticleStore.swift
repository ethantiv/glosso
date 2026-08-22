import CryptoKit
import Foundation

/// Durable article history: every completed translation lands here for 7 days; a pinned entry stays until unpinned.
/// Unlike `ReaderCache`, the key carries no app version or language and the files live in Application Support —
/// a saved article must survive updates and never be purged by the OS.
struct SavedArticleStore: Sendable {
    static let ttl: TimeInterval = 7 * 24 * 3600

    let directory: URL

    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Glosso/saved-articles", isDirectory: true)) {
        self.directory = directory
    }

    /// nil on miss or decode failure; an expired unpinned entry is deleted and reported as a miss.
    func load(_ url: URL) -> ReaderCache.Entry? {
        let file = fileURL(for: url)
        guard let entry = decode(file) else { return nil }
        guard entry.pinned == true || Date.now.timeIntervalSince(entry.savedAt) <= Self.ttl else {
            try? FileManager.default.removeItem(at: file)
            return nil
        }
        return entry
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

    /// Flips the flag without touching `savedAt` — pinning is not a re-translation.
    func setPinned(_ on: Bool, for url: URL) {
        guard var entry = decode(fileURL(for: url)) else { return }
        entry.pinned = on
        write(entry)
    }

    /// Pinned first, then newest first.
    func list() -> [ReaderCache.Entry] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.compactMap(decode).sorted {
            if ($0.pinned == true) != ($1.pinned == true) { return $0.pinned == true }
            return $0.savedAt > $1.savedAt
        }
    }

    private func write(_ entry: ReaderCache.Entry) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(entry) else { return }
        try? data.write(to: fileURL(for: entry.url))
    }

    private func decode(_ file: URL) -> ReaderCache.Entry? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(ReaderCache.Entry.self, from: data)
    }

    /// Decodes rather than reading mtimes — only unpinned entries expire.
    private func sweepExpired() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files {
            guard let entry = decode(file), entry.pinned != true,
                  Date.now.timeIntervalSince(entry.savedAt) > Self.ttl else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func fileURL(for url: URL) -> URL {
        let hash = SHA256.hash(data: Data(url.absoluteString.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash + ".json")
    }
}
