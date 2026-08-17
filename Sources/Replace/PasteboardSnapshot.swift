import AppKit

/// Whole-pasteboard save/restore: a string-only round trip destroys images, files and RTF the user had copied.
@MainActor
enum PasteboardSnapshot {
    /// Copies every item's every flavor — an NSPasteboardItem can't be re-written once its pasteboard changes.
    static func capture(_ pasteboard: NSPasteboard = .general) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
    }

    static func restore(_ items: [NSPasteboardItem], to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        pasteboard.writeObjects(items)
    }
}
