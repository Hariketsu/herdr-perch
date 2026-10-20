// Derived from NotchAgent Sources/NotchApp/NotchPanel.swift
// https://github.com/ykushch/notchagent — Copyright Yuri Kushch — Apache-2.0
// Modified by Herdr Perch.
import AppKit
import SwiftUI

/// Borderless, non-activating panel above the menu bar on every Space.
/// v1 has no text input, so it never becomes key.
final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Clicks must land even though the panel is never key.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
