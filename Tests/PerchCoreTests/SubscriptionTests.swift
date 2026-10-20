import Darwin
import Foundation
import Testing
import PerchCore

@Suite("Subscription stream contract")
struct SubscriptionTests {
    @Test func startedThenEveryEventAndPaneTargetOnWire() async throws {
        let log = RequestLog()
        let server = try FakeHerdrServer { request in
            log.record(request)
            // Ack shape comes from /tmp/perch-exp/global.log and Herdr 0.9.5 schema.
            return FakeReply(chunks: [
                request.result(["type": "subscription_started"]),
                FakeRequest.line(["event": "pane.agent_status_changed", "data": ["pane_id": "w1:p1"]]),
                FakeRequest.line(["event": "pane_focused", "data": [:]]),
                FakeRequest.line(["event": "future.event", "data": ["ignored": true]])
            ])
        }
        defer { server.stop() }
        let stream = HerdrClient(socketPath: server.path, timeout: .milliseconds(400)).subscribe([
            Subscription(type: "pane.created"), Subscription(type: "pane.agent_status_changed", paneID: "w1:p1")
        ])
        var signals: [EventSignal] = []
        await #expect(throws: HerdrError.closedByPeer) {
            for try await signal in stream { signals.append(signal) }
        }
        #expect(signals == [.started, .event, .event, .event])
        let request = try #require(log.values.first)
        #expect(request.method == "events.subscribe")
        let entries = request.params["subscriptions"] as? [[String: Any]] ?? []
        #expect(entries.count == 2)
        #expect(entries.contains { $0["type"] as? String == "pane.created" && $0["pane_id"] == nil })
        #expect(entries.contains {
            $0["type"] as? String == "pane.agent_status_changed" && $0["pane_id"] as? String == "w1:p1"
        })
    }

    @Test(arguments: [true, false])
    func eventsLostEndsStream(_ afterStarted: Bool) async throws {
        let server = try FakeHerdrServer { request in
            var chunks = afterStarted ? [request.result(["type": "subscription_started"])] : []
            chunks.append(request.error("events_lost", "too slow"))
            return FakeReply(chunks: chunks)
        }
        defer { server.stop() }
        var signals: [EventSignal] = []
        await #expect(throws: HerdrError.eventsLost) {
            for try await signal in HerdrClient(socketPath: server.path, timeout: .milliseconds(400)).subscribe([]) {
                signals.append(signal)
            }
        }
        #expect(signals == (afterStarted ? [.started] : []))
    }

    @Test(arguments: [true, false])
    func invalidRequestEndsStream(_ afterStarted: Bool) async throws {
        let server = try FakeHerdrServer { request in
            var chunks = afterStarted ? [request.result(["type": "subscription_started"])] : []
            chunks.append(request.error("invalid_request", "pane gone"))
            return FakeReply(chunks: chunks)
        }
        defer { server.stop() }
        var signals: [EventSignal] = []
        await #expect(throws: HerdrError.server(code: "invalid_request", message: "pane gone")) {
            for try await signal in HerdrClient(socketPath: server.path, timeout: .milliseconds(400)).subscribe([]) {
                signals.append(signal)
            }
        }
        #expect(signals == (afterStarted ? [.started] : []))
    }

    @Test func startedTimeout() async throws {
        let server = try FakeHerdrServer { _ in FakeReply(holdOpen: 1000) }
        defer { server.stop() }
        let start = ContinuousClock.now
        await #expect(throws: HerdrError.timeout) {
            for try await _ in HerdrClient(socketPath: server.path, timeout: .milliseconds(80)).subscribe([]) {
                Issue.record("A silent server must never produce a signal")
            }
        }
        #expect(ContinuousClock.now - start < .seconds(2))
    }

    @Test func timeoutStopsApplyingAfterStarted() async throws {
        let server = try FakeHerdrServer { request in
            FakeReply(chunks: [request.result(["type": "subscription_started"]),
                               FakeRequest.line(["event": "anything", "data": [:]])], delayBetweenChunks: 250)
        }
        defer { server.stop() }
        var signals: [EventSignal] = []
        await #expect(throws: HerdrError.closedByPeer) {
            for try await signal in HerdrClient(socketPath: server.path, timeout: .milliseconds(100)).subscribe([]) {
                signals.append(signal)
            }
        }
        #expect(signals == [.started, .event])
    }

    @Test func closesBeforeStarted() async throws {
        let server = try FakeHerdrServer { _ in FakeReply(chunks: [Data("{\"result\":".utf8)]) }
        defer { server.stop() }
        await #expect(throws: HerdrError.closedByPeer) {
            for try await _ in HerdrClient(socketPath: server.path, timeout: .milliseconds(400)).subscribe([]) {
                Issue.record("An incomplete line must not produce a signal")
            }
        }
    }

    @Test func malformedStartedLine() async throws {
        let server = try FakeHerdrServer { _ in FakeReply(chunks: [Data("not-json\n".utf8)]) }
        defer { server.stop() }
        await #expect(throws: HerdrError.malformedResponse) {
            for try await _ in HerdrClient(socketPath: server.path, timeout: .milliseconds(400)).subscribe([]) {
                Issue.record("Malformed JSON must not produce a signal")
            }
        }
    }

    @Test func missingSocketAndOverlongPath() async {
        let cases: [(String, HerdrError)] = [
            ("/tmp/missing-\(UUID().uuidString.prefix(8))/herdr.sock", .connectFailed(ENOENT)),
            ("/tmp/" + String(repeating: "x", count: 104), .connectFailed(ENAMETOOLONG))
        ]
        for (path, error) in cases {
            await #expect(throws: error) {
                for try await _ in HerdrClient(socketPath: path, timeout: .milliseconds(400)).subscribe([]) {
                    Issue.record("Connection failure must not produce a signal")
                }
            }
        }
    }
}
