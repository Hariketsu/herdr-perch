import PerchCore
import SwiftUI

/// Pixel ram data (architecture.md §6.2), cleaned up from the gpt-image reference in
/// ref/. The notch is black, so gaps and facial features are simply empty cells.
enum RamSprite {
    /// W head; horn L highlight, H base, S inner shade, R ridge; "." empty.
    static let grid = [
        "..........LLRLLR....",
        ".......W.HHHRHHRLL..",
        "......WW.HHHRHHRHHR.",
        ".....WW..HHHRSSRHRHL",
        ".........HHH...RRHHL",
        ".....WWW..H.....SHHL",
        "....WWWWW...WWW..RRR",
        "...WWWWWWWWWWWW..SHL",
        "..WWWWWWWWWWW....SHL",
        ".WWWWWWWWWWW....RRRR",
        "WWWWWWWWWWWW.SSRHHH.",
        "WWWWWWWWWWWW.HHRHH..",
        "WWWWWWWWWWWW..HRH...",
        "WWWWWWWWWWWWW.......",
        ".WWWWWWWWWWWWWWWWW..",
        ".......WWWWWWWWWWW..",
        "........WWWWWWWWWW..",
        "........WWWWWWWWW...",
        ".........WWWWWWW....",
    ]

    private static let prompt = [(8, 4), (9, 5), (10, 4), (9, 7), (9, 8)]  // ">-", Herdr's prompt
    private static let sleepy = [(9, 4), (10, 5), (10, 6), (9, 7)]          // "‿"

    static func face(_ status: DisplayStatus, stale: Bool) -> [(row: Int, col: Int)] {
        (stale || status == .idle ? sleepy : prompt).map { (row: $0.0, col: $0.1) }
    }

    static func headTone(_ status: DisplayStatus, stale: Bool) -> UInt32 {
        if stale { return 0x3A3A40 }
        switch status {
        case .blocked: return 0xF97316
        case .working: return 0x3B82F6
        case .finished: return 0x22C55E
        case .idle: return 0x55555C
        }
    }

    /// [L, H, S, R]
    static func hornTones(_ status: DisplayStatus, stale: Bool) -> [UInt32] {
        if stale { return [0x5E5E66, 0x50505A, 0x48484F, 0x3C3C42] }
        switch status {
        case .blocked: return [0xFDBA74, 0xFB923C, 0xFA8228, 0xEA580C]
        case .working: return [0x93C5FD, 0x60A5FA, 0x4F93F8, 0x2563EB]
        case .finished: return [0x86EFAC, 0x4ADE80, 0x34D06F, 0x16A34A]
        case .idle: return [0xA5A5AE, 0x8A8A93, 0x7A7A83, 0x63636B]
        }
    }
}

/// 20×19pt ram drawn cell by cell. Only a blocked ram hops (in a LayerLoop, which
/// costs a nested hosting view) and shows "!"; every other state is static.
struct PixelRam: View {
    var status: DisplayStatus?
    var stale = false
    var animates = true

    static let size = CGSize(width: 20, height: 19)

    var body: some View {
        Group {
            if isBlocked && animates {
                LayerLoop(kind: .hop) { drawing }
            } else {
                drawing
            }
        }
        .overlay(alignment: .topLeading) {
            if isBlocked {
                VStack(spacing: 1) {
                    Rectangle().frame(width: 2, height: 4)
                    Rectangle().frame(width: 2, height: 1)
                }
                .foregroundStyle(Color(hex: RamSprite.headTone(.blocked, stale: false)))
                .offset(x: -4)
            }
        }
        .accessibilityHidden(true)
    }

    private var drawing: some View {
        let status = status ?? .idle
        let head = Color(hex: RamSprite.headTone(status, stale: stale))
        let horn = RamSprite.hornTones(status, stale: stale).map { Color(hex: $0) }
        let face = Set(RamSprite.face(status, stale: stale).map { $0.row * 100 + $0.col })
        return Canvas { context, _ in
            for (y, row) in RamSprite.grid.enumerated() {
                for (x, character) in row.enumerated() where character != "." && !face.contains(y * 100 + x) {
                    let fill: Color = switch character {
                    case "L": horn[0]
                    case "H": horn[1]
                    case "S": horn[2]
                    case "R": horn[3]
                    default: head
                    }
                    context.fill(Path(CGRect(x: x, y: y, width: 1, height: 1)), with: .color(fill))
                }
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    private var isBlocked: Bool { status == .blocked && !stale }
}
