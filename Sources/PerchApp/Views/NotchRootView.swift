import PerchCore
import SwiftUI

/// Fills the fixed canvas; the notch shape is anchored top-centre and grows
/// in place. Choreography follows open-vibe-island: the collapsed band fades
/// out where it is, the expanded content is laid out at its final size and
/// revealed by the growing shape, and stays mounted briefly after collapsing
/// so the shape clips it away instead of it vanishing.
struct NotchRootView: View {
    @Bindable var model: NotchModel

    @State private var contentMounted = false
    @State private var mountGeneration = 0
    @State private var popping = false

    var body: some View {
        let expanded = model.isExpanded
        let collapsed = model.geometry.collapsedSize(wingWidth: model.wingWidth)
        let open = model.geometry.expandedSize(contentHeight: model.contentHeight, wingWidth: model.wingWidth)
        let size = expanded ? open : collapsed
        let shape = expanded ? NotchShape.expanded : NotchShape.collapsed

        ZStack(alignment: .top) {
            shape
                .fill(.black)
                .overlay { shape.stroke(.white.opacity(expanded ? 0.07 : 0), lineWidth: 1) }
                .frame(width: size.width, height: size.height)

            if contentMounted {
                ExpandedContent(model: model, width: open.width)
                    .frame(width: size.width, height: size.height, alignment: .top)
                    .clipShape(shape)
                    .opacity(expanded ? 1 : 0)
                    .blur(radius: expanded ? 0 : 6)   // vibeisland: incoming layer sharpens from 6px
                    .transition(.opacity.animation(.easeOut(duration: 0.18).delay(0.12)))
                    .allowsHitTesting(expanded)
            }

            CollapsedBand(summary: model.summary, style: model.preferences.compactStyle,
                          centerWidth: model.geometry.centerWidth, wingWidth: model.wingWidth,
                          height: model.geometry.bandHeight)
                .frame(width: collapsed.width)
                .opacity(expanded ? 0 : 1)
                .blur(radius: expanded ? 6 : 0)
                .allowsHitTesting(false)
        }
        .contentShape(shape)
        .onTapGesture { if expanded { model.send(.clicked) } }   // collapsed clicks come from the monitor
        .scaleEffect(scale(expanded: expanded), anchor: .top)
        .animation(model.reduceMotion ? nil : (expanded ? Palette.open : Palette.close), value: expanded)
        .animation(model.reduceMotion ? nil : Palette.resize, value: open.height)
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
        .onChange(of: expanded, initial: true) { _, now in syncMount(expanded: now) }
        .onChange(of: model.presentation.pulse) { pop() }
        .environment(\.colorScheme, .dark)
    }

    private func scale(expanded: Bool) -> CGFloat {
        if expanded { return 1 }
        if popping { return 1.04 }
        return 1
    }

    private func syncMount(expanded: Bool) {
        mountGeneration &+= 1
        let generation = mountGeneration
        if expanded {
            contentMounted = true
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
            guard mountGeneration == generation, !model.isExpanded else { return }
            contentMounted = false
        }
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
            .padding(.leading, 30)
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
            .padding(.trailing, 28)
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
