import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("PointerDriver: \(message)\n".utf8))
    exit(2)
}

func number(_ value: String) -> Double {
    guard let number = Double(value), number.isFinite else { fail("invalid number: \(value)") }
    return number
}

func attribute(_ element: AXUIElement, _ key: CFString) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, key, &value) == .success ? value : nil
}

func rectangle(_ element: AXUIElement) -> CGRect? {
    guard let position = attribute(element, kAXPositionAttribute as CFString),
          let size = attribute(element, kAXSizeAttribute as CFString),
          CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID()
    else { return nil }
    var point = CGPoint.zero
    var extent = CGSize.zero
    guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
          AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
    return CGRect(origin: point, size: extent)
}

struct Screen {
    let frame: CGRect
    let top: CGFloat
    let band: CGFloat
    var center: CGPoint { CGPoint(x: frame.midX, y: top + 10) }
    var park: CGPoint { CGPoint(x: frame.minX + 40, y: top + min(400, frame.height - 40)) }

    init() {
        guard let primary = NSScreen.screens.first else { fail("no screen available") }
        let placement = UserDefaults(suiteName: "dev.herdr.perch")?.string(forKey: "displayPlacement")
        let screen = placement == "mainDisplay" ? primary : NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? primary
        frame = screen.frame
        // NSScreen is bottom-up; CGEvent and AX positions use the primary screen's top-down space.
        top = primary.frame.maxY - screen.frame.maxY
        band = screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : 32
    }
}

func move(_ point: CGPoint) {
    guard CGPreflightPostEventAccess() else {
        fail("mouse posting is not permitted; enable Accessibility for the terminal/runner")
    }
    guard let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                              mouseCursorPosition: point, mouseButton: .left) else { fail("cannot create mouse event") }
    event.post(tap: .cghidEventTap)
}

func clickHeader(_ screen: Screen) {
    move(screen.center)
    Thread.sleep(forTimeInterval: 0.35) // Let a collapsed hover expand before clicking to pin.
    for type in [CGEventType.leftMouseDown, .leftMouseUp] {
        guard let event = CGEvent(mouseEventSource: nil, mouseType: type,
                                  mouseCursorPosition: screen.center, mouseButton: .left) else { fail("cannot create click") }
        event.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.06)
    }
    move(screen.park)
    Thread.sleep(forTimeInterval: 0.6)
}

func rows(_ pid: pid_t, _ screen: Screen) -> [CGRect] {
    guard AXIsProcessTrusted() else { fail("AX inspection is not permitted; enable Accessibility for the terminal/runner") }
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 1)
    let windows = attribute(app, kAXWindowsAttribute as CFString) as? [AXUIElement] ?? []
    var found: [CGRect] = []
    func visit(_ element: AXUIElement, depth: Int) {
        guard depth < 24 else { return }
        if attribute(element, kAXRoleAttribute as CFString) as? String == kAXButtonRole as String,
           let rect = rectangle(element), rect.width > 200, rect.height >= 16, rect.height <= 100,
           rect.minY >= screen.top + screen.band - 1,
           rect.maxY <= screen.top + min(560, screen.frame.height * 0.72) - 2 {
            found.append(rect)
        }
        for child in attribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? [] {
            visit(child, depth: depth + 1)
        }
    }
    for window in windows {
        guard let rect = rectangle(window), abs(rect.midX - screen.frame.midX) < 4,
              abs(rect.minY - screen.top) < 4 else { continue }
        visit(window, depth: 0)
    }
    return found.sorted { $0.minY < $1.minY }
}

func collapse(_ pid: pid_t, _ screen: Screen) {
    move(screen.park)
    Thread.sleep(forTimeInterval: 0.6)
    // An automatic expansion can turn pinned on the first click; two clicks cover both cases.
    for _ in 0..<2 {
        if rows(pid, screen).isEmpty { break }
        clickHeader(screen)
    }
    move(screen.park)
    guard rows(pid, screen).isEmpty else { fail("notch did not collapse") }
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { fail("expected pid, park, collapse, expand, check, path, move, point, glide, click, wiggle, post, or still") }
switch command {
case "pid":
    guard args.count == 2 else { fail("pid <app executable>") }
    let expected = URL(fileURLWithPath: args[1]).resolvingSymlinksInPath()
    let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == "dev.herdr.perch" }
    guard apps.count <= 1, apps.allSatisfy({ $0.executableURL?.resolvingSymlinksInPath() == expected }) else {
        fail("another Perch instance is running; close it before profiling this bundle")
    }
    if let app = apps.first { print(app.processIdentifier) }
case "park":
    move(Screen().park)
case "collapse", "expand", "check", "path":
    guard args.count >= 2, let pid = pid_t(args[1]) else { fail("\(command) <pid> [mode]") }
    let screen = Screen()
    switch command {
    case "collapse": collapse(pid, screen)
    case "expand":
        collapse(pid, screen)
        clickHeader(screen)
        guard rows(pid, screen).count >= 2 else { fail("need at least two visible agent rows in the expanded notch") }
    case "check":
        guard args.count == 3 else { fail("check <pid> collapsed|expanded") }
        let visible = rows(pid, screen)
        guard args[2] == "collapsed" ? visible.isEmpty : visible.count >= 2 else { fail("unexpected surface during profiling") }
    default:
        guard args.count == 3 else { fail("path <pid> outside|row|cross") }
        let start: CGPoint
        let end: CGPoint
        if args[2] == "outside" {
            start = CGPoint(x: screen.frame.midX - 80, y: screen.top + screen.band + 100)
            end = CGPoint(x: screen.frame.midX + 80, y: screen.top + screen.band + 140)
        } else {
            let visible = rows(pid, screen)
            guard visible.count >= 2 else { fail("cannot locate two visible rows") }
            let first = visible[0]
            if args[2] == "row" {
                start = CGPoint(x: first.midX - min(80, first.width / 4), y: first.midY)
                end = CGPoint(x: first.midX + min(80, first.width / 4), y: first.midY)
            } else if args[2] == "cross" {
                start = CGPoint(x: first.midX, y: first.midY)
                end = CGPoint(x: first.midX, y: visible[min(3, visible.count - 1)].midY)
            } else { fail("unknown path") }
        }
        print("\(start.x) \(start.y) \(end.x) \(end.y)")
    }
case "move":
    guard args.count == 3 else { fail("move <x> <y>") }
    move(CGPoint(x: number(args[1]), y: number(args[2])))
case "point":
    // Prints a target in global top-down coordinates: notch center, or a visible row's center (scripts/demo.py).
    let screen = Screen()
    if args.count == 2, args[1] == "center" {
        print("\(screen.center.x) \(screen.center.y)")
    } else if args.count == 4, args[1] == "row", let pid = pid_t(args[2]), let index = Int(args[3]) {
        let visible = rows(pid, screen)
        guard visible.indices.contains(index) else { fail("row \(index) not visible (\(visible.count) rows)") }
        print("\(visible[index].midX) \(visible[index].midY)")
    } else { fail("point center | point row <pid> <index>") }
case "glide":
    // Eased pointer move from the current position, for screen recordings.
    guard args.count == 4 else { fail("glide <x> <y> <seconds>") }
    let start = CGEvent(source: nil)?.location ?? .zero
    let end = CGPoint(x: number(args[1]), y: number(args[2]))
    let duration = number(args[3])
    guard duration > 0 else { fail("duration must be positive") }
    let started = ProcessInfo.processInfo.systemUptime
    while true {
        let t = min(1, (ProcessInfo.processInfo.systemUptime - started) / duration)
        let eased = t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
        move(CGPoint(x: start.x + (end.x - start.x) * eased, y: start.y + (end.y - start.y) * eased))
        if t >= 1 { break }
        Thread.sleep(forTimeInterval: 1.0 / 60)
    }
case "click":
    // Left click at the current pointer position.
    let location = CGEvent(source: nil)?.location ?? .zero
    for type in [CGEventType.leftMouseDown, .leftMouseUp] {
        guard let event = CGEvent(mouseEventSource: nil, mouseType: type,
                                  mouseCursorPosition: location, mouseButton: .left) else { fail("cannot create click") }
        event.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.06)
    }
case "wiggle":
    guard args.count == 6 else { fail("wiggle <x0> <y0> <x1> <y1> <seconds>") }
    let x0 = number(args[1]), y0 = number(args[2]), x1 = number(args[3]), y1 = number(args[4])
    let duration = number(args[5])
    guard duration > 0 else { fail("duration must be positive") }
    let started = ProcessInfo.processInfo.systemUptime
    while ProcessInfo.processInfo.systemUptime - started < duration {
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        let phase = 0.5 - 0.5 * cos(elapsed * 2 * .pi) // One round trip per second, about 60 events/s.
        move(CGPoint(x: x0 + (x1 - x0) * phase, y: y0 + (y1 - y0) * phase))
        Thread.sleep(forTimeInterval: 1.0 / 60)
    }
case "post":
    // Pointer-free surface control through the app's test hooks.
    guard args.count == 2, ["expand", "collapse"].contains(args[1]) else { fail("post expand|collapse") }
    DistributedNotificationCenter.default().postNotificationName(
        .init("dev.herdr.perch.test.\(args[1])"), object: nil, userInfo: nil, deliverImmediately: true)
    Thread.sleep(forTimeInterval: 0.6)
case "still":
    // Exit 1 if the user moves the pointer within the given seconds; only reads the position.
    guard args.count == 2 else { fail("still <seconds>") }
    let duration = number(args[1])
    func location() -> CGPoint { CGEvent(source: nil)?.location ?? .zero }
    let origin = location()
    let started = ProcessInfo.processInfo.systemUptime
    while ProcessInfo.processInfo.systemUptime - started < duration {
        if hypot(location().x - origin.x, location().y - origin.y) > 0.5 { exit(1) }
        Thread.sleep(forTimeInterval: 0.05)
    }
default: fail("unknown command: \(command)")
}
