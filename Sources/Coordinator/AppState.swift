import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    var accessibilityGranted: Bool = false
    var listening: Bool = false
    var updateAvailable: (version: String, asset: URL)? = nil
    var checkingForUpdates: Bool = false
    /// `nil` under a cloud provider: the indicator exists only for the local engine.
    var localModel: LocalModelStatus? = nil
}

/// Whether the local model is resident in memory (instant answer) or unloaded (the next call pays the load).
enum LocalModelStatus: Equatable, Sendable {
    case loaded(expiresAt: Date?)
    case idle

    static func from(loaded: [LoadedModel], model: String) -> LocalModelStatus {
        guard let entry = loaded.first(where: { $0.name == model }) else { return .idle }
        return .loaded(expiresAt: entry.expiresAt)
    }

    func label(now: Date = Date()) -> String {
        switch self {
        case .idle:
            return loc("Model lokalny: uśpiony", "Local model: idle")
        case .loaded(let expiresAt):
            // `keep_alive -1` shows up as a date decades away.
            guard let expiresAt, expiresAt.timeIntervalSince(now) < 365 * 86_400 else {
                return loc("Model lokalny: załadowany · nie zwalnia", "Local model: loaded · never unloads")
            }
            let minutes = max(0, Int((expiresAt.timeIntervalSince(now) / 60).rounded(.up)))
            return loc("Model lokalny: załadowany · zwolni za \(minutes) min",
                       "Local model: loaded · unloads in \(minutes) min")
        }
    }
}
