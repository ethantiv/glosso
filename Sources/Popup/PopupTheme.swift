import SwiftUI

/// What's left of the popup's own styling after the move to system materials and colors: geometry, type and motion.
/// Colors are gone on purpose — controls take the user's accent, surfaces take Liquid Glass or a system material.
enum PopupTheme {
    static let rWindow: CGFloat = 16
    static let rPane: CGFloat = 12
    static let rControl: CGFloat = 7
    static let padPane: CGFloat = 15
    static let padWindow: CGFloat = 9

    static let fontLabel = Font.system(size: 11, weight: .semibold)
    static let fontMeta = Font.system(size: 12, weight: .medium)
    static let fontControl = Font.system(size: 13, weight: .semibold)
    static let fontLead = Font.system(size: 16)
}
