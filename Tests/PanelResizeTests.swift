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
}
