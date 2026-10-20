import SwiftUI

/// The notch silhouette from vibeisland.app's demo: rounded bottom corners
/// plus fixed 6pt concave "shoulders" just outside the rect that blend into
/// the menu bar. Only the bottom radius changes between states (10 → 14).
struct NotchShape: Shape {
    var bottomRadius: CGFloat
    static let shoulder: CGFloat = 6

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let s = Self.shoulder
        let r = min(bottomRadius, rect.width / 2, rect.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX - s, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX + s, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + s), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + s))
        path.addQuadCurve(to: CGPoint(x: rect.minX - s, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// A layer's fade, as in the Vibe Island app: opacity only, starting with the
/// shape on the first frame. No blur or scale — scaling content while the shape
/// also clips it read as a jitter.
///
/// The animation is scoped to the opacity. A plain `.animation(_:value:)` here
/// would also take over the layer's position, which the parent's spring moves:
/// two curves fighting made the ears slide sideways while collapsing.
struct LayerFade: ViewModifier {
    var active: Bool
    var fadeIn: Double = 0.15
    var fadeOut: Double = 0.1
    var fadeInDelay: Double = 0

    func body(content: Content) -> some View {
        let animation = active ? Animation.easeOut(duration: fadeIn).delay(fadeInDelay) : .easeOut(duration: fadeOut)
        return content.animation(animation) { $0.opacity(active ? 1 : 0) }
    }
}
