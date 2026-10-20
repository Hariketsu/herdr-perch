import Testing
@testable import PerchApp

@Suite struct CompletionFeedbackTests {
    private func collapsed(at time: ContinuousClock.Instant, autoExpandOnBlocked: Bool = true) -> PresentationState {
        var state = PresentationState(autoExpandOnBlocked: autoExpandOnBlocked)
        state.handle(.rowsChanged(hasRows: true, newBlocked: false), now: time)
        return state
    }

    @Test func collapsedFeedbackLastsTwoSecondsAndNotLess() {
        let t0 = ContinuousClock.now
        var state = collapsed(at: t0)
        #expect(PresentationState.completionDuration == .seconds(2))
        #expect(state.completion == nil)
        state.handle(.agentFinished(title: "Build passed"), now: t0)
        #expect(state.surface == .collapsed)
        #expect(state.completion == "Build passed")
        #expect(state.nextTick == t0 + .seconds(2))
        state.handle(.tick, now: t0 + .milliseconds(1999))
        #expect(state.completion == "Build passed")
        #expect(state.nextTick == t0 + .seconds(2))
        state.handle(.tick, now: t0 + .seconds(2))
        #expect(state.completion == nil)
        #expect(state.nextTick == nil)
        #expect(state.surface == .collapsed)
    }

    @Test func nextCompletionReplacesTitleAndRestartsItsFullDuration() {
        let t0 = ContinuousClock.now
        var state = collapsed(at: t0)
        state.handle(.agentFinished(title: "First task"), now: t0)
        state.handle(.agentFinished(title: "Second task"), now: t0 + .seconds(1))
        #expect(state.completion == "Second task")
        #expect(state.nextTick == t0 + .seconds(3))
        state.handle(.tick, now: t0 + .seconds(2))
        #expect(state.completion == "Second task")
        #expect(state.nextTick == t0 + .seconds(3))
        state.handle(.tick, now: t0 + .milliseconds(2999))
        #expect(state.completion == "Second task")
        state.handle(.tick, now: t0 + .seconds(3))
        #expect(state.completion == nil)
        #expect(state.nextTick == nil)
    }

    @Test(arguments: ["hidden", "pinned", "hover", "auto"])
    func feedbackOutsideCollapsedIsIgnoredWithoutChangingOtherState(_ mode: String) {
        let t0 = ContinuousClock.now
        var state = PresentationState()
        if mode != "hidden" {
            state = collapsed(at: t0)
            switch mode {
            case "pinned": state.handle(.clicked, now: t0)
            case "hover":
                state.handle(.pointerEntered, now: t0)
                state.handle(.tick, now: t0 + .milliseconds(120))
            default: state.handle(.rowsChanged(hasRows: true, newBlocked: true), now: t0)
            }
        }
        let surface = state.surface
        let deadline = state.nextTick
        let pulse = state.pulse
        state.handle(.agentFinished(title: "Ignored task"), now: t0 + .seconds(1))
        #expect(state.completion == nil)
        #expect(state.surface == surface)
        #expect(state.nextTick == deadline)
        #expect(state.pulse == pulse)
    }

    @Test(arguments: ["click", "auto", "hide"])
    func leavingCollapsedImmediatelyClearsFeedbackAndItsOldTimer(_ transition: String) {
        let t0 = ContinuousClock.now
        var state = collapsed(at: t0)
        state.handle(.agentFinished(title: "Finished task"), now: t0)
        switch transition {
        case "click": state.handle(.clicked, now: t0 + .seconds(1))
        case "auto": state.handle(.rowsChanged(hasRows: true, newBlocked: true), now: t0 + .seconds(1))
        default: state.handle(.rowsChanged(hasRows: false, newBlocked: false), now: t0 + .seconds(1))
        }
        #expect(state.completion == nil)
        switch transition {
        case "click": #expect(state.surface == .expanded(pinned: true, auto: false))
        case "auto": #expect(state.surface == .expanded(pinned: false, auto: true))
        default: #expect(state.surface == .hidden)
        }
        let surface = state.surface
        #expect(state.nextTick == (transition == "auto" ? t0 + .seconds(9) : nil))
        state.handle(.tick, now: t0 + .seconds(2))
        #expect(state.surface == surface)
        #expect(state.completion == nil)
        #expect(state.nextTick == (transition == "auto" ? t0 + .seconds(9) : nil))
    }

    @Test func earlierHoverDeadlineExpandsAndClearsFeedback() {
        let t0 = ContinuousClock.now
        var state = collapsed(at: t0)
        state.handle(.agentFinished(title: "Finished task"), now: t0)
        state.handle(.pointerEntered, now: t0 + .seconds(1))
        #expect(state.completion == "Finished task")
        #expect(state.nextTick == t0 + .milliseconds(1120))
        state.handle(.tick, now: t0 + .milliseconds(1119))
        #expect(state.surface == .collapsed)
        #expect(state.completion == "Finished task")
        state.handle(.tick, now: t0 + .milliseconds(1120))
        #expect(state.surface == .expanded(pinned: false, auto: false))
        #expect(state.completion == nil)
        #expect(state.nextTick == nil)
    }

    @Test func earlierCompletionDeadlineKeepsPendingHoverIntent() {
        let t0 = ContinuousClock.now
        var state = collapsed(at: t0)
        state.handle(.agentFinished(title: "Finished task"), now: t0)
        state.handle(.pointerEntered, now: t0 + .milliseconds(1950))
        #expect(state.nextTick == t0 + .seconds(2))
        state.handle(.tick, now: t0 + .milliseconds(1999))
        #expect(state.completion == "Finished task")
        state.handle(.tick, now: t0 + .seconds(2))
        #expect(state.completion == nil)
        #expect(state.surface == .collapsed)
        #expect(state.nextTick == t0 + .milliseconds(2070))
        state.handle(.tick, now: t0 + .milliseconds(2069))
        #expect(state.surface == .collapsed)
        state.handle(.tick, now: t0 + .milliseconds(2070))
        #expect(state.surface == .expanded(pinned: false, auto: false))
        #expect(state.completion == nil)
        #expect(state.nextTick == nil)
    }

    @Test func completionReceivedDuringHoverIntentDoesNotReplaceHoverTimer() {
        let t0 = ContinuousClock.now
        var state = collapsed(at: t0)
        state.handle(.pointerEntered, now: t0)
        state.handle(.agentFinished(title: "Finished task"), now: t0 + .milliseconds(50))
        #expect(state.completion == "Finished task")
        #expect(state.nextTick == t0 + .milliseconds(120))
        state.handle(.tick, now: t0 + .milliseconds(120))
        #expect(state.surface == .expanded(pinned: false, auto: false))
        #expect(state.completion == nil)
        #expect(state.nextTick == nil)
    }

    @Test func cancellingHoverKeepsFeedbackAndItsDeadline() {
        let t0 = ContinuousClock.now
        var state = collapsed(at: t0)
        state.handle(.agentFinished(title: "Finished task"), now: t0)
        state.handle(.pointerEntered, now: t0 + .milliseconds(500))
        state.handle(.pointerExited, now: t0 + .milliseconds(550))
        #expect(state.completion == "Finished task")
        #expect(state.nextTick == t0 + .seconds(2))
        state.handle(.tick, now: t0 + .milliseconds(620))
        #expect(state.surface == .collapsed)
        #expect(state.completion == "Finished task")
        #expect(state.nextTick == t0 + .seconds(2))
        state.handle(.tick, now: t0 + .seconds(2))
        #expect(state.completion == nil)
        #expect(state.nextTick == nil)
    }

    @Test func pulseAndCompletionDoNotClearRestartOrIncrementEachOther() {
        let t0 = ContinuousClock.now
        var state = collapsed(at: t0, autoExpandOnBlocked: false)
        let initial = state.pulse
        state.handle(.rowsChanged(hasRows: true, newBlocked: true), now: t0)
        #expect(state.pulse == initial + 1)
        #expect(state.completion == nil)
        state.handle(.agentFinished(title: "First task"), now: t0 + .milliseconds(100))
        #expect(state.pulse == initial + 1)
        #expect(state.completion == "First task")
        #expect(state.nextTick == t0 + .milliseconds(2100))
        state.handle(.rowsChanged(hasRows: true, newBlocked: true), now: t0 + .milliseconds(500))
        #expect(state.pulse == initial + 2)
        #expect(state.completion == "First task")
        #expect(state.nextTick == t0 + .milliseconds(2100))
        state.handle(.agentFinished(title: "Second task"), now: t0 + .seconds(1))
        #expect(state.pulse == initial + 2)
        #expect(state.nextTick == t0 + .seconds(3))
        state.handle(.tick, now: t0 + .milliseconds(2100))
        #expect(state.completion == "Second task")
        #expect(state.pulse == initial + 2)
        state.handle(.tick, now: t0 + .seconds(3))
        #expect(state.completion == nil)
        #expect(state.pulse == initial + 2)
    }
}
