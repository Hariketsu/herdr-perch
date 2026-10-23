import Testing
import PerchCore
@testable import PerchApp

@Suite struct PeekTests {
    private let a = AgentRef(session: "test", paneID: "p1")
    private let b = AgentRef(session: "test", paneID: "p2")
    private let c = AgentRef(session: "other", paneID: "p1")

    private func collapsed(at time: ContinuousClock.Instant, alerts: AlertSettings = AlertSettings()) -> PresentationState {
        var state = PresentationState(alerts: alerts)
        state.handle(.rowsChanged(hasRows: true, attention: Attention()), now: time)
        return state
    }

    @Test(arguments: ["blocked", "finished", "system"])
    func peekExpiresAtExactClassDeadline(_ kind: String) {
        let t = ContinuousClock.now
        var state = collapsed(at: t)
        let attention: Attention
        let item: PeekItem
        let seconds: Int
        switch kind {
        case "blocked":
            attention = Attention(blocked: [a]); item = .blocked(a); seconds = 8
        case "finished":
            attention = Attention(finished: [a]); item = .finished(a); seconds = 4
        default:
            attention = Attention(system: .unreachable); item = .system(.unreachable); seconds = 6
        }
        state.handle(.rowsChanged(hasRows: true, attention: attention), now: t)
        #expect(state.surface == .peek)
        #expect(state.peekItems == [item])
        #expect(state.nextTick == t + .seconds(seconds))
        state.handle(.tick, now: t + .milliseconds(seconds * 1000 - 1))
        #expect(state.surface == .peek)
        #expect(state.peekItems == [item])
        state.handle(.tick, now: t + .seconds(seconds))
        #expect(state.surface == .collapsed)
        #expect(state.peekItems.isEmpty)
        #expect(state.nextTick == nil)
    }

    @Test func mergesWithoutDuplicatesAndNeverShortensDeadline() {
        let t = ContinuousClock.now
        var state = collapsed(at: t)
        state.handle(.rowsChanged(hasRows: true, attention: Attention(blocked: [a])), now: t)
        let merged = Attention(blocked: [a], finished: [b], system: .unreachable)
        state.handle(.rowsChanged(hasRows: true, attention: merged), now: t + .seconds(1))
        #expect(state.peekItems == [.blocked(a), .system(.unreachable), .finished(b)])
        #expect(state.nextTick == t + .seconds(8))
        state.handle(.rowsChanged(hasRows: true, attention: merged), now: t + .seconds(7))
        #expect(state.peekItems == [.blocked(a), .system(.unreachable), .finished(b)])
        #expect(state.nextTick == t + .seconds(8))
        state.handle(.rowsChanged(hasRows: true, attention: Attention(blocked: [a, c], finished: [b], system: .unreachable)), now: t + .seconds(7))
        #expect(state.peekItems == [.blocked(c), .blocked(a), .system(.unreachable), .finished(b)])
        #expect(state.nextTick == t + .seconds(15))
    }

    @Test func categoryOrderAndArrivalOrderPreserveAttentionOrderWithinBatch() {
        let t = ContinuousClock.now
        var state = collapsed(at: t)
        state.handle(.rowsChanged(hasRows: true, attention: Attention(blocked: [b, a], finished: [a, b], system: .unreachable)), now: t)
        #expect(state.peekItems == [.blocked(b), .blocked(a), .system(.unreachable), .finished(a), .finished(b)])
        state.handle(.rowsChanged(hasRows: true, attention: Attention(blocked: [b, a, c], finished: [a, b, c], system: .updateRequired)), now: t + .seconds(1))
        #expect(state.peekItems == [.blocked(c), .blocked(b), .blocked(a), .system(.updateRequired), .finished(c), .finished(a), .finished(b)])
    }

    @Test func prunesResolvedCardsAndCancelsDeadlineOnlyWhenEmpty() {
        let t = ContinuousClock.now
        var state = collapsed(at: t)
        state.handle(.rowsChanged(hasRows: true, attention: Attention(blocked: [a], finished: [b], system: .unreachable)), now: t)
        state.handle(.rowsChanged(hasRows: true, attention: Attention(finished: [b], system: .unreachable)), now: t + .seconds(1))
        #expect(state.surface == .peek)
        #expect(state.peekItems == [.system(.unreachable), .finished(b)])
        #expect(state.nextTick == t + .seconds(8))
        state.handle(.rowsChanged(hasRows: true, attention: Attention(finished: [b])), now: t + .seconds(2))
        #expect(state.peekItems == [.finished(b)])
        state.handle(.rowsChanged(hasRows: true, attention: Attention()), now: t + .seconds(3))
        #expect(state.surface == .collapsed)
        #expect(state.peekItems.isEmpty)
        #expect(state.nextTick == nil)
    }

    @Test func firstObservationSuppressesOnlyFinished() {
        let t = ContinuousClock.now
        var state = PresentationState()
        let attention = Attention(blocked: [a], finished: [b], system: .updateRequired)
        state.handle(.rowsChanged(hasRows: true, attention: attention), now: t)
        #expect(state.peekItems == [.blocked(a), .system(.updateRequired)])
        state.handle(.rowsChanged(hasRows: true, attention: attention), now: t + .seconds(1))
        #expect(state.nextTick == t + .seconds(8))
        #expect(state.peekItems == [.blocked(a), .system(.updateRequired)])
    }

    @Test func leavingAndReturningAttentionIsNewIncludingFinishedRecovery() {
        let t = ContinuousClock.now
        var state = collapsed(at: t)
        let attention = Attention(blocked: [a], finished: [b])
        state.handle(.rowsChanged(hasRows: true, attention: attention), now: t)
        state.handle(.rowsChanged(hasRows: true, attention: Attention()), now: t + .seconds(1))
        // Stale refs are omitted by the caller; recovery reintroduces them.
        state.handle(.rowsChanged(hasRows: true, attention: attention), now: t + .seconds(2))
        #expect(state.peekItems == [.blocked(a), .finished(b)])
        #expect(state.nextTick == t + .seconds(10))
    }

    @Test func hiddenUpdatesBaselineEvenWithAttention() {
        let t = ContinuousClock.now
        var state = PresentationState()
        let attention = Attention(blocked: [a], finished: [b], system: .unreachable)
        state.handle(.rowsChanged(hasRows: false, attention: attention), now: t)
        state.handle(.rowsChanged(hasRows: true, attention: attention), now: t + .seconds(1))
        #expect(state.surface == .collapsed)
        #expect(state.peekItems.isEmpty)
        state.handle(.rowsChanged(hasRows: false, attention: Attention()), now: t + .seconds(2))
        state.handle(.rowsChanged(hasRows: true, attention: attention), now: t + .seconds(3))
        #expect(state.peekItems == [.blocked(a), .system(.unreachable), .finished(b)])
    }

    @Test(arguments: ["hover", "exit", "click", "row", "outside"])
    func peekInteractions(_ interaction: String) {
        let t = ContinuousClock.now
        var state = collapsed(at: t)
        state.handle(.rowsChanged(hasRows: true, attention: Attention(blocked: [a])), now: t)
        switch interaction {
        case "hover":
            state.handle(.pointerEntered, now: t + .seconds(1))
            #expect(state.nextTick == t + .milliseconds(1120))
            state.handle(.tick, now: t + .milliseconds(1119))
            #expect(state.surface == .peek)
            state.handle(.tick, now: t + .milliseconds(1120))
            #expect(state.surface == .expanded(pinned: false, auto: false))
        case "exit":
            state.handle(.pointerEntered, now: t + .seconds(1))
            state.handle(.pointerExited, now: t + .milliseconds(1119))
            state.handle(.tick, now: t + .milliseconds(1120))
        case "click":
            state.handle(.clicked, now: t + .seconds(1))
            #expect(state.surface == .expanded(pinned: true, auto: false))
        case "row":
            state.handle(.rowActivated, now: t + .seconds(1))
            #expect(state.surface == .collapsed)
        default: state.handle(.clickedOutside, now: t + .seconds(1))
        }
        if interaction == "exit" || interaction == "outside" {
            #expect(state.surface == .peek)
            #expect(state.peekItems == [.blocked(a)])
            #expect(state.nextTick == t + .seconds(8))
        } else {
            #expect(state.peekItems.isEmpty)
            #expect(state.nextTick == nil)
        }
    }

    @Test(arguments: [false, true])
    func expandModeOverridesPeekAndHighlightsSimultaneousFinished(_ startInPeek: Bool) {
        let t = ContinuousClock.now
        var state = collapsed(at: t, alerts: AlertSettings(blocked: .expand))
        if startInPeek {
            state.handle(.rowsChanged(hasRows: true, attention: Attention(system: .unreachable)), now: t)
        }
        state.handle(.rowsChanged(hasRows: true, attention: Attention(blocked: [a], finished: [b], system: .unreachable)), now: t + .seconds(1))
        #expect(state.surface == .expanded(pinned: false, auto: true))
        #expect(state.peekItems.isEmpty)
        #expect(state.highlight == b)
        #expect(state.nextTick == t + .milliseconds(1900))
        state.handle(.tick, now: t + .milliseconds(1900))
        #expect(state.highlight == nil)
        #expect(state.nextTick == t + .seconds(9))
        state.handle(.tick, now: t + .seconds(9))
        #expect(state.surface == .collapsed)
        #expect(state.nextTick == nil)
    }

    @Test(arguments: [false, true])
    func pulseModeKeepsCurrentSurface(_ startInPeek: Bool) {
        let t = ContinuousClock.now
        var state = collapsed(at: t, alerts: AlertSettings(blocked: .pulse))
        if startInPeek {
            state.handle(.rowsChanged(hasRows: true, attention: Attention(finished: [b])), now: t)
        }
        let surface = state.surface
        let deadline = state.nextTick
        let items = state.peekItems
        state.handle(.rowsChanged(hasRows: true, attention: Attention(blocked: [a], finished: startInPeek ? [b] : [])), now: t + .seconds(1))
        #expect(state.pulse == 1)
        #expect(state.surface == surface)
        #expect(state.peekItems == items)
        #expect(state.nextTick == deadline)
    }

    @Test(arguments: [BlockedAlert.peek, .expand, .pulse], [FinishedAlert.peek, .ear, .off])
    func expandedHighlightsFirstNewRefWithoutPulseOrPeek(_ blocked: BlockedAlert, _ finished: FinishedAlert) {
        let t = ContinuousClock.now
        var state = collapsed(at: t, alerts: AlertSettings(blocked: blocked, finished: finished))
        state.handle(.clicked, now: t)
        state.handle(.rowsChanged(hasRows: true, attention: Attention(blocked: [b, a], finished: [c], system: .unreachable)), now: t)
        #expect(state.surface == .expanded(pinned: true, auto: false))
        #expect(state.peekItems.isEmpty)
        #expect(state.pulse == 0)
        #expect(state.highlight == b)
        #expect(state.nextTick == t + .milliseconds(900))
        state.handle(.tick, now: t + .milliseconds(899))
        #expect(state.highlight == b)
        state.handle(.tick, now: t + .milliseconds(900))
        #expect(state.highlight == nil)
        #expect(state.nextTick == nil)
        state.handle(.rowsChanged(hasRows: true, attention: Attention(blocked: [b, a], finished: [a, c], system: .updateRequired)), now: t + .seconds(1))
        #expect(state.highlight == (finished == .off ? nil : a))
        #expect(state.completion == nil)
    }

    @Test func expandedSystemAloneDoesNothing() {
        let t = ContinuousClock.now
        var state = collapsed(at: t)
        state.handle(.clicked, now: t)
        state.handle(.rowsChanged(hasRows: true, attention: Attention(system: .unreachable)), now: t)
        #expect(state.surface == .expanded(pinned: true, auto: false))
        #expect(state.peekItems.isEmpty)
        #expect(state.highlight == nil)
        #expect(state.nextTick == nil)
    }

    @Test func settingsKeepExistingPeekAndOnlyAffectNewEvents() {
        let t = ContinuousClock.now
        var state = collapsed(at: t)
        state.handle(.rowsChanged(hasRows: true, attention: Attention(blocked: [a], finished: [b])), now: t)
        state.handle(.settingsChanged(AlertSettings(blocked: .pulse, finished: .off)), now: t + .seconds(1))
        state.handle(.rowsChanged(hasRows: true, attention: Attention(blocked: [a], finished: [b, c])), now: t + .seconds(2))
        #expect(state.surface == .peek)
        #expect(state.peekItems == [.blocked(a), .finished(b)])
        #expect(state.nextTick == t + .seconds(8))
        state.handle(.rowsChanged(hasRows: true, attention: Attention(blocked: [a, c], finished: [b, c])), now: t + .seconds(3))
        #expect(state.pulse == 1)
        #expect(state.peekItems == [.blocked(a), .finished(b)])
        #expect(state.nextTick == t + .seconds(8))
    }

    @Test func peekDeadlineCanPrecedePendingHover() {
        let t = ContinuousClock.now
        var state = collapsed(at: t)
        state.handle(.rowsChanged(hasRows: true, attention: Attention(finished: [a])), now: t)
        state.handle(.pointerEntered, now: t + .milliseconds(3950))
        #expect(state.nextTick == t + .seconds(4))
        state.handle(.tick, now: t + .seconds(4))
        #expect(state.surface == .collapsed)
        #expect(state.peekItems.isEmpty)
    }

    @Test(arguments: ["peek", "ear", "highlight"])
    func noRowsClearsAllFeedbackAndTimers(_ mode: String) {
        let t = ContinuousClock.now
        var state = collapsed(at: t, alerts: AlertSettings(finished: mode == "ear" ? .ear : .peek))
        if mode == "highlight" { state.handle(.clicked, now: t) }
        state.handle(.rowsChanged(hasRows: true, attention: Attention(finished: [a])), now: t)
        state.handle(.rowsChanged(hasRows: false, attention: Attention()), now: t + .milliseconds(1))
        #expect(state.surface == .hidden)
        #expect(state.peekItems.isEmpty)
        #expect(state.completion == nil)
        #expect(state.highlight == nil)
        #expect(state.nextTick == nil)
        state.handle(.tick, now: t + .seconds(10))
        #expect(state.surface == .hidden)
    }
}

extension PeekTests {
    @Test func highlightAndExitTimersChooseEarliestDeadline() {
        let t = ContinuousClock.now
        var state = collapsed(at: t)
        state.handle(.pointerEntered, now: t)
        state.handle(.tick, now: t + .milliseconds(120))
        state.handle(.rowsChanged(hasRows: true, attention: Attention(blocked: [a])), now: t + .seconds(1))
        state.handle(.pointerExited, now: t + .milliseconds(1100))
        #expect(state.nextTick == t + .milliseconds(1380))
        state.handle(.pointerEntered, now: t + .milliseconds(1200))
        #expect(state.nextTick == t + .milliseconds(1900))
        state.handle(.tick, now: t + .milliseconds(1900))
        #expect(state.highlight == nil)
        #expect(state.surface == .expanded(pinned: false, auto: false))
        #expect(state.nextTick == nil)
    }
}
