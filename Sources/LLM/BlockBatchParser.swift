import Foundation

/// Reads the `<seg id="N">` list back out of a batch translation.
enum BlockBatchParser {
    private static let pattern = #"(?is)<\s*seg\s+id\s*=\s*["']?(\d+)["']?\s*>(.*?)<\s*/\s*seg\s*>"#

    // ponytail: the round trip only checks the id order — a same-order content swap between two
    // segments still passes. Add a per-segment length-ratio check if that ever shows up.
    /// Scans rather than anchors, so prose, code fences or an echoed wrapper around the segments cost nothing.
    /// Returns nil unless every id comes back exactly once, in the order sent, with a non-empty body.
    static func parse(_ text: String, ids: [Int]) -> [Int: String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let full = NSRange(text.startIndex..., in: text)
        var found: [Int] = []
        var blocks: [Int: String] = [:]
        for match in regex.matches(in: text, range: full) {
            guard let idRange = Range(match.range(at: 1), in: text),
                  let bodyRange = Range(match.range(at: 2), in: text),
                  let id = Int(text[idRange]) else { return nil }
            let body = text[bodyRange].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { return nil }
            found.append(id)
            blocks[id] = body
        }
        // Order, not just membership: a reordered answer is the visible symptom of the model losing track of which text belongs to which id.
        guard found == ids else { return nil }
        return blocks
    }
}
