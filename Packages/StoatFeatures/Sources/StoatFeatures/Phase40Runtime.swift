import Foundation
import StoatAPI
import StoatModels

public enum DMRefreshSource: String, Codable, Hashable, Sendable, CaseIterable {
    case home
    case directMessages
    case friends
    case developer
    case explicit
    case notification
    case mock
    case unknown
}

public enum DMOpenSource: String, Codable, Hashable, Sendable, CaseIterable {
    case friendsRow
    case profilePopover
    case memberRow
    case searchResult
    case savedNotes
    case directList
    case directCall
    case newMessagePicker
    case notification
    case unknown
}

public enum DMOperationStatus: String, Codable, Hashable, Sendable {
    case idle
    case skipped
    case loading
    case succeeded
    case failed
}

public enum DMSafeErrorCategory: String, Codable, Hashable, Sendable {
    case authentication
    case permission
    case notFound = "not-found"
    case rateLimit = "rate-limit"
    case server
    case responseMismatch = "response-mismatch"
    case network
    case client
    case unavailable
    case unknown

    public static func categorize(_ error: any Error) -> DMSafeErrorCategory {
        if let apiError = error as? StoatAPIError {
            return categorize(apiError.diagnosticCategory)
        }
        return categorize(error.userFacingMessage)
    }

    public static func categorize(_ value: String) -> DMSafeErrorCategory {
        let lowered = value.lowercased()
        if lowered.contains("authentication") || lowered.contains("authorized") || lowered.contains("credential") {
            return .authentication
        }
        if lowered.contains("permission") || lowered.contains("forbidden") {
            return .permission
        }
        if lowered.contains("not-found") || lowered.contains("not found") {
            return .notFound
        }
        if lowered.contains("rate") {
            return .rateLimit
        }
        if lowered.contains("server") {
            return .server
        }
        if lowered.contains("decode") || lowered.contains("response-mismatch") || lowered.contains("shape") {
            return .responseMismatch
        }
        if lowered.contains("network") || lowered.contains("transport") || lowered.contains("offline") {
            return .network
        }
        if lowered.contains("unavailable") || lowered.contains("unimplemented") {
            return .unavailable
        }
        if lowered.contains("client") || lowered.contains("invalid") {
            return .client
        }
        return .unknown
    }
}

public enum SavedNotesChannelState: Codable, Hashable, Sendable {
    case available(ChannelID)
    case unavailable
    case opening
    case failed(DMSafeErrorCategory)

    public var label: String {
        switch self {
        case .available:
            "available"
        case .unavailable:
            "unavailable"
        case .opening:
            "opening"
        case let .failed(category):
            "failed \(category.rawValue)"
        }
    }
}

public struct DMChannelMergeResult: Hashable, Sendable {
    public var source: DMRefreshSource
    public var returnedCount: Int
    public var insertedCount: Int
    public var updatedCount: Int
    public var duplicateCount: Int

    public init(
        source: DMRefreshSource,
        returnedCount: Int = 0,
        insertedCount: Int = 0,
        updatedCount: Int = 0,
        duplicateCount: Int = 0
    ) {
        self.source = source
        self.returnedCount = returnedCount
        self.insertedCount = insertedCount
        self.updatedCount = updatedCount
        self.duplicateCount = duplicateCount
    }
}

public struct DMDiagnostics: Hashable, Sendable {
    public var knownDirectMessageCount: Int
    public var knownGroupDMCount: Int
    public var savedNotesState: SavedNotesChannelState
    public var lastRefreshStatus: DMOperationStatus
    public var lastRefreshSource: DMRefreshSource?
    public var lastRefreshCount: Int
    public var lastRefreshDurationMilliseconds: Int?
    public var lastRefreshErrorCategory: DMSafeErrorCategory?
    public var lastOpenStatus: DMOperationStatus
    public var lastOpenSource: DMOpenSource?
    public var lastOpenTarget: String?
    public var lastOpenErrorCategory: DMSafeErrorCategory?
    public var duplicateMergeCount: Int
    public var missingRecipientUserCount: Int
    public var rawIDFallbackCount: Int
    public var unreadChannelCount: Int
    public var mentionCount: Int
    public var locallyClearedUnreadCount: Int
    public var lastAckSummary: String?
    public var safeErrorCategories: [DMSafeErrorCategory]

    public init(
        knownDirectMessageCount: Int = 0,
        knownGroupDMCount: Int = 0,
        savedNotesState: SavedNotesChannelState = .unavailable,
        lastRefreshStatus: DMOperationStatus = .idle,
        lastRefreshSource: DMRefreshSource? = nil,
        lastRefreshCount: Int = 0,
        lastRefreshDurationMilliseconds: Int? = nil,
        lastRefreshErrorCategory: DMSafeErrorCategory? = nil,
        lastOpenStatus: DMOperationStatus = .idle,
        lastOpenSource: DMOpenSource? = nil,
        lastOpenTarget: String? = nil,
        lastOpenErrorCategory: DMSafeErrorCategory? = nil,
        duplicateMergeCount: Int = 0,
        missingRecipientUserCount: Int = 0,
        rawIDFallbackCount: Int = 0,
        unreadChannelCount: Int = 0,
        mentionCount: Int = 0,
        locallyClearedUnreadCount: Int = 0,
        lastAckSummary: String? = nil,
        safeErrorCategories: [DMSafeErrorCategory] = []
    ) {
        self.knownDirectMessageCount = knownDirectMessageCount
        self.knownGroupDMCount = knownGroupDMCount
        self.savedNotesState = savedNotesState
        self.lastRefreshStatus = lastRefreshStatus
        self.lastRefreshSource = lastRefreshSource
        self.lastRefreshCount = lastRefreshCount
        self.lastRefreshDurationMilliseconds = lastRefreshDurationMilliseconds
        self.lastRefreshErrorCategory = lastRefreshErrorCategory
        self.lastOpenStatus = lastOpenStatus
        self.lastOpenSource = lastOpenSource
        self.lastOpenTarget = lastOpenTarget
        self.lastOpenErrorCategory = lastOpenErrorCategory
        self.duplicateMergeCount = duplicateMergeCount
        self.missingRecipientUserCount = missingRecipientUserCount
        self.rawIDFallbackCount = rawIDFallbackCount
        self.unreadChannelCount = unreadChannelCount
        self.mentionCount = mentionCount
        self.locallyClearedUnreadCount = locallyClearedUnreadCount
        self.lastAckSummary = lastAckSummary
        self.safeErrorCategories = safeErrorCategories
    }

    public func addingErrorCategory(_ category: DMSafeErrorCategory?) -> DMDiagnostics {
        guard let category else { return self }
        var copy = self
        var categories = copy.safeErrorCategories.filter { $0 != category }
        categories.append(category)
        copy.safeErrorCategories = Array(categories.suffix(5))
        return copy
    }
}

public enum DMDiagnosticsFormatter {
    public static func redactedText(_ diagnostics: DMDiagnostics) -> String {
        let text = """
        DM diagnostics
        knownDirectMessageCount: \(diagnostics.knownDirectMessageCount)
        knownGroupDMCount: \(diagnostics.knownGroupDMCount)
        savedNotesState: \(savedNotesLabel(diagnostics.savedNotesState))
        lastRefreshStatus: \(diagnostics.lastRefreshStatus.rawValue)
        lastRefreshSource: \(diagnostics.lastRefreshSource?.rawValue ?? "-")
        lastRefreshCount: \(diagnostics.lastRefreshCount)
        lastRefreshDurationMilliseconds: \(diagnostics.lastRefreshDurationMilliseconds.map(String.init) ?? "-")
        lastRefreshErrorCategory: \(diagnostics.lastRefreshErrorCategory?.rawValue ?? "-")
        lastOpenStatus: \(diagnostics.lastOpenStatus.rawValue)
        lastOpenSource: \(diagnostics.lastOpenSource?.rawValue ?? "-")
        lastOpenTarget: \(short(diagnostics.lastOpenTarget))
        lastOpenErrorCategory: \(diagnostics.lastOpenErrorCategory?.rawValue ?? "-")
        duplicateMergeCount: \(diagnostics.duplicateMergeCount)
        missingRecipientUserCount: \(diagnostics.missingRecipientUserCount)
        rawIDFallbackCount: \(diagnostics.rawIDFallbackCount)
        unreadChannelCount: \(diagnostics.unreadChannelCount)
        mentionCount: \(diagnostics.mentionCount)
        locallyClearedUnreadCount: \(diagnostics.locallyClearedUnreadCount)
        lastAckSummary: \(diagnostics.lastAckSummary ?? "-")
        safeErrorCategories: \(diagnostics.safeErrorCategories.map(\.rawValue).joined(separator: ", "))
        """
        return Phase17MessageActions.redactedDiagnosticText(
            Phase6UIHelpers.safeDiagnostics(
                AttachmentDiagnosticsFormatter.redact(redactRawPayloads(text))
            )
        )
    }

    private static func savedNotesLabel(_ state: SavedNotesChannelState) -> String {
        switch state {
        case let .available(channelID):
            "available \(short(channelID.rawValue))"
        case .unavailable:
            "unavailable"
        case .opening:
            "opening"
        case let .failed(category):
            "failed \(category.rawValue)"
        }
    }

    private static func short(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "-" }
        return TimelineCopyFormatter.shortID(value)
    }

    private static func redactRawPayloads(_ value: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\{[^\n]*\}"#) else { return value }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.stringByReplacingMatches(in: value, range: range, withTemplate: "[redacted-payload]")
    }
}
