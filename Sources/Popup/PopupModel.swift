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
    // The source as it was last sent to the model. sourceText is editable (issue #44);
    // the re-translate button lights up while sourceText differs from this baseline and
    // resets it on each run via update(), so it dims again once the edit is translated.
    var capturedSource: String = ""
    var text: String = ""
    var phase: Phase = .capturing
    var direction: TranslationDirection = .unknown
    var errorMessage: String? = nil
    var truncated: Bool = false
    var formality: Formality = .automatic
    // The selected palette verb (issue #23). Drives which header controls show and
    // whether the result is clickable-per-word. Reset to .translate on each capture.
    var action: Action = .translate
    // Extra size added by dragging the resize grip. It widens the panes and
    // raises their height cap in PopupView; the hosting view then reports the
    // grown ideal size and TranslationPopupController.applyContentSize() moves
    // the window frame — the same single path that grows the window during
    // streaming. Reset on each fresh present().
    var sizeDelta: CGSize = .zero

    // Per-word alternatives dropdown (issue #17). An empty `alternatives` once
    // `altsLoading` clears means "none / fetch failed" — the coordinator collapses
    // both into an empty list, so there is no separate error state to track here.
    var selectedWordID: Int? = nil
    var alternatives: [String] = []
    var altsLoading: Bool = false
    var dropdownVisible: Bool { selectedWordID != nil }
    // Bumped on each open so a slow fetch for a previously clicked word can't
    // overwrite the dropdown the user has since reopened on another word.
    var altsRequestToken: Int = 0

    // "Dlaczego tak?" sub-state of the dropdown (issue #39). When showingExplanation
    // is true the dropdown swaps its alternatives list for the explanation of the
    // selected word; the back row returns to the list. An empty explanationText once
    // explanationLoading clears means "fetch failed" — the dropdown shows a fallback.
    var showingExplanation: Bool = false
    var explanationText: String = ""
    var explanationLoading: Bool = false
    // Mirrors altsRequestToken: bumped on each open so a slow explanation fetch can't
    // land in a dropdown the user has since reopened on another word or closed.
    var explanationRequestToken: Int = 0

    // Grammar-diff "why was this corrected?" dropdown (issue #51). Unlike #39 there
    // is no alternatives list to peel back to: the dropdown shows only the reason,
    // so fixReasonMode makes the dropdown skip the list (and Esc close it in one
    // step). Reuses the explanation* fetch fields above. selectedFixChange holds the
    // tapped change's struck error and correction, threaded to the model for the reason.
    var fixReasonMode: Bool = false
    var selectedFixChange: (before: String, after: String)? = nil

    // Memoizes the tokenization keyed on `text` so re-renders that don't change the
    // translation (hover, dropdown open/close) reuse it instead of re-tokenizing.
    @ObservationIgnored private var segmentsCache: (text: String, value: [TextSegment])?

    /// Segments of the finished translation. Derived from `text` so it stays the
    /// single source of truth.
    var segments: [TextSegment] {
        if let cache = segmentsCache, cache.text == text { return cache.value }
        let value = Tokenizer.segments(text)
        segmentsCache = (text, value)
        return value
    }

    func openDropdown(for id: Int) {
        selectedWordID = id
        alternatives = []
        altsLoading = true
        altsRequestToken &+= 1
        // A fresh dropdown always starts on the alternatives list, never inheriting
        // a prior word's "Dlaczego tak?" view (issue #39).
        closeExplanation()
    }

    func closeDropdown() {
        selectedWordID = nil
        altsLoading = false
        alternatives = []
        fixReasonMode = false
        selectedFixChange = nil
        closeExplanation()
    }

    // Opens the dropdown straight into the grammar-diff reason view for the tapped
    // change (issue #51) — no alternatives list, so it skips #39's two-step path.
    // Reuses the explanation* fetch fields (token, loading, text).
    func openFixReason(id: Int, before: String, after: String) {
        selectedWordID = id
        fixReasonMode = true
        selectedFixChange = (before, after)
        showingExplanation = true
        explanationText = ""
        explanationLoading = true
        explanationRequestToken &+= 1
    }

    // Switches the open dropdown into its "Dlaczego tak?" view and arms a fresh fetch
    // (issue #39). Keeps selectedWordID, so the dropdown stays anchored to the word.
    func openExplanation() {
        showingExplanation = true
        explanationText = ""
        explanationLoading = true
        explanationRequestToken &+= 1
    }

    // Returns the dropdown to its alternatives list (the back row) or clears the
    // sub-state when the whole dropdown closes.
    func closeExplanation() {
        showingExplanation = false
        explanationText = ""
        explanationLoading = false
    }

    // Single-level undo of the last word-alternative reword (issue #25). Holds the
    // result as it was right before the reword replaced it; nil = nothing to undo.
    private var undoSnapshot: (text: String, truncated: Bool)?
    var canUndo: Bool { undoSnapshot != nil }

    // Captured by PopupView right before a picked alternative triggers a reword.
    func snapshotForUndo() {
        undoSnapshot = (text, truncated)
    }

    // Restores the pre-reword result; clears the snapshot (single level).
    func undo() {
        guard let snapshot = undoSnapshot else { return }
        closeDropdown()
        text = snapshot.text
        truncated = snapshot.truncated
        errorMessage = nil
        phase = .done
        undoSnapshot = nil
    }

    // Dropped on a fresh translation or a tone change — the prior result no longer
    // applies, so undo must not resurrect it.
    func clearUndo() {
        undoSnapshot = nil
    }
}
