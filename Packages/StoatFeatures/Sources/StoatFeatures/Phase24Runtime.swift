import Foundation
import StoatModels
import StoatRealtime

public enum ManagementActionState<Value: Hashable & Sendable>: Hashable, Sendable {
    case idle
    case loading
    case loaded(Value)
    case failed(String)
}

public struct ServerOverviewDetails: Hashable, Sendable {
    public var server: Server
    public var channels: [Channel]
    public var memberCount: Int
    public var runtimeLine: String
    public var capabilities: ServerManagementCapabilities

    public init(server: Server, channels: [Channel], memberCount: Int, runtimeLine: String, capabilities: ServerManagementCapabilities) {
        self.server = server
        self.channels = channels
        self.memberCount = memberCount
        self.runtimeLine = runtimeLine
        self.capabilities = capabilities
    }
}

public struct ServerManagementCapabilities: Hashable, Sendable {
    public var canManageServer: Bool
    public var canManageChannels: Bool
    public var canInvite: Bool
    public var isConnectedForLiveActions: Bool
    public var permissionResolutionIncomplete: Bool

    public init(canManageServer: Bool, canManageChannels: Bool, canInvite: Bool, isConnectedForLiveActions: Bool, permissionResolutionIncomplete: Bool = false) {
        self.canManageServer = canManageServer
        self.canManageChannels = canManageChannels
        self.canInvite = canInvite
        self.isConnectedForLiveActions = isConnectedForLiveActions
        self.permissionResolutionIncomplete = permissionResolutionIncomplete
    }
}

public struct ChannelCreateForm: Hashable, Sendable {
    public var name: String
    public var description: String
    public var isNSFW: Bool
    public var categoryID: String?

    public init(name: String = "", description: String = "", isNSFW: Bool = false, categoryID: String? = nil) {
        self.name = name
        self.description = description
        self.isNSFW = isNSFW
        self.categoryID = categoryID
    }

    public func draft() -> ChannelCreateDraft? {
        ChannelCreateDraft(name: name, description: description, nsfw: isNSFW ? true : nil).validatedForCreate
    }
}

public struct ChannelEditForm: Hashable, Sendable {
    public var channelID: ChannelID
    public var name: String
    public var description: String
    public var isNSFW: Bool
    public var slowmodeSeconds: UInt64

    public init(channel: Channel) {
        self.channelID = channel.id
        self.name = channel.name ?? channel.displayName
        self.description = channel.description ?? ""
        self.isNSFW = channel.nsfw
        self.slowmodeSeconds = channel.slowmode ?? 0
    }

    public func draft(original: Channel) -> ChannelEditDraft? {
        ChannelEditDraft(
            name: name,
            description: description,
            nsfw: isNSFW,
            slowmode: slowmodeSeconds
        ).validatedForEdit(original: original)
    }
}

public struct PendingChannelDeletion: Identifiable, Hashable, Sendable {
    public var id: ChannelID { channel.id }
    public var channel: Channel

    public init(channel: Channel) {
        self.channel = channel
    }
}

public enum Phase24Management {
    public static func capabilities(
        server: Server?,
        selectedChannel: Channel?,
        currentUserID: UserID?,
        runtimeMode: AppRuntimeMode,
        sessionState: AppSessionState
    ) -> ServerManagementCapabilities {
        let connected = runtimeMode == .mock || (runtimeMode == .liveManual && sessionState == .connected)
        guard let server else {
            return ServerManagementCapabilities(canManageServer: false, canManageChannels: false, canInvite: false, isConnectedForLiveActions: connected, permissionResolutionIncomplete: true)
        }
        let isOwner = currentUserID == server.ownerID
        let serverPermissions = server.defaultPermissions
        let channelPermissions = selectedChannel?.permissions ?? serverPermissions
        let incomplete = selectedChannel?.permissions == nil && !isOwner
        return ServerManagementCapabilities(
            canManageServer: isOwner || serverPermissions.contains(.manageServer),
            canManageChannels: isOwner || channelPermissions.contains(.manageChannel) || serverPermissions.contains(.manageChannel),
            canInvite: isOwner || channelPermissions.contains(.inviteOthers) || serverPermissions.contains(.inviteOthers),
            isConnectedForLiveActions: connected,
            permissionResolutionIncomplete: incomplete
        )
    }

    public static func disabledReasonForChannelManagement(_ capabilities: ServerManagementCapabilities, destructive: Bool = false) -> String? {
        guard capabilities.isConnectedForLiveActions else {
            return "Connect manually to manage channels."
        }
        guard capabilities.canManageChannels else {
            return destructive || capabilities.permissionResolutionIncomplete ? "Permission resolution is incomplete for this action." : "You do not have permission to manage this channel."
        }
        return nil
    }

    public static func disabledReasonForInvites(_ capabilities: ServerManagementCapabilities) -> String? {
        guard capabilities.isConnectedForLiveActions else {
            return "Connect manually to manage invites."
        }
        guard capabilities.canInvite || capabilities.canManageServer else {
            return capabilities.permissionResolutionIncomplete ? "Permission resolution is incomplete for this action." : "You do not have permission to manage invites."
        }
        return nil
    }
}

public enum Phase24SnapshotIntegrator {
    public static func upserting(channel: Channel, into snapshot: RealtimeSnapshot) -> RealtimeSnapshot {
        var snapshot = snapshot
        snapshot.channelsByID[channel.id] = channel
        if let serverID = channel.serverID, var server = snapshot.serversByID[serverID], !server.channelIDs.contains(channel.id) {
            server.channelIDs.append(channel.id)
            snapshot.serversByID[serverID] = server
        }
        return snapshot
    }

    public static func upserting(server: Server, channels: [Channel], into snapshot: RealtimeSnapshot) -> RealtimeSnapshot {
        var snapshot = snapshot
        snapshot.serversByID[server.id] = server
        for channel in channels {
            snapshot = upserting(channel: channel, into: snapshot)
        }
        return snapshot
    }

    public static func deleting(channelID: ChannelID, selectedChannelID: ChannelID?, in snapshot: RealtimeSnapshot) -> (RealtimeSnapshot, ChannelID?) {
        var snapshot = snapshot
        let serverID = snapshot.channelsByID[channelID]?.serverID
        snapshot.channelsByID.removeValue(forKey: channelID)
        snapshot.messagesByChannelID.removeValue(forKey: channelID)
        snapshot.unreadsByChannelID.removeValue(forKey: channelID)
        if let serverID, var server = snapshot.serversByID[serverID] {
            server.channelIDs.removeAll { $0 == channelID }
            server.categories = server.categories?.map { category in
                var category = category
                category.channels.removeAll { $0 == channelID }
                return category
            }
            snapshot.serversByID[serverID] = server
        }
        guard selectedChannelID == channelID, let serverID else {
            return (snapshot, selectedChannelID)
        }
        let fallback = snapshot.serversByID[serverID]?.channelIDs.first { snapshot.channelsByID[$0]?.kind == .textChannel }
        return (snapshot, fallback)
    }

    public static func server(_ server: Server, appending channelID: ChannelID, toCategory categoryID: String?) -> Server {
        guard let categoryID, var categories = server.categories, let index = categories.firstIndex(where: { $0.id == categoryID }) else {
            return server
        }
        if !categories[index].channels.contains(channelID) {
            categories[index].channels.append(channelID)
        }
        var server = server
        server.categories = categories
        return server
    }
}
