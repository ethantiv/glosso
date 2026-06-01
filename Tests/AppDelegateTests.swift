import Foundation
import Testing
@testable import TranslatorMenuBar

@MainActor
@Suite struct AppDelegateTests {
    private func makeDelegate(trusted: Bool) -> (AppDelegate, FakeAccessibilityAuthorizing) {
        let delegate = AppDelegate()
        let ax = FakeAccessibilityAuthorizing(isTrusted: trusted)
        delegate.ax = ax
        delegate.coordinator = AppCoordinator(
            llm: FakeLLMClient(),
            monitor: FakeHotkeyMonitor(),
            reader: FakePasteboardReader(),
            popup: FakePopup()
        )
        return (delegate, ax)
    }

    // recheckAccessibility must START listening when access becomes granted —
    // flipping this branch (start on revoked) would otherwise pass unnoticed.
    @Test func recheckStartsListeningWhenAccessGranted() {
        let (delegate, ax) = makeDelegate(trusted: false)
        delegate.appState.listening = false
        ax.isTrusted = true

        delegate.recheckAccessibility()

        #expect(delegate.appState.accessibilityGranted == true)
        #expect(delegate.appState.listening == true)
    }

    // …and STOP listening when access is revoked, so the menu stops claiming
    // "Nasłuch aktywny" once the hotkey monitor can no longer run.
    @Test func recheckStopsListeningWhenAccessRevoked() {
        let (delegate, ax) = makeDelegate(trusted: true)
        delegate.appState.listening = true
        ax.isTrusted = false

        delegate.recheckAccessibility()

        #expect(delegate.appState.accessibilityGranted == false)
        #expect(delegate.appState.listening == false)
    }
}
