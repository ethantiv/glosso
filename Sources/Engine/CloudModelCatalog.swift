import Foundation

/// The models the Gemini API serves us, each with its own free-tier limits — Google lists no paid tier for Gemma.
enum CloudModelCatalog {
    struct Entry: Sendable, Identifiable, Equatable {
        let id: String
        let displayName: String
        /// SF Symbol for the row, matching EmbeddedModelCatalog's gauges where the speed↔accuracy tier applies.
        let icon: String
        let limits: GeminiRateLimiter.Limits
    }

    private static let gemmaLimits = GeminiRateLimiter.Limits(rpm: 30, tpm: 16_000, rpd: 14_400)

    // Computed so displayName resolves in the app's current UI language.
    static var models: [Entry] { [
        Entry(id: "gemini-3.5-flash-lite", displayName: "Gemini Flash Lite", icon: "bolt",
              limits: GeminiRateLimiter.Limits(rpm: 15, tpm: 250_000, rpd: 500)),
        Entry(id: "gemma-4-26b-a4b-it", displayName: loc("Gemma (szybka)", "Gemma (fast)"),
              icon: "gauge.with.dots.needle.67percent", limits: gemmaLimits),
        Entry(id: "gemma-4-31b-it", displayName: loc("Gemma (dokładna)", "Gemma (accurate)"),
              icon: "gauge.with.dots.needle.100percent", limits: gemmaLimits),
    ] }

    /// By name, not by index: inserting a row must not silently re-point the default.
    static var `default`: Entry { models.first { $0.id == "gemini-3.5-flash-lite" } ?? models[0] }

    static func limits(for id: String) -> GeminiRateLimiter.Limits {
        models.first { $0.id == id }?.limits ?? `default`.limits
    }
}
