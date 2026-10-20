public enum JumpOutcome: Equatable, Sendable {
    case focused
    case needsAttach
    case failed(String)
}

public struct Jumper: Sendable {
    public init() {}

    public func jump(_ row: AgentRow, client: HerdrClient) async -> JumpOutcome { fatalError("unimplemented") }
}
