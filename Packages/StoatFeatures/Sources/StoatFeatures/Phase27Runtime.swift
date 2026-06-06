import Foundation
import StoatModels
import StoatRealtime

public struct Phase27Diagnostics: Hashable, Sendable {
    public var selectedRouteDescription: String
    public var selectedChannelID: ChannelID?
    public var selectedChannelKind: String?
    public var dmLoadState: String?
    public var lastSystemEventRender: String?
    public var bannerPlacementState: String?
    public var lastReadAckDecision: String?
    public var lastReadAckError: String?
    public var embedRenderCount: Int
    public var markdownRenderFailures: Int
    public var pendingDropAttachmentCount: Int
    public var notificationStatus: String?

    public init(
        selectedRouteDescription: String = "home",
        selectedChannelID: ChannelID? = nil,
        selectedChannelKind: String? = nil,
        dmLoadState: String? = nil,
        lastSystemEventRender: String? = nil,
        bannerPlacementState: String? = nil,
        lastReadAckDecision: String? = nil,
        lastReadAckError: String? = nil,
        embedRenderCount: Int = 0,
        markdownRenderFailures: Int = 0,
        pendingDropAttachmentCount: Int = 0,
        notificationStatus: String? = nil
    ) {
        self.selectedRouteDescription = selectedRouteDescription
        self.selectedChannelID = selectedChannelID
        self.selectedChannelKind = selectedChannelKind
        self.dmLoadState = dmLoadState
        self.lastSystemEventRender = lastSystemEventRender
        self.bannerPlacementState = bannerPlacementState
        self.lastReadAckDecision = lastReadAckDecision
        self.lastReadAckError = lastReadAckError
        self.embedRenderCount = embedRenderCount
        self.markdownRenderFailures = markdownRenderFailures
        self.pendingDropAttachmentCount = pendingDropAttachmentCount
        self.notificationStatus = notificationStatus
    }
}

public enum Phase27SystemEventPresenter {
    public static func profileTarget(for message: Message) -> UserID? {
        guard let system = message.system else { return nil }
        let candidate = system.by ?? system.from ?? system.to ?? message.authorID
        guard !isSystemActor(candidate) else { return nil }
        return candidate
    }

    public static func text(for message: Message, usersByID: [UserID: User]) -> String {
        text(for: message, usersByID: usersByID, membersByServerAndUserID: [:], channel: nil)
    }

    public static func text(
        for message: Message,
        usersByID: [UserID: User],
        membersByServerAndUserID: [ServerMemberKey: ServerMember],
        channel: Channel?
    ) -> String {
        guard let system = message.system else { return message.content ?? "Message" }
        let serverID = channel?.serverID
        let actorID = system.by ?? system.from
        let targetID = system.to
        let actor = displayName(actorID, usersByID: usersByID, membersByServerAndUserID: membersByServerAndUserID, serverID: serverID)
        let target = displayName(targetID, usersByID: usersByID, membersByServerAndUserID: membersByServerAndUserID, serverID: serverID)
        let named = system.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackActor = actor ?? "Someone"
        let eventMember = displayName(
            actorID ?? targetID ?? message.authorID,
            usersByID: usersByID,
            membersByServerAndUserID: membersByServerAndUserID,
            serverID: serverID
        )

        switch system.kind {
        case .text:
            return nonEmpty(system.content) ?? "System event"
        case .userAdded:
            if let target { return "\(fallbackActor) added \(target)" }
            return "\(fallbackActor) added a member"
        case .userRemove:
            if let target { return "\(fallbackActor) removed \(target)" }
            return "\(fallbackActor) removed a member"
        case .userJoined:
            return "\(eventMember ?? "A member") joined"
        case .userLeft:
            return "\(eventMember ?? "A member") left"
        case .userKicked:
            if let target { return "\(fallbackActor) kicked \(target)" }
            return "\(fallbackActor) kicked a member"
        case .userBanned:
            if let target { return "\(fallbackActor) banned \(target)" }
            return "\(fallbackActor) banned a member"
        case .channelRenamed:
            if let named, !named.isEmpty { return "Channel renamed to \(named)" }
            return "Channel renamed"
        case .channelDescriptionChanged:
            return "Channel description changed"
        case .channelIconChanged:
            return "Channel icon changed"
        case .channelOwnershipChanged:
            if let target { return "Channel ownership transferred to \(target)" }
            return "Channel ownership changed"
        case .messagePinned:
            return "\(fallbackActor) pinned a message"
        case .messageUnpinned:
            return "\(fallbackActor) unpinned a message"
        case .callStarted:
            return "\(fallbackActor) started a call"
        case let .unknown(value):
            return "Unsupported system event: \(value)"
        }
    }

    private static func displayName(
        _ id: UserID?,
        usersByID: [UserID: User],
        membersByServerAndUserID: [ServerMemberKey: ServerMember],
        serverID: ServerID?
    ) -> String? {
        guard let id, !isSystemActor(id) else { return nil }
        let member = serverID.flatMap { membersByServerAndUserID[ServerMemberKey(serverID: $0, userID: id)] }
        let user = usersByID[id]
        if member != nil || user != nil {
            return UserDisplayResolver.displayName(user: user, member: member, fallbackID: id)
        }
        return nil
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private static func isSystemActor(_ id: UserID) -> Bool {
        let raw = id.rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty || raw == "0" || Set(raw).isSubset(of: Set("0"))
    }
}

public enum Phase27ReadAckDecision: Hashable, Sendable {
    case send(MessageID)
    case skip(String)

    public var diagnostic: String {
        switch self {
        case let .send(id):
            return "send \(id.rawValue)"
        case let .skip(reason):
            return "skip: \(reason)"
        }
    }
}

public enum Phase27SafeURL {
    public static func externalURL(_ raw: String?) -> URL? {
        guard let raw,
              let components = URLComponents(string: raw),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              components.host?.isEmpty == false
        else { return nil }
        return components.url
    }

    public static func display(_ raw: String?) -> String? {
        guard var components = raw.flatMap(URLComponents.init(string:)),
              components.host?.isEmpty == false
        else { return nil }
        components.query = nil
        components.fragment = nil
        return components.string
    }
}
