import Foundation

enum ExplanationParser {
    static func clean(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count >= 2, let first = trimmed.first, let last = trimmed.last,
           (first == "\"" && last == "\"")
            || (first == "'" && last == "'")
            || (first == "„" && last == "”")
            || (first == "“" && last == "”")
            || (first == "„" && last == "\"") {
            trimmed = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed.replacing(#/\s*\(styl:[^)]*\)/#, with: "")
    }
}
