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
    var latest = engineShare
    for try await step in modelManager.pull(model) {
        guard step.total > 0 else { continue }
        let fraction = Double(step.completed) / Double(step.total)
        latest = max(latest, engineShare + fraction * (1 - engineShare))
        progress(latest)
    }
}
