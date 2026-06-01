import Foundation
import StoatAPI
import StoatModels
import StoatPersistence

public enum TimelineValidationSeverity: String, Codable, Hashable, Sendable {
    case info
    case warning
    case error
}

public struct TimelineValidationWarning: Codable, Hashable, Sendable {
    public var severity: TimelineValidationSeverity
    public var message: String

    public init(severity: TimelineValidationSeverity, message: String) {
        self.severity = severity
        self.message = message
    }
}

public struct TimelineVisibleRangeValidator: Sendable {
    public init() {}

    public func warnings(
        channelID: ChannelID?,
        loadedMessageIDs: [MessageID],
        visibleRange: TimelineVisibleRange?,
        atNewest: Bool,
        nearNewestMessageThreshold: Int
    ) -> [TimelineValidationWarning] {
        var warnings: [TimelineValidationWarning] = []
        guard let visibleRange else {
            if !loadedMessageIDs.isEmpty {
                warnings.append(TimelineValidationWarning(severity: .info, message: "Visible range has not reported yet."))
            }
            return warnings
        }
        if let channelID, visibleRange.channelID != channelID {
            warnings.append(TimelineValidationWarning(severity: .error, message: "Visible range channel does not match the active channel."))
        }
        let loadedSet = Set(loadedMessageIDs)
        let missing = visibleRange.visibleMessageIDs.filter { !loadedSet.contains($0) }
        if !missing.isEmpty {
            warnings.append(TimelineValidationWarning(severity: .warning, message: "Visible range contains messages that are not loaded."))
        }
        if let first = visibleRange.firstVisibleMessageID,
           let last = visibleRange.lastVisibleMessageID,
           let firstIndex = loadedMessageIDs.firstIndex(of: first),
           let lastIndex = loadedMessageIDs.firstIndex(of: last),
           firstIndex > lastIndex {
            warnings.append(TimelineValidationWarning(severity: .error, message: "First visible message is after the last visible message."))
        }
        let nearNewest = TimelineViewportReducer.isNewestVisibleOrNearVisible(
            visibleMessageIDs: visibleRange.visibleMessageIDs,
            loadedMessageIDs: loadedMessageIDs,
            trailingThreshold: nearNewestMessageThreshold
        )
        if atNewest && !nearNewest {
            warnings.append(TimelineValidationWarning(severity: .warning, message: "Timeline is marked at newest, but the visible tail is not near the newest loaded message."))
        }
        return warnings
    }
}

public enum TimelineRouteVerificationStatus: String, Codable, Hashable, Sendable {
    case unknown
    case supported
    case unsupported
}

public struct TimelineRouteVerificationResult: Codable, Hashable, Sendable {
    public var singleMessageFetch: TimelineRouteVerificationStatus
    public var aroundMessageFetch: TimelineRouteVerificationStatus
    public var channelSearch: TimelineRouteVerificationStatus
    public var pinnedSearch: TimelineRouteVerificationStatus
    public var checkedAt: Date?

    public init(
        singleMessageFetch: TimelineRouteVerificationStatus = .unknown,
        aroundMessageFetch: TimelineRouteVerificationStatus = .unknown,
        channelSearch: TimelineRouteVerificationStatus = .unknown,
        pinnedSearch: TimelineRouteVerificationStatus = .unknown,
        checkedAt: Date? = nil
    ) {
        self.singleMessageFetch = singleMessageFetch
        self.aroundMessageFetch = aroundMessageFetch
        self.channelSearch = channelSearch
        self.pinnedSearch = pinnedSearch
        self.checkedAt = checkedAt
    }

    public static var sourceVerified: TimelineRouteVerificationResult {
        TimelineRouteVerificationResult(
            singleMessageFetch: .supported,
            aroundMessageFetch: .supported,
            channelSearch: .supported,
            pinnedSearch: .supported,
            checkedAt: Date()
        )
    }

    public var summary: String {
        "single \(singleMessageFetch.rawValue), around \(aroundMessageFetch.rawValue), search \(channelSearch.rawValue), pinned \(pinnedSearch.rawValue)"
    }
}

public struct LoadedMessageFindResult: Hashable, Identifiable, Sendable {
    public var id: MessageID { messageID }
    public var messageID: MessageID
    public var channelID: ChannelID
    public var authorID: UserID
    public var createdAt: Date?
    public var snippet: String

    public init(messageID: MessageID, channelID: ChannelID, authorID: UserID, createdAt: Date?, snippet: String) {
        self.messageID = messageID
        self.channelID = channelID
        self.authorID = authorID
        self.createdAt = createdAt
        self.snippet = snippet
    }
}

public struct LoadedMessageFinder: Sendable {
    public init() {}

    public func find(query: String, messages: [TimelineMessage], maxResults: Int = 50) -> [LoadedMessageFindResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return messages.compactMap { timelineMessage in
            guard let content = timelineMessage.message.content,
                  content.localizedCaseInsensitiveContains(trimmed)
            else {
                return nil
            }
            return LoadedMessageFindResult(
                messageID: timelineMessage.message.id,
                channelID: timelineMessage.message.channelID,
                authorID: timelineMessage.message.authorID,
                createdAt: timelineMessage.message.createdAt,
                snippet: Self.snippet(content, matching: trimmed)
            )
        }
        .prefix(maxResults)
        .map { $0 }
    }

    public static func snippet(_ content: String, matching query: String, limit: Int = 96) -> String {
        let collapsed = content.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        guard collapsed.count > limit else { return collapsed }
        if let range = collapsed.range(of: query, options: .caseInsensitive) {
            let lower = collapsed.index(range.lowerBound, offsetBy: -min(24, collapsed.distance(from: collapsed.startIndex, to: range.lowerBound)), limitedBy: collapsed.startIndex) ?? collapsed.startIndex
            let upper = collapsed.index(range.upperBound, offsetBy: min(limit, collapsed.distance(from: range.upperBound, to: collapsed.endIndex)), limitedBy: collapsed.endIndex) ?? collapsed.endIndex
            return String(collapsed[lower..<upper]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(collapsed.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public actor LiveMessageReferenceResolver: MessageReferenceResolving {
    private let apiClient: any StoatAPIClient
    private let tuning: @Sendable () -> TimelineTuningConfiguration
    private var cache: [ChannelID: [MessageID: MessageReferenceResolution]] = [:]
    private var failedAt: [ChannelID: [MessageID: Date]] = [:]

    public init(apiClient: any StoatAPIClient, tuning: @escaping @Sendable () -> TimelineTuningConfiguration) {
        self.apiClient = apiClient
        self.tuning = tuning
    }

    public func resolveReference(channelID: ChannelID, messageID: MessageID) async throws -> MessageReferenceResolution {
        if let cached = cache[channelID]?[messageID] {
            return cached
        }
        if let failed = failedAt[channelID]?[messageID],
           Date().timeIntervalSince(failed) < TimeInterval(tuning().referenceFetchCooldownSeconds) {
            return .unavailable("Original message is cooling down")
        }
        do {
            let message = try await apiClient.fetchMessage(channelID: channelID, messageID: messageID)
            let resolution: MessageReferenceResolution = .loaded(message)
            cache[channelID, default: [:]][messageID] = resolution
            return resolution
        } catch StoatAPIError.forbidden {
            return rememberFailure(.forbidden, channelID: channelID, messageID: messageID)
        } catch StoatAPIError.notFound {
            return rememberFailure(.notFound, channelID: channelID, messageID: messageID)
        } catch StoatAPIError.rateLimited {
            return rememberFailure(.rateLimited, channelID: channelID, messageID: messageID)
        } catch StoatAPIError.unimplementedEndpoint {
            return rememberFailure(.notSupported, channelID: channelID, messageID: messageID)
        } catch {
            return rememberFailure(.unavailable(error.userFacingMessage), channelID: channelID, messageID: messageID)
        }
    }

    private func rememberFailure(_ resolution: MessageReferenceResolution, channelID: ChannelID, messageID: MessageID) -> MessageReferenceResolution {
        cache[channelID, default: [:]][messageID] = resolution
        failedAt[channelID, default: [:]][messageID] = Date()
        return resolution
    }
}

public enum TimelineCopyFormatter {
    public static func diagnostics(_ diagnostics: TimelineDiagnostics) -> String {
        let warnings = diagnostics.validationWarnings.map { "\($0.severity.rawValue): \($0.message)" }.joined(separator: "; ")
        let text = """
        Timeline diagnostics
        channel: \(shortID(diagnostics.channelID?.rawValue))
        loaded: \(diagnostics.loadedMessageCount)
        oldest: \(shortID(diagnostics.oldestLoadedMessageID?.rawValue))
        newest: \(shortID(diagnostics.newestLoadedMessageID?.rawValue))
        visible: \(shortID(diagnostics.firstVisibleMessageID?.rawValue))...\(shortID(diagnostics.lastVisibleMessageID?.rawValue))
        atNewest: \(diagnostics.atNewest)
        unread: \(shortID(diagnostics.firstUnreadMessageID?.rawValue))
        recovery: \(diagnostics.unreadRecoveryState)
        hasMoreBefore: \(diagnostics.hasMoreBefore)
        hasMoreAfter: \(diagnostics.hasMoreAfter)
        pendingReferences: \(diagnostics.pendingReferenceFetchCount)
        failedReferences: \(diagnostics.failedReferenceFetchCount)
        pendingRetries: \(diagnostics.pendingRetryCount)
        lastAckTarget: \(shortID(diagnostics.lastAckTargetMessageID?.rawValue))
        lastAckResult: \(diagnostics.lastAckResult ?? "-")
        lastTimelineAction: \(diagnostics.lastTimelineActionResult ?? "-")
        routes: \(diagnostics.lastRouteVerificationResult ?? "-")
        tuning: nearNewest=\(diagnostics.tuningConfiguration.nearNewestMessageThreshold), visibleDebounce=\(diagnostics.tuningConfiguration.visibleRangeUpdateDebounceMilliseconds), loadToUnread=\(diagnostics.tuningConfiguration.loadToUnreadMaxAttempts), ackDebounce=\(diagnostics.tuningConfiguration.ackDebounceMilliseconds)
        warnings: \(warnings.isEmpty ? "-" : warnings)
        """
        return Phase6UIHelpers.safeDiagnostics(redactTokenLikeStrings(text))
    }

    public static func calibration(_ run: TimelineCalibrationRun) -> String {
        let observations = run.observations.map { observation in
            let note = observation.note.map { " note=\(redactTokenLikeStrings($0))" } ?? ""
            return "- \(observation.kind.displayName) at \(observation.timestamp.formatted(date: .numeric, time: .standard)): loaded=\(observation.diagnostics.loadedMessageCount), atNewest=\(observation.diagnostics.atNewest), warnings=\(observation.diagnostics.validationWarnings.count)\(note)"
        }.joined(separator: "\n")
        let recommendation = run.recommendedAdjustments.map { "\($0.title): \($0.detail)" } ?? "-"
        let text = """
        Timeline calibration
        id: \(shortID(run.id.uuidString))
        environment: \(shortID(run.environmentID))
        channel: \(shortID(run.channelID?.rawValue))
        started: \(run.startedAt.formatted(date: .numeric, time: .standard))
        ended: \(run.endedAt?.formatted(date: .numeric, time: .standard) ?? "-")
        tuning: nearNewest=\(run.tuning.nearNewestMessageThreshold), visibleDebounce=\(run.tuning.visibleRangeUpdateDebounceMilliseconds), loadToUnread=\(run.tuning.loadToUnreadMaxAttempts), ackDebounce=\(run.tuning.ackDebounceMilliseconds)
        recommendation: \(recommendation)
        observations:
        \(observations.isEmpty ? "-" : observations)
        """
        return Phase6UIHelpers.safeDiagnostics(redactTokenLikeStrings(text))
    }

    public static func shortID(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "-" }
        guard value.count > 12 else { return value }
        return "\(value.prefix(6))...\(value.suffix(4))"
    }

    public static func redactTokenLikeStrings(_ text: String) -> String {
        var output = text
        let patterns = [
            "[A-Za-z0-9_-]{24,}\\.[A-Za-z0-9_-]{24,}\\.[A-Za-z0-9_-]{12,}",
            "(?i)(session|bot|token)[=: ]+[A-Za-z0-9._-]+"
        ]
        for pattern in patterns {
            output = output.replacingOccurrences(of: pattern, with: "<redacted>", options: .regularExpression)
        }
        return output
    }
}
