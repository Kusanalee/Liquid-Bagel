import Foundation
import StoatModels
import StoatPersistence
import StoatRealtime

public enum FriendsTab: String, CaseIterable, Hashable, Sendable {
    case online
    case all
    case pending
    case blocked
    case addFriend

    public var title: String {
        switch self {
        case .online: "Online"
        case .all: "All"
        case .pending: "Pending"
        case .blocked: "Blocked"
        case .addFriend: "Add Friend"
        }
    }
}

public struct FriendListItem: Identifiable, Hashable, Sendable {
    public var id: UserID { user.id }
    public var user: User
    public var relationshipStatus: RelationshipStatus
    public var dmChannelID: ChannelID?
    public var lastMessagePreview: String?
    public var unreadCount: Int
    public var mentionCount: Int
    public var isOnline: Bool

    public init(
        user: User,
        relationshipStatus: RelationshipStatus,
        dmChannelID: ChannelID? = nil,
        lastMessagePreview: String? = nil,
        unreadCount: Int = 0,
        mentionCount: Int = 0,
        isOnline: Bool = false
    ) {
        self.user = user
        self.relationshipStatus = relationshipStatus
        self.dmChannelID = dmChannelID
        self.lastMessagePreview = lastMessagePreview
        self.unreadCount = unreadCount
        self.mentionCount = mentionCount
        self.isOnline = isOnline
    }
}

public struct DirectMessageListItem: Identifiable, Hashable, Sendable {
    public var id: ChannelID { channel.id }
    public var channel: Channel
    public var participants: [User]
    public var displayName: String
    public var avatarUser: User?
    public var groupIcon: File?
    public var groupMemberCount: Int
    public var lastMessagePreview: String?
    public var unreadCount: Int
    public var mentionCount: Int
    public var isMuted: Bool
    public var isSelected: Bool
    public var hasMissingRecipientUsers: Bool
    public var usesRawIDFallback: Bool

    public init(
        channel: Channel,
        participants: [User],
        displayName: String,
        avatarUser: User? = nil,
        groupIcon: File? = nil,
        groupMemberCount: Int = 0,
        lastMessagePreview: String? = nil,
        unreadCount: Int = 0,
        mentionCount: Int = 0,
        isMuted: Bool = false,
        isSelected: Bool = false,
        hasMissingRecipientUsers: Bool = false,
        usesRawIDFallback: Bool = false
    ) {
        self.channel = channel
        self.participants = participants
        self.displayName = displayName
        self.avatarUser = avatarUser
        self.groupIcon = groupIcon
        self.groupMemberCount = groupMemberCount
        self.lastMessagePreview = lastMessagePreview
        self.unreadCount = unreadCount
        self.mentionCount = mentionCount
        self.isMuted = isMuted
        self.isSelected = isSelected
        self.hasMissingRecipientUsers = hasMissingRecipientUsers
        self.usesRawIDFallback = usesRawIDFallback
    }
}

public enum RelationshipActionKind: String, Hashable, Sendable {
    case accept
    case deny
    case remove
    case block
    case unblock
}

public struct PendingRelationshipAction: Identifiable, Hashable, Sendable {
    public var id: String { "\(kind.rawValue)-\(userID.rawValue)" }
    public var kind: RelationshipActionKind
    public var userID: UserID

    public init(kind: RelationshipActionKind, userID: UserID) {
        self.kind = kind
        self.userID = userID
    }

    public var confirmationTitle: String {
        switch kind {
        case .accept: "Accept friend request?"
        case .deny: "Deny friend request?"
        case .remove: "Remove friend?"
        case .block: "Block user?"
        case .unblock: "Unblock user?"
        }
    }

    public var buttonTitle: String {
        switch kind {
        case .accept: "Accept"
        case .deny: "Deny"
        case .remove: "Remove Friend"
        case .block: "Block"
        case .unblock: "Unblock"
        }
    }

    public var isDestructive: Bool {
        switch kind {
        case .accept, .unblock: false
        case .deny, .remove, .block: true
        }
    }
}

public enum Phase22Derivations {
    public static func relationshipStatus(for user: User, currentUserID: UserID?, currentUser: User?) -> RelationshipStatus {
        if let currentUserID, user.id == currentUserID { return .user }
        if let related = currentUser?.relations.first(where: { $0.id == user.id }) {
            return related.status
        }
        return user.relationship
    }

    /// O(1) variant used by bulk derivations: looks up the precomputed relationship map
    /// instead of scanning `currentUser.relations` per user.
    private static func relationshipStatus(
        for user: User,
        currentUserID: UserID?,
        relationshipByUserID: [UserID: RelationshipStatus]
    ) -> RelationshipStatus {
        if let currentUserID, user.id == currentUserID { return .user }
        if let status = relationshipByUserID[user.id] { return status }
        return user.relationship
    }

    /// Builds a `[UserID: RelationshipStatus]` from `currentUser.relations` once so callers
    /// avoid an O(relations) scan per user. Mirrors `first(where:)` precedence (first wins).
    private static func relationshipStatusMap(currentUser: User?) -> [UserID: RelationshipStatus] {
        guard let relations = currentUser?.relations else { return [:] }
        return Dictionary(relations.map { ($0.id, $0.status) }, uniquingKeysWith: { first, _ in first })
    }

    /// Indexes direct-message channels by the *other* recipient once, replacing the
    /// per-user O(channels) scan in `directMessageChannel(containing:)`. First match wins,
    /// matching the previous `.first { … }` semantics for the common one-channel-per-pair case.
    private static func directMessageChannelsByRecipient(
        currentUserID: UserID?,
        snapshot: RealtimeSnapshot
    ) -> [UserID: Channel] {
        var map: [UserID: Channel] = [:]
        for channel in snapshot.channelsByID.values where channel.kind == .directMessage {
            if let currentUserID, !channel.recipients.contains(currentUserID) { continue }
            for recipient in channel.recipients where recipient != currentUserID {
                if map[recipient] == nil { map[recipient] = channel }
            }
        }
        return map
    }

    public static func friendItems(
        snapshot: RealtimeSnapshot,
        currentUserID: UserID?,
        currentUser: User?,
        localReadStates: [ChannelID: LocalReadState] = [:]
    ) -> [FriendListItem] {
        let dmChannelsByRecipient = directMessageChannelsByRecipient(currentUserID: currentUserID, snapshot: snapshot)
        let relationshipByUserID = relationshipStatusMap(currentUser: currentUser)
        let items: [FriendListItem] = snapshot.usersByID.values
            .filter { user in currentUserID.map { user.id != $0 } ?? true }
            .map { user in
                let dm = dmChannelsByRecipient[user.id]
                let counts = unreadCounts(channelID: dm?.id, snapshot: snapshot, localReadStates: localReadStates)
                return FriendListItem(
                    user: user,
                    relationshipStatus: relationshipStatus(for: user, currentUserID: currentUserID, relationshipByUserID: relationshipByUserID),
                    dmChannelID: dm?.id,
                    lastMessagePreview: lastMessagePreview(channelID: dm?.id, snapshot: snapshot),
                    unreadCount: counts.unread,
                    mentionCount: counts.mentions,
                    isOnline: user.online
                )
            }
        // Decorate-sort-undecorate: compute each display name once instead of twice per comparison.
        let decorated: [(item: FriendListItem, sortKey: String)] = items.map { ($0, displayName($0.user)) }
        return decorated
            .sorted { $0.sortKey.localizedCaseInsensitiveCompare($1.sortKey) == .orderedAscending }
            .map(\.item)
    }

    public static func friendItems(
        for tab: FriendsTab,
        snapshot: RealtimeSnapshot,
        currentUserID: UserID?,
        currentUser: User?,
        localReadStates: [ChannelID: LocalReadState] = [:]
    ) -> [FriendListItem] {
        let items = friendItems(snapshot: snapshot, currentUserID: currentUserID, currentUser: currentUser, localReadStates: localReadStates)
        switch tab {
        case .online:
            return items.filter { $0.relationshipStatus == .friend && $0.isOnline }
        case .all:
            return items.filter { $0.relationshipStatus == .friend }
        case .pending:
            return items.filter { $0.relationshipStatus == .incoming || $0.relationshipStatus == .outgoing }
        case .blocked:
            return items.filter { $0.relationshipStatus == .blocked }
        case .addFriend:
            return []
        }
    }

    public static func pendingIncomingCount(snapshot: RealtimeSnapshot, currentUserID: UserID?, currentUser: User?) -> Int {
        friendItems(snapshot: snapshot, currentUserID: currentUserID, currentUser: currentUser)
            .filter { $0.relationshipStatus == .incoming }
            .count
    }

    public static func directMessageItems(
        snapshot: RealtimeSnapshot,
        currentUserID: UserID?,
        localReadStates: [ChannelID: LocalReadState] = [:],
        notificationPreferences: NotificationPreferences = .defaults,
        selectedChannelID: ChannelID? = nil
    ) -> [DirectMessageListItem] {
        snapshot.channelsByID.values
            .filter(DMChannelClassifier.isDirectMessageLike)
            .map { channel in
                let visibleRecipientIDs = visibleRecipientIDs(for: channel, currentUserID: currentUserID)
                let visibleParticipants = visibleRecipientIDs.compactMap { snapshot.usersByID[$0] }
                let counts = unreadCounts(channelID: channel.id, snapshot: snapshot, localReadStates: localReadStates)
                let missingRecipientUsers = visibleRecipientIDs.filter { snapshot.usersByID[$0] == nil }
                let usesRawIDFallback = !missingRecipientUsers.isEmpty && channel.kind != .savedMessages
                return DirectMessageListItem(
                    channel: channel,
                    participants: visibleParticipants,
                    displayName: directMessageDisplayName(
                        channel: channel,
                        participants: visibleParticipants,
                        currentUserID: currentUserID,
                        missingRecipientCount: missingRecipientUsers.count
                    ),
                    avatarUser: visibleParticipants.first,
                    groupIcon: channel.kind == .group ? channel.icon : nil,
                    groupMemberCount: groupMemberCount(for: channel, currentUserID: currentUserID),
                    lastMessagePreview: lastMessagePreview(channelID: channel.id, snapshot: snapshot),
                    unreadCount: counts.unread,
                    mentionCount: counts.mentions,
                    isMuted: notificationPreferences.preference(for: channel.id).isMuted,
                    isSelected: selectedChannelID == channel.id,
                    hasMissingRecipientUsers: !missingRecipientUsers.isEmpty,
                    usesRawIDFallback: usesRawIDFallback
                )
            }
            .sorted { lhs, rhs in
                if lhs.channel.kind == .savedMessages, rhs.channel.kind != .savedMessages { return true }
                if rhs.channel.kind == .savedMessages, lhs.channel.kind != .savedMessages { return false }
                if lhs.mentionCount != rhs.mentionCount { return lhs.mentionCount > rhs.mentionCount }
                if lhs.unreadCount != rhs.unreadCount { return lhs.unreadCount > rhs.unreadCount }
                let leftLast = lhs.channel.lastMessageID?.rawValue ?? ""
                let rightLast = rhs.channel.lastMessageID?.rawValue ?? ""
                if leftLast != rightLast { return leftLast > rightLast }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
    }

    public static func displayName(_ user: User) -> String {
        user.displayName?.isEmpty == false ? user.displayName! : user.username
    }

    public static func safePreview(_ message: Message) -> String {
        let content = (message.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !content.isEmpty {
            return sanitize(content)
        }
        let count = message.attachments?.count ?? 0
        if count > 0 {
            return count == 1 ? "1 attachment" : "\(count) attachments"
        }
        return "Message"
    }

    private static func visibleRecipientIDs(for channel: Channel, currentUserID: UserID?) -> [UserID] {
        if channel.kind == .savedMessages {
            return [currentUserID ?? channel.userID].compactMap { $0 }
        }
        let ids = currentUserID.map { id in channel.recipients.filter { $0 != id } } ?? channel.recipients
        return ids
    }

    private static func groupMemberCount(for channel: Channel, currentUserID: UserID?) -> Int {
        guard channel.kind == .group else { return 0 }
        var ids = Set(channel.recipients)
        if let currentUserID {
            ids.insert(currentUserID)
        }
        return ids.count
    }

    private static func directMessageDisplayName(
        channel: Channel,
        participants: [User],
        currentUserID: UserID?,
        missingRecipientCount: Int
    ) -> String {
        switch channel.kind {
        case .savedMessages:
            return "Saved Notes"
        case .group:
            if let name = channel.name, !name.isEmpty { return name }
            let names = participants.map { UserDisplayResolver.displayName(user: $0, fallbackID: $0.id) }
            if !names.isEmpty { return names.joined(separator: ", ") }
            let count = groupMemberCount(for: channel, currentUserID: currentUserID)
            return count > 0 ? "Group DM (\(count))" : "Group DM"
        case .directMessage:
            if let participant = participants.first {
                return UserDisplayResolver.displayName(user: participant, fallbackID: participant.id)
            }
            return missingRecipientCount > 0 ? "Unknown User" : channel.displayName
        default:
            return channel.displayName
        }
    }

    private static func unreadCounts(channelID: ChannelID?, snapshot: RealtimeSnapshot, localReadStates: [ChannelID: LocalReadState]) -> (unread: Int, mentions: Int) {
        guard let channelID else { return (0, 0) }
        let remote = snapshot.unreadsByChannelID[channelID]
        let local = localReadStates[channelID]
        let unread = max(remote?.lastMessageID == nil ? 0 : 1, local?.unreadCount ?? 0)
        let mentions = (remote?.mentions.count ?? 0) + (local?.mentionCount ?? 0)
        return (unread, mentions)
    }

    private static func lastMessagePreview(channelID: ChannelID?, snapshot: RealtimeSnapshot) -> String? {
        guard let channelID,
              let message = snapshot.messagesByChannelID[channelID]?.max(by: { lhs, rhs in
                  ChannelMessageHistoryReducer.messageIDChronologicalSort(lhs.id, rhs.id)
              })
        else { return nil }
        return safePreview(message)
    }

    /// Precompiled once at first use instead of recompiling three regexes on every preview.
    private static let sanitizeRules: [(regex: NSRegularExpression, template: String)] = {
        let specs: [(pattern: String, template: String)] = [
            (#"https?://\S+"#, "[redacted-url]"),
            (#"/(?:Users|tmp|var|private|Volumes)/[^\s,;\)]+"#, "[redacted-path]"),
            (#"(?i)(authorization|token|session|password|secret|auth)[\s:=]+"?[^"\s]+"?"#, "$1=[redacted]")
        ]
        return specs.compactMap { spec in
            guard let regex = try? NSRegularExpression(pattern: spec.pattern) else { return nil }
            return (regex, spec.template)
        }
    }()

    private static func sanitize(_ value: String) -> String {
        var output = value
        for rule in sanitizeRules {
            let range = NSRange(output.startIndex..., in: output)
            output = rule.regex.stringByReplacingMatches(in: output, options: [], range: range, withTemplate: rule.template)
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
