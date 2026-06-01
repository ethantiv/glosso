import Foundation
import Observation

@MainActor
@Observable
final class PopupModel {
    enum Phase {
        case streaming
        case done
        case error
    }

    var sourceText: String = ""
    var text: String = ""
    var phase: Phase = .streaming
    var errorMessage: String? = nil
    var truncated: Bool = false
}
