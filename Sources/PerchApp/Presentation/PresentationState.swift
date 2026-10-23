import PerchCore

enum Surface: Equatable {
    case hidden
    case collapsed
    case peek
    case expanded(pinned: Bool)
}

/// What currently deserves attention, computed by NotchModel from rows and sessions (stale rows excluded).
struct Attention: Equatable {
    var blocked: [AgentRef] = []
    var finished: [AgentRef] = []
    var system: SystemAlert?
}

enum SystemAlert: Equatable {
    case unreachable
    case updateRequired
}

enum PeekItem: Hashable {
    case blocked(AgentRef)
    case finished(AgentRef)
    case system(SystemAlert)
}

enum PresentationEvent: Equatable {
    case rowsChanged(hasRows: Bool, attention: Attention)
    case pointerEntered
    case pointerExited
    case clicked
    case clickedOutside
    case rowActivated
    case tick
    case settingsChanged(peekOnFinished: Bool)
}

/// Pure reducer for the notch surface (ARCHITECTURE.md, Presentation). Time is passed in;
/// the caller sends `.tick` at `nextTick`.
struct PresentationState {
    static let hoverIntent: Duration = .milliseconds(120)
    static let hoverExitDelay: Duration = .milliseconds(280)
    static let peekBlockedDuration: Duration = .seconds(8)
    static let peekSystemDuration: Duration = .seconds(6)
    static let peekFinishedDuration: Duration = .seconds(4)
    static let highlightDuration: Duration = .milliseconds(900)

    private enum Pending { case expand, collapse }

    private(set) var surface: Surface = .hidden
    /// Cards in display order; non-empty only while peeking.
    private(set) var peekItems: [PeekItem] = []
    /// Row that flashes when something new arrives while the list is open.
    private(set) var highlight: AgentRef?

    var nextTick: ContinuousClock.Instant? {
        [pendingDeadline, peekDeadline, highlightDeadline].compactMap { $0 }.min()
    }

    private var peekOnFinished: Bool
    private var seen: Attention?
    private var arrivals: [PeekItem: (batch: Int, index: Int)] = [:]
    private var batch = 0
    private var pending: Pending?
    private var pendingDeadline: ContinuousClock.Instant?
    private var peekDeadline: ContinuousClock.Instant?
    private var highlightDeadline: ContinuousClock.Instant?

    init(peekOnFinished: Bool = true) {
        self.peekOnFinished = peekOnFinished
    }

    mutating func handle(_ event: PresentationEvent, now: ContinuousClock.Instant) {
        switch (event, surface) {
        case let (.settingsChanged(enabled), _):
            peekOnFinished = enabled

        case let (.rowsChanged(hasRows: false, attention), _):
            seen = attention
            set(.hidden)
            highlight = nil
            highlightDeadline = nil
        case let (.rowsChanged(true, attention), _):
            let fresh = newItems(attention)
            seen = attention
            if surface == .hidden { set(.collapsed) }
            prune(attention)
            notify(fresh, now: now)

        case (.pointerEntered, .collapsed), (.pointerEntered, .peek):
            schedule(.expand, at: now + Self.hoverIntent)
        case (.pointerEntered, .expanded):
            cancel()
        case (.pointerExited, .collapsed), (.pointerExited, .peek):
            if pending == .expand { cancel() }
        case (.pointerExited, .expanded(pinned: false)):
            schedule(.collapse, at: now + Self.hoverExitDelay)

        case (.clicked, .collapsed), (.clicked, .peek), (.clicked, .expanded(pinned: false)):
            set(.expanded(pinned: true))
        case (.clicked, .expanded(pinned: true)), (.clickedOutside, .expanded),
             (.rowActivated, .expanded), (.rowActivated, .peek):
            set(.collapsed)

        case (.tick, _):
            if let deadline = highlightDeadline, now >= deadline {
                highlight = nil
                highlightDeadline = nil
            }
            if let deadline = pendingDeadline, now >= deadline, let action = pending {
                set(action == .expand ? .expanded(pinned: false) : .collapsed)
            }
            if surface == .peek, let deadline = peekDeadline, now >= deadline { set(.collapsed) }

        default:
            break
        }
    }

    // MARK: Attention

    /// Items that were not there last time. The first update only records finished
    /// agents as a baseline, so ones already done at launch stay quiet.
    private func newItems(_ attention: Attention) -> [PeekItem] {
        let previous = seen ?? Attention(finished: attention.finished)
        var items = attention.blocked.filter { !previous.blocked.contains($0) }.map(PeekItem.blocked)
        if let system = attention.system, system != previous.system { items.append(.system(system)) }
        items += attention.finished.filter { !previous.finished.contains($0) }.map(PeekItem.finished)
        return items
    }

    /// Drops cards whose reason went away; an empty peek collapses.
    private mutating func prune(_ attention: Attention) {
        guard surface == .peek else { return }
        peekItems.removeAll { item in
            switch item {
            case let .blocked(ref): !attention.blocked.contains(ref)
            case let .finished(ref): !attention.finished.contains(ref)
            case let .system(alert): attention.system != alert
            }
        }
        if peekItems.isEmpty { set(.collapsed) }
    }

    private mutating func notify(_ items: [PeekItem], now: ContinuousClock.Instant) {
        let wanted = items.filter { item in
            if case .finished = item { peekOnFinished } else { true }
        }
        guard !wanted.isEmpty, surface != .hidden else { return }
        if isExpanded {
            // The list already shows them: flash the first agent row instead of covering the list.
            let flashing = wanted.compactMap { item -> AgentRef? in
                switch item {
                case let .blocked(ref), let .finished(ref): ref
                case .system: nil
                }
            }
            if let first = flashing.first {
                highlight = first
                highlightDeadline = now + Self.highlightDuration
            }
            return
        }
        let peeked = wanted.filter { !peekItems.contains($0) }
        guard !peeked.isEmpty else { return }
        batch += 1
        for (index, item) in peeked.enumerated() {
            arrivals[item] = (batch, index)
            let duration = switch item {
            case .blocked: Self.peekBlockedDuration
            case .system: Self.peekSystemDuration
            case .finished: Self.peekFinishedDuration
            }
            peekDeadline = max(peekDeadline ?? now + duration, now + duration)
        }
        // Kind first (blocked, system, finished); later updates first; within one update, input order.
        peekItems = (peekItems + peeked).sorted { a, b in
            let (x, y) = (arrivals[a]!, arrivals[b]!)
            if Self.rank(a) != Self.rank(b) { return Self.rank(a) < Self.rank(b) }
            return x.batch != y.batch ? x.batch > y.batch : x.index < y.index
        }
        // Entering peek keeps a pending hover expansion: the pointer may already be resting there.
        surface = .peek
    }

    private static func rank(_ item: PeekItem) -> Int {
        switch item {
        case .blocked: 0
        case .system: 1
        case .finished: 2
        }
    }

    private var isExpanded: Bool { if case .expanded = surface { true } else { false } }

    // MARK: Surface

    /// Any surface change cancels pending timers; the cards go with the peek.
    private mutating func set(_ next: Surface) {
        surface = next
        cancel()
        peekItems = []
        peekDeadline = nil
        arrivals = [:]
    }

    private mutating func schedule(_ action: Pending, at deadline: ContinuousClock.Instant) {
        pending = action
        pendingDeadline = deadline
    }

    private mutating func cancel() {
        pending = nil
        pendingDeadline = nil
    }
}
