import Foundation
import Testing
import PerchCore
@testable import PerchApp

@Suite struct ListGroupsTests {
    private func row(_ paneID: String, status: DisplayStatus, since: TimeInterval = 100,
                     stale: Bool = false) -> AgentRow {
        AgentRow(id: AgentRef(session: "test", paneID: paneID), status: status,
                 title: "Task \(paneID)", agentLabel: "Claude", since: Date(timeIntervalSince1970: since),
                 session: "test", isStale: stale, workspaceID: "w1", tabID: "t1")
    }

    @Test func emptyInputHasNoGroups() {
        #expect(ListGroups.make([]).isEmpty)
    }

    @Test(arguments: [false, true])
    func groupsFollowStatusOrderAndKeepInputOrder(_ reversed: Bool) {
        let idle = [row("z-idle", status: .idle, since: 100), row("a-idle", status: .idle, since: 200)]
        let working = [row("z-working", status: .working, since: 100), row("a-working", status: .working, since: 200)]
        let finished = [row("z-finished", status: .finished, since: 100), row("a-finished", status: .finished, since: 200)]
        let blocked = [row("z-blocked", status: .blocked, since: 100), row("a-blocked", status: .blocked, since: 200)]
        let input = [idle[0], working[0], finished[0], blocked[0], working[1], blocked[1], idle[1], finished[1]]
        let groups = ListGroups.make(reversed ? Array(input.reversed()) : input)
        #expect(groups.map(\.status) == [.blocked, .finished, .working, .idle])
        #expect(groups.map(\.rows) == [blocked, finished, working, idle].map { reversed ? Array($0.reversed()) : $0 })
    }

    @Test func emptyGroupsAreOmitted() {
        let idle = row("idle", status: .idle)
        let finished = row("finished", status: .finished)
        let groups = ListGroups.make([idle, finished])
        #expect(groups.map(\.status) == [.finished, .idle])
        #expect(groups.map(\.rows) == [[finished], [idle]])
    }

    @Test(arguments: [DisplayStatus.blocked, .finished, .working, .idle])
    func staleRowsKeepTheirStatusGroup(_ status: DisplayStatus) {
        let stale = row("stale", status: status, stale: true)
        let live = row("live", status: status)
        let groups = ListGroups.make([stale, live])
        #expect(groups.map(\.status) == [status])
        #expect(groups.map(\.rows) == [[stale, live]])
    }
}
