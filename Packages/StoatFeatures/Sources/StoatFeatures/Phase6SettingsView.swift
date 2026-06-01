import StoatAPI
import StoatDesignSystem
import StoatModels
import StoatPersistence
import StoatUI
import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

public struct AccountConnectionSettingsView: View {
    @Bindable private var viewModel: MainShellViewModel
    @State private var accountViewModel: AccountSessionViewModel
    @State private var connectionViewModel: ConnectionSettingsViewModel
    @State private var credentialPresenceByProfileID: [String: Bool] = [:]
    @State private var pendingRevokeSession: AccountSession?
    @State private var confirmRevokeAllOthers = false
    @State private var confirmLogoutCurrent = false
    @State private var pendingDeleteProfile: EnvironmentProfile?
    @State private var deleteProfileForgetsCredential = false

    public init(viewModel: MainShellViewModel) {
        self.viewModel = viewModel
        _accountViewModel = State(initialValue: AccountSessionViewModel(coordinator: viewModel.sessionCoordinator))
        _connectionViewModel = State(initialValue: ConnectionSettingsViewModel(coordinator: viewModel.sessionCoordinator))
    }

    public var body: some View {
        TabView(selection: $viewModel.selectedSettingsTab) {
            AccountSettingsTab(viewModel: viewModel, accountViewModel: accountViewModel)
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
                .tag(SettingsSectionTab.account)

            SessionsSettingsTab(
                accountViewModel: accountViewModel,
                pendingRevokeSession: $pendingRevokeSession,
                confirmRevokeAllOthers: $confirmRevokeAllOthers
            )
            .tabItem { Label("Sessions", systemImage: "macwindow") }
            .tag(SettingsSectionTab.sessions)

            ConnectionSettingsTab(
                viewModel: viewModel,
                connectionViewModel: connectionViewModel,
                credentialPresenceByProfileID: credentialPresenceByProfileID,
                pendingDeleteProfile: $pendingDeleteProfile,
                deleteProfileForgetsCredential: $deleteProfileForgetsCredential,
                refreshCredentials: { Task { await refreshCredentialPresence() } }
            )
            .tabItem { Label("Connection", systemImage: "network") }
            .tag(SettingsSectionTab.connection)

            DeveloperVerificationTab(viewModel: viewModel)
                .tabItem { Label("Developer", systemImage: "checklist") }
                .tag(SettingsSectionTab.developer)
        }
        .padding()
        .frame(width: 760, height: 780)
        .task {
            await connectionViewModel.load()
            accountViewModel.syncFromCoordinator()
            await refreshCredentialPresence()
            if viewModel.selectedSettingsTab == .sessions {
                await accountViewModel.refreshSessions()
            }
        }
        .onChange(of: viewModel.selectedSettingsTab) { _, tab in
            if tab == .sessions {
                Task { await accountViewModel.refreshSessions() }
            }
        }
        .confirmationDialog(
            "Revoke this session?",
            isPresented: Binding(
                get: { pendingRevokeSession != nil },
                set: { if !$0 { pendingRevokeSession = nil } }
            )
        ) {
            Button(pendingRevokeSession?.isCurrent == true ? "Revoke Current Session" : "Revoke Session", role: .destructive) {
                Task {
                    guard let pendingRevokeSession else { return }
                    await accountViewModel.revokeSession(id: pendingRevokeSession.id)
                    viewModel.syncFromSessionCoordinator()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if pendingRevokeSession?.isCurrent == true {
                Text("This may disconnect Liquid Bagel and will remove the local Keychain credential after revocation.")
            } else {
                Text("This logs out the selected session on the server. It does not expose any token.")
            }
        }
        .confirmationDialog("Log out other sessions?", isPresented: $confirmRevokeAllOthers) {
            Button("Log Out Other Sessions", role: .destructive) {
                Task { await accountViewModel.revokeAllOtherSessions() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This keeps this device active and asks Stoat to revoke other active sessions.")
        }
        .confirmationDialog("Revoke current session?", isPresented: $confirmLogoutCurrent) {
            Button("Revoke Current Session", role: .destructive) {
                Task {
                    await accountViewModel.logoutCurrentSession()
                    viewModel.syncFromSessionCoordinator()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This asks Stoat to invalidate this session, disconnects live realtime, and removes the local Keychain credential if the server accepts the request.")
        }
        .confirmationDialog(
            "Delete environment profile?",
            isPresented: Binding(
                get: { pendingDeleteProfile != nil },
                set: { if !$0 { pendingDeleteProfile = nil } }
            )
        ) {
            Button(deleteProfileForgetsCredential ? "Delete Profile and Forget Credential" : "Delete Profile", role: .destructive) {
                Task {
                    guard let pendingDeleteProfile else { return }
                    await connectionViewModel.deleteEnvironment(id: pendingDeleteProfile.id, forgetCredential: deleteProfileForgetsCredential)
                    viewModel.syncFromSessionCoordinator()
                    await refreshCredentialPresence()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let pendingDeleteProfile, credentialPresenceByProfileID[pendingDeleteProfile.id] == true {
                Text(deleteProfileForgetsCredential ? "This removes the profile and clears its scoped Keychain credential." : "This removes only the profile. A scoped Keychain credential may remain.")
            } else {
                Text("The production profile cannot be deleted. Custom profile deletion does not affect tokens unless explicitly requested.")
            }
        }
    }

    private func refreshCredentialPresence() async {
        var values: [String: Bool] = [:]
        for profile in connectionViewModel.environmentProfiles {
            values[profile.id] = await connectionViewModel.credentialExists(profileID: profile.id)
        }
        credentialPresenceByProfileID = values
    }
}

private struct AccountSettingsTab: View {
    @Bindable var viewModel: MainShellViewModel
    let accountViewModel: AccountSessionViewModel
    @State private var confirmForget = false
    @State private var confirmRevoke = false

    var body: some View {
        Form {
            Section("Account") {
                if let user = accountViewModel.currentUser ?? viewModel.sessionCoordinator?.currentUser {
                    HStack(spacing: StoatSpacing.medium) {
                        AvatarView(title: user.displayName ?? user.username, subtitle: user.username, size: 48, isOnline: user.online)
                        VStack(alignment: .leading) {
                            Text(user.displayName ?? user.username)
                                .font(.headline)
                            Text("@\(user.username)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("User ID") {
                        HStack {
                            Text(user.id.rawValue)
                                .textSelection(.enabled)
                            Button {
                                #if canImport(AppKit)
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(user.id.rawValue, forType: .string)
                                #endif
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.borderless)
                            .help("Copy User ID")
                        }
                    }
                } else {
                    ContentUnavailableView("No validated account", systemImage: "person.crop.circle.badge.questionmark", description: Text("Validate a saved session or connect manually to show account details."))
                }
                LabeledContent("Environment", value: viewModel.sessionCoordinator?.environment.isProduction == true ? "Stoat Production" : "Custom")
                LabeledContent("Validation", value: validationText)
                if let date = accountViewModel.lastValidatedAt ?? viewModel.sessionCoordinator?.validatedSession?.validatedAt {
                    LabeledContent("Last validated", value: date.formatted(date: .abbreviated, time: .standard))
                }
                LabeledContent("Credential", value: viewModel.sessionCoordinator?.hasSavedCredential == true ? "Token stored in Keychain" : "No saved credential")
            }

            Section("Actions") {
                HStack {
                    Button("Validate Saved Session") {
                        Task {
                            await viewModel.sessionCoordinator?.validateSavedSession()
                            viewModel.syncFromSessionCoordinator()
                        }
                    }
                    .disabled(viewModel.sessionCoordinator?.hasSavedCredential != true)

                    Button("Connect Manually") {
                        Task { await viewModel.connectLiveManually() }
                    }
                    .disabled(viewModel.sessionCoordinator?.hasSavedCredential != true || isDisconnectable)

                    Button("Disconnect") {
                        Task { await viewModel.disconnectLive() }
                    }
                    .disabled(!isDisconnectable)

                    Button("Reconnect") {
                        Task { await viewModel.reconnectLiveManually() }
                    }
                    .disabled(viewModel.sessionCoordinator?.hasSavedCredential != true || isConnecting)
                }
                HStack {
                    Button("Forget Local Session", role: .destructive) {
                        confirmForget = true
                    }
                    .disabled(viewModel.sessionCoordinator?.hasSavedCredential != true)

                    Button("Revoke Current Session", role: .destructive) {
                        confirmRevoke = true
                    }
                    .disabled(viewModel.sessionCoordinator?.hasSavedCredential != true)

                    Button("Reset to Mock") {
                        Task { await viewModel.resetToMock() }
                    }
                }
            }

            Section("Connection Health") {
                if let coordinator = viewModel.sessionCoordinator {
                    LabeledContent("Health", value: Phase6UIHelpers.connectionHealthText(state: coordinator.connectionState, diagnostics: coordinator.diagnostics, hydration: coordinator.hydrationStatus))
                    LabeledContent("Hydration", value: Phase6UIHelpers.hydrationLabel(coordinator.hydrationStatus))
                    LabeledContent("Mode", value: viewModel.effectiveRuntimeMode == .liveManual ? "Live Manual" : "Mock")
                    LabeledContent("Ready", value: coordinator.hydrationStatus.readyReceived ? "Received" : "Waiting")
                    LabeledContent("Servers", value: "\(coordinator.hydrationStatus.serverCount)")
                    LabeledContent("Channels", value: "\(coordinator.hydrationStatus.channelCount)")
                    LabeledContent("Members", value: "\(coordinator.hydrationStatus.memberCount)")
                    if let connectedAt = coordinator.diagnostics?.connectedAt {
                        LabeledContent("Last connected", value: connectedAt.formatted(date: .abbreviated, time: .standard))
                    }
                    if let readyAt = coordinator.diagnostics?.readyAt {
                        LabeledContent("Last Ready", value: readyAt.formatted(date: .abbreviated, time: .standard))
                    }
                    if let eventAt = coordinator.diagnostics?.lastReceivedEventAt {
                        LabeledContent("Last event", value: eventAt.formatted(date: .abbreviated, time: .standard))
                    }
                    if let nonControlAt = coordinator.diagnostics?.lastNonControlEventAt {
                        LabeledContent("Last non-control event", value: nonControlAt.formatted(date: .abbreviated, time: .standard))
                    }
                    if let latency = coordinator.diagnostics?.lastLatencyMilliseconds {
                        LabeledContent("Ping latency", value: "\(latency) ms")
                    }
                    LabeledContent("Reconnect attempts", value: "\(coordinator.diagnostics?.reconnectAttempt ?? 0)")
                } else {
                    ContentUnavailableView("Connection unavailable", systemImage: "network.slash")
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Forget local session?", isPresented: $confirmForget) {
            Button("Forget Local Session", role: .destructive) {
                Task {
                    await viewModel.sessionCoordinator?.forgetLocalSession()
                    viewModel.syncFromSessionCoordinator()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes the Keychain credential for the selected environment. It does not revoke the server session.")
        }
        .confirmationDialog("Revoke current session?", isPresented: $confirmRevoke) {
            Button("Revoke Current Session", role: .destructive) {
                Task {
                    await viewModel.sessionCoordinator?.revokeCurrentSessionOnServer()
                    viewModel.syncFromSessionCoordinator()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This may disconnect this client and removes the local credential after Stoat accepts the revoke request.")
        }
    }

    private var validationText: String {
        switch viewModel.effectiveSessionState {
        case .validatedReady, .readyToConnect, .connected:
            return "Validated"
        case .savedCredentialUnvalidated:
            return "Saved credential not validated"
        case .validatingCredential:
            return "Validating"
        case .invalidSession:
            return "Invalid or expired"
        default:
            return "Not validated"
        }
    }

    private var isDisconnectable: Bool {
        switch viewModel.effectiveConnectionState {
        case .connecting, .connected, .authenticating, .authenticated, .ready, .reconnecting:
            return true
        case .idle, .disconnected, .failed:
            return false
        }
    }

    private var isConnecting: Bool {
        switch viewModel.effectiveConnectionState {
        case .connecting, .connected, .authenticating, .authenticated, .reconnecting:
            return true
        case .idle, .ready, .disconnected, .failed:
            return false
        }
    }
}

private struct SessionsSettingsTab: View {
    @Bindable var accountViewModel: AccountSessionViewModel
    @Binding var pendingRevokeSession: AccountSession?
    @Binding var confirmRevokeAllOthers: Bool
    @State private var renameTextBySessionID: [SessionID: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: StoatSpacing.medium) {
            HStack {
                Text("Sessions")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    Task { await accountViewModel.refreshSessions() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                Button("Log Out Other Sessions", role: .destructive) {
                    confirmRevokeAllOthers = true
                }
                .disabled(accountViewModel.sessionsState.sessions.filter { !$0.isCurrent }.isEmpty)
            }

            Group {
                switch accountViewModel.sessionsState {
                case .idle:
                    ContentUnavailableView("Sessions not loaded", systemImage: "macwindow", description: Text("Refresh sessions after validating a saved credential."))
                case .loading:
                    ProgressView("Loading sessions")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .empty:
                    ContentUnavailableView("No sessions returned", systemImage: "macwindow.badge.plus", description: Text("Stoat did not return any active sessions for this account."))
                case let .failed(message):
                    ContentUnavailableView("Could not load sessions", systemImage: "exclamationmark.triangle", description: Text(message))
                case let .loaded(sessions):
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: StoatSpacing.small) {
                            ForEach(sessions) { session in
                                sessionRow(session)
                            }
                        }
                    }
                }
            }

            if let error = accountViewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding()
    }

    private func sessionRow(_ session: AccountSession) -> some View {
        VStack(alignment: .leading, spacing: StoatSpacing.small) {
            HStack {
                Image(systemName: "macwindow")
                VStack(alignment: .leading) {
                    HStack {
                        Text(session.friendlyName)
                            .font(.headline)
                        if session.isCurrent {
                            Text("Current")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, StoatSpacing.small)
                                .padding(.vertical, StoatSpacing.xxSmall)
                                .background(Color.accentColor.opacity(0.16), in: Capsule())
                        }
                    }
                    Text("Session \(Phase6UIHelpers.shortenedSessionID(session.id))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let createdAt = session.createdAt {
                        Text("Created \(createdAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Log Out", role: .destructive) {
                    pendingRevokeSession = session
                }
            }
            HStack {
                TextField("Friendly name", text: Binding(
                    get: { renameTextBySessionID[session.id] ?? session.friendlyName },
                    set: { renameTextBySessionID[session.id] = $0 }
                ))
                Button("Rename") {
                    let name = renameTextBySessionID[session.id] ?? session.friendlyName
                    Task { await accountViewModel.renameSession(id: session.id, friendlyName: name) }
                }
            }
        }
        .padding(StoatSpacing.medium)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: StoatRadius.control, style: .continuous))
    }
}

private struct ConnectionSettingsTab: View {
    @Bindable var viewModel: MainShellViewModel
    @Bindable var connectionViewModel: ConnectionSettingsViewModel
    let credentialPresenceByProfileID: [String: Bool]
    @Binding var pendingDeleteProfile: EnvironmentProfile?
    @Binding var deleteProfileForgetsCredential: Bool
    let refreshCredentials: () -> Void

    @State private var name = "Local Stoat"
    @State private var apiURL = "http://localhost:14702"
    @State private var eventsURL = "ws://localhost:14703"
    @State private var mediaURL = ""

    var body: some View {
        Form {
            Section("Environments") {
                Picker("Selected environment", selection: Binding(
                    get: { connectionViewModel.selectedEnvironmentID ?? StoatAPIEnvironment.production.stableID },
                    set: { id in Task { await connectionViewModel.selectEnvironment(id: id); viewModel.syncFromSessionCoordinator(); refreshCredentials() } }
                )) {
                    ForEach(connectionViewModel.environmentProfiles) { profile in
                        Text(Phase6UIHelpers.environmentDisplayName(profile)).tag(profile.id)
                    }
                }

                ForEach(connectionViewModel.environmentProfiles) { profile in
                    VStack(alignment: .leading, spacing: StoatSpacing.xSmall) {
                        HStack {
                            Text(Phase6UIHelpers.environmentDisplayName(profile))
                                .font(.headline)
                            Spacer()
                            if profile.id == connectionViewModel.selectedEnvironmentID {
                                Text("Selected").foregroundStyle(.secondary)
                            }
                        }
                        Text(profile.environment.apiBaseURL.absoluteString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(Phase6UIHelpers.credentialPresenceLabel(hasCredential: credentialPresenceByProfileID[profile.id] == true))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !profile.isProduction {
                            HStack {
                                Button("Load for Editing") {
                                    name = profile.name
                                    apiURL = profile.environment.apiBaseURL.absoluteString
                                    eventsURL = profile.environment.eventsURL.absoluteString
                                    mediaURL = profile.environment.mediaBaseURL?.absoluteString ?? ""
                                }
                                Button("Delete", role: .destructive) {
                                    deleteProfileForgetsCredential = false
                                    pendingDeleteProfile = profile
                                }
                                Button("Delete and Forget Credential", role: .destructive) {
                                    deleteProfileForgetsCredential = true
                                    pendingDeleteProfile = profile
                                }
                                .disabled(credentialPresenceByProfileID[profile.id] != true)
                            }
                        }
                    }
                }
                Text("Custom environment preferences are stored locally; session tokens remain in Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Custom Environment") {
                TextField("Name", text: $name)
                TextField("API base URL", text: $apiURL)
                TextField("Events WebSocket URL", text: $eventsURL)
                TextField("Media base URL (optional)", text: $mediaURL)
                HStack {
                    Button("Add Custom Environment") {
                        Task {
                            await connectionViewModel.addEnvironment(name: name, apiURL: apiURL, eventsURL: eventsURL, mediaURL: mediaURL)
                            viewModel.syncFromSessionCoordinator()
                            refreshCredentials()
                        }
                    }
                    Button("Update Selected Custom Environment") {
                        if let id = connectionViewModel.selectedEnvironmentID {
                            Task {
                                await connectionViewModel.updateEnvironment(id: id, name: name, apiURL: apiURL, eventsURL: eventsURL, mediaURL: mediaURL)
                                viewModel.syncFromSessionCoordinator()
                                refreshCredentials()
                            }
                        }
                    }
                    .disabled(connectionViewModel.selectedEnvironmentID == StoatAPIEnvironment.production.stableID)
                }
                ForEach(currentWarnings, id: \.self) { warning in
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("Safe UI Preferences") {
                Toggle("Show developer runtime controls", isOn: Binding(
                    get: { connectionViewModel.preferences.showDeveloperRuntimeControls },
                    set: { connectionViewModel.preferences.showDeveloperRuntimeControls = $0 }
                ))
                Toggle("Member panel visible", isOn: Binding(
                    get: { connectionViewModel.preferences.memberPanelVisible },
                    set: { value in
                        connectionViewModel.preferences.memberPanelVisible = value
                        viewModel.selection.isMemberPanelVisible = value
                    }
                ))
                Picker("Message density", selection: Binding(
                    get: { connectionViewModel.preferences.messageDensity },
                    set: { value in
                        connectionViewModel.preferences.messageDensity = value
                        viewModel.messageDensity = value
                    }
                )) {
                    Text("Comfortable").tag(MessageDensityPreference.comfortable)
                    Text("Compact").tag(MessageDensityPreference.compact)
                }
                Toggle("Reduce glass intensity", isOn: Binding(
                    get: { connectionViewModel.preferences.reduceGlassIntensity },
                    set: { value in
                        connectionViewModel.preferences.reduceGlassIntensity = value
                        viewModel.reduceGlassIntensity = value
                    }
                ))
                Button("Save Preferences") {
                    Task {
                        await connectionViewModel.save()
                        viewModel.syncFromSessionCoordinator()
                    }
                }
            }

            if let error = connectionViewModel.errorMessage ?? viewModel.sessionCoordinator?.preferenceErrorMessage {
                Section("Status") {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var currentWarnings: [String] {
        (try? ConnectionSettingsViewModel.makeEnvironment(apiURL: apiURL, eventsURL: eventsURL, mediaURL: mediaURL).securityWarnings()) ?? []
    }
}

private struct DeveloperVerificationTab: View {
    @Bindable var viewModel: MainShellViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StoatSpacing.large) {
                CredentialSetupView(viewModel: viewModel)
                    .frame(minHeight: 220)
                TimelineValidationHarnessView(viewModel: viewModel)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct TimelineValidationHarnessView: View {
    @Bindable var viewModel: MainShellViewModel

    var body: some View {
        let diagnostics = viewModel.timelineDiagnostics()
        VStack(alignment: .leading, spacing: StoatSpacing.medium) {
            Text("Timeline Validation")
                .font(.headline)
            diagnosticsGrid(diagnostics)
            routeCapabilities
            warningList(diagnostics.validationWarnings)
            actionGrid
            tuningControls
            calibrationControls
            findControls
            checklist(diagnostics)
        }
        .padding(StoatSpacing.medium)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: StoatRadius.panel, style: .continuous))
    }

    private func diagnosticsGrid(_ diagnostics: TimelineDiagnostics) -> some View {
        Grid(alignment: .leading, horizontalSpacing: StoatSpacing.large, verticalSpacing: StoatSpacing.xSmall) {
            diagnosticRow("Environment", viewModel.sessionCoordinator.map { Phase6UIHelpers.environmentDisplayName($0.environment, preferences: $0.preferences) } ?? "Mock")
            diagnosticRow("Current User", viewModel.currentUser?.displayName ?? viewModel.currentUser?.username ?? "-")
            diagnosticRow("Connection", "\(viewModel.effectiveRuntimeMode == .liveManual ? "Live Manual" : "Mock") · \(viewModel.effectiveSessionState)")
            diagnosticRow("Ready", viewModel.sessionCoordinator?.verificationState.readyReceived == true ? "yes" : "no")
            diagnosticRow("Channel", TimelineCopyFormatter.shortID(diagnostics.channelID?.rawValue))
            diagnosticRow("Loaded", "\(diagnostics.loadedMessageCount)")
            diagnosticRow("Range", "\(TimelineCopyFormatter.shortID(diagnostics.oldestLoadedMessageID?.rawValue)) to \(TimelineCopyFormatter.shortID(diagnostics.newestLoadedMessageID?.rawValue))")
            diagnosticRow("Visible", "\(TimelineCopyFormatter.shortID(diagnostics.firstVisibleMessageID?.rawValue)) to \(TimelineCopyFormatter.shortID(diagnostics.lastVisibleMessageID?.rawValue))")
            diagnosticRow("At Newest", diagnostics.atNewest ? "yes" : "no")
            diagnosticRow("Unread", TimelineCopyFormatter.shortID(diagnostics.firstUnreadMessageID?.rawValue))
            diagnosticRow("Pagination", "before \(diagnostics.hasMoreBefore ? "yes" : "no"), after \(diagnostics.hasMoreAfter ? "yes" : "no")")
            diagnosticRow("References", "pending \(diagnostics.pendingReferenceFetchCount), failed \(diagnostics.failedReferenceFetchCount)")
            diagnosticRow("Retries", "\(diagnostics.pendingRetryCount)")
            diagnosticRow("Ack", "\(TimelineCopyFormatter.shortID(diagnostics.lastAckTargetMessageID?.rawValue)) · \(diagnostics.lastAckResult ?? "-")")
            diagnosticRow("Action", diagnostics.lastTimelineActionResult ?? "-")
            diagnosticRow("Routes", diagnostics.lastRouteVerificationResult ?? "-")
        }
        .font(.caption)
    }

    private func diagnosticRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }

    @ViewBuilder private func warningList(_ warnings: [TimelineValidationWarning]) -> some View {
        if !warnings.isEmpty {
            VStack(alignment: .leading, spacing: StoatSpacing.xSmall) {
                ForEach(warnings, id: \.self) { warning in
                    let imageName = warning.severity == .error ? "exclamationmark.triangle.fill" : "exclamationmark.triangle"
                    let style: Color = warning.severity == .info ? .secondary : .orange
                    Label(warning.message, systemImage: imageName)
                        .font(.caption)
                        .foregroundStyle(style)
                }
            }
        }
    }

    private var actionGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: StoatSpacing.small)], alignment: .leading, spacing: StoatSpacing.small) {
            Button("Validate Timeline") { _ = viewModel.validateTimelineState() }
            Button("Refresh Channel") { viewModel.refreshCurrentContext() }
            Button("Load Older") { Task { await viewModel.loadOlderSelectedMessages() } }
            Button("Load To Unread") { Task { await viewModel.loadToFirstUnreadMessage() } }
            Button("Jump Newest") { viewModel.jumpToNewestMessage() }
            Button("Jump First Unread") { viewModel.jumpToFirstUnreadMessage() }
            Button("Verify Routes") { viewModel.verifyTimelineRoutes() }
            Button("Reset Diagnostics") { viewModel.resetTimelineDiagnostics() }
            Button("Copy Diagnostics") { viewModel.copyRedactedTimelineDiagnostics() }
        }
        .buttonStyle(GlassButtonStyle())
    }

    private var tuningControls: some View {
        VStack(alignment: .leading, spacing: StoatSpacing.small) {
            Text("Timeline Tuning").font(.subheadline.weight(.semibold))
            HStack {
                Picker("Preset", selection: $viewModel.selectedTimelineTuningPreset) {
                    ForEach(TimelineTuningPreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .labelsHidden()
                Button("Apply Preset") { viewModel.applyTimelineTuningPreset(viewModel.selectedTimelineTuningPreset) }
                Button("Reset Defaults") { viewModel.resetTimelineTuningToDefaults() }
            }
            Stepper("Near newest threshold: \(viewModel.timelineTuning.nearNewestMessageThreshold)", value: binding(\.nearNewestMessageThreshold), in: 0...25)
            Stepper("Visible debounce: \(viewModel.timelineTuning.visibleRangeUpdateDebounceMilliseconds) ms", value: binding(\.visibleRangeUpdateDebounceMilliseconds), in: 0...2000, step: 20)
            Stepper("Load-to-unread attempts: \(viewModel.timelineTuning.loadToUnreadMaxAttempts)", value: binding(\.loadToUnreadMaxAttempts), in: 1...20)
            Stepper("Reference cooldown: \(viewModel.timelineTuning.referenceFetchCooldownSeconds) sec", value: binding(\.referenceFetchCooldownSeconds), in: 0...3600, step: 10)
            Stepper("Ack debounce: \(viewModel.timelineTuning.ackDebounceMilliseconds) ms", value: binding(\.ackDebounceMilliseconds), in: 0...10000, step: 100)
        }
        .font(.caption)
    }

    private var routeCapabilities: some View {
        VStack(alignment: .leading, spacing: StoatSpacing.xSmall) {
            Text("Route Capabilities").font(.subheadline.weight(.semibold))
            routeRow("Single-message fetch", viewModel.routeVerificationResult.singleMessageFetch)
            routeRow("Around-message fetch", viewModel.routeVerificationResult.aroundMessageFetch)
            routeRow("Selected-channel search", viewModel.routeVerificationResult.channelSearch)
            routeRow("Pinned search", viewModel.routeVerificationResult.pinnedSearch)
            Text(viewModel.lastRouteVerificationResult == nil ? "Source: not live-probed" : "Source: source-verified, not live-probed")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func routeRow(_ title: String, _ status: TimelineRouteVerificationStatus) -> some View {
        Label("\(title): \(status.rawValue)", systemImage: status == .supported ? "checkmark.circle.fill" : "questionmark.circle")
            .font(.caption)
            .foregroundStyle(status == .supported ? .green : .secondary)
            .accessibilityLabel(Phase13Accessibility.routeCapabilityLabel(title, status: status))
    }

    private var calibrationControls: some View {
        VStack(alignment: .leading, spacing: StoatSpacing.small) {
            Text("Timeline Calibration").font(.subheadline.weight(.semibold))
            let run = viewModel.activeCalibrationRun
            HStack {
                Button(run?.isRunning == true ? "Stop Calibration" : "Start Calibration") {
                    if run?.isRunning == true {
                        viewModel.stopTimelineCalibration()
                    } else {
                        viewModel.startTimelineCalibration()
                    }
                }
                Button("Add Checkpoint") { viewModel.addTimelineCalibrationCheckpoint() }
                    .disabled(run?.isRunning != true)
                Button("Copy Calibration") { viewModel.copyRedactedTimelineCalibration() }
                    .disabled(run == nil)
                Button("Apply Recommendation") { viewModel.applyTimelineCalibrationRecommendation() }
                    .disabled(run?.recommendedAdjustments == nil)
            }
            TextField("Checkpoint note", text: $viewModel.calibrationCheckpointNote)
                .textFieldStyle(.roundedBorder)
                .disabled(run?.isRunning != true)
            Text(Phase13Accessibility.calibrationLabel(isRunning: run?.isRunning == true, observationCount: run?.observations.count ?? 0))
                .font(.caption)
                .foregroundStyle(.secondary)
            if let recommendation = run?.recommendedAdjustments {
                Label("\(recommendation.title): \(recommendation.detail)", systemImage: "lightbulb")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let observations = run?.observations.suffix(4), !observations.isEmpty {
                ForEach(Array(observations)) { observation in
                    Text("\(observation.kind.displayName) · loaded \(observation.diagnostics.loadedMessageCount) · warnings \(observation.diagnostics.validationWarnings.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityLabel(Phase13Accessibility.calibrationLabel(isRunning: viewModel.activeCalibrationRun?.isRunning == true, observationCount: viewModel.activeCalibrationRun?.observations.count ?? 0))
    }

    private func binding(_ keyPath: WritableKeyPath<TimelineTuningConfiguration, Int>) -> Binding<Int> {
        Binding {
            viewModel.timelineTuning[keyPath: keyPath]
        } set: { value in
            var tuning = viewModel.timelineTuning
            tuning[keyPath: keyPath] = value
            viewModel.updateTimelineTuning(tuning)
        }
    }

    private var findControls: some View {
        VStack(alignment: .leading, spacing: StoatSpacing.small) {
            Text("Find in Loaded Messages").font(.subheadline.weight(.semibold))
            HStack {
                TextField("Find loaded messages", text: $viewModel.loadedMessageFindQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { viewModel.refreshLoadedMessageFind() }
                Button("Find") { viewModel.refreshLoadedMessageFind() }
            }
            ForEach(viewModel.loadedMessageFindResults) { result in
                Button {
                    viewModel.jumpToLoadedFindResult(result)
                } label: {
                    HStack {
                        Text(TimelineCopyFormatter.shortID(result.messageID.rawValue))
                        Text(result.snippet).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
            }
            Text("Selected Channel Search").font(.subheadline.weight(.semibold))
            HStack {
                TextField("Search selected channel", text: $viewModel.remoteSearchQuery)
                    .textFieldStyle(.roundedBorder)
                Toggle("Pinned only", isOn: $viewModel.remoteSearchPinnedOnly)
                Button("Search") { Task { await viewModel.runSelectedChannelSearch() } }
                Button("Open Panel") { viewModel.openChannelSearch(mode: .liveChannel) }
            }
            if let status = viewModel.remoteSearchStatus {
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(viewModel.remoteSearchResults) { result in
                HStack {
                    Text(TimelineCopyFormatter.shortID(result.messageID.rawValue))
                    Text(result.snippet).foregroundStyle(.secondary).lineLimit(1)
                }
                .font(.caption)
            }
        }
    }

    private func checklist(_ diagnostics: TimelineDiagnostics) -> some View {
        VStack(alignment: .leading, spacing: StoatSpacing.xSmall) {
            Text("Live Manual Checklist").font(.subheadline.weight(.semibold))
            checklistRow("Connected Live Manual", viewModel.effectiveRuntimeMode == .liveManual && viewModel.effectiveSessionState == .connected)
            checklistRow("Ready received", viewModel.sessionCoordinator?.verificationState.readyReceived == true)
            checklistRow("Selected channel exists", diagnostics.channelID != nil)
            checklistRow("Initial messages loaded", diagnostics.loadedMessageCount > 0)
            checklistRow("Visible range active", diagnostics.firstVisibleMessageID != nil || diagnostics.lastVisibleMessageID != nil)
            checklistRow("At-newest detected", diagnostics.atNewest)
            checklistRow("Reference resolver status known", diagnostics.lastRouteVerificationResult != nil || diagnostics.pendingReferenceFetchCount + diagnostics.failedReferenceFetchCount >= 0)
            checklistRow("Diagnostics are redacted", true)
        }
    }

    private func checklistRow(_ title: String, _ passed: Bool) -> some View {
        Label(title, systemImage: passed ? "checkmark.circle.fill" : "circle")
            .font(.caption)
            .foregroundStyle(passed ? .green : .secondary)
    }
}
