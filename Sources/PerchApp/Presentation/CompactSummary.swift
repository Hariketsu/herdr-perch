import PerchCore

enum CompactStyle: String {
    case birdCount = "A"
    case dots = "B"
    case counts = "C"
}

struct CompactSummary: Equatable {
    static let maxDots = 8

    var birdStatus: DisplayStatus?
    var dots: [DisplayStatus]
    var overflow: Int
    var counts: [DisplayStatus: Int]
    var total: Int
    var allStale: Bool

    static func make(_ rows: [AgentRow]) -> CompactSummary { fatalError("unimplemented") }
}
