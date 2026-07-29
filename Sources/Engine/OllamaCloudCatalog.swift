import Foundation

/// Ollama's own cloud, reached through the same /api/generate the local engine serves. No model list here: `/api/tags` on the host answers unauthenticated, and Ollama retires cloud models on a published schedule.
enum OllamaCloudCatalog {
    static let baseURL = URL(string: "https://ollama.com/api/generate")!
    /// The one cloud model from the family the prompts are tuned against — BF16 where the local tier is quantised.
    static let defaultModel = "gemma4:31b"
    /// One number for every model here, measured on Gemma: this host serves 19 models and sweeping each is not on.
    /// Held at 5 because the sweep refuted the reason to raise it — Ollama Cloud bills GPU *time*, and measured wall
    /// clock is flat at ~2s per block from a batch of 5 to a batch of 40, so a bigger batch buys ~nothing in the
    /// currency that is actually metered. Prompt tokens per block do fall ~42% across that range, but they are
    /// evidently a small share of the bill, or the wall clock would have moved with them.
    static let batch = 5
}
