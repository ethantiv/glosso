import Foundation

enum NDJSONStreamParser {
    private static let decoder = JSONDecoder()

    static func parse(line: String) -> GenerateChunk? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
        return try? decoder.decode(GenerateChunk.self, from: data)
    }
}
