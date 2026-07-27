import Foundation

enum ReplyParser {
    static let maxCount = 5

    static func parse(_ raw: String) -> [String] {
        var blocks: [String] = []
        var current: [Substring] = []
        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            if isSeparator(line) {
                blocks.append(current.joined(separator: "\n"))
                current.removeAll()
            } else {
                current.append(line)
            }
        }
        blocks.append(current.joined(separator: "\n"))

        var seen = Set<String>()
        var result: [String] = []
        for block in blocks {
            let cleaned = block.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty, seen.insert(cleaned.lowercased()).inserted else { continue }
            result.append(cleaned)
            if result.count == maxCount { break }
        }
        return result
    }

    private static func isSeparator(_ line: Substring) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.count >= 3 && trimmed.allSatisfy { $0 == "-" }
    }
}
