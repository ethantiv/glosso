import AppKit
import SwiftUI

enum PopupTheme {
    static let accentNSColor = NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark
            ? NSColor(srgbRed: 0x98 / 255, green: 0xA2 / 255, blue: 0xF8 / 255, alpha: 1)
            : NSColor(srgbRed: 0x4F / 255, green: 0x5B / 255, blue: 0xD8 / 255, alpha: 1)
    }
    static let accent = Color(nsColor: accentNSColor)

    // Solid, matte fill for the alternatives menu — opaque on purpose (not the
    // translucent .popover material) so it reads lighter and less glassy.
    static let menuSurfaceNSColor = NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark ? NSColor(white: 0.22, alpha: 1) : NSColor(white: 1, alpha: 1)
    }
    static let menuSurface = Color(nsColor: menuSurfaceNSColor)

    // Solid window surface — pure white in light (matches the brand mockups), a warm
    // graphite in dark. Replaces the translucent .popover vibrancy so the popup and
    // Settings read like native Notes/Reminders rather than a glassy gray panel.
    static let surfaceNSColor = NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark
            ? NSColor(srgbRed: 0x1E / 255, green: 0x1D / 255, blue: 0x1C / 255, alpha: 1)
            : NSColor(white: 1, alpha: 1)
    }
    static let surface = Color(nsColor: surfaceNSColor)

    // Grouped-section card in Settings — sits slightly raised above `surface`
    // (System Settings' grouped-box look), so its own fill, not a gray recess.
    static let groupedCardNSColor = NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 1, alpha: 1)
    }
    static let groupedCard = Color(nsColor: groupedCardNSColor)

    static var accentTintStrong: Color { accent.opacity(0.18) }
    static var chipNeutralBg: Color { Color.primary.opacity(0.08) }
    static var hairline: Color { Color.primary.opacity(0.12) }
    static var warn: Color { .orange }
    static var warnBg: Color { Color.orange.opacity(0.10) }
    static var copied: Color { Color(red: 0.18, green: 0.62, blue: 0.34) }

    // Brick red for diff deletions (the mockups' .del), separate from `warn`,
    // which stays for genuine warnings.
    static let diffDelNSColor = NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark
            ? NSColor(srgbRed: 0xE0 / 255, green: 0x6A / 255, blue: 0x50 / 255, alpha: 1)
            : NSColor(srgbRed: 0xC0 / 255, green: 0x49 / 255, blue: 0x2F / 255, alpha: 1)
    }
    static let diffDel = Color(nsColor: diffDelNSColor)

    static let rWindow: CGFloat = 16
    static let rPane: CGFloat = 12
    static let rControl: CGFloat = 7
    static let rPill: CGFloat = 9
    static let padPane: CGFloat = 15
    static let padWindow: CGFloat = 9

    // Settings keeps the smaller native sizing; the popup sizes mirror the
    // landing-page mockup panel (result and source both 16, labels 11).
    static let fontLabel = Font.system(size: 11, weight: .semibold)
    static let fontMeta = Font.system(size: 12, weight: .medium)
    static let fontSource = Font.system(size: 15)
    static let fontLead = Font.system(size: 16)

    static let fontControl = Font.system(size: 13, weight: .semibold)
    static let fontSectionLabel = Font.system(size: 11, weight: .semibold)
    static let fontSourceText = Font.system(size: 16)

    static let durEnter: Double = 0.19
    static let durFast: Double = 0.13
    static let enterCurve = Animation.timingCurve(0.16, 1, 0.3, 1, duration: durEnter)
}
