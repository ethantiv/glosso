import Foundation

/// The models the Gemini API serves us, each with its own free-tier limits — Google lists no paid tier for Gemma.
enum CloudModelCatalog {
    struct Entry: Sendable, Identifiable, Equatable {
        let id: String
        let displayName: String
        /// SF Symbol for the row, matching EmbeddedModelCatalog's gauges where the speed↔accuracy tier applies.
        let icon: String
        let limits: GeminiRateLimiter.Limits
        /// Article blocks per reader request. Per model, not per provider: the two here are bound by opposite things — see `batch(for:)`.
        let batch: Int
        /// Reader humanizer level. Gemma's 16k TPM can't carry the ~600-token full directive on 30 requests a minute; Flash Lite's 250k can.
        let readerHumanizer: PromptBuilder.Humanizer
    }

    // Gemma, not Flash Lite: measured on the free tier, flash-lite needs ~30s for a 43-token prompt and delivers its whole stream in one shot, while Gemma answers in ~1s and streams as it goes.
    private static let defaultID = "gemma-4-31b-it"
    private static let gemmaLimits = GeminiRateLimiter.Limits(rpm: 30, tpm: 16_000, rpd: 14_400)
    /// Measured on `gemma-4-31b-it`; the 26B row inherits it untested, since it shares the limits but not the size.
    private static let gemmaBatch = 10

    // Computed so displayName resolves in the app's current UI language.
    static var models: [Entry] { [
        Entry(id: "gemini-3.5-flash-lite", displayName: "Gemini Flash Lite", icon: "bolt",
              limits: GeminiRateLimiter.Limits(rpm: 15, tpm: 250_000, rpd: 500), batch: 20, readerHumanizer: .full),
        Entry(id: "gemma-4-26b-a4b-it", displayName: loc("Gemma (szybka)", "Gemma (fast)"),
              icon: "gauge.with.dots.needle.67percent", limits: gemmaLimits, batch: gemmaBatch, readerHumanizer: .light),
        Entry(id: defaultID, displayName: loc("Gemma (dokładna)", "Gemma (accurate)"),
              icon: "gauge.with.dots.needle.100percent", limits: gemmaLimits, batch: gemmaBatch, readerHumanizer: .light),
    ] }

    /// By id, not by index: inserting a row must not silently re-point the default.
    static var `default`: Entry { models.first { $0.id == defaultID } ?? models[0] }

    static func limits(for id: String) -> GeminiRateLimiter.Limits {
        models.first { $0.id == id }?.limits ?? `default`.limits
    }

    /// Measured live against both models on the real reader corpus, then cut for margin. Neither broke the `<seg id>`
    /// round trip anywhere it was swept — Gemma stayed clean to 40, Flash Lite to 80 — so these are latency and
    /// blast-radius choices, not correctness cliffs. Flash Lite gets 20 because its cost is nearly fixed per call
    /// (11.9s at 5 blocks, 24.3s at 80) and its scarce resource is the 500-request day, which a long article can eat
    /// 16% of at 5 blocks. Gemma gets 10 because its cost is nearly linear instead (16.6s at 5, 68.3s at 20), so a
    /// bigger batch is mostly a longer stall before the first block paints.
    /// Falls back to `.full`, not the default entry: an unknown id is a local or Ollama Cloud model, and both take the full directive.
    static func readerHumanizer(for id: String) -> PromptBuilder.Humanizer {
        models.first { $0.id == id }?.readerHumanizer ?? .full
    }

    static func batch(for id: String) -> Int {
        models.first { $0.id == id }?.batch ?? `default`.batch
    }
}
