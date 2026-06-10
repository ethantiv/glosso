import CoreGraphics

enum PanelResize {
    /// Returns the content-size delta for a grip drag that started at
    /// `startDelta`. The grip sits at the bottom-right, so the drag translation
    /// (positive = right/down) enlarges, clamped at .zero — the panes never
    /// shrink below their design size. Values are rounded to whole points so
    /// the content's ideal size stays integral (fractional window metrics
    /// re-invalidate layout forever). The delta feeds PopupModel.sizeDelta;
    /// the window follows the grown content.
    static func delta(startDelta: CGSize, translation: CGSize) -> CGSize {
        CGSize(
            width: max((startDelta.width + translation.width).rounded(), 0),
            height: max((startDelta.height + translation.height).rounded(), 0)
        )
    }
}
