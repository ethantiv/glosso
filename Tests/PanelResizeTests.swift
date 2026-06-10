import CoreGraphics
import Testing
@testable import Glosso

@Suite("PanelResize")
struct PanelResizeTests {
    @Test("dragging the grip right and down grows the content delta")
    func growsWithDrag() {
        let delta = PanelResize.delta(
            startDelta: CGSize(width: 40, height: 20),
            translation: CGSize(width: 50, height: 30)
        )
        #expect(delta == CGSize(width: 90, height: 50))
    }

    @Test("shrinking clamps at zero so the panes never go below their design size")
    func clampsAtZero() {
        let delta = PanelResize.delta(
            startDelta: CGSize(width: 40, height: 20),
            translation: CGSize(width: -500, height: -500)
        )
        #expect(delta == .zero)
    }

    @Test("delta is rounded to whole points — fractional content widths destabilize the window's ideal-size pipeline")
    func roundsToWholePoints() {
        let delta = PanelResize.delta(
            startDelta: .zero,
            translation: CGSize(width: 10.4, height: 7.6)
        )
        #expect(delta == CGSize(width: 10, height: 8))
    }
}
