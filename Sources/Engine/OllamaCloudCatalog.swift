import Foundation

/// Ollama's own cloud, reached through the same /api/generate the local engine serves. No model list here: `/api/tags` on the host answers unauthenticated, and Ollama retires cloud models on a published schedule.
enum OllamaCloudCatalog {
    static let baseURL = URL(string: "https://ollama.com/api/generate")!
    /// The one cloud model from the family the prompts are tuned against — BF16 where the local tier is quantised.
    static let defaultModel = "gemma4:31b"
}
