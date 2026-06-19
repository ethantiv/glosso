import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    var accessibilityGranted: Bool = false
    var listening: Bool = false
    /// Set when a GitHub release newer than the running build is found; carries the
    /// `.zip` asset URL that the menu, the notification tap and the badge all act on.
    /// Nil until the check resolves (and stays nil on failure — the check fails
    /// silently).
    var updateAvailable: (version: String, asset: URL)? = nil
}
