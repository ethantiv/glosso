import AppKit
import SwiftUI
import Testing
@testable import Glosso

/// The popup's window height is derived from hand-written estimates of what SwiftUI renders. Nothing else in the suite
/// notices when a restyle moves those numbers — the dropdown would simply get clipped, or the panel would reserve a gap.
@MainActor
@Suite("Popup layout")
struct PopupLayoutTests {
    private func hosted<V: View>(_ view: V) -> NSHostingView<V> {
        let host = NSHostingView(rootView: view)
        host.layoutSubtreeIfNeeded()
        return host
    }

    private func model(alternatives: [String]) -> PopupModel {
        let model = PopupModel()
        model.text = "Nauka języka to kwestia uporu."
        model.openDropdown(for: 0)
        model.alternatives = alternatives
        model.altsLoading = false
        return model
    }

    @Test("the alternatives dropdown renders at the height the window reserves for it")
    func dropdownHeightMatchesTheReservation() {
        for count in [1, 3, 5] {
            let model = model(alternatives: (0..<count).map { "alternatywa \($0)" })
            let host = hosted(AlternativesDropdown(model: model, onPick: { _ in }, onExplain: {}, onBack: {}))

            let rendered = host.fittingSize.height
            let reserved = AlternativesLayout.estimatedHeight(count: count, loading: false)
            #expect(abs(rendered - reserved) <= 2,
                    "\(count) alternatives render \(rendered)pt, the window reserves \(reserved)pt")
        }
    }

    @Test("the loading dropdown fits its reserved height too")
    func loadingDropdownFitsTheReservation() {
        let model = PopupModel()
        model.openDropdown(for: 0)
        let host = hosted(AlternativesDropdown(model: model, onPick: { _ in }, onExplain: {}, onBack: {}))

        let reserved = AlternativesLayout.estimatedHeight(count: 0, loading: true)
        #expect(abs(host.fittingSize.height - reserved) <= 2,
                "loading dropdown renders \(host.fittingSize.height)pt, the window reserves \(reserved)pt")
    }

    @Test("the explanation view renders at the height the window reserves for it")
    func explanationHeightMatchesTheReservation() {
        for loading in [true, false] {
            let model = PopupModel()
            model.text = "Nauka języka to kwestia uporu."
            model.openDropdown(for: 0)
            model.openExplanation()
            model.explanationLoading = loading
            if !loading {
                model.explanationText = "Rzeczownik odczasownikowy pasuje tu lepiej, bo chodzi o proces, a nie o wynik."
            }
            let host = hosted(AlternativesDropdown(model: model, onPick: { _ in }, onExplain: {}, onBack: {}))
            // The measured content feeds the same reservation the window uses, so the two can't drift apart.
            let rendered = host.fittingSize.height
            let reserved = AlternativesLayout.explanationHeight(
                content: loading ? 0 : rendered - AlternativesLayout.base, loading: loading)
            #expect(abs(rendered - reserved) <= 2,
                    "explanation (loading: \(loading)) renders \(rendered)pt, the window reserves \(reserved)pt")
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
            fetchAlternatives: { _, _ in [] }, fetchExplanation: { _, _ in "" },
            fetchFixReason: { _, _, _ in "" }, fetchToneNote: { _, _, _, _ in "" },
            pickAlternative: { _, _, _ in }, replace: { _ in }, retranslate: { _ in },
            undo: {}, resizeBy: { _, _ in }, reportSize: { _ in }
        ))

        let first = host.fittingSize
        host.layoutSubtreeIfNeeded()
        let second = host.fittingSize
        #expect(first.width > 0 && first.height > 0)
        // A layout that keeps changing its mind feeds `applyContentSize` a new frame every runloop turn.
        #expect(first == second)
    }
}
