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

    /// Cells grouped by tone character (W, L, H, S, R), with the face punched out.
    static func paths(status: DisplayStatus, stale: Bool, cell: CGFloat) -> [Character: Path] {
        let face = Set(face(status, stale: stale).map { $0.row * 100 + $0.col })
        var paths: [Character: Path] = [:]
        for (y, row) in grid.enumerated() {
            for (x, character) in row.enumerated() where character != "." && !face.contains(y * 100 + x) {
                paths[character, default: Path()].addRect(
                    CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell))
            }
        }
        return paths
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

/// 20×19-cell ram, one path per tone. Lists use 1pt cells; the collapsed ear and the
/// menu bar use 0.8 so it matches the size of other menu bar icons. Only a blocked ram
/// hops (in a LayerLoop, which costs a nested hosting view) and shows "!"; every other
/// state is static.
struct PixelRam: View {
    var status: DisplayStatus?
    var stale = false
    var animates = true
    var scale: CGFloat = 1

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
                VStack(spacing: scale) {
                    Rectangle().frame(width: 2 * scale, height: 4 * scale)
                    Rectangle().frame(width: 2 * scale, height: scale)
                }
                .foregroundStyle(Color(hex: RamSprite.headTone(.blocked, stale: false)))
                .offset(x: -4 * scale)
            }
        }
        .accessibilityHidden(true)
    }

    private var drawing: some View {
        let status = status ?? .idle
        let horn = RamSprite.hornTones(status, stale: stale)
        let tones: [Character: UInt32] = [
            "W": RamSprite.headTone(status, stale: stale), "L": horn[0], "H": horn[1], "S": horn[2], "R": horn[3],
        ]
        let paths = RamSprite.paths(status: status, stale: stale, cell: scale)
        return Canvas { context, _ in
            // One fill per tone: per-cell fills leave hairline seams at fractional scales.
            for (tone, path) in paths { context.fill(path, with: .color(Color(hex: tones[tone]!))) }
        }
        .frame(width: 20 * scale, height: 19 * scale)
    }

    private var isBlocked: Bool { status == .blocked && !stale }
}
