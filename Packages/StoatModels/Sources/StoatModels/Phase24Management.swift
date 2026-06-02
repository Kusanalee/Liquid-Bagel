import Foundation

public enum ServerFetchResponse: Codable, Hashable, Sendable {
    case server(Server)
    case serverWithChannels(server: Server, channels: [Channel])

    private enum CodingKeys: String, CodingKey {
        case server
        case channels
    }

    public init(server: Server, channels: [Channel]? = nil) {
        if let channels {
            self = .serverWithChannels(server: server, channels: channels)
        } else {
            self = .server(server)
        }
    }

    public init(from decoder: Decoder) throws {
        if let keyed = try? decoder.container(keyedBy: CodingKeys.self),
           keyed.contains(.server) {
            let server = try keyed.decode(Server.self, forKey: .server)
            let channels = try keyed.decodeDefault([Channel].self, forKey: .channels, default: [])
            self = .serverWithChannels(server: server, channels: channels)
            return
        }
        self = .server(try Server(from: decoder))
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case let .server(server):
            try server.encode(to: encoder)
        case let .serverWithChannels(server, channels):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(server, forKey: .server)
            try container.encode(channels, forKey: .channels)
        }
    }

    public var server: Server {
        switch self {
        case let .server(server), let .serverWithChannels(server, _):
            server
        }
    }

    public var channels: [Channel] {
        switch self {
        case .server:
            []
        case let .serverWithChannels(_, channels):
            channels
        }
    }
}

public struct ChannelCreateDraft: Codable, Hashable, Sendable {
    public var name: String
    public var type: ChannelKind
    public var description: String?
    public var nsfw: Bool?

    public init(name: String, type: ChannelKind = .textChannel, description: String? = nil, nsfw: Bool? = nil) {
        self.name = name
        self.type = type
        self.description = description
        self.nsfw = nsfw
    }

    public var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var validatedForCreate: ChannelCreateDraft? {
        let trimmed = trimmedName
        guard !trimmed.isEmpty, trimmed.count <= 32 else { return nil }
        let trimmedDescription = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ChannelCreateDraft(
            name: trimmed,
            type: type,
            description: trimmedDescription?.isEmpty == true ? nil : trimmedDescription,
            nsfw: nsfw
        )
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case type
        case description
        case nsfw
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(serverChannelTypeValue, forKey: .type)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(nsfw, forKey: .nsfw)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        let rawType = try container.decodeDefault(String.self, forKey: .type, default: "Text")
        type = rawType == "Voice" ? .voiceChannel : .textChannel
        description = try container.decodeIfPresent(String.self, forKey: .description)
        nsfw = try container.decodeIfPresent(Bool.self, forKey: .nsfw)
    }

    private var serverChannelTypeValue: String {
        switch type {
        case .voiceChannel:
            "Voice"
        default:
            "Text"
        }
    }
}

public struct ChannelEditDraft: Codable, Hashable, Sendable {
    public var name: String?
    public var description: String?
    public var nsfw: Bool?
    public var remove: [ChannelEditRemovedField]

    public init(name: String? = nil, description: String? = nil, nsfw: Bool? = nil, remove: [ChannelEditRemovedField] = []) {
        self.name = name
        self.description = description
        self.nsfw = nsfw
        self.remove = remove
    }

    public func validatedForEdit(original: Channel) -> ChannelEditDraft? {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedName, trimmedName.isEmpty || trimmedName.count > 32 {
            return nil
        }
        let trimmedDescription = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedDescription, trimmedDescription.count > 1024 {
            return nil
        }
        let normalizedDescription = trimmedDescription?.isEmpty == true ? nil : trimmedDescription
        let normalizedRemove = normalizedDescription == nil && description != nil ? Array(Set(remove + [.description])) : remove
        let draft = ChannelEditDraft(
            name: trimmedName == original.name ? nil : trimmedName,
            description: normalizedDescription == original.description ? nil : normalizedDescription,
            nsfw: nsfw == original.nsfw ? nil : nsfw,
            remove: normalizedRemove
        )
        return draft.hasChanges ? draft : nil
    }

    public var hasChanges: Bool {
        name != nil || description != nil || nsfw != nil || !remove.isEmpty
    }
}

public enum ChannelEditRemovedField: String, Codable, Hashable, Sendable {
    case description = "Description"
    case icon = "Icon"
    case voice = "Voice"
}

public struct ServerEditDraft: Codable, Hashable, Sendable {
    public var name: String?
    public var description: String?
    public var icon: FileID?
    public var banner: FileID?
    public var categories: [ServerCategory]?
    public var remove: [ServerEditRemovedField]

    public init(
        name: String? = nil,
        description: String? = nil,
        icon: FileID? = nil,
        banner: FileID? = nil,
        categories: [ServerCategory]? = nil,
        remove: [ServerEditRemovedField] = []
    ) {
        self.name = name
        self.description = description
        self.icon = icon
        self.banner = banner
        self.categories = categories
        self.remove = remove
    }

    public func validatedForEdit(original: Server) -> ServerEditDraft? {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedName, trimmedName.isEmpty || trimmedName.count > 32 {
            return nil
        }
        let trimmedDescription = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedDescription, trimmedDescription.count > 1024 {
            return nil
        }
        let normalizedDescription = trimmedDescription?.isEmpty == true ? nil : trimmedDescription
        let normalizedRemove = normalizedDescription == nil && description != nil ? Array(Set(remove + [.description])) : remove
        let draft = ServerEditDraft(
            name: trimmedName == original.name ? nil : trimmedName,
            description: normalizedDescription == original.description ? nil : normalizedDescription,
            icon: icon,
            banner: banner,
            categories: categories == original.categories ? nil : categories,
            remove: normalizedRemove
        )
        return draft.hasChanges ? draft : nil
    }

    public var hasChanges: Bool {
        name != nil || description != nil || icon != nil || banner != nil || categories != nil || !remove.isEmpty
    }
}

public enum ServerEditRemovedField: String, Codable, Hashable, Sendable {
    case description = "Description"
    case icon = "Icon"
    case banner = "Banner"
}

public struct RoleCreateDraft: Codable, Hashable, Sendable {
    public var name: String

    public init(name: String) {
        self.name = name
    }

    public var validatedForCreate: RoleCreateDraft? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 32 else { return nil }
        return RoleCreateDraft(name: trimmed)
    }
}

public struct RoleCreateResponse: Codable, Hashable, Sendable {
    public var id: RoleID
    public var role: Role

    public init(id: RoleID, role: Role) {
        self.id = id
        self.role = role
    }
}

public struct RoleEditDraft: Codable, Hashable, Sendable {
    public var name: String?
    public var colour: String?
    public var hoist: Bool?
    public var remove: [RoleEditRemovedField]

    public init(name: String? = nil, colour: String? = nil, hoist: Bool? = nil, remove: [RoleEditRemovedField] = []) {
        self.name = name
        self.colour = colour
        self.hoist = hoist
        self.remove = remove
    }

    public func validatedForEdit(original: Role) -> RoleEditDraft? {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedName, trimmedName.isEmpty || trimmedName.count > 32 {
            return nil
        }
        let trimmedColour = colour?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedColour, trimmedColour.count > 128 {
            return nil
        }
        let normalizedColour = trimmedColour?.isEmpty == true ? nil : trimmedColour
        let normalizedRemove = normalizedColour == nil && colour != nil ? Array(Set(remove + [.colour])) : remove
        let draft = RoleEditDraft(
            name: trimmedName == original.name ? nil : trimmedName,
            colour: normalizedColour == original.colour ? nil : normalizedColour,
            hoist: hoist == original.hoist ? nil : hoist,
            remove: normalizedRemove
        )
        return draft.hasChanges ? draft : nil
    }

    public var hasChanges: Bool {
        name != nil || colour != nil || hoist != nil || !remove.isEmpty
    }
}

public enum RoleEditRemovedField: String, Codable, Hashable, Sendable {
    case colour = "Colour"
    case icon = "Icon"
}

public struct MemberEditDraft: Codable, Hashable, Sendable {
    public var nickname: String?
    public var avatar: FileID?
    public var roles: [RoleID]?
    public var timeout: Date?
    public var remove: [MemberEditRemovedField]

    public init(
        nickname: String? = nil,
        avatar: FileID? = nil,
        roles: [RoleID]? = nil,
        timeout: Date? = nil,
        remove: [MemberEditRemovedField] = []
    ) {
        self.nickname = nickname
        self.avatar = avatar
        self.roles = roles
        self.timeout = timeout
        self.remove = remove
    }

    public var hasChanges: Bool {
        nickname != nil || avatar != nil || roles != nil || timeout != nil || !remove.isEmpty
    }
}

public enum MemberEditRemovedField: String, Codable, Hashable, Sendable {
    case nickname = "Nickname"
    case avatar = "Avatar"
    case roles = "Roles"
    case timeout = "Timeout"
    case canReceive = "CanReceive"
    case canPublish = "CanPublish"
    case joinedAt = "JoinedAt"
    case voiceChannel = "VoiceChannel"
}

public struct BanCreateDraft: Codable, Hashable, Sendable {
    public var reason: String?
    public var deleteMessageSeconds: Int64?

    public init(reason: String? = nil, deleteMessageSeconds: Int64? = nil) {
        self.reason = reason
        self.deleteMessageSeconds = deleteMessageSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case reason
        case deleteMessageSeconds = "delete_message_seconds"
    }
}

public struct ServerBan: Codable, Hashable, Sendable, Identifiable {
    public var id: MemberCompositeKey
    public var reason: String?

    public init(id: MemberCompositeKey, reason: String? = nil) {
        self.id = id
        self.reason = reason
    }

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case reason
    }
}

public struct BannedUser: Codable, Hashable, Sendable, Identifiable {
    public var id: UserID
    public var username: String
    public var discriminator: String?
    public var avatar: File?

    public init(id: UserID, username: String, discriminator: String? = nil, avatar: File? = nil) {
        self.id = id
        self.username = username
        self.discriminator = discriminator
        self.avatar = avatar
    }

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case username
        case discriminator
        case avatar
    }
}

public struct BanListResult: Codable, Hashable, Sendable {
    public var users: [BannedUser]
    public var bans: [ServerBan]

    public init(users: [BannedUser], bans: [ServerBan]) {
        self.users = users
        self.bans = bans
    }
}

public struct PermissionWriteOverride: Codable, Hashable, Sendable {
    public var allow: Permissions
    public var deny: Permissions

    public init(allow: Permissions = [], deny: Permissions = []) {
        self.allow = allow
        self.deny = deny
    }

    public init(_ override: PermissionOverride) {
        self.allow = override.allow
        self.deny = override.deny
    }
}

public struct ServerRolePermissionDraft: Codable, Hashable, Sendable {
    public var permissions: PermissionWriteOverride

    public init(permissions: PermissionWriteOverride) {
        self.permissions = permissions
    }
}

public struct ServerDefaultPermissionDraft: Codable, Hashable, Sendable {
    public var permissions: Permissions

    public init(permissions: Permissions) {
        self.permissions = permissions
    }
}

public enum ChannelDefaultPermissionDraft: Codable, Hashable, Sendable {
    case value(Permissions)
    case override(PermissionWriteOverride)

    private enum CodingKeys: String, CodingKey {
        case permissions
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .value(permissions):
            try container.encode(permissions, forKey: .permissions)
        case let .override(override):
            try container.encode(override, forKey: .permissions)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let permissions = try? container.decode(Permissions.self, forKey: .permissions) {
            self = .value(permissions)
        } else {
            self = .override(try container.decode(PermissionWriteOverride.self, forKey: .permissions))
        }
    }
}
