import AppKit

/// Which side of the bilingual edition the reader shows. Swift owns it; the page only applies what it's told.
enum ReaderMode: Int, CaseIterable, Sendable {
    case translated = 0
    case original = 1

    var jsValue: String { self == .original ? "original" : "translated" }

    init(segmentIndex: Int) {
        self = ReaderMode(rawValue: segmentIndex) ?? .translated
    }
}

extension NSToolbarItem.Identifier {
    static let glossoRefresh = NSToolbarItem.Identifier("glosso.refresh")
    static let glossoMode = NSToolbarItem.Identifier("glosso.mode")
    static let glossoChat = NSToolbarItem.Identifier("glosso.chat")
}

/// `ReaderController` is not an `NSObject`, so toolbar target/action goes through a proxy — the same shape as
/// `ReaderScriptMessageProxy` next door.
@MainActor
final class ReaderToolbarProxy: NSObject, NSToolbarDelegate {
    /// One leading flexible space, then the group: a unified toolbar shares its row with the title and subtitle, so
    /// spreading the items across the whole width pushes the last one into the overflow menu.
    static let itemIdentifiers: [NSToolbarItem.Identifier] =
        [.flexibleSpace, .glossoRefresh, .glossoMode, .glossoChat]

    private weak var controller: ReaderController?
    private(set) var modeControl: NSSegmentedControl?
    private(set) var refreshItem: NSToolbarItem?
    private(set) var chatItem: NSToolbarItem?

    init(controller: ReaderController) {
        self.controller = controller
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Self.itemIdentifiers
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Self.itemIdentifiers
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch identifier {
        case .glossoRefresh:
            let item = button(identifier, symbol: "arrow.trianglehead.clockwise",
                              label: loc("Przetłumacz ponownie", "Translate again"),
                              action: #selector(refresh))
            refreshItem = item
            return item
        case .glossoMode:
            let item = NSToolbarItem(itemIdentifier: identifier)
            let control = NSSegmentedControl(
                labels: [loc("Tłumaczenie", "Translation"), loc("Oryginał", "Original")],
                trackingMode: .selectOne, target: self, action: #selector(modeChanged))
            control.selectedSegment = ReaderMode.translated.rawValue
            item.view = control
            item.label = loc("Widok", "View")
            item.paletteLabel = item.label
            item.toolTip = loc("Przełącz oryginał i tłumaczenie", "Switch between original and translation")
            modeControl = control
            return item
        case .glossoChat:
            let item = button(identifier, symbol: "bubble.left.and.text.bubble.right",
                              label: loc("Zapytaj artykuł", "Ask the article"),
                              action: #selector(toggleChat))
            chatItem = item
            return item
        default:
            return nil
        }
    }

    private func button(
        _ identifier: NSToolbarItem.Identifier, symbol: String, label: String, action: Selector
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        item.target = self
        item.action = action
        item.isBordered = true
        return item
    }

    @objc private func refresh() {
        controller?.refreshCurrentArticle()
    }

    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        controller?.setMode(ReaderMode(segmentIndex: sender.selectedSegment))
    }

    @objc private func toggleChat() {
        controller?.toggleChatPanel()
    }
}
