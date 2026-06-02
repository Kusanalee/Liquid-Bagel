import Foundation
import StoatModels
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
    public var lastMessagePreview: String?
    public var unreadCount: Int
    public var mentionCount: Int

    public init(
        channel: Channel,
        participants: [User],
        displayName: String,
        avatarUser: User? = nil,
        lastMessagePreview: String? = nil,
        unreadCount: Int = 0,
        mentionCount: Int = 0
    ) {
        self.channel = channel
        self.participants = participants
        self.displayName = displayName
        self.avatarUser = avatarUser
        self.lastMessagePreview = lastMessagePreview
        self.unreadCount = unreadCount
        self.mentionCount = mentionCount
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

    public static func friendItems(
        snapshot: RealtimeSnapshot,
        currentUserID: UserID?,
        currentUser: User?,
        localReadStates: [ChannelID: LocalReadState] = [:]
    ) -> [FriendListItem] {
        snapshot.usersByID.values
            .filter { user in currentUserID.map { user.id != $0 } ?? true }
            .map { user in
                let dm = directMessageChannel(containing: user.id, currentUserID: currentUserID, snapshot: snapshot)
                let counts = unreadCounts(channelID: dm?.id, snapshot: snapshot, localReadStates: localReadStates)
                return FriendListItem(
                    user: user,
                    relationshipStatus: relationshipStatus(for: user, currentUserID: currentUserID, currentUser: currentUser),
                    dmChannelID: dm?.id,
                    lastMessagePreview: lastMessagePreview(channelID: dm?.id, snapshot: snapshot),
                    unreadCount: counts.unread,
                    mentionCount: counts.mentions,
                    isOnline: user.online
                )
            }
            .sorted { lhs, rhs in
                displayName(lhs.user).localizedCaseInsensitiveCompare(displayName(rhs.user)) == .orderedAscending
            }
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
        localReadStates: [ChannelID: LocalReadState] = [:]
    ) -> [DirectMessageListItem] {
        snapshot.channelsByID.values
            .filter { $0.kind == .directMessage || $0.kind == .group || $0.kind == .savedMessages }
            .map { channel in
                let participants = channel.recipients.compactMap { snapshot.usersByID[$0] }
                let visibleParticipants = currentUserID.map { id in participants.filter { $0.id != id } } ?? participants
                let counts = unreadCounts(channelID: channel.id, snapshot: snapshot, localReadStates: localReadStates)
                return DirectMessageListItem(
                    channel: channel,
                    participants: visibleParticipants,
                    displayName: directMessageDisplayName(channel: channel, participants: visibleParticipants, currentUserID: currentUserID),
                    avatarUser: visibleParticipants.first,
                    lastMessagePreview: lastMessagePreview(channelID: channel.id, snapshot: snapshot),
                    unreadCount: counts.unread,
                    mentionCount: counts.mentions
                )
            }
            .sorted { lhs, rhs in
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

    private static func directMessageChannel(containing userID: UserID, currentUserID: UserID?, snapshot: RealtimeSnapshot) -> Channel? {
        snapshot.channelsByID.values.first { channel in
            guard channel.kind == .directMessage else { return false }
            guard channel.recipients.contains(userID) else { return false }
            if let currentUserID {
                return channel.recipients.contains(currentUserID)
            }
            return true
        }
    }

    private static func directMessageDisplayName(channel: Channel, participants: [User], currentUserID: UserID?) -> String {
        switch channel.kind {
        case .savedMessages:
            return "Saved Notes"
        case .group:
            if let name = channel.name, !name.isEmpty { return name }
            return participants.map(displayName).joined(separator: ", ")
        case .directMessage:
            return participants.first.map(displayName) ?? channel.displayName
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
              let message = snapshot.messagesByChannelID[channelID]?.sorted(by: { lhs, rhs in
                  ChannelMessageHistoryReducer.messageIDChronologicalSort(lhs.id, rhs.id)
              }).last
        else { return nil }
        return safePreview(message)
    }

    private static func sanitize(_ value: String) -> String {
        var output = value
        let replacements = [
            (#"https?://\S+"#, "[redacted-url]"),
            (#"/(?:Users|tmp|var|private|Volumes)/[^\s,;\)]+"#, "[redacted-path]"),
            (#"(?i)(authorization|token|session|password|secret|auth)[\s:=]+"?[^"\s]+"?"#, "$1=[redacted]")
        ]
        for (pattern, replacement) in replacements {
            output = output.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
