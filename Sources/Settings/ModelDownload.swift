import Foundation

@MainActor
func downloadModel(
    _ model: String,
    engine: any EngineProviding,
    modelManager: any ModelManaging,
    progress: @escaping @MainActor @Sendable (Double) -> Void
) async throws {
    let engineShare = 0.15
    try await engine.ensureEngine(progress: { p in
        Task { @MainActor in progress(p * engineShare) }
    })
    // Summed across layers, keyed by each line's status (it carries the layer digest): a single layer's
    // completed/total is not the pull — a small layer finishing first would show a full bar for the whole blob.
    var layers: [String: (completed: Int64, total: Int64)] = [:]
    for try await step in modelManager.pull(model) {
        guard step.total > 0 else { continue }
        layers[step.status] = (step.completed, step.total)
        let completed = layers.values.reduce(Int64(0)) { $0 + $1.completed }
        let total = layers.values.reduce(Int64(0)) { $0 + $1.total }
        guard total > 0 else { continue }
        progress(engineShare + Double(completed) / Double(total) * (1 - engineShare))
    }
}
