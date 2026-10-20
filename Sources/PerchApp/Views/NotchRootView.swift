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
            // appear already active and skip its fade.
            ExpandedContent(model: model, width: open.width)
                .modifier(LayerFade(active: expanded, reduceMotion: model.reduceMotion))
                .frame(width: size.width, height: size.height, alignment: .top)
                .clipShape(shape)
                .allowsHitTesting(expanded)
                .accessibilityHidden(!expanded)

            CollapsedBand(summary: model.summary, style: model.preferences.compactStyle,
                          completion: model.presentation.completion,
                          centerWidth: model.geometry.centerWidth, wingWidth: model.wingWidth,
                          height: model.geometry.bandHeight)
                .frame(width: collapsed.width)
                .modifier(LayerFade(active: !expanded, reduceMotion: model.reduceMotion))
                .allowsHitTesting(false)
        }
        .animation(motion ? Palette.size : nil, value: size)
        .contentShape(shape)
        .onTapGesture { if expanded { model.send(.clicked) } }   // collapsed clicks come from the monitor
        .scaleEffect(popping && !expanded ? 1.04 : 1, anchor: .top)
        .animation(Palette.pop, value: popping)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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

/// Header in the notch strip (camera gap left clear) + the agent list below it.
private struct ExpandedContent: View {
    @Bindable var model: NotchModel
    var width: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            ExpandedHeader(model: model, width: width)
            AgentList(rows: model.store.rows, style: model.preferences.listStyle,
                      notice: model.notice, onActivate: model.activate)
        }
        .frame(width: width)
    }
}

/// Same height as the physical notch. Left lane: bird + count; right lane:
/// settings. The middle stays empty for the camera housing.
private struct ExpandedHeader: View {
    @Bindable var model: NotchModel
    var width: CGFloat

    var body: some View {
        let summary = model.summary
        let lane = max(0, (width - model.geometry.centerWidth) / 2)
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                PixelBird(status: summary.birdStatus, stale: summary.allStale, size: 13)
                Text(summary.total == 1 ? "1 agent" : "\(summary.total) agents")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
            .padding(.leading, 18)
            .frame(width: lane, alignment: .leading)

            Color.clear.frame(width: model.geometry.centerWidth)

            Button(action: model.openSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 11))
                    .frame(width: 22, height: 22)
                    .contentShape(Circle())
            }
            .buttonStyle(HeaderButtonStyle())
            .help("Settings")
            .padding(.trailing, 16)
            .frame(width: lane, alignment: .trailing)
        }
        .frame(height: model.geometry.bandHeight)
    }
}

private struct HeaderButtonStyle: ButtonStyle {
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white.opacity(hovered ? 0.85 : 0.5))
            .background(.white.opacity(hovered ? 0.14 : 0.08), in: Circle())
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: 0.15), value: hovered)
    }
}
