import Foundation
import Observation

@MainActor
@Observable
final class PopupModel {
    enum Phase {
        case idle
        case capturing
        case streaming
        case done
        case error
    }

    var isManual = false
    var canSubmit: Bool {
        !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (isManual ? phase != .capturing && phase != .streaming : sourceText != capturedSource)
    }

    var sourceText: String = ""
    var capturedSource: String = ""
    var text: String = ""
    var phase: Phase = .capturing
    var direction: TranslationDirection = .unknown
    var errorMessage: String? = nil
    var truncated: Bool = false
    var formality: Formality = .automatic
    var action: Action = .translate
    var sizeDelta: CGSize = .zero
    var speech: SpeechPlaybackState = .idle

    var selectedWordID: Int? = nil
    /// The clicked word's (or correction's) text — diff ids don't index `segments`, so the text travels with the selection.
    var selectedWord: String = ""
    /// The clicked correction, nil for a plain word.
    var selectedFixChange: (before: String, after: String)? = nil
    var alternatives: [String] = []
    var altsLoading: Bool = false

    var altsCache: [Int: [String]] = [:]
    var explanationCache: [Int: String] = [:]
    var fixReasonCache: [Int: String] = [:]
    var dropdownVisible: Bool { selectedWordID != nil }
    var altsRequestToken: Int = 0

    var showingExplanation: Bool = false
    var explanationText: String = ""
    var explanationLoading: Bool = false
    var explanationRequestToken: Int = 0

    var fixReasonMode: Bool = false
    /// The reason sits behind the synonym list's header row only when the correction added a word to look up.
    var fixReasonHasBack: Bool { selectedFixChange.map { Self.hasWord($0.after) } ?? false }
    /// Esc closes a reason opened straight from a correction; one opened from the synonym list steps back to it instead.
    var escClosesFixReason: Bool { fixReasonMode && !fixReasonHasBack }

    static func hasWord(_ text: String) -> Bool {
        text.contains { $0.isLetter || $0.isNumber }
    }
    var fixReasonContentHeight: CGFloat = 0

    var toneChange: (from: Formality, to: Formality, previous: String)? = nil
    var toneNoteText: String = ""
    var toneNoteLoading: Bool = false
    var toneNoteVisible: Bool = false
    var toneNoteRequestToken: Int = 0

    func noteToneChange(from: Formality, to: Formality) {
        clearToneNote()
        guard phase == .done, action == .translate, !text.isEmpty else { return }
        toneChange = (from, to, text)
    }

    func clearToneNote() {
        toneChange = nil
        toneNoteText = ""
        toneNoteLoading = false
        toneNoteVisible = false
    }

    @ObservationIgnored private var segmentsCache: (text: String, value: [TextSegment])?

    var segments: [TextSegment] {
        if let cache = segmentsCache, cache.text == text { return cache.value }
        let value = Tokenizer.segments(text)
        segmentsCache = (text, value)
        return value
    }

    @ObservationIgnored private var diffPartsCache: (original: String, corrected: String, value: [DiffPart])?

    var diffParts: [DiffPart] {
        if let cache = diffPartsCache, cache.original == capturedSource, cache.corrected == text {
            return cache.value
        }
        let value = GrammarDiff.parts(original: capturedSource, corrected: text)
        diffPartsCache = (capturedSource, text, value)
        return value
    }

    @ObservationIgnored private var sameRunsCache: (original: String, corrected: String, value: [Int: [FlowRun]])?

    /// Pre-composed flow runs for the diff's unchanged spans, cached with the same key as `diffParts`:
    /// composing them in the view body re-tokenized the whole text on every hover-driven re-eval.
    var diffSameRuns: [Int: [FlowRun]] {
        if let cache = sameRunsCache, cache.original == capturedSource, cache.corrected == text {
            return cache.value
        }
        var runs: [Int: [FlowRun]] = [:]
        // Negative word ids, unique across the whole diff: the tokenizer restarts at 0 per span, and change ids are
        // the non-negative part ids — a collision would cross selection, dropdown anchors and the per-id caches.
        var next = 0
        for part in diffParts {
            if case .same(let id, let sameText) = part {
                let segments = Tokenizer.segments(sameText).map {
                    TextSegment(id: -1 - next - $0.id, text: $0.text, isWord: $0.isWord, isWhitespace: $0.isWhitespace)
                }
                next += segments.count
                runs[id] = FlowComposer.runs(segments)
            }
        }
        sameRunsCache = (capturedSource, text, runs)
        return runs
    }

    var diffChangeCount: Int {
        diffParts.count { if case .change = $0 { return true } else { return false } }
    }

    var splitFixView: Bool { diffChangeCount > 3 }

    var diffHidden: Bool = false

    func toggleDiffHidden() {
        closeDropdown()
        // The hidden-diff view keys words by token id, which overlaps the diff's change ids.
        altsCache.removeAll()
        diffHidden.toggle()
    }

    func openDropdown(for id: Int, word: String = "", fixChange: (before: String, after: String)? = nil) {
        selectedWordID = id
        selectedWord = word
        selectedFixChange = fixChange
        alternatives = []
        altsLoading = true
        altsRequestToken &+= 1
        closeExplanation()
    }

    func closeDropdown() {
        selectedWordID = nil
        selectedWord = ""
        selectedFixChange = nil
        altsLoading = false
        alternatives = []
        closeExplanation()
    }

    /// A correction with no word to look up opens straight onto its reason.
    func openFixReason(id: Int, before: String, after: String) {
        openDropdown(for: id, fixChange: (before, after))
        altsLoading = false
        showFixReason()
    }

    func showFixReason() {
        fixReasonMode = true
        showingExplanation = true
        explanationText = ""
        explanationLoading = true
        fixReasonContentHeight = 0
        explanationRequestToken &+= 1
    }

    func openExplanation() {
        showingExplanation = true
        explanationText = ""
        explanationLoading = true
        explanationRequestToken &+= 1
    }

    func closeExplanation() {
        fixReasonMode = false
        fixReasonContentHeight = 0
        showingExplanation = false
        explanationText = ""
        explanationLoading = false
    }

    private var undoSnapshot: (text: String, truncated: Bool)?
    var canUndo: Bool { undoSnapshot != nil }

    // Captured by PopupView right before a picked alternative triggers a reword.
    func snapshotForUndo() {
        undoSnapshot = (text, truncated)
        clearToneNote()
    }

    // Restores the pre-reword result; clears the snapshot (single level).
    func undo() {
        guard let snapshot = undoSnapshot else { return }
        closeDropdown()
        altsCache.removeAll()
        explanationCache.removeAll()
        fixReasonCache.removeAll()
        text = snapshot.text
        truncated = snapshot.truncated
        errorMessage = nil
        phase = .done
        undoSnapshot = nil
    }

    func clearUndo() {
        undoSnapshot = nil
    }
}
