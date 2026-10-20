import CoreGraphics
import PerchCore

enum CompactStyle: String {
    case birdCount = "A"
    case dots = "B"
    case counts = "C"
}

/// What the collapsed ears show, derived from rows already in display order.
struct CompactSummary: Equatable {
    static let maxDots = 6

    var birdStatus: DisplayStatus?
    var dots: [DisplayStatus]
    var overflow: Int
    var counts: [DisplayStatus: Int]
    var total: Int
    var allStale: Bool

    static func make(_ rows: [AgentRow]) -> CompactSummary {
        CompactSummary(
            birdStatus: rows.map(\.status).min(),
            dots: rows.prefix(maxDots).map(\.status),
            overflow: max(0, rows.count - maxDots),
            counts: rows.reduce(into: [:]) { $0[$1.status, default: 0] += 1 },
            total: rows.count,
            allStale: !rows.isEmpty && rows.allSatisfy(\.isStale))
    }

    /// Per-ear width, matching docs/prototype notch.jsx `wingWidth`.
    func wingWidth(_ style: CompactStyle) -> CGFloat {
        switch style {
        case .birdCount: 30
        case .dots: max(40, CGFloat(min(total, Self.maxDots) * 10 + 22))
        case .counts: max(40, CGFloat(counts.count * 24 + 16))
        }
    }
}
