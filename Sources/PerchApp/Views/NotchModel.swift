import AppKit
import Observation
import PerchCore

/// UI state for the notch: presentation reducer + sizing, fed by `PerchStore`.
@MainActor @Observable
final class NotchModel {
    let store: PerchStore
    var preferences: Preferences {
        didSet { presentation.handle(.settingsChanged(autoExpandOnBlocked: preferences.autoExpandOnBlocked), now: .now) }
    }
    var geometry: NotchGeometry
    var contentHeight: CGFloat = 0
    var notice: String?
    var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    private(set) var presentation: PresentationState

    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var blockedRefs: Set<AgentRef> = []
    @ObservationIgnored private let terminal = TerminalActivator()

    init(store: PerchStore, preferences: Preferences, geometry: NotchGeometry) {
        self.store = store
        self.preferences = preferences
        self.geometry = geometry
        presentation = PresentationState(autoExpandOnBlocked: preferences.autoExpandOnBlocked)
    }

    var summary: CompactSummary { CompactSummary.make(store.rows) }
    var wingWidth: CGFloat { summary.wingWidth(preferences.compactStyle) }
    var surface: Surface { presentation.surface }
    var isExpanded: Bool { if case .expanded = surface { true } else { false } }

    /// Size of the black shape (shoulders excluded).
    var shapeSize: CGSize {
        isExpanded
            ? geometry.expandedSize(contentHeight: contentHeight, wingWidth: wingWidth)
            : geometry.collapsedSize(wingWidth: wingWidth)
    }

    func rowsDidChange() {
        let blocked = Set(store.rows.filter { $0.status == .blocked && !$0.isStale }.map(\.id))
        let newBlocked = !blocked.subtracting(blockedRefs).isEmpty
        blockedRefs = blocked
        if !store.rows.isEmpty { notice = staleNotice }
        send(.rowsChanged(hasRows: !store.rows.isEmpty, newBlocked: newBlocked))
    }

    func send(_ event: PresentationEvent) {
        let wasExpanded = isExpanded
        presentation.handle(event, now: .now)
        if isExpanded && !wasExpanded {
            store.refreshAll()
            notice = staleNotice
        }
        scheduleTick()
    }

    func activate(_ row: AgentRow) {
        send(.rowActivated)
        Task {
            let outcome = await store.jump(row)
            switch outcome {
            case .focused:
                terminal.activate()
                // Background clients can miss the first focus; NotchAgent re-applies it once.
                try? await Task.sleep(for: .milliseconds(120))
                _ = await store.jump(row)
            case .needsAttach:
                showNotice("No Herdr window attached")
            case let .failed(message):
                showNotice(message)
            }
        }
    }

    private var staleNotice: String? {
        if store.sessions.contains(where: { if case .updateRequired = $0.health { true } else { false } }) {
            return "Herdr update required (0.9.5 or later)"
        }
        if store.rows.contains(where: \.isStale) { return "Herdr isn’t reachable — reconnecting…" }
        return nil
    }

    private func showNotice(_ text: String) {
        notice = text
        send(.clicked)  // reopen pinned so the message is visible
    }

    private func scheduleTick() {
        tickTask?.cancel()
        guard let deadline = presentation.nextTick else { return }
        tickTask = Task { [weak self] in
            try? await Task.sleep(until: deadline, clock: .continuous)
            guard !Task.isCancelled else { return }
            self?.send(.tick)
        }
    }
}
