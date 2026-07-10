import Foundation
import Observation
import StoatModels
import StoatRealtime
import StoatUI

public struct TimelineRenderItem: Identifiable, Hashable, Sendable {
    /// The real message id -- unchanged across pending -> confirmed reconciliation, and the one
    /// preparation targeting, actions, acknowledgements, and navigation must keep using.
    public var id: MessageID { timelineMessage.message.id }
    public var timelineMessage: TimelineMessage
    public var groupID: String
    public var authorID: UserID
    public var showsHeader: Bool
    public var startsGroup: Bool
    /// A view-identity key that stays stable across pending -> confirmed -> realtime-echo
    /// reconciliation for a message the current user just sent (keyed by its nonce, which
    /// survives that transition), so SwiftUI doesn't tear down and rebuild the row -- and its
    /// avatar image view -- just because the real message id changed underneath it. Every other
    /// message (including all incoming messages from other authors) keeps using the real id.
    public var renderIdentity: String

    public init(
        timelineMessage: TimelineMessage,
        groupID: String,
        authorID: UserID,
        showsHeader: Bool,
        startsGroup: Bool,
        currentUserID: UserID? = nil
    ) {
        self.timelineMessage = timelineMessage
        self.groupID = groupID
        self.authorID = authorID
        self.showsHeader = showsHeader
        self.startsGroup = startsGroup
        if let nonce = timelineMessage.message.nonce, timelineMessage.message.authorID == currentUserID {
            self.renderIdentity = "local-send-\(nonce)"
        } else {
            self.renderIdentity = timelineMessage.message.id.rawValue
        }
    }
}

public enum TimelineRenderItemBuilder {
    public static func flatten(_ groups: [TimelineMessageGroup], currentUserID: UserID? = nil) -> [TimelineRenderItem] {
        groups.flatMap { group in
            group.messages.enumerated().map { index, message in
                TimelineRenderItem(
                    timelineMessage: message,
                    groupID: group.id,
                    authorID: group.authorID,
                    showsHeader: index == 0,
                    startsGroup: index == 0,
                    currentUserID: currentUserID
                )
            }
        }
    }
}

/// Timeline rows are identified in SwiftUI by `TimelineRenderItem.renderIdentity` (a `String`),
/// not by `MessageID`, so every `ScrollViewProxy.scrollTo` target must be resolved to the row's
/// actual render identity -- `scrollTo(MessageID)` silently matches nothing.
public enum TimelineScrollTargetResolver {
    public static func resolve(target: MessageID, renderItems: [TimelineRenderItem]) -> String {
        renderItems.first { $0.id == target }?.renderIdentity ?? target.rawValue
    }
}

public enum TimelineRowPreparationPriority: Int, Hashable, Sendable {
    case visible = 0
    case lookahead = 1
    case startup = 2
}

public struct TimelineRowPreparationTarget: Hashable, Sendable {
    public var messageID: MessageID
    public var priority: TimelineRowPreparationPriority

    public init(messageID: MessageID, priority: TimelineRowPreparationPriority) {
        self.messageID = messageID
        self.priority = priority
    }
}

public enum TimelineRowPreparationPlanner {
    public static let startupLimit = 32
    public static let lookaheadCount = 8

    public static func startupTargets(
        items: [TimelineRenderItem],
        anchorMessageID: MessageID?,
        limit: Int = startupLimit
    ) -> [TimelineRowPreparationTarget] {
        guard !items.isEmpty, limit > 0 else { return [] }
        let boundedLimit = min(limit, items.count)
        let start: Int
        if let anchorMessageID,
           let anchorIndex = items.firstIndex(where: { $0.id == anchorMessageID }) {
            let centered = anchorIndex - boundedLimit / 2
            start = min(max(0, centered), items.count - boundedLimit)
        } else {
            start = items.count - boundedLimit
        }
        return items[start..<(start + boundedLimit)].map {
            TimelineRowPreparationTarget(messageID: $0.id, priority: .startup)
        }
    }

    public static func visibleTargets(
        items: [TimelineRenderItem],
        visibleMessageIDs: Set<MessageID>,
        lookahead: Int = lookaheadCount
    ) -> [TimelineRowPreparationTarget] {
        guard !items.isEmpty, !visibleMessageIDs.isEmpty else { return [] }
        let visibleIndices = items.indices.filter { visibleMessageIDs.contains(items[$0].id) }
        guard !visibleIndices.isEmpty else { return [] }

        let visible = visibleIndices.map {
            TimelineRowPreparationTarget(messageID: items[$0].id, priority: .visible)
        }
        var lookaheadIndices: Set<Int> = []
        for index in visibleIndices {
            let lower = max(items.startIndex, index - max(0, lookahead))
            let upper = min(items.index(before: items.endIndex), index + max(0, lookahead))
            lookaheadIndices.formUnion(lower...upper)
        }
        lookaheadIndices.subtract(visibleIndices)
        let nearby = lookaheadIndices.sorted().map {
            TimelineRowPreparationTarget(messageID: items[$0].id, priority: .lookahead)
        }
        return visible + nearby
    }
}

public struct TimelineRowPreparationKey: Hashable, Sendable {
    public var channelID: ChannelID
    public var messageID: MessageID
    public var revision: Int

    public init(channelID: ChannelID, messageID: MessageID, revision: Int) {
        self.channelID = channelID
        self.messageID = messageID
        self.revision = revision
    }
}

public enum TimelineRowRevision {
    public static func value(
        for timelineMessage: TimelineMessage,
        inlineMediaRevision: Int = 0
    ) -> Int {
        var message = timelineMessage.message
        // Reaction chips are derived from the live/optimistic message on the main actor.
        // Excluding them prevents an echo from blanking and rebuilding prepared Markdown,
        // media, and actions for an otherwise unchanged row.
        message.reactions = [:]
        var hasher = Hasher()
        hasher.combine(message)
        hasher.combine(timelineMessage.status)
        if message.content?.contains(":") == true {
            hasher.combine(inlineMediaRevision)
        }
        return hasher.finalize()
    }
}

struct Phase60QueuedRowPreparation: Sendable {
    var key: TimelineRowPreparationKey
    var timelineMessage: TimelineMessage
    var priority: TimelineRowPreparationPriority
    var sequence: UInt64
    var snapshot: RealtimeSnapshot
    var identitySnapshots: Phase43IdentitySnapshotStore
    var imageDataByKey: [ImageCacheKey: Data]
    var currentUserID: UserID?
    var permissions: Permissions?
    var isRuntimeSendCapable: Bool
    var developerControlsEnabled: Bool
}

@MainActor
@Observable
public final class TimelineRowPresentationState: Identifiable {
    public let id: MessageID
    public let channelID: ChannelID
    public private(set) var revision: Int
    public private(set) var presentation: TimelineRowPresentation?

    public init(
        messageID: MessageID,
        channelID: ChannelID,
        revision: Int,
        presentation: TimelineRowPresentation? = nil
    ) {
        self.id = messageID
        self.channelID = channelID
        self.revision = revision
        self.presentation = presentation
    }

    public func request(revision: Int) {
        guard self.revision != revision else { return }
        self.revision = revision
        presentation = nil
    }

    public func publish(_ presentation: TimelineRowPresentation, revision: Int) {
        guard self.revision == revision else { return }
        self.presentation = presentation
    }
}

public struct Phase60Diagnostics: Hashable, Sendable {
    public var visibilityEventCount: Int
    public var coalescedViewportFlushCount: Int
    public var rowRequestCount: Int
    public var rowDedupeCount: Int
    public var rowCompletionCount: Int
    public var staleRowDiscardCount: Int
    public var activeSkeletonCount: Int
    public var maximumQueueDepth: Int

    public init(
        visibilityEventCount: Int = 0,
        coalescedViewportFlushCount: Int = 0,
        rowRequestCount: Int = 0,
        rowDedupeCount: Int = 0,
        rowCompletionCount: Int = 0,
        staleRowDiscardCount: Int = 0,
        activeSkeletonCount: Int = 0,
        maximumQueueDepth: Int = 0
    ) {
        self.visibilityEventCount = visibilityEventCount
        self.coalescedViewportFlushCount = coalescedViewportFlushCount
        self.rowRequestCount = rowRequestCount
        self.rowDedupeCount = rowDedupeCount
        self.rowCompletionCount = rowCompletionCount
        self.staleRowDiscardCount = staleRowDiscardCount
        self.activeSkeletonCount = activeSkeletonCount
        self.maximumQueueDepth = maximumQueueDepth
    }
}

public enum Phase60TimelineRowPreparer {
    public static func prepare(
        timelineMessage: TimelineMessage,
        snapshot: RealtimeSnapshot,
        identitySnapshots: Phase43IdentitySnapshotStore,
        imageDataByKey: [ImageCacheKey: Data],
        currentUserID: UserID?,
        permissions: Permissions?,
        isRuntimeSendCapable: Bool,
        developerControlsEnabled: Bool
    ) -> TimelineRowPresentation {
        let message = timelineMessage.message
        let assetContext = Phase52TimelineAssetContext(
            snapshot: snapshot,
            imageDataByKey: imageDataByKey
        )
        let customEmojiItems = assetContext.inlineCustomEmojiItems(for: message)
        let referenceItems = assetContext.inlineReferenceItems(
            for: message,
            identitySnapshots: identitySnapshots,
            currentUserID: currentUserID
        )
        let server = snapshot.channelsByID[message.channelID]?.serverID.flatMap {
            snapshot.serversByID[$0]
        }
        let channel = snapshot.channelsByID[message.channelID]
        let display = identitySnapshots.resolvedDisplay(
            userID: message.authorID,
            user: message.user ?? snapshot.usersByID[message.authorID],
            member: message.member,
            server: server
        )
        return TimelineRowPresentation(
            messageID: message.id,
            authorDisplay: display,
            isSystemEvent: message.system != nil,
            preparedMarkdownContent: message.content.map {
                MarkdownContentPreparer.prepare(
                    $0,
                    customEmojiItems: customEmojiItems,
                    referenceItems: referenceItems
                )
            },
            attachmentItems: assetContext.attachmentItems(for: message),
            customEmojiItems: customEmojiItems,
            referenceItems: referenceItems,
            embedItems: assetContext.embedItems(for: message),
            actionItems: Phase52TimelineInteractionPreparer.actionItems(
                for: timelineMessage,
                currentUserID: currentUserID,
                channel: channel,
                permissions: permissions,
                isRuntimeSendCapable: isRuntimeSendCapable,
                developerControlsEnabled: developerControlsEnabled
            ),
            reactionItems: assetContext.reactionItems(
                for: message,
                currentUserID: currentUserID
            ),
            systemEventPresentation: Phase52TimelineInteractionPreparer.systemEventPresentation(
                for: message,
                snapshot: snapshot,
                identitySnapshots: identitySnapshots
            ),
            mentionsCurrentUser: Phase52TimelineInteractionPreparer.mentionsCurrentUser(
                message,
                currentUserID: currentUserID
            )
        )
    }
}
