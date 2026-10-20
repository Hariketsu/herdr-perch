import Foundation

enum ListStyle: String {
    case heroAndRows
    case rowsOnly
}

enum DisplayPlacement: String {
    case builtInNotch
    case mainDisplay
}

struct Preferences: Equatable {
    var compactStyle: CompactStyle = .dots
    var listStyle: ListStyle = .heroAndRows
    var autoExpandOnBlocked = true
    var displayPlacement: DisplayPlacement = .builtInNotch
    var launchAtLogin = false

    static func load(from defaults: UserDefaults) -> Preferences { fatalError("unimplemented") }
    func save(to defaults: UserDefaults) { fatalError("unimplemented") }
}
