import Darwin
import Foundation
import Testing
import PerchCore

@Suite struct SessionScannerTests {
    private func root() throws -> URL {
        let root = URL(fileURLWithPath: "/tmp/ps-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test func missingRootIsEmpty() {
        #expect(SessionScanner(root: URL(fileURLWithPath: "/tmp/absent-\(UUID().uuidString)")).scan().isEmpty)
    }

    @Test func onlyDefault() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let server = try FakeHerdrServer(root: root) { _ in FakeReply() }
        defer { server.stop() }
        #expect(SessionScanner(root: root).scan() == [
            SessionEndpoint(name: "default", socketPath: server.path, isDefault: true)
        ])
    }

    @Test func defaultFirstThenSortedNamedSessions() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let defaultServer = try FakeHerdrServer(root: root) { _ in FakeReply() }
        defer { defaultServer.stop() }
        let z = try FakeHerdrServer(root: root.appendingPathComponent("sessions/zeta")) { _ in FakeReply() }
        defer { z.stop() }
        // Alphabetically before "default", yet the root socket must still come first.
        let a = try FakeHerdrServer(root: root.appendingPathComponent("sessions/alpha")) { _ in FakeReply() }
        defer { a.stop() }
        let scanner = SessionScanner(root: root)
        #expect(scanner.scan() == [
            SessionEndpoint(name: "default", socketPath: defaultServer.path, isDefault: true),
            SessionEndpoint(name: "alpha", socketPath: a.path, isDefault: false),
            SessionEndpoint(name: "zeta", socketPath: z.path, isDefault: false)
        ])
        z.stop()
        #expect(scanner.scan().map(\.name) == ["default", "alpha"])
    }

    @Test func ignoresFilesDirectoriesSymlinksAndEmptySessions() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = FileManager.default
        let valid = try FakeHerdrServer(root: root.appendingPathComponent("sessions/valid")) { _ in FakeReply() }
        defer { valid.stop() }
        for name in ["empty", "file", "directory", "linkedSocket"] {
            try manager.createDirectory(at: root.appendingPathComponent("sessions/\(name)"), withIntermediateDirectories: true)
        }
        try Data().write(to: root.appendingPathComponent("herdr.sock"))
        try Data().write(to: root.appendingPathComponent("sessions/file/herdr.sock"))
        try manager.createDirectory(at: root.appendingPathComponent("sessions/directory/herdr.sock"), withIntermediateDirectories: true)
        try manager.createSymbolicLink(atPath: root.appendingPathComponent("sessions/linkedSocket/herdr.sock").path,
                                      withDestinationPath: valid.path)
        try manager.createSymbolicLink(atPath: root.appendingPathComponent("sessions/linkedDirectory").path,
                                      withDestinationPath: valid.root.path)
        #expect(SessionScanner(root: root).scan() == [
            SessionEndpoint(name: "valid", socketPath: valid.path, isDefault: false)
        ])
        try manager.removeItem(at: root.appendingPathComponent("herdr.sock"))
        try manager.createSymbolicLink(atPath: root.appendingPathComponent("herdr.sock").path, withDestinationPath: valid.path)
        #expect(SessionScanner(root: root).scan().map(\.name) == ["valid"])
    }

    @Test func staleSocketIsStillDiscoveredWithoutPing() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EMFILE) }
        defer { Darwin.close(fd) }
        let path = root.appendingPathComponent("herdr.sock").path
        try FakeHerdrServer.bindSocket(fd, path: path)
        // Bound but not listening. Scanner recognizes filesystem type, not reachability.
        #expect(SessionScanner(root: root).scan() == [SessionEndpoint(name: "default", socketPath: path, isDefault: true)])
    }
}
