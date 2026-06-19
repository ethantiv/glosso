import Foundation

/// Shared model-download flow for Settings and the first-run wizard: provision the
/// engine (idempotent), then pull the model, reporting a single 0…1 progress value.
///
/// The engine pull occupies the bar's first slice so the row reflects provisioning
/// instead of sitting frozen at 0%; the model pull fills the rest. On an existing
/// engine `ensureEngine` is a no-op and progress simply starts from the engine slice.
/// `/api/pull` restarts completed/total per layer, so the pull phase is clamped
/// monotonic to stop the bar snapping backward as each new layer reports from 0.
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
