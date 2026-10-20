// Derived from open-vibe-island Sources/OpenIslandApp/NotchShape.swift
// https://github.com/Octane0411/open-vibe-island — GPL-3.0
// Modified by Herdr Perch.
import SwiftUI

/// One shape for both states: concave top "shoulders" drawn inside the rect,
/// rounded bottom corners. Both radii animate, so collapsed → expanded reads
/// as the notch itself growing.
struct NotchShape: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    static let collapsed = NotchShape(topCornerRadius: 6, bottomCornerRadius: 10)
    static let expanded = NotchShape(topCornerRadius: 22, bottomCornerRadius: 22)

    func path(in rect: CGRect) -> Path {
        let topR = min(topCornerRadius, rect.width / 4, rect.height / 4)
        let botR = min(bottomCornerRadius, rect.width / 4, rect.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + topR, y: rect.minY + topR),
                          control: CGPoint(x: rect.minX + topR, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + topR, y: rect.maxY - botR))
        path.addQuadCurve(to: CGPoint(x: rect.minX + topR + botR, y: rect.maxY),
                          control: CGPoint(x: rect.minX + topR, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - topR - botR, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - topR, y: rect.maxY - botR),
                          control: CGPoint(x: rect.maxX - topR, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - topR, y: rect.minY + topR))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                          control: CGPoint(x: rect.maxX - topR, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
