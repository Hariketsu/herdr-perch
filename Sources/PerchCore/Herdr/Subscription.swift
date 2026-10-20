public struct Subscription: Hashable, Sendable {
    public var type: String
    public var paneID: String?

    public init(type: String, paneID: String? = nil) {
        self.type = type
        self.paneID = paneID
    }
}

public enum EventSignal: Equatable, Sendable {
    case started
    case event
}
