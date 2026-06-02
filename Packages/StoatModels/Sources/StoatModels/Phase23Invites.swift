import Foundation

public struct InviteCode: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }
}

public enum InviteInputParseResult: Hashable, Sendable {
    case code(InviteCode)
    case invalid(String)
}

public enum InviteCodeParser {
    public static let maximumLength = 128

    public static func parse(_ input: String) -> InviteInputParseResult {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .invalid("Enter an invite code or link.")
        }
        guard trimmed.count <= 512 else {
            return .invalid("Invite input is too long.")
        }

        if let code = codeFromURLLikeInput(trimmed) ?? codeFromRawInput(trimmed) {
            return .code(code)
        }
        return .invalid("Invite code or link is not supported.")
    }

    public static func sanitizeDisplay(_ code: InviteCode?) -> String {
        guard let code else { return "" }
        return String(code.rawValue.prefix(maximumLength))
    }

    public static func inviteURLString(code: InviteCode, isProductionStoat: Bool = true, appBaseURL: URL? = nil) -> String {
        if isProductionStoat {
            return "https://stt.gg/\(code.rawValue)"
        }
        if let appBaseURL {
            return appBaseURL.appending(path: "invite").appending(path: code.rawValue).absoluteString
        }
        return "/invite/\(code.rawValue)"
    }

    private static func codeFromURLLikeInput(_ input: String) -> InviteCode? {
        let stripped = stripSurroundingPunctuation(input)
        if stripped.hasPrefix("/invite/") {
            return codeFromPathComponents(Array(stripped.split(separator: "/").map(String.init)), inviteIndex: 0)
        }

        guard let url = URL(string: stripped),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http"
        else { return nil }

        let host = (components.host ?? "").lowercased()
        let pathComponents = components.path.split(separator: "/").map(String.init)
        if host == "stt.gg" || host == "rvlt.gg" {
            return codeFromPathComponents(pathComponents, inviteIndex: nil)
        }
        if host == "stoat.chat" || host.hasSuffix(".stoat.chat") {
            return codeFromPathComponents(pathComponents, inviteIndex: pathComponents.firstIndex(of: "invite"))
        }
        if let inviteIndex = pathComponents.firstIndex(of: "invite") {
            return codeFromPathComponents(pathComponents, inviteIndex: inviteIndex)
        }
        return nil
    }

    private static func codeFromPathComponents(_ components: [String], inviteIndex: Int?) -> InviteCode? {
        let raw: String?
        if let inviteIndex {
            let next = inviteIndex + 1
            raw = components.indices.contains(next) ? components[next] : nil
        } else {
            raw = components.first
        }
        guard let raw else { return nil }
        return codeFromRawInput(raw)
    }

    private static func codeFromRawInput(_ input: String) -> InviteCode? {
        let candidate = stripSurroundingPunctuation(input)
        guard !candidate.isEmpty,
              candidate.count <= maximumLength,
              candidate.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              candidate.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil
        else { return nil }
        return InviteCode(rawValue: candidate)
    }

    private static func stripSurroundingPunctuation(_ input: String) -> String {
        input.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".,;:!?()[]{}<>\"'`")))
    }
}

public enum InvitePreviewKind: String, Codable, Hashable, Sendable {
    case server = "Server"
    case group = "Group"
    case unknown
}

public struct InvitePreview: Codable, Hashable, Sendable {
    public var code: InviteCode
    public var kind: InvitePreviewKind
    public var serverID: ServerID?
    public var serverName: String?
    public var serverIcon: File?
    public var serverBanner: File?
    public var serverFlags: UInt32?
    public var channelID: ChannelID
    public var channelName: String
    public var channelDescription: String?
    public var inviterName: String
    public var inviterAvatar: File?
    public var memberCount: Int?
    public var isAlreadyJoined: Bool

    public init(
        code: InviteCode,
        kind: InvitePreviewKind,
        serverID: ServerID? = nil,
        serverName: String? = nil,
        serverIcon: File? = nil,
        serverBanner: File? = nil,
        serverFlags: UInt32? = nil,
        channelID: ChannelID,
        channelName: String,
        channelDescription: String? = nil,
        inviterName: String,
        inviterAvatar: File? = nil,
        memberCount: Int? = nil,
        isAlreadyJoined: Bool = false
    ) {
        self.code = code
        self.kind = kind
        self.serverID = serverID
        self.serverName = serverName
        self.serverIcon = serverIcon
        self.serverBanner = serverBanner
        self.serverFlags = serverFlags
        self.channelID = channelID
        self.channelName = channelName
        self.channelDescription = channelDescription
        self.inviterName = inviterName
        self.inviterAvatar = inviterAvatar
        self.memberCount = memberCount
        self.isAlreadyJoined = isAlreadyJoined
    }

    private enum CodingKeys: String, CodingKey {
        case kind = "type"
        case code
        case serverID = "server_id"
        case serverName = "server_name"
        case serverIcon = "server_icon"
        case serverBanner = "server_banner"
        case serverFlags = "server_flags"
        case channelID = "channel_id"
        case channelName = "channel_name"
        case channelDescription = "channel_description"
        case inviterName = "user_name"
        case inviterAvatar = "user_avatar"
        case memberCount = "member_count"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawKind = try container.decode(String.self, forKey: .kind)
        kind = InvitePreviewKind(rawValue: rawKind) ?? .unknown
        code = InviteCode(rawValue: try container.decode(String.self, forKey: .code))
        serverID = try container.decodeIfPresent(ServerID.self, forKey: .serverID)
        serverName = try container.decodeIfPresent(String.self, forKey: .serverName)
        serverIcon = try container.decodeIfPresent(File.self, forKey: .serverIcon)
        serverBanner = try container.decodeIfPresent(File.self, forKey: .serverBanner)
        serverFlags = try container.decodeIfPresent(UInt32.self, forKey: .serverFlags)
        channelID = try container.decode(ChannelID.self, forKey: .channelID)
        channelName = try container.decode(String.self, forKey: .channelName)
        channelDescription = try container.decodeIfPresent(String.self, forKey: .channelDescription)
        inviterName = try container.decode(String.self, forKey: .inviterName)
        inviterAvatar = try container.decodeIfPresent(File.self, forKey: .inviterAvatar)
        memberCount = try container.decodeIfPresent(Int.self, forKey: .memberCount)
        isAlreadyJoined = false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind.rawValue, forKey: .kind)
        try container.encode(code.rawValue, forKey: .code)
        try container.encodeIfPresent(serverID, forKey: .serverID)
        try container.encodeIfPresent(serverName, forKey: .serverName)
        try container.encodeIfPresent(serverIcon, forKey: .serverIcon)
        try container.encodeIfPresent(serverBanner, forKey: .serverBanner)
        try container.encodeIfPresent(serverFlags, forKey: .serverFlags)
        try container.encode(channelID, forKey: .channelID)
        try container.encode(channelName, forKey: .channelName)
        try container.encodeIfPresent(channelDescription, forKey: .channelDescription)
        try container.encode(inviterName, forKey: .inviterName)
        try container.encodeIfPresent(inviterAvatar, forKey: .inviterAvatar)
        try container.encodeIfPresent(memberCount, forKey: .memberCount)
    }

    public func markingAlreadyJoined(_ value: Bool) -> InvitePreview {
        var copy = self
        copy.isAlreadyJoined = value
        return copy
    }
}

public struct ServerCreateDraft: Codable, Hashable, Sendable {
    public var name: String
    public var description: String?
    public var nsfw: Bool?

    public init(name: String, description: String? = nil, nsfw: Bool? = nil) {
        self.name = name
        self.description = description
        self.nsfw = nsfw
    }

    public var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var validatedForCreate: ServerCreateDraft? {
        let trimmed = trimmedName
        guard !trimmed.isEmpty, trimmed.count <= 32 else { return nil }
        let trimmedDescription = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ServerCreateDraft(name: trimmed, description: trimmedDescription?.isEmpty == true ? nil : trimmedDescription, nsfw: nsfw)
    }
}

public struct ServerCreateResponse: Codable, Hashable, Sendable {
    public var server: Server
    public var channels: [Channel]

    public init(server: Server, channels: [Channel]) {
        self.server = server
        self.channels = channels
    }
}

public enum InviteJoinResponse: Codable, Hashable, Sendable {
    case server(server: Server, channels: [Channel])
    case group(channel: Channel, users: [User])
    case unknown(String)

    private enum CodingKeys: String, CodingKey {
        case type
        case server
        case channels
        case channel
        case users
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "Server":
            self = .server(
                server: try container.decode(Server.self, forKey: .server),
                channels: try container.decodeDefault([Channel].self, forKey: .channels, default: [])
            )
        case "Group":
            self = .group(
                channel: try container.decode(Channel.self, forKey: .channel),
                users: try container.decodeDefault([User].self, forKey: .users, default: [])
            )
        default:
            self = .unknown(type)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .server(server, channels):
            try container.encode("Server", forKey: .type)
            try container.encode(server, forKey: .server)
            try container.encode(channels, forKey: .channels)
        case let .group(channel, users):
            try container.encode("Group", forKey: .type)
            try container.encode(channel, forKey: .channel)
            try container.encode(users, forKey: .users)
        case let .unknown(type):
            try container.encode(type, forKey: .type)
        }
    }
}
