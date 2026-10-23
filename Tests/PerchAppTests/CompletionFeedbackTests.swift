import Testing
import PerchCore
@testable import PerchApp

@Suite struct CompletionFeedbackTests {
    private let a = AgentRef(session: "test", paneID: "p1")
    private let b = AgentRef(session: "test", paneID: "p2")

    private func collapsed(at time: ContinuousClock.Instant, blocked: BlockedAlert = .peek) -> PresentationState {
        var state = PresentationState(alerts: AlertSettings(blocked: blocked, finished: .ear))
        state.handle(.rowsChanged(hasRows: true, attention: Attention()), now: time)
        return state
    }

    @Test func earLastsExactlyTwoSecondsAndDuplicateDoesNotRestart() {
        let t = ContinuousClock.now
        var state = collapsed(at: t)
        let attention = Attention(finished: [a])
        state.handle(.rowsChanged(hasRows: true, attention: attention), now: t)
        #expect(state.surface == .collapsed)
        #expect(state.completion == a)
        #expect(state.nextTick == t + .seconds(2))
        state.handle(.rowsChanged(hasRows: true, attention: attention), now: t + .seconds(1))
        #expect(state.nextTick == t + .seconds(2))
        state.handle(.tick, now: t + .milliseconds(1999))
        #expect(state.completion == a)
        state.handle(.tick, now: t + .seconds(2))
        #expect(state.completion == nil)
        #expect(state.nextTick == nil)
        state.handle(.rowsChanged(hasRows: true, attention: attention), now: t + .seconds(3))
        #expect(state.completion == nil)
    }

    @Test func nextCompletionReplacesRefAndRestartsDuration() {
        let t = ContinuousClock.now
        var state = collapsed(at: t)
        state.handle(.rowsChanged(hasRows: true, attention: Attention(finished: [a])), now: t)
        state.handle(.rowsChanged(hasRows: true, attention: Attention(finished: [b, a])), now: t + .seconds(1))
        #expect(state.completion == b)
        #expect(state.nextTick == t + .seconds(3))
        state.handle(.tick, now: t + .seconds(2))
        #expect(state.completion == b)
        state.handle(.tick, now: t + .seconds(3))
        #expect(state.completion == nil)
        #expect(state.nextTick == nil)
    }

    @Test func firstFinishedIsBaselineAndRecoveryCanNotifyAgain() {
        let t = ContinuousClock.now
        var state = PresentationState(alerts: AlertSettings(finished: .ear))
        state.handle(.rowsChanged(hasRows: true, attention: Attention(finished: [a])), now: t)
        #expect(state.completion == nil)
        // A stale or absent finished ref is excluded from Attention by NotchModel.
        state.handle(.rowsChanged(hasRows: true, attention: Attention()), now: t + .seconds(1))
        state.handle(.rowsChanged(hasRows: true, attention: Attention(finished: [a])), now: t + .seconds(2))
        #expect(state.completion == a)
        #expect(state.nextTick == t + .seconds(4))
    }

    @Test(arguments: ["peek", "click", "hover", "expand", "hide"])
    func leavingCollapsedClearsEarAndOldDeadline(_ transition: String) {
        let t = ContinuousClock.now
        var state = collapsed(at: t, blocked: transition == "expand" ? .expand : .peek)
        state.handle(.rowsChanged(hasRows: true, attention: Attention(finished: [a])), now: t)
        switch transition {
        case "click": state.handle(.clicked, now: t + .seconds(1))
        case "hover":
            state.handle(.pointerEntered, now: t + .seconds(1))
            #expect(state.nextTick == t + .milliseconds(1120))
            state.handle(.tick, now: t + .milliseconds(1120))
        case "hide": state.handle(.rowsChanged(hasRows: false, attention: Attention()), now: t + .seconds(1))
        default:
            state.handle(.rowsChanged(hasRows: true, attention: Attention(blocked: [b], finished: [a])), now: t + .seconds(1))
        }
        #expect(state.completion == nil)
        let deadline: ContinuousClock.Instant? = (transition == "peek" || transition == "expand") ? t + .seconds(9) : nil
        #expect(state.nextTick == deadline)
        let surface = state.surface
        state.handle(.tick, now: t + .seconds(2))
        #expect(state.surface == surface)
        #expect(state.nextTick == deadline)
    }

    @Test func earDuringPeekIsIgnoredAndStillUpdatesBaseline() {
        let t = ContinuousClock.now
        var state = collapsed(at: t)
        state.handle(.rowsChanged(hasRows: true, attention: Attention(blocked: [a])), now: t)
        let attention = Attention(blocked: [a], finished: [b])
        state.handle(.rowsChanged(hasRows: true, attention: attention), now: t + .seconds(1))
        #expect(state.surface == .peek)
        #expect(state.peekItems == [.blocked(a)])
        #expect(state.completion == nil)
        #expect(state.nextTick == t + .seconds(8))
        state.handle(.tick, now: t + .seconds(8))
        state.handle(.rowsChanged(hasRows: true, attention: attention), now: t + .seconds(9))
        #expect(state.surface == .collapsed)
        #expect(state.completion == nil)
    }

    @Test func offDoesNotScheduleFeedback() {
        let t = ContinuousClock.now
        var state = PresentationState(alerts: AlertSettings(finished: .off))
        state.handle(.rowsChanged(hasRows: true, attention: Attention()), now: t)
        state.handle(.rowsChanged(hasRows: true, attention: Attention(finished: [a])), now: t)
        #expect(state.surface == .collapsed)
        #expect(state.completion == nil)
        #expect(state.peekItems.isEmpty)
        #expect(state.nextTick == nil)
    }

    @Test func earlierEarDeadlineKeepsPendingHoverIntent() {
        let t = ContinuousClock.now
        var state = collapsed(at: t)
        state.handle(.rowsChanged(hasRows: true, attention: Attention(finished: [a])), now: t)
        state.handle(.pointerEntered, now: t + .milliseconds(1950))
        #expect(state.nextTick == t + .seconds(2))
        state.handle(.tick, now: t + .seconds(2))
        #expect(state.completion == nil)
        #expect(state.surface == .collapsed)
        #expect(state.nextTick == t + .milliseconds(2070))
        state.handle(.tick, now: t + .milliseconds(2070))
        #expect(state.surface == .expanded(pinned: false, auto: false))
        #expect(state.nextTick == nil)
    }

    @Test func completionDuringHoverDoesNotReplaceHoverTimer() {
        let t = ContinuousClock.now
        var state = collapsed(at: t)
        state.handle(.pointerEntered, now: t)
        state.handle(.rowsChanged(hasRows: true, attention: Attention(finished: [a])), now: t + .milliseconds(50))
        #expect(state.completion == a)
        #expect(state.nextTick == t + .milliseconds(120))
        state.handle(.tick, now: t + .milliseconds(120))
        #expect(state.surface == .expanded(pinned: false, auto: false))
        #expect(state.completion == nil)
        #expect(state.nextTick == nil)
    }

    @Test func cancellingHoverKeepsEarDeadline() {
        let t = ContinuousClock.now
        var state = collapsed(at: t)
        state.handle(.rowsChanged(hasRows: true, attention: Attention(finished: [a])), now: t)
        state.handle(.pointerEntered, now: t + .milliseconds(500))
        state.handle(.pointerExited, now: t + .milliseconds(550))
        #expect(state.completion == a)
        #expect(state.nextTick == t + .seconds(2))
        state.handle(.tick, now: t + .seconds(2))
        #expect(state.completion == nil)
        #expect(state.nextTick == nil)
    }

    @Test func pulseAndEarDoNotRestartEachOther() {
        let t = ContinuousClock.now
        var state = collapsed(at: t, blocked: .pulse)
        state.handle(.rowsChanged(hasRows: true, attention: Attention(blocked: [a])), now: t)
        state.handle(.rowsChanged(hasRows: true, attention: Attention(blocked: [a], finished: [b])), now: t + .milliseconds(100))
        #expect(state.pulse == 1)
        #expect(state.completion == b)
        #expect(state.nextTick == t + .milliseconds(2100))
        state.handle(.rowsChanged(hasRows: true, attention: Attention(blocked: [a, b], finished: [b])), now: t + .milliseconds(500))
        #expect(state.pulse == 2)
        #expect(state.completion == b)
        #expect(state.nextTick == t + .milliseconds(2100))
    }
}
