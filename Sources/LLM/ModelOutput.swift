import Foundation

/// Peels what a model wraps its answer in: a markdown fence and an echoed prompt wrapper, in either nesting order.
/// Lives in the prompt layer so every backend's answer is cleaned once, in `PromptRunning` — not per call site,
/// where a forgotten unwrap reintroduces the literal `<block>` wrapper Flash Lite is known to echo.
enum ModelOutput {
    static func unwrap(_ text: String) -> String {
        var current = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for _ in 0..<3 {
            let before = current
            current = peelWrapper(peelFence(current))
            if current == before { break }
        }
        return current
    }

    private static func peelFence(_ text: String) -> String {
        guard text.hasPrefix("```") else { return text }
        var peeled = text.replacingOccurrences(
            of: #"\A```[a-zA-Z]*\s*"#, with: "", options: .regularExpression)
        peeled = peeled.replacingOccurrences(
            of: #"\s*```\z"#, with: "", options: .regularExpression)
        return peeled.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Both ends anchored and the same tag required on both, so a legitimate inline tag can never be mistaken for a wrapper.
    private static func peelWrapper(_ text: String) -> String {
        let peeled = text.replacingOccurrences(
            of: #"(?is)\A<\s*(block|text|article)\s*>\s*(.*?)\s*<\s*/\s*\1\s*>\z"#,
            with: "$2", options: .regularExpression)
        return peeled == text ? text : peeled.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
