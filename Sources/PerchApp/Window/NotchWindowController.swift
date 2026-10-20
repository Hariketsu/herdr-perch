// Derived from NotchAgent Sources/NotchApp/NotchWindowController.swift
// https://github.com/ykushch/notchagent — Copyright Yuri Kushch — Apache-2.0
// Pointer handling follows open-vibe-island Sources/OpenIslandApp/OverlayPanelController.swift
// https://github.com/Octane0411/open-vibe-island — GPL-3.0
// Modified by Herdr Perch.
import AppKit
import Observation
import SwiftUI

/// The panel keeps one fixed canvas frame; every visual transition happens in
/// SwiftUI. Resizing the window mid-spring desynchronises AppKit and SwiftUI
/// (open-vibe-island's finding), so the frame changes only with the screen.
///
/// Mouse events pass through everywhere except the visible shape: collapsed,
/// the panel ignores the mouse entirely and pointer events come from NSEvent
/// monitors plus geometry; expanded, it accepts events only while the pointer
/// is inside the shape.
@MainActor
final class NotchWindowController {
    private let model: NotchModel
    private let panel: NotchPanel
    private var tracker = PointerTracker()
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []

    init(model: NotchModel) {
        self.model = model
        panel = NotchPanel(contentRect: .zero)
        let host = FirstMouseHostingView(rootView: NotchRootView(model: model))
        host.sizingOptions = []
        panel.contentView = host
        panel.ignoresMouseEvents = true
    }

    func show() {
        refreshGeometry()
        observeModel()
        observeEnvironment()
        apply()
    }

    func tearDown() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        panel.orderOut(nil)
    }

    // MARK: Observation

    private func observeModel() {
        withObservationTracking {
            _ = model.surface
            _ = model.shapeSize
            _ = model.preferences.displayPlacement
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.apply()
                self?.observeModel()
            }
        }
    }

    private func observeEnvironment() {
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.apply() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.model.systemReduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            }
        })

        // Mouse monitors need no Accessibility permission. Global sees events
        // bound for other apps (the panel usually ignores the mouse); local sees ours.
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        let onMove: @MainActor () -> Void = { [weak self] in self?.pointerMoved() }
        let onClick: @MainActor () -> Void = { [weak self] in self?.pointerClicked() }
        add(NSEvent.addGlobalMonitorForEvents(matching: moves) { _ in MainActor.assumeIsolated(onMove) })
        add(NSEvent.addLocalMonitorForEvents(matching: moves) { event in
            MainActor.assumeIsolated(onMove)
            return event
        })
        add(NSEvent.addGlobalMonitorForEvents(matching: clicks) { _ in MainActor.assumeIsolated(onClick) })
        add(NSEvent.addLocalMonitorForEvents(matching: clicks) { event in
            MainActor.assumeIsolated(onClick)
            return event
        })
    }

    private func add(_ monitor: Any?) {
        if let monitor { monitors.append(monitor) }
    }

    // MARK: Pointer

    /// Visible shape in screen coordinates.
    private var shapeRegion: CGRect { model.geometry.panelFrame(size: model.shapeSize) }

    private func pointerMoved() {
        guard model.surface != .hidden else { return }
        if let event = tracker.update(location: NSEvent.mouseLocation, region: shapeRegion) {
            model.send(event)
        }
        // Assign only on change: this runs for every mouse move.
        let ignores = !(model.isExpanded && tracker.isInside)
        if panel.ignoresMouseEvents != ignores { panel.ignoresMouseEvents = ignores }
    }

    private func pointerClicked() {
        guard model.surface != .hidden else { return }
        let location = NSEvent.mouseLocation
        if model.isExpanded {
            // Clicks inside reach SwiftUI directly; only outside clicks matter here.
            if PointerTracker.click(at: location, region: shapeRegion, expanded: true) == .clickedOutside {
                model.send(.clickedOutside)
            }
        } else {
            // Collapsed, only the camera housing opens the notch, so clicking a
            // menu-bar icon under an ear does not also expand Perch.
            let housing = model.geometry.panelFrame(
                size: CGSize(width: model.geometry.centerWidth, height: model.geometry.bandHeight))
            if PointerTracker.click(at: location, region: housing, expanded: false) == .clicked {
                model.send(.clicked)
            }
        }
    }

    // MARK: Frame

    private func refreshGeometry() {
        let geometry = NotchGeometry(metrics: NotchScreenMetrics(screen: screen))
        if geometry != model.geometry { model.geometry = geometry }
    }

    private var screen: NSScreen {
        let primary = NSScreen.screens.first ?? NSScreen.main!
        switch model.preferences.displayPlacement {
        case .builtInNotch: return NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? primary
        case .mainDisplay: return primary
        }
    }

    private func apply() {
        refreshGeometry()
        guard model.surface != .hidden else {
            panel.orderOut(nil)
            return
        }
        let canvas = model.geometry.canvasFrame
        if !NSEqualRects(panel.frame, canvas) { panel.setFrame(canvas, display: true) }
        panel.orderFrontRegardless()
        pointerMoved()  // the region may have changed under a still pointer
    }
}
