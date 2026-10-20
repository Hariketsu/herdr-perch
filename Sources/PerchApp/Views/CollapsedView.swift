import PerchCore
import SwiftUI

/// The 32pt band: bird in the left ear, A/B/C summary in the right ear,
/// the camera housing in between.
struct CollapsedBand: View {
    var summary: CompactSummary
    var style: CompactStyle
    var centerWidth: CGFloat
    var wingWidth: CGFloat
    var height: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            PixelBird(status: summary.birdStatus, stale: summary.allStale)
                .padding(.leading, 14)
                .frame(width: wingWidth, alignment: .leading)
            Color.clear.frame(width: centerWidth)
            right
                .padding(.trailing, 13)
                .frame(width: wingWidth, alignment: .trailing)
        }
        .frame(height: height)
        .animation(Palette.spring, value: wingWidth)
    }

    @ViewBuilder private var right: some View {
        if summary.total > 0 {
            switch style {
            case .birdCount:
                let urgent = summary.counts[.blocked, default: 0] > 0 && !summary.allStale
                Text("\(summary.total)")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(urgent ? Palette.alertBright : .white.opacity(0.7))
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(urgent ? Palette.alert.opacity(0.2) : .white.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 4))
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
