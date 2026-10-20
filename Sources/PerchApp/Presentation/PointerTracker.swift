import CoreGraphics

struct PointerTracker {
    private(set) var isInside = false

    mutating func update(location: CGPoint, region: CGRect) -> PresentationEvent? { fatalError("unimplemented") }

    static func click(at location: CGPoint, region: CGRect, expanded: Bool) -> PresentationEvent? {
        fatalError("unimplemented")
    }
}
