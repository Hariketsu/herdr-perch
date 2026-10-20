import Foundation

public struct SessionEndpoint: Hashable, Sendable {
    public var name: String
    public var socketPath: String
    public var isDefault: Bool

    public init(name: String, socketPath: String, isDefault: Bool) {
        self.name = name
        self.socketPath = socketPath
        self.isDefault = isDefault
    }
}

public struct SessionScanner: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// `<root>/herdr.sock` is the default session; `<root>/sessions/<name>/herdr.sock`
    /// are named sessions. Only real sockets count — symlinks are never followed.
    public func scan() -> [SessionEndpoint] {
        var endpoints: [SessionEndpoint] = []
        let defaultSocket = root.appendingPathComponent("herdr.sock").path
        if Self.fileType(defaultSocket) == S_IFSOCK {
            endpoints.append(SessionEndpoint(name: "default", socketPath: defaultSocket, isDefault: true))
        }
        let sessions = root.appendingPathComponent("sessions")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: sessions.path)) ?? []
        for name in names.sorted() {
            let directory = sessions.appendingPathComponent(name)
            guard Self.fileType(directory.path) == S_IFDIR else { continue }
            let socket = directory.appendingPathComponent("herdr.sock").path
            guard Self.fileType(socket) == S_IFSOCK else { continue }
            endpoints.append(SessionEndpoint(name: name, socketPath: socket, isDefault: false))
        }
        return endpoints
    }

    private static func fileType(_ path: String) -> mode_t? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return info.st_mode & S_IFMT
    }
}
