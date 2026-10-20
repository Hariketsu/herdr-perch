/// Serialises snapshot reads for one session.
///
/// Requests while idle wait `coalesce` and then fetch once. Requests during a
/// fetch mark it dirty, which triggers exactly one more fetch when it ends.
public actor RefreshScheduler {
    private enum Phase { case idle, coalescing, fetching(dirty: Bool) }

    private let coalesce: Duration
    private let sleep: @Sendable (Duration) async throws -> Void
    private let fetch: @Sendable () async -> Void
    private var phase = Phase.idle
    private var drainers: [CheckedContinuation<Void, Never>] = []

    public init(
        coalesce: Duration = .milliseconds(50),
        sleep: @escaping @Sendable (Duration) async throws -> Void,
        fetch: @escaping @Sendable () async -> Void
    ) {
        self.coalesce = coalesce
        self.sleep = sleep
        self.fetch = fetch
    }

    public func request() {
        switch phase {
        case .idle:
            phase = .coalescing
            Task { await run() }
        case .coalescing, .fetching(dirty: true):
            break
        case .fetching(dirty: false):
            phase = .fetching(dirty: true)
        }
    }

    public func drain() async {
        if case .idle = phase { return }
        await withCheckedContinuation { drainers.append($0) }
    }

    private func run() async {
        try? await sleep(coalesce)
        repeat {
            phase = .fetching(dirty: false)
            await fetch()
        } while isDirty
        phase = .idle
        let waiting = drainers
        drainers.removeAll()
        waiting.forEach { $0.resume() }
    }

    private var isDirty: Bool {
        if case .fetching(dirty: true) = phase { return true }
        return false
    }
}
