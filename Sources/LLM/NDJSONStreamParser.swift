import Foundation

enum NDJSONStreamParser {
    static func parse(line: String) -> GenerateChunk? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(GenerateChunk.self, from: data)
    }
}
