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

    @Test(arguments: [(99.0, 124.0), (99.8, 124.0), (100.0, 126.0), (100.2, 126.0)])
    func noNotchUsesMenuBarHeightAndRoundsOpenHeights(_ content: Double, _ expected: Double) {
        let geometry = NotchGeometry(metrics: NotchScreenMetrics(frame: screenFrame, safeAreaTop: 0, menuBarHeight: 25))
        #expect(!geometry.hasNotch)
        #expect(geometry.bandHeight == 25)
        #expect(geometry.collapsedSize(wingWidth: 40).height == 25)
        #expect(geometry.expandedSize(contentHeight: CGFloat(content), wingWidth: 40).height == CGFloat(expected))
        #expect(geometry.peekSize(contentHeight: CGFloat(content), wingWidth: 40).height == CGFloat(expected))
    }

    @Test func autoHiddenMenuBarFallsBackTo32Points() {
        let geometry = NotchGeometry(metrics: NotchScreenMetrics(frame: screenFrame, safeAreaTop: 0, menuBarHeight: 0))
        #expect(!geometry.hasNotch)
        #expect(geometry.bandHeight == 32)
        #expect(geometry.collapsedSize(wingWidth: 40).height == 32)
        #expect(geometry.expandedSize(contentHeight: 100, wingWidth: 40).height == 132)
        #expect(geometry.peekSize(contentHeight: 100, wingWidth: 40).height == 132)
    }

    @Test func physicalNotchHeightTakesPrecedenceOverMenuBarHeight() {
        var metrics = notchedMetrics(safeAreaTop: 32)
        metrics.menuBarHeight = 24
        let geometry = NotchGeometry(metrics: metrics)
        #expect(geometry.hasNotch)
        #expect(geometry.bandHeight == 32)
        #expect(geometry.collapsedSize(wingWidth: 40).height == 32)
        #expect(geometry.expandedSize(contentHeight: 100, wingWidth: 40).height == 132)
        #expect(geometry.peekSize(contentHeight: 100, wingWidth: 40).height == 132)
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
        #expect(NotchGeometry.expandedWidth == 640)
        #expect(geometry.expandedSize(contentHeight: 100, wingWidth: 40).width == NotchGeometry.expandedWidth)
        let narrow = NotchGeometry(metrics: NotchScreenMetrics(frame: CGRect(x: 0, y: 0, width: 350, height: 600), safeAreaTop: 0))
        // The 470pt collapsed span exceeds this screen's 326pt expanded-width cap.
        #expect(narrow.expandedSize(contentHeight: 100, wingWidth: NotchGeometry.maxWingWidth).width == 470)
    }

    @Test func expandedWidthCapsAtScreenWidthMinusTwentyFour() {
        let geometry = NotchGeometry(metrics: NotchScreenMetrics(frame: CGRect(x: 0, y: 0, width: 350, height: 600), safeAreaTop: 0))
        #expect(geometry.expandedSize(contentHeight: 100, wingWidth: 40).width == 326)
    }

    @Test func expandedHeightFollowsContentAndCapsAtConfiguredMaximum() {
        let geometry = NotchGeometry(metrics: notchedMetrics())
        #expect(geometry.expandedSize(contentHeight: 0, wingWidth: 40).height == 32)
        #expect(geometry.expandedSize(contentHeight: 100, wingWidth: 40).height == 132)
        #expect(NotchGeometry.maxExpandedHeight == 560)
        #expect(geometry.expandedSize(contentHeight: 1000, wingWidth: 40).height == NotchGeometry.maxExpandedHeight)
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
        #expect(geometry.panelFrame(size: CGSize(width: NotchGeometry.expandedWidth, height: 232)) ==
                CGRect(x: -1164, y: 870, width: NotchGeometry.expandedWidth, height: 232))
        #expect(geometry.panelFrame(size: CGSize(width: 270, height: 32)) == CGRect(x: -979, y: 1070, width: 270, height: 32))
        let primary = NotchGeometry(metrics: notchedMetrics())
        #expect(primary.panelFrame(size: CGSize(width: 266, height: 32)) == CGRect(x: 623, y: 950, width: 266, height: 32))
    }
}

// Fixed-window canvas contract: architecture.md §6.1.
extension NotchGeometryTests {
    @Test func canvasOnNotchedAndUnnotchedScreensIncludesMargins() {
        #expect(NotchGeometry.maxWingWidth == 140)
        #expect(NotchGeometry.canvasMargin == 36)
        let notched = NotchGeometry(metrics: notchedMetrics())
        // Both screens fit the expanded preference, which exceeds the maximum ear span.
        let size = CGSize(width: NotchGeometry.expandedWidth + 2 * NotchGeometry.canvasMargin,
                          height: NotchGeometry.maxExpandedHeight + NotchGeometry.canvasMargin)
        #expect(notched.canvasSize == size)
        #expect(notched.canvasFrame == CGRect(x: 400, y: 386, width: size.width, height: size.height))
        let floating = NotchGeometry(metrics: NotchScreenMetrics(frame: screenFrame, safeAreaTop: 0))
        #expect(floating.canvasSize == size)
        #expect(floating.canvasFrame == CGRect(x: 400, y: 386, width: size.width, height: size.height))
    }

    @Test func canvasCanBeDeterminedByExpandedWidthRatherThanEars() {
        let geometry = NotchGeometry(metrics: notchedMetrics(gap: 100))
        // A 100pt center and two 140pt ears fit within the expanded-width preference.
        #expect(geometry.canvasSize == CGSize(width: NotchGeometry.expandedWidth + 2 * NotchGeometry.canvasMargin,
                                             height: NotchGeometry.maxExpandedHeight + NotchGeometry.canvasMargin))
    }

    @Test func narrowScreenClampsExpandedPreferenceBeforeAddingMargins() {
        var metrics = notchedMetrics(gap: 100)
        metrics.frame = CGRect(x: 0, y: 0, width: 410, height: 500)
        metrics.auxiliaryTopLeftArea = CGRect(x: 0, y: 468, width: 155, height: 32)
        metrics.auxiliaryTopRightArea = CGRect(x: 255, y: 468, width: 155, height: 32)
        let geometry = NotchGeometry(metrics: metrics)
        // The capped preference is 386pt, larger than the 380pt maximum ear span.
        #expect(geometry.canvasSize == CGSize(width: 458, height: 396))
        #expect(geometry.canvasFrame == CGRect(x: -24, y: 104, width: 458, height: 396))
    }

    @Test func maximumEarSpanCanExceedNarrowScreenPreference() {
        let geometry = NotchGeometry(metrics: NotchScreenMetrics(frame: CGRect(x: 0, y: 0, width: 350, height: 500), safeAreaTop: 0))
        // The contract caps the expanded preference, not the final canvas or maximum ear span.
        #expect(geometry.canvasSize == CGSize(width: 542, height: 396))
    }

    @Test func canvasStaysTopCenteredOnScreensWithNonzeroOrigins() {
        let geometry = NotchGeometry(metrics: NotchScreenMetrics(frame: CGRect(x: -1600, y: 120, width: 1512, height: 982), safeAreaTop: 0))
        #expect(geometry.canvasFrame == CGRect(x: -1200, y: 506,
                                              width: NotchGeometry.expandedWidth + 2 * NotchGeometry.canvasMargin,
                                              height: NotchGeometry.maxExpandedHeight + NotchGeometry.canvasMargin))
    }

    @Test func canvasContainsCollapsedAndExpandedPanelFramesAcrossSupportedSizes() {
        var narrow = notchedMetrics(gap: 100)
        narrow.frame = CGRect(x: -350, y: 100, width: 350, height: 500)
        narrow.auxiliaryTopLeftArea = CGRect(x: -350, y: 568, width: 125, height: 32)
        narrow.auxiliaryTopRightArea = CGRect(x: -125, y: 568, width: 125, height: 32)
        let screens = [notchedMetrics(), notchedMetrics(gap: 399), narrow,
                       NotchScreenMetrics(frame: screenFrame, safeAreaTop: 0),
                       NotchScreenMetrics(frame: CGRect(x: 1512, y: -100, width: 350, height: 501), safeAreaTop: 0)]
        for metrics in screens {
            let geometry = NotchGeometry(metrics: metrics)
            let canvas = geometry.canvasFrame
            #expect(canvas.size == geometry.canvasSize)
            #expect(canvas.midX == metrics.frame.midX)
            #expect(canvas.maxY == metrics.frame.maxY)
            for wing: CGFloat in [30, 40, 42, 64, 72, 82, 88, 112, 124, 140] {
                let collapsed = geometry.panelFrame(size: geometry.collapsedSize(wingWidth: wing))
                #expect(canvas.contains(collapsed), "Canvas must contain collapsed frame at wing \(wing)")
                for content: CGFloat in [0, 1, 70.8, 71, 100, 200, 388, 500, 1000] {
                    let expanded = geometry.panelFrame(size: geometry.expandedSize(contentHeight: content, wingWidth: wing))
                    #expect(canvas.contains(expanded), "Canvas must contain expanded frame at wing \(wing), content \(content)")
                }
            }
        }
    }
}

extension NotchGeometryTests {
    @Test func peekWidthUses440AndCapsAtScreenWidthWithoutNarrowingCollapsed() {
        let geometry = NotchGeometry(metrics: notchedMetrics())
        #expect(NotchGeometry.peekWidth == 440)
        #expect(geometry.peekSize(contentHeight: 100, wingWidth: 40).width == 440)
        let narrow = NotchGeometry(metrics: NotchScreenMetrics(frame: CGRect(x: 0, y: 0, width: 350, height: 600), safeAreaTop: 0))
        #expect(narrow.peekSize(contentHeight: 100, wingWidth: 40).width == 326)
        #expect(narrow.peekSize(contentHeight: 100, wingWidth: NotchGeometry.maxWingWidth).width == 470)
    }

    @Test func peekHeightIncludesBandAndCapsAtMaximumOrScreenFraction() {
        let geometry = NotchGeometry(metrics: notchedMetrics())
        #expect(geometry.peekSize(contentHeight: 0, wingWidth: 40).height == 32)
        #expect(geometry.peekSize(contentHeight: 100, wingWidth: 40).height == 132)
        #expect(geometry.peekSize(contentHeight: 1000, wingWidth: 40).height == 560)
        let short = NotchGeometry(metrics: NotchScreenMetrics(frame: CGRect(x: 0, y: 0, width: 1000, height: 500), safeAreaTop: 0))
        #expect(short.peekSize(contentHeight: 1000, wingWidth: 40).height == 360)
    }

    @Test(arguments: [(70.8, 102.0), (71.0, 104.0), (71.2, 104.0)])
    func peekHeightRoundsToNearestEvenValueLikeExpanded(_ content: Double, _ expected: Double) {
        let geometry = NotchGeometry(metrics: notchedMetrics())
        let height = geometry.peekSize(contentHeight: CGFloat(content), wingWidth: 40).height
        #expect(height == CGFloat(expected))
        #expect(height == geometry.expandedSize(contentHeight: CGFloat(content), wingWidth: 40).height)
    }
}
