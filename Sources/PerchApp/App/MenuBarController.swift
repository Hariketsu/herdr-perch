import AppKit
import PerchCore

/// Bird template icon with Show/Hide, Settings…, About, Quit.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let store: PerchStore
    private let onToggle: (Bool) -> Void
    private let onSettings: () -> Void
    private var visible = true
    private let toggleItem = NSMenuItem(title: "Hide Perch", action: #selector(toggle), keyEquivalent: "")
    private let statusItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    init(store: PerchStore, onToggle: @escaping (Bool) -> Void, onSettings: @escaping () -> Void) {
        self.store = store
        self.onToggle = onToggle
        self.onSettings = onSettings
        super.init()
        item.button?.image = Self.ramImage()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.isEnabled = false
        menu.addItem(statusItem)
        menu.addItem(.separator())
        toggleItem.target = self
        menu.addItem(toggleItem)
        menu.addItem(withTitle: "Settings…", action: #selector(settings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "About Herdr Perch", action: #selector(about), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Herdr Perch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        let count = store.rows.count
        statusItem.title = store.sessions.isEmpty ? "Herdr isn’t running"
            : count == 1 ? "1 agent" : "\(count) agents"
    }

    @objc private func toggle() {
        visible.toggle()
        toggleItem.title = visible ? "Hide Perch" : "Show Perch"
        onToggle(visible)
    }

    @objc private func settings() { onSettings() }

    @objc private func about() {
        let credits = NSAttributedString(
            string: """
            A quiet companion for Herdr.

            Acknowledgements: portions derived from NotchAgent \
            (github.com/ykushch/notchagent) by Yuri Kushch, Apache License 2.0.
            Herdr Perch is licensed under the GNU GPL v3.
            """,
            attributes: [.font: NSFont.systemFont(ofSize: 11)])
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    /// The same pixel ram as the notch (prompt face), as a 20×19pt template image.
    private static func ramImage() -> NSImage {
        let face = Set(RamSprite.face(.working, stale: false).map { $0.row * 100 + $0.col })
        let image = NSImage(size: NSSize(width: 20, height: 19), flipped: true) { _ in
            NSColor.black.setFill()
            for (y, row) in RamSprite.grid.enumerated() {
                for (x, c) in row.enumerated() where c != "." && !face.contains(y * 100 + x) {
                    NSRect(x: x, y: y, width: 1, height: 1).fill()
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
