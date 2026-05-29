import Foundation

public struct StoatID<Tag>: RawRepresentable, Codable, Hashable, Sendable, Identifiable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public var id: String { rawValue }
    public var description: String { rawValue }

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum UserIDTag {}
public enum ServerIDTag {}
public enum ChannelIDTag {}
public enum MessageIDTag {}
public enum RoleIDTag {}
public enum EmojiIDTag {}
public enum FileIDTag {}
public enum InviteIDTag {}
public enum SessionIDTag {}

public typealias UserID = StoatID<UserIDTag>
public typealias ServerID = StoatID<ServerIDTag>
public typealias ChannelID = StoatID<ChannelIDTag>
public typealias MessageID = StoatID<MessageIDTag>
public typealias RoleID = StoatID<RoleIDTag>
public typealias EmojiID = StoatID<EmojiIDTag>
public typealias FileID = StoatID<FileIDTag>
public typealias InviteID = StoatID<InviteIDTag>
public typealias SessionID = StoatID<SessionIDTag>

