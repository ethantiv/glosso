import AppKit
import SwiftUI

@MainActor
final class TranslationPopupController: TranslationPopupPresenting {
    var onDismiss: (@MainActor () -> Void)?

    private var panel: FloatingPanel?
    private let model = PopupModel()
    private var escMonitor: Any?
    private var closeObserver: NSObjectProtocol?
    private var resizeObserver: NSObjectProtocol?
    private var moveObserver: NSObjectProtocol?
    private var anchorTopLeft: CGPoint = .zero
    private var anchorScreenFrame: CGRect = .zero

    private static let defaultSize = CGSize(width: 561, height: 160)
    private static let escKeyCode: UInt16 = 53

    func present(at screenPoint: CGPoint) {
        tearDown()

        model.sourceText = ""
        model.text = ""
        model.phase = .capturing
        model.direction = .unknown
        model.errorMessage = nil
        model.truncated = false

        let size = Self.defaultSize
        let panel = FloatingPanel(contentRect: CGRect(origin: .zero, size: size))
        // Borderless windows have no visible title, but macOS accessibility still
        // reads NSWindow.title to name the window for VoiceOver; without it the
        // popup announces as an untitled window. Resolved to the direction in update().
        panel.title = "Tłumaczenie"
        let host = NSHostingController(rootView: PopupView(model: model, close: { [weak self] in
            self?.dismiss()
        }))
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
        // The panel is non-activating and the app is LSUIElement, so a local
        // monitor never sees Esc (it is routed to the foreground app). A global
        // monitor observes it instead.
        escMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                // Bare Esc only: Cmd/Shift/Ctrl/Option+Esc are distinct system
                // shortcuts (Force Quit, etc.) and must not kill the stream.
                let chordModifiers: NSEvent.ModifierFlags = [.command, .shift, .control, .option]
                guard event.keyCode == Self.escKeyCode,
                      event.modifierFlags.intersection(chordModifiers).isEmpty
                else { return }
                self?.dismiss()
            }
        }
    }

    private func removeMonitors() {
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
