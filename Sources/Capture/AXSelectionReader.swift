import ApplicationServices

@MainActor
final class AXSelectionReader: AXSelectionReading {
    func selectedText() -> String? {
        // kAXFocusedUIElementAttribute/kAXSelectedTextAttribute are C globals
        // Swift 6 treats as non-Sendable; their values are exactly these strings,
        // so use the literals to avoid the warning — same trick as AXChecker.
        let systemWide = AXUIElementCreateSystemWide()
        // These copies are synchronous Mach IPC on the main actor; against a hung
        // target the per-process default (~6s, twice) would freeze the menu bar,
        // popup and hotkey monitor. Cap the worst case to a couple hundred ms.
        AXUIElementSetMessagingTimeout(systemWide, 0.2)
        guard let focused = copyAttribute(systemWide, "AXFocusedUIElement"),
              CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.2)
        guard let value = copyAttribute(element, "AXSelectedText"),
              let text = value as? String else { return nil }
        return text
    }

    private func copyAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }
}
