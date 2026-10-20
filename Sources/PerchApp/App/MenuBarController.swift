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
        item.button?.image = Self.birdImage()
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

    /// The same pixel bird as the notch, as a template image.
    private static func birdImage() -> NSImage {
        let rows = ["..........", ".....##...", "....#.##bb", "....####..", "..######..", "########..", "...#####..", "....b..b.."]
        let image = NSImage(size: NSSize(width: 18, height: 14), flipped: true) { _ in
            let cell: CGFloat = 1.6
            NSColor.black.setFill()
            for (y, row) in rows.enumerated() {
                for (x, c) in row.enumerated() where c != "." {
                    NSRect(x: 1 + CGFloat(x) * cell, y: 0.6 + CGFloat(y) * cell, width: cell, height: cell).fill()
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
