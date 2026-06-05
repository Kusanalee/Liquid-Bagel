import Foundation
import StoatModels
import StoatRealtime

public enum Phase26BugPriority: String, Codable, Hashable, Sendable {
    case blocker
    case high
    case medium
    case low
    case backlog
}

public struct Phase26BugBacklogItem: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var priority: Phase26BugPriority
    public var summary: String

    public init(id: String, priority: Phase26BugPriority, summary: String) {
        self.id = id
        self.priority = priority
        self.summary = summary
    }
}

public struct MemberManagementItem: Hashable, Sendable, Identifiable {
    public var id: MemberCompositeKey { member.id }
    public var member: ServerMember
    public var user: User?
    public var displayName: String
    public var username: String
    public var roles: [Role]
    public var highestRank: Int64?
    public var timeoutSummary: String?

    public init(member: ServerMember, user: User?, server: Server) {
        self.member = member
        self.user = user
        let display = UserDisplayResolver.resolved(userID: member.id.userID, user: user, member: member)
        self.displayName = display.displayName
        self.username = display.subtitle ?? UserDisplayResolver.usernameLine(user: user, fallbackID: member.id.userID)
        self.roles = member.roles.compactMap { server.roles[$0] }.sorted { $0.rank < $1.rank }
        self.highestRank = Phase25PermissionResolver.highestRank(for: member, in: server)
        if let timeout = member.timeout, timeout > Date() {
            self.timeoutSummary = "Timed out until \(timeout.formatted(date: .abbreviated, time: .shortened))"
        } else {
            self.timeoutSummary = nil
        }
    }
}

public struct MemberRoleAssignmentDraft: Hashable, Sendable {
    public var member: ServerMember
    public var selectedRoleIDs: Set<RoleID>

    public init(member: ServerMember) {
        self.member = member
        self.selectedRoleIDs = Set(member.roles)
    }

    public var addedRoleIDs: [RoleID] {
        selectedRoleIDs.subtracting(member.roles).sorted { $0.rawValue < $1.rawValue }
    }

    public var removedRoleIDs: [RoleID] {
        Set(member.roles).subtracting(selectedRoleIDs).sorted { $0.rawValue < $1.rawValue }
    }

    public var hasChanges: Bool {
        !addedRoleIDs.isEmpty || !removedRoleIDs.isEmpty
    }

    public func memberDraft() -> MemberEditDraft? {
        guard hasChanges else { return nil }
        return MemberEditDraft(roles: selectedRoleIDs.sorted { $0.rawValue < $1.rawValue })
    }
}

public enum MemberModerationAction: String, Hashable, Sendable {
    case saveNickname
    case resetNickname
    case removeAvatar
    case kick
    case ban
    case timeout
    case clearTimeout
}

public struct PendingMemberModerationAction: Hashable, Sendable, Identifiable {
    public var id: String { "\(action.rawValue)-\(member.id.serverID.rawValue)-\(member.id.userID.rawValue)" }
    public var member: ServerMember
    public var action: MemberModerationAction
    public var reason: String
    public var timeoutUntil: Date?

    public init(member: ServerMember, action: MemberModerationAction, reason: String = "", timeoutUntil: Date? = nil) {
        self.member = member
        self.action = action
        self.reason = reason
        self.timeoutUntil = timeoutUntil
    }
}

public enum PermissionTriState: String, Codable, Hashable, Sendable, CaseIterable {
    case inherit
    case allow
    case deny
}

public enum PermissionEditScope: Hashable, Sendable {
    case serverDefault(serverID: ServerID)
    case serverRole(serverID: ServerID, roleID: RoleID)
    case channelDefault(channelID: ChannelID)
    case channelRole(channelID: ChannelID, roleID: RoleID)

    public var title: String {
        switch self {
        case .serverDefault: "Server default"
        case .serverRole: "Server role"
        case .channelDefault: "Channel default"
        case .channelRole: "Channel role"
        }
    }
}

public struct PermissionKey: Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var group: String
    public var permission: Permissions
    public var isDangerous: Bool

    public init(id: String, title: String, group: String, permission: Permissions, isDangerous: Bool = false) {
        self.id = id
        self.title = title
        self.group = group
        self.permission = permission
        self.isDangerous = isDangerous
    }
}

public struct PermissionEditDiff: Hashable, Sendable, Identifiable {
    public var id: String { key.id }
    public var key: PermissionKey
    public var previous: PermissionTriState
    public var next: PermissionTriState
}

public struct PermissionEditDraft: Hashable, Sendable {
    public var scope: PermissionEditScope
    public var originalAllow: Permissions
    public var originalDeny: Permissions
    public var allowsInherit: Bool
    public var draft: [String: PermissionTriState]
    public var warnings: [String]

    public init(scope: PermissionEditScope, originalAllow: Permissions, originalDeny: Permissions, allowsInherit: Bool, keys: [PermissionKey], warnings: [String] = []) {
        self.scope = scope
        self.originalAllow = originalAllow
        self.originalDeny = originalDeny
        self.allowsInherit = allowsInherit
        self.draft = Dictionary(uniqueKeysWithValues: keys.map { ($0.id, Self.state(for: $0.permission, allow: originalAllow, deny: originalDeny, allowsInherit: allowsInherit)) })
        self.warnings = warnings
    }

    public func state(for key: PermissionKey) -> PermissionTriState {
        draft[key.id] ?? Self.state(for: key.permission, allow: originalAllow, deny: originalDeny, allowsInherit: allowsInherit)
    }

    public mutating func set(_ state: PermissionTriState, for key: PermissionKey) {
        draft[key.id] = allowsInherit ? state : (state == .inherit ? .deny : state)
    }

    public func diff(keys: [PermissionKey]) -> [PermissionEditDiff] {
        keys.compactMap { key in
            let previous = Self.state(for: key.permission, allow: originalAllow, deny: originalDeny, allowsInherit: allowsInherit)
            let next = state(for: key)
            return previous == next ? nil : PermissionEditDiff(key: key, previous: previous, next: next)
        }
    }

    public func overrideDraft(keys: [PermissionKey]) -> PermissionWriteOverride {
        var allow: Permissions = []
        var deny: Permissions = []
        for key in keys {
            switch state(for: key) {
            case .allow:
                allow.insert(key.permission)
            case .deny:
                deny.insert(key.permission)
            case .inherit:
                break
            }
        }
        return PermissionWriteOverride(allow: allow, deny: deny)
    }

    public func defaultPermissionsDraft(keys: [PermissionKey]) -> Permissions {
        var permissions: Permissions = []
        for key in keys where state(for: key) == .allow {
            permissions.insert(key.permission)
        }
        return permissions
    }

    public static func state(for permission: Permissions, allow: Permissions, deny: Permissions, allowsInherit: Bool) -> PermissionTriState {
        if allow.contains(permission) { return .allow }
        if deny.contains(permission) { return .deny }
        return allowsInherit ? .inherit : .deny
    }
}

public enum Phase26Permissions {
    public static let editableKeys: [PermissionKey] = [
        PermissionKey(id: "view", title: "View Channel", group: "General", permission: .viewChannel),
        PermissionKey(id: "history", title: "Read History", group: "General", permission: .readMessageHistory),
        PermissionKey(id: "invite", title: "Invite Others", group: "Membership", permission: .inviteOthers),
        PermissionKey(id: "assign", title: "Assign Roles", group: "Membership", permission: .assignRoles, isDangerous: true),
        PermissionKey(id: "kick", title: "Kick Members", group: "Membership", permission: .kickMembers, isDangerous: true),
        PermissionKey(id: "ban", title: "Ban Members", group: "Membership", permission: .banMembers, isDangerous: true),
        PermissionKey(id: "timeout", title: "Timeout Members", group: "Membership", permission: .timeoutMembers, isDangerous: true),
        PermissionKey(id: "nickname", title: "Manage Nicknames", group: "Membership", permission: .manageNicknames),
        PermissionKey(id: "avatars", title: "Remove Avatars", group: "Membership", permission: .removeAvatars),
        PermissionKey(id: "send", title: "Send Messages", group: "Messaging", permission: .sendMessage),
        PermissionKey(id: "react", title: "React", group: "Messaging", permission: .react),
        PermissionKey(id: "manage-messages", title: "Manage Messages", group: "Messaging", permission: .manageMessages),
        PermissionKey(id: "embed", title: "Send Embeds", group: "Media", permission: .sendEmbeds),
        PermissionKey(id: "upload", title: "Upload Files", group: "Media", permission: .uploadFiles),
        PermissionKey(id: "connect", title: "Connect", group: "Voice", permission: .connect),
        PermissionKey(id: "speak", title: "Speak", group: "Voice", permission: .speak),
        PermissionKey(id: "listen", title: "Listen", group: "Voice", permission: .listen),
        PermissionKey(id: "manage-server", title: "Manage Server", group: "Administration", permission: .manageServer, isDangerous: true),
        PermissionKey(id: "manage-channel", title: "Manage Channels", group: "Administration", permission: .manageChannel, isDangerous: true),
        PermissionKey(id: "manage-roles", title: "Manage Roles", group: "Administration", permission: .manageRole, isDangerous: true),
        PermissionKey(id: "manage-permissions", title: "Manage Permissions", group: "Administration", permission: .managePermissions, isDangerous: true)
    ]
}

public enum Phase26MemberSafety {
    public static func canActOn(member target: ServerMember, currentMember: ServerMember?, server: Server?, currentUserID: UserID?) -> Bool {
        guard let server else { return false }
        if currentUserID == server.ownerID { return target.id.userID != currentUserID }
        guard target.id.userID != server.ownerID,
              target.id.userID != currentUserID,
              let currentRank = Phase25PermissionResolver.highestRank(for: currentMember, in: server),
              let targetRank = Phase25PermissionResolver.highestRank(for: target, in: server)
        else {
            return false
        }
        return targetRank > currentRank
    }

    public static func assignableRoles(in server: Server, currentMember: ServerMember?, currentUserID: UserID?) -> [Role] {
        server.roles.values
            .filter { Phase25PermissionResolver.isRoleEditable($0, currentMember: currentMember, server: server, currentUserID: currentUserID) }
            .sorted { $0.rank < $1.rank }
    }
}
