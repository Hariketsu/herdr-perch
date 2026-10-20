import PerchCore
import SwiftUI

/// Tokens from vibeisland.app, as fixed in docs/prototype.
enum Palette {
    static let alert = Color(hex: 0xF97316), alertBright = Color(hex: 0xFB923C)
    static let work = Color(hex: 0x3B82F6), workBright = Color(hex: 0x60A5FA)
    static let finished = Color(hex: 0x22C55E), finishedBright = Color(hex: 0x4ADE80)
    static let idle = Color(hex: 0x737373)
    static let offline = Color(hex: 0x444444)
    static let notice = Color(hex: 0xFBBF24)

    static func color(_ status: DisplayStatus, stale: Bool = false) -> Color {
        if stale { return offline }
        switch status {
        case .blocked: return alert
        case .finished: return finished
        case .working: return work
        case .idle: return idle
        }
    }

    /// Main and highlight tone for the pixel bird.
    static func birdTones(_ status: DisplayStatus?, stale: Bool) -> (Color, Color) {
        if stale { return (Color(hex: 0x3F3F3F), Color(hex: 0x555555)) }
        switch status {
        case .blocked: return (alert, alertBright)
        case .finished: return (finished, finishedBright)
        case .working: return (work, workBright)
        case .idle, nil: return (Color(hex: 0x6B6B6B), Color(hex: 0x9A9A9A))
        }
    }

    // Notch motion, from vibeisland.app's demo (architecture.md §6.1).
    static let open = Animation.timingCurve(0.175, 0.885, 0.32, 1.1, duration: 0.5)  // growing: vibeisland's overshoot
    /// Shrinking with the same overshoot would dip below the menu-bar height and bounce back
    /// (measured 4.5pt on video), so closing uses the same shape of curve without overshoot.
    static let close = Animation.timingCurve(0.175, 0.885, 0.32, 1.0, duration: 0.45)
    static let radius = Animation.easeOut(duration: 0.4)
    static let pop = Animation.spring(response: 0.3, dampingFraction: 0.5)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}
