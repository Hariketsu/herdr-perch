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
    static let expandedWidth: CGFloat = 400
    static let maxExpandedHeight: CGFloat = 420

    let metrics: NotchScreenMetrics

    init(metrics: NotchScreenMetrics) {
        self.metrics = metrics
    }

    var hasNotch: Bool { fatalError("unimplemented") }
    var centerWidth: CGFloat { fatalError("unimplemented") }
    var bandHeight: CGFloat { fatalError("unimplemented") }
    func collapsedSize(wingWidth: CGFloat) -> CGSize { fatalError("unimplemented") }
    func expandedSize(contentHeight: CGFloat, wingWidth: CGFloat) -> CGSize { fatalError("unimplemented") }
    func panelFrame(size: CGSize) -> CGRect { fatalError("unimplemented") }
}
