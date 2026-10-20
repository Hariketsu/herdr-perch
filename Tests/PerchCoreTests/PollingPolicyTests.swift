import Testing
import PerchCore

@Suite struct PollingPolicyTests {
    @Test func reachable() {
        #expect(PollingPolicy.interval(streamHealthy: true, consecutiveFailures: 0) == .seconds(3))
        #expect(PollingPolicy.interval(streamHealthy: false, consecutiveFailures: 0) == .milliseconds(500))
    }

    @Test(arguments: [true, false])
    func unreachableBackoffOverridesStreamHealth(_ healthy: Bool) {
        for (failures, seconds) in [(1, 1), (2, 2), (3, 4), (4, 8), (5, 10), (6, 10), (100, 10), (Int.max, 10)] {
            #expect(PollingPolicy.interval(streamHealthy: healthy, consecutiveFailures: failures) == .seconds(seconds))
        }
    }
}
