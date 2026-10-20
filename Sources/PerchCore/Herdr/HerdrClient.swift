import Foundation

public enum HerdrError: Error, Equatable, Sendable {
    case connectFailed(Int32)
    case timeout
    case closedByPeer
    case malformedResponse
    case server(code: String, message: String)
    case eventsLost
    case unsupportedProtocol(Int)
}

public struct HerdrClient: Sendable {
    public static let minimumProtocol = 22

    public let socketPath: String
    public let timeout: Duration

    public init(socketPath: String, timeout: Duration = .seconds(2)) {
        self.socketPath = socketPath
        self.timeout = timeout
    }

    public func ping() async throws -> PingInfo { fatalError("unimplemented") }
    public func snapshot() async throws -> Snapshot { fatalError("unimplemented") }
    public func focusWorkspace(_ id: String) async throws { fatalError("unimplemented") }
    public func focusTab(_ id: String) async throws { fatalError("unimplemented") }
    public func focusPane(_ id: String) async throws { fatalError("unimplemented") }

    public func subscribe(_ subscriptions: [Subscription]) -> AsyncThrowingStream<EventSignal, any Error> {
        fatalError("unimplemented")
    }
}
