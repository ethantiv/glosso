import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    var accessibilityGranted: Bool = false
    var listening: Bool = false
    /// Set when a GitHub release newer than the running build is found; the menu
    /// surfaces it as a "download" link. Nil until the check resolves (and stays
    /// nil on failure — the check fails silently).
    var updateAvailable: (version: String, page: URL)? = nil
}
