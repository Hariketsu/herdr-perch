import Foundation

enum ListStyle: String {
    case grouped
    case heroAndRows
    case rowsOnly
}

enum DisplayPlacement: String {
    case builtInNotch
    case mainDisplay
}

/// User settings (product.md §8). Missing or unknown values fall back to defaults.
struct Preferences: Equatable {
    var compactStyle: CompactStyle = .birdCount
    var listStyle: ListStyle = .grouped
    var blockedAlert: BlockedAlert = .peek
    var finishedAlert: FinishedAlert = .peek
    var displayPlacement: DisplayPlacement = .builtInNotch
    var launchAtLogin = false
    var followReduceMotion = false
    var cleanTitles = true

    var alerts: AlertSettings { AlertSettings(blocked: blockedAlert, finished: finishedAlert) }

    static func load(from defaults: UserDefaults) -> Preferences {
        var preferences = Preferences()
        if let style = defaults.string(forKey: "compactStyle").flatMap(CompactStyle.init) { preferences.compactStyle = style }
        if let style = defaults.string(forKey: "listStyle").flatMap(ListStyle.init) { preferences.listStyle = style }
        if let alert = defaults.string(forKey: "blockedAlert").flatMap(BlockedAlert.init) {
            preferences.blockedAlert = alert
        } else if defaults.string(forKey: "blockedAlert") == nil, defaults.object(forKey: "autoExpandOnBlocked") as? Bool == false {
            preferences.blockedAlert = .pulse  // before 0.2: "Expand when an agent is blocked" turned off
        }
        if let alert = defaults.string(forKey: "finishedAlert").flatMap(FinishedAlert.init) { preferences.finishedAlert = alert }
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
        defaults.set(listStyle.rawValue, forKey: "listStyle")
        defaults.set(blockedAlert.rawValue, forKey: "blockedAlert")
        defaults.set(finishedAlert.rawValue, forKey: "finishedAlert")
        defaults.set(displayPlacement.rawValue, forKey: "displayPlacement")
        defaults.set(launchAtLogin, forKey: "launchAtLogin")
        defaults.set(followReduceMotion, forKey: "followReduceMotion")
        defaults.set(cleanTitles, forKey: "cleanTitles")
    }
}
