import AppKit
import ServiceManagement
import SwiftUI

/// Single-page settings (product.md §8). Every change is saved immediately.
struct SettingsView: View {
    @Bindable var model: NotchModel

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Collapsed style", selection: binding(\.compactStyle)) {
                    Text("Bird + count").tag(CompactStyle.birdCount)
                    Text("A dot per agent").tag(CompactStyle.dots)
                    Text("Count per state").tag(CompactStyle.counts)
                }
                Picker("List style", selection: binding(\.listStyle)) {
                    Text("Large first row").tag(ListStyle.heroAndRows)
                    Text("Compact rows").tag(ListStyle.rowsOnly)
                }
            }
            Section("Behavior") {
                Toggle("Expand when an agent is blocked", isOn: binding(\.autoExpandOnBlocked))
                Picker("Display", selection: binding(\.displayPlacement)) {
                    Text("Built-in notch display").tag(DisplayPlacement.builtInNotch)
                    Text("Main display").tag(DisplayPlacement.mainDisplay)
                }
            }
            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { model.preferences.launchAtLogin },
                    set: { enabled in
                        LoginItem.set(enabled)
                        model.preferences.launchAtLogin = LoginItem.isEnabled
                        model.preferences.save(to: .standard)
                    }))
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize()
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<Preferences, Value>) -> Binding<Value> {
        Binding(
            get: { model.preferences[keyPath: keyPath] },
            set: {
                model.preferences[keyPath: keyPath] = $0
                model.preferences.save(to: .standard)
            })
    }
}

@MainActor
final class SettingsWindowController {
    private let model: NotchModel
    private var window: NSWindow?

    init(model: NotchModel) {
        self.model = model
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
            window.title = "Herdr Perch Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Perch: login item change failed: \(error)")
        }
    }
}
