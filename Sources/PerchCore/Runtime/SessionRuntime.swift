import Foundation

public actor SessionRuntime {
    public init(
        endpoint: SessionEndpoint,
        client: HerdrClient,
        now: @escaping @Sendable () -> Date = { Date() },
        onChange: @escaping @Sendable (SessionState) -> Void
    ) {
        fatalError("unimplemented")
    }

    public func start() { fatalError("unimplemented") }
    public func stop() { fatalError("unimplemented") }
    public func requestRefresh() { fatalError("unimplemented") }
    public var state: SessionState { fatalError("unimplemented") }
}

public actor SessionRegistry {
    public init(
        scanner: SessionScanner,
        scanInterval: Duration = .seconds(1),
        unreachableTimeout: Duration = .seconds(30),
        clientTimeout: Duration = .seconds(2),
        now: @escaping @Sendable () -> Date = { Date() },
        onChange: @escaping @Sendable ([SessionState]) -> Void
    ) {
        fatalError("unimplemented")
    }

    public func start() { fatalError("unimplemented") }
    public func stop() { fatalError("unimplemented") }
    public func scanOnce() async { fatalError("unimplemented") }
    public var sessions: [SessionState] { fatalError("unimplemented") }
}
