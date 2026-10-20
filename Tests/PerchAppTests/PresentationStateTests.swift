import Testing
@testable import PerchApp

@Suite struct PresentationStateTests {
    private func collapsed(at time: ContinuousClock.Instant) -> PresentationState {
        var state = PresentationState()
        state.handle(.rowsChanged(hasRows: true, newBlocked: false), now: time)
        return state
    }

    @Test func initialHiddenAndFirstRowsCollapsed() {
        let t0 = ContinuousClock.now
        var state = PresentationState()
        #expect(state.surface == .hidden)
        #expect(state.nextTick == nil)
        state.handle(.rowsChanged(hasRows: false, newBlocked: false), now: t0)
        #expect(state.surface == .hidden)
        state.handle(.rowsChanged(hasRows: true, newBlocked: false), now: t0)
        #expect(state.surface == .collapsed)
        #expect(state.nextTick == nil)
    }

    @Test func hoverExpandsAt120MillisecondsButNotBefore() throws {
        let t0 = ContinuousClock.now
        var state = collapsed(at: t0)
        state.handle(.pointerEntered, now: t0)
        #expect(state.surface == .collapsed)
        let deadline = try #require(state.nextTick)
        #expect(deadline == t0 + .milliseconds(120))
        state.handle(.tick, now: t0 + .milliseconds(119))
        #expect(state.surface == .collapsed)
        #expect(state.nextTick == deadline)
        state.handle(.tick, now: deadline)
        #expect(state.surface == .expanded(pinned: false, auto: false))
        #expect(state.nextTick == nil)
    }

    @Test func shortHoverDoesNotExpandAndCancelsIntent() {
        let t0 = ContinuousClock.now
        var state = collapsed(at: t0)
        state.handle(.pointerEntered, now: t0)
        state.handle(.pointerExited, now: t0 + .milliseconds(119))
        #expect(state.surface == .collapsed)
        #expect(state.nextTick == nil)
        state.handle(.tick, now: t0 + .seconds(1))
        #expect(state.surface == .collapsed)
    }

    @Test func pointerExitCollapsesAfter280Milliseconds() throws {
        let t0 = ContinuousClock.now
        var state = collapsed(at: t0)
        state.handle(.pointerEntered, now: t0)
        state.handle(.tick, now: t0 + .milliseconds(120))
        let exited = t0 + .seconds(1)
        state.handle(.pointerExited, now: exited)
        let deadline = try #require(state.nextTick)
        #expect(deadline == exited + .milliseconds(280))
        state.handle(.tick, now: exited + .milliseconds(279))
        #expect(state.surface == .expanded(pinned: false, auto: false))
        state.handle(.tick, now: deadline)
        #expect(state.surface == .collapsed)
        #expect(state.nextTick == nil)
    }

    @Test func pointerReentryCancelsExitDelay() {
        let t0 = ContinuousClock.now
        var state = collapsed(at: t0)
        state.handle(.pointerEntered, now: t0)
        state.handle(.tick, now: t0 + .milliseconds(120))
        state.handle(.pointerExited, now: t0 + .seconds(1))
        state.handle(.pointerEntered, now: t0 + .milliseconds(1100))
        state.handle(.tick, now: t0 + .seconds(2))
        #expect(state.surface == .expanded(pinned: false, auto: false))
        #expect(state.nextTick == nil)
    }

    @Test func clickTogglesPinnedExpansionAndCollapsed() {
        let t0 = ContinuousClock.now
        var state = collapsed(at: t0)
        state.handle(.clicked, now: t0)
        #expect(state.surface == .expanded(pinned: true, auto: false))
        state.handle(.clicked, now: t0 + .seconds(1))
        #expect(state.surface == .collapsed)
        #expect(state.nextTick == nil)
    }

    @Test func pinnedExpansionIgnoresPointerExit() {
        let t0 = ContinuousClock.now
        var state = collapsed(at: t0)
        state.handle(.clicked, now: t0)
        state.handle(.pointerExited, now: t0 + .seconds(1))
        #expect(state.nextTick == nil)
        state.handle(.tick, now: t0 + .seconds(100))
        #expect(state.surface == .expanded(pinned: true, auto: false))
    }

    @Test func clickOutsideCollapses() {
        let t0 = ContinuousClock.now
        var state = collapsed(at: t0)
        state.handle(.clicked, now: t0)
        state.handle(.clickedOutside, now: t0 + .seconds(1))
        #expect(state.surface == .collapsed)
        #expect(state.nextTick == nil)
    }

    @Test func newBlockedAutomaticallyExpandsAndCollapsesAtEightSeconds() throws {
        let t0 = ContinuousClock.now
        var state = collapsed(at: t0)
        state.handle(.rowsChanged(hasRows: true, newBlocked: true), now: t0)
        #expect(state.surface == .expanded(pinned: false, auto: true))
        let deadline = try #require(state.nextTick)
        #expect(deadline == t0 + .seconds(8))
        state.handle(.tick, now: t0 + .milliseconds(7999))
        #expect(state.surface == .expanded(pinned: false, auto: true))
        #expect(state.nextTick == deadline)
        state.handle(.tick, now: deadline)
        #expect(state.surface == .collapsed)
        #expect(state.nextTick == nil)
    }

    @Test func pointerEntryTakesOverAutomaticExpansion() {
        let t0 = ContinuousClock.now
        var state = collapsed(at: t0)
        state.handle(.rowsChanged(hasRows: true, newBlocked: true), now: t0)
        state.handle(.pointerEntered, now: t0 + .seconds(1))
        #expect(state.surface == .expanded(pinned: false, auto: false))
        #expect(state.nextTick == nil)
        state.handle(.tick, now: t0 + .seconds(8))
        #expect(state.surface == .expanded(pinned: false, auto: false))
    }

    @Test func clickTakesOverAutomaticExpansion() {
        let t0 = ContinuousClock.now
        var state = collapsed(at: t0)
        state.handle(.rowsChanged(hasRows: true, newBlocked: true), now: t0)
        state.handle(.clicked, now: t0 + .seconds(1))
        // The contract requires expanded with auto cleared, but does not specify pinning here.
        if case let .expanded(_, automatic) = state.surface { #expect(!automatic) }
        else { Issue.record("Clicking an automatic expansion must keep it expanded") }
        #expect(state.nextTick == nil)
        let manual = state.surface
        state.handle(.tick, now: t0 + .seconds(8))
        #expect(state.surface == manual)
    }

    @Test func rowActivationCollapses() {
        let t0 = ContinuousClock.now
        var state = collapsed(at: t0)
        state.handle(.clicked, now: t0)
        state.handle(.rowActivated, now: t0 + .seconds(1))
        #expect(state.surface == .collapsed)
        #expect(state.nextTick == nil)
    }

    @Test func disabledAutomaticExpansionAndSettingChanges() {
        let t0 = ContinuousClock.now
        var state = PresentationState(autoExpandOnBlocked: false)
        state.handle(.rowsChanged(hasRows: true, newBlocked: false), now: t0)
        state.handle(.rowsChanged(hasRows: true, newBlocked: true), now: t0)
        #expect(state.surface == .collapsed)
        #expect(state.nextTick == nil)
        state.handle(.settingsChanged(autoExpandOnBlocked: true), now: t0)
        state.handle(.rowsChanged(hasRows: true, newBlocked: true), now: t0)
        #expect(state.surface == .expanded(pinned: false, auto: true))
        state.handle(.clickedOutside, now: t0)
        state.handle(.settingsChanged(autoExpandOnBlocked: false), now: t0)
        state.handle(.rowsChanged(hasRows: true, newBlocked: true), now: t0)
        #expect(state.surface == .collapsed)
        #expect(state.nextTick == nil)
    }

    @Test func losingAllRowsHidesEverySurfaceAndCancelsTimers() {
        let t0 = ContinuousClock.now
        for mode in 0..<4 {
            var state = collapsed(at: t0)
            switch mode {
            case 1: state.handle(.clicked, now: t0)
            case 2: state.handle(.rowsChanged(hasRows: true, newBlocked: true), now: t0)
            case 3: state.handle(.pointerEntered, now: t0)
            default: break
            }
            state.handle(.rowsChanged(hasRows: false, newBlocked: false), now: t0 + .milliseconds(1))
            #expect(state.surface == .hidden)
            #expect(state.nextTick == nil)
            state.handle(.tick, now: t0 + .seconds(10))
            #expect(state.surface == .hidden)
        }
    }
}
