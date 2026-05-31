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
        var topLeftX = mouse.x + offset
        var topLeftY = mouse.y

        let maxX = screenFrame.maxX - panelSize.width
        if topLeftX > maxX { topLeftX = maxX }
        if topLeftX < screenFrame.minX { topLeftX = screenFrame.minX }

        // top-left y is the panel's top edge; the bottom edge sits height below it.
        let maxTopY = screenFrame.maxY
        let minTopY = screenFrame.minY + panelSize.height
        if topLeftY > maxTopY { topLeftY = maxTopY }
        if topLeftY < minTopY { topLeftY = minTopY }

        return CGPoint(x: topLeftX, y: topLeftY)
    }
}
