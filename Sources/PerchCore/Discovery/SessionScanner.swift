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

    public func scan() -> [SessionEndpoint] { fatalError("unimplemented") }
}
