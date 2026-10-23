import Foundation

enum DisplayPlacement: String {
    case builtInNotch
    case mainDisplay
}

/// User settings (ARCHITECTURE.md, Settings). Missing or unknown values fall back to defaults.
struct Preferences: Equatable {
    var compactStyle: CompactStyle = .birdCount
    /// Blocked agents always peek (ARCHITECTURE.md, Presentation); finished ones only when this is on.
    var peekOnFinished = true
    var displayPlacement: DisplayPlacement = .builtInNotch
    var launchAtLogin = false
    var followReduceMotion = false
    var cleanTitles = true

    static func load(from defaults: UserDefaults) -> Preferences {
        var preferences = Preferences()
        if let style = defaults.string(forKey: "compactStyle").flatMap(CompactStyle.init) { preferences.compactStyle = style }
        if let enabled = defaults.object(forKey: "peekOnFinished") as? Bool { preferences.peekOnFinished = enabled }
        if let placement = defaults.string(forKey: "displayPlacement").flatMap(DisplayPlacement.init) {
            preferences.displayPlacement = placement
        }
        if let enabled = defaults.object(forKey: "launchAtLogin") as? Bool { preferences.launchAtLogin = enabled }
        if let enabled = defaults.object(forKey: "followReduceMotion") as? Bool { preferences.followReduceMotion = enabled }
        if let enabled = defaults.object(forKey: "cleanTitles") as? Bool { preferences.cleanTitles = enabled }
        return preferences
    }

    func save(to defaults: UserDefaults) {
        defaults.set(compactStyle.rawValue, forKey: "compactStyle")
        defaults.set(peekOnFinished, forKey: "peekOnFinished")
        defaults.set(displayPlacement.rawValue, forKey: "displayPlacement")
        defaults.set(launchAtLogin, forKey: "launchAtLogin")
        defaults.set(followReduceMotion, forKey: "followReduceMotion")
        defaults.set(cleanTitles, forKey: "cleanTitles")
    }
}
