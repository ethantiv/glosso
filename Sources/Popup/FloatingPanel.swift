import AppKit

final class FloatingPanel: NSPanel {
    init(contentRect: CGRect) {
        // No .resizable here: its system edge-resize zones would fight the
        // controller-owned window frame (applyContentSize is the single writer;
        // competing setFrame calls get reverted synchronously), and they don't
        // respond on a panel that never becomes key anyway. User resizing is
        // handled by the custom grip in PopupView instead.
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        level = .floating
        // No .canJoinAllSpaces: the panel stays on the Space it was opened on and is
        // hidden on the others, instead of appearing on every desktop at once.
        collectionBehavior = [.fullScreenAuxiliary]
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

    // The source pane is an editable field (issue #44). A non-activating panel only
    // receives keystrokes while it is the key window, so it must be allowed to become
    // key — .nonactivatingPanel keeps the owning (LSUIElement) app in the background
    // even then, so typing into the field never yanks the user out of the source app.
    // present() still uses orderFrontRegardless(), so the panel only becomes key when
    // the user clicks into the field, not on appearance.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
