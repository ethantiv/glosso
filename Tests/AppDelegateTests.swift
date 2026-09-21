import Foundation
import Testing
@testable import Glosso

@MainActor
@Suite struct AppDelegateTests {
    private func makeDelegate(trusted: Bool) -> (AppDelegate, FakeAccessibilityAuthorizing) {
        let delegate = AppDelegate(settings: SettingsStore(defaults: TestDefaults(), loginItem: FakeLoginItem()))
        let ax = FakeAccessibilityAuthorizing(isTrusted: trusted)
        delegate.ax = ax
        delegate.coordinator = AppCoordinator(
            llm: FakeLLMClient(),
            monitor: FakeHotkeyMonitor(),
            reader: FakePasteboardReader(),
            axReader: FakeAXSelectionReader(),
            popup: FakePopup(),
            settings: delegate.settings
        )
        return (delegate, ax)
    }

    @Test func recheckStartsListeningWhenAccessGranted() {
        let (delegate, ax) = makeDelegate(trusted: false)
        defer { delegate.coordinator?.stop() }
        delegate.appState.listening = false
        ax.isTrusted = true

        delegate.recheckAccessibility()

        #expect(delegate.appState.accessibilityGranted == true)
        #expect(delegate.appState.listening == true)
    }

    @Test func recheckStopsListeningWhenAccessRevoked() {
        let (delegate, ax) = makeDelegate(trusted: true)
        defer { delegate.coordinator?.stop() }
        delegate.appState.listening = true
        ax.isTrusted = false

        delegate.recheckAccessibility()

        #expect(delegate.appState.accessibilityGranted == false)
        #expect(delegate.appState.listening == false)
    }
}
