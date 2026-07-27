import Foundation

struct GeminiRequest: Encodable, Sendable {
    struct Part: Encodable, Sendable { var text: String }
    struct Content: Encodable, Sendable { var parts: [Part] }
    struct ThinkingConfig: Encodable, Sendable { var thinkingLevel: String }

    struct GenerationConfig: Encodable, Sendable {
        var temperature: Double
        var maxOutputTokens: Int?
        // The cloud counterpart of Ollama's `think:false` and just as load-bearing: the default costs 10–26s per lookup.
        var thinkingConfig = ThinkingConfig(thinkingLevel: "minimal")
    }

    var contents: [Content]
    var generationConfig: GenerationConfig

    init(prompt: String, temperature: Double, maxOutputTokens: Int?) {
        self.contents = [Content(parts: [Part(text: prompt)])]
        self.generationConfig = GenerationConfig(temperature: temperature, maxOutputTokens: maxOutputTokens)
    }
}

struct GeminiResponse: Decodable, Sendable {
    struct Part: Decodable, Sendable { var text: String? }
    struct Content: Decodable, Sendable { var parts: [Part]? }
    struct Candidate: Decodable, Sendable {
        var content: Content?
        var finishReason: String?
    }
    struct UsageMetadata: Decodable, Sendable { var promptTokenCount: Int? }

    var candidates: [Candidate]?
    var usageMetadata: UsageMetadata?

    /// All text parts of the first candidate, concatenated.
    var text: String {
        (candidates?.first?.content?.parts ?? []).compactMap(\.text).joined()
    }

    var finishReason: String? { candidates?.first?.finishReason }
}

struct GeminiErrorEnvelope: Decodable, Sendable {
    struct Detail: Decodable, Sendable {
        var reason: String?
        var retryDelay: String?
    }
    struct Failure: Decodable, Sendable {
        var code: Int?
        var message: String?
        var status: String?
        var details: [Detail]?
    }

    var error: Failure

    var message: String { error.message ?? error.status ?? "unknown error" }

    /// Google reports a bad key as 400 INVALID_ARGUMENT with this reason, not 403.
    var isInvalidKey: Bool {
        error.details?.contains { $0.reason == "API_KEY_INVALID" } == true
    }

    /// `retryDelay` from the RetryInfo detail, e.g. "5s" or "1.5s".
    var retryDelay: TimeInterval? {
        guard let raw = error.details?.compactMap(\.retryDelay).first else { return nil }
        return Double(raw.hasSuffix("s") ? String(raw.dropLast()) : raw)
    }
}

enum GeminiSSEParser {
    /// One `alt=sse` line → a response chunk; blank lines, comments and non-data fields yield nil.
    static func parse(line: String) -> GeminiResponse? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty, let data = payload.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(GeminiResponse.self, from: data)
    }
}
