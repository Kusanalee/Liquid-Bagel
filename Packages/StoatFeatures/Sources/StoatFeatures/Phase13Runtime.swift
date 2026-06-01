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

    public static func routeCapabilityLabel(_ name: String, status: TimelineRouteVerificationStatus) -> String {
        "\(name): \(status.rawValue), source-verified when supported"
    }

    public static func calibrationLabel(isRunning: Bool, observationCount: Int) -> String {
        "Timeline calibration \(isRunning ? "running" : "stopped"), \(observationCount) observation\(observationCount == 1 ? "" : "s")"
    }
}
