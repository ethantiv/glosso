import SwiftUI
import AppKit

@main
struct TranslatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Translator", systemImage: "character.bubble") {
            Button("Przetłumacz przykład (demo)") {
                appDelegate.coordinator?.translate("Cześć, świecie")
            }
            Divider()
            Button("Zakończ") { NSApplication.shared.terminate(nil) }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var coordinator: AppCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }
        let coordinator = AppCoordinator(
            llm: StubLLMClient(),
            monitor: StubHotkeyMonitor(),
            reader: StubPasteboardReader(),
            popup: StubPopupPresenter(),
            ax: StubAccessibilityAuthorizer()
        )
        coordinator.start()
        self.coordinator = coordinator
    }
}
