import CoreGraphics
import Testing
@testable import TranslatorMenuBar

@Suite("PanelPositioning")
struct PanelPositioningTests {
    private let panelSize = CGSize(width: 360, height: 140)
    private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    private func panelRect(topLeft: CGPoint, size: CGSize) -> CGRect {
        // top-left y is the top edge; the bottom-left origin sits height below it.
        CGRect(
            x: topLeft.x,
            y: topLeft.y - size.height,
            width: size.width,
            height: size.height
        )
    }

    private func contains(_ outer: CGRect, _ inner: CGRect) -> Bool {
        inner.minX >= outer.minX
            && inner.maxX <= outer.maxX
            && inner.minY >= outer.minY
            && inner.maxY <= outer.maxY
    }

    @Test("Cursor centered: panel fits and anchors near the cursor")
    func centered() {
        let mouse = CGPoint(x: 960, y: 540)
        let topLeft = PanelPositioning.topLeft(
            forMouse: mouse,
            panelSize: panelSize,
            screenFrame: screen
        )
        let rect = panelRect(topLeft: topLeft, size: panelSize)

        #expect(contains(screen, rect))
        #expect(topLeft.x > mouse.x)
        #expect(topLeft.y == mouse.y)
    }

    @Test("Cursor near right edge: panel shifts left, right edge inside bound")
    func rightEdge() {
        let mouse = CGPoint(x: 1910, y: 540)
        let topLeft = PanelPositioning.topLeft(
            forMouse: mouse,
            panelSize: panelSize,
            screenFrame: screen
        )
        let rect = panelRect(topLeft: topLeft, size: panelSize)

        #expect(contains(screen, rect))
        #expect(rect.maxX <= screen.maxX)
        #expect(topLeft.x < mouse.x)
    }

    @Test("Cursor near bottom edge: panel stays above the bottom bound")
    func bottomEdge() {
        let mouse = CGPoint(x: 960, y: 5)
        let topLeft = PanelPositioning.topLeft(
            forMouse: mouse,
            panelSize: panelSize,
            screenFrame: screen
        )
        let rect = panelRect(topLeft: topLeft, size: panelSize)

        #expect(contains(screen, rect))
        #expect(rect.minY >= screen.minY)
    }

    @Test("Cursor near top edge: panel stays below the top bound")
    func topEdge() {
        let mouse = CGPoint(x: 960, y: 1075)
        let topLeft = PanelPositioning.topLeft(
            forMouse: mouse,
            panelSize: panelSize,
            screenFrame: screen
        )
        let rect = panelRect(topLeft: topLeft, size: panelSize)

        #expect(contains(screen, rect))
        #expect(topLeft.y <= screen.maxY)
    }
}
