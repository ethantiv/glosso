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

    func snapshot() -> SelectionSnapshot? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.2)
        guard let focused = copyAttribute(system, kAXFocusedUIElementAttribute),
              CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.2)
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success,
              let text = copyAttribute(element, kAXSelectedTextAttribute) as? String,
              !text.isEmpty,
              let value = copyAttribute(element, kAXSelectedTextRangeAttribute),
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range),
              range.location >= 0, range.length > 0 else { return nil }
        return SelectionSnapshot(pid: pid, element: element,
                                 range: NSRange(location: range.location, length: range.length), text: text)
    }

    private func copyAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }
}
