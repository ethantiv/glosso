import SwiftUI
import AppKit

@main
struct TranslatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Translator", systemImage: "character.bubble") {
            if appDelegate.appState.listening {
                Text("Nasłuch aktywny — podwójne ⌘C tłumaczy zaznaczenie")
            } else if appDelegate.appState.accessibilityGranted {
                Text("Dostępność OK, ale nasłuch nie wystartował.")
                Button("Sprawdź ponownie") {
                    appDelegate.recheckAccessibility()
                }
            } else {
                Text("Brak uprawnienia Dostępność (Accessibility)")
                Button("Otwórz Ustawienia → Prywatność → Dostępność") {
                    appDelegate.openAccessibilitySettings()
                }
                Button("Sprawdź ponownie") {
                    appDelegate.recheckAccessibility()
                }
            }
            Divider()
            SettingsLink { Text("Ustawienia…") }
            Button("Zakończ") { NSApplication.shared.terminate(nil) }
        }

        Settings {
            SettingsView(store: appDelegate.settings, lister: appDelegate.modelLister)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    let settings = SettingsStore()
    let modelLister = OllamaModelLister()
    // Injectable so tests can drive the granted↔revoked transitions in
    // recheckAccessibility() with a fake; production keeps the real AXChecker.
    var ax: any AccessibilityAuthorizing = AXChecker()
    var coordinator: AppCoordinator?
    private var activationObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }

        appState.accessibilityGranted = ax.isTrusted
        if !ax.isTrusted {
            ax.requestAccess(prompt: true)
        }

        let reader = SystemPasteboardReader()
        let coordinator = AppCoordinator(
            llm: OllamaClient(),
            monitor: GlobalHotkeyMonitor(changeCountProvider: { reader.currentChangeCount }),
            reader: reader,
            axReader: AXSelectionReader(),
            popup: TranslationPopupController(),
            settings: settings
        )
        appState.listening = coordinator.start()
        self.coordinator = coordinator

        // Accessibility can be revoked while we run; re-check whenever an app
        // activates so the menu stops claiming "Nasłuch aktywny" when it isn't.
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.recheckAccessibility() }
        }
    }

    func openAccessibilitySettings() {
        ax.openSystemSettings()
    }

    func recheckAccessibility() {
        appState.accessibilityGranted = ax.isTrusted
        if ax.isTrusted {
            if appState.listening == false {
                appState.listening = coordinator?.start() ?? false
            }
        } else if appState.listening {
            coordinator?.stop()
            appState.listening = false
        }
    }
}
