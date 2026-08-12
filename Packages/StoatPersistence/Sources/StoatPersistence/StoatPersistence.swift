import CryptoKit
import Foundation
import StoatAPI
import StoatModels

public struct PersistenceScope: Equatable, Sendable {
    public var appGroupIdentifier: String?

    public init(appGroupIdentifier: String? = nil) {
        self.appGroupIdentifier = appGroupIdentifier
    }
}

public enum PersistenceError: Error, Equatable, Sendable, LocalizedError {
    case notImplemented
    case missingProductionProfile
    case productionProfileCannotBeDeleted
    case invalidProfile(String)
    case encodingFailed(String)
    case decodingFailed(String)

    public var message: String {
        switch self {
        case .notImplemented:
            return "Persistence is not implemented."
        case .missingProductionProfile:
            return "Preferences must include the production environment profile."
        case .productionProfileCannotBeDeleted:
            return "The production environment profile cannot be deleted."
        case let .invalidProfile(message):
            return message
        case let .encodingFailed(message):
            return "Could not encode preferences: \(message)"
        case let .decodingFailed(message):
            return "Could not decode preferences: \(message)"
        }
    }

    public var errorDescription: String? { message }
}

public enum InlineImagePreviewPolicy: String, Codable, Hashable, Sendable, CaseIterable {
    case automaticSmallImages
    case explicitClickOnly
    case disabled
}

public enum MessageDensityPreference: String, Codable, Hashable, Sendable, CaseIterable {
    case comfortable
    case compact
}

public enum NotificationDeliveryScope: String, Codable, Hashable, Sendable, CaseIterable {
    case mentionsAndDirectMessages
    case allMessages
}

public enum NotificationContentVisibility: String, Codable, Hashable, Sendable, CaseIterable {
    case privateMode
    case showSenderAndContent
}

public enum DockBadgePreference: String, Codable, Hashable, Sendable, CaseIterable {
    case off
    case mentionsOnly
    case unreadChannelsAndMentions
}

public struct ChannelNotificationPreference: Codable, Hashable, Sendable {
    public var isMuted: Bool
    public var suppressNative: Bool
    public var suppressInApp: Bool

    public init(isMuted: Bool = false, suppressNative: Bool = false, suppressInApp: Bool = false) {
        self.isMuted = isMuted
        self.suppressNative = suppressNative
        self.suppressInApp = suppressInApp
    }

    public var suppressesAllDelivery: Bool {
        isMuted || (suppressNative && suppressInApp)
    }
}

public struct NotificationPreferences: Codable, Hashable, Sendable {
    public var nativeNotificationsEnabled: Bool
    public var inAppBannersEnabled: Bool
    public var contentVisibility: NotificationContentVisibility
    public var suppressActiveChannel: Bool
    public var deliveryScope: NotificationDeliveryScope
    public var dockBadge: DockBadgePreference
    public var channelPreferences: [ChannelID: ChannelNotificationPreference]

    public init(
        nativeNotificationsEnabled: Bool = false,
        inAppBannersEnabled: Bool = true,
        contentVisibility: NotificationContentVisibility = .privateMode,
        suppressActiveChannel: Bool = true,
        deliveryScope: NotificationDeliveryScope = .mentionsAndDirectMessages,
        dockBadge: DockBadgePreference = .unreadChannelsAndMentions,
        channelPreferences: [ChannelID: ChannelNotificationPreference] = [:]
    ) {
        self.nativeNotificationsEnabled = nativeNotificationsEnabled
        self.inAppBannersEnabled = inAppBannersEnabled
        self.contentVisibility = contentVisibility
        self.suppressActiveChannel = suppressActiveChannel
        self.deliveryScope = deliveryScope
        self.dockBadge = dockBadge
        self.channelPreferences = channelPreferences.filter { $0.value.isMuted || $0.value.suppressNative || $0.value.suppressInApp }
    }

    public static var defaults: NotificationPreferences {
        NotificationPreferences()
    }

    public func preference(for channelID: ChannelID) -> ChannelNotificationPreference {
        channelPreferences[channelID] ?? ChannelNotificationPreference()
    }

    public func validated() -> NotificationPreferences {
        var copy = self
        copy.channelPreferences = channelPreferences.filter { preference in
            preference.value.isMuted || preference.value.suppressNative || preference.value.suppressInApp
        }
        return copy
    }
}

/// Local voice call settings — device selection, capture processing, push-to-talk, and voice
/// activation. Local-only by design (not part of `SyncedClientPreferences`): device IDs are
/// per-machine, so syncing them across devices would just make one machine's mic pick fight
/// another's.
public struct VoicePreferences: Codable, Hashable, Sendable {
    public var inputDeviceID: String?
    public var outputDeviceID: String?
    public var echoCancellation: Bool
    public var noiseSuppression: Bool
    public var pushToTalkEnabled: Bool
    public var pushToTalkKeyCode: UInt16?
    /// 0...1 voice-activation threshold, used only when `pushToTalkEnabled == false`.
    public var inputSensitivity: Double

    public init(
        inputDeviceID: String? = nil,
        outputDeviceID: String? = nil,
        echoCancellation: Bool = true,
        noiseSuppression: Bool = true,
        pushToTalkEnabled: Bool = false,
        pushToTalkKeyCode: UInt16? = nil,
        inputSensitivity: Double = 0.15
    ) {
        self.inputDeviceID = inputDeviceID
        self.outputDeviceID = outputDeviceID
        self.echoCancellation = echoCancellation
        self.noiseSuppression = noiseSuppression
        self.pushToTalkEnabled = pushToTalkEnabled
        self.pushToTalkKeyCode = pushToTalkKeyCode
        self.inputSensitivity = inputSensitivity
    }

    private enum CodingKeys: String, CodingKey {
        case inputDeviceID
        case outputDeviceID
        case echoCancellation
        case noiseSuppression
        case pushToTalkEnabled
        case pushToTalkKeyCode
        case inputSensitivity
    }

    /// Decoded key-by-key with per-field fallbacks, same reasoning as `TimelineTuningConfiguration`:
    /// the synthesized `Decodable` would fail the whole blob on one missing key.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = VoicePreferences()
        self.init(
            inputDeviceID: try container.decodeIfPresent(String.self, forKey: .inputDeviceID),
            outputDeviceID: try container.decodeIfPresent(String.self, forKey: .outputDeviceID),
            echoCancellation: try container.decodeIfPresent(Bool.self, forKey: .echoCancellation) ?? defaults.echoCancellation,
            noiseSuppression: try container.decodeIfPresent(Bool.self, forKey: .noiseSuppression) ?? defaults.noiseSuppression,
            pushToTalkEnabled: try container.decodeIfPresent(Bool.self, forKey: .pushToTalkEnabled) ?? defaults.pushToTalkEnabled,
            pushToTalkKeyCode: try container.decodeIfPresent(UInt16.self, forKey: .pushToTalkKeyCode),
            inputSensitivity: try container.decodeIfPresent(Double.self, forKey: .inputSensitivity) ?? defaults.inputSensitivity
        )
    }

    public static var defaults: VoicePreferences {
        VoicePreferences()
    }

    public func validated() -> VoicePreferences {
        var copy = self
        copy.inputSensitivity = min(max(inputSensitivity, 0), 1)
        return copy
    }
}

public struct TimelineTuningConfiguration: Codable, Hashable, Sendable {
    public var nearNewestMessageThreshold: Int
    public var visibleRangeUpdateDebounceMilliseconds: Int
    public var loadToUnreadMaxAttempts: Int
    public var referenceFetchMaxAttempts: Int
    public var referenceFetchCooldownSeconds: Int
    public var ackDebounceMilliseconds: Int
    /// How far above the viewport an older page starts loading, as a percentage of viewport
    /// height. 150 means "begin fetching when the oldest loaded message is within 1.5 screens".
    public var olderPrefetchDistancePercent: Int
    /// Backstop trigger: fetch when the first visible message is within this many rows of the
    /// oldest loaded one. Covers the case where the scroll-geometry threshold cannot re-arm.
    public var olderPrefetchRowThreshold: Int

    public init(
        nearNewestMessageThreshold: Int = 2,
        visibleRangeUpdateDebounceMilliseconds: Int = 120,
        loadToUnreadMaxAttempts: Int = 4,
        referenceFetchMaxAttempts: Int = 1,
        referenceFetchCooldownSeconds: Int = 60,
        ackDebounceMilliseconds: Int = 1500,
        olderPrefetchDistancePercent: Int = 150,
        olderPrefetchRowThreshold: Int = 12
    ) {
        self.nearNewestMessageThreshold = nearNewestMessageThreshold
        self.visibleRangeUpdateDebounceMilliseconds = visibleRangeUpdateDebounceMilliseconds
        self.loadToUnreadMaxAttempts = loadToUnreadMaxAttempts
        self.referenceFetchMaxAttempts = referenceFetchMaxAttempts
        self.referenceFetchCooldownSeconds = referenceFetchCooldownSeconds
        self.ackDebounceMilliseconds = ackDebounceMilliseconds
        self.olderPrefetchDistancePercent = olderPrefetchDistancePercent
        self.olderPrefetchRowThreshold = olderPrefetchRowThreshold
    }

    private enum CodingKeys: String, CodingKey {
        case nearNewestMessageThreshold
        case visibleRangeUpdateDebounceMilliseconds
        case loadToUnreadMaxAttempts
        case referenceFetchMaxAttempts
        case referenceFetchCooldownSeconds
        case ackDebounceMilliseconds
        case olderPrefetchDistancePercent
        case olderPrefetchRowThreshold
    }

    /// Decoded key-by-key with per-field fallbacks rather than through the synthesized
    /// initializer. Synthesized `Decodable` throws on a missing key, so adding a field would
    /// make every previously stored payload fail to decode and silently reset the user's whole
    /// preference blob. Same reason `NotificationPreferences` does this.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = TimelineTuningConfiguration()
        self.init(
            nearNewestMessageThreshold: try container.decodeIfPresent(Int.self, forKey: .nearNewestMessageThreshold) ?? defaults.nearNewestMessageThreshold,
            visibleRangeUpdateDebounceMilliseconds: try container.decodeIfPresent(Int.self, forKey: .visibleRangeUpdateDebounceMilliseconds) ?? defaults.visibleRangeUpdateDebounceMilliseconds,
            loadToUnreadMaxAttempts: try container.decodeIfPresent(Int.self, forKey: .loadToUnreadMaxAttempts) ?? defaults.loadToUnreadMaxAttempts,
            referenceFetchMaxAttempts: try container.decodeIfPresent(Int.self, forKey: .referenceFetchMaxAttempts) ?? defaults.referenceFetchMaxAttempts,
            referenceFetchCooldownSeconds: try container.decodeIfPresent(Int.self, forKey: .referenceFetchCooldownSeconds) ?? defaults.referenceFetchCooldownSeconds,
            ackDebounceMilliseconds: try container.decodeIfPresent(Int.self, forKey: .ackDebounceMilliseconds) ?? defaults.ackDebounceMilliseconds,
            olderPrefetchDistancePercent: try container.decodeIfPresent(Int.self, forKey: .olderPrefetchDistancePercent) ?? defaults.olderPrefetchDistancePercent,
            olderPrefetchRowThreshold: try container.decodeIfPresent(Int.self, forKey: .olderPrefetchRowThreshold) ?? defaults.olderPrefetchRowThreshold
        )
    }

    public static var defaults: TimelineTuningConfiguration {
        TimelineTuningConfiguration()
    }

    public func validated() -> TimelineTuningConfiguration {
        TimelineTuningConfiguration(
            nearNewestMessageThreshold: Self.clamp(nearNewestMessageThreshold, 0...25),
            visibleRangeUpdateDebounceMilliseconds: Self.clamp(visibleRangeUpdateDebounceMilliseconds, 0...2_000),
            loadToUnreadMaxAttempts: Self.clamp(loadToUnreadMaxAttempts, 1...20),
            referenceFetchMaxAttempts: Self.clamp(referenceFetchMaxAttempts, 0...5),
            referenceFetchCooldownSeconds: Self.clamp(referenceFetchCooldownSeconds, 0...3_600),
            ackDebounceMilliseconds: Self.clamp(ackDebounceMilliseconds, 0...10_000),
            olderPrefetchDistancePercent: Self.clamp(olderPrefetchDistancePercent, 0...500),
            olderPrefetchRowThreshold: Self.clamp(olderPrefetchRowThreshold, 0...100)
        )
    }

    private static func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

public enum TimelineTuningPreset: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case conservative
    case balanced
    case responsive
    case debugStrict

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .conservative: "Conservative"
        case .balanced: "Balanced"
        case .responsive: "Responsive"
        case .debugStrict: "Debug Strict"
        }
    }

    public var configuration: TimelineTuningConfiguration {
        switch self {
        case .conservative:
            TimelineTuningConfiguration.defaults
        case .balanced:
            TimelineTuningConfiguration(
                nearNewestMessageThreshold: 3,
                visibleRangeUpdateDebounceMilliseconds: 100,
                loadToUnreadMaxAttempts: 5,
                referenceFetchMaxAttempts: 1,
                referenceFetchCooldownSeconds: 60,
                ackDebounceMilliseconds: 1400,
                olderPrefetchDistancePercent: 200,
                olderPrefetchRowThreshold: 15
            )
        case .responsive:
            TimelineTuningConfiguration(
                nearNewestMessageThreshold: 4,
                visibleRangeUpdateDebounceMilliseconds: 60,
                loadToUnreadMaxAttempts: 6,
                referenceFetchMaxAttempts: 2,
                referenceFetchCooldownSeconds: 45,
                ackDebounceMilliseconds: 1000,
                olderPrefetchDistancePercent: 300,
                olderPrefetchRowThreshold: 20
            )
        case .debugStrict:
            TimelineTuningConfiguration(
                nearNewestMessageThreshold: 0,
                visibleRangeUpdateDebounceMilliseconds: 0,
                loadToUnreadMaxAttempts: 2,
                referenceFetchMaxAttempts: 0,
                referenceFetchCooldownSeconds: 0,
                ackDebounceMilliseconds: 0,
                olderPrefetchDistancePercent: 0,
                olderPrefetchRowThreshold: 0
            )
        }
    }
}

public struct EnvironmentProfile: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var environment: StoatAPIEnvironment
    public var isProduction: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        name: String,
        environment: StoatAPIEnvironment,
        isProduction: Bool,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.environment = environment
        self.isProduction = isProduction
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public static func production(now: Date = Date()) -> EnvironmentProfile {
        EnvironmentProfile(
            id: StoatAPIEnvironment.production.stableID,
            name: "Stoat Production",
            environment: .production,
            isProduction: true,
            createdAt: now,
            updatedAt: now
        )
    }

    public static func custom(
        name: String,
        environment: StoatAPIEnvironment,
        now: Date = Date(),
        id: String? = nil,
        createdAt: Date? = nil
    ) throws -> EnvironmentProfile {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw PersistenceError.invalidProfile("Environment name cannot be blank.")
        }
        try environment.validate()
        guard !environment.isProduction else {
            throw PersistenceError.invalidProfile("Use the built-in production profile for Stoat production.")
        }
        return EnvironmentProfile(
            id: id ?? environment.stableID,
            name: trimmedName,
            environment: environment,
            isProduction: false,
            createdAt: createdAt ?? now,
            updatedAt: now
        )
    }

    public func updating(name: String, environment: StoatAPIEnvironment, now: Date = Date()) throws -> EnvironmentProfile {
        if isProduction {
            var copy = self
            copy.updatedAt = now
            return copy
        }
        let newID = environment == self.environment ? id : environment.stableID
        return try EnvironmentProfile.custom(
            name: name,
            environment: environment,
            now: now,
            id: newID,
            createdAt: environment == self.environment ? createdAt : now
        )
    }
}

public struct AppPreferences: Codable, Hashable, Sendable {
    public var lastSelectedEnvironmentID: String?
    public var environmentProfiles: [EnvironmentProfile]
    public var showDeveloperRuntimeControls: Bool
    /// Paint the shell from the offline cache before the network is touched.
    ///
    /// A kill switch rather than a feature toggle. This is the change most likely to produce a
    /// subtle staleness bug in the field, and being able to turn it off without shipping a build
    /// is worth one stored boolean.
    public var offlineCacheRestoreOnLaunch: Bool
    /// Sync the allowlisted preference subset through the account without being asked.
    ///
    /// Deliberately not part of `SyncedClientPreferences`: a device that opts out of syncing must
    /// not have that decision overwritten by a device that opted in.
    public var automaticSettingsSyncEnabled: Bool
    public var lastSelectedServerID: ServerID?
    public var lastSelectedChannelID: ChannelID?
    public var memberPanelVisible: Bool
    public var messageDensity: MessageDensityPreference
    public var reduceGlassIntensity: Bool
    public var liquidGlassTransparency: Double
    public var inlineImagePreviewPolicy: InlineImagePreviewPolicy
    public var timelineTuning: TimelineTuningConfiguration
    public var notificationPreferences: NotificationPreferences
    public var voicePreferences: VoicePreferences
    public var lastSettingsSyncTimestamp: Int64?

    private enum CodingKeys: String, CodingKey {
        case lastSelectedEnvironmentID
        case environmentProfiles
        case showDeveloperRuntimeControls
        case lastSelectedServerID
        case lastSelectedChannelID
        case memberPanelVisible
        case messageDensity
        case reduceGlassIntensity
        case liquidGlassTransparency
        case inlineImagePreviewPolicy
        case timelineTuning
        case notificationPreferences
        case voicePreferences
        case lastSettingsSyncTimestamp
        case offlineCacheRestoreOnLaunch
        case automaticSettingsSyncEnabled
    }

    public init(
        lastSelectedEnvironmentID: String? = nil,
        environmentProfiles: [EnvironmentProfile] = [EnvironmentProfile.production()],
        showDeveloperRuntimeControls: Bool = false,
        offlineCacheRestoreOnLaunch: Bool = true,
        automaticSettingsSyncEnabled: Bool = true,
        lastSelectedServerID: ServerID? = nil,
        lastSelectedChannelID: ChannelID? = nil,
        memberPanelVisible: Bool = true,
        messageDensity: MessageDensityPreference = .comfortable,
        reduceGlassIntensity: Bool = false,
        liquidGlassTransparency: Double = 1.0,
        inlineImagePreviewPolicy: InlineImagePreviewPolicy = .automaticSmallImages,
        timelineTuning: TimelineTuningConfiguration = .defaults,
        notificationPreferences: NotificationPreferences = .defaults,
        voicePreferences: VoicePreferences = .defaults,
        lastSettingsSyncTimestamp: Int64? = nil
    ) {
        self.lastSelectedEnvironmentID = lastSelectedEnvironmentID
        self.environmentProfiles = Self.normalizedProfiles(environmentProfiles)
        self.showDeveloperRuntimeControls = showDeveloperRuntimeControls
        self.offlineCacheRestoreOnLaunch = offlineCacheRestoreOnLaunch
        self.automaticSettingsSyncEnabled = automaticSettingsSyncEnabled
        self.lastSelectedServerID = lastSelectedServerID
        self.lastSelectedChannelID = lastSelectedChannelID
        self.memberPanelVisible = memberPanelVisible
        self.messageDensity = messageDensity
        self.reduceGlassIntensity = reduceGlassIntensity
        self.liquidGlassTransparency = Self.clampedLiquidGlassTransparency(reduceGlassIntensity && liquidGlassTransparency == 1.0 ? 0.35 : liquidGlassTransparency)
        self.inlineImagePreviewPolicy = inlineImagePreviewPolicy
        self.timelineTuning = timelineTuning.validated()
        self.notificationPreferences = notificationPreferences.validated()
        self.voicePreferences = voicePreferences.validated()
        self.lastSettingsSyncTimestamp = lastSettingsSyncTimestamp
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyReduceGlassIntensity = try container.decodeIfPresent(Bool.self, forKey: .reduceGlassIntensity) ?? false
        self.init(
            lastSelectedEnvironmentID: try container.decodeIfPresent(String.self, forKey: .lastSelectedEnvironmentID),
            environmentProfiles: try container.decodeIfPresent([EnvironmentProfile].self, forKey: .environmentProfiles) ?? [EnvironmentProfile.production()],
            showDeveloperRuntimeControls: try container.decodeIfPresent(Bool.self, forKey: .showDeveloperRuntimeControls) ?? false,
            offlineCacheRestoreOnLaunch: try container.decodeIfPresent(Bool.self, forKey: .offlineCacheRestoreOnLaunch) ?? true,
            automaticSettingsSyncEnabled: try container.decodeIfPresent(Bool.self, forKey: .automaticSettingsSyncEnabled) ?? true,
            lastSelectedServerID: try container.decodeIfPresent(ServerID.self, forKey: .lastSelectedServerID),
            lastSelectedChannelID: try container.decodeIfPresent(ChannelID.self, forKey: .lastSelectedChannelID),
            memberPanelVisible: try container.decodeIfPresent(Bool.self, forKey: .memberPanelVisible) ?? true,
            messageDensity: try container.decodeIfPresent(MessageDensityPreference.self, forKey: .messageDensity) ?? .comfortable,
            reduceGlassIntensity: legacyReduceGlassIntensity,
            liquidGlassTransparency: try container.decodeIfPresent(Double.self, forKey: .liquidGlassTransparency) ?? (legacyReduceGlassIntensity ? 0.35 : 1.0),
            inlineImagePreviewPolicy: try container.decodeIfPresent(InlineImagePreviewPolicy.self, forKey: .inlineImagePreviewPolicy) ?? .automaticSmallImages,
            timelineTuning: try container.decodeIfPresent(TimelineTuningConfiguration.self, forKey: .timelineTuning) ?? .defaults,
            notificationPreferences: try container.decodeIfPresent(NotificationPreferences.self, forKey: .notificationPreferences) ?? .defaults,
            voicePreferences: try container.decodeIfPresent(VoicePreferences.self, forKey: .voicePreferences) ?? .defaults,
            lastSettingsSyncTimestamp: try container.decodeIfPresent(Int64.self, forKey: .lastSettingsSyncTimestamp)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(lastSelectedEnvironmentID, forKey: .lastSelectedEnvironmentID)
        try container.encode(environmentProfiles, forKey: .environmentProfiles)
        try container.encode(showDeveloperRuntimeControls, forKey: .showDeveloperRuntimeControls)
        try container.encode(offlineCacheRestoreOnLaunch, forKey: .offlineCacheRestoreOnLaunch)
        try container.encode(automaticSettingsSyncEnabled, forKey: .automaticSettingsSyncEnabled)
        try container.encodeIfPresent(lastSelectedServerID, forKey: .lastSelectedServerID)
        try container.encodeIfPresent(lastSelectedChannelID, forKey: .lastSelectedChannelID)
        try container.encode(memberPanelVisible, forKey: .memberPanelVisible)
        try container.encode(messageDensity, forKey: .messageDensity)
        try container.encode(reduceGlassIntensity, forKey: .reduceGlassIntensity)
        try container.encode(Self.clampedLiquidGlassTransparency(liquidGlassTransparency), forKey: .liquidGlassTransparency)
        try container.encode(inlineImagePreviewPolicy, forKey: .inlineImagePreviewPolicy)
        try container.encode(timelineTuning.validated(), forKey: .timelineTuning)
        try container.encode(notificationPreferences.validated(), forKey: .notificationPreferences)
        try container.encode(voicePreferences.validated(), forKey: .voicePreferences)
        try container.encodeIfPresent(lastSettingsSyncTimestamp, forKey: .lastSettingsSyncTimestamp)
    }

    public static var defaults: AppPreferences {
        AppPreferences()
    }

    public var selectedEnvironmentProfile: EnvironmentProfile {
        if let lastSelectedEnvironmentID,
           let profile = environmentProfiles.first(where: { $0.id == lastSelectedEnvironmentID }) {
            return profile
        }
        return environmentProfiles.first(where: \.isProduction) ?? .production()
    }

    public var selectedEnvironment: StoatAPIEnvironment {
        selectedEnvironmentProfile.environment
    }

    public func validated() throws -> AppPreferences {
        guard environmentProfiles.contains(where: { $0.id == StoatAPIEnvironment.production.stableID && $0.isProduction }) else {
            throw PersistenceError.missingProductionProfile
        }
        for profile in environmentProfiles {
            if profile.isProduction {
                guard profile.id == StoatAPIEnvironment.production.stableID, profile.environment == .production else {
                    throw PersistenceError.invalidProfile("The production profile must use the built-in production environment.")
                }
            } else {
                try profile.environment.validate()
            }
        }
        var copy = self
        copy.liquidGlassTransparency = Self.clampedLiquidGlassTransparency(liquidGlassTransparency)
        copy.timelineTuning = timelineTuning.validated()
        copy.notificationPreferences = notificationPreferences.validated()
        return copy
    }

    public func withSelectedEnvironmentID(_ id: String?) -> AppPreferences {
        var copy = self
        copy.lastSelectedEnvironmentID = environmentProfiles.contains(where: { $0.id == id }) ? id : StoatAPIEnvironment.production.stableID
        return copy
    }

    public func upserting(profile: EnvironmentProfile) throws -> AppPreferences {
        if profile.isProduction && profile.id != StoatAPIEnvironment.production.stableID {
            throw PersistenceError.invalidProfile("The production profile ID must be production.")
        }
        var copy = self
        copy.environmentProfiles.removeAll { $0.id == profile.id }
        copy.environmentProfiles.append(profile)
        copy.environmentProfiles = Self.normalizedProfiles(copy.environmentProfiles)
        if copy.lastSelectedEnvironmentID == nil {
            copy.lastSelectedEnvironmentID = profile.id
        }
        return try copy.validated()
    }

    public func deletingProfile(id: String) throws -> AppPreferences {
        guard id != StoatAPIEnvironment.production.stableID else {
            throw PersistenceError.productionProfileCannotBeDeleted
        }
        var copy = self
        copy.environmentProfiles.removeAll { $0.id == id && !$0.isProduction }
        if copy.lastSelectedEnvironmentID == id {
            copy.lastSelectedEnvironmentID = StoatAPIEnvironment.production.stableID
        }
        copy.environmentProfiles = Self.normalizedProfiles(copy.environmentProfiles)
        return try copy.validated()
    }

    private static func normalizedProfiles(_ profiles: [EnvironmentProfile]) -> [EnvironmentProfile] {
        var keyed: [String: EnvironmentProfile] = [:]
        for profile in profiles {
            keyed[profile.id] = profile
        }
        keyed[StoatAPIEnvironment.production.stableID] = keyed[StoatAPIEnvironment.production.stableID] ?? .production()
        return keyed.values.sorted { lhs, rhs in
            if lhs.isProduction != rhs.isProduction { return lhs.isProduction }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    public static func clampedLiquidGlassTransparency(_ value: Double) -> Double {
        min(max(value, 0.25), 1.0)
    }
}

public protocol AppPreferencesStore: Sendable {
    func loadPreferences() async throws -> AppPreferences
    func savePreferences(_ preferences: AppPreferences) async throws
    func resetPreferences() async throws
}

public actor UserDefaultsAppPreferencesStore: AppPreferencesStore {
    public static let defaultSuiteName = "LiquidBagel.AppPreferences"
    public static let defaultKey = "appPreferences.v1"

    private let userDefaults: UserDefaults
    private let key: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        suiteName: String? = nil,
        key: String = UserDefaultsAppPreferencesStore.defaultKey,
        encoder: JSONEncoder = .stoat,
        decoder: JSONDecoder = .stoat
    ) {
        if let suiteName, let defaults = UserDefaults(suiteName: suiteName) {
            self.userDefaults = defaults
        } else {
            self.userDefaults = .standard
        }
        self.key = key
        self.encoder = encoder
        self.decoder = decoder
    }

    public func loadPreferences() async throws -> AppPreferences {
        guard let data = userDefaults.data(forKey: key) else {
            return .defaults
        }
        do {
            return try decoder.decode(AppPreferences.self, from: data).validated()
        } catch let error as PersistenceError {
            throw error
        } catch {
            throw PersistenceError.decodingFailed(error.localizedDescription)
        }
    }

    public func savePreferences(_ preferences: AppPreferences) async throws {
        do {
            let validated = try preferences.validated()
            let data = try encoder.encode(validated)
            userDefaults.set(data, forKey: key)
        } catch let error as PersistenceError {
            throw error
        } catch {
            throw PersistenceError.encodingFailed(error.localizedDescription)
        }
    }

    public func resetPreferences() async throws {
        userDefaults.removeObject(forKey: key)
    }

    public func encodedPreferencesData() -> Data? {
        userDefaults.data(forKey: key)
    }
}

public actor InMemoryAppPreferencesStore: AppPreferencesStore {
    private var preferences: AppPreferences
    private let saveError: (any Error & Sendable)?

    public init(preferences: AppPreferences = .defaults, saveError: (any Error & Sendable)? = nil) {
        self.preferences = preferences
        self.saveError = saveError
    }

    public func loadPreferences() async throws -> AppPreferences {
        try preferences.validated()
    }

    public func savePreferences(_ preferences: AppPreferences) async throws {
        if let saveError {
            throw saveError
        }
        self.preferences = try preferences.validated()
    }

    public func resetPreferences() async throws {
        preferences = .defaults
    }
}

/// The allowlisted preference subset synced through the verified `/sync/settings` routes.
/// Environment profiles, launch mode, developer flags, and last-selected IDs intentionally never sync.
public struct SyncedClientPreferences: Codable, Hashable, Sendable {
    public var messageDensity: MessageDensityPreference
    public var liquidGlassTransparency: Double
    public var inlineImagePreviewPolicy: InlineImagePreviewPolicy
    public var notificationPreferences: NotificationPreferences

    public init(
        messageDensity: MessageDensityPreference = .comfortable,
        liquidGlassTransparency: Double = 1.0,
        inlineImagePreviewPolicy: InlineImagePreviewPolicy = .automaticSmallImages,
        notificationPreferences: NotificationPreferences = .defaults
    ) {
        self.messageDensity = messageDensity
        self.liquidGlassTransparency = AppPreferences.clampedLiquidGlassTransparency(liquidGlassTransparency)
        self.inlineImagePreviewPolicy = inlineImagePreviewPolicy
        self.notificationPreferences = notificationPreferences.validated()
    }

    public init(preferences: AppPreferences) {
        self.init(
            messageDensity: preferences.messageDensity,
            liquidGlassTransparency: preferences.liquidGlassTransparency,
            inlineImagePreviewPolicy: preferences.inlineImagePreviewPolicy,
            notificationPreferences: preferences.notificationPreferences
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            messageDensity: try container.decodeIfPresent(MessageDensityPreference.self, forKey: .messageDensity) ?? .comfortable,
            liquidGlassTransparency: try container.decodeIfPresent(Double.self, forKey: .liquidGlassTransparency) ?? 1.0,
            inlineImagePreviewPolicy: try container.decodeIfPresent(InlineImagePreviewPolicy.self, forKey: .inlineImagePreviewPolicy) ?? .automaticSmallImages,
            notificationPreferences: try container.decodeIfPresent(NotificationPreferences.self, forKey: .notificationPreferences) ?? .defaults
        )
    }

    public func apply(to preferences: inout AppPreferences) {
        preferences.messageDensity = messageDensity
        preferences.liquidGlassTransparency = AppPreferences.clampedLiquidGlassTransparency(liquidGlassTransparency)
        preferences.inlineImagePreviewPolicy = inlineImagePreviewPolicy
        preferences.notificationPreferences = notificationPreferences.validated()
    }
}

public protocol ChannelMessageCaching: Sendable {
    func messages(for channelID: ChannelID) async -> [Message]
    /// The cached page plus what the timeline needs to describe it honestly -- notably whether
    /// older messages exist beyond it.
    func history(for channelID: ChannelID) async -> CachedChannelHistory?
    func store(_ history: CachedChannelHistory) async
    func store(_ messages: [Message], for channelID: ChannelID) async
    func remove(channelID: ChannelID) async
    func removeAll() async
}

public extension ChannelMessageCaching {
    func messages(for channelID: ChannelID) async -> [Message] {
        await history(for: channelID)?.messages ?? []
    }

    func store(_ messages: [Message], for channelID: ChannelID) async {
        guard !messages.isEmpty else { return }
        await store(CachedChannelHistory(
            channelID: channelID,
            messages: messages,
            hasMoreBefore: false,
            savedAt: Date()
        ))
    }
}

public struct NoopChannelMessageCache: ChannelMessageCaching {
    public init() {}

    public func history(for channelID: ChannelID) async -> CachedChannelHistory? { nil }
    public func store(_ history: CachedChannelHistory) async {}
    public func remove(channelID: ChannelID) async {}
    public func removeAll() async {}
}

public actor FileChannelMessageCache: ChannelMessageCaching {
    private struct Envelope: Codable {
        var version: Int
        var channelID: ChannelID
        var savedAt: Date
        var messages: [Message]
        /// Absent in v1 payloads, which predate the field. Those cached pages are treated as
        /// complete history, which is the conservative reading: it stops the offline timeline
        /// from advertising older messages it cannot actually fetch.
        var hasMoreBefore: Bool?
    }

    private static let envelopeVersion = 2
    private static let supportedReadVersions: Set<Int> = [1, 2]

    private let directory: URL
    private let maxMessagesPerChannel: Int
    private let maxChannels: Int
    private let maxTotalBytes: Int
    private var isPrepared = false

    /// - Parameter maxMessagesPerChannel: matches `RealtimeStateStore`'s in-memory cap so a
    ///   cached channel opens with the same depth a live one has.
    /// - Parameter maxTotalBytes: a file *count* cap alone is not a size cap. 200 channels of 200
    ///   messages carrying embeds and attachment metadata runs well past 100 MB.
    public init(
        scopeIdentifier: String,
        directory: URL? = nil,
        maxMessagesPerChannel: Int = 200,
        maxChannels: Int = 200,
        maxTotalBytes: Int = 64 * 1024 * 1024
    ) {
        let scope = Self.digest(scopeIdentifier)
        if let directory {
            self.directory = directory.appendingPathComponent(scope, isDirectory: true)
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            // Under the shared SessionCache root so signing out can remove one directory and
            // take message history with it.
            self.directory = base.appendingPathComponent("LiquidBagel/SessionCache/Messages/\(scope)", isDirectory: true)
        }
        self.maxMessagesPerChannel = max(1, maxMessagesPerChannel)
        self.maxChannels = max(1, maxChannels)
        self.maxTotalBytes = max(1, maxTotalBytes)
    }

    public func history(for channelID: ChannelID) async -> CachedChannelHistory? {
        let url = fileURL(for: channelID)
        guard let data = try? Data(contentsOf: url),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              Self.supportedReadVersions.contains(envelope.version),
              envelope.channelID == channelID
        else { return nil }
        // Touch for LRU.
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return CachedChannelHistory(
            channelID: channelID,
            messages: envelope.messages,
            hasMoreBefore: envelope.hasMoreBefore ?? false,
            savedAt: envelope.savedAt
        )
    }

    public func store(_ history: CachedChannelHistory) async {
        guard !history.messages.isEmpty else { return }
        prepareIfNeeded()
        let truncated = history.messages.count > maxMessagesPerChannel
        let envelope = Envelope(
            version: Self.envelopeVersion,
            channelID: history.channelID,
            savedAt: history.savedAt,
            messages: Array(history.messages.suffix(maxMessagesPerChannel)),
            // Dropping the oldest messages to fit the cap creates older history by definition,
            // whatever the caller believed before truncation.
            hasMoreBefore: history.hasMoreBefore || truncated
        )
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        try? data.write(to: fileURL(for: history.channelID), options: .atomic)
        evictIfNeeded()
    }

    public func remove(channelID: ChannelID) async {
        try? FileManager.default.removeItem(at: fileURL(for: channelID))
    }

    public func removeAll() async {
        try? FileManager.default.removeItem(at: directory)
        isPrepared = false
    }

    private func prepareIfNeeded() {
        guard !isPrepared else { return }
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        isPrepared = true
    }

    private func fileURL(for channelID: ChannelID) -> URL {
        directory.appendingPathComponent("\(Self.digest(channelID.rawValue)).json", isDirectory: false)
    }

    private func evictIfNeeded() {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)
        else { return }
        let entries = urls.map { url -> (url: URL, modified: Date, size: Int) in
            let values = try? url.resourceValues(forKeys: Set(keys))
            return (url, values?.contentModificationDate ?? .distantPast, values?.fileSize ?? 0)
        }
        var remaining = entries.sorted { $0.modified > $1.modified }
        var totalBytes = remaining.reduce(0) { $0 + $1.size }

        // Least recently read goes first, until under both the file-count and byte caps.
        while remaining.count > maxChannels || totalBytes > maxTotalBytes {
            guard let evicted = remaining.popLast() else { break }
            try? FileManager.default.removeItem(at: evicted.url)
            totalBytes -= evicted.size
        }
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}
