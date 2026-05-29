import Foundation
import StoatModels

public actor ServerSubscriptionManager {
    private var subscriptions: [ServerID: Date] = [:]
    private let maximumActiveSubscriptions: Int
    private let minimumResubscribeInterval: TimeInterval
    private let expirationInterval: TimeInterval

    public init(
        maximumActiveSubscriptions: Int = 5,
        minimumResubscribeInterval: TimeInterval = 10 * 60,
        expirationInterval: TimeInterval = 15 * 60
    ) {
        self.maximumActiveSubscriptions = maximumActiveSubscriptions
        self.minimumResubscribeInterval = minimumResubscribeInterval
        self.expirationInterval = expirationInterval
    }

    public func shouldSubscribe(serverID: ServerID, appIsFocused: Bool, now: Date = Date()) -> Bool {
        guard appIsFocused else { return false }
        expire(now: now)
        if let last = subscriptions[serverID], now.timeIntervalSince(last) < minimumResubscribeInterval {
            return false
        }
        if subscriptions[serverID] == nil, subscriptions.count >= maximumActiveSubscriptions {
            return false
        }
        subscriptions[serverID] = now
        return true
    }

    public func activeSubscriptions(now: Date = Date()) -> Set<ServerID> {
        expire(now: now)
        return Set(subscriptions.keys)
    }

    private func expire(now: Date) {
        subscriptions = subscriptions.filter { now.timeIntervalSince($0.value) < expirationInterval }
    }
}

