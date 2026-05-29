import Foundation
import Observation
import StoatAPI
import StoatModels
import StoatPersistence

public protocol SessionManaging: Sendable {
    func listSessions(environment: StoatAPIEnvironment, credential: StoatAuthCredential) async throws -> [SessionInfo]
    func renameSession(id: SessionID, friendlyName: String, environment: StoatAPIEnvironment, credential: StoatAuthCredential) async throws -> SessionInfo
    func revokeSession(id: SessionID, environment: StoatAPIEnvironment, credential: StoatAuthCredential) async throws
    func revokeAllSessions(revokeSelf: Bool, environment: StoatAPIEnvironment, credential: StoatAuthCredential) async throws
    func logoutCurrentSession(environment: StoatAPIEnvironment, credential: StoatAuthCredential) async throws
}

public struct LiveSessionManager: SessionManaging {
    private let apiClientFactory: @Sendable (StoatAPIEnvironment, any CredentialProvider) -> any StoatAPIClient

    public init(
        apiClientFactory: @escaping @Sendable (StoatAPIEnvironment, any CredentialProvider) -> any StoatAPIClient = { environment, provider in
            LiveStoatAPIClient(environment: environment, credentialProvider: provider)
        }
    ) {
        self.apiClientFactory = apiClientFactory
    }

    public func listSessions(environment: StoatAPIEnvironment, credential: StoatAuthCredential) async throws -> [SessionInfo] {
        try await apiClient(environment: environment, credential: credential).fetchSessions()
    }

    public func renameSession(id: SessionID, friendlyName: String, environment: StoatAPIEnvironment, credential: StoatAuthCredential) async throws -> SessionInfo {
        try await apiClient(environment: environment, credential: credential).renameSession(id: id, friendlyName: friendlyName)
    }

    public func revokeSession(id: SessionID, environment: StoatAPIEnvironment, credential: StoatAuthCredential) async throws {
        try await apiClient(environment: environment, credential: credential).revokeSession(id: id)
    }

    public func revokeAllSessions(revokeSelf: Bool, environment: StoatAPIEnvironment, credential: StoatAuthCredential) async throws {
        try await apiClient(environment: environment, credential: credential).revokeAllSessions(revokeSelf: revokeSelf)
    }

    public func logoutCurrentSession(environment: StoatAPIEnvironment, credential: StoatAuthCredential) async throws {
        try await apiClient(environment: environment, credential: credential).logoutCurrentSession()
    }

    private func apiClient(environment: StoatAPIEnvironment, credential: StoatAuthCredential) -> any StoatAPIClient {
        apiClientFactory(environment, StaticCredentialProvider(credential))
    }
}

public actor MockSessionManager: SessionManaging {
    public private(set) var revokeAllArguments: [Bool] = []
    public private(set) var revokedSessionIDs: [SessionID] = []
    public private(set) var renamedSessions: [(SessionID, String)] = []
    public private(set) var logoutCallCount = 0

    private var sessions: [SessionInfo]
    private let error: (any Error & Sendable)?

    public init(sessions: [SessionInfo] = [], error: (any Error & Sendable)? = nil) {
        self.sessions = sessions
        self.error = error
    }

    public func listSessions(environment: StoatAPIEnvironment, credential: StoatAuthCredential) async throws -> [SessionInfo] {
        if let error { throw error }
        return sessions
    }

    public func renameSession(id: SessionID, friendlyName: String, environment: StoatAPIEnvironment, credential: StoatAuthCredential) async throws -> SessionInfo {
        if let error { throw error }
        let renamed = SessionInfo(id: id, name: friendlyName)
        sessions.removeAll { $0.id == id }
        sessions.append(renamed)
        renamedSessions.append((id, friendlyName))
        return renamed
    }

    public func revokeSession(id: SessionID, environment: StoatAPIEnvironment, credential: StoatAuthCredential) async throws {
        if let error { throw error }
        sessions.removeAll { $0.id == id }
        revokedSessionIDs.append(id)
    }

    public func revokeAllSessions(revokeSelf: Bool, environment: StoatAPIEnvironment, credential: StoatAuthCredential) async throws {
        if let error { throw error }
        revokeAllArguments.append(revokeSelf)
        if revokeSelf {
            sessions.removeAll()
        }
    }

    public func logoutCurrentSession(environment: StoatAPIEnvironment, credential: StoatAuthCredential) async throws {
        if let error { throw error }
        logoutCallCount += 1
    }
}

public struct AccountSession: Hashable, Identifiable, Sendable {
    public var id: SessionID
    public var friendlyName: String
    public var createdAt: Date?
    public var isCurrent: Bool

    public init(info: SessionInfo, currentSessionID: SessionID?) {
        self.id = info.id
        self.friendlyName = info.name
        self.createdAt = Message.dateFromULID(info.id.rawValue)
        self.isCurrent = info.id == currentSessionID
    }
}

public enum SessionsState: Equatable, Sendable {
    case idle
    case loading
    case loaded([AccountSession])
    case empty
    case failed(String)

    public var sessions: [AccountSession] {
        if case let .loaded(sessions) = self { return sessions }
        return []
    }
}

public enum Phase6ValidationError: Error, Equatable, Sendable, LocalizedError {
    case missingCredential
    case blankFriendlyName
    case missingCoordinator

    public var errorDescription: String? {
        switch self {
        case .missingCredential:
            return "No saved credential is available for the selected environment."
        case .blankFriendlyName:
            return "Session name cannot be blank."
        case .missingCoordinator:
            return "Session coordinator is unavailable."
        }
    }
}

@MainActor
@Observable
public final class AccountSessionViewModel {
    public private(set) var currentUser: User?
    public private(set) var environment: StoatAPIEnvironment
    public private(set) var currentSessionID: SessionID?
    public private(set) var lastValidatedAt: Date?
    public private(set) var sessionsState: SessionsState
    public var errorMessage: String?

    @ObservationIgnored private weak var coordinator: AppSessionCoordinator?
    @ObservationIgnored private let sessionManager: any SessionManaging
    @ObservationIgnored private let credentialProvider: @Sendable () async throws -> StoatAuthCredential?

    public init(
        coordinator: AppSessionCoordinator?,
        sessionManager: any SessionManaging = LiveSessionManager()
    ) {
        self.coordinator = coordinator
        self.sessionManager = sessionManager
        self.currentUser = coordinator?.currentUser
        self.environment = coordinator?.environment ?? .production
        self.lastValidatedAt = coordinator?.validatedSession?.validatedAt
        self.currentSessionID = coordinator?.validatedSession?.credential.sessionID
        self.sessionsState = .idle
        self.credentialProvider = { [weak coordinator] in
            guard let coordinator else { return nil }
            return try await coordinator.credentialForCurrentEnvironment()
        }
    }

    public init(
        currentUser: User? = nil,
        environment: StoatAPIEnvironment = .production,
        currentSessionID: SessionID? = nil,
        lastValidatedAt: Date? = nil,
        sessionManager: any SessionManaging,
        credentialProvider: @escaping @Sendable () async throws -> StoatAuthCredential?
    ) {
        self.coordinator = nil
        self.sessionManager = sessionManager
        self.currentUser = currentUser
        self.environment = environment
        self.currentSessionID = currentSessionID
        self.lastValidatedAt = lastValidatedAt
        self.sessionsState = .idle
        self.credentialProvider = credentialProvider
    }

    public func syncFromCoordinator() {
        guard let coordinator else { return }
        currentUser = coordinator.currentUser
        environment = coordinator.environment
        lastValidatedAt = coordinator.validatedSession?.validatedAt
        currentSessionID = coordinator.validatedSession?.credential.sessionID
    }

    public func refreshSessions() async {
        syncFromCoordinator()
        sessionsState = .loading
        errorMessage = nil
        do {
            let credential = try await requireCredential()
            let infos = try await sessionManager.listSessions(environment: environment, credential: credential)
            let sessions = infos
                .map { AccountSession(info: $0, currentSessionID: credential.sessionID ?? currentSessionID) }
                .sorted { lhs, rhs in
                    switch (lhs.createdAt, rhs.createdAt) {
                    case let (left?, right?):
                        return left > right
                    case (_?, nil):
                        return true
                    case (nil, _?):
                        return false
                    case (nil, nil):
                        return lhs.friendlyName.localizedCaseInsensitiveCompare(rhs.friendlyName) == .orderedAscending
                    }
                }
            sessionsState = sessions.isEmpty ? .empty : .loaded(sessions)
        } catch {
            let message = error.userFacingMessage
            sessionsState = .failed(message)
            errorMessage = message
        }
    }

    public func renameSession(id: SessionID, friendlyName: String) async {
        let trimmed = friendlyName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = Phase6ValidationError.blankFriendlyName.errorDescription
            return
        }
        do {
            let credential = try await requireCredential()
            let updated = try await sessionManager.renameSession(id: id, friendlyName: trimmed, environment: environment, credential: credential)
            replaceSession(AccountSession(info: updated, currentSessionID: credential.sessionID ?? currentSessionID))
            errorMessage = nil
        } catch {
            errorMessage = error.userFacingMessage
        }
    }

    public func revokeSession(id: SessionID) async {
        do {
            let credential = try await requireCredential()
            try await sessionManager.revokeSession(id: id, environment: environment, credential: credential)
            removeSession(id: id)
            if id == credential.sessionID {
                await coordinator?.forgetLocalSession()
                syncFromCoordinator()
            }
            errorMessage = nil
        } catch {
            errorMessage = error.userFacingMessage
        }
    }

    public func revokeAllOtherSessions() async {
        do {
            let credential = try await requireCredential()
            try await sessionManager.revokeAllSessions(revokeSelf: false, environment: environment, credential: credential)
            let currentID = credential.sessionID ?? currentSessionID
            if case let .loaded(sessions) = sessionsState, let currentID {
                let filtered = sessions.filter { $0.id == currentID }
                sessionsState = filtered.isEmpty ? .empty : .loaded(filtered)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.userFacingMessage
        }
    }

    public func logoutCurrentSession() async {
        do {
            let credential = try await requireCredential()
            try await sessionManager.logoutCurrentSession(environment: environment, credential: credential)
            await coordinator?.forgetLocalSession()
            syncFromCoordinator()
            sessionsState = .idle
            errorMessage = nil
        } catch {
            errorMessage = error.userFacingMessage
        }
    }

    private func requireCredential() async throws -> StoatAuthCredential {
        guard let credential = try await credentialProvider() else {
            throw Phase6ValidationError.missingCredential
        }
        return credential
    }

    private func replaceSession(_ session: AccountSession) {
        guard case var .loaded(sessions) = sessionsState else { return }
        sessions.removeAll { $0.id == session.id }
        sessions.append(session)
        sessionsState = .loaded(sessions.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) })
    }

    private func removeSession(id: SessionID) {
        guard case var .loaded(sessions) = sessionsState else { return }
        sessions.removeAll { $0.id == id }
        sessionsState = sessions.isEmpty ? .empty : .loaded(sessions)
    }
}

@MainActor
@Observable
public final class ConnectionSettingsViewModel {
    public var preferences: AppPreferences
    public var environmentProfiles: [EnvironmentProfile]
    public var selectedEnvironmentID: String?
    public var errorMessage: String?

    @ObservationIgnored private weak var coordinator: AppSessionCoordinator?
    @ObservationIgnored private let preferencesStore: any AppPreferencesStore
    @ObservationIgnored private let tokenStore: (any ScopedTokenStore)?

    public init(coordinator: AppSessionCoordinator?) {
        let initialPreferences = coordinator?.preferences ?? .defaults
        self.coordinator = coordinator
        self.preferencesStore = InMemoryAppPreferencesStore(preferences: initialPreferences)
        self.tokenStore = nil
        self.preferences = initialPreferences
        self.environmentProfiles = initialPreferences.environmentProfiles
        self.selectedEnvironmentID = initialPreferences.lastSelectedEnvironmentID ?? initialPreferences.selectedEnvironmentProfile.id
    }

    public init(
        preferencesStore: any AppPreferencesStore,
        tokenStore: (any ScopedTokenStore)? = nil,
        preferences: AppPreferences = .defaults
    ) {
        self.coordinator = nil
        self.preferencesStore = preferencesStore
        self.tokenStore = tokenStore
        self.preferences = preferences
        self.environmentProfiles = preferences.environmentProfiles
        self.selectedEnvironmentID = preferences.lastSelectedEnvironmentID ?? preferences.selectedEnvironmentProfile.id
    }

    public func load() async {
        if let coordinator {
            preferences = coordinator.preferences
        } else {
            do {
                preferences = try await preferencesStore.loadPreferences()
            } catch {
                errorMessage = error.userFacingMessage
                preferences = .defaults
            }
        }
        environmentProfiles = preferences.environmentProfiles
        selectedEnvironmentID = preferences.lastSelectedEnvironmentID ?? preferences.selectedEnvironmentProfile.id
    }

    public func save() async {
        do {
            if let coordinator {
                await coordinator.savePreferences(preferences)
            } else {
                try await preferencesStore.savePreferences(preferences)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.userFacingMessage
        }
    }

    public func selectEnvironment(id: String) async {
        guard environmentProfiles.contains(where: { $0.id == id }) else {
            errorMessage = "Environment profile was not found."
            return
        }
        selectedEnvironmentID = id
        preferences = preferences.withSelectedEnvironmentID(id)
        if let coordinator {
            await coordinator.selectEnvironmentProfile(id: id)
            preferences = coordinator.preferences
            environmentProfiles = preferences.environmentProfiles
        } else {
            await save()
        }
    }

    public func addEnvironment(name: String, apiURL: String, eventsURL: String, mediaURL: String? = nil) async {
        do {
            let profile = try Self.makeProfile(name: name, apiURL: apiURL, eventsURL: eventsURL, mediaURL: mediaURL)
            preferences = try preferences.upserting(profile: profile).withSelectedEnvironmentID(profile.id)
            environmentProfiles = preferences.environmentProfiles
            selectedEnvironmentID = profile.id
            if let coordinator {
                await coordinator.upsertEnvironmentProfile(profile)
                preferences = coordinator.preferences
                environmentProfiles = preferences.environmentProfiles
            } else {
                await save()
            }
            errorMessage = nil
        } catch {
            errorMessage = error.userFacingMessage
        }
    }

    public func updateEnvironment(id: String, name: String, apiURL: String, eventsURL: String, mediaURL: String? = nil) async {
        guard let existing = environmentProfiles.first(where: { $0.id == id }) else {
            errorMessage = "Environment profile was not found."
            return
        }
        do {
            let environment = try Self.makeEnvironment(apiURL: apiURL, eventsURL: eventsURL, mediaURL: mediaURL)
            let updated = try existing.updating(name: name, environment: environment)
            preferences = try preferences.deletingProfile(id: id).upserting(profile: updated).withSelectedEnvironmentID(updated.id)
            environmentProfiles = preferences.environmentProfiles
            selectedEnvironmentID = updated.id
            if let coordinator {
                await coordinator.upsertEnvironmentProfile(updated)
                preferences = coordinator.preferences
                environmentProfiles = preferences.environmentProfiles
            } else {
                await save()
            }
            errorMessage = nil
        } catch {
            errorMessage = error.userFacingMessage
        }
    }

    public func deleteEnvironment(id: String, forgetCredential: Bool = false) async {
        do {
            preferences = try preferences.deletingProfile(id: id)
            environmentProfiles = preferences.environmentProfiles
            selectedEnvironmentID = preferences.selectedEnvironmentProfile.id
            if let coordinator {
                await coordinator.deleteEnvironmentProfile(id: id, forgetCredential: forgetCredential)
                preferences = coordinator.preferences
                environmentProfiles = preferences.environmentProfiles
                selectedEnvironmentID = preferences.selectedEnvironmentProfile.id
            } else {
                if forgetCredential {
                    try await tokenStore?.clearCredential(scope: CredentialScope(environmentID: id))
                }
                await save()
            }
            errorMessage = nil
        } catch {
            errorMessage = error.userFacingMessage
        }
    }

    public func credentialExists(profileID: String) async -> Bool {
        if let coordinator {
            return await coordinator.credentialExists(environmentID: profileID)
        }
        guard let tokenStore else { return false }
        return (try? await tokenStore.loadCredential(scope: CredentialScope(environmentID: profileID))) != nil
    }

    public static func makeProfile(name: String, apiURL: String, eventsURL: String, mediaURL: String?) throws -> EnvironmentProfile {
        try EnvironmentProfile.custom(name: name, environment: makeEnvironment(apiURL: apiURL, eventsURL: eventsURL, mediaURL: mediaURL))
    }

    public static func makeEnvironment(apiURL: String, eventsURL: String, mediaURL: String?) throws -> StoatAPIEnvironment {
        let apiString = apiURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let eventsString = eventsURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let api = URL(string: apiString), let events = URL(string: eventsString) else {
            throw PersistenceError.invalidProfile("API and events URLs must be valid.")
        }
        let mediaString = mediaURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let media = mediaString.isEmpty ? nil : URL(string: mediaString)
        if !mediaString.isEmpty, media == nil {
            throw PersistenceError.invalidProfile("Media URL must be valid.")
        }
        return try StoatAPIEnvironment.custom(apiBaseURL: api, eventsURL: events, mediaBaseURL: media ?? nil)
    }
}

public enum Phase6UIHelpers {
    public static func shortenedSessionID(_ id: SessionID) -> String {
        let value = id.rawValue
        guard value.count > 10 else { return value }
        return "\(value.prefix(6))...\(value.suffix(4))"
    }

    public static func environmentDisplayName(_ profile: EnvironmentProfile) -> String {
        profile.isProduction ? "Stoat Production" : profile.name
    }

    public static func credentialPresenceLabel(hasCredential: Bool) -> String {
        hasCredential ? "Credential saved for this environment" : "No saved credential"
    }

    public static func safeDiagnostics(_ text: String) -> String {
        var output = text
        for pattern in ["token=[^\\s,]+", "X-Session-Token: [^\\s,]+", "X-Bot-Token: [^\\s,]+"] {
            output = output.replacingOccurrences(of: pattern, with: "token=<redacted>", options: .regularExpression)
        }
        return output
    }
}

private extension StoatAuthCredential {
    var sessionID: SessionID? {
        switch self {
        case let .userSession(_, sessionID):
            return sessionID
        case .botToken:
            return nil
        }
    }
}
