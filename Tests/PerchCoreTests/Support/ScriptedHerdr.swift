import Foundation
import PerchCore

struct SubscriptionAttempt: Sendable {
    let request: FakeRequest
    let at: ContinuousClock.Instant
    let stream: FakeStream?
    var plan: Set<Subscription> {
        let entries = request.params["subscriptions"] as? [[String: Any]] ?? []
        return Set(entries.compactMap { entry in
            guard let type = entry["type"] as? String else { return nil }
            return Subscription(type: type, paneID: entry["pane_id"] as? String)
        })
    }
}

/// Mutable wire-level Herdr script. No product internals are mocked.
final class HerdrScript: @unchecked Sendable {
    private let lock = NSLock()
    private var currentSnapshot = testSnapshot()
    private var snapshotError: (String, String)?
    private var pingError: (String, String)?
    private var protocolVersion = 22
    private var queuedSubscriptionErrors: [(String, String)] = []
    private var attempts: [SubscriptionAttempt] = []
    private var snapshots = 0

    var snapshotCount: Int { lock.withLock { snapshots } }
    var subscriptions: [SubscriptionAttempt] { lock.withLock { attempts } }
    func setSnapshot(_ snapshot: Snapshot) { lock.withLock { currentSnapshot = snapshot } }
    func failSnapshots(_ error: (String, String)?) { lock.withLock { snapshotError = error } }
    func failPings(_ error: (String, String)?) { lock.withLock { pingError = error } }
    func setProtocol(_ version: Int) { lock.withLock { protocolVersion = version } }
    func rejectNextSubscriptions(_ errors: [(String, String)]) { lock.withLock { queuedSubscriptionErrors = errors } }

    func reply(_ request: FakeRequest) -> FakeReply {
        lock.withLock {
            switch request.method {
            case "ping":
                if let (code, message) = pingError { return FakeReply(chunks: [request.error(code, message)]) }
                return FakeReply(chunks: [request.result(["type": "pong", "version": "0.9.5", "protocol": protocolVersion])])
            case "session.snapshot":
                snapshots += 1
                if let (code, message) = snapshotError { return FakeReply(chunks: [request.error(code, message)]) }
                return FakeReply(chunks: [request.result(Self.encode(currentSnapshot))])
            case "events.subscribe":
                if !queuedSubscriptionErrors.isEmpty {
                    let (code, message) = queuedSubscriptionErrors.removeFirst()
                    attempts.append(SubscriptionAttempt(request: request, at: .now, stream: nil))
                    return FakeReply(chunks: [request.error(code, message)])
                }
                let stream = FakeStream()
                attempts.append(SubscriptionAttempt(request: request, at: .now, stream: stream))
                return FakeReply(chunks: [request.result(["type": "subscription_started"])], stream: stream)
            default:
                return FakeReply(chunks: [request.error("invalid_request", "unexpected method")])
            }
        }
    }

    func event() {
        let streams = lock.withLock { attempts.compactMap(\.stream) }
        // Deliberately contradictory payload: only the next snapshot is authoritative.
        let line = FakeRequest.line(["event": "future.event", "data": ["agent_status": "idle"]])
        streams.forEach { $0.send(line) }
    }

    func endSubscriptions(error: (String, String)? = nil) {
        let current = subscriptions
        for attempt in current {
            if let (code, message) = error { attempt.stream?.send(attempt.request.error(code, message)) }
            attempt.stream?.finish()
        }
    }

    private static func encode(_ snapshot: Snapshot) -> [String: Any] {
        let panes = snapshot.panes.map { ["pane_id": $0.paneID, "tab_id": $0.tabID, "workspace_id": $0.workspaceID] }
        let agents: [[String: Any]] = snapshot.agents.map { agent in
            var value: [String: Any] = ["pane_id": agent.paneID, "tab_id": agent.tabID, "workspace_id": agent.workspaceID,
                                       "agent": agent.agent, "agent_status": agent.status.rawValue,
                                       "state_change_seq": agent.stateChangeSeq, "focused": agent.focused,
                                       "state_labels": agent.stateLabels]
            value["title"] = agent.title
            value["name"] = agent.name
            value["display_agent"] = agent.displayAgent
            value["completion_seq"] = agent.completionSeq
            value["cwd"] = agent.cwd
            return value
        }
        return ["type": "session_snapshot", "snapshot": ["protocol": snapshot.protocolVersion, "panes": panes, "agents": agents]]
    }
}

final class ScriptedHerdr: Sendable {
    let script: HerdrScript
    let server: FakeHerdrServer
    init(root: URL? = nil) throws {
        let script = HerdrScript()
        self.script = script
        self.server = try FakeHerdrServer(root: root) { script.reply($0) }
    }
    var endpoint: SessionEndpoint { SessionEndpoint(name: "test", socketPath: server.path, isDefault: false) }
    var client: HerdrClient { HerdrClient(socketPath: server.path, timeout: .milliseconds(150)) }
    func stop() { server.stop() }
}

final class StateLog<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Value] = []
    func append(_ value: Value) { lock.withLock { storage.append(value) } }
    var values: [Value] { lock.withLock { storage } }
    var last: Value? { lock.withLock { storage.last } }
}

final class ManualDate: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 100)
    func now() -> Date { lock.withLock { value } }
    func advance(_ seconds: TimeInterval) { lock.withLock { value.addTimeInterval(seconds) } }
}
