import Foundation

/// Cleans the model's free-form "Dlaczego tak?" reply into the single line shown
/// in the per-word dropdown (issue #39). The prompt asks for one bare sentence, so
/// this only trims surrounding whitespace and strips wrapping quotes the model may
/// still add despite being told not to — mirroring `AlternativesParser`'s defense.
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
        return trimmed
    }
}
