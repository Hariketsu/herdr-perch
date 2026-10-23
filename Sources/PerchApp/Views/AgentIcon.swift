import AppKit
import SwiftUI

/// Monochrome agent marks. The SVGs are embedded as strings:
/// the hand-assembled .app has no SwiftPM resource bundle for `Bundle.module` to find.
/// Sources: lobe-icons (MIT) claudecode / codex / opencode / pi; the omp.sh header π mark
/// (oh-my-pi, MIT). See NOTICE. Arc flags are written out ("0 0 1 3.046", not "013.046"):
/// CoreSVG rejects the compact form and drops the arc, which broke the Codex mark.
enum AgentIcon {
    static func name(for agentLabel: String) -> String? {
        switch agentLabel.lowercased() {
        case "claude": "claudecode"
        case "codex": "codex"
        case "omp": "omp"
        case "opencode": "opencode"
        case "pi": "pi"
        default: nil
        }
    }

    @MainActor static func image(named name: String) -> NSImage? {
        if let cached = cache[name] { return cached }
        guard let svg = svgs[name], let image = NSImage(data: Data(svg.utf8)) else { return nil }
        image.isTemplate = true
        cache[name] = image
        return image
    }

    @MainActor private static var cache: [String: NSImage] = [:]

    private static let svgs: [String: String] = [
        "claudecode": svg24("""
            <path fill-rule="evenodd" d="M20.998 10.949H24v3.102h-3v3.028h-1.487V20H18v-2.921h-1.487V20H15v-2.921H9V20H7.488v-2.921H6V20H4.487v-2.921H3V14.05H0V10.95h3V5h17.998v5.949zM6 10.949h1.488V8.102H6v2.847zm10.51 0H18V8.102h-1.49v2.847z"/>
            """),
        "codex": svg24("""
            <path fill-rule="evenodd" d="M8.086.457a6.105 6.105 0 0 1 3.046 -.415c1.333.153 2.521.72 3.564 1.7a.117 .117 0 0 0 .107 .029c1.408-.346 2.762-.224 4.061.366l.063.03.154.076c1.357.703 2.33 1.77 2.918 3.198.278.679.418 1.388.421 2.126a5.655 5.655 0 0 1 -.18 1.631 .167 .167 0 0 0 .04 .155 5.982 5.982 0 0 1 1.578 2.891c.385 1.901-.01 3.615-1.183 5.14l-.182.22a6.063 6.063 0 0 1 -2.934 1.851 .162 .162 0 0 0 -.108 .102c-.255.736-.511 1.364-.987 1.992-1.199 1.582-2.962 2.462-4.948 2.451-1.583-.008-2.986-.587-4.21-1.736a.145 .145 0 0 0 -.14 -.032c-.518.167-1.04.191-1.604.185a5.924 5.924 0 0 1 -2.595 -.622 6.058 6.058 0 0 1 -2.146 -1.781c-.203-.269-.404-.522-.551-.821a7.74 7.74 0 0 1 -.495 -1.283 6.11 6.11 0 0 1 -.017 -3.064 .166 .166 0 0 0 .008 -.074 .115 .115 0 0 0 -.037 -.064 5.958 5.958 0 0 1 -1.38 -2.202 5.196 5.196 0 0 1 -.333 -1.589 6.915 6.915 0 0 1 .188 -2.132c.45-1.484 1.309-2.648 2.577-3.493.282-.188.55-.334.802-.438.286-.12.573-.22.861-.304a.129 .129 0 0 0 .087 -.087A6.016 6.016 0 0 1 5.635 2.31C6.315 1.464 7.132.846 8.086.457zm-.804 7.85a.848 .848 0 0 0 -1.473 .842l1.694 2.965-1.688 2.848a.849 .849 0 0 0 1.46 .864l1.94-3.272a.849 .849 0 0 0 .007 -.854l-1.94-3.393zm5.446 6.24a.849 .849 0 0 0 0 1.695h4.848a.849 .849 0 0 0 0 -1.696h-4.848z"/>
            """),
        "opencode": svg24("""
            <path fill-rule="evenodd" d="M16 6H8v12h8V6zm4 16H4V2h16v20z"/>
            """),
        "pi": svg24("""
            <path fill-rule="evenodd" d="M1 1h16.5v11H12v5.5H6.5V23H1V1zm5.5 5.5V12H12V6.5H6.5z"/><path d="M17.5 12H23v11h-5.5V12z"/>
            """),
        "omp": """
            <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 64 64"><path d="M10 14h44v9H43v33h-9V23h-9v22h-9V23H10z"/></svg>
            """,
    ]

    private static func svg24(_ paths: String) -> String {
        #"<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">"# + paths + "</svg>"
    }
}

/// 13pt agent mark tinted like secondary text; unknown agents fall back to a grey label.
struct AgentMark: View {
    var label: String
    var highlighted = false

    var body: some View {
        if let name = AgentIcon.name(for: label), let image = AgentIcon.image(named: name) {
            Image(nsImage: image).resizable().interpolation(.high)
                .frame(width: 13, height: 13)
                .foregroundStyle(.white.opacity(highlighted ? 0.75 : 0.5))
                .help(label)
        } else {
            Text(label).font(.system(size: 9.5, weight: .medium)).foregroundStyle(.white.opacity(0.45))
                .lineLimit(1).fixedSize()
        }
    }
}
