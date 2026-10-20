public enum JumpOutcome: Equatable, Sendable {
    case focused
    case needsAttach
    case failed(String)
}

public struct Jumper: Sendable {
    public init() {}

    /// workspace → tab → pane; focusing the pane alone can leave Herdr on the old tab.
    public func jump(_ row: AgentRow, client: HerdrClient) async -> JumpOutcome {
        do {
            try await client.focusWorkspace(row.workspaceID)
            try await client.focusTab(row.tabID)
            try await client.focusPane(row.id.paneID)
            return .focused
        } catch let HerdrError.server(code, message) {
            if (code + " " + message).lowercased().contains("detach") { return .needsAttach }
            return .failed(message.isEmpty ? code : message)
        } catch {
            return .failed(String(describing: error))
        }
    }
}
