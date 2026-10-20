import Foundation

/// One NDJSON line describing what Perch would show. Shared by `PERCH_TRACE`
/// and `perchctl` so smoke/E2E tests observe exactly the app's state.
public enum StateTrace {
    public static func line(rows: [AgentRow], sessions: [SessionState], at time: Date = Date()) -> Data {
        var data = try! JSONSerialization.data(
            withJSONObject: ["t": time.timeIntervalSince1970, "rows": rows.map(row), "sessions": sessions.map(session)],
            options: [.sortedKeys, .withoutEscapingSlashes])
        data.append(0x0A)
        return data
    }

    private static func row(_ row: AgentRow) -> [String: Any] {
        ["session": row.session, "pane": row.id.paneID, "status": statusName(row.status),
         "title": row.title, "stale": row.isStale]
    }

    private static func session(_ state: SessionState) -> [String: Any] {
        let health = switch state.health {
        case .live: "live"
        case .stale: "stale"
        case .updateRequired: "updateRequired"
        }
        return ["name": state.endpoint.name, "health": health]
    }

    static func statusName(_ status: DisplayStatus) -> String {
        switch status {
        case .blocked: "blocked"
        case .finished: "finished"
        case .working: "working"
        case .idle: "idle"
        }
    }
}
