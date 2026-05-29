import Foundation

public struct UserID: RawRepresentable, Codable, Hashable, Sendable, Identifiable {
    public let rawValue: String

    public var id: String { rawValue }

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct ServerID: RawRepresentable, Codable, Hashable, Sendable, Identifiable {
    public let rawValue: String

    public var id: String { rawValue }

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct ChannelID: RawRepresentable, Codable, Hashable, Sendable, Identifiable {
    public let rawValue: String

    public var id: String { rawValue }

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct MessageID: RawRepresentable, Codable, Hashable, Sendable, Identifiable {
    public let rawValue: String

    public var id: String { rawValue }

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct User: Codable, Hashable, Sendable, Identifiable {
    public let id: UserID
    public var username: String
    public var displayName: String?

    public init(id: UserID, username: String, displayName: String? = nil) {
        self.id = id
        self.username = username
        self.displayName = displayName
    }
}

public struct Server: Codable, Hashable, Sendable, Identifiable {
    public let id: ServerID
    public var name: String

    public init(id: ServerID, name: String) {
        self.id = id
        self.name = name
    }
}

public struct Channel: Codable, Hashable, Sendable, Identifiable {
    public let id: ChannelID
    public var serverID: ServerID?
    public var name: String

    public init(id: ChannelID, serverID: ServerID? = nil, name: String) {
        self.id = id
        self.serverID = serverID
        self.name = name
    }
}

public struct Message: Codable, Hashable, Sendable, Identifiable {
    public let id: MessageID
    public var channelID: ChannelID
    public var authorID: UserID
    public var content: String
    public var createdAt: Date?

    public init(
        id: MessageID,
        channelID: ChannelID,
        authorID: UserID,
        content: String,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.channelID = channelID
        self.authorID = authorID
        self.content = content
        self.createdAt = createdAt
    }
}

public enum StoatModelsVersion {
    public static let phase = "Phase 0"
}
