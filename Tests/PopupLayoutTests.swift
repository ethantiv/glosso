import AppKit
import SwiftUI
import Testing
@testable import Glosso

/// The panel's window size is whatever SwiftUI measures, so a layout that never settles feeds `applyContentSize` a new
/// frame every runloop turn and nothing else in the suite would notice.
@MainActor
@Suite("Popup layout")
struct PopupLayoutTests {
    private func hosted<V: View>(_ view: V) -> NSHostingView<V> {
        let host = NSHostingView(rootView: view)
        host.layoutSubtreeIfNeeded()
        return host
    }

    @Test("the dropdown reports a stable, non-zero ideal size")
    func dropdownIdealSizeIsStable() {
        // Its own window sizes itself from this measurement, per content state — a state that measures to zero would
        // open an invisible window.
        for state in ["alternatives", "loading", "explanation"] {
            let model = PopupModel()
            model.text = "Nauka języka to kwestia uporu."
            model.openDropdown(for: 0)
            switch state {
            case "alternatives":
                model.alternatives = (0..<3).map { "alternatywa \($0)" }
                model.altsLoading = false
            case "explanation":
                model.openExplanation()
                model.explanationLoading = false
                model.explanationText = "Rzeczownik odczasownikowy pasuje tu lepiej, bo chodzi o proces, a nie o wynik."
            default:
                break
            }
            let host = hosted(AlternativesDropdown(model: model, onPick: { _ in }, onExplain: {}, onBack: {}))
            let first = host.fittingSize
            host.layoutSubtreeIfNeeded()
            #expect(first.width > 0 && first.height > 0, "\(state) measures \(first)")
            #expect(first == host.fittingSize, "\(state) measures differently on a second pass")
        }
    }

    @Test("the panel reports a stable, non-zero ideal size")
    func popupIdealSizeIsStable() {
        let model = PopupModel()
        model.sourceText = "Learning a language is mostly a matter of stubbornness."
        model.text = "Nauka języka to w dużej mierze kwestia uporu."
        model.phase = .done
        let host = hosted(PopupView(
            model: model,
            close: {}, selectFormality: { _ in }, selectAction: { _ in },
            fetchAlternatives: { _, _ in [] },
            fetchFixReason: { _, _, _ in "" }, fetchToneNote: { _, _, _, _ in "" },
            replace: { _ in }, retranslate: { _ in },
            undo: {}, resizeBy: { _, _ in }, reportSize: { _ in }, reportDropdownAnchor: { _ in }
        ))

        let first = host.fittingSize
        host.layoutSubtreeIfNeeded()
        let second = host.fittingSize
        #expect(first.width > 0 && first.height > 0)
        // A layout that keeps changing its mind feeds `applyContentSize` a new frame every runloop turn.
        #expect(first == second)
    }
}
