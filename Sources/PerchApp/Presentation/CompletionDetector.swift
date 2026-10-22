import PerchCore

/// Finds the agent that newly became Finished between two row updates, for the
/// collapsed "✓ title" feedback (architecture.md §6). Pure logic.
struct CompletionDetector {
    private var finished: Set<AgentRef>?

    /// The first call only records a baseline, so agents already finished at launch stay quiet.
    mutating func observe(_ rows: [AgentRow]) -> AgentRow? {
        let current = rows.filter { $0.status == .finished && !$0.isStale }
        defer { finished = Set(current.map(\.id)) }
        guard let previous = finished else { return nil }
        // max(by:) keeps the first of equal elements, so ties go to the earlier row.
        return current.filter { !previous.contains($0.id) }.max { $0.since < $1.since }
    }
}
