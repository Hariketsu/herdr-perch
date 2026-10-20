import Foundation
import PerchCore

func testAgent(_ pane: String = "p1", status: AgentStatus = .working, seq: UInt64 = 1) -> AgentInfo {
    AgentInfo(paneID: pane, tabID: "t1", workspaceID: "w1", agent: "claude", status: status, stateChangeSeq: seq)
}

func testSnapshot(_ agents: [AgentInfo] = [testAgent()]) -> Snapshot {
    Snapshot(protocolVersion: 22, panes: agents.map {
        PaneInfo(paneID: $0.paneID, tabID: $0.tabID, workspaceID: $0.workspaceID)
    }, agents: agents)
}

func testSession(_ name: String = "test", agents: [AgentInfo] = [testAgent()], health: SessionHealth = .live) -> SessionState {
    SessionState(endpoint: SessionEndpoint(name: name, socketPath: "/tmp/test-\(name).sock", isDefault: name == "default"),
                 snapshot: testSnapshot(agents), health: health)
}

func testRow() -> AgentRow {
    AgentRow(id: AgentRef(session: "test", paneID: "p1"), status: .working, title: "Task", agentLabel: "Claude",
             since: Date(timeIntervalSince1970: 100), session: "test", workspaceID: "w1", tabID: "t1")
}
