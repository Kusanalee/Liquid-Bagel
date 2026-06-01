import Foundation
import StoatModels
import StoatPersistence

public enum TimelineCalibrationObservationKind: String, Codable, Hashable, Sendable, CaseIterable {
    case manualCheckpoint
    case afterInitialLoad
    case afterScroll
    case afterLoadOlder
    case afterJumpNewest
    case afterJumpUnread
    case afterSearchJump
    case afterAck
    case warning

    public var displayName: String {
        switch self {
        case .manualCheckpoint: "Manual checkpoint"
        case .afterInitialLoad: "After initial load"
        case .afterScroll: "After scroll"
        case .afterLoadOlder: "After load older"
        case .afterJumpNewest: "After jump newest"
        case .afterJumpUnread: "After jump unread"
        case .afterSearchJump: "After search jump"
        case .afterAck: "After ack"
        case .warning: "Warning"
        }
    }
}

public struct TimelineCalibrationObservation: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var timestamp: Date
    public var kind: TimelineCalibrationObservationKind
    public var diagnostics: TimelineDiagnostics
    public var note: String?

    public init(id: UUID = UUID(), timestamp: Date = Date(), kind: TimelineCalibrationObservationKind, diagnostics: TimelineDiagnostics, note: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.diagnostics = diagnostics
        self.note = note
    }
}

public struct TimelineTuningRecommendation: Codable, Hashable, Sendable {
    public var title: String
    public var detail: String
    public var recommendedTuning: TimelineTuningConfiguration

    public init(title: String, detail: String, recommendedTuning: TimelineTuningConfiguration) {
        self.title = title
        self.detail = detail
        self.recommendedTuning = recommendedTuning.validated()
    }
}

public struct TimelineCalibrationRun: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var startedAt: Date
    public var endedAt: Date?
    public var environmentID: String
    public var channelID: ChannelID?
    public var tuning: TimelineTuningConfiguration
    public var observations: [TimelineCalibrationObservation]
    public var warnings: [TimelineValidationWarning]
    public var recommendedAdjustments: TimelineTuningRecommendation?

    public init(
        id: UUID = UUID(),
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        environmentID: String,
        channelID: ChannelID?,
        tuning: TimelineTuningConfiguration,
        observations: [TimelineCalibrationObservation] = [],
        warnings: [TimelineValidationWarning] = [],
        recommendedAdjustments: TimelineTuningRecommendation? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.environmentID = environmentID
        self.channelID = channelID
        self.tuning = tuning.validated()
        self.observations = observations
        self.warnings = warnings
        self.recommendedAdjustments = recommendedAdjustments
    }

    public var isRunning: Bool { endedAt == nil }

    public func adding(_ observation: TimelineCalibrationObservation) -> TimelineCalibrationRun {
        var copy = self
        copy.observations.append(observation)
        copy.warnings = observation.diagnostics.validationWarnings
        copy.recommendedAdjustments = TimelineCalibrationAdvisor.recommendation(for: copy)
        return copy
    }

    public func stopped(at date: Date = Date()) -> TimelineCalibrationRun {
        var copy = self
        copy.endedAt = date
        copy.recommendedAdjustments = TimelineCalibrationAdvisor.recommendation(for: copy)
        return copy
    }
}

public enum TimelineCalibrationAdvisor {
    public static func recommendation(for run: TimelineCalibrationRun) -> TimelineTuningRecommendation? {
        let warningMessages = run.observations.flatMap(\.diagnostics.validationWarnings).map(\.message)
        var tuning = run.tuning

        if warningMessages.contains(where: { $0.localizedCaseInsensitiveContains("marked at newest") }) {
            tuning.nearNewestMessageThreshold += 1
            return TimelineTuningRecommendation(
                title: "Increase near-newest threshold",
                detail: "Observed at-newest warnings suggest the visible tail is close but not being treated as newest.",
                recommendedTuning: tuning
            )
        }
        if warningMessages.contains(where: { $0.localizedCaseInsensitiveContains("Visible range has not reported") || $0.localizedCaseInsensitiveContains("not loaded") }) {
            tuning.visibleRangeUpdateDebounceMilliseconds += 40
            return TimelineTuningRecommendation(
                title: "Stabilize visible-range updates",
                detail: "Visible-range warnings suggest a slightly slower debounce may reduce noisy calibration readings.",
                recommendedTuning: tuning
            )
        }
        if run.observations.contains(where: { observation in
            if case .targetUnloaded = observation.diagnostics.unreadRecoveryState { return true }
            return false
        }) {
            tuning.loadToUnreadMaxAttempts += 1
            return TimelineTuningRecommendation(
                title: "Allow another unread recovery attempt",
                detail: "Unread recovery reached an unloaded target during calibration.",
                recommendedTuning: tuning
            )
        }
        return nil
    }
}

public enum ChannelSearchMode: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case loadedOnly
    case liveChannel
    case pinned

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .loadedOnly: "Find in loaded messages"
        case .liveChannel: "Live channel search"
        case .pinned: "Pinned in this channel"
        }
    }
}

public struct ChannelSearchQuery: Codable, Hashable, Sendable {
    public var text: String
    public var mode: ChannelSearchMode
    public var pinnedOnly: Bool

    public init(text: String = "", mode: ChannelSearchMode = .loadedOnly, pinnedOnly: Bool = false) {
        self.text = text
        self.mode = mode
        self.pinnedOnly = pinnedOnly
    }

    public var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct ChannelSearchResult: Codable, Hashable, Identifiable, Sendable {
    public var id: MessageID { messageID }
    public var messageID: MessageID
    public var channelID: ChannelID
    public var authorID: UserID
    public var authorDisplayName: String?
    public var createdAt: Date?
    public var snippet: String
    public var mode: ChannelSearchMode
    public var isPinned: Bool
    public var isLoaded: Bool
    public var safeStatus: String?

    public init(
        messageID: MessageID,
        channelID: ChannelID,
        authorID: UserID,
        authorDisplayName: String? = nil,
        createdAt: Date? = nil,
        snippet: String,
        mode: ChannelSearchMode,
        isPinned: Bool = false,
        isLoaded: Bool = false,
        safeStatus: String? = nil
    ) {
        self.messageID = messageID
        self.channelID = channelID
        self.authorID = authorID
        self.authorDisplayName = authorDisplayName
        self.createdAt = createdAt
        self.snippet = TimelineCopyFormatter.redactTokenLikeStrings(snippet)
        self.mode = mode
        self.isPinned = isPinned
        self.isLoaded = isLoaded
        self.safeStatus = safeStatus.map(TimelineCopyFormatter.redactTokenLikeStrings)
    }
}

public enum ChannelSearchState: Hashable, Sendable {
    case idle
    case searching(ChannelSearchQuery)
    case results(ChannelSearchQuery, [ChannelSearchResult])
    case empty(ChannelSearchQuery)
    case failed(ChannelSearchQuery, String)

    public var results: [ChannelSearchResult] {
        if case let .results(_, results) = self { return results }
        return []
    }

    public var query: ChannelSearchQuery? {
        switch self {
        case .idle:
            return nil
        case let .searching(query), let .results(query, _), let .empty(query), let .failed(query, _):
            return query
        }
    }
}

public struct TimelineSearchHighlightState: Hashable, Sendable {
    public var channelID: ChannelID?
    public var query: String
    public var mode: ChannelSearchMode
    public var resultIDs: [MessageID]
    public var currentResultID: MessageID?
    public var unloadedResultIDs: [MessageID]
    public var updatedAt: Date?

    public init(
        channelID: ChannelID?,
        query: String,
        mode: ChannelSearchMode,
        resultIDs: [MessageID],
        currentResultID: MessageID?,
        unloadedResultIDs: [MessageID] = [],
        updatedAt: Date? = Date()
    ) {
        self.channelID = channelID
        self.query = TimelineCopyFormatter.redactTokenLikeStrings(query)
        self.mode = mode
        self.resultIDs = resultIDs
        self.currentResultID = currentResultID
        self.unloadedResultIDs = unloadedResultIDs
        self.updatedAt = updatedAt
    }

    public var loadedResultIDs: [MessageID] {
        let unloaded = Set(unloadedResultIDs)
        return resultIDs.filter { !unloaded.contains($0) }
    }

    public var isEmpty: Bool { resultIDs.isEmpty }

    public func contains(_ messageID: MessageID) -> Bool {
        resultIDs.contains(messageID) && !unloadedResultIDs.contains(messageID)
    }

    public func isCurrent(_ messageID: MessageID) -> Bool {
        currentResultID == messageID
    }

    public func indexOfCurrent() -> Int? {
        guard let currentResultID else { return nil }
        return resultIDs.firstIndex(of: currentResultID).map { $0 + 1 }
    }

    public static func make(
        channelID: ChannelID?,
        query: ChannelSearchQuery,
        results: [ChannelSearchResult],
        currentResultID: MessageID?,
        loadedMessageIDs: Set<MessageID>,
        updatedAt: Date = Date()
    ) -> TimelineSearchHighlightState? {
        guard !results.isEmpty else { return nil }
        let scoped = results.filter { result in
            guard let channelID else { return true }
            return result.channelID == channelID
        }
        guard !scoped.isEmpty else { return nil }
        let resultIDs = scoped.map(\.messageID)
        let unloaded = scoped.filter { !loadedMessageIDs.contains($0.messageID) }.map(\.messageID)
        let preferredCurrent = currentResultID.flatMap { resultIDs.contains($0) ? $0 : nil }
            ?? scoped.first(where: { loadedMessageIDs.contains($0.messageID) })?.messageID
            ?? resultIDs.first
        return TimelineSearchHighlightState(
            channelID: channelID,
            query: query.trimmedText,
            mode: query.mode,
            resultIDs: resultIDs,
            currentResultID: preferredCurrent,
            unloadedResultIDs: unloaded,
            updatedAt: updatedAt
        )
    }
}

public enum TimelineDefaultTuningDecision: Hashable, Sendable {
    case remainConservative(reason: String)
    case recommendBalanced(reason: String)
    case recommendCustom(TimelineTuningConfiguration, reason: String)

    public var title: String {
        switch self {
        case .remainConservative: "Remain Conservative"
        case .recommendBalanced: "Recommend Balanced"
        case .recommendCustom: "Recommend Custom"
        }
    }

    public var reason: String {
        switch self {
        case let .remainConservative(reason), let .recommendBalanced(reason), let .recommendCustom(_, reason):
            return reason
        }
    }

    public var recommendedConfiguration: TimelineTuningConfiguration {
        switch self {
        case .remainConservative:
            return TimelineTuningPreset.conservative.configuration
        case .recommendBalanced:
            return TimelineTuningPreset.balanced.configuration
        case let .recommendCustom(configuration, _):
            return configuration.validated()
        }
    }
}

public enum TimelineDefaultTuningAdvisor {
    public static func decision(notes: [String], recommendation: TimelineTuningRecommendation?) -> TimelineDefaultTuningDecision {
        let redactedNotes = notes
            .map(TimelineCopyFormatter.redactTokenLikeStrings)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !redactedNotes.isEmpty || recommendation != nil else {
            return .remainConservative(reason: "No real Live Manual calibration notes are recorded, so Phase 14 keeps the conservative default.")
        }

        let joined = redactedNotes.joined(separator: "\n").lowercased()
        let balancedSignals = ["balanced", "stable at balanced", "recommend balanced", "move to balanced"]
            .filter { joined.contains($0) }
            .count
        let cautionSignals = ["noisy", "unstable", "failed", "warning", "conservative", "regression"]
            .filter { joined.contains($0) }
            .count

        if let recommendation,
           recommendation.recommendedTuning != TimelineTuningPreset.conservative.configuration,
           recommendation.recommendedTuning != TimelineTuningPreset.balanced.configuration {
            return .recommendCustom(recommendation.recommendedTuning, reason: TimelineCopyFormatter.redactTokenLikeStrings(recommendation.detail))
        }

        if balancedSignals > 0 && cautionSignals == 0 {
            return .recommendBalanced(reason: "Imported calibration notes consistently mention Balanced without warning signals.")
        }

        return .remainConservative(reason: "Calibration notes are absent, mixed, or noisy; keep the safer conservative default and apply other presets manually.")
    }
}

public enum Phase13Accessibility {
    public static func channelSearchPanelLabel(mode: ChannelSearchMode, resultCount: Int) -> String {
        "\(mode.displayName), \(resultCount) result\(resultCount == 1 ? "" : "s")"
    }

    public static func channelSearchResultLabel(_ result: ChannelSearchResult, isSelected: Bool) -> String {
        var parts = [
            result.authorDisplayName ?? result.authorID.rawValue,
            result.snippet,
            result.mode.displayName
        ]
        if result.isPinned { parts.append("Pinned") }
        parts.append(result.isLoaded ? "Loaded" : "Outside loaded range")
        if isSelected { parts.append("Selected") }
        return parts.joined(separator: ", ")
    }

    public static func searchHighlightLabel(isHighlighted: Bool, isCurrent: Bool) -> String? {
        guard isHighlighted else { return nil }
        return isCurrent ? "current search result" : "search result"
    }

    public static func searchResultCountLabel(mode: ChannelSearchMode, currentIndex: Int?, total: Int, loaded: Int, unloaded: Int) -> String {
        let position = currentIndex.map { "result \($0) of \(total)" } ?? "\(total) results"
        return "\(mode.displayName), \(position), \(loaded) loaded, \(unloaded) outside loaded range"
    }

    public static func loadAroundCurrentResultHint(canLoad: Bool) -> String {
        canLoad ? "Loads messages around the current search result after explicit confirmation." : "Current search result is already loaded or the route is unavailable."
    }

    public static func routeCapabilityLabel(_ name: String, status: TimelineRouteVerificationStatus) -> String {
        "\(name): \(status.rawValue), source-verified when supported"
    }

    public static func calibrationLabel(isRunning: Bool, observationCount: Int) -> String {
        "Timeline calibration \(isRunning ? "running" : "stopped"), \(observationCount) observation\(observationCount == 1 ? "" : "s")"
    }
}
