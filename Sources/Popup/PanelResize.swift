import CoreGraphics

enum PanelResize {
    /// Returns the content-size delta for a finished grip drag that started at
    /// `startDelta`. The grip sits at the bottom-right, so the drag translation
    /// (positive = right/down) enlarges, clamped at .zero — the panes never
    /// shrink below their design size. Values are rounded to whole points:
    /// fractional pane widths make the window's ideal size fractional, and the
    /// hosting machinery oscillates between its integral roundings (see
    /// PopupModel.sizeDelta). The delta feeds PopupModel.sizeDelta; the window
    /// itself follows the grown content.
    static func delta(startDelta: CGSize, translation: CGSize) -> CGSize {
        CGSize(
            width: max((startDelta.width + translation.width).rounded(), 0),
            height: max((startDelta.height + translation.height).rounded(), 0)
        )
    }
}
