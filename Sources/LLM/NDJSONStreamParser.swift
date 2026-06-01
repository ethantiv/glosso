import Foundation

enum NDJSONStreamParser {
    static func parse(line: String) -> GenerateChunk? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
        // A fresh decoder per line: JSONDecoder isn't documented thread-safe and
        // overlapping translate() Tasks could otherwise race on a shared instance.
        return try? JSONDecoder().decode(GenerateChunk.self, from: data)
    }
}
