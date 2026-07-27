import ApplicationServices

@MainActor
final class AXSelectionReader: AXSelectionReading {
    func selectedText() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
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
