import StoatAPI
import StoatDesignSystem
import StoatModels
import StoatPersistence
import StoatRealtime
import StoatUI
import SwiftUI

public struct LiquidBagelRootView: View {
    @StateObject private var model = LiquidBagelMockModel()

    public init() {}

    public var body: some View {
        PhaseZeroShellView(snapshot: model.snapshot)
            .task {
                await model.load()
            }
    }
}

@MainActor
private final class LiquidBagelMockModel: ObservableObject {
    @Published var snapshot: StoatUISnapshot = .placeholder

    private let apiClient: any StoatAPIClient

    init(apiClient: any StoatAPIClient = MockStoatAPIClient()) {
        self.apiClient = apiClient
    }

    func load() async {
        do {
            async let currentUser = apiClient.fetchCurrentUser()
            async let servers = apiClient.fetchServers()
            async let channels = apiClient.fetchChannels()

            let loadedCurrentUser = try await currentUser
            let loadedServers = try await servers
            let loadedChannels = try await channels
            let loadedMessages: [Message]
            if let firstChannelID = loadedChannels.first?.id {
                loadedMessages = try await apiClient.fetchMessages(channelID: firstChannelID, before: nil, after: nil, limit: 50)
            } else {
                loadedMessages = []
            }

            let authorIDs = Set(loadedMessages.map(\.authorID))
            let messageUsers = loadedMessages.compactMap(\.user)
            let existingUsers = [loadedCurrentUser] + messageUsers
            let users = existingUsers + authorIDs
                .filter { id in !existingUsers.contains { $0.id == id } }
                .map { User(id: $0, username: $0.rawValue) }

            snapshot = StoatUISnapshot(
                currentUser: loadedCurrentUser,
                users: users,
                servers: loadedServers,
                channels: loadedChannels,
                messages: loadedMessages
            )
        } catch {
            snapshot = .placeholder
        }
    }
}

public struct LiquidBagelSettingsView: View {
    public init() {}

    public var body: some View {
        Form {
            Section("Instance") {
                LabeledContent("API", value: PhaseOneStatus.current.environment.apiBaseURL.absoluteString)
                LabeledContent("Events", value: PhaseOneStatus.current.environment.eventsURL.absoluteString)
                LabeledContent("Media", value: PhaseOneStatus.current.environment.mediaBaseURL?.absoluteString ?? "Not configured")
            }

            Section("Status") {
                LabeledContent("App phase", value: "Phase 1")
                LabeledContent("Networking", value: "Mock UI, verified REST foundation")
                LabeledContent("Persistence", value: "Not implemented")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

public struct PhaseOneStatus: Equatable, Sendable {
    public var environment: StoatAPIEnvironment
    public var readyFields: [ReadyField]
    public var persistenceScope: PersistenceScope

    public init(
        environment: StoatAPIEnvironment = .production,
        readyFields: [ReadyField] = [.users, .servers, .channels, .members, .channelUnreads],
        persistenceScope: PersistenceScope = PersistenceScope()
    ) {
        self.environment = environment
        self.readyFields = readyFields
        self.persistenceScope = persistenceScope
    }

    public static let current = PhaseOneStatus()
}

public typealias PhaseZeroStatus = PhaseOneStatus
