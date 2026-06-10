import AppKit
import SwiftUI

@MainActor
final class TranslationPopupController: TranslationPopupPresenting {
    var onDismiss: (@MainActor () -> Void)?
    var onSelectFormality: (@MainActor (Formality) -> Void)?
    var onFetchAlternatives: (@MainActor (_ word: String, _ translation: String) async -> [String])?
    var onPickAlternative: (@MainActor (_ original: String, _ chosen: String, _ translation: String) -> Void)?
    var onFetchExplanation: (@MainActor (_ word: String, _ translation: String) async -> String)?
    var onReplace: (@MainActor (_ translation: String) -> Void)?

    private var panel: FloatingPanel?
    private let model = PopupModel()
    // The latest ideal window size reported by PopupView's onGeometryChange —
    // the only size source: the hosting view runs with sizingOptions = [], so
    // no AppKit constraint machinery can resize (or drift) the window on its
    // own. (.intrinsicContentSize installs real size constraints and the
    // window's autolayout then repositions the window with a drifting origin;
    // .preferredContentSize resizes the window from inside window layout and
    // recurses to a stack overflow under a live grip drag.)
    private var contentIdealSize: CGSize?
    private var eventTap: CFMachPort?
    private var tapRunLoopSource: CFRunLoopSource?
    private var escMonitor: Any?
    private var outsideClickMonitor: Any?
    private var closeObserver: NSObjectProtocol?
    private var moveObserver: NSObjectProtocol?
    private var sizeApplyScheduled = false
    private var resizeStartDelta: CGSize?
    private var anchorTopLeft: CGPoint = .zero
    private var anchorScreenFrame: CGRect = .zero

    private static let defaultSize = CGSize(width: 561, height: 160)

    func present(at screenPoint: CGPoint, formality: Formality) {
        tearDown()

        resetTranslationPane()
        // A fresh capture must not let Undo reach back to an unrelated previous
        // translation (issue #25); resetTranslationPane is shared with reword, which
        // keeps the snapshot, so clear it only on this fresh-translation path.
        model.clearUndo()
        model.sourceText = ""
        model.direction = .unknown
        model.formality = formality
        model.sizeDelta = .zero
        resizeStartDelta = nil

        let panel = FloatingPanel(contentRect: CGRect(origin: .zero, size: Self.defaultSize))
        // Borderless windows have no visible title, but macOS accessibility still
        // reads NSWindow.title to name the window for VoiceOver; without it the
        // popup announces as an untitled window. Resolved to the direction in update().
        panel.title = "Tłumaczenie"
        let hostView = NSHostingView(rootView: PopupView(
            model: model,
            close: { [weak self] in self?.dismiss() },
            selectFormality: { [weak self] formality in self?.onSelectFormality?(formality) },
            fetchAlternatives: { [weak self] word, translation in
                await self?.onFetchAlternatives?(word, translation) ?? []
            },
            fetchExplanation: { [weak self] word, translation in
                await self?.onFetchExplanation?(word, translation) ?? ""
            },
            pickAlternative: { [weak self] original, chosen, translation in
                self?.onPickAlternative?(original, chosen, translation)
            },
            replace: { [weak self] text in self?.onReplace?(text) },
            resizeBy: { [weak self] translation, ended in
                self?.handleResizeDrag(translation: translation, ended: ended)
            },
            reportSize: { [weak self] size in
                self?.contentIdealSize = size
                self?.scheduleApplyContentSize()
            }
        ))
        hostView.sizingOptions = []
        panel.contentView = hostView

        // Measure the content before positioning, so the panel opens at its
        // real size instead of growing right after appearing — the layout pass
        // delivers the first reportSize.
        contentIdealSize = nil
        hostView.layoutSubtreeIfNeeded()
        let size = contentIdealSize ?? Self.defaultSize

        // visibleFrame excludes the menu bar / notch and the Dock, so the window
        // never opens partly behind them.
        let frame = screen(containing: screenPoint).visibleFrame
        let panelTopLeft = PanelPositioning.topLeft(
            forMouse: screenPoint,
            panelSize: size,
            screenFrame: frame
        )
        // The window carries a transparent shadow margin around the visible panel, so
        // shift its top-left up-left by that margin to keep the panel under the cursor.
        let margin = PopupView.shadowMargin
        // Whole points: a fractional anchor can never equal the window's
        // integral frame, which would make applyContentSize re-apply forever.
        let topLeft = CGPoint(
            x: (panelTopLeft.x - margin).rounded(),
            y: (panelTopLeft.y + margin).rounded()
        )
        anchorTopLeft = topLeft
        anchorScreenFrame = frame
        panel.setFrame(
            CGRect(x: topLeft.x, y: topLeft.y - size.height, width: size.width, height: size.height),
            display: false
        )
        panel.orderFrontRegardless()
        self.panel = panel

        // The window is movable, so a user drag re-anchors where the content-
        // driven growth in applyContentSize() should grow from; otherwise it
        // would yank the window back to the original spot on the next token.
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak self, weak panel] _ in
            MainActor.assumeIsolated {
                guard let self, let panel, self.panel === panel else { return }
                self.anchorTopLeft = CGPoint(x: panel.frame.minX, y: panel.frame.maxY)
            }
        }

        // The red close button calls close() on the panel directly, bypassing our
        // dismiss(). Observe willClose so that path still releases monitors and
        // notifies the coordinator to cancel the in-flight capture. dismiss() and
        // tearDown() remove this observer *before* closing, so this handler runs
        // only for the close-button path — and only while this exact panel is the
        // current one (a new present() mid-close must not nil out the new panel).
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: panel, queue: .main
        ) { [weak self, weak panel] _ in
            MainActor.assumeIsolated {
                guard let self, let panel, self.panel === panel else { return }
                self.releaseResources()
                self.panel = nil
                self.onDismiss?()
            }
        }

        installMonitors()
    }

    func update(direction: TranslationDirection, sourceText: String) {
        model.direction = direction
        model.sourceText = sourceText
        panel?.title = "Tłumaczenie · \(direction.label)"
    }

    func append(token: String) {
        if model.phase == .capturing { model.phase = .streaming }
        model.text += token
    }

    func showError(_ message: String) {
        model.phase = .error
        model.errorMessage = message
    }

    func finish(truncated: Bool) {
        model.truncated = truncated
        model.phase = .done
    }

    func restartTranslation() {
        resetTranslationPane()
    }

    // Clears just the translation pane back to its loading skeleton, leaving the
    // source text, direction and selected tone in place. Shared by present() (which
    // additionally resets those) and restartTranslation() so neither path can drift.
    private func resetTranslationPane() {
        // A pane restart (re-translation for tone or a picked alternative) must
        // drop any open word dropdown; otherwise it reappears over the new result.
        model.closeDropdown()
        model.text = ""
        model.errorMessage = nil
        model.truncated = false
        model.phase = .capturing
    }

    // Coalesces the hosting view's ideal-size callbacks (several can fire per
    // content change) into one frame application on the next runloop turn —
    // applying from within layout would re-enter it.
    private func scheduleApplyContentSize() {
        guard !sizeApplyScheduled else { return }
        sizeApplyScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.sizeApplyScheduled = false
            self.applyContentSize()
        }
    }

    // The single writer of the window frame: sizes the panel to the content's
    // ideal size (streamed tokens, dropdown growth, grip stretching) with the
    // top-left pinned, so it grows downward instead of creeping up over the
    // cursor (AppKit keeps the bottom-left fixed) — raising it only when the
    // taller panel would drop its bottom edge below the visible frame (behind
    // the Dock).
    private func applyContentSize() {
        guard let panel, var size = contentIdealSize else { return }
        guard size.width > 0, size.height > 0 else { return }
        // Integral sizes: fractional window metrics round differently at the
        // window level and the mismatch re-invalidates layout forever.
        size = CGSize(width: size.width.rounded(.up), height: size.height.rounded(.up))
        let screenFrame = panel.screen?.visibleFrame ?? anchorScreenFrame
        var topLeft = anchorTopLeft
        let minTopY = screenFrame.minY + size.height
        if topLeft.y < minTopY { topLeft.y = minTopY }
        if topLeft.y > screenFrame.maxY { topLeft.y = screenFrame.maxY }
        let maxLeftX = screenFrame.maxX - size.width
        if topLeft.x > maxLeftX { topLeft.x = maxLeftX }
        if topLeft.x < screenFrame.minX { topLeft.x = screenFrame.minX }
        // Compare the whole target frame, not just the size: any drift of the
        // origin (whatever its source) must be corrected back to the anchor.
        let target = CGRect(
            x: topLeft.x, y: topLeft.y - size.height, width: size.width, height: size.height
        )
        guard target != panel.frame else { return }
        panel.setFrame(target, display: true)
    }

    // Resizes from the PopupView grip — live, by stretching the content
    // (model.sizeDelta): the pane sizes change, the hosting view reports the
    // new ideal size, and applyContentSize() moves the window frame. All
    // sizing flows through that one path; the window is never resized from
    // the drag handler itself.
    private func handleResizeDrag(translation: CGSize, ended: Bool) {
        if resizeStartDelta == nil { resizeStartDelta = model.sizeDelta }
        guard let startDelta = resizeStartDelta else { return }
        model.sizeDelta = PanelResize.delta(startDelta: startDelta, translation: translation)
        if ended { resizeStartDelta = nil }
    }

    func dismiss() {
        guard let panel else { return }
        // Remove the willClose observer first so close() below doesn't re-enter
        // the close-button path; fire onDismiss ourselves instead.
        releaseResources()
        panel.orderOut(nil)
        panel.close()
        self.panel = nil
        onDismiss?()
    }

    // Releases the panel and its observers without firing onDismiss, so present()
    // can reuse it to stay idempotent without cancelling the in-flight capture task.
    private func tearDown() {
        guard let panel else { return }
        releaseResources()
        panel.orderOut(nil)
        panel.close()
        self.panel = nil
    }

    // Removes the event monitors and the willClose observer. Shared by dismiss(),
    // tearDown() and the close-button path so each tears the same state down once.
    private func releaseResources() {
        removeMonitors()
        for observer in [closeObserver, moveObserver].compactMap({ $0 }) {
            NotificationCenter.default.removeObserver(observer)
        }
        closeObserver = nil
        moveObserver = nil
        contentIdealSize = nil
    }

    private func installMonitors() {
        // A global mouse monitor fires only for clicks delivered to *other* apps, so
        // it sees exactly the clicks that land outside our non-activating panel —
        // clicks inside it stay local and the SwiftUI scrim handles those. Used only
        // to close an open word dropdown (issue #30); it never dismisses the panel
        // (that outside-click-to-dismiss was deliberately dropped in 5f4a549 when the
        // window became movable and gained a close button).
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.model.dropdownVisible else { return }
                self.model.closeDropdown()
            }
        }

        // The panel is non-activating and the app is LSUIElement, so Esc is routed
        // to the foreground (source) app. A global NSEvent monitor can only observe
        // it — it can't stop Esc from also firing in the source app (issue #27). A
        // CGEventTap can return nil to swallow the event before it gets there. It
        // needs the Accessibility permission, which the app already holds.
        let mask = CGEventMask(1) << CGEventType.keyDown.rawValue
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: translationPopupEscTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        guard let tap else {
            // tapCreate fails only if Accessibility isn't granted; the app can't
            // show a popup without it (the hotkey monitor needs it too), so this is
            // purely defensive. Fall back to the old observe-only monitor so Esc
            // still dismisses the popup — it just won't be swallowed.
            installFallbackMonitor()
            return
        }
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        tapRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    // macOS disables a tap that's too slow or hit by heavy input; re-enable it or
    // Esc would silently stop being swallowed.
    fileprivate func reenableTap() {
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
    }

    // Decides what to do with a bare keyDown and triggers any side effect. Takes
    // Sendable scalars (not the CGEvent/NSEvent) so the CGEvent stays in the
    // callback's nonisolated region — passing it across the actor hop would force
    // it to be Sendable, which it isn't.
    fileprivate func handleTapKeyDown(keyCode: UInt16, modifiersRawValue: UInt) -> Bool {
        switch EscKeyHandling.action(
            keyCode: keyCode,
            modifiers: NSEvent.ModifierFlags(rawValue: modifiersRawValue),
            dropdownVisible: model.dropdownVisible,
            explanationVisible: model.showingExplanation
        ) {
        case .passThrough:
            return false
        case .closeExplanation:
            // Same reasoning as closeDropdown: pure model mutation, run synchronously
            // so a fast second Esc sees the explanation already closed and falls
            // through to closing the dropdown.
            model.closeExplanation()
            return true
        case .closeDropdown:
            // closeDropdown() only mutates model state — it never touches the tap —
            // so run it synchronously. Deferring it would let a fast second Esc read
            // a stale dropdownVisible and re-close instead of dismissing the panel.
            model.closeDropdown()
            return true
        case .dismiss:
            // Defer: dismiss() reaches removeMonitors(), which would invalidate this
            // tap from inside its own callback. Swallow now, tear down on the next hop.
            DispatchQueue.main.async { [weak self] in self?.dismiss() }
            return true
        }
    }

    private func installFallbackMonitor() {
        escMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                switch EscKeyHandling.action(
                    keyCode: event.keyCode,
                    modifiers: event.modifierFlags,
                    dropdownVisible: self.model.dropdownVisible,
                    explanationVisible: self.model.showingExplanation
                ) {
                case .passThrough: break
                case .closeExplanation: self.model.closeExplanation()
                case .closeDropdown: self.model.closeDropdown()
                case .dismiss: self.dismiss()
                }
            }
        }
    }

    private func removeMonitors() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
        if let tapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), tapRunLoopSource, .commonModes)
            self.tapRunLoopSource = nil
        }
        if let escMonitor {
            NSEvent.removeMonitor(escMonitor)
            self.escMonitor = nil
        }
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
    }

    private func screen(containing point: CGPoint) -> NSScreen {
        for screen in NSScreen.screens where screen.frame.contains(point) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
    }
}

// A CGEventTap callback must be a non-capturing top-level function; the controller
// is threaded through `userInfo` as an opaque pointer. The tap runs on the main
// run loop, so the callback fires on the main thread — recover MainActor isolation
// the same way GlobalHotkeyMonitor does for its NSEvent callback.
private func translationPopupEscTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<TranslationPopupController>.fromOpaque(refcon).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { controller.reenableTap() }
        return Unmanaged.passUnretained(event)
    }
    // This fires on every keystroke while the popup is shown; only Esc matters, so
    // gate on the raw keycode field before allocating an NSEvent for the rest.
    guard UInt16(event.getIntegerValueField(.keyboardEventKeycode)) == EscKeyHandling.escKeyCode,
          let nsEvent = NSEvent(cgEvent: event)
    else { return Unmanaged.passUnretained(event) }
    let keyCode = nsEvent.keyCode
    let modifiersRawValue = nsEvent.modifierFlags.rawValue
    let swallow = MainActor.assumeIsolated {
        controller.handleTapKeyDown(keyCode: keyCode, modifiersRawValue: modifiersRawValue)
    }
    return swallow ? nil : Unmanaged.passUnretained(event)
}
