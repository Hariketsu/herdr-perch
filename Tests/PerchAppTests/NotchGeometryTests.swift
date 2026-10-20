// Derived from NotchAgent Tests/NotchAppTests/NotchGeometryTests.swift (Apache-2.0)
// https://github.com/ykushch/notchagent — Copyright Yuri Kushch
// Modified by Herdr Perch.
import CoreGraphics
import Testing
@testable import PerchApp

@Suite struct NotchGeometryTests {
    private let screenFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)

    private func notchedMetrics(gap: CGFloat = 186, safeAreaTop: CGFloat = 32) -> NotchScreenMetrics {
        NotchScreenMetrics(frame: screenFrame, safeAreaTop: safeAreaTop,
                           auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: 663, height: 32),
                           auxiliaryTopRightArea: CGRect(x: 663 + gap, y: 950, width: 1512 - 663 - gap, height: 32))
    }

    @Test func physicalNotchUsesAuxiliaryGapAndSafeAreaHeight() {
        let geometry = NotchGeometry(metrics: notchedMetrics())
        #expect(geometry.hasNotch)
        #expect(geometry.centerWidth == 186)
        #expect(geometry.bandHeight == 32)
        #expect(geometry.collapsedSize(wingWidth: 40) == CGSize(width: 266, height: 32))
        let taller = NotchGeometry(metrics: notchedMetrics(safeAreaTop: 38))
        #expect(taller.bandHeight == 38)
        #expect(taller.collapsedSize(wingWidth: 82) == CGSize(width: 350, height: 38))
    }

    @Test func noNotchUsesFloatingFallback() {
        let geometry = NotchGeometry(metrics: NotchScreenMetrics(frame: screenFrame, safeAreaTop: 0))
        #expect(!geometry.hasNotch)
        #expect(geometry.centerWidth == 190)
        #expect(geometry.bandHeight == 32)
        #expect(geometry.collapsedSize(wingWidth: 40) == CGSize(width: 270, height: 32))
    }

    @Test(arguments: [0, 79, 80, 400, 401])
    func invalidGapFallsBack(_ gap: Int) {
        let geometry = NotchGeometry(metrics: notchedMetrics(gap: CGFloat(gap), safeAreaTop: 38))
        #expect(!geometry.hasNotch)
        #expect(geometry.centerWidth == 190)
        #expect(geometry.bandHeight == 32)
    }

    @Test(arguments: [81, 399])
    func gapInsideOpenBoundsIsAccepted(_ gap: Int) {
        let geometry = NotchGeometry(metrics: notchedMetrics(gap: CGFloat(gap)))
        #expect(geometry.hasNotch)
        #expect(geometry.centerWidth == CGFloat(gap))
    }

    @Test func bothAuxiliaryAreasAndPositiveSafeAreaAreRequired() {
        #expect(!NotchGeometry(metrics: notchedMetrics(safeAreaTop: 0)).hasNotch)
        var metrics = notchedMetrics()
        metrics.auxiliaryTopLeftArea = nil
        #expect(!NotchGeometry(metrics: metrics).hasNotch)
        metrics = notchedMetrics()
        metrics.auxiliaryTopRightArea = nil
        #expect(!NotchGeometry(metrics: metrics).hasNotch)
    }

    @Test func expandedWidthUsesPreferredWidthAndNeverNarrowsCollapsedState() {
        let geometry = NotchGeometry(metrics: notchedMetrics())
        #expect(geometry.expandedSize(contentHeight: 100, wingWidth: 40).width == 400)
        #expect(geometry.expandedSize(contentHeight: 100, wingWidth: 150).width == 486)
    }

    @Test func expandedWidthCapsAtScreenWidthMinusTwentyFour() {
        let geometry = NotchGeometry(metrics: NotchScreenMetrics(frame: CGRect(x: 0, y: 0, width: 350, height: 600), safeAreaTop: 0))
        #expect(geometry.expandedSize(contentHeight: 100, wingWidth: 40).width == 326)
    }

    @Test func expandedHeightFollowsContentAndCapsAt420() {
        let geometry = NotchGeometry(metrics: notchedMetrics())
        #expect(geometry.expandedSize(contentHeight: 0, wingWidth: 40).height == 32)
        #expect(geometry.expandedSize(contentHeight: 100, wingWidth: 40).height == 132)
        #expect(geometry.expandedSize(contentHeight: 1000, wingWidth: 40).height == 420)
    }

    @Test func expandedHeightCapsAtSeventyTwoPercentOfScreenHeight() {
        let geometry = NotchGeometry(metrics: NotchScreenMetrics(frame: CGRect(x: 0, y: 0, width: 1000, height: 500), safeAreaTop: 0))
        #expect(geometry.expandedSize(contentHeight: 1000, wingWidth: 40).height == 360)
    }

    @Test(arguments: [(70.8, 102.0), (71.0, 104.0), (71.2, 104.0)])
    func expandedHeightRoundsToNearestEvenValue(_ contentHeight: Double, _ expected: Double) {
        let geometry = NotchGeometry(metrics: notchedMetrics())
        #expect(geometry.expandedSize(contentHeight: CGFloat(contentHeight), wingWidth: 40).height == CGFloat(expected))
    }

    @Test func framesStayTopCenteredIncludingNonzeroScreenOrigins() {
        let geometry = NotchGeometry(metrics: NotchScreenMetrics(frame: CGRect(x: -1600, y: 120, width: 1512, height: 982), safeAreaTop: 0))
        #expect(geometry.panelFrame(size: CGSize(width: 400, height: 232)) == CGRect(x: -1044, y: 870, width: 400, height: 232))
        #expect(geometry.panelFrame(size: CGSize(width: 270, height: 32)) == CGRect(x: -979, y: 1070, width: 270, height: 32))
        let primary = NotchGeometry(metrics: notchedMetrics())
        #expect(primary.panelFrame(size: CGSize(width: 266, height: 32)) == CGRect(x: 623, y: 950, width: 266, height: 32))
    }
}
