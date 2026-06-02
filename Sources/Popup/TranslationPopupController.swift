import AppKit
import SwiftUI

@MainActor
final class TranslationPopupController: TranslationPopupPresenting {
    var onDismiss: (@MainActor () -> Void)?
    var onSelectFormality: (@MainActor (Formality) -> Void)?
    var onFetchAlternatives: (@MainActor (_ word: String, _ translation: String) async -> [String])?
    var onPickAlternative: (@MainActor (_ original: String, _ chosen: String, _ translation: String) -> Void)?

    private var panel: FloatingPanel?
    private let model = PopupModel()
    private var eventTap: CFMachPort?
    private var tapRunLoopSource: CFRunLoopSource?
    private var escMonitor: Any?
    private var closeObserver: NSObjectProtocol?
    private var resizeObserver: NSObjectProtocol?
    private var moveObserver: NSObjectProtocol?
    private var anchorTopLeft: CGPoint = .zero
    private var anchorScreenFrame: CGRect = .zero

    private static let defaultSize = CGSize(width: 561, height: 160)

    func present(at screenPoint: CGPoint, formality: Formality) {
        tearDown()

        resetTranslationPane()
        model.sourceText = ""
        model.direction = .unknown
        model.formality = formality

        let size = Self.defaultSize
        let panel = FloatingPanel(contentRect: CGRect(origin: .zero, size: size))
        // Borderless windows have no visible title, but macOS accessibility still
        // reads NSWindow.title to name the window for VoiceOver; without it the
        // popup announces as an untitled window. Resolved to the direction in update().
        panel.title = "Tłumaczenie"
        let host = NSHostingController(rootView: PopupView(
            model: model,
            close: { [weak self] in self?.dismiss() },
            selectFormality: { [weak self] formality in self?.onSelectFormality?(formality) },
            fetchAlternatives: { [weak self] word, translation in
                await self?.onFetchAlternatives?(word, translation) ?? []
            },
            pickAlternative: { [weak self] original, chosen, translation in
                self?.onPickAlternative?(original, chosen, translation)
            }
        ))
        // Let the SwiftUI content drive the window size so the panel grows to fit
        // longer text instead of clipping it (capped per pane, then scrolls).
        host.sizingOptions = [.preferredContentSize]
        panel.contentViewController = host

        // visibleFrame excludes the menu bar / notch and the Dock, so the window
        // never opens partly behind them.
        let frame = screen(containing: screenPoint).visibleFrame
        let topLeft = PanelPositioning.topLeft(
            forMouse: screenPoint,
            panelSize: size,
            screenFrame: frame
        )
        anchorTopLeft = topLeft
        anchorScreenFrame = frame
        panel.setFrameTopLeftPoint(topLeft)
        panel.orderFrontRegardless()
        self.panel = panel

        // The content sizes itself to the text, so the panel grows as tokens
        // stream in. AppKit keeps the bottom-left origin fixed on resize, which
        // would creep the window up over the cursor; re-pin the top-left so it
        // grows downward instead — raising it only when the taller panel would
        // drop its bottom edge below the visible frame (behind the Dock).
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: panel, queue: .main
        ) { [weak self, weak panel] _ in
            MainActor.assumeIsolated {
                guard let self, let panel, self.panel === panel else { return }
                let screenFrame = panel.screen?.visibleFrame ?? self.anchorScreenFrame
                var topLeft = self.anchorTopLeft
                let minTopY = screenFrame.minY + panel.frame.height
                if topLeft.y < minTopY { topLeft.y = minTopY }
                if topLeft.y > screenFrame.maxY { topLeft.y = screenFrame.maxY }
                let maxLeftX = screenFrame.maxX - panel.frame.width
                if topLeft.x > maxLeftX { topLeft.x = maxLeftX }
                if topLeft.x < screenFrame.minX { topLeft.x = screenFrame.minX }
                panel.setFrameTopLeftPoint(topLeft)
            }
        }

        // The window is movable now, so a user drag re-anchors where it should
        // grow from; otherwise the resize observer would yank it back to the
        // original spot on the next streamed token.
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
        for observer in [closeObserver, resizeObserver, moveObserver].compactMap({ $0 }) {
            NotificationCenter.default.removeObserver(observer)
        }
        closeObserver = nil
        resizeObserver = nil
        moveObserver = nil
    }

    private func installMonitors() {
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
            dropdownVisible: model.dropdownVisible
        ) {
        case .passThrough:
            return false
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
                    dropdownVisible: self.model.dropdownVisible
                ) {
                case .passThrough: break
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
