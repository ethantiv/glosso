import AppKit

final class FloatingPanel: NSPanel {
    init(contentRect: CGRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        level = .floating
        collectionBehavior = [.fullScreenAuxiliary]
        isFloatingPanel = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        // AppKit's own shadow, not a SwiftUI one: a hand-drawn shadow only has the window's transparent margin to blur
        // into, so it gets clipped by the window edge and reads as a hard line. The window shadow renders outside the
        // frame and matches every other window on screen. It is cached, though — see `invalidateShadow()` in the
        // controller.
        hasShadow = true
        isMovableByWindowBackground = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
