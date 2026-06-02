import Foundation
import StoatModels

public enum GatewayErrorCode: String, Codable, Hashable, Sendable {
    case labelMe = "LabelMe"
    case internalError = "InternalError"
    case invalidSession = "InvalidSession"
    case onboardingNotFinished = "OnboardingNotFinished"
    case alreadyAuthenticated = "AlreadyAuthenticated"
    case unknown

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = GatewayErrorCode(rawValue: (try? container.decode(String.self)) ?? "") ?? .unknown
    }
}

public enum ClientGatewayEvent: Equatable, Sendable, CustomDebugStringConvertible, Encodable {
    case authenticate(token: String)
    case beginTyping(channel: ChannelID)
    case endTyping(channel: ChannelID)
    case ping(data: Int64?)
    case subscribe(serverID: ServerID)

    public var debugDescription: String {
        switch self {
        case .authenticate:
            "Authenticate(token: <redacted>)"
        case let .beginTyping(channel):
            "BeginTyping(channel: \(channel.rawValue))"
        case let .endTyping(channel):
            "EndTyping(channel: \(channel.rawValue))"
        case let .ping(data):
            "Ping(data: \(data.map(String.init) ?? "nil"))"
        case let .subscribe(serverID):
            "Subscribe(serverID: \(serverID.rawValue))"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case token
        case channel
        case data
        case serverID = "server_id"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .authenticate(token):
            try container.encode("Authenticate", forKey: .type)
            try container.encode(token, forKey: .token)
        case let .beginTyping(channel):
            try container.encode("BeginTyping", forKey: .type)
            try container.encode(channel, forKey: .channel)
        case let .endTyping(channel):
            try container.encode("EndTyping", forKey: .type)
            try container.encode(channel, forKey: .channel)
        case let .ping(data):
            try container.encode("Ping", forKey: .type)
            try container.encodeIfPresent(data, forKey: .data)
        case let .subscribe(serverID):
            try container.encode("Subscribe", forKey: .type)
            try container.encode(serverID, forKey: .serverID)
        }
    }
}

public struct PartialMessage: Codable, Hashable, Sendable {
    public var content: String?
    public var editedAt: Date?
    public var embeds: [Embed]?
    public var pinned: Bool?
    public var reactions: [String: Set<UserID>]?
    public var raw: JSONValue?

    public init(content: String? = nil, editedAt: Date? = nil, embeds: [Embed]? = nil, pinned: Bool? = nil, reactions: [String: Set<UserID>]? = nil, raw: JSONValue? = nil) {
        self.content = content
        self.editedAt = editedAt
        self.embeds = embeds
        self.pinned = pinned
        self.reactions = reactions
        self.raw = raw
    }

    private enum CodingKeys: String, CodingKey {
        case content
        case editedAt = "edited"
        case embeds
        case pinned
        case reactions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        content = try container.decodeIfPresent(String.self, forKey: .content)
        editedAt = try container.decodeIfPresent(Date.self, forKey: .editedAt)
        embeds = try container.decodeIfPresent([Embed].self, forKey: .embeds)
        pinned = try container.decodeIfPresent(Bool.self, forKey: .pinned)
        reactions = try container.decodeIfPresent([String: Set<UserID>].self, forKey: .reactions)
        raw = try? JSONValue(from: decoder)
    }
}

public struct PartialChannel: Codable, Hashable, Sendable {
    public var name: String?
    public var description: String?
    public var lastMessageID: MessageID?
    public var raw: JSONValue?

    private enum CodingKeys: String, CodingKey {
        case name
        case description
        case lastMessageID = "last_message_id"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        lastMessageID = try container.decodeIfPresent(MessageID.self, forKey: .lastMessageID)
        raw = try? JSONValue(from: decoder)
    }
}

public struct PartialServer: Codable, Hashable, Sendable {
    public var name: String?
    public var description: String?
    public var raw: JSONValue?

    public init(name: String? = nil, description: String? = nil, raw: JSONValue? = nil) {
        self.name = name
        self.description = description
        self.raw = raw
    }
}

public struct PartialServerMember: Codable, Hashable, Sendable {
    public var nickname: String?
    public var roles: [RoleID]?
    public var raw: JSONValue?

    private enum CodingKeys: String, CodingKey {
        case nickname
        case roles
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nickname = try container.decodeIfPresent(String.self, forKey: .nickname)
        roles = try container.decodeIfPresent([RoleID].self, forKey: .roles)
        raw = try? JSONValue(from: decoder)
    }
}

public struct PartialRole: Codable, Hashable, Sendable {
    public var name: String?
    public var raw: JSONValue?

    private enum CodingKeys: String, CodingKey {
        case name
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        raw = try? JSONValue(from: decoder)
    }
}

public struct PartialUser: Codable, Hashable, Sendable {
    public var username: String?
    public var displayName: String?
    public var status: UserStatus?
    public var relationship: RelationshipStatus?
    public var online: Bool?
    public var flags: UInt32?
    public var badges: UInt32?
    public var raw: JSONValue?

    private enum CodingKeys: String, CodingKey {
        case username
        case displayName = "display_name"
        case status
        case relationship
        case online
        case flags
        case badges
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        username = try container.decodeIfPresent(String.self, forKey: .username)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        status = try container.decodeIfPresent(UserStatus.self, forKey: .status)
        relationship = try container.decodeIfPresent(RelationshipStatus.self, forKey: .relationship)
        online = try container.decodeIfPresent(Bool.self, forKey: .online)
        flags = try container.decodeIfPresent(UInt32.self, forKey: .flags)
        badges = try container.decodeIfPresent(UInt32.self, forKey: .badges)
        raw = try? JSONValue(from: decoder)
    }
}

public struct PartialEmoji: Codable, Hashable, Sendable {
    public var name: String?
    public var raw: JSONValue?

    private enum CodingKeys: String, CodingKey {
        case name
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        raw = try? JSONValue(from: decoder)
    }
}

public struct MessageUpdateEvent: Codable, Hashable, Sendable {
    public var id: MessageID
    public var channelID: ChannelID
    public var data: PartialMessage
    public var clear: [String]

    private enum CodingKeys: String, CodingKey {
        case id
        case channelID = "channel"
        case data
        case clear
    }
}

public struct MessageAppendEvent: Codable, Hashable, Sendable {
    public var id: MessageID
    public var channelID: ChannelID
    public var append: PartialMessage

    private enum CodingKeys: String, CodingKey {
        case id
        case channelID = "channel"
        case append
    }
}

public struct MessageDeleteEvent: Codable, Hashable, Sendable {
    public var id: MessageID
    public var channelID: ChannelID

    private enum CodingKeys: String, CodingKey {
        case id
        case channelID = "channel"
    }
}

public struct BulkMessageDeleteEvent: Codable, Hashable, Sendable {
    public var channelID: ChannelID
    public var ids: [MessageID]

    private enum CodingKeys: String, CodingKey {
        case channelID = "channel"
        case ids
    }
}

public struct MessageReactionEvent: Codable, Hashable, Sendable {
    public var id: MessageID
    public var channelID: ChannelID
    public var userID: UserID
    public var emojiID: String

    private enum CodingKeys: String, CodingKey {
        case id
        case channelID = "channel_id"
        case userID = "user_id"
        case emojiID = "emoji_id"
    }
}

public struct MessageRemoveReactionEvent: Codable, Hashable, Sendable {
    public var id: MessageID
    public var channelID: ChannelID
    public var emojiID: String

    private enum CodingKeys: String, CodingKey {
        case id
        case channelID = "channel_id"
        case emojiID = "emoji_id"
    }
}

public struct ChannelUpdateEvent: Codable, Hashable, Sendable {
    public var id: ChannelID
    public var data: PartialChannel
    public var clear: [String]
}

public struct ChannelDeleteEvent: Codable, Hashable, Sendable {
    public var id: ChannelID
}

public struct ChannelUserEvent: Codable, Hashable, Sendable {
    public var id: ChannelID
    public var userID: UserID

    private enum CodingKeys: String, CodingKey {
        case id
        case userID = "user"
    }
}

public struct ChannelAckEvent: Codable, Hashable, Sendable {
    public var id: ChannelID
    public var userID: UserID
    public var messageID: MessageID

    private enum CodingKeys: String, CodingKey {
        case id
        case userID = "user"
        case messageID = "message_id"
    }
}

public struct ServerCreateEvent: Codable, Hashable, Sendable {
    public var id: ServerID
    public var server: Server
    public var channels: [Channel]
    public var emojis: [Emoji]
}

public struct ServerUpdateEvent: Codable, Hashable, Sendable {
    public var id: ServerID
    public var data: PartialServer
    public var clear: [String]
}

public struct ServerDeleteEvent: Codable, Hashable, Sendable {
    public var id: ServerID
}

public struct ServerMemberUpdateEvent: Codable, Hashable, Sendable {
    public var id: MemberCompositeKey
    public var data: PartialServerMember
    public var clear: [String]
}

public struct ServerMemberJoinEvent: Codable, Hashable, Sendable {
    public var id: ServerID
    public var userID: UserID
    public var member: ServerMember?

    private enum CodingKeys: String, CodingKey {
        case id
        case userID = "user"
        case member
    }
}

public struct ServerMemberLeaveEvent: Codable, Hashable, Sendable {
    public var id: ServerID
    public var userID: UserID
    public var reason: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case userID = "user"
        case reason
    }
}

public struct ServerRoleUpdateEvent: Codable, Hashable, Sendable {
    public var id: ServerID
    public var roleID: RoleID
    public var data: PartialRole
    public var clear: [String]

    private enum CodingKeys: String, CodingKey {
        case id
        case roleID = "role_id"
        case data
        case clear
    }
}

public struct ServerRoleDeleteEvent: Codable, Hashable, Sendable {
    public var id: ServerID
    public var roleID: RoleID

    private enum CodingKeys: String, CodingKey {
        case id
        case roleID = "role_id"
    }
}

public struct UserUpdateEvent: Codable, Hashable, Sendable {
    public var id: UserID
    public var data: PartialUser
    public var clear: [String]
    public var eventID: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case data
        case clear
        case eventID = "event_id"
    }
}

public struct UserRelationshipEvent: Codable, Hashable, Sendable {
    public var id: UserID?
    public var user: User
    public var status: RelationshipStatus?

    public init(id: UserID? = nil, user: User, status: RelationshipStatus? = nil) {
        self.id = id
        self.user = user
        self.status = status
    }
}

public struct UserPresenceEvent: Codable, Hashable, Sendable {
    public var id: UserID
    public var online: Bool
}

public struct UserSettingsUpdateEvent: Codable, Hashable, Sendable {
    public var id: UserID
    public var update: UserSettings
}

public struct UserPlatformWipeEvent: Codable, Hashable, Sendable {
    public var userID: UserID
    public var flags: Int

    private enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case flags
    }
}

public struct EmojiUpdateEvent: Codable, Hashable, Sendable {
    public var id: EmojiID
    public var data: PartialEmoji
}

public struct EmojiDeleteEvent: Codable, Hashable, Sendable {
    public var id: EmojiID
}

public enum AuthForwardedEvent: Hashable, Sendable {
    case deleteSession(userID: UserID, sessionID: SessionID)
    case deleteAllSessions(userID: UserID, excludeSessionID: SessionID)
    case unknown(eventType: String?, raw: JSONValue)
}

public enum StoatGatewayEvent: Hashable, Sendable {
    case error(GatewayErrorCode)
    case authenticated
    case logout
    case bulk([StoatGatewayEvent])
    case pong(data: Int64?)
    case ready(ReadyPayload)
    case message(Message)
    case messageUpdate(MessageUpdateEvent)
    case messageAppend(MessageAppendEvent)
    case messageDelete(MessageDeleteEvent)
    case bulkMessageDelete(BulkMessageDeleteEvent)
    case messageReact(MessageReactionEvent)
    case messageUnreact(MessageReactionEvent)
    case messageRemoveReaction(MessageRemoveReactionEvent)
    case channelCreate(Channel)
    case channelUpdate(ChannelUpdateEvent)
    case channelDelete(ChannelDeleteEvent)
    case channelGroupJoin(ChannelUserEvent)
    case channelGroupLeave(ChannelUserEvent)
    case channelStartTyping(ChannelUserEvent)
    case channelStopTyping(ChannelUserEvent)
    case channelAck(ChannelAckEvent)
    case serverCreate(ServerCreateEvent)
    case serverUpdate(ServerUpdateEvent)
    case serverDelete(ServerDeleteEvent)
    case serverMemberUpdate(ServerMemberUpdateEvent)
    case serverMemberJoin(ServerMemberJoinEvent)
    case serverMemberLeave(ServerMemberLeaveEvent)
    case serverRoleUpdate(ServerRoleUpdateEvent)
    case serverRoleDelete(ServerRoleDeleteEvent)
    case userUpdate(UserUpdateEvent)
    case userRelationship(UserRelationshipEvent)
    case userPresence(UserPresenceEvent)
    case userSettingsUpdate(UserSettingsUpdateEvent)
    case userPlatformWipe(UserPlatformWipeEvent)
    case emojiCreate(Emoji)
    case emojiUpdate(EmojiUpdateEvent)
    case emojiDelete(EmojiDeleteEvent)
    case auth(AuthForwardedEvent)
    case unknown(type: String, raw: JSONValue)
}

extension StoatGatewayEvent: Decodable {
    private enum CodingKeys: String, CodingKey {
        case type
        case data
        case eventType = "event_type"
        case userID = "user_id"
        case sessionID = "session_id"
        case excludeSessionID = "exclude_session_id"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "Error":
            self = .error(try container.decode(GatewayErrorCode.self, forKey: .data))
        case "Authenticated":
            self = .authenticated
        case "Logout":
            self = .logout
        case "Bulk":
            self = .bulk(try EventEnvelope.decode(StoatGatewayEvent.self, from: decoder))
        case "Pong":
            let value = try? container.decode(Int64.self, forKey: .data)
            self = .pong(data: value)
        case "Ready":
            self = .ready(try ReadyPayload(from: decoder))
        case "Message":
            self = .message(try Message(from: decoder))
        case "MessageUpdate":
            self = .messageUpdate(try MessageUpdateEvent(from: decoder))
        case "MessageAppend":
            self = .messageAppend(try MessageAppendEvent(from: decoder))
        case "MessageDelete":
            self = .messageDelete(try MessageDeleteEvent(from: decoder))
        case "BulkMessageDelete":
            self = .bulkMessageDelete(try BulkMessageDeleteEvent(from: decoder))
        case "MessageReact":
            self = .messageReact(try MessageReactionEvent(from: decoder))
        case "MessageUnreact":
            self = .messageUnreact(try MessageReactionEvent(from: decoder))
        case "MessageRemoveReaction":
            self = .messageRemoveReaction(try MessageRemoveReactionEvent(from: decoder))
        case "ChannelCreate":
            self = .channelCreate(try Channel(from: decoder))
        case "ChannelUpdate":
            self = .channelUpdate(try ChannelUpdateEvent(from: decoder))
        case "ChannelDelete":
            self = .channelDelete(try ChannelDeleteEvent(from: decoder))
        case "ChannelGroupJoin":
            self = .channelGroupJoin(try ChannelUserEvent(from: decoder))
        case "ChannelGroupLeave":
            self = .channelGroupLeave(try ChannelUserEvent(from: decoder))
        case "ChannelStartTyping":
            self = .channelStartTyping(try ChannelUserEvent(from: decoder))
        case "ChannelStopTyping":
            self = .channelStopTyping(try ChannelUserEvent(from: decoder))
        case "ChannelAck":
            self = .channelAck(try ChannelAckEvent(from: decoder))
        case "ServerCreate":
            self = .serverCreate(try ServerCreateEvent(from: decoder))
        case "ServerUpdate":
            self = .serverUpdate(try ServerUpdateEvent(from: decoder))
        case "ServerDelete":
            self = .serverDelete(try ServerDeleteEvent(from: decoder))
        case "ServerMemberUpdate":
            self = .serverMemberUpdate(try ServerMemberUpdateEvent(from: decoder))
        case "ServerMemberJoin":
            self = .serverMemberJoin(try ServerMemberJoinEvent(from: decoder))
        case "ServerMemberLeave":
            self = .serverMemberLeave(try ServerMemberLeaveEvent(from: decoder))
        case "ServerRoleUpdate":
            self = .serverRoleUpdate(try ServerRoleUpdateEvent(from: decoder))
        case "ServerRoleDelete":
            self = .serverRoleDelete(try ServerRoleDeleteEvent(from: decoder))
        case "UserUpdate":
            self = .userUpdate(try UserUpdateEvent(from: decoder))
        case "UserRelationship":
            self = .userRelationship(try UserRelationshipEvent(from: decoder))
        case "UserPresence":
            self = .userPresence(try UserPresenceEvent(from: decoder))
        case "UserSettingsUpdate":
            self = .userSettingsUpdate(try UserSettingsUpdateEvent(from: decoder))
        case "UserPlatformWipe":
            self = .userPlatformWipe(try UserPlatformWipeEvent(from: decoder))
        case "EmojiCreate":
            self = .emojiCreate(try Emoji(from: decoder))
        case "EmojiUpdate":
            self = .emojiUpdate(try EmojiUpdateEvent(from: decoder))
        case "EmojiDelete":
            self = .emojiDelete(try EmojiDeleteEvent(from: decoder))
        case "Auth":
            let raw = (try? JSONValue(from: decoder)) ?? .object([:])
            let eventType = try container.decodeIfPresent(String.self, forKey: .eventType)
            switch eventType {
            case "DeleteSession":
                self = .auth(.deleteSession(userID: try container.decode(UserID.self, forKey: .userID), sessionID: try container.decode(SessionID.self, forKey: .sessionID)))
            case "DeleteAllSessions":
                self = .auth(.deleteAllSessions(userID: try container.decode(UserID.self, forKey: .userID), excludeSessionID: try container.decode(SessionID.self, forKey: .excludeSessionID)))
            default:
                self = .auth(.unknown(eventType: eventType, raw: raw))
            }
        default:
            self = .unknown(type: type, raw: (try? JSONValue(from: decoder)) ?? .object([:]))
        }
    }
}

private struct EventEnvelope: Decodable {
    var v: [StoatGatewayEvent]

    static func decode(_ type: StoatGatewayEvent.Type, from decoder: Decoder) throws -> [StoatGatewayEvent] {
        try EventEnvelope(from: decoder).v
    }
}
