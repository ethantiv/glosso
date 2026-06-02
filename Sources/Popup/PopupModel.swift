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

    // Per-word alternatives dropdown (issue #17). An empty `alternatives` once
    // `altsLoading` clears means "none / fetch failed" — the coordinator collapses
    // both into an empty list, so there is no separate error state to track here.
    var selectedWordID: Int? = nil
    var alternatives: [String] = []
    var altsLoading: Bool = false
    var dropdownVisible: Bool = false
    // Bumped on each open so a slow fetch for a previously clicked word can't
    // overwrite the dropdown the user has since reopened on another word.
    var altsRequestToken: Int = 0

    /// Segments of the finished translation. Derived from `text` so it stays the
    /// single source of truth; recomputed cheaply for popup-sized text.
    var segments: [TextSegment] { Tokenizer.segments(text) }

    func openDropdown(for id: Int) {
        selectedWordID = id
        alternatives = []
        altsLoading = true
        dropdownVisible = true
        altsRequestToken &+= 1
    }

    func closeDropdown() {
        dropdownVisible = false
        selectedWordID = nil
        altsLoading = false
        alternatives = []
    }
}
