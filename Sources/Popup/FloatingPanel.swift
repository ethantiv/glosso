import AppKit

final class FloatingPanel: NSPanel {
    init(contentRect: CGRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .titled, .closable],
            backing: .buffered,
            defer: false
        )

        level = .floating
        // .transient is documented as mutually exclusive with .canJoinAllSpaces;
        // keeping both can make the panel vanish on a Space switch mid-stream.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isFloatingPanel = true
        // NSPanel defaults to releasing itself on close; combined with our own
        // strong reference being dropped in dismiss() that over-releases under ARC.
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isMovable = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
