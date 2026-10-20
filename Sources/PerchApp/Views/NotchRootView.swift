import PerchCore
import SwiftUI

/// Black notch shape anchored to the top edge; collapsed band on top, list below when expanded.
struct NotchRootView: View {
    @Bindable var model: NotchModel

    static let shoulder: CGFloat = 13

    static func shadowMargin(expanded: Bool) -> CGFloat { expanded ? 32 : 8 }

    var body: some View {
        let size = model.shapeSize
        let expanded = model.isExpanded
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    CollapsedBand(summary: model.summary, style: model.preferences.compactStyle,
                                  centerWidth: model.geometry.centerWidth, wingWidth: model.wingWidth,
                                  height: model.geometry.bandHeight)
                        .frame(maxWidth: .infinity)
                    if expanded {
                        AgentList(rows: model.store.rows, style: model.preferences.listStyle,
                                  notice: model.notice, onActivate: model.activate)
                            .fixedSize(horizontal: false, vertical: true)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { model.contentHeight = $0 }
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
                                    .animation(Palette.spring.delay(0.06)),
                                removal: .opacity.animation(.easeOut(duration: 0.15))))
                    }
                }
                .frame(width: size.width, height: size.height, alignment: .top)
                .clipped()
            }
            .background(NotchShape(radius: expanded ? 18 : 10, shoulder: Self.shoulder).fill(.black))
            .shadow(color: model.summary.counts[.blocked] != nil && !expanded ? Palette.alert.opacity(0.25) : .black.opacity(0.45),
                    radius: expanded ? 14 : 3, y: expanded ? 8 : 1)
            .contentShape(Rectangle())
            .onHover { model.send($0 ? .pointerEntered : .pointerExited) }
            .onTapGesture { model.send(.clicked) }
            .animation(model.reduceMotion ? nil : Palette.spring, value: size)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
    }
}

/// Rectangle with rounded bottom corners and concave "shoulders" that blend into the menu bar.
struct NotchShape: Shape {
    var radius: CGFloat
    var shoulder: CGFloat

    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let s = min(shoulder, rect.height / 2)
        path.move(to: CGPoint(x: rect.minX - shoulder, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX + shoulder, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + s), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - radius), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + s))
        path.addQuadCurve(to: CGPoint(x: rect.minX - shoulder, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
