import CoreGraphics

// Sizing for the grammar-fix "why" dropdown (#73), split out as pure functions so
// the no-clip invariant can be tested deterministically. The window reserves space
// below the panel from `estimatedDropdownHeight`; the dropdown itself renders at
// `actualDropdownHeight`. As long as the estimate is never smaller than the actual
// height for the same measured reason, the dropdown always fits and never clips.
enum FixReasonLayout {
    // The non-interactive "Dlaczego poprawiono?" header row above the reason.
    static let header: CGFloat = 36
    // The spinner row shown while the reason is being fetched.
    static let loadingPane: CGFloat = 40
    // Floor for the reserve before the reason has been measured, so the first frame
    // still leaves a row of room rather than collapsing to the header.
    static let minPane: CGFloat = 44
    // Safety cap: a pathologically long reason scrolls inside the dropdown rather
    // than growing the window past the screen.
    static let maxReason: CGFloat = 300

    /// Height of the reason pane (and the ScrollView frame) for a measured content
    /// height — the reason grows the window up to the cap, then scrolls.
    static func reasonPaneHeight(content: CGFloat) -> CGFloat {
        min(content, maxReason)
    }

    /// What the window reserves below the panel for the dropdown.
    static func estimatedDropdownHeight(content: CGFloat, loading: Bool) -> CGFloat {
        loading ? header + loadingPane : header + min(max(content, minPane), maxReason)
    }

    /// The dropdown's real rendered height for a measured reason.
    static func actualDropdownHeight(content: CGFloat) -> CGFloat {
        header + reasonPaneHeight(content: content)
    }
}
