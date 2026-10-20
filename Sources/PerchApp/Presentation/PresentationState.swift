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

struct PresentationState {
    static let hoverIntent: Duration = .milliseconds(120)
    static let hoverExitDelay: Duration = .milliseconds(280)
    static let autoCollapse: Duration = .seconds(8)

    private(set) var surface: Surface = .hidden
    private(set) var nextTick: ContinuousClock.Instant?

    init(autoExpandOnBlocked: Bool = true) {}

    mutating func handle(_ event: PresentationEvent, now: ContinuousClock.Instant) {
        fatalError("unimplemented")
    }
}
