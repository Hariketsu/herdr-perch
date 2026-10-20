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

    public static func decode(response: Data) throws -> Snapshot {
        fatalError("unimplemented")
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
