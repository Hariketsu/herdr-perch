import AppKit

struct NotchScreenMetrics: Equatable {
    var frame: CGRect
    var safeAreaTop: CGFloat
    var auxiliaryTopLeftArea: CGRect?
    var auxiliaryTopRightArea: CGRect?

    init(frame: CGRect, safeAreaTop: CGFloat, auxiliaryTopLeftArea: CGRect? = nil, auxiliaryTopRightArea: CGRect? = nil) {
        self.frame = frame
        self.safeAreaTop = safeAreaTop
        self.auxiliaryTopLeftArea = auxiliaryTopLeftArea
        self.auxiliaryTopRightArea = auxiliaryTopRightArea
    }

    init(screen: NSScreen) {
        self.init(
            frame: screen.frame,
            safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea,
            auxiliaryTopRightArea: screen.auxiliaryTopRightArea)
    }
}

struct NotchGeometry: Equatable {
    static let fallbackBandHeight: CGFloat = 32
    static let floatingCenterWidth: CGFloat = 190
    static let expandedWidth: CGFloat = 640
    static let maxExpandedHeight: CGFloat = 560

    let metrics: NotchScreenMetrics

    init(metrics: NotchScreenMetrics) {
        self.metrics = metrics
    }

    /// Physical notch width when the screen has one we trust (NotchAgent's 80…400pt bound).
    private var notchWidth: CGFloat? {
        guard metrics.safeAreaTop > 0,
              let left = metrics.auxiliaryTopLeftArea,
              let right = metrics.auxiliaryTopRightArea
        else { return nil }
        let gap = right.minX - left.maxX
        return gap > 80 && gap < 400 ? gap : nil
    }

    var hasNotch: Bool { notchWidth != nil }
    var centerWidth: CGFloat { notchWidth ?? Self.floatingCenterWidth }
    var bandHeight: CGFloat { hasNotch ? metrics.safeAreaTop : Self.fallbackBandHeight }

    func collapsedSize(wingWidth: CGFloat) -> CGSize {
        CGSize(width: centerWidth + 2 * wingWidth, height: bandHeight)
    }

    func expandedSize(contentHeight: CGFloat, wingWidth: CGFloat) -> CGSize {
        let collapsed = collapsedSize(wingWidth: wingWidth)
        let width = max(collapsed.width, min(Self.expandedWidth, metrics.frame.width - 24))
        let height = min(bandHeight + contentHeight, Self.maxExpandedHeight, metrics.frame.height * 0.72)
        return CGSize(width: width, height: (height / 2).rounded() * 2)
    }

    func panelFrame(size: CGSize) -> CGRect {
        CGRect(x: metrics.frame.midX - size.width / 2, y: metrics.frame.maxY - size.height,
               width: size.width, height: size.height)
    }
}

extension NotchGeometry {
    static let maxWingWidth: CGFloat = 140
    static let canvasMargin: CGFloat = 36

    /// Fixed panel size: large enough for every collapsed and expanded shape.
    var canvasSize: CGSize {
        let width = max(min(Self.expandedWidth, metrics.frame.width - 24), centerWidth + 2 * Self.maxWingWidth)
        let height = min(Self.maxExpandedHeight, metrics.frame.height * 0.72)
        return CGSize(width: width + 2 * Self.canvasMargin, height: height + Self.canvasMargin)
    }

    var canvasFrame: CGRect { panelFrame(size: canvasSize) }
}
