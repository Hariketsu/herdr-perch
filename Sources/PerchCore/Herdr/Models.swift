import Foundation

public enum AgentStatus: String, Sendable, Equatable {
    case idle, working, blocked, done, unknown
}

public struct AgentInfo: Sendable, Equatable {
    public var paneID: String
    public var tabID: String
    public var workspaceID: String
    public var agent: String
    public var displayAgent: String?
    public var name: String?
    public var status: AgentStatus
    public var stateChangeSeq: UInt64
    public var completionSeq: UInt64?
    public var title: String?
    public var stateLabels: [String: String]
    public var cwd: String?
    public var focused: Bool

    public init(
        paneID: String, tabID: String, workspaceID: String, agent: String,
        displayAgent: String? = nil, name: String? = nil, status: AgentStatus,
        stateChangeSeq: UInt64 = 0, completionSeq: UInt64? = nil, title: String? = nil,
        stateLabels: [String: String] = [:], cwd: String? = nil, focused: Bool = false
    ) {
        self.paneID = paneID
        self.tabID = tabID
        self.workspaceID = workspaceID
        self.agent = agent
        self.displayAgent = displayAgent
        self.name = name
        self.status = status
        self.stateChangeSeq = stateChangeSeq
        self.completionSeq = completionSeq
        self.title = title
        self.stateLabels = stateLabels
        self.cwd = cwd
        self.focused = focused
    }
}

public struct PaneInfo: Sendable, Equatable {
    public var paneID: String
    public var tabID: String
    public var workspaceID: String

    public init(paneID: String, tabID: String, workspaceID: String) {
        self.paneID = paneID
        self.tabID = tabID
        self.workspaceID = workspaceID
    }
}

public struct Snapshot: Sendable, Equatable {
    public var protocolVersion: Int
    public var panes: [PaneInfo]
    public var agents: [AgentInfo]

    public init(protocolVersion: Int, panes: [PaneInfo], agents: [AgentInfo]) {
        self.protocolVersion = protocolVersion
        self.panes = panes
        self.agents = agents
    }

    /// Decodes a full `session.snapshot` response line. Elements missing a
    /// required identifier are skipped individually rather than failing the whole snapshot.
    public static func decode(response: Data) throws -> Snapshot {
        let result = try HerdrClient.result(of: response)
        let body = result["snapshot"] as? [String: Any] ?? result
        let panes = (body["panes"] as? [[String: Any]] ?? []).compactMap(PaneInfo.init(json:))
        let agents = (body["agents"] as? [[String: Any]] ?? []).compactMap(AgentInfo.init(json:))
        return Snapshot(
            protocolVersion: (body["protocol"] as? NSNumber)?.intValue ?? 0,
            panes: panes,
            agents: agents)
    }
}

extension PaneInfo {
    init?(json: [String: Any]) {
        guard let paneID = json["pane_id"] as? String,
              let tabID = json["tab_id"] as? String,
              let workspaceID = json["workspace_id"] as? String
        else { return nil }
        self.init(paneID: paneID, tabID: tabID, workspaceID: workspaceID)
    }
}

extension AgentInfo {
    init?(json: [String: Any]) {
        guard let pane = PaneInfo(json: json), let agent = json["agent"] as? String else { return nil }
        self.init(
            paneID: pane.paneID,
            tabID: pane.tabID,
            workspaceID: pane.workspaceID,
            agent: agent,
            displayAgent: json["display_agent"] as? String,
            name: json["name"] as? String,
            status: (json["agent_status"] as? String).flatMap(AgentStatus.init(rawValue:)) ?? .unknown,
            stateChangeSeq: (json["state_change_seq"] as? NSNumber)?.uint64Value ?? 0,
            completionSeq: (json["completion_seq"] as? NSNumber)?.uint64Value,
            title: json["title"] as? String ?? json["terminal_title_stripped"] as? String,
            stateLabels: (json["state_labels"] as? [String: Any])?.compactMapValues { $0 as? String } ?? [:],
            cwd: json["foreground_cwd"] as? String ?? json["cwd"] as? String,
            focused: json["focused"] as? Bool ?? false)
    }
}

public struct PingInfo: Sendable, Equatable {
    public var version: String
    public var protocolVersion: Int

    public init(version: String, protocolVersion: Int) {
        self.version = version
        self.protocolVersion = protocolVersion
    }
}
