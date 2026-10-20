import CoreGraphics
import Testing
@testable import PerchApp

@Suite struct PointerTrackerTests {
    private let region = CGRect(x: 100, y: 950, width: 186, height: 32)

    @Test func entryExitAndUnchangedPositions() {
        var tracker = PointerTracker()
        #expect(!tracker.isInside)
        #expect(tracker.update(location: CGPoint(x: 0, y: 0), region: region) == nil)
        #expect(!tracker.isInside)
        #expect(tracker.update(location: CGPoint(x: 193, y: 966), region: region) == .pointerEntered)
        #expect(tracker.isInside)
        #expect(tracker.update(location: CGPoint(x: 200, y: 970), region: region) == nil)
        #expect(tracker.isInside)
        #expect(tracker.update(location: CGPoint(x: 0, y: 0), region: region) == .pointerExited)
        #expect(!tracker.isInside)
        #expect(tracker.update(location: CGPoint(x: 0, y: 0), region: region) == nil)
    }

    @Test(arguments: [(100, 966), (286, 966), (193, 950), (193, 982),
                      (100, 950), (100, 982), (286, 950), (286, 982)])
    func allEdgesAndCornersAreInside(_ x: Int, _ y: Int) {
        let point = CGPoint(x: CGFloat(x), y: CGFloat(y))
        var tracker = PointerTracker()
        #expect(tracker.update(location: point, region: region) == .pointerEntered)
        #expect(tracker.isInside)
        #expect(tracker.update(location: point, region: region) == nil)
        #expect(PointerTracker.click(at: point, region: region, expanded: false) == .clicked)
        #expect(PointerTracker.click(at: point, region: region, expanded: true) == .clicked)
    }

    @Test(arguments: [(99.5, 966.0), (286.5, 966.0), (193.0, 949.5), (193.0, 982.5)])
    func pointsJustOutsideEveryEdgeAreOutside(_ x: Double, _ y: Double) {
        let point = CGPoint(x: CGFloat(x), y: CGFloat(y))
        var tracker = PointerTracker()
        #expect(tracker.update(location: CGPoint(x: 193, y: 966), region: region) == .pointerEntered)
        #expect(tracker.update(location: point, region: region) == .pointerExited)
        #expect(!tracker.isInside)
        #expect(PointerTracker.click(at: point, region: region, expanded: true) == .clickedOutside)
        #expect(PointerTracker.click(at: point, region: region, expanded: false) == nil)
    }

    @Test func stationaryPointEntersAndExitsWhenRegionGrowsAndShrinks() {
        let point = CGPoint(x: 193, y: 940)
        let expanded = CGRect(x: 0, y: 700, width: 400, height: 282)
        var tracker = PointerTracker()
        #expect(tracker.update(location: point, region: region) == nil)
        #expect(tracker.update(location: point, region: expanded) == .pointerEntered)
        #expect(tracker.isInside)
        #expect(tracker.update(location: point, region: expanded) == nil)
        #expect(tracker.update(location: point, region: region) == .pointerExited)
        #expect(!tracker.isInside)
    }

    @Test func stationaryPointExitsAndEntersWhenRegionMoves() {
        let point = CGPoint(x: 193, y: 966)
        let shifted = region.offsetBy(dx: 400, dy: 0)
        var tracker = PointerTracker()
        #expect(tracker.update(location: point, region: region) == .pointerEntered)
        #expect(tracker.update(location: point, region: shifted) == .pointerExited)
        #expect(!tracker.isInside)
        #expect(tracker.update(location: point, region: region) == .pointerEntered)
        #expect(tracker.isInside)
    }

    @Test(arguments: [false, true])
    func interiorClickIsClickedForBothSurfaces(_ expanded: Bool) {
        #expect(PointerTracker.click(at: CGPoint(x: 193, y: 966), region: region, expanded: expanded) == .clicked)
    }
}
