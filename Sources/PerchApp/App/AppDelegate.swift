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
        // PERCH_HERDR_ROOT points Perch at another directory, e.g. a single demo session (scripts/demo.py).
        let root = ProcessInfo.processInfo.environment["PERCH_HERDR_ROOT"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/herdr")
        let preferences = Preferences.load(from: .standard)
        store = PerchStore(root: root)
        model = NotchModel(
            store: store, preferences: preferences,
            geometry: NotchGeometry(metrics: NotchScreenMetrics(screen: NSScreen.screens.first ?? NSScreen.main!)))
        window = NotchWindowController(model: model)
        settings = SettingsWindowController(model: model)
        model.showSettings = { [weak self] in self?.settings.show() }
        menuBar = MenuBarController(store: store, onToggle: { [weak self] visible in
            visible ? self?.window.show() : self?.window.tearDown()
        }, onSettings: { [weak self] in self?.settings.show() },
           onAbout: { [weak self] in self?.settings.showAbout() })

        observeRows()
        store.start()
        window.show()
        handleTerminationSignal()
        if ProcessInfo.processInfo.environment["PERCH_TEST_HOOKS"] == "1" { observeTestHooks() }
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

    /// Distributed notifications that pin open / collapse the notch without posting pointer events (`scripts/perf.sh --static`).
    /// Only registered with `PERCH_TEST_HOOKS=1`, so a normal launch doesn't let other processes drive the notch.
    private func observeTestHooks() {
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: .init("dev.herdr.perch.test.expand"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let model = self?.model, model.surface == .collapsed else { return }
                model.send(.clicked)
            }
        }
        center.addObserver(forName: .init("dev.herdr.perch.test.collapse"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let model = self?.model, model.isOpen else { return }
                model.send(.rowActivated)
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
