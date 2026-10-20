import PerchCore
import SwiftUI

/// Expanded list, laid out like the Vibe Island app: one row per agent with its
/// pixel bird, a bold title over a status line, tags on the right; notices as cards.
struct AgentList: View {
    var rows: [AgentRow]
    var style: ListStyle
    var notice: String?
    var onActivate: (AgentRow) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let notice { NoticeCard(text: notice) }
            if rows.isEmpty {
                Text("No agents in Herdr")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
            }
            TimelineView(.periodic(from: .now, by: 30)) { context in
                VStack(spacing: 2) {
                    ForEach(rows) { row in
                        Button { onActivate(row) } label: {
                            switch style {
                            case .heroAndRows: DetailedRow(row: row, now: context.date)
                            case .rowsOnly: CompactRow(row: row, now: context.date)
                            }
                        }
                        .buttonStyle(RowButtonStyle())
                    }
                }
            }
        }
        .padding(EdgeInsets(top: 4, leading: 10, bottom: 10, trailing: 10))
    }
}

/// Two-line row: bird | title / status line | tags.
private struct DetailedRow: View {
    var row: AgentRow
    var now: Date

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            PixelBird(status: row.status, stale: row.isStale, size: 13).padding(.top, 3)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    .lineLimit(1)
                Text(statusLine(row)).font(.system(size: 11.5)).lineLimit(1)
                    .foregroundStyle(row.isStale ? Color(hex: 0x666666) : Palette.color(row.status))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Tags(row: row, now: now).padding(.top, 1)
            Affordance()
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
    }
}

/// Single-line row for denser lists.
private struct CompactRow: View {
    var row: AgentRow
    var now: Date

    var body: some View {
        HStack(spacing: 8) {
            PixelBird(status: row.status, stale: row.isStale, size: 10)
            Text(row.title).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.85))
                .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            if row.status == .blocked || row.status == .finished {
                Text(row.status == .blocked ? "Input" : "Done")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(row.isStale ? Color(hex: 0x666666) : Palette.color(row.status))
            }
            Tags(row: row, now: now)
            Affordance()
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
    }
}

private struct Tags: View {
    var row: AgentRow
    var now: Date

    var body: some View {
        HStack(spacing: 4) {
            Tag(text: row.agentLabel, tint: Palette.agentTint(row.agentLabel))
            if let project = row.project { Tag(text: project) }
            if row.showsSessionTag { Tag(text: row.session) }
            Text(Self.duration(since: row.since, now: now))
                .font(.system(size: 10).monospacedDigit()).foregroundStyle(.white.opacity(0.45))
                .frame(minWidth: 24, alignment: .trailing)
        }
        .fixedSize()
    }

    static func duration(since: Date, now: Date) -> String {
        let minutes = max(0, Int((now.timeIntervalSince(since) / 60).rounded()))
        if minutes < 1 { return "<1m" }
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        return hours < 24 ? "\(hours)h" : "\(hours / 24)d"
    }
}

/// Small rounded label; agents get a tinted one like Vibe Island's agent badges.
private struct Tag: View {
    var text: String
    var tint: Color?

    var body: some View {
        Text(text).font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(tint ?? .white.opacity(0.55))
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background((tint ?? .white).opacity(tint == nil ? 0.1 : 0.16), in: RoundedRectangle(cornerRadius: 4))
    }
}

/// Amber card for connection and jump notices (Vibe Island shows hints as cards).
private struct NoticeCard: View {
    var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11))
                .foregroundStyle(Palette.notice)
            Text(text).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.06)))
    }
}

/// "↗" that appears on hover: every row jumps to Herdr in v1.
private struct Affordance: View {
    @Environment(\.rowHovered) private var hovered

    var body: some View {
        Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.white.opacity(hovered ? 0.55 : 0)).frame(width: 12).padding(.top, 3)
    }
}

/// Hover highlight switches instantly: an animated fade re-rendered the list for
/// every frame of the transition each time the pointer crossed a row (perf.sh).
private struct RowButtonStyle: ButtonStyle {
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .environment(\.rowHovered, hovered)
            .background(.white.opacity(configuration.isPressed ? 0.1 : hovered ? 0.06 : 0),
                        in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
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
    case .idle: return row.isUnrecognized ? "Unrecognized" : "Ready"
    }
}
