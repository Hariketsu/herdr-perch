import Foundation

public enum DisplayStatus: Int, Comparable, Sendable {
    case blocked = 0, finished, working, idle

    public init(_ status: AgentStatus) {
        switch status {
        case .blocked: self = .blocked
        case .done: self = .finished
        case .working: self = .working
        case .idle, .unknown: self = .idle
        }
    }

    public static func < (lhs: DisplayStatus, rhs: DisplayStatus) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct AgentRef: Hashable, Sendable {
    public var session: String
    public var paneID: String

    public init(session: String, paneID: String) {
        self.session = session
        self.paneID = paneID
    }
}

public enum SessionHealth: Equatable, Sendable {
    case live
    case stale(since: Date)
    case updateRequired(protocolVersion: Int)
}

public struct AgentRow: Identifiable, Equatable, Sendable {
    public var id: AgentRef
    public var status: DisplayStatus
    public var isUnrecognized: Bool
    public var title: String
    public var subtitle: String?
    public var agentLabel: String
    public var project: String?
    public var since: Date
    public var session: String
    public var showsSessionTag: Bool
    public var isStale: Bool
    public var workspaceID: String
    public var tabID: String

    public init(
        id: AgentRef, status: DisplayStatus, isUnrecognized: Bool = false, title: String,
        subtitle: String? = nil, agentLabel: String, project: String? = nil, since: Date,
        session: String, showsSessionTag: Bool = false, isStale: Bool = false,
        workspaceID: String, tabID: String
    ) {
        self.id = id
        self.status = status
        self.isUnrecognized = isUnrecognized
        self.title = title
        self.subtitle = subtitle
        self.agentLabel = agentLabel
        self.project = project
        self.since = since
        self.session = session
        self.showsSessionTag = showsSessionTag
        self.isStale = isStale
        self.workspaceID = workspaceID
        self.tabID = tabID
    }
}

public struct SessionState: Sendable, Equatable {
    public var endpoint: SessionEndpoint
    public var snapshot: Snapshot?
    public var health: SessionHealth

    public init(endpoint: SessionEndpoint, snapshot: Snapshot? = nil, health: SessionHealth) {
        self.endpoint = endpoint
        self.snapshot = snapshot
        self.health = health
    }
}
