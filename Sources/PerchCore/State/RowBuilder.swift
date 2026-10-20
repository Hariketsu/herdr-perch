import Foundation

public struct StatusClock: Sendable {
    public init() {}

    public mutating func observe(_ ref: AgentRef, seq: UInt64, now: Date) -> Date { fatalError("unimplemented") }
    public mutating func retain(only refs: Set<AgentRef>) { fatalError("unimplemented") }
}

public enum RowBuilder {
    public static func rows(_ sessions: [SessionState], clock: inout StatusClock, now: Date) -> [AgentRow] {
        fatalError("unimplemented")
    }
}
