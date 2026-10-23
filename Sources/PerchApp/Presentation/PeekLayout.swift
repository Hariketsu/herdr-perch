/// Peek shows at most three cards; the rest fold into "+N more" (ARCHITECTURE.md, Presentation).
enum PeekLayout {
    static let maxCards = 3

    static func split(_ items: [PeekItem]) -> (shown: [PeekItem], overflow: Int) {
        (Array(items.prefix(maxCards)), max(0, items.count - maxCards))
    }
}
