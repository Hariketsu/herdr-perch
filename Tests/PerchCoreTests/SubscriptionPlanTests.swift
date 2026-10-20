import Testing
import PerchCore

@Suite struct SubscriptionPlanTests {
    let globals: Set<Subscription> = Set([
        "pane.created", "pane.closed", "pane.exited", "pane.moved", "pane.agent_detected",
        "pane.focused", "tab.closed", "workspace.closed"
    ].map { Subscription(type: $0) })

    @Test func exactGlobalPlan() {
        #expect(SubscriptionPlan.global == globals)
        #expect(SubscriptionPlan.make(for: Snapshot(protocolVersion: 22, panes: [], agents: [])) == globals)
    }

    @Test func allPanesIncludingThoseWithoutAgents() {
        let snapshot = Snapshot(protocolVersion: 22, panes: [
            PaneInfo(paneID: "p1", tabID: "t", workspaceID: "w"),
            PaneInfo(paneID: "p2", tabID: "t", workspaceID: "w")
        ], agents: [AgentInfo(paneID: "p1", tabID: "t", workspaceID: "w", agent: "claude", status: .working)])
        let expected = globals.union([
            Subscription(type: "pane.agent_status_changed", paneID: "p1"),
            Subscription(type: "pane.agent_status_changed", paneID: "p2")
        ])
        #expect(SubscriptionPlan.make(for: snapshot) == expected)
        var reordered = snapshot
        reordered.panes.reverse()
        reordered.panes.append(snapshot.panes[0])
        reordered.agents = []
        #expect(SubscriptionPlan.make(for: reordered) == expected)
        reordered.panes = [snapshot.panes[0]]
        #expect(SubscriptionPlan.make(for: reordered) == globals.union([
            Subscription(type: "pane.agent_status_changed", paneID: "p1")
        ]))
    }
}
