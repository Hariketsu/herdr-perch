import AppKit
import Observation
import PerchCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: PerchStore!
    private var model: NotchModel!
    private var window: NotchWindowController!
    private var menuBar: MenuBarController!
    private var settings: SettingsWindowController!
    private var termSource: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/herdr")
        let preferences = Preferences.load(from: .standard)
        store = PerchStore(root: root)
        model = NotchModel(
            store: store, preferences: preferences,
            geometry: NotchGeometry(metrics: NotchScreenMetrics(screen: NSScreen.screens.first ?? NSScreen.main!)))
        window = NotchWindowController(model: model)
        settings = SettingsWindowController(model: model)
        menuBar = MenuBarController(store: store, onToggle: { [weak self] visible in
            visible ? self?.window.show() : self?.window.tearDown()
        }, onSettings: { [weak self] in self?.settings.show() })

        observeRows()
        store.start()
        window.show()
        handleTerminationSignal()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
    }

    private func observeRows() {
        withObservationTracking {
            _ = store.rows
            _ = store.sessions
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.model.rowsDidChange()
                self?.observeRows()
            }
        }
    }

    /// SIGTERM → normal termination with exit status 0 (smoke test, `launchctl`).
    private func handleTerminationSignal() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        termSource = source
    }
}
