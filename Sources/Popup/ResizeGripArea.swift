import AppKit
import SwiftUI

// AppKit-level hit area for the resize grip. A SwiftUI DragGesture never sees
// the drag here: with isMovableByWindowBackground the window-move tracking
// claims the mouseDown unless the hit-tested NSView opts out, and NSHostingView
// only opts out real controls (Button etc.), not bare gesture modifiers. This
// NSView opts out itself and reports the drag as a cumulative translation in
// SwiftUI's y-down convention, matching the resizeBy callback.
struct ResizeGripArea: NSViewRepresentable {
    let resizeBy: (_ translation: CGSize, _ ended: Bool) -> Void

    func makeNSView(context: Context) -> GripView {
        let view = GripView()
        view.resizeBy = resizeBy
        return view
    }

    func updateNSView(_ view: GripView, context: Context) {
        view.resizeBy = resizeBy
    }

    final class GripView: NSView {
        var resizeBy: ((_ translation: CGSize, _ ended: Bool) -> Void)?
        private var startMouse: CGPoint?

        override var mouseDownCanMoveWindow: Bool { false }
        // Without this the first click on the grip is eaten as an activation
        // attempt — the non-activating panel's app is usually inactive.
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        // Lets FloatingPanel's isMovableByWindowBackground gate answer "not over
        // the grip" at mouseDown time — the race-free way to keep a grip drag
        // from also moving the window (see FloatingPanel).
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            (window as? FloatingPanel)?.resizeGripView = self
        }

        // Cursor rects are only serviced reliably on key windows, and this
        // panel never becomes key — drive the cursor from a tracking area.
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.activeAlways, .inVisibleRect, .cursorUpdate],
                owner: self,
                userInfo: nil
            ))
        }

        override func cursorUpdate(with event: NSEvent) {
            NSCursor.frameResize(position: .bottomRight, directions: .all).set()
        }

        // Deltas come from NSEvent.mouseLocation (screen coordinates): the
        // window — and this view — moves under the cursor during setFrame, so
        // window-relative coordinates would feed back into the resize. Screen
        // y grows upward, so dragging down must flip into a positive height.
        override func mouseDown(with event: NSEvent) {
            startMouse = NSEvent.mouseLocation
        }

        override func mouseDragged(with event: NSEvent) {
            guard let startMouse else { return }
            resizeBy?(translation(from: startMouse), false)
        }

        override func mouseUp(with event: NSEvent) {
            guard let startMouse else { return }
            resizeBy?(translation(from: startMouse), true)
            self.startMouse = nil
        }

        private func translation(from start: CGPoint) -> CGSize {
            let current = NSEvent.mouseLocation
            return CGSize(width: current.x - start.x, height: start.y - current.y)
        }
    }
}
