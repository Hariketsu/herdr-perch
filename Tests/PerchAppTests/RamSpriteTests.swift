import Testing
import PerchCore
@testable import PerchApp

@Suite struct RamSpriteTests {
    @Test func gridHasExpectedDimensionsAndOnlyKnownCells() {
        #expect(RamSprite.grid.count == 19)
        let allowed = Set("WLHSR.")
        for row in RamSprite.grid {
            #expect(row.count == 20)
            #expect(Set(row).isSubset(of: allowed))
        }
    }

    @Test(arguments: [DisplayStatus.blocked, .finished, .working, .idle])
    func faceSelectsClosedEyesOrPrompt(_ status: DisplayStatus) {
        let closed = Set(RamSprite.face(.idle, stale: false).map { [$0.row, $0.col] })
        let prompt = Set(RamSprite.face(.working, stale: false).map { [$0.row, $0.col] })
        #expect(!closed.isEmpty)
        #expect(!prompt.isEmpty)
        #expect(closed != prompt)
        #expect(Set(RamSprite.face(status, stale: false).map { [$0.row, $0.col] }) == (status == .idle ? closed : prompt))
        #expect(Set(RamSprite.face(status, stale: true).map { [$0.row, $0.col] }) == closed)
    }

    @Test(arguments: [DisplayStatus.blocked, .finished, .working, .idle], [false, true])
    func faceCellsAreInsideTheHead(_ status: DisplayStatus, _ stale: Bool) throws {
        let grid = RamSprite.grid.map(Array.init)
        for cell in RamSprite.face(status, stale: stale) {
            try #require(grid.indices.contains(cell.row))
            try #require(grid[cell.row].indices.contains(cell.col))
            #expect(grid[cell.row][cell.col] == "W")
        }
    }

    @Test(arguments: [
        (DisplayStatus.blocked, UInt32(0xF97316), [UInt32(0xFDBA74), 0xFB923C, 0xFA8228, 0xEA580C]),
        (DisplayStatus.working, UInt32(0x3B82F6), [UInt32(0x93C5FD), 0x60A5FA, 0x4F93F8, 0x2563EB]),
        (DisplayStatus.finished, UInt32(0x22C55E), [UInt32(0x86EFAC), 0x4ADE80, 0x34D06F, 0x16A34A]),
        (DisplayStatus.idle, UInt32(0x55555C), [UInt32(0xA5A5AE), 0x8A8A93, 0x7A7A83, 0x63636B])
    ])
    func liveColorsMatchStatus(_ status: DisplayStatus, _ head: UInt32, _ horns: [UInt32]) {
        #expect(RamSprite.headTone(status, stale: false) == head)
        #expect(RamSprite.hornTones(status, stale: false).count == 4)
        #expect(RamSprite.hornTones(status, stale: false) == horns)
    }

    @Test(arguments: [DisplayStatus.blocked, .finished, .working, .idle])
    func staleColorsAreIndependentOfStatus(_ status: DisplayStatus) {
        #expect(RamSprite.headTone(status, stale: true) == 0x3A3A40)
        #expect(RamSprite.hornTones(status, stale: true).count == 4)
        #expect(RamSprite.hornTones(status, stale: true) == [0x5E5E66, 0x50505A, 0x48484F, 0x3C3C42])
    }
}
