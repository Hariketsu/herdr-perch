// Derived from NotchAgent Sources/HerdrClient/TerminalActivator.swift
// https://github.com/ykushch/notchagent — Copyright Yuri Kushch — Apache-2.0
// Modified by Herdr Perch.
import AppKit

/// Brings the terminal hosting Herdr to the front after a jump.
/// Never shells out (`open -b` used to block the main thread in NotchAgent).
@MainActor
final class TerminalActivator {
    static let bundleIDs: Set<String> = [
        "com.mitchellh.ghostty", "com.apple.Terminal", "com.googlecode.iterm2",
        "net.kovidgoyal.kitty", "com.github.wez.wezterm", "org.alacritty", "dev.warp.Warp-Stable",
    ]

    private var lastUsed: String?

    func activate() {
        guard let app = choose() else { return }
        lastUsed = app.bundleIdentifier
        app.activate()
    }

    /// Frontmost terminal, else the only running one, else the last one used.
    private func choose() -> NSRunningApplication? {
        if let front = NSWorkspace.shared.frontmostApplication, Self.isTerminal(front) { return front }
        let running = NSWorkspace.shared.runningApplications.filter(Self.isTerminal)
        if running.count == 1 { return running[0] }
        return running.first { $0.bundleIdentifier == lastUsed }
    }

    private static func isTerminal(_ app: NSRunningApplication) -> Bool {
        bundleIDs.contains(app.bundleIdentifier ?? "")
    }
}
