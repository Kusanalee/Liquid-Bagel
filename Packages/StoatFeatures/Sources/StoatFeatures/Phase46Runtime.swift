import Foundation
import StoatModels

public struct Phase46ModerationPrewarmKey: Hashable, Sendable {
    public var selectedServerID: ServerID?
    public var selectedChannelID: ChannelID?
    public var selectedOrFallbackTextChannelID: ChannelID?
    public var currentUserID: UserID?
    public var serverVersion: Int
    public var memberVersion: Int
    public var roleVersion: Int
    public var channelVersion: Int
    public var permissionVersion: Int
    public var banVersion: Int
    public var capabilityVersion: Int

    public init(
        selectedServerID: ServerID? = nil,
        selectedChannelID: ChannelID? = nil,
        selectedOrFallbackTextChannelID: ChannelID? = nil,
        currentUserID: UserID? = nil,
        serverVersion: Int = 0,
        memberVersion: Int = 0,
        roleVersion: Int = 0,
        channelVersion: Int = 0,
        permissionVersion: Int = 0,
        banVersion: Int = 0,
        capabilityVersion: Int = 0
    ) {
        self.selectedServerID = selectedServerID
        self.selectedChannelID = selectedChannelID
        self.selectedOrFallbackTextChannelID = selectedOrFallbackTextChannelID
        self.currentUserID = currentUserID
        self.serverVersion = serverVersion
        self.memberVersion = memberVersion
        self.roleVersion = roleVersion
        self.channelVersion = channelVersion
        self.permissionVersion = permissionVersion
        self.banVersion = banVersion
        self.capabilityVersion = capabilityVersion
    }
}

public struct Phase46ModerationSignatureSummary: Hashable, Sendable {
    public var serverVersion: Int
    public var memberVersion: Int
    public var roleVersion: Int
    public var channelVersion: Int
    public var permissionVersion: Int
    public var banVersion: Int
    public var capabilityVersion: Int

    public init(
        serverVersion: Int = 0,
        memberVersion: Int = 0,
        roleVersion: Int = 0,
        channelVersion: Int = 0,
        permissionVersion: Int = 0,
        banVersion: Int = 0,
        capabilityVersion: Int = 0
    ) {
        self.serverVersion = serverVersion
        self.memberVersion = memberVersion
        self.roleVersion = roleVersion
        self.channelVersion = channelVersion
        self.permissionVersion = permissionVersion
        self.banVersion = banVersion
        self.capabilityVersion = capabilityVersion
    }

    public mutating func bumpSnapshotVersions() {
        serverVersion &+= 1
        memberVersion &+= 1
        roleVersion &+= 1
        channelVersion &+= 1
        permissionVersion &+= 1
    }

    public mutating func bumpSelectionVersions() {
        serverVersion &+= 1
        channelVersion &+= 1
        permissionVersion &+= 1
    }

    public mutating func bumpMemberVersion() {
        memberVersion &+= 1
    }

    public mutating func bumpBanVersion() {
        banVersion &+= 1
    }

    public mutating func bumpCapabilityVersion() {
        capabilityVersion &+= 1
    }
}

public enum Phase46PrewarmTrigger: String, Sendable {
    case memberPanelVisible
    case profilePopoverVisible
    case serverSettingsModerationVisible
    case explicitModerationAction
    case stateMutation
}

public enum Phase46PrewarmResult: String, Sendable {
    case idle
    case prepared
    case deduped
    case skippedNoServer
    case skippedNoMembers
    case skippedInFlight
}

public struct Phase46MemberPanelPrewarmState: Hashable, Sendable {
    public var preparedKey: Phase46ModerationPrewarmKey?
    public var inFlightKey: Phase46ModerationPrewarmKey?
    public var lastTrigger: Phase46PrewarmTrigger
    public var lastResult: Phase46PrewarmResult
    public var preparedMemberCount: Int
    public var attemptCount: Int
    public var dedupeCount: Int

    public init(
        preparedKey: Phase46ModerationPrewarmKey? = nil,
        inFlightKey: Phase46ModerationPrewarmKey? = nil,
        lastTrigger: Phase46PrewarmTrigger = .stateMutation,
        lastResult: Phase46PrewarmResult = .idle,
        preparedMemberCount: Int = 0,
        attemptCount: Int = 0,
        dedupeCount: Int = 0
    ) {
        self.preparedKey = preparedKey
        self.inFlightKey = inFlightKey
        self.lastTrigger = lastTrigger
        self.lastResult = lastResult
        self.preparedMemberCount = preparedMemberCount
        self.attemptCount = attemptCount
        self.dedupeCount = dedupeCount
    }
}

public struct Phase46FreezePreventionDiagnostics: Hashable, Sendable {
    public var renderCacheOnlyHits: Int
    public var renderCacheOnlyMisses: Int
    public var lifecyclePrewarmAttempts: Int
    public var lifecyclePrewarmDedupes: Int
    public var lastTrigger: Phase46PrewarmTrigger
    public var lastResult: Phase46PrewarmResult
    public var lastPreparedMemberCount: Int

    public init(
        renderCacheOnlyHits: Int = 0,
        renderCacheOnlyMisses: Int = 0,
        lifecyclePrewarmAttempts: Int = 0,
        lifecyclePrewarmDedupes: Int = 0,
        lastTrigger: Phase46PrewarmTrigger = .stateMutation,
        lastResult: Phase46PrewarmResult = .idle,
        lastPreparedMemberCount: Int = 0
    ) {
        self.renderCacheOnlyHits = renderCacheOnlyHits
        self.renderCacheOnlyMisses = renderCacheOnlyMisses
        self.lifecyclePrewarmAttempts = lifecyclePrewarmAttempts
        self.lifecyclePrewarmDedupes = lifecyclePrewarmDedupes
        self.lastTrigger = lastTrigger
        self.lastResult = lastResult
        self.lastPreparedMemberCount = lastPreparedMemberCount
    }
}
