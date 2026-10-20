import Foundation
import PerchCore

// Debug/test CLI over PerchCore. Output format: architecture.md §4.7.

func usage() -> Never {
    FileHandle.standardError.write(Data("usage: perchctl dump|watch [--root <dir>] | jump <session> <pane> [--root <dir>]\n".utf8))
    exit(64)
}

var arguments = Array(CommandLine.arguments.dropFirst())
var root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/herdr")
if let index = arguments.firstIndex(of: "--root") {
    guard index + 1 < arguments.count else { usage() }
    root = URL(fileURLWithPath: arguments[index + 1])
    arguments.removeSubrange(index...index + 1)
}

/// Every reachable session, read once.
func readSessions(root: URL) async -> [SessionState] {
    var states: [SessionState] = []
    for endpoint in SessionScanner(root: root).scan() {
        let client = HerdrClient(socketPath: endpoint.socketPath)
        do {
            _ = try await client.ping()
            states.append(SessionState(endpoint: endpoint, snapshot: try await client.snapshot(), health: .live))
        } catch let HerdrError.unsupportedProtocol(version) {
            states.append(SessionState(endpoint: endpoint, health: .updateRequired(protocolVersion: version)))
        } catch {
            continue
        }
    }
    return states
}

func emit(_ data: Data) {
    FileHandle.standardOutput.write(data)
}

switch arguments.first {
case "dump":
    let sessions = await readSessions(root: root)
    var clock = StatusClock()
    emit(StateTrace.line(rows: RowBuilder.rows(sessions, clock: &clock, now: Date()), sessions: sessions))

case "watch":
    let store = PerchStore(root: root, tracePath: "/dev/stdout")
    store.start()
    signal(SIGTERM) { _ in exit(0) }
    while true { try await Task.sleep(for: .seconds(3600)) }

case "jump":
    guard arguments.count == 3 else { usage() }
    let sessions = await readSessions(root: root).filter { $0.endpoint.name == arguments[1] }
    var clock = StatusClock()
    let row = RowBuilder.rows(sessions, clock: &clock, now: Date()).first { $0.id.paneID == arguments[2] }
    let outcome: JumpOutcome
    if let row, let session = sessions.first {
        outcome = await Jumper().jump(row, client: HerdrClient(socketPath: session.endpoint.socketPath))
    } else {
        outcome = .failed("No agent \(arguments[2]) in session \(arguments[1])")
    }
    let (name, message): (String, String?) = switch outcome {
    case .focused: ("focused", nil)
    case .needsAttach: ("needsAttach", nil)
    case let .failed(message): ("failed", message)
    }
    var object: [String: Any] = ["outcome": name]
    object["message"] = message ?? NSNull()
    emit(try JSONSerialization.data(withJSONObject: object) + Data("\n".utf8))
    exit(outcome == .focused ? 0 : 1)

default:
    usage()
}
