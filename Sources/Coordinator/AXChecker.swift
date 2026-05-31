import AppKit
import ApplicationServices

@MainActor
final class AXChecker: AccessibilityAuthorizing {
    var isTrusted: Bool { AXIsProcessTrusted() }

    func requestAccess(prompt: Bool) {
        // kAXTrustedCheckOptionPrompt is a C global Swift 6 treats as non-Sendable;
        // its value is exactly this string, so use the literal to avoid the warning.
        let key = "AXTrustedCheckOptionPrompt"
        _ = AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    func openSystemSettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        else { return }
        NSWorkspace.shared.open(url)
    }
}
