import AppKit
import PerchCore
import ServiceManagement
import SwiftUI

/// Settings laid out like Vibe Island's: a sidebar of coloured icons, and a
/// Display page with a live notch preview and selectable style cards.
struct SettingsView: View {
    @Bindable var model: NotchModel
    @State private var page: Page = .display

    enum Page: String, CaseIterable, Identifiable {
        case general = "General", display = "Display", about = "About"
        var id: Self { self }
        var icon: String {
            switch self {
            case .general: "gearshape.fill"
            case .display: "textformat.size"
            case .about: "info"
            }
        }
        var tint: Color {
            switch self {
            case .general: .gray
            case .display: .indigo
            case .about: .blue
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Page.allCases, selection: $page) { page in
                Label {
                    Text(page.rawValue)
                } icon: {
                    Image(systemName: page.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(page.tint.gradient, in: RoundedRectangle(cornerRadius: 6))
                }
                .tag(page)
            }
            .navigationSplitViewColumnWidth(190)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Label(page.rawValue, systemImage: page.icon).font(.title2.bold()).labelStyle(.titleOnly)
                    switch page {
                    case .general: GeneralPage(model: model)
                    case .display: DisplayPage(model: model)
                    case .about: AboutPage()
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 720, height: 560)
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

private struct Section<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            VStack(alignment: .leading, spacing: 12) { content }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

private struct GeneralPage: View {
    @Bindable var model: NotchModel

    var body: some View {
        Section(title: "Behavior") {
            Toggle("Expand when an agent is blocked", isOn: savedBinding(model, \.autoExpandOnBlocked))
            Divider()
            Toggle("Launch at login", isOn: Binding(
                get: { model.preferences.launchAtLogin },
                set: { enabled in
                    LoginItem.set(enabled)
                    model.preferences.launchAtLogin = LoginItem.isEnabled
                    model.preferences.save(to: .standard)
                }))
        }
    }
}

private struct DisplayPage: View {
    @Bindable var model: NotchModel

    var body: some View {
        Section(title: "Notch") {
            NotchPreview(model: model)
            HStack(spacing: 10) {
                StyleCard(style: .birdCount, title: "Clean", detail: "More space for menu bar", model: model)
                StyleCard(style: .dots, title: "Dots", detail: "One dot per agent", model: model)
                StyleCard(style: .counts, title: "Counts", detail: "Agents per state", model: model)
            }
            Divider()
            Picker("Display", selection: savedBinding(model, \.displayPlacement)) {
                Text("Built-in Notch Display").tag(DisplayPlacement.builtInNotch)
                Text("Main Display").tag(DisplayPlacement.mainDisplay)
            }
        }
        Section(title: "Panel") {
            Picker("Rows", selection: savedBinding(model, \.listStyle)) {
                Text("Grouped").tag(ListStyle.grouped)
                Text("Detailed").tag(ListStyle.heroAndRows)
                Text("Compact").tag(ListStyle.rowsOnly)
            }
            Divider()
            Toggle("Clean agent titles (strip “π >” prompts and icons)", isOn: savedBinding(model, \.cleanTitles))
            Divider()
            Toggle("Follow system “Reduce motion”", isOn: savedBinding(model, \.followReduceMotion))
        }
    }
}

/// The collapsed notch as it looks right now, over a wallpaper-like gradient.
private struct NotchPreview: View {
    @Bindable var model: NotchModel

    var body: some View {
        let geometry = model.geometry
        let size = geometry.collapsedSize(wingWidth: model.wingWidth)
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(hex: 0x2563EB), Color(hex: 0x7C3AED), Color(hex: 0xF97316)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            NotchShape(bottomRadius: 10).fill(.black).frame(width: size.width, height: size.height)
            CollapsedBand(summary: model.summary, style: model.preferences.compactStyle, completion: nil,
                          centerWidth: geometry.centerWidth, wingWidth: model.wingWidth,
                          height: geometry.bandHeight)
                .frame(width: size.width)
        }
        .frame(height: 110)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .environment(\.colorScheme, .dark)
        .animation(.smooth(duration: 0.3), value: model.preferences.compactStyle)
    }
}

private struct StyleCard: View {
    var style: CompactStyle
    var title: String
    var detail: String
    @Bindable var model: NotchModel

    var body: some View {
        let selected = model.preferences.compactStyle == style
        Button {
            savedBinding(model, \.compactStyle).wrappedValue = style
        } label: {
            VStack(spacing: 6) {
                miniature
                    .frame(width: 112, height: 18)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(.background.tertiary, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(selected ? Color.accentColor : .secondary.opacity(0.25), lineWidth: selected ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var miniature: some View {
        HStack(spacing: 3) {
            Circle().fill(Palette.finished).frame(width: 5, height: 5)
            Spacer()
            switch style {
            case .birdCount: Text("2").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
            case .dots:
                Circle().fill(Palette.work).frame(width: 4, height: 4)
                Circle().fill(Palette.idle).frame(width: 4, height: 4)
            case .counts:
                Circle().fill(Palette.work).frame(width: 4, height: 4)
                Text("1").font(.system(size: 7, weight: .bold)).foregroundStyle(.secondary)
                Circle().fill(Palette.idle).frame(width: 4, height: 4)
                Text("1").font(.system(size: 7, weight: .bold)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6)
    }
}

private struct AboutPage: View {
    var body: some View {
        Section(title: "Herdr Perch") {
            Text("A quiet companion for Herdr.")
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                .foregroundStyle(.secondary)
            Divider()
            Text("Licensed under the GNU GPL v3.").foregroundStyle(.secondary)
            Text("Portions derived from NotchAgent (github.com/ykushch/notchagent) by Yuri Kushch, Apache License 2.0, and open-vibe-island (github.com/Octane0411/open-vibe-island), GPL-3.0.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
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
            window.title = "Herdr Perch"
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
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
