import Foundation

/// Parses the model's free-form alternatives reply (one per line) into a clean,
/// de-duplicated list for the popup dropdown (issue #17). Defensive about the
/// model occasionally adding bullets or numbering despite the prompt asking for
/// none, and drops any echo of the original word.
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

    // Drops a leading bullet ("- ", "• ", "* ") or numbering ("1. ", "2) ") the
    // model may prepend, plus any wrapping quotes, leaving the bare alternative.
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
