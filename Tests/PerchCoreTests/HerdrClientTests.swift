import Darwin
import Foundation
import Testing
import PerchCore

private enum RequestOperation: String, CaseIterable, Sendable {
    case ping, snapshot, workspace, tab, pane
    func call(_ client: HerdrClient) async throws {
        switch self {
        case .ping: _ = try await client.ping()
        case .snapshot: _ = try await client.snapshot()
        case .workspace: try await client.focusWorkspace("w1")
        case .tab: try await client.focusTab("w1:t1")
        case .pane: try await client.focusPane("w1:p1")
        }
    }
}

@Suite("HerdrClient over isolated Unix sockets")
struct HerdrClientTests {
    @Test func pingAndFreshConnectionPerRequest() async throws {
        let log = RequestLog()
        let server = try FakeHerdrServer { request in
            log.record(request)
            return FakeReply(chunks: [request.result(["type": "pong", "version": "0.9.5", "protocol": 22])])
        }
        defer { server.stop() }
        let client = HerdrClient(socketPath: server.path, timeout: .milliseconds(400))
        for _ in 0..<3 {
            #expect(try await client.ping() == PingInfo(version: "0.9.5", protocolVersion: 22))
        }
        // Server handles precisely one request on each accepted connection.
        #expect(log.values.map(\.method) == ["ping", "ping", "ping"])
    }

    @Test func independentConcurrentRequests() async throws {
        let log = RequestLog()
        let server = try FakeHerdrServer { request in
            log.record(request)
            return FakeReply(chunks: [request.result(["type": "pong", "version": "0.9.5", "protocol": 22])])
        }
        defer { server.stop() }
        let client = HerdrClient(socketPath: server.path, timeout: .seconds(1))
        try await withThrowingTaskGroup(of: PingInfo.self) { group in
            for _ in 0..<10 { group.addTask { try await client.ping() } }
            for try await result in group { #expect(result.protocolVersion == 22) }
        }
        #expect(log.values.count == 10)
    }

    @Test(arguments: [21, 22, 23])
    func protocolGate(_ version: Int) async throws {
        let server = try FakeHerdrServer { request in
            FakeReply(chunks: [request.result(["type": "pong", "version": "fixture", "protocol": version])])
        }
        defer { server.stop() }
        let client = HerdrClient(socketPath: server.path, timeout: .milliseconds(400))
        #expect(HerdrClient.minimumProtocol == 22)
        if version < 22 {
            await #expect(throws: HerdrError.unsupportedProtocol(21)) { try await client.ping() }
        } else {
            #expect(try await client.ping() == PingInfo(version: "fixture", protocolVersion: version))
        }
    }

    @Test func recordedSnapshotRoundTrip() async throws {
        let response = try fixture("snapshot-0.9.5")
        let log = RequestLog()
        let server = try FakeHerdrServer { request in
            log.record(request)
            let envelope = try! JSONSerialization.jsonObject(with: response) as! [String: Any]
            return FakeReply(chunks: [request.result(envelope["result"] as! [String: Any])])
        }
        defer { server.stop() }
        let result = try await HerdrClient(socketPath: server.path, timeout: .milliseconds(400)).snapshot()
        #expect(result.protocolVersion == 22)
        #expect(result.panes.count == 3)
        #expect(Set(result.agents.map(\.status)) == [.working, .blocked, .done])
        #expect(log.values.map(\.method) == ["session.snapshot"])
    }

    @Test func focusMethodsSendTargetsAndUseNewConnections() async throws {
        let log = RequestLog()
        // Response shapes verified against Herdr 0.9.5 `herdr api schema --json`.
        let server = try FakeHerdrServer { request in
            log.record(request)
            let body: [String: Any]
            switch request.method {
            case "workspace.focus": body = ["type": "workspace_focused", "workspace_id": "w1"]
            case "tab.focus": body = ["type": "tab_focused", "workspace_id": "w1", "tab_id": "w1:t1"]
            case "pane.focus": body = ["type": "pane_focused", "workspace_id": "w1", "pane_id": "w1:p1"]
            default: return FakeReply(chunks: [request.error("invalid_request", "unexpected method")])
            }
            return FakeReply(chunks: [request.result(body)])
        }
        defer { server.stop() }
        let client = HerdrClient(socketPath: server.path, timeout: .milliseconds(400))
        try await client.focusWorkspace("w1")
        try await client.focusTab("w1:t1")
        try await client.focusPane("w1:p1")
        let requests = log.values
        #expect(requests.map(\.method) == ["workspace.focus", "tab.focus", "pane.focus"])
        #expect(requests.count == 3)
        guard requests.count == 3 else { return }
        #expect(requests[0].params["workspace_id"] as? String == "w1")
        #expect(requests[1].params["tab_id"] as? String == "w1:t1")
        #expect(requests[2].params["pane_id"] as? String == "w1:p1")
    }

    @Test(arguments: RequestOperation.allCases)
    private func serverError(_ operation: RequestOperation) async throws {
        let server = try FakeHerdrServer { request in
            FakeReply(chunks: [request.error("invalid_request", "fixture error")])
        }
        defer { server.stop() }
        await #expect(throws: HerdrError.server(code: "invalid_request", message: "fixture error")) {
            try await operation.call(HerdrClient(socketPath: server.path, timeout: .milliseconds(400)))
        }
    }

    @Test(arguments: RequestOperation.allCases)
    private func timeoutOnSilentPeer(_ operation: RequestOperation) async throws {
        let server = try FakeHerdrServer { _ in FakeReply(holdOpen: 1000) }
        defer { server.stop() }
        let start = ContinuousClock.now
        await #expect(throws: HerdrError.timeout) {
            try await operation.call(HerdrClient(socketPath: server.path, timeout: .milliseconds(80)))
        }
        #expect(ContinuousClock.now - start < .seconds(2))
    }

    @Test(arguments: RequestOperation.allCases)
    private func incompleteLineThenClose(_ operation: RequestOperation) async throws {
        let server = try FakeHerdrServer { _ in FakeReply(chunks: [Data("{\"id\":".utf8)]) }
        defer { server.stop() }
        await #expect(throws: HerdrError.closedByPeer) {
            try await operation.call(HerdrClient(socketPath: server.path, timeout: .milliseconds(400)))
        }
    }

    @Test(arguments: RequestOperation.allCases)
    private func malformedJSON(_ operation: RequestOperation) async throws {
        let server = try FakeHerdrServer { _ in FakeReply(chunks: [Data("not-json\n".utf8)]) }
        defer { server.stop() }
        await #expect(throws: HerdrError.malformedResponse) {
            try await operation.call(HerdrClient(socketPath: server.path, timeout: .milliseconds(400)))
        }
    }

    @Test(arguments: RequestOperation.allCases)
    private func nonexistentSocket(_ operation: RequestOperation) async {
        let path = "/tmp/missing-\(UUID().uuidString.prefix(8))/herdr.sock"
        await #expect(throws: HerdrError.connectFailed(ENOENT)) {
            try await operation.call(HerdrClient(socketPath: path, timeout: .milliseconds(400)))
        }
    }

    @Test(arguments: RequestOperation.allCases)
    private func pathTooLong(_ operation: RequestOperation) async {
        // 104 bytes including a multi-byte character; checks bytes rather than Swift character count.
        let path = "/tmp/" + String(repeating: "a", count: 97) + "é"
        #expect(path.utf8.count == 104)
        await #expect(throws: HerdrError.connectFailed(ENAMETOOLONG)) {
            try await operation.call(HerdrClient(socketPath: path, timeout: .milliseconds(400)))
        }
    }

    @Test func refusedConnection() async throws {
        let root = URL(fileURLWithPath: "/tmp/pr-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EMFILE) }
        defer { Darwin.close(fd) }
        let path = root.appendingPathComponent("herdr.sock").path
        try FakeHerdrServer.bindSocket(fd, path: path)
        await #expect(throws: HerdrError.connectFailed(ECONNREFUSED)) {
            try await HerdrClient(socketPath: path, timeout: .milliseconds(400)).ping()
        }
    }

    @Test func earlyPeerCloseDoesNotKillProcessWithSIGPIPE() async throws {
        let server = try FakeHerdrServer(closeBeforeRequest: true) { _ in FakeReply() }
        defer { server.stop() }
        // A request larger than the socket send buffer exercises writing after peer closure.
        let subscriptions = (0..<12_000).map {
            Subscription(type: "pane.agent_status_changed", paneID: "w1:p\($0)")
        }
        await #expect(throws: HerdrError.closedByPeer) {
            for try await _ in HerdrClient(socketPath: server.path, timeout: .seconds(1)).subscribe(subscriptions) {
                Issue.record("A peer closed before reading cannot acknowledge subscriptions")
            }
        }
    }

    @Test func fragmentedLargeSnapshot() async throws {
        let title = String(repeating: "任务🌿", count: 40_000)
        #expect(title.utf8.count >= 256 * 1024)
        let server = try FakeHerdrServer { request in
            var agent = minimalAgent()
            agent["terminal_title_stripped"] = title
            let line = request.result(["type": "session_snapshot", "snapshot": [
                "protocol": 22, "agents": [agent], "panes": []
            ]])
            let chunks = stride(from: 0, to: line.count, by: 4093).map {
                line.subdata(in: $0..<min($0 + 4093, line.count))
            }
            return FakeReply(chunks: chunks, delayBetweenChunks: 1)
        }
        defer { server.stop() }
        let snapshot = try await HerdrClient(socketPath: server.path, timeout: .seconds(2)).snapshot()
        #expect(snapshot.agents.first?.title == title)
    }
}
