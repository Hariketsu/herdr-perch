import AppKit
import PerchCore
import ServiceManagement
import SwiftUI

/// One grouped page sized to its content, as HIG asks of a settings window with few options:
/// standard label–control rows, segmented choices instead of pop-up menus, and a single live
/// preview where the choice is purely visual (the collapsed notch).
struct SettingsView: View {
    @Bindable var model: NotchModel
    var showAbout: () -> Void

    var body: some View {
        Form {
            Section {
                IdentityHeader(status: HerdrStatus.make(model.store.sessions), showAbout: showAbout)
            }
            Section("Notch") {
                NotchPreview(model: model)
                Picker("Style", selection: savedBinding(model, \.compactStyle)) {
                    Text("Clean").tag(CompactStyle.birdCount)
                    Text("Dots").tag(CompactStyle.dots)
                    Text("Counts").tag(CompactStyle.counts)
                }
                .pickerStyle(.segmented)
                Picker("Display", selection: savedBinding(model, \.displayPlacement)) {
                    Text("Built-in Notch").tag(DisplayPlacement.builtInNotch)
                    Text("Main Display").tag(DisplayPlacement.mainDisplay)
                }
                .pickerStyle(.segmented)
            }
            Section("Behavior") {
                Toggle(isOn: savedBinding(model, \.peekOnFinished)) {
                    Text("Peek when an agent finishes")
                    Text("Blocked agents always peek out of the notch; this adds finished ones.")
                }
                Toggle(isOn: savedBinding(model, \.cleanTitles)) {
                    Text("Clean agent titles")
                    Text("“π > Migrate config” shows as “Migrate config”.")
                }
                Toggle(isOn: savedBinding(model, \.followReduceMotion)) {
                    Text("Reduce motion when the system asks to")
                    Text("Off: the notch keeps its full animation even with Reduce Motion on.")
                }
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
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 480)
    }
}

/// Writes every change through to UserDefaults.
@MainActor
private func savedBinding<Value>(_ model: NotchModel, _ keyPath: WritableKeyPath<Preferences, Value>) -> Binding<Value> {
    Binding(
        get: { model.preferences[keyPath: keyPath] },
        set: {
            model.preferences[keyPath: keyPath] = $0
            model.preferences.save(to: .standard)
        })
}

/// App icon, name and version with the live Herdr connection: who Perch is and whether it works.
private struct IdentityHeader: View {
    var status: HerdrStatus
    var showAbout: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text("Herdr Perch").font(.title3.weight(.semibold))
                HStack(spacing: 6) {
                    Circle().fill(color).frame(width: 7, height: 7)
                    Text(status.title)
                }
                .font(.callout)
                Text("Version \(AboutView.shortVersion) · Requires Herdr 0.9.5 or later")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("About…", action: showAbout)
        }
        .padding(.vertical, 4)
    }

    private var color: Color {
        switch status.level {
        case .connected: Palette.finished
        case .attention: Palette.notice
        case .offline: .secondary
        }
    }
}

/// The collapsed notch in the chosen style over a wallpaper-like gradient. Drawn from fictional
/// agents, one per state, so every style shows every colour (and never real titles or counts).
private struct NotchPreview: View {
    @Bindable var model: NotchModel

    private static let summary = CompactSummary.make([
        sample("blocked", .blocked), sample("finished", .finished), sample("working", .working), sample("idle", .idle),
    ])

    var body: some View {
        let style = model.preferences.compactStyle
        let geometry = model.geometry
        let wing = Self.summary.wingWidth(style)
        // Narrower than the real camera housing so the notch sits comfortably in the small preview.
        let center = min(geometry.centerWidth, 110)
        let size = CGSize(width: center + 2 * wing, height: geometry.bandHeight)
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(hex: 0x2563EB), Color(hex: 0x7C3AED), Color(hex: 0xF97316)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            NotchShape(bottomRadius: 10).fill(.black).frame(width: size.width, height: size.height)
            CollapsedBand(summary: Self.summary, style: style, centerWidth: center,
                          wingWidth: wing, height: geometry.bandHeight)
                .frame(width: size.width)
        }
        .frame(height: 110)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .environment(\.colorScheme, .dark)
        .animation(.smooth(duration: 0.3), value: style)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static func sample(_ id: String, _ status: DisplayStatus) -> AgentRow {
        AgentRow(id: AgentRef(session: "preview", paneID: id), status: status, title: id, agentLabel: "",
                 since: .now, session: "preview", workspaceID: "preview", tabID: id)
    }
}

// MARK: - About

/// Mirrors the README: what Perch is, where it lives, whom it thanks, and its license.
struct AboutView: View {
    private static let repository = URL(string: "https://github.com/Hariketsu/herdr-perch")!

    static var shortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    private static var version: String {
        let build = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String).map { " (\($0))" } ?? ""
        return "Version \(shortVersion)\(build)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            VStack(alignment: .leading, spacing: 10) {
                Text("Acknowledgments").font(.headline)
                Credit(links: [("Herdr", "https://github.com/herdrdev/herdr")],
                       detail: "The API that makes companions like Perch possible.")
                Credit(links: [("Vibe Island", "https://vibeisland.app"),
                               ("open-vibe-island", "https://github.com/Octane0411/open-vibe-island")],
                       detail: "The reference for the notch’s look and motion. The overlay window and pointer handling are derived from open-vibe-island (GPL-3.0).")
                Credit(links: [("NotchAgent", "https://github.com/ykushch/notchagent")],
                       detail: "Parts of the Herdr client and terminal activation are derived from it (Apache-2.0).")
                Credit(links: [("Lobe Icons", "https://github.com/lobehub/lobe-icons"),
                               ("oh-my-pi", "https://github.com/can1357/oh-my-pi")],
                       detail: "The agent marks (MIT).")
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("Licensed under GPL-3.0.")
                    Link("View License", destination: Self.repository.appending(path: "blob/main/LICENSE"))
                }
                Text("Herdr Perch is an independent project and is not affiliated with or endorsed by Herdr. Agent marks are trademarks of their respective owners and are used only to identify agents.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.callout).foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(width: 460)
    }

    private var header: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
            Text("Herdr Perch").font(.title.bold())
            Text("Your Herdr agents, perched in the MacBook notch.").foregroundStyle(.secondary)
            Text(Self.version).font(.callout).foregroundStyle(.tertiary)
            HStack(spacing: 8) {
                OpenButton(title: "GitHub", url: Self.repository)
                OpenButton(title: "Releases", url: Self.repository.appending(path: "releases"))
                OpenButton(title: "Report an Issue", url: Self.repository.appending(path: "issues/new"))
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
    }
}

/// "Name · Name" links over a line of detail.
private struct Credit: View {
    var links: [(name: String, url: String)]
    var detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                ForEach(links, id: \.name) { link in
                    if link.name != links.first?.name { Text("·").foregroundStyle(.secondary) }
                    Link(link.name, destination: URL(string: link.url)!).fontWeight(.medium)
                }
            }
            Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct OpenButton: View {
    var title: String
    var url: URL

    var body: some View {
        Button(title) { NSWorkspace.shared.open(url) }.buttonStyle(.bordered)
    }
}

// MARK: - Windows

/// Settings and About windows, created once and brought to the front on demand.
@MainActor
final class SettingsWindowController {
    private let model: NotchModel
    private var settings: NSWindow?
    private var about: NSWindow?

    init(model: NotchModel) {
        self.model = model
    }

    func show() {
        settings = settings ?? Self.window(title: "Herdr Perch Settings",
                                           SettingsView(model: model, showAbout: { [weak self] in self?.showAbout() }))
        Self.present(settings)
    }

    func showAbout() {
        about = about ?? Self.window(title: "About Herdr Perch", AboutView())
        Self.present(about)
    }

    private static func window(title: String, _ view: some View) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = title
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private static func present(_ window: NSWindow?) {
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
