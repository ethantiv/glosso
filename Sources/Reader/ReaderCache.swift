import CryptoKit
import Foundation

/// Disk cache of fully translated reader articles: one JSON file per URL under
/// ~/Library/Caches/Glosso/reader, keyed by SHA256 of the URL, replayed into the
/// template on a hit so a re-opened article costs zero fetch/extraction/LLM.
/// Entries expire after 7 days; a partial (cancelled/failed) run is never saved.
struct ReaderCache: Sendable {
    struct Entry: Codable {
        var url: URL
        var savedAt: Date
        /// Original title — feeds glossoSetArticle so the original-view toggle works.
        var title: String
        /// Feeds glossoSetTitle and the window title.
        var translatedTitle: String
        var byline: String
        /// Original extracted HTML — glossoSetArticle's walk is deterministic, so
        /// re-inserting it re-derives the same block ids the translations map uses.
        var content: String
        var summary: String
        /// Block id → applied HTML (including Polish-skip blocks, so a replay
        /// un-dims every block).
        var translations: [Int: String]
    }

    static let ttl: TimeInterval = 7 * 24 * 3600

    let directory: URL
    private let version: String

    // The app version is folded into the file key: block ids are deterministic
    // only within one build (the template's walk/SKIP/thresholds can change), so
    // an entry from another version must miss instead of mis-applying its
    // translations. Orphaned old-version files age out via the TTL sweep.
    init(directory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Glosso/reader", isDirectory: true),
         version: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") {
        self.directory = directory
        self.version = version
    }

    /// nil on miss or decode failure; an expired entry is deleted and reported as a miss.
    func load(_ url: URL) -> Entry? {
        let file = fileURL(for: url)
        guard let data = try? Data(contentsOf: file),
              let entry = try? JSONDecoder().decode(Entry.self, from: data)
        else { return nil }
        guard Date.now.timeIntervalSince(entry.savedAt) <= Self.ttl else {
            try? FileManager.default.removeItem(at: file)
            return nil
        }
        return entry
    }

    /// Deletes the entry for a URL (no-op on miss) — backs the reader's
    /// re-translate button.
    func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: fileURL(for: url))
    }

    /// Best-effort (all throws swallowed): creates the directory, writes the entry,
    /// then sweeps expired sibling files so never-revisited URLs don't pile up.
    func save(_ entry: Entry) {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(entry) else { return }
        try? data.write(to: fileURL(for: entry.url))
        sweepExpired()
    }

    // The file is written at savedAt, so its modification date approximates the
    // entry's age — one stat per file instead of a full decode.
    private func sweepExpired() {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files {
            guard let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate else { continue }
            if Date.now.timeIntervalSince(modified) > Self.ttl {
                try? fm.removeItem(at: file)
            }
        }
    }

    private func fileURL(for url: URL) -> URL {
        let hash = SHA256.hash(data: Data("\(version)|\(url.absoluteString)".utf8))
            .map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash + ".json")
    }
}
