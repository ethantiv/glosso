import AppKit
import SwiftUI

/// Hosts the first-run wizard in a standard, activating titled window — unlike the
/// non-activating popup `FloatingPanel`, the wizard needs focus for its picker and
/// buttons. Both the "Zakończ" button and the window's close button mark onboarding
/// done (via the willClose observer), so the wizard never reappears once dismissed.
@MainActor
final class OnboardingController {
    private let store: SettingsStore
    private let lister: any ModelListing
    private let engine: any EngineProviding
    private let modelManager: any ModelManaging
    private let appState: AppState
    private let onOpenAccessibility: () -> Void
    private let onRecheckAccessibility: () -> Void

    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?

    init(
        store: SettingsStore,
        lister: any ModelListing,
        engine: any EngineProviding,
        modelManager: any ModelManaging,
        appState: AppState,
        onOpenAccessibility: @escaping () -> Void,
        onRecheckAccessibility: @escaping () -> Void
    ) {
        self.store = store
        self.lister = lister
        self.engine = engine
        self.modelManager = modelManager
        self.appState = appState
        self.onOpenAccessibility = onOpenAccessibility
        self.onRecheckAccessibility = onRecheckAccessibility
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = OnboardingView(
            store: store,
            lister: lister,
            engine: engine,
            modelManager: modelManager,
            appState: appState,
            onOpenAccessibility: onOpenAccessibility,
            onRecheckAccessibility: onRecheckAccessibility,
            onFinish: { [weak self] in self?.window?.close() }
        )

        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Witaj w Glosso"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.center()

        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.store.hasCompletedOnboarding = true
                if let observer = self.closeObserver {
                    NotificationCenter.default.removeObserver(observer)
                }
                self.closeObserver = nil
                self.window = nil
            }
        }

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
