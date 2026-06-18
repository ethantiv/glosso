import Foundation

/// The Gemma 4 MLX models Glosso offers for on-demand download in Settings. These
/// are Ollama tags pulled via `/api/pull`; sizes are the Ollama library's download
/// sizes (note e4b is larger than 12b — higher precision, not a typo).
enum EmbeddedModelCatalog {
    struct Entry: Sendable, Identifiable, Equatable {
        let id: String
        let size: String
        var name: String { id }
    }

    static let models: [Entry] = [
        Entry(id: "gemma4:12b-mlx", size: "6,8 GB"),
        Entry(id: "gemma4:e4b-mlx", size: "9,6 GB"),
        Entry(id: "gemma4:26b-mlx", size: "17 GB"),
        Entry(id: "gemma4:31b-mlx", size: "20 GB"),
    ]
}
