import Foundation
import StoatModels

public enum ReadyField: String, Codable, CaseIterable, Sendable {
    case users
    case servers
    case channels
    case members
    case emojis
    case userSettings = "user_settings"
    case channelUnreads = "channel_unreads"
    case policyChanges = "policy_changes"
}

public struct ReadySnapshot: Equatable, Sendable {
    public var users: [User]
    public var servers: [Server]
    public var channels: [Channel]

    public init(users: [User] = [], servers: [Server] = [], channels: [Channel] = []) {
        self.users = users
        self.servers = servers
        self.channels = channels
    }
}

public enum StoatEvent: Equatable, Sendable {
    case authenticated
    case ready(ReadySnapshot)
    case message(Message)
    case unknown(type: String)
}

public enum RealtimeError: Error, Equatable, Sendable {
    case notImplemented
}

public actor RealtimeClient {
    public init() {}

    public func connect(sessionToken: String, readyFields: [ReadyField]) async throws {
        throw RealtimeError.notImplemented
    }

    public func disconnect() {}
}
