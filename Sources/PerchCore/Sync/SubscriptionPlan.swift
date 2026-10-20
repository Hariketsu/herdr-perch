public enum SubscriptionPlan {
    public static let global: Set<Subscription> = []

    public static func make(for snapshot: Snapshot) -> Set<Subscription> { fatalError("unimplemented") }
}

public enum PollingPolicy {
    public static func interval(streamHealthy: Bool, consecutiveFailures: Int) -> Duration {
        fatalError("unimplemented")
    }
}
