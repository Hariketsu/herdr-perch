import PerchCore

/// Sections of the grouped list (architecture.md §6.2). Pure logic.
enum ListGroups {
    /// Non-empty groups, blocked → finished → working → idle; rows keep their order.
    static func make(_ rows: [AgentRow]) -> [(status: DisplayStatus, rows: [AgentRow])] {
        [DisplayStatus.blocked, .finished, .working, .idle].compactMap { status in
            let group = rows.filter { $0.status == status }
            return group.isEmpty ? nil : (status, group)
        }
    }
}
