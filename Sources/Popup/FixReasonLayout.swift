import CoreGraphics

/// The one measurement the fix-reason dropdown still needs: how tall its scroll pane may grow. Everything else this
/// enum used to hold was the window's reservation for the dropdown, which went away when the dropdown became a window
/// of its own and started sizing itself.
enum FixReasonLayout {
    static let maxReason: CGFloat = 300

    static func reasonPaneHeight(content: CGFloat) -> CGFloat {
        min(content, maxReason)
    }
}
