import CoreGraphics

enum PanelPositioning {
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
