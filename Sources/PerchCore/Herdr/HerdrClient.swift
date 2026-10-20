// Derived from NotchAgent Sources/HerdrClient/HerdrClient.swift
// https://github.com/ykushch/notchagent — Copyright Yuri Kushch — Apache-2.0
// Modified by Herdr Perch.
import Foundation

public enum HerdrError: Error, Equatable, Sendable {
    case connectFailed(Int32)
    case timeout
    case closedByPeer
    case malformedResponse
    case server(code: String, message: String)
    case eventsLost
    case unsupportedProtocol(Int)
}

/// Client for Herdr's newline-delimited JSON socket API.
///
/// Every request uses a fresh connection (Herdr serves one request per
/// connection). `subscribe` holds the only long-lived connection.
public struct HerdrClient: Sendable {
    public static let minimumProtocol = 22

    public let socketPath: String
    public let timeout: Duration

    public init(socketPath: String, timeout: Duration = .seconds(2)) {
        self.socketPath = socketPath
        self.timeout = timeout
    }

    public func ping() async throws -> PingInfo {
        let result = try Self.result(of: await request("ping"))
        guard let version = result["version"] as? String,
              let protocolVersion = (result["protocol"] as? NSNumber)?.intValue
        else { throw HerdrError.malformedResponse }
        guard protocolVersion >= Self.minimumProtocol else {
            throw HerdrError.unsupportedProtocol(protocolVersion)
        }
        return PingInfo(version: version, protocolVersion: protocolVersion)
    }

    public func snapshot() async throws -> Snapshot {
        try Snapshot.decode(response: await request("session.snapshot"))
    }

    public func focusWorkspace(_ id: String) async throws {
        _ = try Self.result(of: await request("workspace.focus", ["workspace_id": id]))
    }

    public func focusTab(_ id: String) async throws {
        _ = try Self.result(of: await request("tab.focus", ["tab_id": id]))
    }

    public func focusPane(_ id: String) async throws {
        _ = try Self.result(of: await request("pane.focus", ["pane_id": id]))
    }

    /// Long-lived stream: `.started` once, then `.event` per pushed line.
    /// The timeout applies only until `subscription_started` arrives.
    public func subscribe(_ subscriptions: [Subscription]) -> AsyncThrowingStream<EventSignal, any Error> {
        let entries: [[String: String]] = subscriptions.map { subscription in
            var entry = ["type": subscription.type]
            if let paneID = subscription.paneID { entry["pane_id"] = paneID }
            return entry
        }
        let payload = Self.encode("events.subscribe", ["subscriptions": entries])
        let path = socketPath
        let timeout = timeout

        return AsyncThrowingStream { continuation in
            let holder = ConnectionHolder()
            continuation.onTermination = { _ in holder.interrupt() }
            Thread.detachNewThread {
                do {
                    let deadline = ContinuousClock.now + timeout
                    let connection = try SocketConnection.connect(path: path, deadline: deadline)
                    guard holder.set(connection) else { return continuation.finish() }
                    try connection.writeLine(payload, deadline: deadline)
                    let first = try Self.result(of: connection.readLine(deadline: deadline))
                    guard first["type"] as? String == "subscription_started" else {
                        throw HerdrError.malformedResponse
                    }
                    continuation.yield(.started)
                    while true {
                        let line = try connection.readLine(deadline: nil)
                        guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                            throw HerdrError.malformedResponse
                        }
                        if let error = message["error"] as? [String: Any] { throw Self.map(error) }
                        continuation.yield(.event)
                    }
                } catch {
                    continuation.finish(throwing: holder.isInterrupted ? nil : error)
                }
            }
        }
    }

    // MARK: Request plumbing

    private func request(_ method: String, _ params: [String: Any] = [:]) async throws -> Data {
        let payload = Self.encode(method, params)
        let path = socketPath
        let deadline = ContinuousClock.now + timeout
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result {
                    let connection = try SocketConnection.connect(path: path, deadline: deadline)
                    try connection.writeLine(payload, deadline: deadline)
                    return try connection.readLine(deadline: deadline)
                })
            }
        }
    }

    private static func encode(_ method: String, _ params: [String: Any]) -> Data {
        // Inputs are string-keyed literals built above; serialization cannot fail.
        try! JSONSerialization.data(withJSONObject: ["id": "perch", "method": method, "params": params])
    }

    /// The `result` object of a response line, or the mapped server error.
    static func result(of line: Data) throws -> [String: Any] {
        guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            throw HerdrError.malformedResponse
        }
        if let error = message["error"] as? [String: Any] { throw map(error) }
        guard let result = message["result"] as? [String: Any] else { throw HerdrError.malformedResponse }
        return result
    }

    private static func map(_ error: [String: Any]) -> HerdrError {
        let code = error["code"] as? String ?? "unknown"
        if code == "events_lost" { return .eventsLost }
        return .server(code: code, message: error["message"] as? String ?? "")
    }
}

/// Lets stream termination interrupt the reader thread's blocking read.
private final class ConnectionHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var connection: SocketConnection?
    private var interrupted = false

    var isInterrupted: Bool { lock.withLock { interrupted } }

    /// False if the stream was already terminated.
    func set(_ connection: SocketConnection) -> Bool {
        lock.withLock {
            self.connection = connection
            return !interrupted
        }
    }

    func interrupt() {
        lock.withLock {
            interrupted = true
            connection?.interrupt()
        }
    }
}
