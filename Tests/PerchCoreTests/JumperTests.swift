import Foundation
import Testing
import PerchCore

@Suite struct JumperTests {
    @Test func focusChainUsesWorkspaceTabPaneOrderAndCorrectTargets() async throws {
        let log = RequestLog()
        let server = try FakeHerdrServer { request in
            log.record(request)
            return Self.success(request)
        }
        defer { server.stop() }
        let result = await Jumper().jump(testRow(), client: HerdrClient(socketPath: server.path, timeout: .milliseconds(150)))
        #expect(result == .focused)
        let requests = log.values
        #expect(requests.map(\.method) == ["workspace.focus", "tab.focus", "pane.focus"])
        guard requests.count == 3 else { return }
        #expect(requests[0].params["workspace_id"] as? String == "w1")
        #expect(requests[1].params["tab_id"] as? String == "t1")
        #expect(requests[2].params["pane_id"] as? String == "p1")
    }

    @Test(arguments: [0, 1, 2])
    func failureStopsChainAtEachStep(_ failedStep: Int) async throws {
        let log = RequestLog()
        let methods = ["workspace.focus", "tab.focus", "pane.focus"]
        let server = try FakeHerdrServer { request in
            log.record(request)
            return request.method == methods[failedStep]
                ? FakeReply(chunks: [request.error("not_found", "target vanished")]) : Self.success(request)
        }
        defer { server.stop() }
        let result = await Jumper().jump(testRow(), client: HerdrClient(socketPath: server.path, timeout: .milliseconds(150)))
        switch result {
        case .failed: break // The failure message format is not specified.
        default: Issue.record("Expected failed outcome, got \(result)")
        }
        #expect(log.values.map(\.method) == Array(methods.prefix(failedStep + 1)).map(Optional.some))
    }

    @Test(arguments: [true, false])
    func detachInEitherCodeOrMessageNeedsAttach(_ inCode: Bool) async throws {
        let log = RequestLog()
        let server = try FakeHerdrServer { request in
            log.record(request)
            return FakeReply(chunks: [request.error(inCode ? "client_detached" : "unavailable",
                                                   inCode ? "no client" : "client detached")])
        }
        defer { server.stop() }
        #expect(await Jumper().jump(testRow(), client: HerdrClient(socketPath: server.path, timeout: .milliseconds(150))) == .needsAttach)
        #expect(log.values.map(\.method) == ["workspace.focus"])
    }

    private static func success(_ request: FakeRequest) -> FakeReply {
        let type: String
        switch request.method {
        case "workspace.focus": type = "workspace_focused"
        case "tab.focus": type = "tab_focused"
        default: type = "pane_focused"
        }
        return FakeReply(chunks: [request.result(["type": type, "workspace_id": "w1", "tab_id": "t1", "pane_id": "p1"])])
    }
}
