import CoreGraphics

enum FixReasonLayout {
    // The non-interactive "Dlaczego poprawiono?" header row above the reason.
    static let header: CGFloat = 36
    // The spinner row shown while the reason is being fetched.
    static let loadingPane: CGFloat = 40
    static let minPane: CGFloat = 44
    static let maxReason: CGFloat = 300

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

/// The alternatives dropdown's rendered height, which `PopupView` reserves below the panel before the view exists.
/// Measured against `NSHostingView.fittingSize` in `PopupLayoutTests` — these are not guesses to be nudged by eye.
enum AlternativesLayout {
    /// The "Dlaczego tak?" header row plus the divider and the list's own padding.
    static let base: CGFloat = 33
    static let row: CGFloat = 31
    /// The spinner row, and the "no alternatives" row that replaces it.
    static let placeholder: CGFloat = 34

    static func estimatedHeight(count: Int, loading: Bool) -> CGFloat {
        loading || count == 0 ? base + placeholder : base + CGFloat(count) * row
    }
}
