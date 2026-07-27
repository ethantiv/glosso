import AppKit
import SwiftUI

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

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.activeAlways, .inVisibleRect, .cursorUpdate, .mouseEnteredAndExited],
                owner: self,
                userInfo: nil
            ))
        }

        override func cursorUpdate(with event: NSEvent) {
            NSCursor.frameResize(position: .bottomRight, directions: .all).set()
        }

        override func mouseExited(with event: NSEvent) {
            NSCursor.arrow.set()
        }

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
