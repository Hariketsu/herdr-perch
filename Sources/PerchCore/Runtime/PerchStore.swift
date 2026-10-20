import Foundation
import Observation

@MainActor @Observable
public final class PerchStore {
    public private(set) var rows: [AgentRow] = []
    public private(set) var sessions: [SessionState] = []

    public init(root: URL, tracePath: String? = ProcessInfo.processInfo.environment["PERCH_TRACE"]) {}

    public func start() { fatalError("unimplemented") }
    public func stop() { fatalError("unimplemented") }
    public func refreshAll() { fatalError("unimplemented") }
    public func jump(_ row: AgentRow) async -> JumpOutcome { fatalError("unimplemented") }
}
