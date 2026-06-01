import ApplicationServices

@MainActor
final class AXSelectionReader: AXSelectionReading {
    func selectedText() -> String? {
        // kAXFocusedUIElementAttribute/kAXSelectedTextAttribute are C globals
        // Swift 6 treats as non-Sendable; their values are exactly these strings,
        // so use the literals to avoid the warning — same chwyt as AXChecker.
        let systemWide = AXUIElementCreateSystemWide()
        guard let focused = copyAttribute(systemWide, "AXFocusedUIElement") else { return nil }
        let element = focused as! AXUIElement
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
