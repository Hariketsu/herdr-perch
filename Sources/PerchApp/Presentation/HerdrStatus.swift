import PerchCore

/// One-line Herdr connection state for the About page.
struct HerdrStatus: Equatable {
    enum Level: Equatable { case connected, attention, offline }

    var level: Level
    var title: String

    static func make(_ sessions: [SessionState]) -> HerdrStatus {
        if sessions.isEmpty { return HerdrStatus(level: .offline, title: "Herdr isn’t running") }
        if sessions.contains(where: { if case .updateRequired = $0.health { true } else { false } }) {
            return HerdrStatus(level: .attention, title: "Herdr update required (0.9.5 or later)")
        }
        if sessions.contains(where: { if case .stale = $0.health { true } else { false } }) {
            return HerdrStatus(level: .attention, title: "Reconnecting to Herdr…")
        }
        let count = sessions.count
        return HerdrStatus(level: .connected, title: "Connected · \(count) session\(count == 1 ? "" : "s")")
    }
}
