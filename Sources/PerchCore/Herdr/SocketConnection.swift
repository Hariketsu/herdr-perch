// Derived from NotchAgent Sources/HerdrClient/SocketConnection.swift
// https://github.com/ykushch/notchagent — Copyright Yuri Kushch — Apache-2.0
// Modified by Herdr Perch.
import Darwin
import Foundation

/// One blocking Unix-socket connection with newline framing.
///
/// Herdr closes the socket after one request/response, so ordinary use is
/// connect → write one line → read one line → close. The event subscription is
/// the only long-lived connection.
///
/// All I/O is non-blocking + `poll`, so every call honours an absolute deadline
/// (nil = wait forever). `interrupt()` may be called from another thread to wake
/// a blocked reader.
final class SocketConnection: @unchecked Sendable {
    private let fd: Int32
    private var buffer = Data()

    private init(fd: Int32) {
        self.fd = fd
    }

    deinit {
        Darwin.close(fd)
    }

    static func connect(path: String, deadline: ContinuousClock.Instant?) throws -> SocketConnection {
        var address = sockaddr_un()
        let bytes = Array(path.utf8)
        // sun_path must also hold the trailing NUL.
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            throw HerdrError.connectFailed(ENAMETOOLONG)
        }
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes + [0]) }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw HerdrError.connectFailed(errno) }
        let connection = SocketConnection(fd: fd)

        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)

        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if result != 0 {
            let error = errno
            guard error == EINPROGRESS || error == EAGAIN else { throw HerdrError.connectFailed(error) }
            try connection.wait(for: POLLOUT, deadline: deadline)
            var pending: Int32 = 0
            var length = socklen_t(MemoryLayout<Int32>.size)
            getsockopt(fd, SOL_SOCKET, SO_ERROR, &pending, &length)
            if pending != 0 { throw HerdrError.connectFailed(pending) }
        }
        return connection
    }

    func writeLine(_ data: Data, deadline: ContinuousClock.Instant?) throws {
        var payload = data
        payload.append(0x0A)
        var offset = 0
        while offset < payload.count {
            let count = payload.withUnsafeBytes {
                Darwin.send(fd, $0.baseAddress!.advanced(by: offset), payload.count - offset, 0)
            }
            if count > 0 {
                offset += count
                continue
            }
            switch errno {
            case EINTR: continue
            case EAGAIN: try wait(for: POLLOUT, deadline: deadline)
            default: throw HerdrError.closedByPeer  // EPIPE, ECONNRESET, …
            }
        }
    }

    /// Next line without the trailing newline. EOF before a full line → `closedByPeer`.
    func readLine(deadline: ContinuousClock.Instant?) throws -> Data {
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)
                return Data(line)
            }
            let count = chunk.withUnsafeMutableBytes { Darwin.recv(fd, $0.baseAddress, $0.count, 0) }
            if count > 0 {
                buffer.append(contentsOf: chunk[0..<count])
            } else if count == 0 {
                throw HerdrError.closedByPeer
            } else {
                switch errno {
                case EINTR: continue
                case EAGAIN: try wait(for: POLLIN, deadline: deadline)
                default: throw HerdrError.closedByPeer
                }
            }
        }
    }

    /// Wakes any thread blocked in `readLine`/`writeLine`; they then see EOF.
    func interrupt() {
        Darwin.shutdown(fd, SHUT_RDWR)
    }

    private func wait(for events: Int32, deadline: ContinuousClock.Instant?) throws {
        while true {
            var timeout: Int32 = -1
            if let deadline {
                let remaining = ContinuousClock.now.duration(to: deadline)
                guard remaining > .zero else { throw HerdrError.timeout }
                let (seconds, attoseconds) = remaining.components
                timeout = Int32(clamping: seconds * 1000 + attoseconds / 1_000_000_000_000_000 + 1)
            }
            var descriptor = pollfd(fd: fd, events: Int16(events), revents: 0)
            let ready = poll(&descriptor, 1, timeout)
            if ready > 0 { return }
            if ready < 0 && errno != EINTR { throw HerdrError.closedByPeer }
        }
    }
}
