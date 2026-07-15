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

    // Reply drafts (issue #60). Populated by the controller's showReplies when the
    // .reply action finishes; the view renders them as a pick-one list. Picking one
    // mirrors it into `text` so the Copy button (which copies `text`) works unchanged.
    // Both are cleared on each pane reset so a stale list can't outlive a verb switch.
    var replyDrafts: [String] = []
    var selectedDraftIndex: Int? = nil

    func selectDraft(_ index: Int) {
        guard replyDrafts.indices.contains(index) else { return }
        selectedDraftIndex = index
        text = replyDrafts[index]
    }

    // Per-word alternatives dropdown (issue #17). An empty `alternatives` once
    // `altsLoading` clears means "none / fetch failed" — the coordinator collapses
    // both into an empty list, so there is no separate error state to track here.
    var selectedWordID: Int? = nil
    var alternatives: [String] = []
    var altsLoading: Bool = false

    // Per-result caches so re-opening a dropdown the model already answered shows
    // the answer instantly instead of re-fetching (the spinner-on-revisit bug).
    // Keyed by segment.id (alternatives/#39 explanation) or change.id (#51 reason),
    // which are positional in the current text — so resetTranslationPane() clears
    // all three whenever the text changes and the ids would no longer line up.
    // Only non-empty results are cached; an empty fetch is a "none/failed" and must
    // stay retryable.
    var altsCache: [Int: [String]] = [:]
    var explanationCache: [Int: String] = [:]
    var fixReasonCache: [Int: String] = [:]
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
    // Measured height of the rendered reason text (#73). PopupView reserves exactly
    // this below the panel so the window grows to fit the reason instead of clipping
    // it; the dropdown caps and scrolls it past FixReasonLayout.maxReason.
    var fixReasonContentHeight: CGFloat = 0

    // Register coach (issue #53): what the last tone-pill cycle did. `toneChange`
    // holds the translation as it read under the previous register (snapshotted by
    // the pill before the re-translation wipes the pane) plus both registers; its
    // presence is what shows the "Co się zmieniło?" chip. The note itself is fetched
    // only on demand and cached here, so re-opening the row costs no second model run.
    // Deliberately separate from the explanation* fields, which belong to the word
    // dropdown and can be open at the same time.
    var toneChange: (from: Formality, to: Formality, previous: String)? = nil
    var toneNoteText: String = ""
    var toneNoteLoading: Bool = false
    var toneNoteVisible: Bool = false
    // Mirrors explanationRequestToken: a note fetch outliving its tone change (a
    // fresh capture, another cycle) must not land in the row.
    var toneNoteRequestToken: Int = 0

    /// Snapshots the current translation as the "before" side of a tone change. Only
    /// a finished translation can be contrasted — mid-stream, in another verb, or
    /// with no result there is nothing to compare against, so the chip stays hidden.
    func noteToneChange(from: Formality, to: Formality) {
        clearToneNote()
        guard phase == .done, action == .translate, !text.isEmpty else { return }
        toneChange = (from, to, text)
    }

    /// Drops the tone note whenever the result it contrasts stops being the tone
    /// change's own: a fresh capture, a verb switch, a source edit, a reword or its
    /// undo. Not called from the pane reset — the pill snapshots right before the
    /// re-translation resets the pane, and that would erase it immediately.
    func clearToneNote() {
        toneChange = nil
        toneNoteText = ""
        toneNoteLoading = false
        toneNoteVisible = false
    }

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

    // Memoizes the grammar diff keyed on its two inputs so re-renders that don't
    // change them (hover, dropdown open/close) reuse it instead of re-running the
    // full CollectionDifference — mirrors segmentsCache for the fixGrammar pane.
    @ObservationIgnored private var diffPartsCache: (original: String, corrected: String, value: [DiffPart])?

    /// Word-level diff between the captured original and the `fixGrammar` correction
    /// (issue #51). Derived from `capturedSource`/`text`, the single sources of truth.
    var diffParts: [DiffPart] {
        if let cache = diffPartsCache, cache.original == capturedSource, cache.corrected == text {
            return cache.value
        }
        let value = GrammarDiff.parts(original: capturedSource, corrected: text)
        diffPartsCache = (capturedSource, text, value)
        return value
    }

    /// Tappable change spans in the current grammar diff — the same unit as the
    /// "dlaczego poprawiono?" tap targets.
    var diffChangeCount: Int {
        diffParts.count { if case .change = $0 { return true } else { return false } }
    }

    /// A dense fixGrammar diff splits the result pane into a diff section and a
    /// clean corrected-text section: reading the correction through many
    /// strikethroughs gets hard. With a few changes the diff nearly IS the clean
    /// text, so the split (and the eye) would be pure noise — hence the threshold.
    var splitFixView: Bool { diffChangeCount > 3 }

    /// The split view's eye: hides the diff section, leaving only the clean
    /// corrected text. Deliberately transient (reset by resetTranslationPane on
    /// every fresh capture and re-run, never persisted) so the tappable learning
    /// layer can't stay silently disabled forever.
    var diffHidden: Bool = false

    /// Hiding the diff removes every dropdown anchor with it, so an open reason
    /// dropdown must close along.
    func toggleDiffHidden() {
        if !diffHidden { closeDropdown() }
        diffHidden.toggle()
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
        fixReasonContentHeight = 0
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
        fixReasonContentHeight = 0
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
        // The reword replaces the result the tone note contrasts, so the note (and
        // its chip) no longer describes what's on screen (issue #53).
        clearToneNote()
    }

    // Restores the pre-reword result; clears the snapshot (single level).
    func undo() {
        guard let snapshot = undoSnapshot else { return }
        closeDropdown()
        // The restored text re-tokenizes, so the segment/change ids the dropdown
        // caches are keyed on no longer line up — drop them (mirrors
        // resetTranslationPane), or a revisit replays another word's answer.
        altsCache.removeAll()
        explanationCache.removeAll()
        fixReasonCache.removeAll()
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
