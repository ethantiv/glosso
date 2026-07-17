import Foundation

/// Decides whether a fresh double-Cmd+C capture is an article URL for the reader
/// window. Only the WHOLE trimmed selection being a single http(s) URL with a host
/// qualifies — a URL merely contained in prose translates normally.
enum URLDetector {
    static func articleURL(in text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace),
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host() != nil
        else { return nil }
        return url
    }
}
