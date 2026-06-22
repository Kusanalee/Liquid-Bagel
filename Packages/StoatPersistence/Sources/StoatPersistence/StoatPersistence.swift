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

public enum PreferredLaunchMode: String, Codable, Hashable, Sendable {
    case mock
    case rememberLastButDoNotConnect
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

public struct TimelineTuningConfiguration: Codable, Hashable, Sendable {
    public var nearNewestMessageThreshold: Int
    public var visibleRangeUpdateDebounceMilliseconds: Int
    public var loadToUnreadMaxAttempts: Int
    public var referenceFetchMaxAttempts: Int
    public var referenceFetchCooldownSeconds: Int
    public var ackDebounceMilliseconds: Int

    public init(
        nearNewestMessageThreshold: Int = 2,
        visibleRangeUpdateDebounceMilliseconds: Int = 120,
        loadToUnreadMaxAttempts: Int = 4,
        referenceFetchMaxAttempts: Int = 1,
        referenceFetchCooldownSeconds: Int = 60,
        ackDebounceMilliseconds: Int = 1500
    ) {
        self.nearNewestMessageThreshold = nearNewestMessageThreshold
        self.visibleRangeUpdateDebounceMilliseconds = visibleRangeUpdateDebounceMilliseconds
        self.loadToUnreadMaxAttempts = loadToUnreadMaxAttempts
        self.referenceFetchMaxAttempts = referenceFetchMaxAttempts
        self.referenceFetchCooldownSeconds = referenceFetchCooldownSeconds
        self.ackDebounceMilliseconds = ackDebounceMilliseconds
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
            ackDebounceMilliseconds: Self.clamp(ackDebounceMilliseconds, 0...10_000)
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
                ackDebounceMilliseconds: 1400
            )
        case .responsive:
            TimelineTuningConfiguration(
                nearNewestMessageThreshold: 4,
                visibleRangeUpdateDebounceMilliseconds: 60,
                loadToUnreadMaxAttempts: 6,
                referenceFetchMaxAttempts: 2,
                referenceFetchCooldownSeconds: 45,
                ackDebounceMilliseconds: 1000
            )
        case .debugStrict:
            TimelineTuningConfiguration(
                nearNewestMessageThreshold: 0,
                visibleRangeUpdateDebounceMilliseconds: 0,
                loadToUnreadMaxAttempts: 2,
                referenceFetchMaxAttempts: 0,
                referenceFetchCooldownSeconds: 0,
                ackDebounceMilliseconds: 0
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
    public var preferredLaunchMode: PreferredLaunchMode
    public var showDeveloperRuntimeControls: Bool
    public var lastSelectedServerID: ServerID?
    public var lastSelectedChannelID: ChannelID?
    public var memberPanelVisible: Bool
    public var messageDensity: MessageDensityPreference
    public var reduceGlassIntensity: Bool
    public var liquidGlassTransparency: Double
    public var inlineImagePreviewPolicy: InlineImagePreviewPolicy
    public var timelineTuning: TimelineTuningConfiguration
    public var notificationPreferences: NotificationPreferences

    private enum CodingKeys: String, CodingKey {
        case lastSelectedEnvironmentID
        case environmentProfiles
        case preferredLaunchMode
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
    }

    public init(
        lastSelectedEnvironmentID: String? = nil,
        environmentProfiles: [EnvironmentProfile] = [EnvironmentProfile.production()],
        preferredLaunchMode: PreferredLaunchMode = .mock,
        showDeveloperRuntimeControls: Bool = true,
        lastSelectedServerID: ServerID? = nil,
        lastSelectedChannelID: ChannelID? = nil,
        memberPanelVisible: Bool = true,
        messageDensity: MessageDensityPreference = .comfortable,
        reduceGlassIntensity: Bool = false,
        liquidGlassTransparency: Double = 1.0,
        inlineImagePreviewPolicy: InlineImagePreviewPolicy = .automaticSmallImages,
        timelineTuning: TimelineTuningConfiguration = .defaults,
        notificationPreferences: NotificationPreferences = .defaults
    ) {
        self.lastSelectedEnvironmentID = lastSelectedEnvironmentID
        self.environmentProfiles = Self.normalizedProfiles(environmentProfiles)
        self.preferredLaunchMode = preferredLaunchMode
        self.showDeveloperRuntimeControls = showDeveloperRuntimeControls
        self.lastSelectedServerID = lastSelectedServerID
        self.lastSelectedChannelID = lastSelectedChannelID
        self.memberPanelVisible = memberPanelVisible
        self.messageDensity = messageDensity
        self.reduceGlassIntensity = reduceGlassIntensity
        self.liquidGlassTransparency = Self.clampedLiquidGlassTransparency(reduceGlassIntensity && liquidGlassTransparency == 1.0 ? 0.35 : liquidGlassTransparency)
        self.inlineImagePreviewPolicy = inlineImagePreviewPolicy
        self.timelineTuning = timelineTuning.validated()
        self.notificationPreferences = notificationPreferences.validated()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyReduceGlassIntensity = try container.decodeIfPresent(Bool.self, forKey: .reduceGlassIntensity) ?? false
        self.init(
            lastSelectedEnvironmentID: try container.decodeIfPresent(String.self, forKey: .lastSelectedEnvironmentID),
            environmentProfiles: try container.decodeIfPresent([EnvironmentProfile].self, forKey: .environmentProfiles) ?? [EnvironmentProfile.production()],
            preferredLaunchMode: try container.decodeIfPresent(PreferredLaunchMode.self, forKey: .preferredLaunchMode) ?? .mock,
            showDeveloperRuntimeControls: try container.decodeIfPresent(Bool.self, forKey: .showDeveloperRuntimeControls) ?? true,
            lastSelectedServerID: try container.decodeIfPresent(ServerID.self, forKey: .lastSelectedServerID),
            lastSelectedChannelID: try container.decodeIfPresent(ChannelID.self, forKey: .lastSelectedChannelID),
            memberPanelVisible: try container.decodeIfPresent(Bool.self, forKey: .memberPanelVisible) ?? true,
            messageDensity: try container.decodeIfPresent(MessageDensityPreference.self, forKey: .messageDensity) ?? .comfortable,
            reduceGlassIntensity: legacyReduceGlassIntensity,
            liquidGlassTransparency: try container.decodeIfPresent(Double.self, forKey: .liquidGlassTransparency) ?? (legacyReduceGlassIntensity ? 0.35 : 1.0),
            inlineImagePreviewPolicy: try container.decodeIfPresent(InlineImagePreviewPolicy.self, forKey: .inlineImagePreviewPolicy) ?? .automaticSmallImages,
            timelineTuning: try container.decodeIfPresent(TimelineTuningConfiguration.self, forKey: .timelineTuning) ?? .defaults,
            notificationPreferences: try container.decodeIfPresent(NotificationPreferences.self, forKey: .notificationPreferences) ?? .defaults
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(lastSelectedEnvironmentID, forKey: .lastSelectedEnvironmentID)
        try container.encode(environmentProfiles, forKey: .environmentProfiles)
        try container.encode(preferredLaunchMode, forKey: .preferredLaunchMode)
        try container.encode(showDeveloperRuntimeControls, forKey: .showDeveloperRuntimeControls)
        try container.encodeIfPresent(lastSelectedServerID, forKey: .lastSelectedServerID)
        try container.encodeIfPresent(lastSelectedChannelID, forKey: .lastSelectedChannelID)
        try container.encode(memberPanelVisible, forKey: .memberPanelVisible)
        try container.encode(messageDensity, forKey: .messageDensity)
        try container.encode(reduceGlassIntensity, forKey: .reduceGlassIntensity)
        try container.encode(Self.clampedLiquidGlassTransparency(liquidGlassTransparency), forKey: .liquidGlassTransparency)
        try container.encode(inlineImagePreviewPolicy, forKey: .inlineImagePreviewPolicy)
        try container.encode(timelineTuning.validated(), forKey: .timelineTuning)
        try container.encode(notificationPreferences.validated(), forKey: .notificationPreferences)
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

public protocol StoatCacheRepository: Sendable {
    func cachedCurrentUser() async throws -> User?
}

public struct EmptyStoatCacheRepository: StoatCacheRepository {
    public init() {}

    public func cachedCurrentUser() async throws -> User? {
        nil
    }
}
