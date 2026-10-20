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

/// Crossfade between the collapsed and expanded layers. Both start at once
/// with the shape (a delay left the growing shape empty, or the notch blank
/// mid-collapse), and neither scales: scaling content while the shape also
/// clips it read as a jitter.
struct LayerFade: ViewModifier {
    var active: Bool
    var reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(active ? 1 : 0)
            .animation(.easeOut(duration: active ? 0.2 : 0.15), value: active)
            .blur(radius: active || reduceMotion ? 0 : 3)
            .animation(.easeOut(duration: 0.25), value: active)
    }
}
