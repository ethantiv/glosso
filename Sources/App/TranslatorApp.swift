import SwiftUI
import AppKit

@main
struct TranslatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Translator", systemImage: "character.bubble") {
            if appDelegate.appState.accessibilityGranted {
                Text("Nasłuch aktywny — podwójne ⌘C tłumaczy zaznaczenie")
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
            Button("Zakończ") { NSApplication.shared.terminate(nil) }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private let ax = AXChecker()
    private var coordinator: AppCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }

        appState.accessibilityGranted = ax.isTrusted
        if !ax.isTrusted {
            ax.requestAccess(prompt: true)
        }

        let coordinator = AppCoordinator(
            llm: OllamaClient(),
            monitor: GlobalHotkeyMonitor(),
            reader: SystemPasteboardReader(),
            popup: TranslationPopupController(),
            ax: ax
        )
        appState.listening = coordinator.start()
        self.coordinator = coordinator
    }

    func openAccessibilitySettings() {
        ax.openSystemSettings()
    }

    func recheckAccessibility() {
        appState.accessibilityGranted = ax.isTrusted
        if ax.isTrusted, appState.listening == false {
            appState.listening = coordinator?.start() ?? false
        }
    }
}
