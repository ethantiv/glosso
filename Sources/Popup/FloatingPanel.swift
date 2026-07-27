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
        hasShadow = false
        isMovableByWindowBackground = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
