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
    public static func displayName(user: User?, member: ServerMember? = nil, fallbackID: UserID? = nil) -> String {
        if let nickname = trimmed(member?.nickname) { return nickname }
        if let displayName = trimmed(user?.displayName) { return displayName }
        if let username = trimmed(user?.username) { return username }
        if let fallbackID { return shortenedID(fallbackID) }
        return "Unknown"
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

    private static func trimmed(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
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

    public init(userID: UserID, user: User?, member: ServerMember?) {
        self.userID = userID
        self.user = user
        self.member = member
        self.displayName = UserDisplayResolver.displayName(user: user, member: member, fallbackID: userID)
        self.subtitle = user?.status?.text ?? UserDisplayResolver.usernameLine(user: user, fallbackID: userID)
        self.avatar = member?.avatar ?? user?.avatar
        self.isBot = user?.bot != nil
        self.isOnline = user?.online == true
        self.statusText = user?.status?.text
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

    public init(
        totalMembers: Int = 0,
        visibleMemberEstimate: Int = 0,
        groupCount: Int = 0,
        avatarLoadQueueCount: Int = 0,
        lastGroupingDurationDescription: String? = nil
    ) {
        self.totalMembers = totalMembers
        self.visibleMemberEstimate = visibleMemberEstimate
        self.groupCount = groupCount
        self.avatarLoadQueueCount = avatarLoadQueueCount
        self.lastGroupingDurationDescription = lastGroupingDurationDescription
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
                MemberListItem(userID: member.id.userID, user: snapshot.usersByID[member.id.userID], member: member)
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
