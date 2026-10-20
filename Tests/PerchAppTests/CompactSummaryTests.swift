import Foundation
import Testing
import PerchCore
@testable import PerchApp

@Suite struct CompactSummaryTests {
    private func rows(_ statuses: [DisplayStatus], stale: Bool = false) -> [AgentRow] {
        statuses.enumerated().map { index, status in
            AgentRow(id: AgentRef(session: "test", paneID: "p\(index)"), status: status,
                     title: "Task", agentLabel: "Claude", since: Date(timeIntervalSince1970: 100),
                     session: "test", isStale: stale, workspaceID: "w1", tabID: "t1")
        }
    }

    @Test func emptySummary() {
        let summary = CompactSummary.make([])
        #expect(summary.birdStatus == nil)
        #expect(summary.dots.isEmpty)
        #expect(summary.overflow == 0)
        #expect(summary.counts.isEmpty)
        #expect(summary.total == 0)
        #expect(summary.allStale == false)
    }

    @Test func mostUrgentStatusWins() {
        #expect(CompactSummary.make(rows([.idle])).birdStatus == .idle)
        #expect(CompactSummary.make(rows([.idle, .working])).birdStatus == .working)
        #expect(CompactSummary.make(rows([.idle, .working, .finished])).birdStatus == .finished)
        #expect(CompactSummary.make(rows([.idle, .working, .finished, .blocked])).birdStatus == .blocked)
    }

    @Test func dotsKeepInputOrderAndCapAtSixWhileCountsIncludeOverflow() {
        let summary = CompactSummary.make(rows([.idle, .working, .blocked, .finished, .idle, .working, .blocked, .idle, .blocked]))
        #expect(CompactSummary.maxDots == 6)
        #expect(summary.dots == [.idle, .working, .blocked, .finished, .idle, .working])
        #expect(summary.overflow == 3)
        #expect(summary.total == 9)
        #expect(summary.counts == [.idle: 3, .working: 2, .blocked: 3, .finished: 1])
    }

    @Test(arguments: [(0, 0), (5, 0), (6, 0), (7, 1)])
    func overflowBoundary(_ total: Int, _ overflow: Int) {
        let summary = CompactSummary.make(rows(Array(repeating: .working, count: total)))
        #expect(summary.overflow == overflow)
        #expect(summary.total == total)
    }

    @Test func countsOmitZeroEntries() {
        let summary = CompactSummary.make(rows([.working, .blocked, .working]))
        #expect(summary.counts == [.working: 2, .blocked: 1])
        #expect(summary.counts[.idle] == nil)
        #expect(summary.counts[.finished] == nil)
    }

    @Test func onlyAllStaleRowsProduceAllStale() {
        let stale = rows([.working, .blocked], stale: true)
        #expect(CompactSummary.make(stale).allStale)
        var mixed = stale
        mixed[0].isStale = false
        #expect(!CompactSummary.make(mixed).allStale)
        #expect(!CompactSummary.make(rows([.idle, .finished])).allStale)
    }

    @Test(arguments: [0, 1, 6, 12])
    func birdCountWingsStayThirty(_ total: Int) {
        #expect(CompactSummary.make(rows(Array(repeating: .working, count: total))).wingWidth(.birdCount) == 30)
    }

    @Test(arguments: [(0, 40), (1, 40), (2, 42), (5, 72), (6, 82), (9, 82)])
    func dotWingFormulaAndMinimum(_ total: Int, _ expected: Int) {
        #expect(CompactSummary.make(rows(Array(repeating: .working, count: total))).wingWidth(.dots) == CGFloat(expected))
    }

    @Test func countWingsDependOnNonzeroStatusKinds() {
        #expect(CompactSummary.make([]).wingWidth(.counts) == 40)
        #expect(CompactSummary.make(rows([.working, .working])).wingWidth(.counts) == 40)
        #expect(CompactSummary.make(rows([.working, .blocked])).wingWidth(.counts) == 64)
        #expect(CompactSummary.make(rows([.working, .blocked, .finished])).wingWidth(.counts) == 88)
        #expect(CompactSummary.make(rows([.working, .blocked, .finished, .idle])).wingWidth(.counts) == 112)
    }
}
