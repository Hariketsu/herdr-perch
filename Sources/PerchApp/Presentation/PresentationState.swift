import PerchCore

enum Surface: Equatable {
    case hidden
    case collapsed
    case expanded(pinned: Bool, auto: Bool)
}

enum PresentationEvent: Equatable {
    case rowsChanged(hasRows: Bool, newBlocked: Bool)
    case pointerEntered
    case pointerExited
    case clicked
    case clickedOutside
    case rowActivated
    case tick
    case settingsChanged(autoExpandOnBlocked: Bool)
}

/// Pure reducer for the notch surface (architecture.md §6). Time is passed in;
/// the caller sends `.tick` at `nextTick`.
struct PresentationState {
    static let hoverIntent: Duration = .milliseconds(120)
    static let hoverExitDelay: Duration = .milliseconds(280)
    static let autoCollapse: Duration = .seconds(8)

    private enum Pending { case expand, collapse }

    private(set) var surface: Surface = .hidden
    private(set) var nextTick: ContinuousClock.Instant?
    var isHovering: Bool { fatalError("unimplemented") }
    var pulse: Int { fatalError("unimplemented") }
    private var pending: Pending?
    private var autoExpandOnBlocked: Bool

    init(autoExpandOnBlocked: Bool = true) {
        self.autoExpandOnBlocked = autoExpandOnBlocked
    }

    mutating func handle(_ event: PresentationEvent, now: ContinuousClock.Instant) {
        switch (event, surface) {
        case let (.settingsChanged(enabled), _):
            autoExpandOnBlocked = enabled

        case (.rowsChanged(hasRows: false, _), _):
            set(.hidden)
        case let (.rowsChanged(true, newBlocked), .hidden):
            set(.collapsed)
            if newBlocked { autoExpand(now) }
        case (.rowsChanged(true, true), .collapsed):
            autoExpand(now)

        case (.pointerEntered, .collapsed):
            schedule(.expand, at: now + Self.hoverIntent)
        case let (.pointerEntered, .expanded(pinned, _)):
            set(.expanded(pinned: pinned, auto: false))
        case (.pointerExited, .collapsed):
            cancel()
        case (.pointerExited, .expanded(pinned: false, auto: false)):
            schedule(.collapse, at: now + Self.hoverExitDelay)

        case (.clicked, .collapsed), (.clicked, .expanded(pinned: false, _)):
            set(.expanded(pinned: true, auto: false))
        case (.clicked, .expanded(pinned: true, _)), (.clickedOutside, .expanded), (.rowActivated, .expanded):
            set(.collapsed)

        case (.tick, _):
            guard let deadline = nextTick, now >= deadline, let action = pending else { return }
            set(action == .expand ? .expanded(pinned: false, auto: false) : .collapsed)

        default:
            break
        }
    }

    private mutating func autoExpand(_ now: ContinuousClock.Instant) {
        guard autoExpandOnBlocked else { return }
        set(.expanded(pinned: false, auto: true))
        schedule(.collapse, at: now + Self.autoCollapse)
    }

    /// Any surface change cancels pending timers.
    private mutating func set(_ next: Surface) {
        surface = next
        cancel()
    }

    private mutating func schedule(_ action: Pending, at deadline: ContinuousClock.Instant) {
        pending = action
        nextTick = deadline
    }

    private mutating func cancel() {
        pending = nil
        nextTick = nil
    }
}
