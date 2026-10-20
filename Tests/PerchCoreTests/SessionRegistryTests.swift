import Darwin
import Foundation
import Testing
import PerchCore

@Suite struct SessionRegistryTests {
    private func root() throws -> URL {
        let url = URL(fileURLWithPath: "/tmp/pr-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func newSocketIsAdmittedWithinOneScanCycleAndSorted() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let log = StateLog<[SessionState]>()
        let registry = SessionRegistry(scanner: SessionScanner(root: root), scanInterval: .milliseconds(50),
                                       clientTimeout: .milliseconds(150), onChange: { log.append($0) })
        await registry.start()
        let z = try ScriptedHerdr(root: root.appendingPathComponent("sessions/zeta"))
        defer { z.stop() }
        let a = try ScriptedHerdr(root: root.appendingPathComponent("sessions/alpha"))
        defer { a.stop() }
        let main = try ScriptedHerdr(root: root)
        defer { main.stop() }
        _ = await eventually(within: .milliseconds(500)) {
            log.last?.map(\.endpoint.name) == ["default", "alpha", "zeta"]
        }
        #expect(await registry.sessions.map(\.endpoint.name) == ["default", "alpha", "zeta"])
        await registry.stop()
    }

    @Test func leftoverSocketWithoutListenerIsNotAdmitted() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("sessions/leftover")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EMFILE) }
        do {
            try FakeHerdrServer.bindSocket(fd, path: directory.appendingPathComponent("herdr.sock").path)
        } catch {
            Darwin.close(fd)
            throw error
        }
        Darwin.close(fd) // The filesystem socket survives, but no server is listening.
        #expect(SessionScanner(root: root).scan().count == 1)
        let registry = SessionRegistry(scanner: SessionScanner(root: root), clientTimeout: .milliseconds(150), onChange: { _ in })
        await registry.scanOnce()
        #expect(await registry.sessions.isEmpty)
        await registry.stop()
    }

    @Test func failedPingIsNotAdmittedAndIsRetriedNextScan() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let server = try ScriptedHerdr(root: root.appendingPathComponent("sessions/test"))
        defer { server.stop() }
        server.script.failPings(("unavailable", "not ready"))
        let registry = SessionRegistry(scanner: SessionScanner(root: root), clientTimeout: .milliseconds(150), onChange: { _ in })
        await registry.scanOnce()
        #expect(await registry.sessions.isEmpty)
        #expect(server.script.snapshotCount == 0)
        server.script.failPings(nil)
        await registry.scanOnce()
        _ = await eventually { await registry.sessions.first?.snapshot != nil }
        #expect(await registry.sessions.map(\.endpoint.name) == ["test"])
        await registry.stop()
    }

    @Test func socketDisappearanceImmediatelyRemovesSession() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let server = try ScriptedHerdr(root: root.appendingPathComponent("sessions/test"))
        defer { server.stop() }
        let registry = SessionRegistry(scanner: SessionScanner(root: root), clientTimeout: .milliseconds(150), onChange: { _ in })
        await registry.scanOnce()
        _ = await eventually { await registry.sessions.count == 1 }
        try FileManager.default.removeItem(atPath: server.server.path)
        await registry.scanOnce()
        #expect(await registry.sessions.isEmpty)
        await registry.stop()
    }

    @Test func unreachableTimeoutUsesInjectedTimeAndRequiresSuccessfulPingToRejoin() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let server = try ScriptedHerdr(root: root.appendingPathComponent("sessions/test"))
        defer { server.stop() }
        let clock = ManualDate()
        let registry = SessionRegistry(scanner: SessionScanner(root: root), unreachableTimeout: .seconds(1),
                                       clientTimeout: .milliseconds(150), now: { clock.now() }, onChange: { _ in })
        await registry.scanOnce()
        _ = await eventually { server.script.snapshotCount >= 2 && !server.script.subscriptions.isEmpty }
        server.script.failSnapshots(("unavailable", "offline"))
        server.script.failPings(("unavailable", "offline"))
        server.script.event()
        _ = await eventually { await registry.sessions.first?.health == .stale(since: clock.now()) }
        clock.advance(0.75)
        await registry.scanOnce()
        #expect(await registry.sessions.count == 1)
        clock.advance(0.5)
        await registry.scanOnce()
        #expect(await registry.sessions.isEmpty)
        await registry.scanOnce()
        #expect(await registry.sessions.isEmpty)
        server.script.failPings(nil)
        server.script.failSnapshots(nil)
        await registry.scanOnce()
        _ = await eventually {
            let sessions = await registry.sessions
            return sessions.first?.health == .live && sessions.first?.snapshot != nil
        }
        await registry.stop()
    }

    @Test func oldProtocolCreatesHealthOnlyPlaceholder() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let server = try ScriptedHerdr(root: root.appendingPathComponent("sessions/old"))
        defer { server.stop() }
        server.script.setProtocol(21)
        let registry = SessionRegistry(scanner: SessionScanner(root: root), clientTimeout: .milliseconds(150), onChange: { _ in })
        await registry.scanOnce()
        let sessions = await registry.sessions
        #expect(sessions.count == 1)
        #expect(sessions.first?.health == .updateRequired(protocolVersion: 21))
        #expect(sessions.first?.snapshot == nil)
        #expect(server.script.snapshotCount == 0)
        await registry.stop()
    }
}
