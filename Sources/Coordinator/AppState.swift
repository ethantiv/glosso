import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    var accessibilityGranted: Bool = false
    var listening: Bool = false
    var updateAvailable: (version: String, asset: URL)? = nil
    var checkingForUpdates: Bool = false
}
