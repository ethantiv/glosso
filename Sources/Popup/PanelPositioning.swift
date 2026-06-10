import CoreGraphics

enum PanelPositioning {
    /// Returns the panel's top-left corner in macOS global coordinates
    /// (origin at the bottom-left of the screen, y grows upward).
    /// The panel is anchored just to the right of the cursor and drops down
    /// from it, then clamped so the whole panel stays inside `screenFrame`.
    static func topLeft(
        forMouse mouse: CGPoint,
        panelSize: CGSize,
        screenFrame: CGRect,
        offset: CGFloat = 12
    ) -> CGPoint {
        clampedTopLeft(
            CGPoint(x: mouse.x + offset, y: mouse.y),
            panelSize: panelSize,
            screenFrame: screenFrame
        )
    }

    /// Clamps a panel top-left so the whole panel stays inside `screenFrame`.
    /// Shared by the initial mouse-relative placement above and the controller's
    /// applyContentSize so the two can't disagree. When the panel is larger than
    /// the frame, the left and top edges win: the header (with the close button)
    /// stays reachable while the overflow drops off the bottom/right.
    static func clampedTopLeft(
        _ topLeft: CGPoint,
        panelSize: CGSize,
        screenFrame: CGRect
    ) -> CGPoint {
        var clamped = topLeft

        let maxX = screenFrame.maxX - panelSize.width
        if clamped.x > maxX { clamped.x = maxX }
        if clamped.x < screenFrame.minX { clamped.x = screenFrame.minX }

        // top-left y is the panel's top edge; the bottom edge sits height below it.
        let minTopY = screenFrame.minY + panelSize.height
        if clamped.y < minTopY { clamped.y = minTopY }
        if clamped.y > screenFrame.maxY { clamped.y = screenFrame.maxY }

        return clamped
    }
}
