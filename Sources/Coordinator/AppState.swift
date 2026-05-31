import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    var accessibilityGranted: Bool = false
    var listening: Bool = false
}
