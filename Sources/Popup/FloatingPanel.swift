import AppKit

final class FloatingPanel: NSPanel {
    init(contentRect: CGRect) {
        // No .resizable here: on a resizable window AppKit stops honoring the
        // hosting controller's preferredContentSize, which kills the grow-as-
        // tokens-stream behavior, and its edge zones don't respond on a panel
        // that never becomes key anyway. User resizing is handled by the custom
        // grip in PopupView instead.
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless],
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
        // rounded SwiftUI material show through.
        isOpaque = false
        backgroundColor = .clear
        // The shadow is drawn in SwiftUI (PopupView), not by AppKit: the system
        // window shadow hugs the whole content alpha, which rings the dropdown's
        // protruding part with a hard contour. SwiftUI shadows on the panel and the
        // dropdown stay independent and soft.
        hasShadow = false
        // Moving is a SwiftUI WindowDragGesture on the card (PopupView), NOT the
        // background-drag machinery: with this enabled the draggable region is
        // published to the WindowServer ahead of time for the whole window, so
        // dragging the resize grip also moved the window — and nothing reactive
        // can stop it (the grip NSView's mouseDownCanMoveWindow is ignored, and
        // hover/mouseDown toggles or a dynamic getter lose to the pre-published
        // region). The gesture can't fire over the grip by construction: events
        // over an NSViewRepresentable never enter SwiftUI's gesture graph.
        isMovableByWindowBackground = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
