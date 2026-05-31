import AppKit
import SwiftUI

@MainActor
final class TranslationPopupController: TranslationPopupPresenting {
    var onDismiss: (@MainActor () -> Void)?

    private var panel: FloatingPanel?
    private let model = PopupModel()
    private var escMonitor: Any?
    private var outsideClickMonitor: Any?
    private var resizeObserver: NSObjectProtocol?
    private var anchorTopLeft: CGPoint = .zero

    private static let defaultSize = CGSize(width: 360, height: 140)
    private static let escKeyCode: UInt16 = 53

    func present(direction: TranslationDirection, at screenPoint: CGPoint) {
        tearDown()

        model.direction = direction
        model.text = ""
        model.phase = .streaming
        model.errorMessage = nil

        let size = Self.defaultSize
        let panel = FloatingPanel(contentRect: CGRect(origin: .zero, size: size))
        let host = NSHostingController(rootView: PopupView(model: model))
        // Let the SwiftUI content drive the window size so the panel grows to fit
        // longer translations instead of clipping them.
        host.sizingOptions = [.preferredContentSize]
        panel.contentViewController = host

        // visibleFrame excludes the menu bar / notch and the Dock, so the popup
        // never renders behind them (where the outside-click monitor would also
        // dismiss it the moment the user clicks the bar to reach it).
        let frame = screen(containing: screenPoint).visibleFrame
        let topLeft = PanelPositioning.topLeft(
            forMouse: screenPoint,
            panelSize: size,
            screenFrame: frame
        )
        anchorTopLeft = topLeft
        panel.setFrameTopLeftPoint(topLeft)
        panel.orderFrontRegardless()
        self.panel = panel

        // The hosting view drives the panel size, which grows as tokens stream
        // in. AppKit keeps the bottom-left origin fixed on resize, so without
        // this the panel would grow upward over the cursor; re-pin the top-left.
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel else { return }
                panel.setFrameTopLeftPoint(self.anchorTopLeft)
            }
        }

        installMonitors()
    }

    func append(token: String) {
        model.text += token
    }

    func showError(_ message: String) {
        model.phase = .error
        model.errorMessage = message
    }

    func finish() {
        model.phase = .done
    }

    func dismiss() {
        guard panel != nil else { return }
        tearDown()
        onDismiss?()
    }

    // Releases the panel and its observers without firing onDismiss, so present()
    // can reuse it to stay idempotent without cancelling the in-flight capture task.
    private func tearDown() {
        removeMonitors()
        if let resizeObserver {
            NotificationCenter.default.removeObserver(resizeObserver)
            self.resizeObserver = nil
        }
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }

    private func installMonitors() {
        // The panel is non-activating and the app is LSUIElement, so a local
        // monitor never sees Esc (it is routed to the foreground app). A global
        // monitor observes it the same way the outside-click one does.
        escMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                guard event.keyCode == Self.escKeyCode else { return }
                self?.dismiss()
            }
        }

        // The panel never becomes key, so clicks landing in other apps are only
        // observable through the global monitor; dismiss only when the click is
        // outside the panel, otherwise it races click-to-copy on the same event.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel,
                      !panel.frame.contains(NSEvent.mouseLocation) else { return }
                self.dismiss()
            }
        }
    }

    private func removeMonitors() {
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
