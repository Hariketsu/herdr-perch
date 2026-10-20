import Foundation
import Observation

/// Main-actor façade the UI reads: all sessions merged into `[AgentRow]`.
@MainActor @Observable
public final class PerchStore {
    public private(set) var rows: [AgentRow] = []
    public private(set) var sessions: [SessionState] = []

    @ObservationIgnored private var registry: SessionRegistry!
    @ObservationIgnored private var clock = StatusClock()
    @ObservationIgnored private let trace: FileHandle?

    public init(root: URL, tracePath: String? = ProcessInfo.processInfo.environment["PERCH_TRACE"]) {
        trace = tracePath.flatMap { path in
            FileManager.default.createFile(atPath: path, contents: nil)
            return FileHandle(forWritingAtPath: path)
        }
        registry = SessionRegistry(scanner: SessionScanner(root: root)) { [weak self] _ in
            Task { @MainActor in await self?.pull() }
        }
    }

    public func start() {
        Task { await registry.start() }
    }

    public func stop() {
        Task { await registry.stop() }
    }

    public func refreshAll() {
        Task { await registry.refreshAll() }
    }

    public func jump(_ row: AgentRow) async -> JumpOutcome {
        guard let session = sessions.first(where: { $0.endpoint.name == row.session }) else {
            return .failed("Session \(row.session) is gone")
        }
        let outcome = await Jumper().jump(row, client: HerdrClient(socketPath: session.endpoint.socketPath))
        refreshAll()
        return outcome
    }

    private func pull() async {
        let latest = await registry.sessions
        let built = RowBuilder.rows(latest, clock: &clock, now: Date())
        guard latest != sessions || built != rows else { return }
        sessions = latest
        rows = built
        trace?.write(StateTrace.line(rows: built, sessions: latest))
    }
}
