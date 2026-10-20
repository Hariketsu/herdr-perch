import Foundation
import Testing
import PerchCore

func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

func snapshotResponse(agents: [[String: Any]] = [], panes: [[String: Any]] = []) throws -> Data {
    try JSONSerialization.data(withJSONObject: ["id": "test", "result": [
        "type": "session_snapshot", "snapshot": ["protocol": 22, "agents": agents, "panes": panes]
    ]])
}

func minimalAgent(_ pane: String = "w1:p1") -> [String: Any] {
    ["pane_id": pane, "tab_id": "w1:t1", "workspace_id": "w1", "agent": "claude"]
}

/// A bounded observation loop for test coordination, never for product timing.
@discardableResult
func eventually(within timeout: Duration = .seconds(1), _ predicate: @escaping @Sendable () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await predicate() { return true }
        try? await Task.sleep(for: .milliseconds(1))
    }
    Issue.record("Test coordination did not complete within \(timeout)")
    return false
}

final class RequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [FakeRequest] = []
    func record(_ request: FakeRequest) { lock.withLock { requests.append(request) } }
    var values: [FakeRequest] { lock.withLock { requests } }
}
