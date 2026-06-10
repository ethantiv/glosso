import CoreGraphics

enum PanelResize {
    /// Returns the content-size delta for a grip drag that started at
    /// `startDelta`. The grip sits at the bottom-right, so the drag translation
    /// (positive = right/down) enlarges, clamped at .zero — the panes never
    /// shrink below their design size. The delta feeds PopupModel.sizeDelta;
    /// the window itself follows the grown content.
    static func delta(startDelta: CGSize, translation: CGSize) -> CGSize {
        CGSize(
            width: max(startDelta.width + translation.width, 0),
            height: max(startDelta.height + translation.height, 0)
        )
    }
}
