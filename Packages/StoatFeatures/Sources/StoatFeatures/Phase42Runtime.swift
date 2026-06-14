import Foundation
import StoatModels

public enum ModerationAction: String, CaseIterable, Hashable, Sendable {
    case kick
    case ban
    case unban
    case timeout
    case removeTimeout

    public var title: String {
        switch self {
        case .kick: "Kick"
        case .ban: "Ban"
        case .unban: "Unban"
        case .timeout: "Apply Timeout"
        case .removeTimeout: "Remove Timeout"
        }
    }

    public var diagnosticsCategory: String {
        switch self {
        case .kick: "kick"
        case .ban: "ban"
        case .unban: "unban"
        case .timeout: "timeout"
        case .removeTimeout: "removeTimeout"
        }
    }

    public var systemImage: String {
        switch self {
        case .kick: "rectangle.portrait.and.arrow.right"
        case .ban: "hand.raised.fill"
        case .unban: "hand.raised.slash"
        case .timeout: "clock.badge.exclamationmark"
        case .removeTimeout: "clock.arrow.circlepath"
        }
    }

    public var requiresReason: Bool {
        self == .ban
    }
}

public enum ModerationTimeoutPreset: String, CaseIterable, Hashable, Sendable, Identifiable {
    case fiveMinutes
    case tenMinutes
    case oneHour
    case sixHours
    case twentyFourHours
    case sevenDays
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .fiveMinutes: "5m"
        case .tenMinutes: "10m"
        case .oneHour: "1h"
        case .sixHours: "6h"
        case .twentyFourHours: "24h"
        case .sevenDays: "7d"
        case .custom: "Custom"
        }
    }

    public var diagnosticsBucket: String {
        switch self {
        case .fiveMinutes, .tenMinutes: "minutes"
        case .oneHour, .sixHours: "hours"
        case .twentyFourHours: "day"
        case .sevenDays: "week"
        case .custom: "custom"
        }
    }

    public func timeoutUntil(now: Date, custom: Date) -> Date {
        switch self {
        case .fiveMinutes:
            now.addingTimeInterval(5 * 60)
        case .tenMinutes:
            now.addingTimeInterval(10 * 60)
        case .oneHour:
            now.addingTimeInterval(60 * 60)
        case .sixHours:
            now.addingTimeInterval(6 * 60 * 60)
        case .twentyFourHours:
            now.addingTimeInterval(24 * 60 * 60)
        case .sevenDays:
            now.addingTimeInterval(7 * 24 * 60 * 60)
        case .custom:
            max(custom, now.addingTimeInterval(60))
        }
    }
}

public struct PendingModerationConfirmation: Hashable, Sendable, Identifiable {
    public var id: String { "\(action.rawValue)-\(serverID.rawValue)-\(targetUserID.rawValue)" }
    public var action: ModerationAction
    public var serverID: ServerID
    public var serverName: String
    public var targetUserID: UserID
    public var targetMember: ServerMember?
    public var displayName: String
    public var reason: String
    public var timeoutPreset: ModerationTimeoutPreset
    public var customTimeoutUntil: Date
    public var allowNonMemberBan: Bool

    public init(
        action: ModerationAction,
        serverID: ServerID,
        serverName: String,
        targetUserID: UserID,
        targetMember: ServerMember?,
        displayName: String,
        reason: String = "",
        timeoutPreset: ModerationTimeoutPreset = .oneHour,
        customTimeoutUntil: Date = Date().addingTimeInterval(60 * 60),
        allowNonMemberBan: Bool = false
    ) {
        self.action = action
        self.serverID = serverID
        self.serverName = serverName
        self.targetUserID = targetUserID
        self.targetMember = targetMember
        self.displayName = displayName
        self.reason = reason
        self.timeoutPreset = timeoutPreset
        self.customTimeoutUntil = customTimeoutUntil
        self.allowNonMemberBan = allowNonMemberBan
    }

    public func timeoutUntil(now: Date = Date()) -> Date? {
        guard action == .timeout else { return nil }
        return timeoutPreset.timeoutUntil(now: now, custom: customTimeoutUntil)
    }
}

public struct ModerationDashboardCounts: Hashable, Sendable {
    public var knownBans: Int
    public var renderedBans: Int
    public var pendingBans: Int
    public var knownTimeouts: Int
    public var renderedTimeouts: Int
    public var pendingTimeouts: Int

    public init(
        knownBans: Int = 0,
        renderedBans: Int = 0,
        pendingBans: Int = 0,
        knownTimeouts: Int = 0,
        renderedTimeouts: Int = 0,
        pendingTimeouts: Int = 0
    ) {
        self.knownBans = knownBans
        self.renderedBans = renderedBans
        self.pendingBans = pendingBans
        self.knownTimeouts = knownTimeouts
        self.renderedTimeouts = renderedTimeouts
        self.pendingTimeouts = pendingTimeouts
    }
}
