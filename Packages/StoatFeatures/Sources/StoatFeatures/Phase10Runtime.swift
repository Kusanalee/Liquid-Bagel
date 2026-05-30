import Foundation
import StoatAPI
import StoatModels

public struct TimelineViewportState: Hashable, Sendable {
    public var channelID: ChannelID?
    public var anchorMessageID: MessageID?
    public var selectedMessageID: MessageID?
    public var newestVisibleMessageID: MessageID?
    public var oldestVisibleMessageID: MessageID?
    public var isAtNewest: Bool
    public var hasNewerMessagesIndicator: Bool
    public var pendingScrollIntent: TimelineScrollIntent?

    public init(
        channelID: ChannelID? = nil,
        anchorMessageID: MessageID? = nil,
        selectedMessageID: MessageID? = nil,
        newestVisibleMessageID: MessageID? = nil,
        oldestVisibleMessageID: MessageID? = nil,
        isAtNewest: Bool = true,
        hasNewerMessagesIndicator: Bool = false,
        pendingScrollIntent: TimelineScrollIntent? = nil
    ) {
        self.channelID = channelID
        self.anchorMessageID = anchorMessageID
        self.selectedMessageID = selectedMessageID
        self.newestVisibleMessageID = newestVisibleMessageID
        self.oldestVisibleMessageID = oldestVisibleMessageID
        self.isAtNewest = isAtNewest
        self.hasNewerMessagesIndicator = hasNewerMessagesIndicator
        self.pendingScrollIntent = pendingScrollIntent
    }
}

public enum TimelineScrollIntent: Hashable, Sendable {
    case message(MessageID, anchor: TimelineScrollAnchor, reason: TimelineScrollReason)
    case newest(reason: TimelineScrollReason)
    case firstUnread(MessageID)
    case preservePositionAfterPrepend(previousOldestID: MessageID)
}

public enum TimelineScrollAnchor: Hashable, Sendable {
    case top
    case center
    case bottom
    case nearest
}

public enum TimelineScrollReason: Hashable, Sendable {
    case channelSelected
    case jumpCommand
    case newMessage
    case loadOlder
    case retrySend
    case editComplete
    case deleteFallback
    case unreadJump
}

public enum MessageFocusSource: Hashable, Sendable {
    case keyboard
    case mouse
    case contextMenu
    case quickSwitcher
    case scrollJump
    case realtimeFallback
}

public enum MessageFocusMode: Hashable, Sendable {
    case none
    case selected
    case editing
    case replying
    case actionMenu
    case failedRecovery
}

public struct MessageActionFocus: Hashable, Sendable {
    public var channelID: ChannelID?
    public var messageID: MessageID?
    public var source: MessageFocusSource
    public var mode: MessageFocusMode

    public init(
        channelID: ChannelID? = nil,
        messageID: MessageID? = nil,
        source: MessageFocusSource = .keyboard,
        mode: MessageFocusMode = .none
    ) {
        self.channelID = channelID
        self.messageID = messageID
        self.source = source
        self.mode = mode
    }
}

public struct TimelineSelection: Hashable, Sendable {
    public var focus: MessageActionFocus

    public init(channelID: ChannelID? = nil, messageID: MessageID? = nil, source: MessageFocusSource = .keyboard, mode: MessageFocusMode = .selected) {
        let resolvedMode: MessageFocusMode = messageID == nil ? .none : mode
        self.focus = MessageActionFocus(channelID: channelID, messageID: messageID, source: source, mode: resolvedMode)
    }

    public init(focus: MessageActionFocus) {
        self.focus = focus
    }

    public var channelID: ChannelID? {
        get { focus.channelID }
        set { focus.channelID = newValue }
    }

    public var messageID: MessageID? {
        get { focus.messageID }
        set {
            focus.messageID = newValue
            if newValue == nil {
                focus.mode = .none
            } else if focus.mode == .none {
                focus.mode = .selected
            }
        }
    }
}

public struct ReplyContext: Hashable, Sendable {
    public var channelID: ChannelID
    public var messageID: MessageID
    public var authorDisplayName: String
    public var contentPreview: String

    public init(channelID: ChannelID, messageID: MessageID, authorDisplayName: String, contentPreview: String) {
        self.channelID = channelID
        self.messageID = messageID
        self.authorDisplayName = authorDisplayName
        self.contentPreview = contentPreview
    }
}

public struct ComposerDraftState: Hashable, Sendable {
    public var channelID: ChannelID
    public var text: String
    public var replyContext: ReplyContext?
    public var shouldMentionReplyAuthor: Bool

    public init(channelID: ChannelID, text: String = "", replyContext: ReplyContext? = nil, shouldMentionReplyAuthor: Bool = true) {
        self.channelID = channelID
        self.text = text
        self.replyContext = replyContext
        self.shouldMentionReplyAuthor = shouldMentionReplyAuthor
    }
}

public struct TimelineViewportReducer: Sendable {
    public init() {}

    public func channelSelected(channelID: ChannelID?, messages: [TimelineMessage], firstUnreadMessageID: MessageID?) -> TimelineViewportState {
        let newest = messages.last?.message.id
        let target = firstUnreadMessageID.flatMap { unread in messages.contains { $0.message.id == unread } ? unread : nil } ?? newest
        return TimelineViewportState(
            channelID: channelID,
            anchorMessageID: target,
            selectedMessageID: target,
            newestVisibleMessageID: newest,
            oldestVisibleMessageID: messages.first?.message.id,
            isAtNewest: true,
            pendingScrollIntent: target.map { .message($0, anchor: .bottom, reason: .channelSelected) }
        )
    }

    public func jumpNewest(_ state: TimelineViewportState, newestMessageID: MessageID?) -> TimelineViewportState {
        var state = state
        guard let newestMessageID else { return state }
        state.selectedMessageID = newestMessageID
        state.anchorMessageID = newestMessageID
        state.isAtNewest = true
        state.hasNewerMessagesIndicator = false
        state.pendingScrollIntent = .newest(reason: .jumpCommand)
        return state
    }

    public func jumpFirstUnread(_ state: TimelineViewportState, unreadMessageID: MessageID?, loadedMessageIDs: Set<MessageID>) -> TimelineViewportState {
        var state = state
        guard let unreadMessageID, loadedMessageIDs.contains(unreadMessageID) else { return state }
        state.selectedMessageID = unreadMessageID
        state.anchorMessageID = unreadMessageID
        state.pendingScrollIntent = .firstUnread(unreadMessageID)
        return state
    }

    public func preserveAfterPrepend(_ state: TimelineViewportState, previousOldestID: MessageID?) -> TimelineViewportState {
        var state = state
        guard let previousOldestID else { return state }
        state.pendingScrollIntent = .preservePositionAfterPrepend(previousOldestID: previousOldestID)
        return state
    }

    public func newMessage(_ state: TimelineViewportState, newestMessageID: MessageID, isActiveChannel: Bool) -> TimelineViewportState {
        var state = state
        state.newestVisibleMessageID = newestMessageID
        guard isActiveChannel else { return state }
        if state.isAtNewest {
            state.selectedMessageID = newestMessageID
            state.anchorMessageID = newestMessageID
            state.pendingScrollIntent = .message(newestMessageID, anchor: .bottom, reason: .newMessage)
        } else {
            state.hasNewerMessagesIndicator = true
        }
        return state
    }

    public func keepVisible(_ state: TimelineViewportState, messageID: MessageID, reason: TimelineScrollReason) -> TimelineViewportState {
        var state = state
        state.selectedMessageID = messageID
        state.anchorMessageID = messageID
        state.pendingScrollIntent = .message(messageID, anchor: .nearest, reason: reason)
        return state
    }
}

public protocol ChannelAckSending: Sendable {
    func ackChannel(channelID: ChannelID, messageID: MessageID) async throws
}

public actor LiveChannelAckSender: ChannelAckSending {
    private let apiClient: any StoatAPIClient

    public init(apiClient: any StoatAPIClient) {
        self.apiClient = apiClient
    }

    public func ackChannel(channelID: ChannelID, messageID: MessageID) async throws {
        try await apiClient.ackChannel(channelID: channelID, messageID: messageID)
    }
}

public actor NoopChannelAckSender: ChannelAckSending {
    public init() {}
    public func ackChannel(channelID: ChannelID, messageID: MessageID) async throws {}
}

public actor RecordingChannelAckSender: ChannelAckSending {
    public private(set) var acks: [(ChannelID, MessageID)] = []

    public init() {}

    public func ackChannel(channelID: ChannelID, messageID: MessageID) async throws {
        acks.append((channelID, messageID))
    }
}
