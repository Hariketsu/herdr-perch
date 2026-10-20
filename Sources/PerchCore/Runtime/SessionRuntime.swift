import Foundation

/// One Herdr server: snapshot is the only writer of state; events and the
/// fallback timer merely request another read.
public actor SessionRuntime {
    private let endpoint: SessionEndpoint
    private let client: HerdrClient
    private let now: @Sendable () -> Date
    private let onChange: @Sendable (SessionState) -> Void

    private var snapshot: Snapshot?
    private var health = SessionHealth.live
    private var consecutiveFailures = 0
    private var streamHealthy = false
    private var plan: Set<Subscription>?
    private var stopped = true
    private var scheduler: RefreshScheduler?
    private var eventTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?

    public init(
        endpoint: SessionEndpoint,
        client: HerdrClient,
        now: @escaping @Sendable () -> Date = { Date() },
        onChange: @escaping @Sendable (SessionState) -> Void
    ) {
        self.endpoint = endpoint
        self.client = client
        self.now = now
        self.onChange = onChange
    }

    public var state: SessionState {
        SessionState(endpoint: endpoint, snapshot: snapshot, health: health)
    }

    public func start() {
        guard stopped else { return }
        stopped = false
        let scheduler = RefreshScheduler(
            sleep: { try await Task.sleep(for: $0) },
            fetch: { [weak self] in await self?.refresh() })
        self.scheduler = scheduler
        Task { await scheduler.request() }
        timerTask = Task { [weak self] in
            while let interval = await self?.pollInterval {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                await self?.requestRefresh()
            }
        }
    }

    public func stop() {
        stopped = true
        eventTask?.cancel()
        timerTask?.cancel()
        eventTask = nil
        timerTask = nil
        scheduler = nil
    }

    public func requestRefresh() {
        guard !stopped, let scheduler else { return }
        Task { await scheduler.request() }
    }

    // MARK: Refresh

    private var pollInterval: Duration? {
        stopped ? nil : PollingPolicy.interval(streamHealthy: streamHealthy, consecutiveFailures: consecutiveFailures)
    }

    private func refresh() async {
        guard !stopped else { return }
        let before = state
        do {
            let fresh = try await client.snapshot()
            guard !stopped else { return }
            snapshot = fresh
            health = .live
            consecutiveFailures = 0
            subscribe(SubscriptionPlan.make(for: fresh))
        } catch {
            guard !stopped else { return }
            consecutiveFailures += 1
            if case .live = health { health = .stale(since: now()) }
        }
        if state != before { onChange(state) }
    }

    // MARK: Events

    /// (Re)subscribes only when the plan changes; the old stream is cancelled.
    private func subscribe(_ next: Set<Subscription>) {
        guard next != plan else { return }
        plan = next
        streamHealthy = false
        eventTask?.cancel()
        eventTask = Task { [weak self] in await self?.runEvents(next) }
    }

    private func runEvents(_ subscriptions: Set<Subscription>) async {
        var failures = 0
        while !Task.isCancelled, !stopped {
            do {
                for try await signal in client.subscribe(Array(subscriptions)) {
                    if signal == .started {
                        streamHealthy = true
                        failures = 0
                    }
                    requestRefresh()
                }
                if Task.isCancelled { return }
            } catch {
                if Task.isCancelled { return }
            }
            // Any end of stream is a reason to re-read: the pane may be gone or Herdr restarting.
            streamHealthy = false
            requestRefresh()
            failures += 1
            let backoff = min(0.25 * pow(2, Double(failures - 1)), 30)
            try? await Task.sleep(for: .seconds(backoff))
        }
    }
}

/// Owns one `SessionRuntime` per reachable socket found by `SessionScanner`.
public actor SessionRegistry {
    private struct Entry {
        var runtime: SessionRuntime?
        var state: SessionState
    }

    private let scanner: SessionScanner
    private let scanInterval: Duration
    private let unreachableTimeout: Duration
    private let clientTimeout: Duration
    private let now: @Sendable () -> Date
    private let onChange: @Sendable ([SessionState]) -> Void

    private var entries: [SessionEndpoint: Entry] = [:]
    private var order: [SessionEndpoint] = []
    private var scanTask: Task<Void, Never>?

    public init(
        scanner: SessionScanner,
        scanInterval: Duration = .seconds(1),
        unreachableTimeout: Duration = .seconds(30),
        clientTimeout: Duration = .seconds(2),
        now: @escaping @Sendable () -> Date = { Date() },
        onChange: @escaping @Sendable ([SessionState]) -> Void
    ) {
        self.scanner = scanner
        self.scanInterval = scanInterval
        self.unreachableTimeout = unreachableTimeout
        self.clientTimeout = clientTimeout
        self.now = now
        self.onChange = onChange
    }

    public var sessions: [SessionState] {
        order.compactMap { entries[$0]?.state }
    }

    public func start() {
        guard scanTask == nil else { return }
        scanTask = Task { [weak self] in
            while !Task.isCancelled, let self {
                await self.scanOnce()
                try? await Task.sleep(for: self.scanInterval)
            }
        }
    }

    public func stop() async {
        scanTask?.cancel()
        scanTask = nil
        for entry in entries.values { await entry.runtime?.stop() }
        entries.removeAll()
        order.removeAll()
    }

    public func refreshAll() async {
        for entry in entries.values { await entry.runtime?.requestRefresh() }
    }

    public func scanOnce() async {
        let before = sessions
        let found = scanner.scan()
        let foundSet = Set(found)
        let timeout = TimeInterval(unreachableTimeout.components.seconds)
            + TimeInterval(unreachableTimeout.components.attoseconds) / 1e18

        for (endpoint, entry) in entries {
            var expired = false
            if case let .stale(since) = entry.state.health { expired = now().timeIntervalSince(since) >= timeout }
            if !foundSet.contains(endpoint) || expired {
                await entry.runtime?.stop()
                entries[endpoint] = nil
            }
        }

        for endpoint in found where entries[endpoint] == nil {
            let client = HerdrClient(socketPath: endpoint.socketPath, timeout: clientTimeout)
            do {
                _ = try await client.ping()
            } catch let HerdrError.unsupportedProtocol(version) {
                entries[endpoint] = Entry(state: SessionState(endpoint: endpoint, health: .updateRequired(protocolVersion: version)))
                continue
            } catch {
                continue  // e.g. a leftover socket from a crashed server; retry next scan
            }
            let runtime = SessionRuntime(endpoint: endpoint, client: client, now: now) { [weak self] _ in
                // Pull the latest state rather than trusting callback order across hops.
                Task { await self?.pull(endpoint) }
            }
            entries[endpoint] = Entry(runtime: runtime, state: SessionState(endpoint: endpoint, health: .live))
            await runtime.start()
        }

        order = found.filter { entries[$0] != nil }
        if sessions != before { onChange(sessions) }
    }

    private func pull(_ endpoint: SessionEndpoint) async {
        guard let runtime = entries[endpoint]?.runtime else { return }
        let state = await runtime.state
        guard entries[endpoint]?.runtime === runtime, entries[endpoint]?.state != state else { return }
        entries[endpoint]?.state = state
        onChange(sessions)
    }
}
