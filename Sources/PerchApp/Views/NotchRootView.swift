import PerchCore
import SwiftUI

/// Fills the fixed canvas; the notch shape is anchored top-centre and grows in
/// place. Visual parameters follow vibeisland.app's demo: one overshooting
/// curve for size, a separate ease-out for the corner radius, a two-layer
/// shadow with a state glow, and blur/scale crossfades between layers.
struct NotchRootView: View {
    @Bindable var model: NotchModel

    @State private var bottomRadius: CGFloat = 10
    @State private var popping = false

    var body: some View {
        let expanded = model.isExpanded
        let collapsed = model.geometry.collapsedSize(wingWidth: model.wingWidth)
        let open = model.geometry.expandedSize(contentHeight: model.contentHeight, wingWidth: model.wingWidth)
        let size = expanded ? open : collapsed
        let shape = NotchShape(bottomRadius: bottomRadius)
        let motion = !model.reduceMotion

        ZStack(alignment: .top) {
            shape
                .fill(.black)
                .frame(width: size.width, height: size.height)
                .shadow(color: .black.opacity(0.6), radius: 4, y: 2)
                .shadow(color: .black.opacity(0.3), radius: 12, y: 8)
                .shadow(color: glow(expanded: expanded), radius: expanded ? 10 : 0)

            // Always mounted, like vibeisland's stacked layers: an inserted layer would
            // appear already active and skip its fade. Laid out at the shape's current
            // width, as in Vibe Island: leading content rides the left edge, trailing
            // tags the right edge, and cards stretch with the shape.
            ExpandedContent(model: model)
                .modifier(LayerFade(active: expanded))
                .modifier(ReflowingFrame(width: size.width, height: size.height))
                .clipShape(shape)
                .allowsHitTesting(expanded)
                .accessibilityHidden(!expanded)

            CollapsedBand(summary: model.summary, style: model.preferences.compactStyle,
                          completion: model.presentation.completion,
                          centerWidth: model.geometry.centerWidth, wingWidth: model.wingWidth,
                          height: model.geometry.bandHeight)
                // Each ear rides its own edge of the shape (left ear the left edge, right
                // ear the right edge): they slide out and fade within ~80ms when opening,
                // and converge back with the edges, appearing ~60ms in, when closing.
                // Position follows the shape's spring.
                .frame(width: size.width)
                .modifier(LayerFade(active: !expanded, fadeIn: 0.15, fadeOut: 0.08, fadeInDelay: 0.06))
                .allowsHitTesting(false)
        }
        .contentShape(shape)
        .onTapGesture { if expanded { model.send(.clicked) } }   // collapsed clicks come from the monitor
        .scaleEffect(popping && !expanded ? 1.04 : 1, anchor: .top)
        // The centring frame must sit inside the animations: otherwise the shape's
        // position jumps to its final x while its width animates, and the notch
        // lurches ~22pt sideways at the start of collapsing (measured on video).
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(motion ? (expanded ? Palette.open : Palette.close) : nil, value: size)
        .animation(Palette.pop, value: popping)
        .background(alignment: .top) {
            // Measured off-screen so the first expanded frame already has its final height.
            // Only the list: expandedSize adds the notch strip (header) itself.
            AgentList(rows: model.store.rows, style: model.preferences.listStyle,
                      notice: model.notice, onActivate: { _ in })
                .frame(width: open.width)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { model.contentHeight = $0 }
                .hidden()
        }
        .onChange(of: expanded, initial: true) { _, now in
            withAnimation(motion ? Palette.radius : nil) { bottomRadius = now ? 14 : 10 }
        }
        .onChange(of: model.presentation.pulse) { pop() }
        .environment(\.colorScheme, .dark)
    }

    /// vibeisland adds a faint white rim glow to open lists and an amber one for attention.
    private func glow(expanded: Bool) -> Color {
        guard expanded else { return .clear }
        return model.summary.counts[.blocked] != nil ? Palette.alert.opacity(0.15) : .white.opacity(0.04)
    }

    private func pop() {
        popping = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { popping = false }
    }
}

/// A frame whose size is animatable data, so its content is laid out again at
/// every animation frame. A plain `.frame` only interpolates each child between
/// its start and end positions: long titles laid out wide overlapped tags that
/// were still sliding in. Reflowing truncates titles to the width of the moment.
private struct ReflowingFrame: ViewModifier, Animatable {
    var width: CGFloat
    var height: CGFloat

    nonisolated var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(width, height) }
        set { (width, height) = (newValue.first, newValue.second) }
    }

    func body(content: Content) -> some View {
        content.frame(width: width, height: height, alignment: .top)
    }
}

/// Notch strip with settings on the right of the camera (as in Vibe Island), then the list.
private struct ExpandedContent: View {
    @Bindable var model: NotchModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Spacer()
                // Settings live in the notch too: menu-bar managers like Ice can hide or
                // displace the status item behind the notch, making it unreachable.
                Button(action: model.openSettings) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(HeaderButtonStyle())
                .help("Settings")
            }
            .padding(.trailing, 14)
            .frame(height: model.geometry.bandHeight)
            AgentList(rows: model.store.rows, style: model.preferences.listStyle,
                      notice: model.notice, onActivate: model.activate)
        }
    }
}

private struct HeaderButtonStyle: ButtonStyle {
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white.opacity(hovered ? 0.9 : 0.6))
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: 0.12), value: hovered)
    }
}
