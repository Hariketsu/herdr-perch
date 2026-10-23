import AppKit
import Observation
import PerchCore

/// UI state for the notch: presentation reducer + sizing, fed by `PerchStore`.
@MainActor @Observable
final class NotchModel {
    let store: PerchStore
    var preferences: Preferences {
        didSet { presentation.handle(.settingsChanged(preferences.alerts), now: .now) }
    }
    var geometry: NotchGeometry
    var contentHeight: CGFloat = 0
    var peekContentHeight: CGFloat = 0
    var notice: String?
    /// Grouped list: the Idle section is folded at every launch.
    var idleExpanded = false
    var systemReduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    /// Full motion by default; the system setting applies only when the user opts in.
    var reduceMotion: Bool { preferences.followReduceMotion && systemReduceMotion }
    @ObservationIgnored var showSettings: () -> Void = {}
    private(set) var presentation: PresentationState

    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private let terminal = TerminalActivator()

    init(store: PerchStore, preferences: Preferences, geometry: NotchGeometry) {
        self.store = store
        self.preferences = preferences
        self.geometry = geometry
        presentation = PresentationState(alerts: preferences.alerts)
    }

    var summary: CompactSummary { CompactSummary.make(store.rows) }
    /// The ear widens while it shows "✓ title" (FinishedAlert.ear).
    var wingWidth: CGFloat {
        completionTitle == nil ? summary.wingWidth(preferences.compactStyle) : NotchGeometry.maxWingWidth
    }
    var surface: Surface { presentation.surface }
    var isExpanded: Bool { if case .expanded = surface { true } else { false } }
    var isPeeking: Bool { surface == .peek }
    /// Expanded or peeking: the panel takes mouse events inside the shape.
    var isOpen: Bool { isExpanded || isPeeking }

    /// Size of the black shape (shoulders excluded).
    var shapeSize: CGSize {
        switch surface {
        case .expanded: geometry.expandedSize(contentHeight: contentHeight, wingWidth: wingWidth)
        case .peek: geometry.peekSize(contentHeight: peekContentHeight, wingWidth: wingWidth)
        case .hidden, .collapsed: geometry.collapsedSize(wingWidth: wingWidth)
        }
    }

    /// Title for the collapsed "✓ title" ear, if its agent is still listed.
    var completionTitle: String? {
        guard let ref = presentation.completion, let row = store.rows.first(where: { $0.id == ref }) else { return nil }
        return preferences.cleanTitles ? TitleCleaner.clean(row.title) : row.title
    }

    func rowsDidChange() {
        let live = store.rows.filter { !$0.isStale }
        let attention = Attention(
            blocked: live.filter { $0.status == .blocked }.map(\.id),
            finished: live.filter { $0.status == .finished }.map(\.id),
            system: systemAlert)
        if !store.rows.isEmpty { notice = staleNotice }
        send(.rowsChanged(hasRows: !store.rows.isEmpty, attention: attention))
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

    func openSettings() {
        send(.rowActivated)  // collapse, like leaving via a row
        showSettings()
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

    private var systemAlert: SystemAlert? {
        if store.sessions.contains(where: { if case .updateRequired = $0.health { true } else { false } }) {
            return .updateRequired
        }
        return store.rows.contains(where: \.isStale) ? .unreachable : nil
    }

    private var staleNotice: String? { systemAlert.map(Self.text) }

    static func text(_ alert: SystemAlert) -> String {
        switch alert {
        case .updateRequired: "Herdr update required (0.9.5 or later)"
        case .unreachable: "Herdr isn’t reachable — reconnecting…"
        }
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
