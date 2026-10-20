import CoreGraphics

/// Turns raw screen-space mouse positions into presentation events.
/// Regions are closed: a pointer pinned to the screen's top edge (y == maxY) is inside.
struct PointerTracker {
    private(set) var isInside = false

    mutating func update(location: CGPoint, region: CGRect) -> PresentationEvent? {
        let inside = Self.contains(region, location)
        defer { isInside = inside }
        guard inside != isInside else { return nil }
        return inside ? .pointerEntered : .pointerExited
    }

    static func click(at location: CGPoint, region: CGRect, expanded: Bool) -> PresentationEvent? {
        if contains(region, location) { return .clicked }
        return expanded ? .clickedOutside : nil
    }

    private static func contains(_ rect: CGRect, _ point: CGPoint) -> Bool {
        point.x >= rect.minX && point.x <= rect.maxX && point.y >= rect.minY && point.y <= rect.maxY
    }
}
