import Foundation
import Testing
import PerchCore

@Suite struct SessionRuntimeTests {
    private func started(_ server: ScriptedHerdr, log: StateLog<SessionState>) async -> SessionRuntime {
        let runtime = SessionRuntime(endpoint: server.endpoint, client: server.client, onChange: { log.append($0) })
        await runtime.start()
        _ = await eventually { server.script.snapshotCount >= 2 && !server.script.subscriptions.isEmpty && log.last?.snapshot != nil }
        return runtime
    }

    @Test func firstStartReadsSnapshotAndPublishesLiveState() async throws {
        let server = try ScriptedHerdr()
        defer { server.stop() }
        let log = StateLog<SessionState>()
        let runtime = await started(server, log: log)
        let state = await runtime.state
        #expect(state.endpoint == server.endpoint)
        #expect(state.snapshot == testSnapshot())
        #expect(state.health == .live)
        #expect(log.last?.snapshot == testSnapshot())
        #expect(server.script.subscriptions.first?.plan == SubscriptionPlan.make(for: testSnapshot()))
        await runtime.stop()
    }

    @Test func eventRefreshesFromSnapshotWithinHalfSecond() async throws {
        let server = try ScriptedHerdr()
        defer { server.stop() }
        let log = StateLog<SessionState>()
        let runtime = await started(server, log: log)
        let updated = testSnapshot([testAgent(status: .blocked, seq: 2)])
        server.script.setSnapshot(updated)
        let start = ContinuousClock.now
        server.script.event()
        _ = await eventually(within: .milliseconds(500)) { log.last?.snapshot == updated }
        #expect(ContinuousClock.now - start < .milliseconds(500))
        #expect(log.last?.snapshot?.agents.first?.status == .blocked)
        await runtime.stop()
    }

    @Test func changedPanePlanResubscribesAndRefreshesAfterStarted() async throws {
        let server = try ScriptedHerdr()
        defer { server.stop() }
        let log = StateLog<SessionState>()
        let runtime = await started(server, log: log)
        var snapshot = testSnapshot()
        // A pane without an agent must still enter the new plan.
        snapshot.panes.append(PaneInfo(paneID: "p2", tabID: "t1", workspaceID: "w1"))
        server.script.setSnapshot(snapshot)
        let before = server.script.snapshotCount
        server.script.event()
        let expected = SubscriptionPlan.make(for: snapshot)
        _ = await eventually { server.script.subscriptions.count >= 2 && server.script.subscriptions.last?.plan == expected }
        _ = await eventually { server.script.snapshotCount >= before + 2 }
        #expect(log.last?.snapshot == snapshot)
        await runtime.stop()
    }

    @Test func invalidRequestBacksOffResubscribesAndKeepsHealthLive() async throws {
        let server = try ScriptedHerdr()
        defer { server.stop() }
        let log = StateLog<SessionState>()
        let runtime = await started(server, log: log)
        let before = server.script.snapshotCount
        let attemptsBefore = server.script.subscriptions.count
        server.script.rejectNextSubscriptions([("invalid_request", "pane gone")])
        server.script.endSubscriptions(error: ("invalid_request", "pane gone"))
        _ = await eventually(within: .seconds(2)) { server.script.subscriptions.count >= attemptsBefore + 2 }
        _ = await eventually { server.script.snapshotCount > before }
        let retries = Array(server.script.subscriptions.dropFirst(attemptsBefore))
        if retries.count >= 2 {
            // 250ms exponential backoff must prevent a tight retry loop; allow scheduling jitter.
            #expect(retries[1].at - retries[0].at >= .milliseconds(200))
        }
        #expect(log.values.allSatisfy { $0.health == .live })
        #expect(await runtime.state.health == .live)
        await runtime.stop()
    }

    @Test(arguments: [true, false])
    func lostEventsOrPeerCloseResubscribesAndRefreshes(_ eventsLost: Bool) async throws {
        let server = try ScriptedHerdr()
        defer { server.stop() }
        let log = StateLog<SessionState>()
        let runtime = await started(server, log: log)
        let before = server.script.snapshotCount
        let count = server.script.subscriptions.count
        let updated = testSnapshot([testAgent(status: .done, seq: 2)])
        server.script.setSnapshot(updated)
        server.script.endSubscriptions(error: eventsLost ? ("events_lost", "missed events") : nil)
        _ = await eventually { server.script.subscriptions.count > count && server.script.snapshotCount > before && log.last?.snapshot == updated }
        #expect(log.last?.health == .live)
        await runtime.stop()
    }

    @Test func snapshotFailureRetainsLastGoodStateAndRecoveryReplacesIt() async throws {
        let server = try ScriptedHerdr()
        defer { server.stop() }
        let clock = ManualDate()
        let log = StateLog<SessionState>()
        let runtime = SessionRuntime(endpoint: server.endpoint, client: server.client, now: { clock.now() }, onChange: { log.append($0) })
        await runtime.start()
        _ = await eventually { server.script.snapshotCount >= 2 && log.last?.snapshot != nil }
        server.script.failSnapshots(("unavailable", "try again"))
        server.script.event()
        _ = await eventually { log.last?.health == .stale(since: clock.now()) }
        #expect(log.last?.snapshot == testSnapshot())
        let updated = testSnapshot([testAgent("new", status: .idle, seq: 8)])
        server.script.setSnapshot(updated)
        server.script.failSnapshots(nil)
        await runtime.requestRefresh()
        _ = await eventually { log.last?.health == .live && log.last?.snapshot == updated }
        await runtime.stop()
    }

    @Test func stopPreventsFurtherCallbacks() async throws {
        let server = try ScriptedHerdr()
        defer { server.stop() }
        let log = StateLog<SessionState>()
        let runtime = await started(server, log: log)
        await runtime.stop()
        let count = log.values.count
        server.script.setSnapshot(testSnapshot([testAgent(status: .blocked, seq: 2)]))
        server.script.event()
        await runtime.requestRefresh()
        // A bounded observation window catches work queued by an event or the stopped timer.
        try await Task.sleep(for: .milliseconds(100))
        #expect(log.values.count == count)
    }
}
