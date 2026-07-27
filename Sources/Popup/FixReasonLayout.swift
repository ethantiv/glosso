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
