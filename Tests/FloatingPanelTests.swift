import AppKit
import Testing
@testable import Glosso

@MainActor
@Suite("FloatingPanel")
struct FloatingPanelTests {
    @Test("panel stays a non-activating borderless window without .resizable, whose system edge-resize would fight the controller-owned window frame")
    func styleMaskKeepsControllerOwnedSizing() {
        let panel = FloatingPanel(contentRect: .zero)
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.styleMask.contains(.borderless))
        #expect(!panel.styleMask.contains(.resizable))
    }
}
