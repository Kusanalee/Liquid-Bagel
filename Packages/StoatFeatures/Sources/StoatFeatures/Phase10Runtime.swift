import Foundation
import StoatAPI
import StoatModels
import StoatPersistence

public struct TimelineViewportState: Hashable, Sendable {
    public var channelID: ChannelID?
    public var anchorMessageID: MessageID?
    public var selectedMessageID: MessageID?
    public var visibleRange: TimelineVisibleRange?
    public var newestVisibleMessageID: MessageID?
    public var oldestVisibleMessageID: MessageID?
    public var isAtNewest: Bool
    public var hasNewerMessagesIndicator: Bool
    public var pendingScrollIntent: TimelineScrollIntent?

    public init(
        channelID: ChannelID? = nil,
        anchorMessageID: MessageID? = nil,
        selectedMessageID: MessageID? = nil,
        visibleRange: TimelineVisibleRange? = nil,
        newestVisibleMessageID: MessageID? = nil,
        oldestVisibleMessageID: MessageID? = nil,
        isAtNewest: Bool = true,
        hasNewerMessagesIndicator: Bool = false,
        pendingScrollIntent: TimelineScrollIntent? = nil
    ) {
        self.channelID = channelID
        self.anchorMessageID = anchorMessageID
        self.selectedMessageID = selectedMessageID
        self.visibleRange = visibleRange
        self.newestVisibleMessageID = newestVisibleMessageID
        self.oldestVisibleMessageID = oldestVisibleMessageID
        self.isAtNewest = isAtNewest
        self.hasNewerMessagesIndicator = hasNewerMessagesIndicator
        self.pendingScrollIntent = pendingScrollIntent
    }
}

public struct TimelineVisibleRange: Hashable, Sendable {
    public var channelID: ChannelID
    public var firstVisibleMessageID: MessageID?
    public var lastVisibleMessageID: MessageID?
    public var visibleMessageIDs: [MessageID]
    public var updatedAt: Date

    public init(
        channelID: ChannelID,
        firstVisibleMessageID: MessageID? = nil,
        lastVisibleMessageID: MessageID? = nil,
        visibleMessageIDs: [MessageID] = [],
        updatedAt: Date = Date()
    ) {
        self.channelID = channelID
        self.firstVisibleMessageID = firstVisibleMessageID
        self.lastVisibleMessageID = lastVisibleMessageID
        self.visibleMessageIDs = visibleMessageIDs
        self.updatedAt = updatedAt
    }
}

public enum TimelineScrollIntent: Hashable, Sendable {
    case message(MessageID, anchor: TimelineScrollAnchor, reason: TimelineScrollReason)
    case newest(reason: TimelineScrollReason)
    case firstUnread(MessageID)
    case preservePositionAfterPrepend(previousOldestID: MessageID)
    case preserveVisibleAnchor(MessageID)
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
    public var attachments: [ComposerAttachmentDraft]

    public init(
        channelID: ChannelID,
        text: String = "",
        replyContext: ReplyContext? = nil,
        shouldMentionReplyAuthor: Bool = true,
        attachments: [ComposerAttachmentDraft] = []
    ) {
        self.channelID = channelID
        self.text = text
        self.replyContext = replyContext
        self.shouldMentionReplyAuthor = shouldMentionReplyAuthor
        self.attachments = attachments
    }
}

public enum UnreadRecoveryState: Hashable, Sendable {
    case none
    case targetLoaded(MessageID)
    case targetUnloaded(MessageID)
    case loadingToTarget(MessageID, attempts: Int)
    case targetMissing(MessageID)
    case failed(MessageID, String)
}

public struct ChannelLoadedMessageRange: Hashable, Sendable {
    public var oldestLoadedMessageID: MessageID?
    public var newestLoadedMessageID: MessageID?
    public var hasMoreBefore: Bool
    public var hasMoreAfter: Bool
    public var loadedAroundMessageID: MessageID?
    public var lastPaginationError: String?

    public init(
        oldestLoadedMessageID: MessageID? = nil,
        newestLoadedMessageID: MessageID? = nil,
        hasMoreBefore: Bool = false,
        hasMoreAfter: Bool = false,
        loadedAroundMessageID: MessageID? = nil,
        lastPaginationError: String? = nil
    ) {
        self.oldestLoadedMessageID = oldestLoadedMessageID
        self.newestLoadedMessageID = newestLoadedMessageID
        self.hasMoreBefore = hasMoreBefore
        self.hasMoreAfter = hasMoreAfter
        self.loadedAroundMessageID = loadedAroundMessageID
        self.lastPaginationError = lastPaginationError
    }
}

public struct FailedMessageRecoveryMetadata: Hashable, Sendable {
    public var originalContent: String
    public var originalNonce: String?
    public var attachmentIDs: [FileID]
    public var attachmentFiles: [File]
    public var replyContext: ReplyContext?
    public var mentionReply: Bool
    public var createdAt: Date
    public var lastAttemptAt: Date?
    public var attemptCount: Int
    public var lastError: String

    public init(
        originalContent: String,
        originalNonce: String? = nil,
        attachmentIDs: [FileID] = [],
        attachmentFiles: [File] = [],
        replyContext: ReplyContext? = nil,
        mentionReply: Bool = true,
        createdAt: Date = Date(),
        lastAttemptAt: Date? = nil,
        attemptCount: Int = 1,
        lastError: String
    ) {
        self.originalContent = originalContent
        self.originalNonce = originalNonce
        self.attachmentIDs = attachmentIDs
        self.attachmentFiles = attachmentFiles
        self.replyContext = replyContext
        self.mentionReply = mentionReply
        self.createdAt = createdAt
        self.lastAttemptAt = lastAttemptAt
        self.attemptCount = attemptCount
        self.lastError = lastError
    }

    public func retrying(at date: Date = Date()) -> Self {
        var copy = self
        copy.lastAttemptAt = date
        copy.attemptCount += 1
        return copy
    }

    public func edited(content: String) -> Self {
        var copy = self
        copy.originalContent = content
        return copy
    }
}

public enum MessageReferenceResolution: Hashable, Sendable {
    case loaded(Message)
    case deleted
    case forbidden
    case notFound
    case rateLimited
    case unavailable(String)
    case notSupported
}

public protocol MessageReferenceResolving: Sendable {
    func resolveReference(channelID: ChannelID, messageID: MessageID) async throws -> MessageReferenceResolution
}

public struct DisabledMessageReferenceResolver: MessageReferenceResolving {
    public init() {}
    public func resolveReference(channelID: ChannelID, messageID: MessageID) async throws -> MessageReferenceResolution {
        .notSupported
    }
}

public actor InMemoryMessageReferenceResolver: MessageReferenceResolving {
    private var messagesByChannelID: [ChannelID: [MessageID: Message]]
    private var deletedMessageIDs: Set<MessageID>

    public init(messagesByChannelID: [ChannelID: [Message]] = [:], deletedMessageIDs: Set<MessageID> = []) {
        self.messagesByChannelID = messagesByChannelID.mapValues { messages in
            Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
        }
        self.deletedMessageIDs = deletedMessageIDs
    }

    public func resolveReference(channelID: ChannelID, messageID: MessageID) async throws -> MessageReferenceResolution {
        if let message = messagesByChannelID[channelID]?[messageID] {
            return .loaded(message)
        }
        if deletedMessageIDs.contains(messageID) {
            return .deleted
        }
        return .unavailable("Original message unavailable")
    }
}

public struct TimelineDiagnostics: Hashable, Sendable {
    public var channelID: ChannelID?
    public var loadedMessageCount: Int
    public var oldestLoadedMessageID: MessageID?
    public var newestLoadedMessageID: MessageID?
    public var firstVisibleMessageID: MessageID?
    public var lastVisibleMessageID: MessageID?
    public var firstUnreadMessageID: MessageID?
    public var atNewest: Bool
    public var hasMoreBefore: Bool
    public var hasMoreAfter: Bool
    public var unreadRecoveryState: UnreadRecoveryState
    public var pendingReferenceFetchCount: Int
    public var failedReferenceFetchCount: Int
    public var pendingRetryCount: Int
    public var lastAckTargetMessageID: MessageID?
    public var lastAckResult: String?
    public var lastTimelineActionResult: String?
    public var lastRouteVerificationResult: String?
    public var tuningConfiguration: TimelineTuningConfiguration
    public var validationWarnings: [TimelineValidationWarning]

    public init(
        channelID: ChannelID? = nil,
        loadedMessageCount: Int = 0,
        oldestLoadedMessageID: MessageID? = nil,
        newestLoadedMessageID: MessageID? = nil,
        firstVisibleMessageID: MessageID? = nil,
        lastVisibleMessageID: MessageID? = nil,
        firstUnreadMessageID: MessageID? = nil,
        atNewest: Bool = true,
        hasMoreBefore: Bool = false,
        hasMoreAfter: Bool = false,
        unreadRecoveryState: UnreadRecoveryState = .none,
        pendingReferenceFetchCount: Int = 0,
        failedReferenceFetchCount: Int = 0,
        pendingRetryCount: Int = 0,
        lastAckTargetMessageID: MessageID? = nil,
        lastAckResult: String? = nil,
        lastTimelineActionResult: String? = nil,
        lastRouteVerificationResult: String? = nil,
        tuningConfiguration: TimelineTuningConfiguration = .defaults,
        validationWarnings: [TimelineValidationWarning] = []
    ) {
        self.channelID = channelID
        self.loadedMessageCount = loadedMessageCount
        self.oldestLoadedMessageID = oldestLoadedMessageID
        self.newestLoadedMessageID = newestLoadedMessageID
        self.firstVisibleMessageID = firstVisibleMessageID
        self.lastVisibleMessageID = lastVisibleMessageID
        self.firstUnreadMessageID = firstUnreadMessageID
        self.atNewest = atNewest
        self.hasMoreBefore = hasMoreBefore
        self.hasMoreAfter = hasMoreAfter
        self.unreadRecoveryState = unreadRecoveryState
        self.pendingReferenceFetchCount = pendingReferenceFetchCount
        self.failedReferenceFetchCount = failedReferenceFetchCount
        self.pendingRetryCount = pendingRetryCount
        self.lastAckTargetMessageID = lastAckTargetMessageID
        self.lastAckResult = lastAckResult
        self.lastTimelineActionResult = lastTimelineActionResult
        self.lastRouteVerificationResult = lastRouteVerificationResult
        self.tuningConfiguration = tuningConfiguration
        self.validationWarnings = validationWarnings
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
            visibleRange: channelID.map {
                TimelineVisibleRange(
                    channelID: $0,
                    firstVisibleMessageID: messages.first?.message.id,
                    lastVisibleMessageID: newest,
                    visibleMessageIDs: messages.map(\.message.id)
                )
            },
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

    public func visibleRangeChanged(
        _ state: TimelineViewportState,
        channelID: ChannelID,
        visibleMessageIDs: [MessageID],
        loadedMessageIDs: [MessageID],
        nearNewestMessageThreshold: Int = 2,
        updatedAt: Date = Date()
    ) -> TimelineViewportState {
        var state = state
        let orderedVisible = loadedMessageIDs.filter { visibleMessageIDs.contains($0) }
        guard state.visibleRange?.channelID != channelID || state.visibleRange?.visibleMessageIDs != orderedVisible else {
            return state
        }
        state.channelID = channelID
        state.visibleRange = TimelineVisibleRange(
            channelID: channelID,
            firstVisibleMessageID: orderedVisible.first,
            lastVisibleMessageID: orderedVisible.last,
            visibleMessageIDs: orderedVisible,
            updatedAt: updatedAt
        )
        state.oldestVisibleMessageID = orderedVisible.first
        state.newestVisibleMessageID = orderedVisible.last
        state.isAtNewest = Self.isNewestVisibleOrNearVisible(
            visibleMessageIDs: orderedVisible,
            loadedMessageIDs: loadedMessageIDs,
            trailingThreshold: nearNewestMessageThreshold
        )
        if state.isAtNewest {
            state.hasNewerMessagesIndicator = false
        }
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

    public static func isNewestVisibleOrNearVisible(visibleMessageIDs: [MessageID], loadedMessageIDs: [MessageID], trailingThreshold: Int = 2) -> Bool {
        guard let newest = loadedMessageIDs.last else { return true }
        guard !visibleMessageIDs.contains(newest) else { return true }
        guard let lastVisible = visibleMessageIDs.last,
              let visibleIndex = loadedMessageIDs.firstIndex(of: lastVisible)
        else {
            return false
        }
        let newestIndex = loadedMessageIDs.index(before: loadedMessageIDs.endIndex)
        return loadedMessageIDs.distance(from: visibleIndex, to: newestIndex) <= trailingThreshold
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
