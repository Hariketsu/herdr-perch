import AppKit
import SwiftUI

/// Runs a looping animation on a Core Animation layer around SwiftUI content.
/// The render server drives it, so the app does no per-frame work — a SwiftUI
/// `phaseAnimator` doing the same cost ~4.7% CPU (2026-10-20 smoke test).
enum LoopKind: Equatable {
    case throb(period: Double)   // opacity 1 ↔ 0.35
    case hop                     // 2pt up and back
}

struct LayerLoop<Content: View>: NSViewRepresentable {
    var kind: LoopKind?
    @ViewBuilder var content: Content

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        let host = NSHostingView(rootView: content)
        host.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.topAnchor.constraint(equalTo: container.topAnchor),
            host.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        (container.subviews.first as? NSHostingView<Content>)?.rootView = content
        guard let layer = container.layer else { return }
        let key = "perch.loop"
        if context.coordinator.kind == kind, layer.animation(forKey: key) != nil || kind == nil { return }
        context.coordinator.kind = kind
        layer.removeAnimation(forKey: key)
        guard let kind else { return }
        let animation: CABasicAnimation
        switch kind {
        case let .throb(period):
            animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = 1.0
            animation.toValue = 0.35
            animation.duration = period / 2
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        case .hop:
            animation = CABasicAnimation(keyPath: "transform.translation.y")
            animation.fromValue = 0
            animation.toValue = 2   // AppKit layers are not flipped: positive y is up
            animation.duration = 0.35
            animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.175, 0.885, 0.32, 1.1)
        }
        animation.autoreverses = true
        animation.repeatCount = .infinity
        layer.add(animation, forKey: key)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var kind: LoopKind?
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        (nsView.subviews.first as? NSHostingView<Content>)?.fittingSize
    }
}
