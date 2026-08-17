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
    var capturedSource: String = ""
    var text: String = ""
    var phase: Phase = .capturing
    var direction: TranslationDirection = .unknown
    var errorMessage: String? = nil
    var truncated: Bool = false
    var formality: Formality = .automatic
    var action: Action = .translate
    var sizeDelta: CGSize = .zero

    var replyDrafts: [String] = []
    var selectedDraftIndex: Int? = nil

    func selectDraft(_ index: Int) {
        guard replyDrafts.indices.contains(index) else { return }
        selectedDraftIndex = index
        text = replyDrafts[index]
    }

    var selectedWordID: Int? = nil
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
        for part in diffParts {
            if case .same(let id, let sameText) = part {
                runs[id] = FlowComposer.runs(Tokenizer.segments(sameText))
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
        if !diffHidden { closeDropdown() }
        diffHidden.toggle()
    }

    func openDropdown(for id: Int) {
        selectedWordID = id
        alternatives = []
        altsLoading = true
        altsRequestToken &+= 1
        closeExplanation()
    }

    func closeDropdown() {
        selectedWordID = nil
        altsLoading = false
        alternatives = []
        fixReasonMode = false
        fixReasonContentHeight = 0
        closeExplanation()
    }

    func openFixReason(id: Int, before: String, after: String) {
        selectedWordID = id
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
