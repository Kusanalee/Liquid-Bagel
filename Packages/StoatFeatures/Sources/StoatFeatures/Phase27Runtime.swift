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
        let candidate: UserID?
        switch system.kind {
        case .userJoined, .userLeft:
            candidate = userID(fromSystemID: system.id) ?? system.by ?? system.from ?? system.to ?? message.authorID
        case .userAdded, .userRemove, .userKicked, .userBanned, .channelOwnershipChanged:
            candidate = userID(fromSystemID: system.id) ?? system.to ?? system.by ?? system.from ?? message.authorID
        default:
            candidate = system.by ?? system.from ?? system.to ?? message.authorID
        }
        guard let candidate else { return nil }
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

    public static func presentation(
        for message: Message,
        participantResolver: (UserID, SystemEventParticipantRole) -> SystemEventParticipant?
    ) -> SystemEventPresentation {
        guard let system = message.system else {
            return .text(message.content ?? "Message")
        }

        func participant(_ id: UserID?, role: SystemEventParticipantRole) -> SystemEventPresentationPiece? {
            guard let id, !isSystemActor(id),
                  let resolved = participantResolver(id, role),
                  !resolved.display.isFallback
            else { return nil }
            return .participant(resolved)
        }

        func actorPieces(actorID: UserID?, fallback: String, action: String, targetID: UserID?, targetFallback: String) -> SystemEventPresentation {
            var fallbackCount = 0
            var pieces: [SystemEventPresentationPiece] = []
            if let actor = participant(actorID, role: .actor) {
                pieces.append(actor)
            } else {
                pieces.append(.text(fallback))
                fallbackCount += 1
            }
            pieces.append(.text(action))
            if let target = participant(targetID, role: .target) {
                pieces.append(target)
            } else {
                pieces.append(.text(targetFallback))
                fallbackCount += 1
            }
            return SystemEventPresentation(pieces: pieces, fallbackCount: fallbackCount)
        }

        func affectedPieces(_ id: UserID?, action: String, fallback: String = "A member") -> SystemEventPresentation {
            if let affected = participant(id, role: .affected) {
                return SystemEventPresentation(pieces: [affected, .text(action)])
            }
            return SystemEventPresentation(pieces: [.text("\(fallback)\(action)")], fallbackCount: 1)
        }

        let actorID = system.by ?? system.from
        let affectedID = userID(fromSystemID: system.id) ?? actorID ?? system.to ?? message.authorID
        let targetID = userID(fromSystemID: system.id) ?? system.to
        let named = system.name?.trimmingCharacters(in: .whitespacesAndNewlines)

        switch system.kind {
        case .text:
            return .text(nonEmpty(system.content) ?? "System event")
        case .userAdded:
            return actorPieces(actorID: actorID ?? message.authorID, fallback: "Someone", action: " added ", targetID: targetID, targetFallback: "a member")
        case .userRemove:
            return actorPieces(actorID: actorID ?? message.authorID, fallback: "Someone", action: " removed ", targetID: targetID, targetFallback: "a member")
        case .userJoined:
            return affectedPieces(affectedID, action: " joined")
        case .userLeft:
            return affectedPieces(affectedID, action: " left")
        case .userKicked:
            return actorPieces(actorID: actorID ?? message.authorID, fallback: "Someone", action: " kicked ", targetID: targetID, targetFallback: "a member")
        case .userBanned:
            return actorPieces(actorID: actorID ?? message.authorID, fallback: "Someone", action: " banned ", targetID: targetID, targetFallback: "a member")
        case .channelRenamed:
            if let named, !named.isEmpty { return .text("Channel renamed to \(named)") }
            return .text("Channel renamed")
        case .channelDescriptionChanged:
            return .text("Channel description changed")
        case .channelIconChanged:
            return .text("Channel icon changed")
        case .channelOwnershipChanged:
            if let target = participant(targetID, role: .target) {
                return SystemEventPresentation(pieces: [.text("Channel ownership transferred to "), target])
            }
            return .text("Channel ownership changed", fallbackCount: 1)
        case .messagePinned:
            if let actor = participant(actorID ?? message.authorID, role: .actor) {
                return SystemEventPresentation(pieces: [actor, .text(" pinned a message")])
            }
            return .text("Someone pinned a message", fallbackCount: 1)
        case .messageUnpinned:
            if let actor = participant(actorID ?? message.authorID, role: .actor) {
                return SystemEventPresentation(pieces: [actor, .text(" unpinned a message")])
            }
            return .text("Someone unpinned a message", fallbackCount: 1)
        case .callStarted:
            if let actor = participant(actorID ?? message.authorID, role: .actor) {
                return SystemEventPresentation(pieces: [actor, .text(" started a call")])
            }
            return .text("Someone started a call", fallbackCount: 1)
        case let .unknown(value):
            return .text("Unsupported system event: \(value)")
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

    private static func userID(fromSystemID value: String?) -> UserID? {
        guard let trimmed = nonEmpty(value) else { return nil }
        let userID = UserID(rawValue: trimmed)
        guard !isSystemActor(userID) else { return nil }
        return userID
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
