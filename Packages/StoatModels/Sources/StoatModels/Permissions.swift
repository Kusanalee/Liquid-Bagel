import Foundation

public struct Permissions: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(UInt64.self) {
            rawValue = value
        } else {
            let value = try container.decode(Int64.self)
            rawValue = UInt64(bitPattern: value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static let manageChannel = Permissions(rawValue: 1 << 0)
    public static let manageServer = Permissions(rawValue: 1 << 1)
    public static let managePermissions = Permissions(rawValue: 1 << 2)
    public static let manageRole = Permissions(rawValue: 1 << 3)
    public static let manageCustomisation = Permissions(rawValue: 1 << 4)

    public static let kickMembers = Permissions(rawValue: 1 << 6)
    public static let banMembers = Permissions(rawValue: 1 << 7)
    public static let timeoutMembers = Permissions(rawValue: 1 << 8)
    public static let assignRoles = Permissions(rawValue: 1 << 9)
    public static let changeNickname = Permissions(rawValue: 1 << 10)
    public static let manageNicknames = Permissions(rawValue: 1 << 11)
    public static let changeAvatar = Permissions(rawValue: 1 << 12)
    public static let removeAvatars = Permissions(rawValue: 1 << 13)

    public static let viewChannel = Permissions(rawValue: 1 << 20)
    public static let readMessageHistory = Permissions(rawValue: 1 << 21)
    public static let sendMessage = Permissions(rawValue: 1 << 22)
    public static let manageMessages = Permissions(rawValue: 1 << 23)
    public static let manageWebhooks = Permissions(rawValue: 1 << 24)
    public static let inviteOthers = Permissions(rawValue: 1 << 25)
    public static let sendEmbeds = Permissions(rawValue: 1 << 26)
    public static let uploadFiles = Permissions(rawValue: 1 << 27)
    public static let masquerade = Permissions(rawValue: 1 << 28)
    public static let react = Permissions(rawValue: 1 << 29)

    public static let connect = Permissions(rawValue: 1 << 30)
    public static let speak = Permissions(rawValue: 1 << 31)
    public static let video = Permissions(rawValue: 1 << 32)
    public static let muteMembers = Permissions(rawValue: 1 << 33)
    public static let deafenMembers = Permissions(rawValue: 1 << 34)
    public static let moveMembers = Permissions(rawValue: 1 << 35)
    public static let listen = Permissions(rawValue: 1 << 36)
    public static let mentionEveryone = Permissions(rawValue: 1 << 37)
    public static let mentionRoles = Permissions(rawValue: 1 << 38)
    public static let bypassSlowmode = Permissions(rawValue: 1 << 39)

    public static let grantAllSafe = Permissions(rawValue: 0x000F_FFFF_FFFF_FFFF)
}

public struct PermissionOverride: Codable, Hashable, Sendable {
    public var allow: Permissions
    public var deny: Permissions

    public init(allow: Permissions = [], deny: Permissions = []) {
        self.allow = allow
        self.deny = deny
    }

    private enum CodingKeys: String, CodingKey {
        case allow = "a"
        case deny = "d"
    }
}

