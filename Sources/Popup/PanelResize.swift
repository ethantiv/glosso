import CoreGraphics

enum PanelResize {
    /// Returns the window size for a grip drag that started at `startSize`.
    /// The grip sits at the bottom-right, so the drag translation (positive =
    /// right/down) maps directly to wider/taller, clamped at `minSize`. The
    /// resulting size flows into PopupModel.userSize — positioning (keeping the
    /// top-left pinned) stays with the controller's didResize observer.
    static func size(
        startSize: CGSize,
        translation: CGSize,
        minSize: CGSize
    ) -> CGSize {
        CGSize(
            width: max(startSize.width + translation.width, minSize.width),
            height: max(startSize.height + translation.height, minSize.height)
        )
    }
}
