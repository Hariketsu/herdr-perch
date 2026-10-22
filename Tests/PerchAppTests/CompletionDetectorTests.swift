import Foundation
import Testing
import PerchCore
@testable import PerchApp

@Suite struct CompletionDetectorTests {
    private func row(_ paneID: String = "p1", status: DisplayStatus,
                     since: TimeInterval = 100, stale: Bool = false) -> AgentRow {
        AgentRow(id: AgentRef(session: "test", paneID: paneID), status: status,
                 title: "Task \(paneID)", agentLabel: "Claude", since: Date(timeIntervalSince1970: since),
                 session: "test", isStale: stale, workspaceID: "w1", tabID: "t1")
    }

    @Test func firstObservationRecordsFinishedRowsWithoutFeedback() {
        var detector = CompletionDetector()
        let rows = [row(status: .finished), row("p2", status: .working)]
        #expect(detector.observe(rows) == nil)
        #expect(detector.observe(rows) == nil)
    }

    @Test func workingToFinishedReturnsCurrentIdentityAndTitle() throws {
        var detector = CompletionDetector()
        #expect(detector.observe([row(status: .working)]) == nil)
        var finished = row(status: .finished, since: 200)
        finished.title = "Completed task"
        let observed = detector.observe([finished])
        let completion = try #require(observed)
        #expect(completion.id == finished.id)
        #expect(completion.title == finished.title)
    }

    @Test func remainingFinishedDoesNotRepeatFeedback() {
        var detector = CompletionDetector()
        #expect(detector.observe([row(status: .working)]) == nil)
        var finished = row(status: .finished)
        #expect(detector.observe([finished]) == finished)
        #expect(detector.observe([finished]) == nil)
        finished.title = "Updated title"
        finished.since = Date(timeIntervalSince1970: 200)
        #expect(detector.observe([finished]) == nil)
    }

    @Test func returningToFinishedAfterIdleTriggersAgain() {
        var detector = CompletionDetector()
        let finished = row(status: .finished)
        #expect(detector.observe([finished]) == nil)
        #expect(detector.observe([row(status: .idle)]) == nil)
        #expect(detector.observe([finished]) == finished)
        #expect(detector.observe([finished]) == nil)
    }

    @Test func disappearingFinishedRowCanTriggerOnReturn() {
        var detector = CompletionDetector()
        let finished = row(status: .finished)
        #expect(detector.observe([finished]) == nil)
        #expect(detector.observe([]) == nil)
        #expect(detector.observe([finished]) == finished)
        #expect(detector.observe([finished]) == nil)
    }

    @Test(arguments: [(100.0, 200.0, "p2"), (200.0, 100.0, "p1"), (100.0, 100.0, "p1")])
    func simultaneousCompletionsPreferNewestThenInputOrder(_ firstSince: TimeInterval,
                                                         _ secondSince: TimeInterval,
                                                         _ expectedPaneID: String) throws {
        var detector = CompletionDetector()
        #expect(detector.observe([row(status: .working), row("p2", status: .working)]) == nil)
        let finished = [row(status: .finished, since: firstSince), row("p2", status: .finished, since: secondSince)]
        let observed = detector.observe(finished)
        let completion = try #require(observed)
        #expect(completion.id == AgentRef(session: "test", paneID: expectedPaneID))
        #expect(detector.observe(finished) == nil)
    }

    @Test func equalCompletionTimesFollowRowsWhenOrderIsReversed() {
        var detector = CompletionDetector()
        #expect(detector.observe([]) == nil)
        let first = row("p2", status: .finished)
        let second = row(status: .finished)
        #expect(detector.observe([first, second]) == first)
        #expect(detector.observe([second, first]) == nil)
    }

    @Test(arguments: [DisplayStatus.working, .finished])
    func staleFinishedRowsTriggerOnlyOnceAfterRecovery(_ initialStatus: DisplayStatus) {
        var detector = CompletionDetector()
        #expect(detector.observe([row(status: initialStatus)]) == nil)
        #expect(detector.observe([row(status: .finished, stale: true)]) == nil)
        #expect(detector.observe([row(status: .finished, stale: true)]) == nil)
        let recovered = row(status: .finished)
        #expect(detector.observe([recovered]) == recovered)
        #expect(detector.observe([recovered]) == nil)
    }

    @Test func newlyAppearingFinishedRowTriggersAfterBaseline() {
        var detector = CompletionDetector()
        let existing = row(status: .finished, since: 300)
        #expect(detector.observe([existing]) == nil)
        let added = row("p2", status: .finished, since: 100)
        #expect(detector.observe([existing, added]) == added)
        #expect(detector.observe([existing, added]) == nil)
    }

    @Test func emptyFirstObservationStillEstablishesBaseline() {
        var detector = CompletionDetector()
        #expect(detector.observe([]) == nil)
        let finished = row(status: .finished)
        #expect(detector.observe([finished]) == finished)
        #expect(detector.observe([finished]) == nil)
    }
}
