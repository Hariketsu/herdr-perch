// Derived from NotchAgent Sources/NotchApp/NotchWindowController.swift
// https://github.com/ykushch/notchagent — Copyright Yuri Kushch — Apache-2.0
// Modified by Herdr Perch.
import AppKit
import Observation
import SwiftUI

/// Keeps the panel frame equal to the notch shape's bounds so the menu bar
/// around it stays clickable. Growing resizes the frame before the shape
/// animates; shrinking resizes after (NotchAgent's ordering).
@MainActor
final class NotchWindowController {
    private let model: NotchModel
    private let panel: NotchPanel
    private var mouseMonitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var revision = 0
    private var shrinkTask: Task<Void, Never>?

    init(model: NotchModel) {
        self.model = model
        panel = NotchPanel(contentRect: .zero)
        let host = FirstMouseHostingView(rootView: NotchRootView(model: model))
        host.sizingOptions = []
        panel.contentView = host
    }

    func show() {
        refreshGeometry()
        observeModel()
        observeEnvironment()
        apply()
    }

    func tearDown() {
        mouseMonitors.forEach(NSEvent.removeMonitor)
        observers.forEach(NotificationCenter.default.removeObserver)
        panel.orderOut(nil)
    }

    private func observeModel() {
        withObservationTracking {
            _ = model.shapeSize
            _ = model.surface
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
            MainActor.assumeIsolated {
                self?.refreshGeometry()
                self?.apply()
            }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.model.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            }
        })
        // Outside clicks collapse; monitoring mouse-down needs no Accessibility permission.
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        let check: @MainActor () -> Void = { [weak self] in
            guard let self, self.model.isExpanded, !self.panel.frame.contains(NSEvent.mouseLocation) else { return }
            self.model.send(.clickedOutside)
        }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { _ in
            Task { @MainActor in check() }
        }) { mouseMonitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { event in
            Task { @MainActor in check() }
            return event
        }) { mouseMonitors.append(monitor) }
    }

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
        revision &+= 1
        let current = revision
        let target = frame(for: model.shapeSize)
        shrinkTask?.cancel()
        if !panel.isVisible || model.reduceMotion {
            panel.setFrame(target, display: true)
        } else {
            // Cover both old and new shape while the spring runs, then settle on the target.
            panel.setFrame(panel.frame.union(target), display: true)
            shrinkTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(550))
                guard let self, !Task.isCancelled, self.revision == current else { return }
                self.panel.setFrame(target, display: true)
            }
        }
        panel.orderFrontRegardless()
    }

    /// Shape plus shoulders plus room for the shadow, which would otherwise be clipped
    /// to a hard edge. Kept small when collapsed so the menu bar beside the ears stays clickable.
    private func frame(for shape: CGSize) -> CGRect {
        let margin = NotchRootView.shadowMargin(expanded: model.isExpanded)
        let size = CGSize(width: shape.width + 2 * (NotchRootView.shoulder + margin), height: shape.height + margin)
        return model.geometry.panelFrame(size: size)
    }
}
