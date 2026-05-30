import Foundation

public struct User: Codable, Hashable, Sendable, Identifiable {
    public let id: UserID
    public var username: String
    public var discriminator: String
    public var displayName: String?
    public var avatar: File?
    public var relations: [Relationship]
    public var badges: UInt32
    public var status: UserStatus?
    public var flags: UInt32
    public var privileged: Bool
    public var bot: BotInformation?
    public var relationship: RelationshipStatus
    public var online: Bool

    public init(
        id: UserID,
        username: String,
        discriminator: String = "0000",
        displayName: String? = nil,
        avatar: File? = nil,
        relations: [Relationship] = [],
        badges: UInt32 = 0,
        status: UserStatus? = nil,
        flags: UInt32 = 0,
        privileged: Bool = false,
        bot: BotInformation? = nil,
        relationship: RelationshipStatus = .none,
        online: Bool = false
    ) {
        self.id = id
        self.username = username
        self.discriminator = discriminator
        self.displayName = displayName
        self.avatar = avatar
        self.relations = relations
        self.badges = badges
        self.status = status
        self.flags = flags
        self.privileged = privileged
        self.bot = bot
        self.relationship = relationship
        self.online = online
    }

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case username
        case discriminator
        case displayName = "display_name"
        case avatar
        case relations
        case badges
        case status
        case flags
        case privileged
        case bot
        case relationship
        case online
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UserID.self, forKey: .id)
        username = try container.decode(String.self, forKey: .username)
        discriminator = try container.decodeDefault(String.self, forKey: .discriminator, default: "0000")
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        avatar = try container.decodeIfPresent(File.self, forKey: .avatar)
        relations = try container.decodeDefault([Relationship].self, forKey: .relations, default: [])
        badges = try container.decodeDefault(UInt32.self, forKey: .badges, default: 0)
        status = try container.decodeIfPresent(UserStatus.self, forKey: .status)
        flags = try container.decodeDefault(UInt32.self, forKey: .flags, default: 0)
        privileged = try container.decodeDefault(Bool.self, forKey: .privileged, default: false)
        bot = try container.decodeIfPresent(BotInformation.self, forKey: .bot)
        relationship = try container.decodeDefault(RelationshipStatus.self, forKey: .relationship, default: .none)
        online = try container.decodeDefault(Bool.self, forKey: .online, default: false)
    }
}

public struct BotInformation: Codable, Hashable, Sendable {
    public var ownerID: UserID?

    public init(ownerID: UserID? = nil) {
        self.ownerID = ownerID
    }

    private enum CodingKeys: String, CodingKey {
        case ownerID = "owner"
    }
}

public struct UserStatus: Codable, Hashable, Sendable {
    public var text: String?
    public var presence: Presence?

    public init(text: String? = nil, presence: Presence? = nil) {
        self.text = text
        self.presence = presence
    }
}

public enum Presence: Codable, Hashable, Sendable {
    case online
    case idle
    case focus
    case busy
    case invisible
    case unknown(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        switch try container.decode(String.self) {
        case "Online": self = .online
        case "Idle": self = .idle
        case "Focus": self = .focus
        case "Busy": self = .busy
        case "Invisible": self = .invisible
        case let value: self = .unknown(value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawAPIValue)
    }

    public var rawAPIValue: String {
        switch self {
        case .online: "Online"
        case .idle: "Idle"
        case .focus: "Focus"
        case .busy: "Busy"
        case .invisible: "Invisible"
        case let .unknown(value): value
        }
    }
}

public struct Relationship: Codable, Hashable, Sendable, Identifiable {
    public let id: UserID
    public var status: RelationshipStatus

    public init(id: UserID, status: RelationshipStatus) {
        self.id = id
        self.status = status
    }

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case status
    }
}

public enum RelationshipStatus: Codable, Hashable, Sendable {
    case none
    case user
    case friend
    case outgoing
    case incoming
    case blocked
    case blockedOther
    case unknown(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        switch try container.decode(String.self) {
        case "None": self = .none
        case "User": self = .user
        case "Friend": self = .friend
        case "Outgoing": self = .outgoing
        case "Incoming": self = .incoming
        case "Blocked": self = .blocked
        case "BlockedOther": self = .blockedOther
        case let value: self = .unknown(value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawAPIValue)
    }

    public var rawAPIValue: String {
        switch self {
        case .none: "None"
        case .user: "User"
        case .friend: "Friend"
        case .outgoing: "Outgoing"
        case .incoming: "Incoming"
        case .blocked: "Blocked"
        case .blockedOther: "BlockedOther"
        case let .unknown(value): value
        }
    }
}

public struct File: Codable, Hashable, Sendable, Identifiable {
    public let id: FileID
    public var tag: String
    public var filename: String
    public var metadata: FileMetadata
    public var contentType: String
    public var size: Int
    public var deleted: Bool?
    public var reported: Bool?
    public var messageID: MessageID?
    public var userID: UserID?
    public var serverID: ServerID?
    public var objectID: String?

    public init(
        id: FileID,
        tag: String,
        filename: String,
        metadata: FileMetadata = .file,
        contentType: String,
        size: Int,
        deleted: Bool? = nil,
        reported: Bool? = nil,
        messageID: MessageID? = nil,
        userID: UserID? = nil,
        serverID: ServerID? = nil,
        objectID: String? = nil
    ) {
        self.id = id
        self.tag = tag
        self.filename = filename
        self.metadata = metadata
        self.contentType = contentType
        self.size = size
        self.deleted = deleted
        self.reported = reported
        self.messageID = messageID
        self.userID = userID
        self.serverID = serverID
        self.objectID = objectID
    }

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case tag
        case filename
        case metadata
        case contentType = "content_type"
        case size
        case deleted
        case reported
        case messageID = "message_id"
        case userID = "user_id"
        case serverID = "server_id"
        case objectID = "object_id"
    }
}

public enum FileMetadata: Codable, Hashable, Sendable {
    case file
    case text
    case image(width: Int, height: Int, thumbhash: [UInt8]?, animated: Bool?)
    case video(width: Int, height: Int)
    case audio
    case unknown(String)

    private enum CodingKeys: String, CodingKey {
        case type
        case width
        case height
        case thumbhash
        case animated
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "File":
            self = .file
        case "Text":
            self = .text
        case "Image":
            self = .image(
                width: try container.decode(Int.self, forKey: .width),
                height: try container.decode(Int.self, forKey: .height),
                thumbhash: try container.decodeIfPresent([UInt8].self, forKey: .thumbhash),
                animated: try container.decodeIfPresent(Bool.self, forKey: .animated)
            )
        case "Video":
            self = .video(
                width: try container.decode(Int.self, forKey: .width),
                height: try container.decode(Int.self, forKey: .height)
            )
        case "Audio":
            self = .audio
        case let value:
            self = .unknown(value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .file:
            try container.encode("File", forKey: .type)
        case .text:
            try container.encode("Text", forKey: .type)
        case let .image(width, height, thumbhash, animated):
            try container.encode("Image", forKey: .type)
            try container.encode(width, forKey: .width)
            try container.encode(height, forKey: .height)
            try container.encodeIfPresent(thumbhash, forKey: .thumbhash)
            try container.encodeIfPresent(animated, forKey: .animated)
        case let .video(width, height):
            try container.encode("Video", forKey: .type)
            try container.encode(width, forKey: .width)
            try container.encode(height, forKey: .height)
        case .audio:
            try container.encode("Audio", forKey: .type)
        case let .unknown(value):
            try container.encode(value, forKey: .type)
        }
    }
}

public struct Server: Codable, Hashable, Sendable, Identifiable {
    public let id: ServerID
    public var ownerID: UserID
    public var name: String
    public var description: String?
    public var channelIDs: [ChannelID]
    public var categories: [ServerCategory]?
    public var systemMessages: SystemMessageChannels?
    public var roles: [RoleID: Role]
    public var defaultPermissions: Permissions
    public var icon: File?
    public var banner: File?
    public var flags: UInt32
    public var nsfw: Bool
    public var analytics: Bool
    public var discoverable: Bool

    public init(
        id: ServerID,
        ownerID: UserID,
        name: String,
        description: String? = nil,
        channelIDs: [ChannelID] = [],
        categories: [ServerCategory]? = nil,
        systemMessages: SystemMessageChannels? = nil,
        roles: [RoleID: Role] = [:],
        defaultPermissions: Permissions = [],
        icon: File? = nil,
        banner: File? = nil,
        flags: UInt32 = 0,
        nsfw: Bool = false,
        analytics: Bool = false,
        discoverable: Bool = false
    ) {
        self.id = id
        self.ownerID = ownerID
        self.name = name
        self.description = description
        self.channelIDs = channelIDs
        self.categories = categories
        self.systemMessages = systemMessages
        self.roles = roles
        self.defaultPermissions = defaultPermissions
        self.icon = icon
        self.banner = banner
        self.flags = flags
        self.nsfw = nsfw
        self.analytics = analytics
        self.discoverable = discoverable
    }

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case ownerID = "owner"
        case name
        case description
        case channelIDs = "channels"
        case categories
        case systemMessages = "system_messages"
        case roles
        case defaultPermissions = "default_permissions"
        case icon
        case banner
        case flags
        case nsfw
        case analytics
        case discoverable
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ServerID.self, forKey: .id)
        ownerID = try container.decode(UserID.self, forKey: .ownerID)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        channelIDs = try container.decodeDefault([ChannelID].self, forKey: .channelIDs, default: [])
        categories = try container.decodeIfPresent([ServerCategory].self, forKey: .categories)
        systemMessages = try container.decodeIfPresent(SystemMessageChannels.self, forKey: .systemMessages)
        let rawRoles = try container.decodeDefault([String: Role].self, forKey: .roles, default: [:])
        roles = Dictionary(uniqueKeysWithValues: rawRoles.map { (RoleID(rawValue: $0.key), $0.value) })
        defaultPermissions = try container.decode(Permissions.self, forKey: .defaultPermissions)
        icon = try container.decodeIfPresent(File.self, forKey: .icon)
        banner = try container.decodeIfPresent(File.self, forKey: .banner)
        flags = try container.decodeDefault(UInt32.self, forKey: .flags, default: 0)
        nsfw = try container.decodeDefault(Bool.self, forKey: .nsfw, default: false)
        analytics = try container.decodeDefault(Bool.self, forKey: .analytics, default: false)
        discoverable = try container.decodeDefault(Bool.self, forKey: .discoverable, default: false)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(ownerID, forKey: .ownerID)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(channelIDs, forKey: .channelIDs)
        try container.encodeIfPresent(categories, forKey: .categories)
        try container.encodeIfPresent(systemMessages, forKey: .systemMessages)
        let rawRoles = Dictionary(uniqueKeysWithValues: roles.map { ($0.key.rawValue, $0.value) })
        try container.encode(rawRoles, forKey: .roles)
        try container.encode(defaultPermissions, forKey: .defaultPermissions)
        try container.encodeIfPresent(icon, forKey: .icon)
        try container.encodeIfPresent(banner, forKey: .banner)
        try container.encode(flags, forKey: .flags)
        try container.encode(nsfw, forKey: .nsfw)
        try container.encode(analytics, forKey: .analytics)
        try container.encode(discoverable, forKey: .discoverable)
    }
}

public struct ServerCategory: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var channels: [ChannelID]

    public init(id: String, title: String, channels: [ChannelID]) {
        self.id = id
        self.title = title
        self.channels = channels
    }
}

public struct SystemMessageChannels: Codable, Hashable, Sendable {
    public var userJoined: ChannelID?
    public var userLeft: ChannelID?
    public var userKicked: ChannelID?
    public var userBanned: ChannelID?

    public init(userJoined: ChannelID? = nil, userLeft: ChannelID? = nil, userKicked: ChannelID? = nil, userBanned: ChannelID? = nil) {
        self.userJoined = userJoined
        self.userLeft = userLeft
        self.userKicked = userKicked
        self.userBanned = userBanned
    }

    private enum CodingKeys: String, CodingKey {
        case userJoined = "user_joined"
        case userLeft = "user_left"
        case userKicked = "user_kicked"
        case userBanned = "user_banned"
    }
}

public struct Role: Codable, Hashable, Sendable, Identifiable {
    public let id: RoleID
    public var name: String
    public var permissions: PermissionOverride
    public var colour: String?
    public var hoist: Bool
    public var rank: Int64
    public var icon: File?

    public init(id: RoleID, name: String, permissions: PermissionOverride, colour: String? = nil, hoist: Bool = false, rank: Int64 = 0, icon: File? = nil) {
        self.id = id
        self.name = name
        self.permissions = permissions
        self.colour = colour
        self.hoist = hoist
        self.rank = rank
        self.icon = icon
    }

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name
        case permissions
        case colour
        case hoist
        case rank
        case icon
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(RoleID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        permissions = try container.decode(PermissionOverride.self, forKey: .permissions)
        colour = try container.decodeIfPresent(String.self, forKey: .colour)
        hoist = try container.decodeDefault(Bool.self, forKey: .hoist, default: false)
        rank = try container.decodeDefault(Int64.self, forKey: .rank, default: 0)
        icon = try container.decodeIfPresent(File.self, forKey: .icon)
    }
}

public struct Channel: Codable, Hashable, Sendable, Identifiable {
    public let id: ChannelID
    public var kind: ChannelKind
    public var userID: UserID?
    public var serverID: ServerID?
    public var name: String?
    public var ownerID: UserID?
    public var description: String?
    public var active: Bool?
    public var recipients: [UserID]
    public var icon: File?
    public var lastMessageID: MessageID?
    public var permissions: Permissions?
    public var defaultPermissions: PermissionOverride?
    public var rolePermissions: [RoleID: PermissionOverride]
    public var nsfw: Bool
    public var voice: VoiceInformation?
    public var slowmode: UInt64?

    public var displayName: String {
        name ?? {
            switch kind {
            case .savedMessages: "Saved Notes"
            case .directMessage: "Direct Message"
            case .group: "Group"
            case .textChannel: "Text Channel"
            case .voiceChannel: "Voice Channel"
            case let .unknown(value): value
            }
        }()
    }

    public init(
        id: ChannelID,
        kind: ChannelKind,
        userID: UserID? = nil,
        serverID: ServerID? = nil,
        name: String? = nil,
        ownerID: UserID? = nil,
        description: String? = nil,
        active: Bool? = nil,
        recipients: [UserID] = [],
        icon: File? = nil,
        lastMessageID: MessageID? = nil,
        permissions: Permissions? = nil,
        defaultPermissions: PermissionOverride? = nil,
        rolePermissions: [RoleID: PermissionOverride] = [:],
        nsfw: Bool = false,
        voice: VoiceInformation? = nil,
        slowmode: UInt64? = nil
    ) {
        self.id = id
        self.kind = kind
        self.userID = userID
        self.serverID = serverID
        self.name = name
        self.ownerID = ownerID
        self.description = description
        self.active = active
        self.recipients = recipients
        self.icon = icon
        self.lastMessageID = lastMessageID
        self.permissions = permissions
        self.defaultPermissions = defaultPermissions
        self.rolePermissions = rolePermissions
        self.nsfw = nsfw
        self.voice = voice
        self.slowmode = slowmode
    }

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case kind = "channel_type"
        case userID = "user"
        case serverID = "server"
        case name
        case ownerID = "owner"
        case description
        case active
        case recipients
        case icon
        case lastMessageID = "last_message_id"
        case permissions
        case defaultPermissions = "default_permissions"
        case rolePermissions = "role_permissions"
        case nsfw
        case voice
        case slowmode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ChannelID.self, forKey: .id)
        kind = try container.decode(ChannelKind.self, forKey: .kind)
        userID = try container.decodeIfPresent(UserID.self, forKey: .userID)
        serverID = try container.decodeIfPresent(ServerID.self, forKey: .serverID)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        ownerID = try container.decodeIfPresent(UserID.self, forKey: .ownerID)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        active = try container.decodeIfPresent(Bool.self, forKey: .active)
        recipients = try container.decodeDefault([UserID].self, forKey: .recipients, default: [])
        icon = try container.decodeIfPresent(File.self, forKey: .icon)
        lastMessageID = try container.decodeIfPresent(MessageID.self, forKey: .lastMessageID)
        permissions = try container.decodeIfPresent(Permissions.self, forKey: .permissions)
        defaultPermissions = try container.decodeIfPresent(PermissionOverride.self, forKey: .defaultPermissions)
        let rawRolePermissions = try container.decodeDefault([String: PermissionOverride].self, forKey: .rolePermissions, default: [:])
        rolePermissions = Dictionary(uniqueKeysWithValues: rawRolePermissions.map { (RoleID(rawValue: $0.key), $0.value) })
        nsfw = try container.decodeDefault(Bool.self, forKey: .nsfw, default: false)
        voice = try container.decodeIfPresent(VoiceInformation.self, forKey: .voice)
        slowmode = try container.decodeIfPresent(UInt64.self, forKey: .slowmode)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(userID, forKey: .userID)
        try container.encodeIfPresent(serverID, forKey: .serverID)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(ownerID, forKey: .ownerID)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(active, forKey: .active)
        try container.encode(recipients, forKey: .recipients)
        try container.encodeIfPresent(icon, forKey: .icon)
        try container.encodeIfPresent(lastMessageID, forKey: .lastMessageID)
        try container.encodeIfPresent(permissions, forKey: .permissions)
        try container.encodeIfPresent(defaultPermissions, forKey: .defaultPermissions)
        let rawRolePermissions = Dictionary(uniqueKeysWithValues: rolePermissions.map { ($0.key.rawValue, $0.value) })
        try container.encode(rawRolePermissions, forKey: .rolePermissions)
        try container.encode(nsfw, forKey: .nsfw)
        try container.encodeIfPresent(voice, forKey: .voice)
        try container.encodeIfPresent(slowmode, forKey: .slowmode)
    }
}

public enum ChannelKind: Codable, Hashable, Sendable {
    case savedMessages
    case directMessage
    case group
    case textChannel
    case voiceChannel
    case unknown(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        switch try container.decode(String.self) {
        case "SavedMessages": self = .savedMessages
        case "DirectMessage": self = .directMessage
        case "Group": self = .group
        case "TextChannel": self = .textChannel
        case "VoiceChannel": self = .voiceChannel
        case let value: self = .unknown(value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawAPIValue)
    }

    public var rawAPIValue: String {
        switch self {
        case .savedMessages: "SavedMessages"
        case .directMessage: "DirectMessage"
        case .group: "Group"
        case .textChannel: "TextChannel"
        case .voiceChannel: "VoiceChannel"
        case let .unknown(value): value
        }
    }
}

public struct VoiceInformation: Codable, Hashable, Sendable {
    public var maxUsers: Int?

    public init(maxUsers: Int? = nil) {
        self.maxUsers = maxUsers
    }

    private enum CodingKeys: String, CodingKey {
        case maxUsers = "max_users"
    }
}

public struct MemberCompositeKey: Codable, Hashable, Sendable {
    public var serverID: ServerID
    public var userID: UserID

    public init(serverID: ServerID, userID: UserID) {
        self.serverID = serverID
        self.userID = userID
    }

    private enum CodingKeys: String, CodingKey {
        case serverID = "server"
        case userID = "user"
    }
}

public struct ServerMember: Codable, Hashable, Sendable, Identifiable {
    public let id: MemberCompositeKey
    public var joinedAt: Date
    public var nickname: String?
    public var avatar: File?
    public var roles: [RoleID]
    public var timeout: Date?
    public var canPublish: Bool
    public var canReceive: Bool

    public init(id: MemberCompositeKey, joinedAt: Date, nickname: String? = nil, avatar: File? = nil, roles: [RoleID] = [], timeout: Date? = nil, canPublish: Bool = true, canReceive: Bool = true) {
        self.id = id
        self.joinedAt = joinedAt
        self.nickname = nickname
        self.avatar = avatar
        self.roles = roles
        self.timeout = timeout
        self.canPublish = canPublish
        self.canReceive = canReceive
    }

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case joinedAt = "joined_at"
        case nickname
        case avatar
        case roles
        case timeout
        case canPublish = "can_publish"
        case canReceive = "can_receive"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(MemberCompositeKey.self, forKey: .id)
        joinedAt = try container.decode(Date.self, forKey: .joinedAt)
        nickname = try container.decodeIfPresent(String.self, forKey: .nickname)
        avatar = try container.decodeIfPresent(File.self, forKey: .avatar)
        roles = try container.decodeDefault([RoleID].self, forKey: .roles, default: [])
        timeout = try container.decodeIfPresent(Date.self, forKey: .timeout)
        canPublish = try container.decodeDefault(Bool.self, forKey: .canPublish, default: true)
        canReceive = try container.decodeDefault(Bool.self, forKey: .canReceive, default: true)
    }
}

public typealias Member = ServerMember

public struct Message: Codable, Hashable, Sendable, Identifiable {
    public let id: MessageID
    public var nonce: String?
    public var channelID: ChannelID
    public var authorID: UserID
    public var user: User?
    public var member: ServerMember?
    public var webhook: MessageWebhook?
    public var content: String?
    public var system: SystemMessage?
    public var attachments: [File]?
    public var editedAt: Date?
    public var embeds: [Embed]?
    public var mentions: [UserID]?
    public var roleMentions: [RoleID]?
    public var replies: [MessageID]?
    public var reactions: [String: Set<UserID>]
    public var interactions: MessageInteractions
    public var masquerade: Masquerade?
    public var pinned: Bool?
    public var flags: MessageFlags

    public var createdAt: Date? { Self.dateFromULID(id.rawValue) }
    public var isEdited: Bool { editedAt != nil }
    public var isPinned: Bool { pinned == true }
    public var isSuppressed: Bool { flags.contains(.suppressNotifications) }
    public var mentionsEveryone: Bool { flags.contains(.mentionsEveryone) }

    public init(
        id: MessageID,
        channelID: ChannelID,
        authorID: UserID,
        content: String? = nil,
        nonce: String? = nil,
        user: User? = nil,
        member: ServerMember? = nil,
        webhook: MessageWebhook? = nil,
        system: SystemMessage? = nil,
        attachments: [File]? = nil,
        editedAt: Date? = nil,
        embeds: [Embed]? = nil,
        mentions: [UserID]? = nil,
        roleMentions: [RoleID]? = nil,
        replies: [MessageID]? = nil,
        reactions: [String: Set<UserID>] = [:],
        interactions: MessageInteractions = MessageInteractions(),
        masquerade: Masquerade? = nil,
        pinned: Bool? = nil,
        flags: MessageFlags = []
    ) {
        self.id = id
        self.nonce = nonce
        self.channelID = channelID
        self.authorID = authorID
        self.user = user
        self.member = member
        self.webhook = webhook
        self.content = content
        self.system = system
        self.attachments = attachments
        self.editedAt = editedAt
        self.embeds = embeds
        self.mentions = mentions
        self.roleMentions = roleMentions
        self.replies = replies
        self.reactions = reactions
        self.interactions = interactions
        self.masquerade = masquerade
        self.pinned = pinned
        self.flags = flags
    }

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case nonce
        case channelID = "channel"
        case authorID = "author"
        case user
        case member
        case webhook
        case content
        case system
        case attachments
        case editedAt = "edited"
        case embeds
        case mentions
        case roleMentions = "role_mentions"
        case replies
        case reactions
        case interactions
        case masquerade
        case pinned
        case flags
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(MessageID.self, forKey: .id)
        nonce = try container.decodeIfPresent(String.self, forKey: .nonce)
        channelID = try container.decode(ChannelID.self, forKey: .channelID)
        authorID = try container.decode(UserID.self, forKey: .authorID)
        user = try container.decodeIfPresent(User.self, forKey: .user)
        member = try container.decodeIfPresent(ServerMember.self, forKey: .member)
        webhook = try container.decodeIfPresent(MessageWebhook.self, forKey: .webhook)
        content = try container.decodeIfPresent(String.self, forKey: .content)
        system = try container.decodeIfPresent(SystemMessage.self, forKey: .system)
        attachments = try container.decodeIfPresent([File].self, forKey: .attachments)
        editedAt = try container.decodeIfPresent(Date.self, forKey: .editedAt)
        embeds = try container.decodeIfPresent([Embed].self, forKey: .embeds)
        mentions = try container.decodeIfPresent([UserID].self, forKey: .mentions)
        roleMentions = try container.decodeIfPresent([RoleID].self, forKey: .roleMentions)
        replies = try container.decodeIfPresent([MessageID].self, forKey: .replies)
        reactions = try container.decodeDefault([String: Set<UserID>].self, forKey: .reactions, default: [:])
        interactions = try container.decodeDefault(MessageInteractions.self, forKey: .interactions, default: MessageInteractions())
        masquerade = try container.decodeIfPresent(Masquerade.self, forKey: .masquerade)
        pinned = try container.decodeIfPresent(Bool.self, forKey: .pinned)
        flags = try container.decodeDefault(MessageFlags.self, forKey: .flags, default: [])
    }

    public static func dateFromULID(_ value: String) -> Date? {
        guard value.count == 26 else { return nil }
        let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
        let lookup = Dictionary(uniqueKeysWithValues: alphabet.enumerated().map { ($0.element, UInt64($0.offset)) })
        var timestamp: UInt64 = 0
        for scalar in value.uppercased().prefix(10) {
            guard let digit = lookup[scalar] else { return nil }
            timestamp = timestamp * 32 + digit
        }
        return Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
    }
}

public struct MessageFlags: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(UInt32.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static let suppressNotifications = MessageFlags(rawValue: 1)
    public static let mentionsEveryone = MessageFlags(rawValue: 2)
    public static let mentionsOnline = MessageFlags(rawValue: 3)
}

public struct MessageWebhook: Codable, Hashable, Sendable {
    public var name: String
    public var avatar: String?

    public init(name: String, avatar: String? = nil) {
        self.name = name
        self.avatar = avatar
    }
}

public struct SystemMessage: Codable, Hashable, Sendable {
    public var kind: SystemMessageKind
    public var content: String?
    public var id: String?
    public var by: UserID?
    public var name: String?
    public var from: UserID?
    public var to: UserID?
    public var finishedAt: Date?

    public init(kind: SystemMessageKind, content: String? = nil, id: String? = nil, by: UserID? = nil, name: String? = nil, from: UserID? = nil, to: UserID? = nil, finishedAt: Date? = nil) {
        self.kind = kind
        self.content = content
        self.id = id
        self.by = by
        self.name = name
        self.from = from
        self.to = to
        self.finishedAt = finishedAt
    }

    private enum CodingKeys: String, CodingKey {
        case kind = "type"
        case content
        case id
        case by
        case name
        case from
        case to
        case finishedAt = "finished_at"
    }
}

public enum SystemMessageKind: Codable, Hashable, Sendable {
    case text
    case userAdded
    case userRemove
    case userJoined
    case userLeft
    case userKicked
    case userBanned
    case channelRenamed
    case channelDescriptionChanged
    case channelIconChanged
    case channelOwnershipChanged
    case messagePinned
    case messageUnpinned
    case callStarted
    case unknown(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        switch try container.decode(String.self) {
        case "text": self = .text
        case "user_added": self = .userAdded
        case "user_remove": self = .userRemove
        case "user_joined": self = .userJoined
        case "user_left": self = .userLeft
        case "user_kicked": self = .userKicked
        case "user_banned": self = .userBanned
        case "channel_renamed": self = .channelRenamed
        case "channel_description_changed": self = .channelDescriptionChanged
        case "channel_icon_changed": self = .channelIconChanged
        case "channel_ownership_changed": self = .channelOwnershipChanged
        case "message_pinned": self = .messagePinned
        case "message_unpinned": self = .messageUnpinned
        case "call_started": self = .callStarted
        case let value: self = .unknown(value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawAPIValue)
    }

    public var rawAPIValue: String {
        switch self {
        case .text: "text"
        case .userAdded: "user_added"
        case .userRemove: "user_remove"
        case .userJoined: "user_joined"
        case .userLeft: "user_left"
        case .userKicked: "user_kicked"
        case .userBanned: "user_banned"
        case .channelRenamed: "channel_renamed"
        case .channelDescriptionChanged: "channel_description_changed"
        case .channelIconChanged: "channel_icon_changed"
        case .channelOwnershipChanged: "channel_ownership_changed"
        case .messagePinned: "message_pinned"
        case .messageUnpinned: "message_unpinned"
        case .callStarted: "call_started"
        case let .unknown(value): value
        }
    }
}

public struct MessageInteractions: Codable, Hashable, Sendable {
    public var reactions: Set<String>?
    public var restrictReactions: Bool

    public init(reactions: Set<String>? = nil, restrictReactions: Bool = false) {
        self.reactions = reactions
        self.restrictReactions = restrictReactions
    }

    private enum CodingKeys: String, CodingKey {
        case reactions
        case restrictReactions = "restrict_reactions"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reactions = try container.decodeIfPresent(Set<String>.self, forKey: .reactions)
        restrictReactions = try container.decodeDefault(Bool.self, forKey: .restrictReactions, default: false)
    }
}

public struct Masquerade: Codable, Hashable, Sendable {
    public var name: String?
    public var avatar: String?
    public var colour: String?

    public init(name: String? = nil, avatar: String? = nil, colour: String? = nil) {
        self.name = name
        self.avatar = avatar
        self.colour = colour
    }
}

public struct MessageReply: Codable, Hashable, Sendable {
    public var id: MessageID
    public var mention: Bool
    public var failIfNotExists: Bool?

    public init(id: MessageID, mention: Bool, failIfNotExists: Bool? = nil) {
        self.id = id
        self.mention = mention
        self.failIfNotExists = failIfNotExists
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case mention
        case failIfNotExists = "fail_if_not_exists"
    }
}

public struct SendableEmbed: Codable, Hashable, Sendable {
    public var iconURL: String?
    public var url: String?
    public var title: String?
    public var description: String?
    public var media: FileID?
    public var colour: String?

    public init(iconURL: String? = nil, url: String? = nil, title: String? = nil, description: String? = nil, media: FileID? = nil, colour: String? = nil) {
        self.iconURL = iconURL
        self.url = url
        self.title = title
        self.description = description
        self.media = media
        self.colour = colour
    }

    private enum CodingKeys: String, CodingKey {
        case iconURL = "icon_url"
        case url
        case title
        case description
        case media
        case colour
    }
}

public struct Embed: Codable, Hashable, Sendable {
    public var kind: EmbedKind
    public var url: String?
    public var originalURL: String?
    public var title: String?
    public var description: String?
    public var siteName: String?
    public var iconURL: String?
    public var colour: String?
    public var width: Int?
    public var height: Int?
    public var size: ImageSize?
    public var image: EmbedImage?
    public var video: EmbedVideo?
    public var media: File?
    public var special: JSONValue?

    public init(kind: EmbedKind, url: String? = nil, originalURL: String? = nil, title: String? = nil, description: String? = nil, siteName: String? = nil, iconURL: String? = nil, colour: String? = nil, width: Int? = nil, height: Int? = nil, size: ImageSize? = nil, image: EmbedImage? = nil, video: EmbedVideo? = nil, media: File? = nil, special: JSONValue? = nil) {
        self.kind = kind
        self.url = url
        self.originalURL = originalURL
        self.title = title
        self.description = description
        self.siteName = siteName
        self.iconURL = iconURL
        self.colour = colour
        self.width = width
        self.height = height
        self.size = size
        self.image = image
        self.video = video
        self.media = media
        self.special = special
    }

    private enum CodingKeys: String, CodingKey {
        case kind = "type"
        case url
        case originalURL = "original_url"
        case title
        case description
        case siteName = "site_name"
        case iconURL = "icon_url"
        case colour
        case width
        case height
        case size
        case image
        case video
        case media
        case special
    }
}

public enum EmbedKind: Codable, Hashable, Sendable {
    case website
    case image
    case video
    case text
    case none
    case unknown(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        switch try container.decode(String.self) {
        case "Website": self = .website
        case "Image": self = .image
        case "Video": self = .video
        case "Text": self = .text
        case "None": self = .none
        case let value: self = .unknown(value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawAPIValue)
    }

    public var rawAPIValue: String {
        switch self {
        case .website: "Website"
        case .image: "Image"
        case .video: "Video"
        case .text: "Text"
        case .none: "None"
        case let .unknown(value): value
        }
    }
}

public struct EmbedImage: Codable, Hashable, Sendable {
    public var url: String
    public var width: Int
    public var height: Int
    public var size: ImageSize?

    public init(url: String, width: Int, height: Int, size: ImageSize? = nil) {
        self.url = url
        self.width = width
        self.height = height
        self.size = size
    }
}

public struct EmbedVideo: Codable, Hashable, Sendable {
    public var url: String
    public var width: Int
    public var height: Int

    public init(url: String, width: Int, height: Int) {
        self.url = url
        self.width = width
        self.height = height
    }
}

public enum ImageSize: Codable, Hashable, Sendable {
    case large
    case preview
    case unknown(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        switch try container.decode(String.self) {
        case "Large": self = .large
        case "Preview": self = .preview
        case let value: self = .unknown(value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawAPIValue)
    }

    public var rawAPIValue: String {
        switch self {
        case .large: "Large"
        case .preview: "Preview"
        case let .unknown(value): value
        }
    }
}

public struct Emoji: Codable, Hashable, Sendable, Identifiable {
    public let id: EmojiID
    public var parent: EmojiParent
    public var creatorID: UserID
    public var name: String
    public var animated: Bool
    public var nsfw: Bool

    public init(id: EmojiID, parent: EmojiParent, creatorID: UserID, name: String, animated: Bool = false, nsfw: Bool = false) {
        self.id = id
        self.parent = parent
        self.creatorID = creatorID
        self.name = name
        self.animated = animated
        self.nsfw = nsfw
    }

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case parent
        case creatorID = "creator_id"
        case name
        case animated
        case nsfw
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(EmojiID.self, forKey: .id)
        parent = try container.decode(EmojiParent.self, forKey: .parent)
        creatorID = try container.decode(UserID.self, forKey: .creatorID)
        name = try container.decode(String.self, forKey: .name)
        animated = try container.decodeDefault(Bool.self, forKey: .animated, default: false)
        nsfw = try container.decodeDefault(Bool.self, forKey: .nsfw, default: false)
    }
}

public enum EmojiParent: Codable, Hashable, Sendable {
    case server(ServerID)
    case detached
    case unknown(String, id: String?)

    private enum CodingKeys: String, CodingKey {
        case type
        case id
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "Server":
            self = .server(try container.decode(ServerID.self, forKey: .id))
        case "Detached":
            self = .detached
        case let value:
            self = .unknown(value, id: try container.decodeIfPresent(String.self, forKey: .id))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .server(id):
            try container.encode("Server", forKey: .type)
            try container.encode(id, forKey: .id)
        case .detached:
            try container.encode("Detached", forKey: .type)
        case let .unknown(type, id):
            try container.encode(type, forKey: .type)
            try container.encodeIfPresent(id, forKey: .id)
        }
    }
}

public struct Invite: Codable, Hashable, Sendable, Identifiable {
    public let id: InviteID
    public var kind: InviteKind
    public var serverID: ServerID?
    public var creatorID: UserID
    public var channelID: ChannelID

    public init(id: InviteID, kind: InviteKind, serverID: ServerID? = nil, creatorID: UserID, channelID: ChannelID) {
        self.id = id
        self.kind = kind
        self.serverID = serverID
        self.creatorID = creatorID
        self.channelID = channelID
    }

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case kind = "type"
        case serverID = "server"
        case creatorID = "creator"
        case channelID = "channel"
    }
}

public enum InviteKind: Codable, Hashable, Sendable {
    case server
    case group
    case unknown(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        switch try container.decode(String.self) {
        case "Server": self = .server
        case "Group": self = .group
        case let value: self = .unknown(value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawAPIValue)
    }

    public var rawAPIValue: String {
        switch self {
        case .server: "Server"
        case .group: "Group"
        case let .unknown(value): value
        }
    }
}

public struct ChannelUnread: Codable, Hashable, Sendable, Identifiable {
    public let id: ChannelCompositeKey
    public var lastMessageID: MessageID?
    public var mentions: [MessageID]

    public init(id: ChannelCompositeKey, lastMessageID: MessageID? = nil, mentions: [MessageID] = []) {
        self.id = id
        self.lastMessageID = lastMessageID
        self.mentions = mentions
    }

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case lastMessageID = "last_id"
        case mentions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ChannelCompositeKey.self, forKey: .id)
        lastMessageID = try container.decodeIfPresent(MessageID.self, forKey: .lastMessageID)
        mentions = try container.decodeDefault([MessageID].self, forKey: .mentions, default: [])
    }
}

public struct ChannelCompositeKey: Codable, Hashable, Sendable {
    public var channelID: ChannelID
    public var userID: UserID

    public init(channelID: ChannelID, userID: UserID) {
        self.channelID = channelID
        self.userID = userID
    }

    private enum CodingKeys: String, CodingKey {
        case channelID = "channel"
        case userID = "user"
    }
}

public struct UserSettings: Codable, Hashable, Sendable {
    public var values: [String: JSONValue]

    public init(values: [String: JSONValue] = [:]) {
        self.values = values
    }

    public init(from decoder: Decoder) throws {
        values = try [String: JSONValue](from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try values.encode(to: encoder)
    }
}

public enum BulkMessageResponse: Codable, Hashable, Sendable {
    case messages([Message])
    case messagesAndUsers(messages: [Message], users: [User], members: [ServerMember]?)

    public var messages: [Message] {
        switch self {
        case let .messages(messages):
            messages
        case let .messagesAndUsers(messages, _, _):
            messages
        }
    }

    private enum CodingKeys: String, CodingKey {
        case messages
        case users
        case members
    }

    public init(from decoder: Decoder) throws {
        if let messages = try? [Message](from: decoder) {
            self = .messages(messages)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        self = .messagesAndUsers(
            messages: try container.decode([Message].self, forKey: .messages),
            users: try container.decode([User].self, forKey: .users),
            members: try container.decodeIfPresent([ServerMember].self, forKey: .members)
        )
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case let .messages(messages):
            try messages.encode(to: encoder)
        case let .messagesAndUsers(messages, users, members):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(messages, forKey: .messages)
            try container.encode(users, forKey: .users)
            try container.encodeIfPresent(members, forKey: .members)
        }
    }
}

public enum MessageSort: String, Codable, Hashable, Sendable, CaseIterable {
    case relevance = "Relevance"
    case latest = "Latest"
    case oldest = "Oldest"
}

public struct MessageFetchOptions: Codable, Hashable, Sendable {
    public var before: MessageID?
    public var after: MessageID?
    public var nearby: MessageID?
    public var sort: MessageSort?
    public var limit: Int?
    public var includeUsers: Bool?

    public init(
        before: MessageID? = nil,
        after: MessageID? = nil,
        nearby: MessageID? = nil,
        sort: MessageSort? = nil,
        limit: Int? = nil,
        includeUsers: Bool? = nil
    ) {
        self.before = before
        self.after = after
        self.nearby = nearby
        self.sort = sort
        self.limit = limit
        self.includeUsers = includeUsers
    }

    private enum CodingKeys: String, CodingKey {
        case before
        case after
        case nearby
        case sort
        case limit
        case includeUsers = "include_users"
    }
}

public struct ChannelMessageSearchRequest: Codable, Hashable, Sendable {
    public var query: String?
    public var pinned: Bool?
    public var before: MessageID?
    public var after: MessageID?
    public var limit: Int?
    public var sort: MessageSort?
    public var includeUsers: Bool?

    public init(
        query: String? = nil,
        pinned: Bool? = nil,
        before: MessageID? = nil,
        after: MessageID? = nil,
        limit: Int? = nil,
        sort: MessageSort? = nil,
        includeUsers: Bool? = nil
    ) {
        self.query = query
        self.pinned = pinned
        self.before = before
        self.after = after
        self.limit = limit
        self.sort = sort
        self.includeUsers = includeUsers
    }

    private enum CodingKeys: String, CodingKey {
        case query
        case pinned
        case before
        case after
        case limit
        case sort
        case includeUsers = "include_users"
    }
}
