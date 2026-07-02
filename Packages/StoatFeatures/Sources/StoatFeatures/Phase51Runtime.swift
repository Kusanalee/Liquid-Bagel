import Foundation
import StoatModels
import StoatPersistence
import StoatRealtime
import StoatUI

public struct Phase51PresentationRevision: Hashable, Sendable {
    public var snapshot: Int
    public var selection: Int
    public var identity: Int
    public var messages: Int
    public var media: Int

    public init(
        snapshot: Int = 0,
        selection: Int = 0,
        identity: Int = 0,
        messages: Int = 0,
        media: Int = 0
    ) {
        self.snapshot = snapshot
        self.selection = selection
        self.identity = identity
        self.messages = messages
        self.media = media
    }
}

public struct ServerRailPresentationItem: Identifiable, Hashable, Sendable {
    public var id: ServerID { server.id }
    public var server: Server
    public var unreadCount: Int
    public var mentionCount: Int

    public init(server: Server, unreadCount: Int = 0, mentionCount: Int = 0) {
        self.server = server
        self.unreadCount = unreadCount
        self.mentionCount = mentionCount
    }
}

public struct ShellPresentationSnapshot: Hashable, Sendable {
    public var revision: Phase51PresentationRevision
    public var serverRailItems: [ServerRailPresentationItem]
    public var serverRailItemsByID: [ServerID: ServerRailPresentationItem]
    public var allFriendItems: [FriendListItem]
    public var directMessageItems: [DirectMessageListItem]

    public init(
        revision: Phase51PresentationRevision = Phase51PresentationRevision(),
        serverRailItems: [ServerRailPresentationItem] = [],
        serverRailItemsByID: [ServerID: ServerRailPresentationItem] = [:],
        allFriendItems: [FriendListItem] = [],
        directMessageItems: [DirectMessageListItem] = []
    ) {
        self.revision = revision
        self.serverRailItems = serverRailItems
        self.serverRailItemsByID = serverRailItemsByID
        self.allFriendItems = allFriendItems
        self.directMessageItems = directMessageItems
    }

    public var servers: [Server] {
        serverRailItems.map(\.server)
    }
}

public struct ServerSettingsPresentationSnapshot: Hashable, Sendable {
    public var revision: Phase51PresentationRevision
    public var details: ServerSettingsDetails
    public var orderedRoles: [Role]
    public var textChannels: [Channel]
    public var permissionGroups: [String]
    public var emojiItems: [CustomEmojiDisplayItem]
    public var emojiManagementDisabledReason: String?
    public var memberItems: [MemberManagementItem]
    public var timeoutItems: [MemberManagementItem]

    public init(
        revision: Phase51PresentationRevision,
        details: ServerSettingsDetails,
        orderedRoles: [Role],
        textChannels: [Channel],
        permissionGroups: [String],
        emojiItems: [CustomEmojiDisplayItem],
        emojiManagementDisabledReason: String?,
        memberItems: [MemberManagementItem],
        timeoutItems: [MemberManagementItem]
    ) {
        self.revision = revision
        self.details = details
        self.orderedRoles = orderedRoles
        self.textChannels = textChannels
        self.permissionGroups = permissionGroups
        self.emojiItems = emojiItems
        self.emojiManagementDisabledReason = emojiManagementDisabledReason
        self.memberItems = memberItems
        self.timeoutItems = timeoutItems
    }
}

public struct TimelineRowPresentation: Hashable, Sendable, Identifiable {
    public var id: MessageID { messageID }
    public var messageID: MessageID
    public var authorDisplay: ResolvedUserDisplay
    public var isSystemEvent: Bool
    public var preparedMarkdownContent: PreparedMarkdownContent?
    public var attachmentItems: [AttachmentDisplayItem]
    public var customEmojiItems: [MessageInlineCustomEmojiItem]
    public var embedItems: [MessageEmbedDisplayItem]
    public var actionItems: [MessageActionItem]
    public var reactionItems: [MessageReactionDisplayItem]
    public var systemEventPresentation: SystemEventPresentation?

    public init(
        messageID: MessageID,
        authorDisplay: ResolvedUserDisplay,
        isSystemEvent: Bool,
        preparedMarkdownContent: PreparedMarkdownContent? = nil,
        attachmentItems: [AttachmentDisplayItem] = [],
        customEmojiItems: [MessageInlineCustomEmojiItem] = [],
        embedItems: [MessageEmbedDisplayItem] = [],
        actionItems: [MessageActionItem] = [],
        reactionItems: [MessageReactionDisplayItem] = [],
        systemEventPresentation: SystemEventPresentation? = nil
    ) {
        self.messageID = messageID
        self.authorDisplay = authorDisplay
        self.isSystemEvent = isSystemEvent
        self.preparedMarkdownContent = preparedMarkdownContent
        self.attachmentItems = attachmentItems
        self.customEmojiItems = customEmojiItems
        self.embedItems = embedItems
        self.actionItems = actionItems
        self.reactionItems = reactionItems
        self.systemEventPresentation = systemEventPresentation
    }
}

public enum TimelinePresentationState: Hashable, Sendable {
    case idle
    case preparing(channelID: ChannelID, loadedMessageCount: Int, visibleGroupCount: Int)
    case ready(channelID: ChannelID, messageCount: Int, groupCount: Int)
}

public struct TimelinePresentationDiagnostics: Hashable, Sendable {
    public var groupingBuildCount: Int
    public var rowBuildCount: Int
    public var cancellationCount: Int
    public var staleResultDiscardCount: Int
    public var visibleMessageCount: Int
    public var visibleGroupCount: Int

    public init(
        groupingBuildCount: Int = 0,
        rowBuildCount: Int = 0,
        cancellationCount: Int = 0,
        staleResultDiscardCount: Int = 0,
        visibleMessageCount: Int = 0,
        visibleGroupCount: Int = 0
    ) {
        self.groupingBuildCount = groupingBuildCount
        self.rowBuildCount = rowBuildCount
        self.cancellationCount = cancellationCount
        self.staleResultDiscardCount = staleResultDiscardCount
        self.visibleMessageCount = visibleMessageCount
        self.visibleGroupCount = visibleGroupCount
    }
}

public struct Phase51PerformanceDiagnostics: Hashable, Sendable {
    public var shellBuildCount: Int
    public var shellCacheHitCount: Int
    public var timelineBuildCount: Int
    public var timelineCacheHitCount: Int
    public var serverSettingsBuildCount: Int
    public var serverSettingsCancellationCount: Int
    public var diagnosticsPublishCount: Int
    public var diagnosticsThrottleCount: Int
    public var lastOperationCategory: String?
    public var lastOperationMilliseconds: Int?
    public var mainThreadBudgetViolationCount: Int

    public init(
        shellBuildCount: Int = 0,
        shellCacheHitCount: Int = 0,
        timelineBuildCount: Int = 0,
        timelineCacheHitCount: Int = 0,
        serverSettingsBuildCount: Int = 0,
        serverSettingsCancellationCount: Int = 0,
        diagnosticsPublishCount: Int = 0,
        diagnosticsThrottleCount: Int = 0,
        lastOperationCategory: String? = nil,
        lastOperationMilliseconds: Int? = nil,
        mainThreadBudgetViolationCount: Int = 0
    ) {
        self.shellBuildCount = shellBuildCount
        self.shellCacheHitCount = shellCacheHitCount
        self.timelineBuildCount = timelineBuildCount
        self.timelineCacheHitCount = timelineCacheHitCount
        self.serverSettingsBuildCount = serverSettingsBuildCount
        self.serverSettingsCancellationCount = serverSettingsCancellationCount
        self.diagnosticsPublishCount = diagnosticsPublishCount
        self.diagnosticsThrottleCount = diagnosticsThrottleCount
        self.lastOperationCategory = lastOperationCategory
        self.lastOperationMilliseconds = lastOperationMilliseconds
        self.mainThreadBudgetViolationCount = mainThreadBudgetViolationCount
    }
}

public enum Phase51PresentationBuilder {
    public static func shell(
        revision: Phase51PresentationRevision,
        snapshot: RealtimeSnapshot,
        selection: ShellSelection,
        currentUserID: UserID?,
        currentUser: User?,
        localReadStates: [ChannelID: LocalReadState],
        locallyClearedUnreadChannelIDs: Set<ChannelID>,
        notificationPreferences: NotificationPreferences
    ) throws -> ShellPresentationSnapshot {
        try Task.checkCancellation()
        let railItems = snapshot.serversByID.values
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { server in
                var unreadCount = 0
                var mentionCount = 0
                for channelID in server.channelIDs {
                    let remote = snapshot.unreadsByChannelID[channelID]
                    let local = localReadStates[channelID]
                    let isSelected = selection.channelID == channelID || selection.dmChannelID == channelID
                    let isCleared = locallyClearedUnreadChannelIDs.contains(channelID)
                    if !isSelected, !isCleared, (local?.unreadCount ?? 0) > 0 || remote?.lastMessageID != nil {
                        unreadCount += 1
                    }
                    mentionCount += max(local?.mentionCount ?? 0, remote?.mentions.count ?? 0)
                }
                return ServerRailPresentationItem(server: server, unreadCount: unreadCount, mentionCount: mentionCount)
            }
        try Task.checkCancellation()
        let friends = Phase22Derivations.friendItems(
            snapshot: snapshot,
            currentUserID: currentUserID,
            currentUser: currentUser,
            localReadStates: localReadStates
        )
        try Task.checkCancellation()
        let directMessages = Phase22Derivations.directMessageItems(
            snapshot: snapshot,
            currentUserID: currentUserID,
            localReadStates: localReadStates,
            notificationPreferences: notificationPreferences,
            selectedChannelID: ActiveConversation.resolve(selection: selection, snapshot: snapshot).channelID
        )
        return ShellPresentationSnapshot(
            revision: revision,
            serverRailItems: railItems,
            serverRailItemsByID: Dictionary(uniqueKeysWithValues: railItems.map { ($0.id, $0) }),
            allFriendItems: friends,
            directMessageItems: directMessages
        )
    }

    public static func serverSettings(
        revision: Phase51PresentationRevision,
        snapshot: RealtimeSnapshot,
        serverID: ServerID,
        selectedChannelID: ChannelID?,
        currentUserID: UserID?,
        runtimeLine: String,
        capabilities: ServerManagementCapabilities,
        identitySnapshots: Phase43IdentitySnapshotStore,
        normalizedMemberQuery: String
    ) -> ServerSettingsPresentationSnapshot? {
        guard let server = snapshot.serversByID[serverID] else { return nil }
        let channels = orderedChannels(server: server, snapshot: snapshot)
        let members = snapshot.membersByServerAndUserID.values
            .filter { $0.id.serverID == serverID }
            .sorted { $0.id.userID.rawValue < $1.id.userID.rawValue }
        let selectedChannel = selectedChannelID.flatMap { snapshot.channelsByID[$0] }
        let fallbackChannel = selectedChannel ?? channels.first(where: { $0.kind == .textChannel })
        let currentMember = currentUserID.flatMap {
            snapshot.membersByServerAndUserID[ServerMemberKey(serverID: serverID, userID: $0)]
        }
        let permissionPreview = Phase25PermissionResolver.resolve(
            server: server,
            channel: fallbackChannel,
            member: currentMember,
            currentUserID: currentUserID
        )
        let details = ServerSettingsDetails(
            server: server,
            channels: channels,
            members: members,
            runtimeLine: runtimeLine,
            capabilities: capabilities,
            permissionPreview: permissionPreview
        )
        let emojiManagementDisabledReason: String?
        if !capabilities.isConnectedForLiveActions {
            emojiManagementDisabledReason = "Reconnect to manage server emoji."
        } else if currentUserID == server.ownerID
            || permissionPreview.effectivePermissions.contains(.manageCustomisation) {
            emojiManagementDisabledReason = nil
        } else if permissionPreview.warnings.isEmpty {
            emojiManagementDisabledReason = "You do not have permission to manage server emoji."
        } else {
            emojiManagementDisabledReason = "Permission resolution is incomplete for server emoji management."
        }
        let memberItems = members.map { member in
            let user = snapshot.usersByID[member.id.userID]
            let display = identitySnapshots.resolvedDisplay(
                userID: member.id.userID,
                user: user,
                member: member,
                server: server
            )
            return MemberManagementItem(member: member, user: user, display: display, server: server)
        }
        let filteredMembers: [MemberManagementItem]
        if normalizedMemberQuery.isEmpty {
            filteredMembers = memberItems
        } else {
            filteredMembers = memberItems.filter { item in
                item.displayName.localizedCaseInsensitiveContains(normalizedMemberQuery)
                    || item.username.localizedCaseInsensitiveContains(normalizedMemberQuery)
                    || item.roles.contains { $0.name.localizedCaseInsensitiveContains(normalizedMemberQuery) }
            }
        }
        return ServerSettingsPresentationSnapshot(
            revision: revision,
            details: details,
            orderedRoles: server.roles.values.sorted { $0.rank < $1.rank },
            textChannels: channels.filter { $0.kind == .textChannel },
            permissionGroups: Array(Set(Phase26Permissions.editableKeys.map(\.group))).sorted(),
            emojiItems: snapshot.emojisByID.values
                .map(CustomEmojiDisplayItem.init(emoji:))
                .filter { $0.serverID == serverID }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending },
            emojiManagementDisabledReason: emojiManagementDisabledReason,
            memberItems: filteredMembers,
            timeoutItems: filteredMembers.filter { $0.timeoutSummary != nil }
        )
    }

    private static func orderedChannels(server: Server, snapshot: RealtimeSnapshot) -> [Channel] {
        if !server.channelIDs.isEmpty {
            return server.channelIDs.compactMap { snapshot.channelsByID[$0] }
        }
        return snapshot.channelsByID.values
            .filter { $0.serverID == server.id }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
}
