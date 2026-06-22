import Foundation
import StoatModels

public enum MessageNavigationSource: String, Codable, Hashable, Sendable, CaseIterable {
    case loadedSearch
    case remoteSearch
    case pinnedMessage
    case replyPreview
    case unreadMarker
    case notification
    case command
    case directRoute
}

public struct MessageNavigationRequest: Hashable, Sendable, Identifiable {
    public var id: String {
        [
            serverID?.rawValue ?? "-",
            channelID.rawValue,
            messageID?.rawValue ?? "-",
            source.rawValue
        ].joined(separator: ":")
    }

    public var serverID: ServerID?
    public var channelID: ChannelID
    public var messageID: MessageID?
    public var source: MessageNavigationSource
    public var allowChannelFallback: Bool
    public var highlightDuration: TimeInterval

    public init(
        serverID: ServerID? = nil,
        channelID: ChannelID,
        messageID: MessageID? = nil,
        source: MessageNavigationSource,
        allowChannelFallback: Bool = false,
        highlightDuration: TimeInterval = 2
    ) {
        self.serverID = serverID
        self.channelID = channelID
        self.messageID = messageID
        self.source = source
        self.allowChannelFallback = allowChannelFallback
        self.highlightDuration = max(0.25, min(highlightDuration, 6))
    }
}

public enum MessageNavigationResult: String, Codable, Hashable, Sendable {
    case loaded
    case loadedAfterContextFetch
    case channelOnly
    case unavailable
    case queued
    case deduped
    case failed

    public var isSuccess: Bool {
        switch self {
        case .loaded, .loadedAfterContextFetch, .channelOnly, .queued, .deduped:
            return true
        case .unavailable, .failed:
            return false
        }
    }
}

public struct MessageNavigationCoordinator: Hashable, Sendable {
    public private(set) var inFlightTargets: Set<String>

    public init(inFlightTargets: Set<String> = []) {
        self.inFlightTargets = inFlightTargets
    }

    public mutating func begin(_ request: MessageNavigationRequest) -> Bool {
        guard !inFlightTargets.contains(request.id) else { return false }
        inFlightTargets.insert(request.id)
        return true
    }

    public mutating func finish(_ request: MessageNavigationRequest) {
        inFlightTargets.remove(request.id)
    }
}

public struct TargetMessageHighlightState: Hashable, Sendable {
    public var channelID: ChannelID
    public var messageID: MessageID
    public var source: MessageNavigationSource
    public var startedAt: Date
    public var expiresAt: Date

    public init(channelID: ChannelID, messageID: MessageID, source: MessageNavigationSource, startedAt: Date = Date(), duration: TimeInterval = 2) {
        self.channelID = channelID
        self.messageID = messageID
        self.source = source
        self.startedAt = startedAt
        self.expiresAt = startedAt.addingTimeInterval(max(0.25, min(duration, 6)))
    }

    public func isActive(at date: Date = Date()) -> Bool {
        expiresAt > date
    }
}

public enum ReplyTargetResolution: String, Codable, Hashable, Sendable {
    case loaded
    case loading
    case deleted
    case inaccessible
    case notFound
    case unavailable
    case notSupported
}

public struct ReplyPreviewState: Hashable, Sendable, Identifiable {
    public var id: String { "\(channelID.rawValue):\(messageID.rawValue):\(targetMessageID.rawValue)" }
    public var channelID: ChannelID
    public var messageID: MessageID
    public var targetMessageID: MessageID
    public var resolution: ReplyTargetResolution
    public var authorDisplayName: String?
    public var avatarFile: File?
    public var summary: String
    public var canOpenTarget: Bool

    public init(
        channelID: ChannelID,
        messageID: MessageID,
        targetMessageID: MessageID,
        resolution: ReplyTargetResolution,
        authorDisplayName: String? = nil,
        avatarFile: File? = nil,
        summary: String,
        canOpenTarget: Bool = false
    ) {
        self.channelID = channelID
        self.messageID = messageID
        self.targetMessageID = targetMessageID
        self.resolution = resolution
        self.authorDisplayName = Phase44SafeSummary.safeDisplayName(authorDisplayName)
        self.avatarFile = avatarFile
        self.summary = Phase44SafeSummary.messageSummary(summary)
        self.canOpenTarget = canOpenTarget
    }

    public var plainText: String {
        if let authorDisplayName, !authorDisplayName.isEmpty {
            return "\(authorDisplayName): \(summary)"
        }
        return summary
    }
}

public struct ReplyComposerState: Hashable, Sendable {
    public var channelID: ChannelID
    public var targetMessageID: MessageID
    public var authorDisplayName: String
    public var summary: String
    public var shouldMentionAuthor: Bool

    public init?(draft: ComposerDraftState) {
        guard let reply = draft.replyContext else { return nil }
        self.channelID = draft.channelID
        self.targetMessageID = reply.messageID
        self.authorDisplayName = Phase44SafeSummary.safeDisplayName(reply.authorDisplayName) ?? "Someone"
        self.summary = Phase44SafeSummary.messageSummary(reply.contentPreview)
        self.shouldMentionAuthor = draft.shouldMentionReplyAuthor
    }
}

public struct PinnedMessageDisplayItem: Hashable, Sendable, Identifiable {
    public var id: MessageID { messageID }
    public var channelID: ChannelID
    public var messageID: MessageID
    public var authorID: UserID
    public var authorDisplayName: String
    public var summary: String
    public var createdAt: Date?
    public var isPinned: Bool
    public var isLoaded: Bool
    public var canUnpin: Bool
    public var status: String?

    public init(
        channelID: ChannelID,
        messageID: MessageID,
        authorID: UserID,
        authorDisplayName: String,
        summary: String,
        createdAt: Date? = nil,
        isPinned: Bool = true,
        isLoaded: Bool = false,
        canUnpin: Bool = true,
        status: String? = nil
    ) {
        self.channelID = channelID
        self.messageID = messageID
        self.authorID = authorID
        self.authorDisplayName = Phase44SafeSummary.safeDisplayName(authorDisplayName) ?? "Someone"
        self.summary = Phase44SafeSummary.messageSummary(summary)
        self.createdAt = createdAt
        self.isPinned = isPinned
        self.isLoaded = isLoaded
        self.canUnpin = canUnpin
        self.status = status.map { Phase44SafeSummary.messageSummary($0) }
    }
}

public enum PinnedMessagesLoadState: Hashable, Sendable {
    case idle
    case loading(ChannelID)
    case loaded(ChannelID, [PinnedMessageDisplayItem])
    case failed(ChannelID, String)

    public var items: [PinnedMessageDisplayItem] {
        if case let .loaded(_, items) = self { return items }
        return []
    }
}

public struct PinnedMessagesState: Hashable, Sendable {
    public var loadState: PinnedMessagesLoadState
    public var inFlightActionMessageIDs: Set<MessageID>
    public var lastUpdatedAt: Date?

    public init(loadState: PinnedMessagesLoadState = .idle, inFlightActionMessageIDs: Set<MessageID> = [], lastUpdatedAt: Date? = nil) {
        self.loadState = loadState
        self.inFlightActionMessageIDs = inFlightActionMessageIDs
        self.lastUpdatedAt = lastUpdatedAt
    }
}

public struct TypingIndicatorState: Hashable, Sendable {
    public var channelID: ChannelID?
    public var entriesByUserID: [UserID: Date]
    public var timeout: TimeInterval

    public init(channelID: ChannelID? = nil, entriesByUserID: [UserID: Date] = [:], timeout: TimeInterval = 6) {
        self.channelID = channelID
        self.entriesByUserID = entriesByUserID
        self.timeout = max(1, timeout)
    }

    public var activeUserIDs: [UserID] {
        entriesByUserID.keys.sorted { $0.rawValue < $1.rawValue }
    }

    public mutating func replace(channelID: ChannelID?, typingUserIDs: Set<UserID>, currentUserID: UserID?, now: Date = Date()) {
        if self.channelID != channelID {
            self.channelID = channelID
            entriesByUserID = [:]
        }
        let filtered = typingUserIDs.filter { $0 != currentUserID }
        entriesByUserID = entriesByUserID.filter { filtered.contains($0.key) && now.timeIntervalSince($0.value) <= timeout }
        for userID in filtered {
            entriesByUserID[userID] = now
        }
    }

    @discardableResult
    public mutating func removeStale(now: Date = Date()) -> Int {
        let before = entriesByUserID.count
        entriesByUserID = entriesByUserID.filter { now.timeIntervalSince($0.value) <= timeout }
        return before - entriesByUserID.count
    }

    public mutating func clear(channelID: ChannelID? = nil) {
        self.channelID = channelID
        entriesByUserID = [:]
    }

    public static func displayText(names: [String]) -> String? {
        let safeNames = names.compactMap(Phase44SafeSummary.safeDisplayName).filter { !$0.isEmpty }
        switch safeNames.count {
        case 0:
            return nil
        case 1:
            return "\(safeNames[0]) is typing..."
        case 2:
            return "\(safeNames[0]) and \(safeNames[1]) are typing..."
        default:
            return "Several people are typing..."
        }
    }
}

public struct Phase44ChatInteractionDiagnostics: Hashable, Sendable {
    public var replyPreviewResolvedLoaded: Int
    public var replyPreviewResolvedUnloaded: Int
    public var replyPreviewUnavailable: Int
    public var replyComposerSetCount: Int
    public var replyComposerClearedAfterSendCount: Int
    public var replyComposerPreservedAfterFailureCount: Int
    public var pinnedListRequestCount: Int
    public var pinnedListSuccessCount: Int
    public var pinnedListFailureCount: Int
    public var pinActionSuccessCount: Int
    public var pinActionFailureCount: Int
    public var unpinActionSuccessCount: Int
    public var unpinActionFailureCount: Int
    public var pinnedMessageJumpCount: Int
    public var pinnedMessageUnavailableCount: Int
    public var searchLocalResultBuckets: [String: Int]
    public var searchRemoteResultBuckets: [String: Int]
    public var jumpSourceCounts: [String: Int]
    public var jumpLoadedCount: Int
    public var jumpUnloadedCount: Int
    public var jumpUnavailableCount: Int
    public var jumpDegradedToChannelCount: Int
    public var targetHighlightCount: Int
    public var typingActiveUsersBuckets: [String: Int]
    public var typingStaleCleanupCount: Int
    public var ackRequestedCount: Int
    public var ackSentCount: Int
    public var ackDedupedCount: Int
    public var ackFailureCount: Int
    public var unreadLocalClearSources: [String: Int]
    public var notificationRouteQueuedCount: Int
    public var notificationRouteReplayedCount: Int
    public var notificationRouteDegradedCount: Int
    public var muteSuppressionDecisionCounts: [String: Int]
    public var durationBuckets: [String: Int]
    public var lastSafeStatus: String?

    public init(
        replyPreviewResolvedLoaded: Int = 0,
        replyPreviewResolvedUnloaded: Int = 0,
        replyPreviewUnavailable: Int = 0,
        replyComposerSetCount: Int = 0,
        replyComposerClearedAfterSendCount: Int = 0,
        replyComposerPreservedAfterFailureCount: Int = 0,
        pinnedListRequestCount: Int = 0,
        pinnedListSuccessCount: Int = 0,
        pinnedListFailureCount: Int = 0,
        pinActionSuccessCount: Int = 0,
        pinActionFailureCount: Int = 0,
        unpinActionSuccessCount: Int = 0,
        unpinActionFailureCount: Int = 0,
        pinnedMessageJumpCount: Int = 0,
        pinnedMessageUnavailableCount: Int = 0,
        searchLocalResultBuckets: [String: Int] = [:],
        searchRemoteResultBuckets: [String: Int] = [:],
        jumpSourceCounts: [String: Int] = [:],
        jumpLoadedCount: Int = 0,
        jumpUnloadedCount: Int = 0,
        jumpUnavailableCount: Int = 0,
        jumpDegradedToChannelCount: Int = 0,
        targetHighlightCount: Int = 0,
        typingActiveUsersBuckets: [String: Int] = [:],
        typingStaleCleanupCount: Int = 0,
        ackRequestedCount: Int = 0,
        ackSentCount: Int = 0,
        ackDedupedCount: Int = 0,
        ackFailureCount: Int = 0,
        unreadLocalClearSources: [String: Int] = [:],
        notificationRouteQueuedCount: Int = 0,
        notificationRouteReplayedCount: Int = 0,
        notificationRouteDegradedCount: Int = 0,
        muteSuppressionDecisionCounts: [String: Int] = [:],
        durationBuckets: [String: Int] = [:],
        lastSafeStatus: String? = nil
    ) {
        self.replyPreviewResolvedLoaded = replyPreviewResolvedLoaded
        self.replyPreviewResolvedUnloaded = replyPreviewResolvedUnloaded
        self.replyPreviewUnavailable = replyPreviewUnavailable
        self.replyComposerSetCount = replyComposerSetCount
        self.replyComposerClearedAfterSendCount = replyComposerClearedAfterSendCount
        self.replyComposerPreservedAfterFailureCount = replyComposerPreservedAfterFailureCount
        self.pinnedListRequestCount = pinnedListRequestCount
        self.pinnedListSuccessCount = pinnedListSuccessCount
        self.pinnedListFailureCount = pinnedListFailureCount
        self.pinActionSuccessCount = pinActionSuccessCount
        self.pinActionFailureCount = pinActionFailureCount
        self.unpinActionSuccessCount = unpinActionSuccessCount
        self.unpinActionFailureCount = unpinActionFailureCount
        self.pinnedMessageJumpCount = pinnedMessageJumpCount
        self.pinnedMessageUnavailableCount = pinnedMessageUnavailableCount
        self.searchLocalResultBuckets = searchLocalResultBuckets
        self.searchRemoteResultBuckets = searchRemoteResultBuckets
        self.jumpSourceCounts = jumpSourceCounts
        self.jumpLoadedCount = jumpLoadedCount
        self.jumpUnloadedCount = jumpUnloadedCount
        self.jumpUnavailableCount = jumpUnavailableCount
        self.jumpDegradedToChannelCount = jumpDegradedToChannelCount
        self.targetHighlightCount = targetHighlightCount
        self.typingActiveUsersBuckets = typingActiveUsersBuckets
        self.typingStaleCleanupCount = typingStaleCleanupCount
        self.ackRequestedCount = ackRequestedCount
        self.ackSentCount = ackSentCount
        self.ackDedupedCount = ackDedupedCount
        self.ackFailureCount = ackFailureCount
        self.unreadLocalClearSources = unreadLocalClearSources
        self.notificationRouteQueuedCount = notificationRouteQueuedCount
        self.notificationRouteReplayedCount = notificationRouteReplayedCount
        self.notificationRouteDegradedCount = notificationRouteDegradedCount
        self.muteSuppressionDecisionCounts = muteSuppressionDecisionCounts
        self.durationBuckets = durationBuckets
        self.lastSafeStatus = lastSafeStatus.map { Phase44SafeSummary.messageSummary($0) }
    }
}

public enum Phase44DiagnosticsFormatter {
    public static func redactedText(_ diagnostics: Phase44ChatInteractionDiagnostics) -> String {
        let text = """
        Phase 44 Chat Interaction Diagnostics
        replyPreviewLoadedUnloadedUnavailable: \(diagnostics.replyPreviewResolvedLoaded)/\(diagnostics.replyPreviewResolvedUnloaded)/\(diagnostics.replyPreviewUnavailable)
        replyComposerSetClearedPreserved: \(diagnostics.replyComposerSetCount)/\(diagnostics.replyComposerClearedAfterSendCount)/\(diagnostics.replyComposerPreservedAfterFailureCount)
        pinnedListRequestSuccessFailure: \(diagnostics.pinnedListRequestCount)/\(diagnostics.pinnedListSuccessCount)/\(diagnostics.pinnedListFailureCount)
        pinActionSuccessFailure: \(diagnostics.pinActionSuccessCount)/\(diagnostics.pinActionFailureCount)
        unpinActionSuccessFailure: \(diagnostics.unpinActionSuccessCount)/\(diagnostics.unpinActionFailureCount)
        pinnedJumpUnavailable: \(diagnostics.pinnedMessageJumpCount)/\(diagnostics.pinnedMessageUnavailableCount)
        searchLocalBuckets: \(bucketText(diagnostics.searchLocalResultBuckets))
        searchRemoteBuckets: \(bucketText(diagnostics.searchRemoteResultBuckets))
        jumpSources: \(bucketText(diagnostics.jumpSourceCounts))
        jumpLoadedUnloadedUnavailableDegraded: \(diagnostics.jumpLoadedCount)/\(diagnostics.jumpUnloadedCount)/\(diagnostics.jumpUnavailableCount)/\(diagnostics.jumpDegradedToChannelCount)
        targetHighlightCount: \(diagnostics.targetHighlightCount)
        typingBuckets: \(bucketText(diagnostics.typingActiveUsersBuckets))
        typingStaleCleanup: \(diagnostics.typingStaleCleanupCount)
        ackRequestedSentDedupedFailed: \(diagnostics.ackRequestedCount)/\(diagnostics.ackSentCount)/\(diagnostics.ackDedupedCount)/\(diagnostics.ackFailureCount)
        unreadLocalClearSources: \(bucketText(diagnostics.unreadLocalClearSources))
        notificationQueuedReplayedDegraded: \(diagnostics.notificationRouteQueuedCount)/\(diagnostics.notificationRouteReplayedCount)/\(diagnostics.notificationRouteDegradedCount)
        muteSuppressionSources: \(bucketText(diagnostics.muteSuppressionDecisionCounts))
        durationBuckets: \(bucketText(diagnostics.durationBuckets))
        lastStatus: \(diagnostics.lastSafeStatus ?? "-")
        """
        return Phase43IdentityDiagnosticsFormatter.redactSensitiveText(text)
    }

    private static func bucketText(_ buckets: [String: Int]) -> String {
        guard !buckets.isEmpty else { return "-" }
        return buckets
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ",")
    }
}

public enum Phase44SafeSummary {
    public static func safeDisplayName(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if looksLikeFullID(trimmed) { return nil }
        return messageSummary(trimmed, limit: 48)
    }

    public static func messageSummary(_ value: String, limit: Int = 96) -> String {
        var output = value.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        let regexReplacements: [(String, String)] = [
            (#"https?://[^\s,;)"]+"#, "[link]"),
            (#"file://[^\s,;)"]+"#, "[path]"),
            (#"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#, "[email]"),
            (#"(/Users|/tmp|/var|/private|/Volumes)(/[^\s,;)"]+)+"#, "[path]"),
            (#"(?i)\b(password|token|session|authorization|mfa|ticket|response|reason)\b\s*[:=]\s*["']?[^"',;\s]+"#, "$1=[redacted]")
        ]
        for (pattern, replacement) in regexReplacements {
            output = output.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        output = output.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        output = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if looksLikeFullID(output) { output = "Message" }
        guard !output.isEmpty else { return "Message" }
        guard output.count > limit else { return output }
        let index = output.index(output.startIndex, offsetBy: max(0, limit - 3))
        return String(output[..<index]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    public static func messageSummary(for message: Message) -> String {
        if let content = message.content, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return messageSummary(content)
        }
        if let attachments = message.attachments, !attachments.isEmpty {
            return attachments.count == 1 ? "1 attachment" : "\(attachments.count) attachments"
        }
        if let embeds = message.embeds, !embeds.isEmpty {
            if let summary = embedSummary(for: embeds) {
                return summary
            }
            return embeds.count == 1 ? "1 embed" : "\(embeds.count) embeds"
        }
        if message.system != nil {
            return "System message"
        }
        return "Message"
    }

    public static func bucket(for count: Int) -> String {
        switch count {
        case 0: "0"
        case 1: "1"
        case 2: "2"
        case 3...5: "3-5"
        case 6...20: "6-20"
        default: "20+"
        }
    }

    private static func looksLikeFullID(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9_-]{20,}$"#, options: .regularExpression) != nil
    }

    private static func embedSummary(for embeds: [Embed]) -> String? {
        for embed in embeds {
            let candidates = [
                embed.title,
                embed.description,
                embed.siteName,
                embed.url.flatMap(safeURLHost),
                embed.originalURL.flatMap(safeURLHost)
            ]
            for candidate in candidates {
                guard let candidate else { continue }
                let summary = messageSummary(candidate)
                if summary != "Message" {
                    return summary
                }
            }
            if embed.media != nil {
                return embed.kind == .video ? "Video embed" : "Image embed"
            }
            if embed.image != nil {
                return "Image embed"
            }
            if embed.video != nil {
                return "Video embed"
            }
        }
        return nil
    }

    private static func safeURLHost(_ value: String) -> String? {
        guard let components = URLComponents(string: value),
              let host = components.host,
              !host.isEmpty
        else { return nil }
        return host
    }
}
