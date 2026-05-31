import AppKit
import SwiftUI

@MainActor
final class TranslationPopupController: TranslationPopupPresenting {
    var onDismiss: (@MainActor () -> Void)?

    private var panel: FloatingPanel?
    private let model = PopupModel()
    private var escMonitor: Any?
    private var outsideClickMonitor: Any?

    private static let defaultSize = CGSize(width: 360, height: 140)
    private static let escKeyCode: UInt16 = 53

    func present(direction: TranslationDirection, at screenPoint: CGPoint) {
        model.direction = direction
        model.text = ""
        model.phase = .streaming
        model.errorMessage = nil

        let size = Self.defaultSize
        let panel = FloatingPanel(contentRect: CGRect(origin: .zero, size: size))
        panel.contentViewController = NSHostingController(rootView: PopupView(model: model))

        let frame = screen(containing: screenPoint).frame
        let topLeft = PanelPositioning.topLeft(
            forMouse: screenPoint,
            panelSize: size,
            screenFrame: frame
        )
        panel.setFrameTopLeftPoint(topLeft)
        panel.orderFrontRegardless()
        self.panel = panel

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
        removeMonitors()
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        onDismiss?()
    }

    private func installMonitors() {
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == Self.escKeyCode {
                self.dismiss()
                return nil
            }
            return event
        }

        // The panel never becomes key, so clicks landing in other apps are only
        // observable through the global monitor; treat any such click as dismiss.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.dismiss()
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
