import Testing
import PerchCore

@Suite struct DisplayStatusTests {
    @Test func mapsEveryAgentStatus() {
        #expect(DisplayStatus(.blocked) == .blocked)
        #expect(DisplayStatus(.done) == .finished)
        #expect(DisplayStatus(.working) == .working)
        #expect(DisplayStatus(.idle) == .idle)
        #expect(DisplayStatus(.unknown) == .idle)
    }
    @Test func urgencyOrder() {
        #expect([DisplayStatus.idle, .working, .blocked, .finished].sorted() == [.blocked, .finished, .working, .idle])
    }
}
