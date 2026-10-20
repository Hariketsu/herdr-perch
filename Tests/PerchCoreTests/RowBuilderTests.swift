import Foundation
import Testing
import PerchCore

@Suite struct RowBuilderTests {
    let now = Date(timeIntervalSince1970: 100)

    @Test func titlePriorityAndAgentLabel() throws {
        var agent = testAgent()
        agent.name = "Named task"
        agent.title = "Terminal task"
        agent.displayAgent = "Custom Claude"
        var clock = StatusClock()
        func row(_ agent: AgentInfo) throws -> AgentRow {
            try #require(RowBuilder.rows([testSession(agents: [agent])], clock: &clock, now: now).first)
        }
        #expect(try row(agent).title == "Named task")
        #expect(try row(agent).agentLabel == "Custom Claude")
        agent.name = nil
        #expect(try row(agent).title == "Terminal task")
        agent.title = nil
        #expect(try row(agent).title == "Custom Claude")
        agent.displayAgent = nil
        #expect(try row(agent).title == "claude")
        #expect(try row(agent).agentLabel == "Claude")
        agent.agent = "future-agent"
        #expect(try row(agent).title == "future-agent")
        #expect(try row(agent).agentLabel == "future-agent")
    }

    @Test(arguments: [("claude", "Claude"), ("codex", "Codex"), ("omp", "OMP"), ("opencode", "OpenCode")])
    func knownAgentLabels(_ raw: String, _ expected: String) throws {
        var agent = testAgent()
        agent.agent = raw
        var clock = StatusClock()
        let row = try #require(RowBuilder.rows([testSession(agents: [agent])], clock: &clock, now: now).first)
        #expect(row.agentLabel == expected)
    }

    @Test func subtitleUsesRawStatusLabelThenTaskTitleAndSuppressesDuplicates() throws {
        var agent = testAgent(status: .done)
        agent.name = "Named task"
        agent.title = "Task detail"
        agent.stateLabels = ["done": "Ready for review", "finished": "Wrong display-state key"]
        var clock = StatusClock()
        func row(_ agent: AgentInfo) throws -> AgentRow {
            try #require(RowBuilder.rows([testSession(agents: [agent])], clock: &clock, now: now).first)
        }
        #expect(try row(agent).subtitle == "Ready for review")
        agent.stateLabels = [:]
        #expect(try row(agent).subtitle == "Task detail")
        agent.name = nil
        #expect(try row(agent).subtitle == nil)
        agent.stateLabels = ["done": "Task detail"]
        #expect(try row(agent).subtitle == nil)
        agent.title = nil
        agent.stateLabels = [:]
        #expect(try row(agent).subtitle == nil)
    }

    @Test func projectsIdentityUnknownAndStaleness() throws {
        var agent = testAgent(status: .unknown)
        agent.cwd = "/work/sample-project"
        var clock = StatusClock()
        let row = try #require(RowBuilder.rows([
            testSession("session-a", agents: [agent], health: .stale(since: now))
        ], clock: &clock, now: now).first)
        #expect(row.project == "sample-project")
        #expect(row.id == AgentRef(session: "session-a", paneID: "p1"))
        #expect(row.session == "session-a")
        #expect(row.workspaceID == "w1")
        #expect(row.tabID == "t1")
        #expect(row.status == .idle)
        #expect(row.isUnrecognized)
        #expect(row.isStale)
        #expect(row.since == now)
        #expect(!row.showsSessionTag)
        let live = try #require(RowBuilder.rows([testSession()], clock: &clock, now: now).first)
        #expect(live.project == nil)
        #expect(!live.isStale)
        #expect(!live.isUnrecognized)
    }

    @Test func multipleSessionsIncludingHealthOnlyPlaceholderShowTags() {
        var clock = StatusClock()
        let placeholder = SessionState(endpoint: SessionEndpoint(name: "old", socketPath: "/tmp/old.sock", isDefault: false),
                                       health: .updateRequired(protocolVersion: 21))
        let rows = RowBuilder.rows([testSession("a"), testSession("b"), placeholder], clock: &clock, now: now)
        #expect(rows.count == 2)
        #expect(rows.allSatisfy { $0.showsSessionTag })
        #expect(RowBuilder.rows([testSession("a"), placeholder], clock: &clock, now: now).first?.showsSessionTag == true)
        #expect(RowBuilder.rows([placeholder], clock: &clock, now: now).isEmpty)
        #expect(RowBuilder.rows([], clock: &clock, now: now).isEmpty)
    }

    @Test func urgencyThenNewestThenSessionThenPaneIsStable() {
        let agents = [testAgent("idle", status: .idle), testAgent("work", status: .working),
                      testAgent("done", status: .done), testAgent("old", status: .blocked),
                      testAgent("new", status: .blocked)]
        let a = testSession("a", agents: agents)
        let b = testSession("b", agents: [testAgent("p2", status: .blocked), testAgent("p1", status: .blocked)])
        var clock = StatusClock()
        _ = clock.observe(AgentRef(session: "a", paneID: "old"), seq: 1, now: now.addingTimeInterval(-20))
        let rows = RowBuilder.rows([b, a], clock: &clock, now: now)
        #expect(rows.map(\.id) == [
            AgentRef(session: "a", paneID: "new"), AgentRef(session: "b", paneID: "p1"),
            AgentRef(session: "b", paneID: "p2"), AgentRef(session: "a", paneID: "old"),
            AgentRef(session: "a", paneID: "done"), AgentRef(session: "a", paneID: "work"), AgentRef(session: "a", paneID: "idle")
        ])
        var reordered = a
        reordered.snapshot?.agents.reverse()
        #expect(RowBuilder.rows([reordered, b], clock: &clock, now: now.addingTimeInterval(1)) == rows)
    }

    @Test func sequenceControlsSinceAndRemovedRowsForgetTheirClock() throws {
        var clock = StatusClock()
        var session = testSession(agents: [testAgent(status: .done)])
        let first = RowBuilder.rows([session], clock: &clock, now: now)
        session.snapshot?.agents[0].status = .idle // focus clears done without advancing seq in Herdr
        #expect(RowBuilder.rows([session], clock: &clock, now: now.addingTimeInterval(1)).first?.since == first.first?.since)
        session.snapshot?.agents[0].stateChangeSeq = 2
        let later = now.addingTimeInterval(2)
        #expect(RowBuilder.rows([session], clock: &clock, now: later).first?.since == later)
        _ = RowBuilder.rows([], clock: &clock, now: later)
        #expect(RowBuilder.rows([session], clock: &clock, now: later.addingTimeInterval(1)).first?.since == later.addingTimeInterval(1))
    }
}
