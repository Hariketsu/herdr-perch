import Foundation

/// Remembers when each agent's current `state_change_seq` was first observed.
/// Herdr reports no timestamps; this only drives the duration label and sorting.
public struct StatusClock: Sendable {
    private var entries: [AgentRef: (seq: UInt64, since: Date)] = [:]

    public init() {}

    public mutating func observe(_ ref: AgentRef, seq: UInt64, now: Date) -> Date {
        if let entry = entries[ref], entry.seq == seq { return entry.since }
        entries[ref] = (seq, now)
        return now
    }

    public mutating func retain(only refs: Set<AgentRef>) {
        entries = entries.filter { refs.contains($0.key) }
    }
}

public enum RowBuilder {
    static let agentLabels = ["claude": "Claude", "codex": "Codex", "omp": "OMP", "opencode": "OpenCode"]

    public static func rows(_ sessions: [SessionState], clock: inout StatusClock, now: Date) -> [AgentRow] {
        let showsSessionTag = sessions.count >= 2
        var rows: [AgentRow] = []
        for session in sessions {
            guard let snapshot = session.snapshot else { continue }
            let isStale = if case .stale = session.health { true } else { false }
            for agent in snapshot.agents {
                let ref = AgentRef(session: session.endpoint.name, paneID: agent.paneID)
                let title = agent.name ?? agent.title ?? agent.displayAgent ?? agent.agent
                let subtitle = agent.stateLabels[agent.status.rawValue] ?? agent.title
                rows.append(AgentRow(
                    id: ref,
                    status: DisplayStatus(agent.status),
                    isUnrecognized: agent.status == .unknown,
                    title: title,
                    subtitle: subtitle == title ? nil : subtitle,
                    agentLabel: agent.displayAgent ?? agentLabels[agent.agent] ?? agent.agent,
                    project: agent.cwd.map { URL(fileURLWithPath: $0).lastPathComponent },
                    since: clock.observe(ref, seq: agent.stateChangeSeq, now: now),
                    session: session.endpoint.name,
                    showsSessionTag: showsSessionTag,
                    isStale: isStale,
                    workspaceID: agent.workspaceID,
                    tabID: agent.tabID))
            }
        }
        clock.retain(only: Set(rows.map(\.id)))
        return rows.sorted { a, b in
            if a.status != b.status { return a.status < b.status }
            if a.since != b.since { return a.since > b.since }
            if a.session != b.session { return a.session < b.session }
            return a.id.paneID < b.id.paneID
        }
    }
}
