import CoreGraphics

enum PanelResize {
    /// Returns the window frame for a grip drag that started at `startFrame`,
    /// in macOS global coordinates (y grows upward). The grip sits at the
    /// bottom-right, so the drag translation (SwiftUI coordinates: y grows
    /// downward) maps right/down to wider/taller. The top-left corner stays
    /// pinned — the frame origin moves down as the height grows — and the
    /// size never shrinks below `minSize`.
    static func frame(
        startFrame: CGRect,
        translation: CGSize,
        minSize: CGSize
    ) -> CGRect {
        let width = max(startFrame.width + translation.width, minSize.width)
        let height = max(startFrame.height + translation.height, minSize.height)
        return CGRect(
            x: startFrame.minX,
            y: startFrame.maxY - height,
            width: width,
            height: height
        )
    }
}
