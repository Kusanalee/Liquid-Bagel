import Foundation
import StoatModels

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
    public static func text(for message: Message, usersByID: [UserID: User]) -> String {
        guard let system = message.system else { return message.content ?? "Message" }
        let actor = displayName(system.by ?? system.from, usersByID: usersByID)
        let target = displayName(system.to, usersByID: usersByID)
        let named = system.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackActor = actor ?? "Someone"

        switch system.kind {
        case .text:
            return nonEmpty(system.content) ?? "System event"
        case .userAdded:
            if let target { return "\(fallbackActor) added \(target)" }
            return "\(fallbackActor) added someone"
        case .userRemove:
            if let target { return "\(fallbackActor) removed \(target)" }
            return "\(fallbackActor) removed someone"
        case .userJoined:
            return "\(actor ?? target ?? "Someone") joined"
        case .userLeft:
            return "\(actor ?? target ?? "Someone") left"
        case .userKicked:
            if let target { return "\(fallbackActor) kicked \(target)" }
            return "\(fallbackActor) kicked someone"
        case .userBanned:
            if let target { return "\(fallbackActor) banned \(target)" }
            return "\(fallbackActor) banned someone"
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

    private static func displayName(_ id: UserID?, usersByID: [UserID: User]) -> String? {
        guard let id else { return nil }
        if let user = usersByID[id] {
            return user.displayName?.isEmpty == false ? user.displayName : user.username
        }
        return nil
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
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
