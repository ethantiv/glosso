import AppKit
import Testing
@testable import Glosso

@MainActor
@Suite("FloatingPanel")
struct FloatingPanelTests {
    @Test("panel is user-resizable without losing its non-activating borderless style")
    func styleMaskAllowsResizing() {
        let panel = FloatingPanel(contentRect: .zero)
        #expect(panel.styleMask.contains(.resizable))
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.styleMask.contains(.borderless))
    }

    @Test("minimum window size never clips the card at its design pane widths")
    func minWindowSizeCoversDesignLayout() {
        let minSize = PopupView.minWindowSize
        #expect(minSize.width >= 561 + 2 * PopupView.shadowMargin)
        #expect(minSize.height >= 160 + 2 * PopupView.shadowMargin)
    }
}
