import Foundation
import StoatModels

public enum ModerationDisabledReason: String, Hashable, Sendable {
    case noSelectedServer
    case disconnected
    case routeUnavailable
    case currentUserMissingPermission
    case permissionResolutionIncomplete
    case targetIsSelf
    case targetIsServerOwner
    case targetNotMember
    case targetAlreadyBanned
    case targetNotBanned
    case targetNotTimedOut
    case targetRoleEqualOrHigher
    case unknownMemberData
    case unknownPermissionHierarchy
    case targetHasTimeoutPermission

    public var message: String {
        switch self {
        case .noSelectedServer: "Select a server before moderating members."
        case .disconnected: "Reconnect before member moderation."
        case .routeUnavailable: "This moderation route is not verified in Liquid Bagel."
        case .currentUserMissingPermission: "You do not have permission for this moderation action."
        case .permissionResolutionIncomplete: "Permission resolution is incomplete for this moderation action."
        case .targetIsSelf: "You cannot moderate yourself."
        case .targetIsServerOwner: "You cannot moderate the server owner."
        case .targetNotMember: "This action requires the target to be a current server member."
        case .targetAlreadyBanned: "This user is already banned from this server."
        case .targetNotBanned: "This user is not in the current ban list."
        case .targetNotTimedOut: "This member is not currently timed out."
        case .targetRoleEqualOrHigher: "This member has an equal or higher role."
        case .unknownMemberData: "Member data is not hydrated enough to safely moderate this user."
        case .unknownPermissionHierarchy: "Cannot verify permission hierarchy for this member."
        case .targetHasTimeoutPermission: "This member has timeout permission and cannot be timed out safely."
        }
    }
}

public struct ModerationRouteAvailability: Hashable, Sendable {
    public var kick: Bool
    public var ban: Bool
    public var unban: Bool
    public var timeout: Bool
    public var removeTimeout: Bool
    public var fetchBans: Bool
    public var fetchUser: Bool

    public init(
        kick: Bool = true,
        ban: Bool = true,
        unban: Bool = true,
        timeout: Bool = true,
        removeTimeout: Bool = true,
        fetchBans: Bool = true,
        fetchUser: Bool = true
    ) {
        self.kick = kick
        self.ban = ban
        self.unban = unban
        self.timeout = timeout
        self.removeTimeout = removeTimeout
        self.fetchBans = fetchBans
        self.fetchUser = fetchUser
    }

    public func isAvailable(_ action: ModerationAction) -> Bool {
        switch action {
        case .kick: kick
        case .ban: ban
        case .unban: unban
        case .timeout: timeout
        case .removeTimeout: removeTimeout
        }
    }
}

public struct ModerationActionContext: Hashable, Sendable {
    public var currentUserID: UserID?
    public var server: Server?
    public var currentMember: ServerMember?
    public var targetUserID: UserID
    public var targetMember: ServerMember?
    public var knownBannedUserIDs: Set<UserID>
    public var permissionResolution: PermissionResolutionResult
    public var isConnectedForLiveActions: Bool
    public var routeAvailability: ModerationRouteAvailability
    public var allowNonMemberBan: Bool
    public var now: Date

    public init(
        currentUserID: UserID?,
        server: Server?,
        currentMember: ServerMember?,
        targetUserID: UserID,
        targetMember: ServerMember?,
        knownBannedUserIDs: Set<UserID> = [],
        permissionResolution: PermissionResolutionResult,
        isConnectedForLiveActions: Bool,
        routeAvailability: ModerationRouteAvailability = ModerationRouteAvailability(),
        allowNonMemberBan: Bool = false,
        now: Date = Date()
    ) {
        self.currentUserID = currentUserID
        self.server = server
        self.currentMember = currentMember
        self.targetUserID = targetUserID
        self.targetMember = targetMember
        self.knownBannedUserIDs = knownBannedUserIDs
        self.permissionResolution = permissionResolution
        self.isConnectedForLiveActions = isConnectedForLiveActions
        self.routeAvailability = routeAvailability
        self.allowNonMemberBan = allowNonMemberBan
        self.now = now
    }
}

public enum ModerationActionResolver {
    public static func availableModerationActions(context: ModerationActionContext) -> [ModerationAction] {
        ModerationAction.allCases.filter { disabledReason(for: $0, context: context) == nil }
    }

    public static func disabledReason(for action: ModerationAction, context: ModerationActionContext) -> ModerationDisabledReason? {
        guard let server = context.server else { return .noSelectedServer }
        guard context.routeAvailability.isAvailable(action) else { return .routeUnavailable }
        guard context.isConnectedForLiveActions else { return .disconnected }
        if context.targetUserID == context.currentUserID {
            return .targetIsSelf
        }
        if context.targetUserID == server.ownerID {
            return .targetIsServerOwner
        }

        let isOwner = context.currentUserID == server.ownerID
        let knownBanned = context.knownBannedUserIDs.contains(context.targetUserID)
        let requiredPermission = permission(for: action)
        if !isOwner, !context.permissionResolution.effectivePermissions.contains(requiredPermission) {
            return context.permissionResolution.warnings.isEmpty ? .currentUserMissingPermission : .permissionResolutionIncomplete
        }
        if !isOwner, context.permissionResolution.warnings.contains(.missingMember) {
            return .unknownMemberData
        }
        if !isOwner, context.permissionResolution.warnings.contains(.missingRole) {
            return .unknownPermissionHierarchy
        }

        switch action {
        case .kick:
            guard let targetMember = context.targetMember else { return .targetNotMember }
            return hierarchyDisabledReason(currentMember: context.currentMember, targetMember: targetMember, server: server, isOwner: isOwner)
        case .ban:
            if knownBanned { return .targetAlreadyBanned }
            guard let targetMember = context.targetMember else {
                return context.allowNonMemberBan ? nil : .unknownMemberData
            }
            return hierarchyDisabledReason(currentMember: context.currentMember, targetMember: targetMember, server: server, isOwner: isOwner)
        case .unban:
            return knownBanned ? nil : .targetNotBanned
        case .timeout:
            guard let targetMember = context.targetMember else { return .targetNotMember }
            if !isOwner, targetCanTimeoutMembers(targetMember, server: server) {
                return .targetHasTimeoutPermission
            }
            return hierarchyDisabledReason(currentMember: context.currentMember, targetMember: targetMember, server: server, isOwner: isOwner)
        case .removeTimeout:
            guard let targetMember = context.targetMember else { return .targetNotMember }
            guard let timeout = targetMember.timeout, timeout > context.now else { return .targetNotTimedOut }
            return hierarchyDisabledReason(currentMember: context.currentMember, targetMember: targetMember, server: server, isOwner: isOwner)
        }
    }

    public static func requiresConfirmation(for action: ModerationAction) -> Bool {
        switch action {
        case .kick, .ban, .unban, .timeout, .removeTimeout:
            true
        }
    }

    private static func permission(for action: ModerationAction) -> Permissions {
        switch action {
        case .kick:
            .kickMembers
        case .ban, .unban:
            .banMembers
        case .timeout, .removeTimeout:
            .timeoutMembers
        }
    }

    private static func hierarchyDisabledReason(currentMember: ServerMember?, targetMember: ServerMember, server: Server, isOwner: Bool) -> ModerationDisabledReason? {
        if isOwner { return nil }
        guard let currentRank = currentRanking(currentMember, server: server),
              let targetRank = targetRanking(targetMember, server: server)
        else {
            return .unknownPermissionHierarchy
        }
        return targetRank <= currentRank ? .targetRoleEqualOrHigher : nil
    }

    private static func currentRanking(_ member: ServerMember?, server: Server) -> Int64? {
        Phase25PermissionResolver.highestRank(for: member, in: server)
    }

    private static func targetRanking(_ member: ServerMember, server: Server) -> Int64? {
        Phase25PermissionResolver.highestRank(for: member, in: server)
    }

    private static func targetCanTimeoutMembers(_ member: ServerMember, server: Server) -> Bool {
        var permissions = server.defaultPermissions
        for role in member.roles.compactMap({ server.roles[$0] }).sorted(by: { $0.rank > $1.rank }) {
            permissions.formUnion(role.permissions.allow)
            permissions.subtract(role.permissions.deny)
        }
        return permissions.contains(.timeoutMembers)
    }
}
