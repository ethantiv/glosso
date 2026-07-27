import Foundation

enum AlternativesParser {
    static let maxCount = 6

    static func parse(_ raw: String, original: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        let originalKey = original.lowercased()

        for line in raw.split(whereSeparator: \.isNewline) {
            let cleaned = stripLeadingMarker(line.trimmingCharacters(in: .whitespaces))
            guard !cleaned.isEmpty else { continue }
            let key = cleaned.lowercased()
            guard key != originalKey, !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(cleaned)
            if result.count == maxCount { break }
        }
        return result
    }

    private static func stripLeadingMarker(_ line: String) -> String {
        var s = Substring(line)
        if let range = s.range(of: #"^(\d+[.)]|[-•*])\s+"#, options: .regularExpression) {
            s = s[range.upperBound...]
        }
        var trimmed = s.trimmingCharacters(in: .whitespaces)
        if trimmed.count >= 2, let first = trimmed.first, let last = trimmed.last,
           (first == "\"" && last == "\"") || (first == "'" && last == "'") {
            trimmed = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        }
        return trimmed
    }
}
