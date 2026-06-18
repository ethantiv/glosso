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

    static let models: [Entry] = [
        Entry(id: "gemma4:12b-mlx", displayName: "Szybki", size: "6,8 GB", icon: "gauge.with.dots.needle.33percent"),
        Entry(id: "gemma4:26b-mlx", displayName: "Zrównoważony", size: "17 GB", icon: "gauge.with.dots.needle.67percent"),
        Entry(id: "gemma4:31b-mlx", displayName: "Najdokładniejszy", size: "20 GB", icon: "gauge.with.dots.needle.100percent"),
    ]

    /// The largest model that comfortably fits in this Mac's unified memory. The
    /// model shares RAM with the GPU and stays resident via `keep_alive`, so a model
    /// near the RAM ceiling would starve the user's other apps. Thresholds are a
    /// tuning knob — bump them if real-world fit differs from the on-disk size.
    static func recommended(forRAMBytes ramBytes: UInt64) -> Entry {
        let gigabytes = Double(ramBytes) / 1_073_741_824
        if gigabytes >= 32 { return models[2] }
        if gigabytes >= 24 { return models[1] }
        return models[0]
    }

    static var recommended: Entry {
        recommended(forRAMBytes: ProcessInfo.processInfo.physicalMemory)
    }
}
