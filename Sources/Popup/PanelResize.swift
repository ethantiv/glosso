import CoreGraphics

enum PanelResize {
    static func delta(startDelta: CGSize, translation: CGSize) -> CGSize {
        CGSize(
            width: max((startDelta.width + translation.width).rounded(), 0),
            height: max((startDelta.height + translation.height).rounded(), 0)
        )
    }
}
