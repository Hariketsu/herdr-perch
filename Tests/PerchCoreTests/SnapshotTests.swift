import Foundation
import Testing
import PerchCore

@Suite("Snapshot decoding contract")
struct SnapshotTests {
    @Test func recorded095() throws {
        let snapshot = try Snapshot.decode(response: fixture("snapshot-0.9.5"))
        #expect(snapshot.protocolVersion == 22)
        #expect(Set(snapshot.panes.map(\.paneID)) == ["w1:p1", "w1:p2", "w1:p3"])
        #expect(snapshot.panes.first { $0.paneID == "w1:p2" } ==
                PaneInfo(paneID: "w1:p2", tabID: "w1:t2", workspaceID: "w1"))
        #expect(snapshot.agents.count == 3)
        let working = try #require(snapshot.agents.first { $0.paneID == "w1:p1" })
        #expect(working.agent == "claude")
        #expect(working.status == .working)
        #expect(working.focused)
        #expect(working.stateChangeSeq == 1)
        #expect(working.cwd == "/private/tmp")
        let blocked = try #require(snapshot.agents.first { $0.paneID == "w1:p3" })
        #expect(blocked.title == "Fixture task title")
        #expect(blocked.agent == "omp")
        #expect(blocked.status == .blocked)
        #expect(blocked.stateLabels == ["blocked": "needs approval"])
        let done = try #require(snapshot.agents.first { $0.paneID == "w1:p2" })
        #expect(done.status == .done)
        #expect(done.stateChangeSeq == 3)
        #expect(done.completionSeq == 3)
        #expect(!done.focused)
    }

    @Test func legacyFixtureInResponseEnvelope() throws {
        // The upstream resource is a bare snapshot. decode accepts a full response only.
        let body = try JSONSerialization.jsonObject(with: fixture("snapshot"))
        let response = try JSONSerialization.data(withJSONObject: [
            "id": "legacy", "result": ["type": "session_snapshot", "snapshot": body]
        ])
        let snapshot = try Snapshot.decode(response: response)
        #expect(snapshot.protocolVersion == 16)
        #expect(snapshot.panes.count == 6)
        // One upstream agent lacks `agent` and must be skipped individually.
        #expect(Set(snapshot.agents.map(\.paneID)) == ["w652cb9b5bdfa32:p1", "w1:p1", "w2:p1", "w3:p1"])
        let agent = try #require(snapshot.agents.first { $0.paneID == "w3:p1" })
        #expect(agent.status == .idle)
        #expect(agent.stateChangeSeq == 0)
        #expect(agent.completionSeq == nil)
        #expect(agent.stateLabels.isEmpty)
        #expect(agent.cwd == "/Users/demo/projects/notchagent")
    }

    @Test(arguments: ["pane_id", "tab_id", "workspace_id", "agent"])
    func skipsOnlyAgentMissingRequiredField(_ field: String) throws {
        var invalid = minimalAgent("invalid")
        invalid.removeValue(forKey: field)
        let result = try Snapshot.decode(response: snapshotResponse(agents: [invalid, minimalAgent("valid")]))
        #expect(result.agents.map(\.paneID) == ["valid"])
    }

    @Test(arguments: ["pane_id", "tab_id", "workspace_id"])
    func skipsOnlyPaneMissingRequiredField(_ field: String) throws {
        let valid = ["pane_id": "valid", "tab_id": "t", "workspace_id": "w"]
        var invalid = valid
        invalid.removeValue(forKey: field)
        let result = try Snapshot.decode(response: snapshotResponse(panes: [invalid, valid]))
        #expect(result.panes == [PaneInfo(paneID: "valid", tabID: "t", workspaceID: "w")])
    }

    @Test func absentOptionalFields() throws {
        let result = try Snapshot.decode(response: snapshotResponse(agents: [minimalAgent()]))
        let agent = try #require(result.agents.first)
        #expect(agent.status == .unknown)
        #expect(!agent.focused)
        #expect(agent.stateChangeSeq == 0)
        #expect(agent.completionSeq == nil)
        #expect(agent.stateLabels == [:])
        #expect(agent.displayAgent == nil)
        #expect(agent.name == nil)
        #expect(agent.title == nil)
        #expect(agent.cwd == nil)
    }

    @Test(arguments: ["idle", "working", "blocked", "done", "future-status"])
    func statuses(_ raw: String) throws {
        var input = minimalAgent()
        input["agent_status"] = raw
        let result = try Snapshot.decode(response: snapshotResponse(agents: [input]))
        #expect(result.agents.first?.status == AgentStatus(rawValue: raw) ?? .unknown)
    }

    @Test func optionalMetadataAndForegroundDirectory() throws {
        var input = minimalAgent()
        input.merge(["display_agent": "Claude Code", "name": "Reviewer", "terminal_title_stripped": "Review PR",
                     "state_change_seq": UInt64(4_294_967_300), "completion_seq": 8,
                     "state_labels": ["blocked": "Approve"], "focused": true,
                     "foreground_cwd": "/work/current", "cwd": "/work/old"]) { _, new in new }
        let agent = try #require(Snapshot.decode(response: snapshotResponse(agents: [input])).agents.first)
        #expect(agent.displayAgent == "Claude Code")
        #expect(agent.name == "Reviewer")
        #expect(agent.title == "Review PR")
        #expect(agent.stateChangeSeq == 4_294_967_300)
        #expect(agent.completionSeq == 8)
        #expect(agent.stateLabels == ["blocked": "Approve"])
        #expect(agent.focused)
        #expect(agent.cwd == "/work/current")
    }

    @Test func metadataTitleOverridesTerminalTitle() throws {
        var input = minimalAgent()
        input["title"] = "Metadata task"
        input["terminal_title_stripped"] = "Terminal task"
        #expect(try Snapshot.decode(response: snapshotResponse(agents: [input])).agents.first?.title == "Metadata task")
        input["title"] = NSNull()
        #expect(try Snapshot.decode(response: snapshotResponse(agents: [input])).agents.first?.title == "Terminal task")
    }

    @Test func directoryFallback() throws {
        var input = minimalAgent()
        input["cwd"] = "/work/fallback"
        input["foreground_cwd"] = NSNull()
        #expect(try Snapshot.decode(response: snapshotResponse(agents: [input])).agents.first?.cwd == "/work/fallback")
    }
}
