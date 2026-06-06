import Foundation
import StoatModels
import StoatRealtime

public enum DMChannelClassifier {
    public static func isDirectMessageLike(_ channel: Channel) -> Bool {
        switch channel.kind {
        case .directMessage, .group, .savedMessages:
            return channel.serverID == nil
        case .textChannel, .voiceChannel, .unknown:
            return false
        }
    }
}

public enum UserDisplayResolver {
    public enum Source: String, Hashable, Sendable {
        case memberNickname
        case userDisplayName
        case username
        case botName
        case shortenedID
        case unknown
    }

    public static func displayName(user: User?, member: ServerMember? = nil, fallbackID: UserID? = nil) -> String {
        resolved(userID: fallbackID ?? user?.id ?? member?.id.userID, user: user, member: member).displayName
    }

    public static func resolved(userID: UserID?, user: User?, member: ServerMember? = nil) -> ResolvedUserDisplay {
        let resolvedUserID = userID ?? user?.id ?? member?.id.userID ?? UserID(rawValue: "unknown")
        if let nickname = trimmed(member?.nickname) {
            return ResolvedUserDisplay(userID: resolvedUserID, displayName: nickname, subtitle: usernameLine(user: user, fallbackID: resolvedUserID), avatarFile: member?.avatar ?? user?.avatar, fallbackInitials: initials(for: nickname), isFallback: false, source: .memberNickname, isBot: user?.bot != nil)
        }
        if let displayName = trimmed(user?.displayName) {
            return ResolvedUserDisplay(userID: resolvedUserID, displayName: displayName, subtitle: usernameLine(user: user, fallbackID: resolvedUserID), avatarFile: member?.avatar ?? user?.avatar, fallbackInitials: initials(for: displayName), isFallback: false, source: .userDisplayName, isBot: user?.bot != nil)
        }
        if let username = trimmed(user?.username) {
            let source: Source = user?.bot == nil ? .username : .botName
            return ResolvedUserDisplay(userID: resolvedUserID, displayName: username, subtitle: "@\(username)", avatarFile: member?.avatar ?? user?.avatar, fallbackInitials: initials(for: username), isFallback: false, source: source, isBot: user?.bot != nil)
        }
        if let userID {
            let shortened = shortenedID(userID)
            return ResolvedUserDisplay(userID: userID, displayName: shortened, subtitle: "Unknown user \(shortened)", avatarFile: member?.avatar ?? user?.avatar, fallbackInitials: initials(for: shortened), isFallback: true, source: .shortenedID)
        }
        return ResolvedUserDisplay(userID: resolvedUserID, displayName: "Unknown", subtitle: "Unknown user", avatarFile: member?.avatar ?? user?.avatar, fallbackInitials: "?", isFallback: true, source: .unknown)
    }

    public static func usernameLine(user: User?, fallbackID: UserID? = nil) -> String {
        if let username = trimmed(user?.username) {
            return "@\(username)"
        }
        if let fallbackID {
            return "Unknown user \(shortenedID(fallbackID))"
        }
        return "Unknown user"
    }

    public static func initials(for displayName: String) -> String {
        let words = displayName
            .split(whereSeparator: { $0.isWhitespace || $0 == "-" || $0 == "_" })
            .prefix(2)
            .compactMap(\.first)
        let value = String(words).uppercased()
        return value.isEmpty ? "?" : value
    }

    public static func shortenedID(_ id: UserID) -> String {
        let raw = id.rawValue
        guard raw.count > 10 else { return raw }
        return "\(raw.prefix(4))...\(raw.suffix(4))"
    }

    public static func systemFallbackName(_ id: UserID) -> String {
        "User \(shortenedID(id))"
    }

    private static func trimmed(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

public typealias ResolvedUserDisplaySource = UserDisplayResolver.Source

public struct ResolvedUserDisplay: Hashable, Sendable {
    public var userID: UserID
    public var displayName: String
    public var subtitle: String?
    public var avatarFile: File?
    public var fallbackInitials: String
    public var isFallback: Bool
    public var source: ResolvedUserDisplaySource
    public var isBot: Bool

    public init(
        userID: UserID,
        displayName: String,
        subtitle: String? = nil,
        avatarFile: File? = nil,
        fallbackInitials: String,
        isFallback: Bool,
        source: ResolvedUserDisplaySource,
        isBot: Bool = false
    ) {
        self.userID = userID
        self.displayName = displayName
        self.subtitle = subtitle
        self.avatarFile = avatarFile
        self.fallbackInitials = fallbackInitials
        self.isFallback = isFallback
        self.source = source
        self.isBot = isBot
    }
}

public struct ResolvedRoleColor: Hashable, Sendable {
    public var sourceRoleID: RoleID?
    public var rawHex: String?
    public var displayColorToken: String?
    public var isReadable: Bool
    public var fallbackReason: String?
    public var rawValue: String
    public var red: Double
    public var green: Double
    public var blue: Double
    public var isAdjustedForReadability: Bool

    public init?(rawValue: String?, highContrast: Bool = false, sourceRoleID: RoleID? = nil) {
        guard var hex = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !hex.isEmpty
        else { return nil }
        if highContrast { return nil }
        if hex.hasPrefix("#") {
            hex.removeFirst()
        }
        guard hex.count == 6, let value = Int(hex, radix: 16) else { return nil }
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        if luminance > 0.78 {
            self.red = red * 0.72
            self.green = green * 0.72
            self.blue = blue * 0.72
            self.isAdjustedForReadability = true
        } else {
            self.red = red
            self.green = green
            self.blue = blue
            self.isAdjustedForReadability = false
        }
        let normalized = "#\(hex.uppercased())"
        self.sourceRoleID = sourceRoleID
        self.rawHex = normalized
        self.displayColorToken = normalized
        self.isReadable = true
        self.fallbackReason = nil
        self.rawValue = normalized
    }
}

public enum RoleColorResolver {
    public static func resolve(member: ServerMember?, server: Server?, highContrast: Bool = false) -> ResolvedRoleColor? {
        guard let member, let server else { return nil }
        return member.roles
            .compactMap { server.roles[$0] }
            .sorted(by: rolePriority)
            .compactMap { role in
                ResolvedRoleColor(rawValue: role.colour, highContrast: highContrast, sourceRoleID: role.id)
            }
            .first
    }

    public static func sortedRoles(member: ServerMember?, server: Server?) -> [Role] {
        guard let member, let server else { return [] }
        return member.roles.compactMap { server.roles[$0] }.sorted(by: rolePriority)
    }

    private static func rolePriority(_ lhs: Role, _ rhs: Role) -> Bool {
        if lhs.rank != rhs.rank { return lhs.rank > rhs.rank }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}

public enum RightSidebarContext: Hashable, Sendable {
    case hidden
    case serverMembers(serverID: ServerID, channelID: ChannelID?)
    case directMessageParticipants(channelID: ChannelID)
    case groupDMParticipants(channelID: ChannelID)
    case homeSummary
    case friendsSummary
    case discoverSummary

    public var isPeopleContext: Bool {
        switch self {
        case .serverMembers, .directMessageParticipants, .groupDMParticipants:
            true
        case .hidden, .homeSummary, .friendsSummary, .discoverSummary:
            false
        }
    }
}

public struct MemberListItem: Hashable, Sendable, Identifiable {
    public var id: UserID { userID }
    public var userID: UserID
    public var user: User?
    public var member: ServerMember?
    public var displayName: String
    public var subtitle: String
    public var avatar: File?
    public var isBot: Bool
    public var isOnline: Bool
    public var statusText: String?
    public var roleIDs: [RoleID]
    public var primaryRole: Role?
    public var roleColor: ResolvedRoleColor?

    public init(userID: UserID, user: User?, member: ServerMember?, server: Server? = nil) {
        let display = UserDisplayResolver.resolved(userID: userID, user: user, member: member)
        self.userID = userID
        self.user = user
        self.member = member
        self.displayName = display.displayName
        self.subtitle = user?.status?.text ?? display.subtitle ?? UserDisplayResolver.usernameLine(user: user, fallbackID: userID)
        self.avatar = display.avatarFile
        self.isBot = user?.bot != nil
        self.isOnline = user?.online == true
        self.statusText = user?.status?.text
        self.roleIDs = member?.roles ?? []
        let roles = RoleColorResolver.sortedRoles(member: member, server: server)
        self.primaryRole = roles.first
        self.roleColor = RoleColorResolver.resolve(member: member, server: server)
    }
}

public struct CustomEmojiDisplayItem: Hashable, Sendable, Identifiable {
    public var id: EmojiID
    public var serverID: ServerID?
    public var name: String
    public var file: File
    public var shortcode: String
    public var animated: Bool

    public init(emoji: Emoji) {
        self.id = emoji.id
        if case let .server(serverID) = emoji.parent {
            self.serverID = serverID
        } else {
            self.serverID = nil
        }
        self.name = emoji.name
        self.shortcode = ":\(emoji.name):"
        self.animated = emoji.animated
        self.file = File(id: FileID(rawValue: emoji.id.rawValue), tag: "emojis", filename: "\(emoji.name).png", contentType: "image/png", size: 0)
    }
}

public struct MemberListGroup: Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var items: [MemberListItem]

    public init(id: String, title: String, items: [MemberListItem]) {
        self.id = id
        self.title = title
        self.items = items
    }
}

public struct MemberListPerformanceDiagnostics: Hashable, Sendable {
    public var totalMembers: Int
    public var visibleMemberEstimate: Int
    public var groupCount: Int
    public var avatarLoadQueueCount: Int
    public var lastGroupingDurationDescription: String?
    public var knownMemberCount: Int
    public var knownUserCount: Int
    public var missingUserCount: Int
    public var missingAvatarCount: Int
    public var renderedMemberCount: Int
    public var droppedMemberCount: Int
    public var droppedReasonSummary: String?

    public init(
        totalMembers: Int = 0,
        visibleMemberEstimate: Int = 0,
        groupCount: Int = 0,
        avatarLoadQueueCount: Int = 0,
        lastGroupingDurationDescription: String? = nil,
        knownMemberCount: Int = 0,
        knownUserCount: Int = 0,
        missingUserCount: Int = 0,
        missingAvatarCount: Int = 0,
        renderedMemberCount: Int = 0,
        droppedMemberCount: Int = 0,
        droppedReasonSummary: String? = nil
    ) {
        self.totalMembers = totalMembers
        self.visibleMemberEstimate = visibleMemberEstimate
        self.groupCount = groupCount
        self.avatarLoadQueueCount = avatarLoadQueueCount
        self.lastGroupingDurationDescription = lastGroupingDurationDescription
        self.knownMemberCount = knownMemberCount
        self.knownUserCount = knownUserCount
        self.missingUserCount = missingUserCount
        self.missingAvatarCount = missingAvatarCount
        self.renderedMemberCount = renderedMemberCount
        self.droppedMemberCount = droppedMemberCount
        self.droppedReasonSummary = droppedReasonSummary
    }
}

public enum MemberHydrationSource: String, Hashable, Sendable {
    case readyOnly = "Ready only"
    case restHydrated = "REST hydrated"
    case realtimeUpdate = "Realtime update"
}

public struct MemberHydrationDiagnostics: Hashable, Sendable {
    public var source: MemberHydrationSource
    public var lastMemberFetchServerID: ServerID?
    public var requestedCount: Int
    public var returnedCount: Int
    public var mergedMemberCount: Int
    public var mergedUserCount: Int
    public var missingUserCount: Int
    public var droppedCount: Int
    public var staleFetchDiscarded: Bool
    public var isLoading: Bool
    public var error: String?
    public var lastUpdatedAt: Date?

    public init(
        source: MemberHydrationSource = .readyOnly,
        lastMemberFetchServerID: ServerID? = nil,
        requestedCount: Int = 0,
        returnedCount: Int = 0,
        mergedMemberCount: Int = 0,
        mergedUserCount: Int = 0,
        missingUserCount: Int = 0,
        droppedCount: Int = 0,
        staleFetchDiscarded: Bool = false,
        isLoading: Bool = false,
        error: String? = nil,
        lastUpdatedAt: Date? = nil
    ) {
        self.source = source
        self.lastMemberFetchServerID = lastMemberFetchServerID
        self.requestedCount = requestedCount
        self.returnedCount = returnedCount
        self.mergedMemberCount = mergedMemberCount
        self.mergedUserCount = mergedUserCount
        self.missingUserCount = missingUserCount
        self.droppedCount = droppedCount
        self.staleFetchDiscarded = staleFetchDiscarded
        self.isLoading = isLoading
        self.error = error
        self.lastUpdatedAt = lastUpdatedAt
    }
}

public struct DMRouteDiagnostics: Hashable, Sendable {
    public var clickedChannelID: ChannelID?
    public var selectedConversationChannelID: ChannelID?
    public var selectedServerID: ServerID?
    public var messageLoadRequested: Bool
    public var lastLoadResult: String?
    public var composerTargetDescription: String?

    public init(
        clickedChannelID: ChannelID? = nil,
        selectedConversationChannelID: ChannelID? = nil,
        selectedServerID: ServerID? = nil,
        messageLoadRequested: Bool = false,
        lastLoadResult: String? = nil,
        composerTargetDescription: String? = nil
    ) {
        self.clickedChannelID = clickedChannelID
        self.selectedConversationChannelID = selectedConversationChannelID
        self.selectedServerID = selectedServerID
        self.messageLoadRequested = messageLoadRequested
        self.lastLoadResult = lastLoadResult
        self.composerTargetDescription = composerTargetDescription
    }
}

public enum ChannelContextMenuActionKind: String, Hashable, Sendable {
    case settings
    case createChannel
    case copyChannelID
    case deleteChannel
}

public struct ChannelContextMenuItem: Hashable, Sendable, Identifiable {
    public var id: ChannelContextMenuActionKind { kind }
    public var kind: ChannelContextMenuActionKind
    public var title: String
    public var systemImage: String
    public var disabledReason: String?
    public var isDestructive: Bool
    public var isDeveloperOnly: Bool

    public init(
        kind: ChannelContextMenuActionKind,
        title: String,
        systemImage: String,
        disabledReason: String? = nil,
        isDestructive: Bool = false,
        isDeveloperOnly: Bool = false
    ) {
        self.kind = kind
        self.title = title
        self.systemImage = systemImage
        self.disabledReason = disabledReason
        self.isDestructive = isDestructive
        self.isDeveloperOnly = isDeveloperOnly
    }
}

public enum MemberListDeriver {
    public static func groups(
        server: Server?,
        snapshot: RealtimeSnapshot,
        query: String = "",
        includeRoleGroups: Bool = true
    ) -> [MemberListGroup] {
        guard let server else { return [] }
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let members = snapshot.membersByServerAndUserID.values
            .filter { $0.id.serverID == server.id }
            .map { member in
                MemberListItem(userID: member.id.userID, user: snapshot.usersByID[member.id.userID], member: member, server: server)
            }
            .filter { item in
                guard !normalizedQuery.isEmpty else { return true }
                return item.displayName.localizedCaseInsensitiveContains(normalizedQuery)
                    || item.subtitle.localizedCaseInsensitiveContains(normalizedQuery)
                    || item.userID.rawValue.localizedCaseInsensitiveContains(normalizedQuery)
            }

        let sorted = members.sorted(by: memberSort)
        guard includeRoleGroups else {
            return fallbackGroups(items: sorted)
        }

        let orderedRoles = server.roles.values
            .sorted { lhs, rhs in
                if lhs.rank != rhs.rank { return lhs.rank > rhs.rank }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        var used: Set<UserID> = []
        var groups: [MemberListGroup] = []

        for role in orderedRoles where role.hoist {
            let items = sorted.filter { item in
                guard let member = item.member else { return false }
                return member.roles.contains(role.id)
            }
            guard !items.isEmpty else { continue }
            used.formUnion(items.map(\.userID))
            groups.append(MemberListGroup(id: "role-\(role.id.rawValue)", title: "\(role.name) - \(items.count)", items: items))
        }

        let bots = sorted.filter { $0.isBot && !used.contains($0.userID) }
        if !bots.isEmpty {
            used.formUnion(bots.map(\.userID))
            groups.append(MemberListGroup(id: "bots", title: "Bots - \(bots.count)", items: bots))
        }

        let remaining = sorted.filter { !used.contains($0.userID) }
        groups.append(contentsOf: fallbackGroups(items: remaining))
        return groups
    }

    private static func fallbackGroups(items: [MemberListItem]) -> [MemberListGroup] {
        let online = items.filter(\.isOnline)
        let offline = items.filter { !$0.isOnline && $0.user != nil }
        let unknown = items.filter { $0.user == nil }
        var groups: [MemberListGroup] = []
        if !online.isEmpty {
            groups.append(MemberListGroup(id: "online", title: "Online - \(online.count)", items: online))
        }
        if !offline.isEmpty {
            groups.append(MemberListGroup(id: "offline", title: "Offline - \(offline.count)", items: offline))
        }
        if !unknown.isEmpty {
            groups.append(MemberListGroup(id: "unknown", title: "Unknown - \(unknown.count)", items: unknown))
        }
        return groups
    }

    private static func memberSort(_ lhs: MemberListItem, _ rhs: MemberListItem) -> Bool {
        if lhs.isOnline != rhs.isOnline { return lhs.isOnline && !rhs.isOnline }
        let compared = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
        if compared != .orderedSame { return compared == .orderedAscending }
        return lhs.userID.rawValue < rhs.userID.rawValue
    }
}

public struct TimelinePerformanceDiagnostics: Hashable, Sendable {
    public var loadedMessageCount: Int
    public var renderedMessageEstimate: Int
    public var groupedMessageCount: Int
    public var markdownCacheCount: Int
    public var embedCacheCount: Int
    public var avatarLoadQueueCount: Int
    public var visibleRangeUpdateCount: Int
    public var lastSlowOperation: String?

    public init(
        loadedMessageCount: Int = 0,
        renderedMessageEstimate: Int = 0,
        groupedMessageCount: Int = 0,
        markdownCacheCount: Int = 0,
        embedCacheCount: Int = 0,
        avatarLoadQueueCount: Int = 0,
        visibleRangeUpdateCount: Int = 0,
        lastSlowOperation: String? = nil
    ) {
        self.loadedMessageCount = loadedMessageCount
        self.renderedMessageEstimate = renderedMessageEstimate
        self.groupedMessageCount = groupedMessageCount
        self.markdownCacheCount = markdownCacheCount
        self.embedCacheCount = embedCacheCount
        self.avatarLoadQueueCount = avatarLoadQueueCount
        self.visibleRangeUpdateCount = visibleRangeUpdateCount
        self.lastSlowOperation = lastSlowOperation
    }
}

public struct Phase28DogfoodDiagnostics: Hashable, Sendable {
    public var dmSelectionState: String
    public var dmLoadState: String
    public var missingUserCount: Int
    public var userHydrationQueueCount: Int
    public var notificationAuthorizationStatus: String
    public var notificationAuthorizerKind: String
    public var lastNotificationPermissionRequest: String?
    public var serverSettingsButtonState: String
    public var memberListDiagnostics: String
    public var timelinePerformanceDiagnostics: String

    public init(
        dmSelectionState: String = "none",
        dmLoadState: String = "idle",
        missingUserCount: Int = 0,
        userHydrationQueueCount: Int = 0,
        notificationAuthorizationStatus: String = "unknown",
        notificationAuthorizerKind: String = "unknown",
        lastNotificationPermissionRequest: String? = nil,
        serverSettingsButtonState: String = "unknown",
        memberListDiagnostics: String = "",
        timelinePerformanceDiagnostics: String = ""
    ) {
        self.dmSelectionState = dmSelectionState
        self.dmLoadState = dmLoadState
        self.missingUserCount = missingUserCount
        self.userHydrationQueueCount = userHydrationQueueCount
        self.notificationAuthorizationStatus = notificationAuthorizationStatus
        self.notificationAuthorizerKind = notificationAuthorizerKind
        self.lastNotificationPermissionRequest = lastNotificationPermissionRequest
        self.serverSettingsButtonState = serverSettingsButtonState
        self.memberListDiagnostics = memberListDiagnostics
        self.timelinePerformanceDiagnostics = timelinePerformanceDiagnostics
    }
}
