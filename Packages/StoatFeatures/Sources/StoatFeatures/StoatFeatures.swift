import StoatAPI
import StoatDesignSystem
import StoatPersistence
import StoatRealtime
import StoatUI
import SwiftUI

public struct LiquidBagelRootView: View {
    public init() {}

    public var body: some View {
        PhaseZeroShellView()
    }
}

public struct LiquidBagelSettingsView: View {
    public init() {}

    public var body: some View {
        Form {
            Section("Instance") {
                LabeledContent("API", value: PhaseZeroStatus.current.environment.apiBaseURL.absoluteString)
                LabeledContent("Events", value: PhaseZeroStatus.current.environment.eventsWebSocketURL.absoluteString)
            }

            Section("Status") {
                LabeledContent("App phase", value: "Phase 0")
                LabeledContent("Networking", value: "Not implemented")
                LabeledContent("Persistence", value: "Not implemented")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

public struct PhaseZeroStatus: Equatable, Sendable {
    public var environment: StoatAPIEnvironment
    public var readyFields: [ReadyField]
    public var persistenceScope: PersistenceScope

    public init(
        environment: StoatAPIEnvironment = .official,
        readyFields: [ReadyField] = [.users, .servers, .channels, .members, .channelUnreads],
        persistenceScope: PersistenceScope = PersistenceScope()
    ) {
        self.environment = environment
        self.readyFields = readyFields
        self.persistenceScope = persistenceScope
    }

    public static let current = PhaseZeroStatus()
}
