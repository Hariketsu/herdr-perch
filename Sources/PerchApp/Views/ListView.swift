import PerchCore
import SwiftUI

/// Expanded list: first row large (bird + title + tags + status line), others compact.
struct AgentList: View {
    var rows: [AgentRow]
    var style: ListStyle
    var notice: String?
    var onActivate: (AgentRow) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let notice {
                Text(notice).font(.system(size: 10.5)).foregroundStyle(Palette.notice)
                    .padding(.horizontal, 8).padding(.top, 4).padding(.bottom, 6)
            }
            if rows.isEmpty {
                Text("No agents in Herdr")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity).padding(.top, 8).padding(.bottom, 4)
            }
            TimelineView(.periodic(from: .now, by: 30)) { context in
                VStack(spacing: 2) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        Button { onActivate(row) } label: {
                            if style == .heroAndRows && index == 0 {
                                HeroRow(row: row, now: context.date)
                            } else {
                                MiniRow(row: row, now: context.date)
                            }
                        }
                        .buttonStyle(RowButtonStyle(highlighted: style == .heroAndRows && index == 0 && row.status == .finished))
                    }
                }
            }
        }
        .padding(EdgeInsets(top: 4, leading: 12, bottom: 12, trailing: 12))
    }
}

private struct HeroRow: View {
    var row: AgentRow
    var now: Date

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            PixelBird(status: row.status, stale: row.isStale).padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(row.title).font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
                        .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    Tags(row: row, now: now)
                }
                HStack(spacing: 5) {
                    if row.status == .blocked && !row.isStale {
                        LayerLoop(kind: .throb(period: 1.5)) { Circle().fill(Palette.alert).frame(width: 5, height: 5) }
                    }
                    Text(statusLine(row)).font(.system(size: 10.5)).lineLimit(1)
                }
                .foregroundStyle(row.isStale ? Color(hex: 0x666666) : Palette.color(row.status))
            }
            Affordance()
        }
        .padding(8)
    }
}

private struct MiniRow: View {
    var row: AgentRow
    var now: Date

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(status: row.status, stale: row.isStale)
            Text(row.title).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.75))
                .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            if row.status == .blocked || row.status == .finished {
                Text(row.status == .blocked ? "Input" : "Done")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(row.isStale ? Color(hex: 0x666666) : Palette.color(row.status))
            }
            Tags(row: row, now: now)
            Affordance()
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
    }
}

private struct Tags: View {
    var row: AgentRow
    var now: Date

    var body: some View {
        HStack(spacing: 4) {
            Tag(text: row.agentLabel)
            if let project = row.project { Tag(text: project) }
            if row.showsSessionTag { Tag(text: row.session, outlined: true) }
            Text(Self.duration(since: row.since, now: now))
                .font(.system(size: 9).monospacedDigit()).foregroundStyle(.white.opacity(0.5))
                .frame(minWidth: 22, alignment: .trailing)
        }
        .fixedSize()
    }

    static func duration(since: Date, now: Date) -> String {
        let minutes = max(0, Int((now.timeIntervalSince(since) / 60).rounded()))
        if minutes < 1 { return "now" }
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        return hours < 24 ? "\(hours)h" : "\(hours / 24)d"
    }
}

private struct Tag: View {
    var text: String
    var outlined = false

    var body: some View {
        Text(text).font(.system(size: 9, weight: .medium))
            .foregroundStyle(.white.opacity(outlined ? 0.6 : 0.5))
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(.white.opacity(outlined ? 0.05 : 0.1), in: RoundedRectangle(cornerRadius: 4))
            .overlay {
                if outlined { RoundedRectangle(cornerRadius: 4).strokeBorder(.white.opacity(0.12)) }
            }
    }
}

/// "↗" that appears on hover: every row jumps to Herdr in v1.
private struct Affordance: View {
    @Environment(\.rowHovered) private var hovered

    var body: some View {
        Text("↗").font(.system(size: 12)).foregroundStyle(.white.opacity(hovered ? 0.5 : 0)).frame(width: 10)
    }
}

private struct RowButtonStyle: ButtonStyle {
    var highlighted: Bool
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .environment(\.rowHovered, hovered)
            .background(.white.opacity(hovered ? 0.08 : highlighted ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: 0.15), value: hovered)
    }
}

private extension EnvironmentValues {
    @Entry var rowHovered = false
}

/// Status line text, only from Herdr fields (product.md §3).
func statusLine(_ row: AgentRow) -> String {
    if let subtitle = row.subtitle { return subtitle }
    switch row.status {
    case .blocked: return "Needs your input"
    case .finished: return "Done — click to jump"
    case .working: return "Working"
    case .idle: return row.isUnrecognized ? "Unrecognized" : "Idle"
    }
}
