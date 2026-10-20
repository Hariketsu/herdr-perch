public actor RefreshScheduler {
    private let coalesce: Duration
    private let sleep: @Sendable (Duration) async throws -> Void
    private let fetch: @Sendable () async -> Void

    public init(
        coalesce: Duration = .milliseconds(50),
        sleep: @escaping @Sendable (Duration) async throws -> Void,
        fetch: @escaping @Sendable () async -> Void
    ) {
        self.coalesce = coalesce
        self.sleep = sleep
        self.fetch = fetch
    }

    public func request() { fatalError("unimplemented") }
    public func drain() async { fatalError("unimplemented") }
}
