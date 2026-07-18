import Foundation

/// The Gemma 4 MLX models Glosso offers for on-demand download in Settings. These
/// are Ollama tags pulled via `/api/pull`; sizes are the Ollama library's download
/// sizes. Ordered smallest→largest, which here also means fastest→most accurate.
enum EmbeddedModelCatalog {
    struct Entry: Sendable, Identifiable, Equatable {
        let id: String
        let displayName: String
        let size: String
        /// SF Symbol for the speed↔accuracy tier, rendered in place of the name.
        let icon: String
    }

    // Computed so displayName resolves in the app's current UI language.
    static var models: [Entry] { [
        Entry(id: "gemma4:12b-mlx", displayName: loc("Szybki", "Fast"), size: loc("6,8 GB", "6.8 GB"), icon: "gauge.with.dots.needle.33percent"),
        Entry(id: "gemma4:26b-mlx", displayName: loc("Zrównoważony", "Balanced"), size: "17 GB", icon: "gauge.with.dots.needle.67percent"),
        Entry(id: "gemma4:31b-mlx", displayName: loc("Najdokładniejszy", "Most accurate"), size: "20 GB", icon: "gauge.with.dots.needle.100percent"),
    ] }

    /// The largest model that comfortably fits in this Mac's unified memory. The
    /// model shares RAM with the GPU and stays resident via `keep_alive`, so a model
    /// near the RAM ceiling would starve the user's other apps. Calibrated against a
    /// real 36 GB Mac where 26B (17 GB) is the sweet spot and 31B (20 GB) is already
    /// too heavy — i.e. roughly RAM ≥ 2× the model's on-disk size. Thresholds are a
    /// tuning knob — bump them if real-world fit differs.
    static func recommended(forRAMBytes ramBytes: UInt64) -> Entry {
        let gigabytes = Double(ramBytes) / 1_073_741_824
        if gigabytes >= 48 { return models[2] }
        if gigabytes >= 36 { return models[1] }
        return models[0]
    }

    static var recommended: Entry {
        recommended(forRAMBytes: ProcessInfo.processInfo.physicalMemory)
    }
}
