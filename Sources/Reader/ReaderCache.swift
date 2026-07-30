import CryptoKit
import Foundation

struct ReaderCache: Sendable {
    struct Entry: Codable {
        var url: URL
        var savedAt: Date
        /// Original title — feeds glossoSetArticle so the original-view toggle works.
        var title: String
        /// Feeds glossoSetTitle and the window title.
        var translatedTitle: String
        var byline: String
        var content: String
        var summary: String
        var translations: [Int: String]
        /// The footer label of the engine that actually translated this, so a replay two days later doesn't credit
        /// whatever provider is selected by then. nil on entries written before the label existed.
        var engine: String? = nil
    }

    static let ttl: TimeInterval = 7 * 24 * 3600

    let directory: URL
    private let version: String

    init(directory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Glosso/reader", isDirectory: true),
         version: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") {
        self.directory = directory
        self.version = version
    }

    /// nil on miss or decode failure; an expired entry is deleted and reported as a miss.
    func load(_ url: URL, primary: PrimaryLanguage) -> Entry? {
        let file = fileURL(for: url, primary: primary)
        guard let data = try? Data(contentsOf: file),
              let entry = try? JSONDecoder().decode(Entry.self, from: data)
        else { return nil }
        guard Date.now.timeIntervalSince(entry.savedAt) <= Self.ttl else {
            try? FileManager.default.removeItem(at: file)
            return nil
        }
        return entry
    }

    func remove(_ url: URL, primary: PrimaryLanguage) {
        try? FileManager.default.removeItem(at: fileURL(for: url, primary: primary))
    }

    func save(_ entry: Entry, primary: PrimaryLanguage) {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(entry) else { return }
        try? data.write(to: fileURL(for: entry.url, primary: primary))
        sweepExpired()
    }

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

    private func fileURL(for url: URL, primary: PrimaryLanguage) -> URL {
        let hash = SHA256.hash(data: Data("\(version)|\(primary.rawValue)|\(url.absoluteString)".utf8))
            .map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash + ".json")
    }
}
