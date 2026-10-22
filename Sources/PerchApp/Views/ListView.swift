import PerchCore
import SwiftUI

/// Expanded list. Grouped (default, architecture.md §6.2): sections by status with
/// cards for agents that need a look and a folded Idle section; Detailed and Compact
/// list every agent in one run. Notices show as cards on top.
struct AgentList: View {
    var rows: [AgentRow]
    var style: ListStyle
    var cleanTitles: Bool
    @Binding var idleExpanded: Bool
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
                let shown = cleanTitles ? rows.map(cleaned) : rows
                switch style {
                case .grouped:
                    GroupedList(rows: shown, now: context.date, idleExpanded: $idleExpanded, onActivate: onActivate)
                case .heroAndRows, .rowsOnly:
                    VStack(spacing: 2) {
                        ForEach(shown) { row in
                            Button { onActivate(row) } label: {
                                if style == .heroAndRows {
                                    DetailedRow(row: row, now: context.date)
                                } else {
                                    CompactRow(row: row, now: context.date)
                                }
                            }
                            .buttonStyle(RowButtonStyle())
                        }
                    }
                }
            }
        }
        .padding(EdgeInsets(top: 4, leading: 10, bottom: 10, trailing: 10))
    }
}

/// Status counts on the left of the expanded strip: "● 1 need you  ● 2 working  ● 3 idle";
/// drops the words when they would run into the camera housing.
struct StatusSummary: View {
    var counts: [DisplayStatus: Int]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            items(words: true)
            items(words: false)
        }
        .font(.system(size: 11, weight: .medium))
        .lineLimit(1)
    }

    private func items(words: Bool) -> some View {
        HStack(spacing: words ? 10 : 8) {
            ForEach([DisplayStatus.blocked, .finished, .working, .idle], id: \.self) { status in
                if let count = counts[status], count > 0 {
                    HStack(spacing: 4) {
                        Circle().frame(width: 6, height: 6)
                        Text(words ? "\(count) \(Self.word(status))" : "\(count)").monospacedDigit()
                    }
                    .foregroundStyle(status == .idle ? Color.white.opacity(0.38) : Palette.bright(status))
                }
            }
        }
        .fixedSize()
    }

    static func word(_ status: DisplayStatus) -> String {
        switch status {
        case .blocked: "need you"
        case .finished: "done"
        case .working: "working"
        case .idle: "idle"
        }
    }
}

// MARK: - Grouped

private struct GroupedList: View {
    var rows: [AgentRow]
    var now: Date
    @Binding var idleExpanded: Bool
    var onActivate: (AgentRow) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(ListGroups.make(rows), id: \.status) { group in
                VStack(alignment: .leading, spacing: 2) {
                    if group.status == .idle {
                        IdleHeader(rows: group.rows, expanded: $idleExpanded)
                        if idleExpanded {
                            ForEach(group.rows) { row in
                                Button { onActivate(row) } label: { IdleRow(row: row, now: now) }
                                    .buttonStyle(RowButtonStyle())
                            }
                        }
                    } else {
                        GroupHeader(status: group.status, count: group.rows.count)
                        ForEach(group.rows) { row in
                            Button { onActivate(row) } label: { CardRow(row: row, now: now) }
                                .buttonStyle(RowButtonStyle())
                        }
                    }
                }
            }
        }
    }
}

private struct GroupHeader: View {
    var status: DisplayStatus
    var count: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(Self.label(status))
            Text("\(count)").monospacedDigit().opacity(0.8)
        }
        .font(.system(size: 10, weight: .semibold)).kerning(0.6)
        .foregroundStyle(.white.opacity(0.38))
        .padding(EdgeInsets(top: 4, leading: 10, bottom: 2, trailing: 10))
    }

    static func label(_ status: DisplayStatus) -> String {
        switch status {
        case .blocked: "NEEDS YOU"
        case .finished: "DONE"
        case .working: "WORKING"
        case .idle: "IDLE"
        }
    }
}

/// "› IDLE 4" with up to six still rams; toggles the Idle rows.
private struct IdleHeader: View {
    var rows: [AgentRow]
    @Binding var expanded: Bool

    var body: some View {
        Button { expanded.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold))
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                Text(GroupHeader.label(.idle)).kerning(0.6)
                Text("\(rows.count)").monospacedDigit().opacity(0.8)
                if !expanded {
                    HStack(spacing: 6) {
                        ForEach(rows.prefix(6)) { row in
                            PixelRam(status: .idle, stale: row.isStale, animates: false)
                        }
                    }
                    .padding(.leading, 6)
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.38))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
    }
}

/// Card for an agent that needs a look: ram | title / "status · project · age" | icon.
private struct CardRow: View {
    var row: AgentRow
    var now: Date
    @Environment(\.rowHovered) private var hovered

    var body: some View {
        HStack(spacing: 10) {
            PixelRam(status: row.status, stale: row.isStale).frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                HStack(spacing: 5) {
                    Text(statusLine(row)).foregroundStyle(row.isStale ? Color(hex: 0x666666) : Palette.bright(row.status))
                    if let project = row.project { Text("·"); Text(project) }
                    if row.showsSessionTag { Text("·"); Text(row.session) }
                    Text("·")
                    Text(durationText(since: row.since, now: now)).monospacedDigit()
                }
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.38)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            AgentMark(label: row.agentLabel, highlighted: hovered)
            Affordance()
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .background(Self.tint(row), in: RoundedRectangle(cornerRadius: 11))
    }

    static func tint(_ row: AgentRow) -> Color {
        if row.isStale { return .white.opacity(0.04) }
        switch row.status {
        case .blocked: return Palette.alert.opacity(0.10)
        case .finished: return Palette.finished.opacity(0.08)
        case .working, .idle: return .white.opacity(0.04)
        }
    }
}

/// Single-line idle row: ram | dimmed title | project | icon | age.
private struct IdleRow: View {
    var row: AgentRow
    var now: Date
    @Environment(\.rowHovered) private var hovered

    var body: some View {
        HStack(spacing: 10) {
            PixelRam(status: .idle, stale: row.isStale).frame(width: 22)
            Text(row.title).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.62))
                .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            if let project = row.project {
                Text(project).font(.system(size: 11)).foregroundStyle(.white.opacity(0.38)).lineLimit(1)
                    .frame(maxWidth: 110, alignment: .leading)
            }
            AgentMark(label: row.agentLabel, highlighted: hovered)
            Text(durationText(since: row.since, now: now))
                .font(.system(size: 10.5).monospacedDigit()).foregroundStyle(.white.opacity(0.38))
                .frame(minWidth: 26, alignment: .trailing)
            Affordance()
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
    }
}

// MARK: - Detailed and Compact

/// Two-line row: ram | title / status line | tags.
private struct DetailedRow: View {
    var row: AgentRow
    var now: Date

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            PixelRam(status: row.status, stale: row.isStale).frame(width: 22)
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
            PixelRam(status: row.status, stale: row.isStale).frame(width: 22)
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
    @Environment(\.rowHovered) private var hovered

    var body: some View {
        HStack(spacing: 6) {
            if let project = row.project { Tag(text: project) }
            if row.showsSessionTag { Tag(text: row.session) }
            AgentMark(label: row.agentLabel, highlighted: hovered)
            Text(durationText(since: row.since, now: now))
                .font(.system(size: 10).monospacedDigit()).foregroundStyle(.white.opacity(0.45))
                .frame(minWidth: 24, alignment: .trailing)
        }
        .fixedSize()
    }
}

/// Small rounded grey label for project and session names.
private struct Tag: View {
    var text: String

    var body: some View {
        Text(text).font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(.white.opacity(0.55))
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
    }
}

func durationText(since: Date, now: Date) -> String {
    let minutes = max(0, Int((now.timeIntervalSince(since) / 60).rounded()))
    if minutes < 1 { return "<1m" }
    if minutes < 60 { return "\(minutes)m" }
    let hours = minutes / 60
    return hours < 24 ? "\(hours)h" : "\(hours / 24)d"
}

// MARK: - Shared

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
            .foregroundStyle(.white.opacity(hovered ? 0.55 : 0)).frame(width: 12)
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

/// The row with prompt prefixes and icons stripped from its title and subtitle (Settings › Clean titles).
private func cleaned(_ row: AgentRow) -> AgentRow {
    var row = row
    row.title = TitleCleaner.clean(row.title)
    row.subtitle = row.subtitle.map(TitleCleaner.clean).flatMap { $0 == row.title ? nil : $0 }
    return row
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
