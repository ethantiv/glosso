import SwiftUI

/// What's left of the popup's own styling after the move to system materials and colors: geometry, type and motion.
/// Colors are gone on purpose — the panel is a system surface and the controls floating over it are Liquid Glass.
enum PopupTheme {
    static let rWindow: CGFloat = 16
    static let rPane: CGFloat = 12
    static let rControl: CGFloat = 7
    static let padPane: CGFloat = 15
    /// Tighter than the rest of the pane: the control row above already carries its own bottom padding, so the full
    /// inset stacked into a visible gap over the section labels.
    static let padPaneTop: CGFloat = 6
    static let padWindow: CGFloat = 9

    static let fontLabel = Font.system(size: 11, weight: .semibold)
    static let fontMeta = Font.system(size: 12, weight: .medium)
    static let fontControl = Font.system(size: 13, weight: .semibold)
    static let fontLead = Font.system(size: 16)
}
