// Derived from NotchAgent Tests/HerdrClientTests/SocketClientTests.swift (Apache-2.0)
// https://github.com/ykushch/notchagent — Copyright Yuri Kushch
// Modified by Herdr Perch.
import Darwin
import Foundation

/// Only the test transport crosses threads; JSON objects never mutate after parsing.
struct FakeRequest: @unchecked Sendable {
    let json: [String: Any]
    var method: String? { json["method"] as? String }
    var params: [String: Any] { json["params"] as? [String: Any] ?? [:] }
    func result(_ body: [String: Any]) -> Data {
        Self.line(["id": json["id"] ?? NSNull(), "result": body])
    }
    func error(_ code: String, _ message: String) -> Data {
        Self.line(["id": json["id"] ?? NSNull(), "error": ["code": code, "message": message]])
    }
    static func line(_ json: [String: Any]) -> Data {
        // All callers provide JSON literals; failure is a test setup error.
        var data = try! JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        data.append(10)
        return data
    }
}

struct FakeReply: Sendable {
    var chunks: [Data] = []
    var delayBetweenChunks: Int32 = 0 // milliseconds, bounded and interrupted by stop()
    var holdOpen: Int32 = 0
}

final class FakeHerdrServer: @unchecked Sendable {
    let root: URL
    let path: String
    private let listener: Int32
    private let ownsRoot: Bool
    private let closeBeforeRequest: Bool
    private let lock = NSLock()
    private let group = DispatchGroup()
    private var stopped = false
    private var clients: Set<Int32> = []
    private let handler: @Sendable (FakeRequest) -> FakeReply

    init(root: URL? = nil, closeBeforeRequest: Bool = false, handler: @escaping @Sendable (FakeRequest) -> FakeReply) throws {
        self.ownsRoot = root == nil
        self.closeBeforeRequest = closeBeforeRequest
        let root = root ?? URL(fileURLWithPath: "/tmp/pt-\(UUID().uuidString.prefix(8))")
        self.root = root
        self.path = root.appendingPathComponent("herdr.sock").path
        self.handler = handler
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        listener = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listener >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno)!) }
        do {
            try Self.bindSocket(listener, path: path)
            guard listen(listener, 32) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno)!) }
        } catch {
            Darwin.close(listener)
            try? FileManager.default.removeItem(atPath: path)
            throw error
        }
        group.enter()
        Thread.detachNewThread { [self] in
            defer { group.leave() }
            while !lock.withLock({ stopped }) {
                var descriptor = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)
                guard poll(&descriptor, 1, 20) > 0 else { continue }
                if lock.withLock({ stopped }) { break }
                let fd = accept(listener, nil, nil)
                guard fd >= 0 else { continue }
                lock.withLock { _ = clients.insert(fd) }
                group.enter()
                Thread.detachNewThread { [self] in
                    defer {
                        lock.withLock {
                            clients.remove(fd)
                            Darwin.close(fd)
                        }
                        group.leave()
                    }
                    serve(fd)
                }
            }
        }
    }

    static func bindSocket(_ fd: Int32, path: String) throws {
        var address = sockaddr_un()
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            throw POSIXError(.ENAMETOOLONG)
        }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: bytes + [0])
        }
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno)!) }
    }

    private func serve(_ fd: Int32) {
        if closeBeforeRequest { return }
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while !data.contains(10) {
            let count = recv(fd, &buffer, buffer.count, 0)
            guard count > 0 else { return }
            data.append(contentsOf: buffer.prefix(count))
        }
        guard let newline = data.firstIndex(of: 10),
              let json = try? JSONSerialization.jsonObject(with: data[..<newline]) as? [String: Any]
        else { return }
        let reply = handler(FakeRequest(json: json))
        for (index, chunk) in reply.chunks.enumerated() {
            if index > 0 { pause(fd, milliseconds: reply.delayBetweenChunks) }
            var offset = 0
            while offset < chunk.count {
                let count = chunk.withUnsafeBytes {
                    send(fd, $0.baseAddress!.advanced(by: offset), chunk.count - offset, 0)
                }
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { return }
                offset += count
            }
        }
        pause(fd, milliseconds: reply.holdOpen)
    }

    private func pause(_ fd: Int32, milliseconds: Int32) {
        guard milliseconds > 0 else { return }
        var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        _ = poll(&descriptor, 1, milliseconds)
    }

    func stop() {
        let needsStop = lock.withLock {
            if stopped { return false }
            stopped = true
            for fd in clients { shutdown(fd, SHUT_RDWR) }
            return true
        }
        guard needsStop else { return }
        group.wait()
        Darwin.close(listener)
        try? FileManager.default.removeItem(atPath: path)
        // The caller owns explicitly supplied roots; scanner tests remove those.
        if ownsRoot { try? FileManager.default.removeItem(at: root) }
    }
}
