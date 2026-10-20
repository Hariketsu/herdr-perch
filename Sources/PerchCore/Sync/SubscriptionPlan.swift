public enum SubscriptionPlan {
    public static let global: Set<Subscription> = Set([
        "pane.created", "pane.closed", "pane.exited", "pane.moved", "pane.agent_detected",
        "pane.focused", "tab.closed", "workspace.closed",
    ].map { Subscription(type: $0) })

    /// Every pane — not only those with an agent — so an agent appearing in an
    /// existing pane needs no resubscription.
    public static func make(for snapshot: Snapshot) -> Set<Subscription> {
        global.union(snapshot.panes.map { Subscription(type: "pane.agent_status_changed", paneID: $0.paneID) })
    }
}

public enum PollingPolicy {
    public static func interval(streamHealthy: Bool, consecutiveFailures: Int) -> Duration {
        guard consecutiveFailures > 0 else { return streamHealthy ? .seconds(3) : .milliseconds(500) }
        // 1, 2, 4, 8, then capped at 10.
        return consecutiveFailures >= 5 ? .seconds(10) : .seconds(1 << (consecutiveFailures - 1))
    }
}
