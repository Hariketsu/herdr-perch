import Foundation
import Testing
import PerchCore

@Suite struct StatusClockTests {
    @Test func firstObservationPersistsUntilSequenceChanges() {
        var clock = StatusClock()
        let ref = AgentRef(session: "a", paneID: "p1")
        let first = Date(timeIntervalSince1970: 10)
        let later = first.addingTimeInterval(30)
        #expect(clock.observe(ref, seq: 0, now: first) == first)
        #expect(clock.observe(ref, seq: 0, now: later) == first)
        #expect(clock.observe(ref, seq: 1, now: later) == later)
        #expect(clock.observe(ref, seq: 1, now: later.addingTimeInterval(10)) == later)
    }
    @Test func samePaneInDifferentSessionsHasIndependentClock() {
        var clock = StatusClock()
        let a = AgentRef(session: "a", paneID: "p1")
        let b = AgentRef(session: "b", paneID: "p1")
        let first = Date(timeIntervalSince1970: 10)
        let later = first.addingTimeInterval(5)
        #expect(clock.observe(a, seq: 1, now: first) == first)
        #expect(clock.observe(b, seq: 1, now: later) == later)
        #expect(clock.observe(a, seq: 1, now: later) == first)
    }
    @Test func retainClearsOnlyRemovedReferences() {
        var clock = StatusClock()
        let a = AgentRef(session: "a", paneID: "p1")
        let b = AgentRef(session: "a", paneID: "p2")
        let first = Date(timeIntervalSince1970: 10)
        let later = first.addingTimeInterval(5)
        _ = clock.observe(a, seq: 1, now: first)
        _ = clock.observe(b, seq: 1, now: first)
        clock.retain(only: [a])
        #expect(clock.observe(a, seq: 1, now: later) == first)
        #expect(clock.observe(b, seq: 1, now: later) == later)
        clock.retain(only: [])
        #expect(clock.observe(a, seq: 1, now: later) == later)
    }
}
