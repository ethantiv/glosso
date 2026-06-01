import AppKit
import SwiftUI

enum PopupTheme {
    static let accentNSColor = NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark
            ? NSColor(srgbRed: 0x6F / 255, green: 0x9D / 255, blue: 0xFD / 255, alpha: 1)
            : NSColor(srgbRed: 0x44 / 255, green: 0x75 / 255, blue: 0xE7 / 255, alpha: 1)
    }
    static let accent = Color(nsColor: accentNSColor)

    static var accentTintStrong: Color { accent.opacity(0.18) }
    static var accentWash: Color { accent.opacity(0.07) }
    static var chipNeutralBg: Color { Color.primary.opacity(0.08) }
    static var paneRecessed: Color { Color.primary.opacity(0.055) }
    static var hairline: Color { Color.primary.opacity(0.12) }
    static var warn: Color { .orange }
    static var warnBg: Color { Color.orange.opacity(0.10) }
    static var copied: Color { Color(red: 0.18, green: 0.62, blue: 0.34) }

    static let rWindow: CGFloat = 13
    static let rPane: CGFloat = 9
    static let rControl: CGFloat = 7
    static let padPane: CGFloat = 15
    static let padWindow: CGFloat = 9

    static let fontLabel = Font.system(size: 11, weight: .semibold)
    static let fontMeta = Font.system(size: 12, weight: .medium)
    static let fontSource = Font.system(size: 15)
    static let fontLead = Font.system(size: 16)

    static let durEnter: Double = 0.19
    static let durFast: Double = 0.13
    static let enterCurve = Animation.timingCurve(0.16, 1, 0.3, 1, duration: durEnter)
}
