import Foundation
import Testing
import PerchCore
@testable import PerchApp

@Suite struct HerdrStatusTests {
    private func session(_ name: String, health: SessionHealth) -> SessionState {
        SessionState(endpoint: SessionEndpoint(name: name, socketPath: "/tmp/perch-test-\(name).sock", isDefault: false),
                     snapshot: nil, health: health)
    }

    @Test func noSessionsIsOffline() {
        let status = HerdrStatus.make([])
        #expect(status.level == .offline)
        #expect(status.title == "Herdr isn’t running")
    }

    @Test func updateRequiredNeedsAttention() {
        let status = HerdrStatus.make([session("old", health: .updateRequired(protocolVersion: 21))])
        #expect(status.level == .attention)
        #expect(status.title == "Herdr update required (0.9.5 or later)")
    }

    @Test func staleSessionIsReconnecting() {
        let status = HerdrStatus.make([session("stale", health: .stale(since: Date(timeIntervalSince1970: 100)))])
        #expect(status.level == .attention)
        #expect(status.title == "Reconnecting to Herdr…")
    }

    @Test(arguments: [(1, "Connected · 1 session"), (2, "Connected · 2 sessions"), (5, "Connected · 5 sessions")])
    func liveSessionsUseCountAndCorrectPlural(_ count: Int, _ title: String) {
        let sessions = (0..<count).map { session("live-\($0)", health: .live) }
        let status = HerdrStatus.make(sessions)
        #expect(status.level == .connected)
        #expect(status.title == title)
    }

    @Test(arguments: [false, true])
    func updateRequiredTakesPrecedenceOverStaleAndLive(_ reversed: Bool) {
        let sessions = [session("live", health: .live),
                        session("stale", health: .stale(since: Date(timeIntervalSince1970: 100))),
                        session("old", health: .updateRequired(protocolVersion: 21))]
        let status = HerdrStatus.make(reversed ? Array(sessions.reversed()) : sessions)
        #expect(status.level == .attention)
        #expect(status.title == "Herdr update required (0.9.5 or later)")
    }

    @Test(arguments: [false, true])
    func staleTakesPrecedenceOverLive(_ reversed: Bool) {
        let sessions = [session("live", health: .live),
                        session("stale", health: .stale(since: Date(timeIntervalSince1970: 100)))]
        let status = HerdrStatus.make(reversed ? Array(sessions.reversed()) : sessions)
        #expect(status.level == .attention)
        #expect(status.title == "Reconnecting to Herdr…")
    }
}
