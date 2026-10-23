import AppKit
import PerchCore

/// Bird template icon with Show/Hide, Settings…, About, Quit.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let store: PerchStore
    private let onToggle: (Bool) -> Void
    private let onSettings: () -> Void
    private let onAbout: () -> Void
    private var visible = true
    private let toggleItem = NSMenuItem(title: "Hide Perch", action: #selector(toggle), keyEquivalent: "")
    private let statusItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    init(store: PerchStore, onToggle: @escaping (Bool) -> Void, onSettings: @escaping () -> Void,
         onAbout: @escaping () -> Void) {
        self.store = store
        self.onToggle = onToggle
        self.onSettings = onSettings
        self.onAbout = onAbout
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

    @objc private func about() { onAbout() }

    /// The same pixel ram as the notch (prompt face) at 0.8 scale, as a 16pt template image.
    private static func ramImage() -> NSImage {
        let cell: CGFloat = 0.8
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.translateBy(x: 0, y: 0.4)  // centre the 15.2pt-tall ram
            for path in RamSprite.paths(status: .working, stale: false, cell: cell).values {
                context.addPath(path.cgPath)
            }
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath()
            return true
        }
        image.isTemplate = true
        return image
    }
}
