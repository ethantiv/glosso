import AppKit
import SwiftUI

// Hosts PopupView and reports when its content's ideal size may have changed,
// leaving the actual window sizing to TranslationPopupController. The built-in
// window-driving option is unusable here: with .preferredContentSize the
// hosting view resizes the window from inside window layout
// (updateAnimatedWindowSize), which re-enters layout until the stack overflows
// once the content size changes continuously (live grip resize). The
// .intrinsicContentSize option only *reports* the ideal size — the controller
// reads it and sets the frame itself.
final class AutoSizingHostingView: NSHostingView<PopupView> {
    var onIdealSizeChange: (() -> Void)?

    required init(rootView: PopupView) {
        super.init(rootView: rootView)
        sizingOptions = [.intrinsicContentSize]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // SwiftUI invalidates the intrinsic size when the content's ideal size
    // changes, and renders inside layout(); hooking both catches every content
    // change (streamed tokens, dropdown growth, grip stretching) right after
    // the view graph is up to date. The callback only schedules — the
    // controller applies the size on the next runloop turn, so window layout
    // is never re-entered from within itself.
    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        onIdealSizeChange?()
    }

    override func layout() {
        super.layout()
        onIdealSizeChange?()
    }
}
