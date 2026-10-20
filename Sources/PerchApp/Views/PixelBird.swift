import PerchCore
import SwiftUI

/// Perched pixel bird, drawn like Vibe Island's pixel pet ('#' body, 'e' eye, 'b' beak/legs).
struct PixelBird: View {
    var status: DisplayStatus?
    var stale = false
    var size: CGFloat = 16

    private static let open = [
        "..........",
        ".....##...",
        "....#e##bb",
        "....####..",
        "..######..",
        "########..",
        "...#####..",
        "....b..b..",
    ]
    private static let shut = open.enumerated().map { $0.offset == 2 ? "....####bb" : $0.element }

    var body: some View {
        let (main, bright) = Palette.birdTones(status, stale: stale)
        let rows = (status == .idle || status == nil || stale) ? Self.shut : Self.open
        LayerLoop(kind: isBlocked ? .hop : nil) {
            Canvas { context, canvas in
                let cell = canvas.height / 8
                for (y, row) in rows.enumerated() {
                    for (x, character) in row.enumerated() where character != "." {
                        let fill: Color = character == "#" ? main : character == "e" ? .black : bright
                        context.fill(Path(CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell)),
                                     with: .color(fill))
                    }
                }
            }
            .frame(width: size * 1.25, height: size)
        }
        .accessibilityHidden(true)
    }

    private var isBlocked: Bool { status == .blocked && !stale }
}
