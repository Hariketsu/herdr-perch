import PerchCore
import SwiftUI

/// The collapsed band: pixel ram in the left ear, A/B/C summary in the right
/// ear, the camera housing in between. Like Vibe Island it fades out as the
/// notch opens (the ram reappears on each row) and back in as it closes.
struct CollapsedBand: View {
    var summary: CompactSummary
    var style: CompactStyle
    var completion: String?       // "✓ title" feedback replaces the right ear briefly
    var centerWidth: CGFloat
    var wingWidth: CGFloat
    var height: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            PixelRam(status: summary.birdStatus, stale: summary.allStale, scale: 0.8)
                .padding(.leading, 9)
                .frame(width: wingWidth, alignment: .leading)
            // Flexible so each ear can ride its own edge of an animating shape.
            Spacer(minLength: centerWidth)
            right
                .padding(.trailing, 10)
                .frame(width: wingWidth, alignment: .trailing)
        }
        .frame(height: height)
        .animation(Palette.open, value: completion)
    }

    @ViewBuilder private var right: some View {
        if let completion {
            HStack(spacing: 4) {
                Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                Text(completion).font(.system(size: 10.5, weight: .semibold)).lineLimit(1)
            }
            .foregroundStyle(Palette.finishedBright)
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
        } else if summary.total > 0 {
            switch style {
            case .birdCount:
                // Vibe Island's Clean style: a bare number.
                let urgent = summary.counts[.blocked, default: 0] > 0 && !summary.allStale
                Text("\(summary.total)")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(urgent ? Palette.alertBright : .white.opacity(summary.allStale ? 0.4 : 0.92))
            case .dots:
                HStack(spacing: 4) {
                    ForEach(Array(summary.dots.enumerated()), id: \.offset) { _, status in
                        StatusDot(status: status, stale: summary.allStale)
                    }
                    if summary.overflow > 0 {
                        Text("+\(summary.overflow)").font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
                    }
                }
            case .counts:
                HStack(spacing: 8) {
                    ForEach([DisplayStatus.blocked, .finished, .working, .idle], id: \.self) { status in
                        if let count = summary.counts[status] {
                            HStack(spacing: 3) {
                                StatusDot(status: status, stale: summary.allStale)
                                Text("\(count)")
                                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(status == .blocked && !summary.allStale
                                                     ? Palette.alertBright : .white.opacity(0.8))
                            }
                        }
                    }
                }
            }
        }
    }
}

/// 6pt status dot; blocked pulses, working breathes, others stay still.
struct StatusDot: View {
    var status: DisplayStatus
    var stale = false

    var body: some View {
        let color = Palette.color(status, stale: stale)
        LayerLoop(kind: Self.loop(status, stale: stale)) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .shadow(color: status == .blocked && !stale ? Palette.alert : .clear, radius: 3)
                .padding(3)  // room for the glow
        }
        .padding(-3)
    }

    static func loop(_ status: DisplayStatus, stale: Bool) -> LoopKind? {
        guard !stale else { return nil }
        switch status {
        case .blocked: return .throb(period: 1.5)
        case .working: return .throb(period: 2.4)
        case .finished, .idle: return nil
        }
    }
}
