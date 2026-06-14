import Foundation
import StoatModels
import StoatRealtime

public enum ServerSettingsTab: String, CaseIterable, Hashable, Sendable {
    case overview
    case appearance
    case categories
    case roles
    case permissions
    case members
    case moderation
    case danger

    public var title: String {
        switch self {
        case .overview: "Overview"
        case .appearance: "Appearance"
        case .categories: "Categories"
        case .roles: "Roles"
        case .permissions: "Permissions"
        case .members: "Members"
        case .moderation: "Moderation"
        case .danger: "Danger"
        }
    }
}

public struct ServerSettingsDetails: Hashable, Sendable {
    public var server: Server
    public var channels: [Channel]
    public var members: [ServerMember]
    public var runtimeLine: String
    public var capabilities: ServerManagementCapabilities
    public var permissionPreview: PermissionResolutionResult

    public init(server: Server, channels: [Channel], members: [ServerMember], runtimeLine: String, capabilities: ServerManagementCapabilities, permissionPreview: PermissionResolutionResult) {
        self.server = server
        self.channels = channels
        self.members = members
        self.runtimeLine = runtimeLine
        self.capabilities = capabilities
        self.permissionPreview = permissionPreview
    }
}

public struct ServerSettingsForm: Hashable, Sendable {
    public var name: String
    public var description: String

    public init(server: Server) {
        self.name = server.name
        self.description = server.description ?? ""
    }

    public func draft(original: Server) -> ServerEditDraft? {
        ServerEditDraft(name: name, description: description).validatedForEdit(original: original)
    }
}

public struct ServerMediaDraft: Hashable, Sendable {
    public var data: Data
    public var filename: String
    public var mimeType: String

    public init(data: Data, filename: String, mimeType: String) {
        self.data = data
        self.filename = filename
        self.mimeType = mimeType
    }
}

public struct CategoryEditorForm: Hashable, Sendable {
    public var categories: [ServerCategory]

    public init(server: Server) {
        self.categories = server.categories ?? []
    }

    public func uncategorizedChannels(allChannelIDs: [ChannelID]) -> [ChannelID] {
        let categorized = Set(categories.flatMap(\.channels))
        return allChannelIDs.filter { !categorized.contains($0) }
    }

    public mutating func createCategory(title: String, id: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        categories.append(ServerCategory(id: id, title: String(trimmed.prefix(64)), channels: []))
    }

    public mutating func renameCategory(id: String, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = categories.firstIndex(where: { $0.id == id }) else { return }
        categories[index].title = String(trimmed.prefix(64))
    }

    public mutating func deleteCategory(id: String) {
        categories.removeAll { $0.id == id }
    }

    public mutating func move(channelID: ChannelID, toCategory categoryID: String?) {
        for index in categories.indices {
            categories[index].channels.removeAll { $0 == channelID }
        }
        guard let categoryID, let index = categories.firstIndex(where: { $0.id == categoryID }) else { return }
        categories[index].channels.append(channelID)
    }
}

public struct RoleEditorForm: Hashable, Sendable {
    public var roleID: RoleID?
    public var name: String
    public var colour: String
    public var hoist: Bool

    public init(role: Role? = nil) {
        self.roleID = role?.id
        self.name = role?.name ?? ""
        self.colour = role?.colour ?? ""
        self.hoist = role?.hoist ?? false
    }

    public func createDraft() -> RoleCreateDraft? {
        RoleCreateDraft(name: name).validatedForCreate
    }

    public func editDraft(original: Role) -> RoleEditDraft? {
        RoleEditDraft(name: name, colour: colour, hoist: hoist).validatedForEdit(original: original)
    }
}

public enum PermissionResolutionWarning: String, Hashable, Sendable {
    case missingServer
    case missingMember
    case missingRole
    case missingChannelOverwrite
    case notServerChannel
    case timedOut
    case noViewChannel
}

public struct PermissionResolutionResult: Hashable, Sendable {
    public var effectivePermissions: Permissions
    public var canManageServer: Bool
    public var canManageChannels: Bool
    public var canInvite: Bool
    public var canManageRoles: Bool
    public var canAssignRoles: Bool
    public var canManagePermissions: Bool
    public var canUploadFiles: Bool
    public var warnings: [PermissionResolutionWarning]

    public init(effectivePermissions: Permissions, warnings: [PermissionResolutionWarning] = []) {
        self.effectivePermissions = effectivePermissions
        self.canManageServer = effectivePermissions.contains(.manageServer)
        self.canManageChannels = effectivePermissions.contains(.manageChannel)
        self.canInvite = effectivePermissions.contains(.inviteOthers)
        self.canManageRoles = effectivePermissions.contains(.manageRole)
        self.canAssignRoles = effectivePermissions.contains(.assignRoles)
        self.canManagePermissions = effectivePermissions.contains(.managePermissions)
        self.canUploadFiles = effectivePermissions.contains(.uploadFiles)
        self.warnings = warnings
    }
}

public enum Phase25PermissionResolver {
    public static func resolve(server: Server?, channel: Channel?, member: ServerMember?, currentUserID: UserID?) -> PermissionResolutionResult {
        guard let server else {
            return PermissionResolutionResult(effectivePermissions: [], warnings: [.missingServer])
        }
        if currentUserID == server.ownerID {
            return PermissionResolutionResult(effectivePermissions: .grantAllSafe)
        }
        guard let member else {
            return PermissionResolutionResult(effectivePermissions: [], warnings: [.missingMember])
        }

        var warnings: [PermissionResolutionWarning] = []
        var permissions = server.defaultPermissions
        let serverRoleOverrides = orderedRoles(member.roles, in: server).map(\.permissions)
        if serverRoleOverrides.count != member.roles.count {
            warnings.append(.missingRole)
        }
        for permissionOverride in serverRoleOverrides {
            permissions.apply(permissionOverride)
        }
        if !member.canPublish {
            permissions.remove([.speak, .video])
        }
        if !member.canReceive {
            permissions.remove(.listen)
        }
        if member.timeout != nil {
            permissions.formIntersection([.viewChannel, .readMessageHistory])
            warnings.append(.timedOut)
        }

        guard let channel else {
            return PermissionResolutionResult(effectivePermissions: permissions, warnings: warnings)
        }
        guard channel.kind == .textChannel || channel.kind == .voiceChannel else {
            warnings.append(.notServerChannel)
            return PermissionResolutionResult(effectivePermissions: channel.permissions ?? permissions, warnings: warnings)
        }
        permissions.apply(channel.defaultPermissions ?? PermissionOverride())
        let channelRoleOverrides = orderedRoles(member.roles, in: server).compactMap { role in
            channel.rolePermissions[role.id]
        }
        if !channel.rolePermissions.isEmpty && channelRoleOverrides.isEmpty {
            warnings.append(.missingChannelOverwrite)
        }
        for permissionOverride in channelRoleOverrides {
            permissions.apply(permissionOverride)
        }
        if member.timeout != nil {
            permissions.formIntersection([.viewChannel, .readMessageHistory])
        }
        if !permissions.contains(.viewChannel) {
            permissions = []
            warnings.append(.noViewChannel)
        }
        return PermissionResolutionResult(effectivePermissions: permissions, warnings: warnings)
    }

    public static func highestRank(for member: ServerMember?, in server: Server?) -> Int64? {
        guard let member, let server else { return nil }
        return member.roles.compactMap { server.roles[$0]?.rank }.min()
    }

    public static func isRoleEditable(_ role: Role, currentMember: ServerMember?, server: Server?, currentUserID: UserID?) -> Bool {
        guard let server else { return false }
        if currentUserID == server.ownerID { return true }
        guard let highest = highestRank(for: currentMember, in: server) else { return false }
        return role.rank > highest
    }

    private static func orderedRoles(_ roleIDs: [RoleID], in server: Server) -> [Role] {
        roleIDs.compactMap { server.roles[$0] }.sorted { $0.rank > $1.rank }
    }
}

private extension Permissions {
    mutating func apply(_ override: PermissionOverride) {
        formUnion(override.allow)
        subtract(override.deny)
    }
}
