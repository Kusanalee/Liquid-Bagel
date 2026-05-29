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

public enum MessageDensityPreference: String, Codable, Hashable, Sendable, CaseIterable {
    case comfortable
    case compact
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

    public init(
        lastSelectedEnvironmentID: String? = nil,
        environmentProfiles: [EnvironmentProfile] = [EnvironmentProfile.production()],
        preferredLaunchMode: PreferredLaunchMode = .mock,
        showDeveloperRuntimeControls: Bool = true,
        lastSelectedServerID: ServerID? = nil,
        lastSelectedChannelID: ChannelID? = nil,
        memberPanelVisible: Bool = true,
        messageDensity: MessageDensityPreference = .comfortable,
        reduceGlassIntensity: Bool = false
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
        return self
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
