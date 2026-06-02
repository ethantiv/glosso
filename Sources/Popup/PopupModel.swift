import Foundation
import Observation

@MainActor
@Observable
final class PopupModel {
    enum Phase {
        case capturing
        case streaming
        case done
        case error
    }

    var sourceText: String = ""
    var text: String = ""
    var phase: Phase = .capturing
    var direction: TranslationDirection = .unknown
    var errorMessage: String? = nil
    var truncated: Bool = false
    var formality: Formality = .automatic
}
