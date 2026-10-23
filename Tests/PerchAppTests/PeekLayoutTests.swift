import Testing
import PerchCore
@testable import PerchApp

@Suite struct PeekLayoutTests {
    @Test(arguments: [0, 3, 5])
    func splitsAtThreeCards(_ count: Int) {
        let items = (0..<count).map { PeekItem.blocked(AgentRef(session: "test", paneID: "p\($0)")) }
        let result = PeekLayout.split(items)
        #expect(PeekLayout.maxCards == 3)
        #expect(result.shown == Array(items.prefix(3)))
        #expect(result.overflow == max(0, count - 3))
    }
}
