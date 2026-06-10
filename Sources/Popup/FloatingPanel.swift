import AppKit

final class FloatingPanel: NSPanel {
    init(contentRect: CGRect) {
        // .resizable on a borderless panel enables the system edge-drag resize
        // zones without a title bar; resizing works even though the panel never
        // becomes key. The hot zones sit at the window frame edge, which lies
        // PopupView.shadowMargin outside the visible card.
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless, .resizable],
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
        // Borderless has no title bar, so a transparent background lets the
        // rounded SwiftUI material show through. Dragging anywhere on the
        // background moves the panel (no title bar grab).
        isOpaque = false
        backgroundColor = .clear
        // The shadow is drawn in SwiftUI (PopupView), not by AppKit: the system
        // window shadow hugs the whole content alpha, which rings the dropdown's
        // protruding part with a hard contour. SwiftUI shadows on the panel and the
        // dropdown stay independent and soft.
        hasShadow = false
        isMovableByWindowBackground = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
