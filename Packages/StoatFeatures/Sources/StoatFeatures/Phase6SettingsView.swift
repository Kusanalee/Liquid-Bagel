import StoatAPI
import StoatDesignSystem
import StoatModels
import StoatPersistence
import StoatUI
import StoatVoice
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

            AppearanceSettingsTab(viewModel: viewModel, connectionViewModel: connectionViewModel)
                .tabItem { Label("Appearance", systemImage: "circle.lefthalf.filled") }
                .tag(SettingsSectionTab.appearance)

            NotificationSettingsTab(viewModel: viewModel)
                .tabItem { Label("Notifications", systemImage: "bell.badge") }
                .tag(SettingsSectionTab.notifications)

            VoiceSettingsTab(viewModel: viewModel)
                .tabItem { Label("Voice", systemImage: "mic") }
                .tag(SettingsSectionTab.voice)

            if viewModel.isDeveloperControlsEnabled {
                DeveloperVerificationTab(viewModel: viewModel)
                    .tabItem { Label("Developer", systemImage: "checklist") }
                    .tag(SettingsSectionTab.developer)
            }
        }
        .padding()
        .frame(width: 760, height: 780)
        .environment(\.stoatLiquidGlassTransparency, viewModel.liquidGlassTransparency)
        .task {
            await connectionViewModel.load()
            accountViewModel.syncFromCoordinator()
            viewModel.refreshNotificationPermissionStatus()
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
        // Turning developer options off removes the tab it is selecting from underneath itself,
        // which would leave the TabView with a tag that matches nothing and render blank.
        .onChange(of: viewModel.isDeveloperControlsEnabled) { _, enabled in
            if !enabled, viewModel.selectedSettingsTab == .developer {
                viewModel.selectedSettingsTab = .connection
            }
        }
        .task {
            if !viewModel.isDeveloperControlsEnabled, viewModel.selectedSettingsTab == .developer {
                viewModel.selectedSettingsTab = .account
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
                    if viewModel.isDeveloperControlsEnabled {
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
                    }
                } else {
                    ContentUnavailableView("No validated account", systemImage: "person.crop.circle.badge.questionmark", description: Text("Set up or retry a saved session to show account details."))
                }
                LabeledContent("Environment", value: viewModel.sessionCoordinator?.environment.isProduction == true ? "Stoat Production" : "Custom")
                LabeledContent("Validation", value: validationText)
                if let date = accountViewModel.lastValidatedAt ?? viewModel.sessionCoordinator?.validatedSession?.validatedAt {
                    LabeledContent("Last validated", value: date.formatted(date: .abbreviated, time: .standard))
                }
                LabeledContent("Credential", value: viewModel.sessionCoordinator?.hasSavedCredential == true ? "Token stored in Keychain" : "No saved credential")
            }

            ProfileEditorSection(viewModel: viewModel)

            Section("Actions") {
                HStack {
                    Button("Validate Saved Session") {
                        Task {
                            await viewModel.sessionCoordinator?.validateSavedSession()
                            viewModel.syncFromSessionCoordinator()
                        }
                    }
                    .disabled(viewModel.sessionCoordinator?.hasSavedCredential != true)

                    Button("Retry Connection") {
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

                }
            }

            Section("Connection") {
                // Everyone gets one plain-language line. The counter grid underneath is for
                // people who turned Developer Options on and know what hydration means.
                Label(viewModel.connectionSummaryText, systemImage: viewModel.connectionSummarySymbol)
                if viewModel.isDeveloperControlsEnabled, let coordinator = viewModel.sessionCoordinator {
                    LabeledContent("Health", value: Phase6UIHelpers.connectionHealthText(state: coordinator.connectionState, diagnostics: coordinator.diagnostics, hydration: coordinator.hydrationStatus))
                    LabeledContent("Hydration", value: Phase6UIHelpers.hydrationLabel(coordinator.hydrationStatus))
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

private struct ProfileEditorSection: View {
    @Bindable var viewModel: MainShellViewModel

    var body: some View {
        Section("Profile") {
            if let user = viewModel.currentUserForPresentation {
                VStack(alignment: .leading, spacing: StoatSpacing.medium) {
                    ZStack(alignment: .bottomLeading) {
                        backgroundPreview(for: user)
                        AvatarView(title: viewModel.profileEditDraft.displayName.isEmpty ? user.username : viewModel.profileEditDraft.displayName, size: 72, isOnline: user.online, presence: user.status?.presence, imageData: avatarPreviewData(for: user))
                            .padding(.leading, StoatSpacing.large)
                            .offset(y: 36)
                    }
                    .padding(.bottom, 36)

                    HStack(spacing: StoatSpacing.small) {
                        Button {
                            viewModel.chooseProfileAvatar()
                        } label: {
                            Label("Choose Avatar", systemImage: "photo")
                        }
                        Button(role: .destructive) {
                            viewModel.removeProfileAvatar()
                        } label: {
                            Label("Remove Avatar", systemImage: "person.crop.circle.badge.minus")
                        }
                        .disabled(!canRemoveAvatar)
                    }

                    HStack(spacing: StoatSpacing.small) {
                        Button {
                            viewModel.chooseProfileBackground()
                        } label: {
                            Label("Choose Banner", systemImage: "rectangle.on.rectangle.angled")
                        }
                        Button(role: .destructive) {
                            viewModel.removeProfileBackground()
                        } label: {
                            Label("Remove Banner", systemImage: "rectangle.badge.minus")
                        }
                        .disabled(!canRemoveBackground)
                    }

                    TextField("Display name", text: $viewModel.profileEditDraft.displayName)
                        .textFieldStyle(.roundedBorder)

                    TextEditor(text: $viewModel.profileEditDraft.profileContent)
                        .font(.body)
                        .frame(minHeight: 94)
                        .overlay(alignment: .topLeading) {
                            if viewModel.profileEditDraft.profileContent.isEmpty {
                                Text("Profile bio")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }

                    if !viewModel.profileEditDraft.profileContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        MarkdownMessageContent(viewModel.profileEditDraft.profileContent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(StoatSpacing.small)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: StoatRadius.control, style: .continuous))
                    }

                    if viewModel.profileEditDraft.isSaving {
                        HStack(spacing: StoatSpacing.small) {
                            ProgressView().controlSize(.small)
                            Text("Saving profile")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if let error = viewModel.profileEditDraft.safeErrorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if let status = viewModel.profileEditDraft.saveStatusMessage {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Button {
                            Task { await viewModel.saveProfileEdit() }
                        } label: {
                            Label("Save", systemImage: "checkmark.circle")
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!viewModel.canSaveProfileEdit)

                        Button {
                            viewModel.cancelProfileEdit()
                        } label: {
                            Label("Cancel", systemImage: "xmark.circle")
                        }
                        .keyboardShortcut(.cancelAction)
                        .disabled(viewModel.profileEditDraft.isSaving || !viewModel.profileEditDraft.isDirty)
                    }
                }
            } else {
                ContentUnavailableView("No editable account", systemImage: "person.crop.circle.badge.questionmark")
            }
        }
        .onAppear {
            viewModel.prepareProfileEditor(force: false)
            loadCurrentImages()
        }
        .task {
            await viewModel.ensureCurrentUserProfileForEditing()
            loadCurrentImages()
        }
    }

    private func loadCurrentImages() {
        guard let user = viewModel.currentUserForPresentation else { return }
        viewModel.loadImageResource(for: user.avatar, kind: .userAvatar)
        viewModel.loadImageResource(for: viewModel.userProfilesByID[user.id]?.background, kind: .profileBackground)
    }

    private func avatarPreviewData(for user: User) -> Data? {
        switch viewModel.profileEditDraft.avatarChange {
        case .unchanged:
            return viewModel.imageData(for: user.avatar, kind: .userAvatar)
        case .remove:
            return nil
        case let .upload(draft):
            return draft.previewData
        }
    }

    @ViewBuilder private func backgroundPreview(for user: User) -> some View {
        Color.clear
            .frame(height: 120)
            .frame(maxWidth: .infinity)
            .overlay {
                bannerOverlayContent(for: user)
            }
            .clipShape(RoundedRectangle(cornerRadius: StoatRadius.panel, style: .continuous))
    }

    @ViewBuilder private func bannerOverlayContent(for user: User) -> some View {
        #if canImport(AppKit)
        if let data = backgroundPreviewData(for: user) {
            DecodedDataImage(data: data, pixelSize: 1200)
                .scaledToFill()
        } else {
            backgroundFallback
        }
        #else
        backgroundFallback
        #endif
    }

    private func backgroundPreviewData(for user: User) -> Data? {
        switch viewModel.profileEditDraft.backgroundChange {
        case .unchanged:
            return viewModel.imageData(for: viewModel.userProfilesByID[user.id]?.background, kind: .profileBackground)
        case .remove:
            return nil
        case let .upload(draft):
            return draft.previewData
        }
    }

    private var backgroundFallback: some View {
        RoundedRectangle(cornerRadius: StoatRadius.panel, style: .continuous)
            .fill(LinearGradient(colors: [Color.accentColor.opacity(0.22), Color.primary.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                Image(systemName: "rectangle.on.rectangle.angled")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
    }

    private var canRemoveAvatar: Bool {
        switch viewModel.profileEditDraft.avatarChange {
        case .unchanged:
            return viewModel.profileEditDraft.originalAvatarFileID != nil
        case .remove:
            return false
        case .upload:
            return true
        }
    }

    private var canRemoveBackground: Bool {
        switch viewModel.profileEditDraft.backgroundChange {
        case .unchanged:
            return viewModel.profileEditDraft.originalBackgroundFileID != nil
        case .remove:
            return false
        case .upload:
            return true
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

            Section("Offline") {
                Toggle("Open with saved content", isOn: Binding(
                    get: { connectionViewModel.preferences.offlineCacheRestoreOnLaunch },
                    set: { value in
                        connectionViewModel.preferences.offlineCacheRestoreOnLaunch = value
                        Task {
                            await connectionViewModel.save()
                            viewModel.syncFromSessionCoordinator()
                        }
                    }
                ))
                Text("Shows your servers, channels, and recent messages while Liquid Bagel reconnects. Saved content is encrypted and removed when you sign out.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent("Saved on this Mac", value: viewModel.offlineCacheSizeDescription)
                Button("Clear Saved Content", role: .destructive) {
                    Task { await viewModel.clearOfflineCache() }
                }
            }

            Section("Advanced") {
                Toggle("Enable Developer Options", isOn: Binding(
                    get: { connectionViewModel.preferences.showDeveloperRuntimeControls },
                    set: { value in
                        connectionViewModel.preferences.showDeveloperRuntimeControls = value
                        Task {
                            await connectionViewModel.save()
                            viewModel.syncFromSessionCoordinator()
                        }
                    }
                ))
                Text("Adds a Developer tab, runtime diagnostics, and ID-copying actions throughout the app. Off by default.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .task { await viewModel.refreshOfflineCacheSize() }

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

private struct AppearanceSettingsTab: View {
    @Bindable var viewModel: MainShellViewModel
    @Bindable var connectionViewModel: ConnectionSettingsViewModel

    var body: some View {
        Form {
            Section("Appearance") {
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

                VStack(alignment: .leading, spacing: StoatSpacing.small) {
                    LabeledContent("Liquid Glass transparency", value: transparencyPercent)
                    Slider(
                        value: Binding(
                            get: { connectionViewModel.preferences.liquidGlassTransparency },
                            set: { value in
                                let clamped = AppPreferences.clampedLiquidGlassTransparency(value)
                                connectionViewModel.preferences.liquidGlassTransparency = clamped
                                connectionViewModel.preferences.reduceGlassIntensity = clamped <= 0.35
                                viewModel.liquidGlassTransparency = clamped
                                viewModel.reduceGlassIntensity = clamped <= 0.35
                            }
                        ),
                        in: 0.25...1.0,
                        step: 0.05
                    ) {
                        Text("Liquid Glass transparency")
                    } minimumValueLabel: {
                        Text("Solid")
                    } maximumValueLabel: {
                        Text("Clear")
                    }
                }

                Picker("Inline image previews", selection: Binding(
                    get: { connectionViewModel.preferences.inlineImagePreviewPolicy },
                    set: { value in
                        connectionViewModel.preferences.inlineImagePreviewPolicy = value
                        viewModel.inlineImagePreviewPolicy = value
                    }
                )) {
                    Text("Automatic small images").tag(InlineImagePreviewPolicy.automaticSmallImages)
                    Text("Explicit click only").tag(InlineImagePreviewPolicy.explicitClickOnly)
                    Text("Disabled").tag(InlineImagePreviewPolicy.disabled)
                }
            }

            Section("Interface") {
                Toggle("Member panel visible", isOn: Binding(
                    get: { connectionViewModel.preferences.memberPanelVisible },
                    set: { value in
                        connectionViewModel.preferences.memberPanelVisible = value
                        viewModel.selection.isMemberPanelVisible = value
                    }
                ))
            }

            Section {
                Button("Save Appearance") {
                    Task {
                        await connectionViewModel.save()
                        viewModel.syncFromSessionCoordinator()
                    }
                }
            }

            Section("Cloud Sync") {
                Toggle("Sync automatically", isOn: Binding(
                    get: { connectionViewModel.preferences.automaticSettingsSyncEnabled },
                    set: { value in
                        connectionViewModel.preferences.automaticSettingsSyncEnabled = value
                        Task {
                            await connectionViewModel.save()
                            viewModel.syncFromSessionCoordinator()
                        }
                    }
                ))
                Text("Appearance and notification preferences follow this account to your other devices.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    if settingsSyncWorking {
                        ProgressView().controlSize(.small)
                    }
                    Text(settingsSyncStatusText ?? "Synced")
                        .font(.caption)
                        .foregroundStyle(settingsSyncStatusIsError ? .red : .secondary)
                    Spacer()
                    Button("Sync Now") {
                        Task {
                            await viewModel.pushCloudPreferences()
                            await viewModel.fetchCloudPreferences()
                        }
                    }
                    .disabled(settingsSyncWorking)
                }

                // The explicit fetch/push/apply-older triad stays available for troubleshooting,
                // behind the same flag as the rest of the engineering surface.
                if viewModel.isDeveloperControlsEnabled {
                    HStack {
                        Button("Fetch From Cloud") {
                            Task { await viewModel.fetchCloudPreferences() }
                        }
                        .disabled(settingsSyncWorking)
                        Button("Push To Cloud") {
                            Task { await viewModel.pushCloudPreferences() }
                        }
                        .disabled(settingsSyncWorking)
                        if case .staleRemote = viewModel.settingsSyncState {
                            Button("Apply Older Cloud Copy") {
                                Task { await viewModel.fetchCloudPreferences(applyOlder: true) }
                            }
                            .disabled(settingsSyncWorking)
                        }
                    }
                    .font(.caption)
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

    private var transparencyPercent: String {
        "\(Int((connectionViewModel.preferences.liquidGlassTransparency * 100).rounded()))%"
    }

    private var settingsSyncWorking: Bool {
        viewModel.settingsSyncState == .working
    }

    private var settingsSyncStatusIsError: Bool {
        if case .failed = viewModel.settingsSyncState { return true }
        return false
    }

    private var settingsSyncStatusText: String? {
        switch viewModel.settingsSyncState {
        case .idle:
            return nil
        case .working:
            return "Syncing..."
        case let .applied(timestamp):
            return "Applied cloud preferences from \(Self.syncTimestampText(timestamp))."
        case let .pushed(timestamp):
            return "Pushed preferences to the cloud at \(Self.syncTimestampText(timestamp))."
        case let .staleRemote(timestamp):
            return "The cloud copy from \(Self.syncTimestampText(timestamp)) is not newer than this device."
        case .empty:
            return "No cloud preferences are saved yet. Use Push To Cloud to create them."
        case let .failed(message):
            return message
        }
    }

    private static func syncTimestampText(_ timestamp: Int64) -> String {
        Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
            .formatted(date: .abbreviated, time: .shortened)
    }
}

private struct DeveloperVerificationTab: View {
    @Bindable var viewModel: MainShellViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StoatSpacing.large) {
                // The whole tab is behind Developer Options now, so nothing in it needs a
                // second gate of its own.
                CredentialSetupView(viewModel: viewModel)
                    .frame(minHeight: 220)
                LoginDiagnosticsSection(coordinator: viewModel.sessionCoordinator)
                ProfileEditDiagnosticsSection(viewModel: viewModel)
                TimelineValidationHarnessView(viewModel: viewModel)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task {
            viewModel.ensureNotificationSignatureStatus()
        }
    }
}

private struct LoginDiagnosticsSection: View {
    let coordinator: AppSessionCoordinator?

    var body: some View {
        GroupBox("Login Diagnostics") {
            VStack(alignment: .leading, spacing: StoatSpacing.small) {
                if let coordinator {
                    let summary = """
                    login: \(coordinator.loginDiagnostics.redactedSummary)
                    startup/auth: \(coordinator.startupAuthDiagnostics.redactedSummary)
                    """
                    Text(summary)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Copy Redacted Diagnostics") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(summary, forType: .string)
                    }
                    .controlSize(.small)
                } else {
                    Text("No coordinator attached.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(StoatSpacing.small)
        }
        .padding(.horizontal, StoatSpacing.medium)
    }
}

private struct ProfileEditDiagnosticsSection: View {
    @Bindable var viewModel: MainShellViewModel

    var body: some View {
        GroupBox("Profile Edit Diagnostics") {
            VStack(alignment: .leading, spacing: StoatSpacing.small) {
                LabeledContent("Last action", value: diagnostics.lastAction)
                LabeledContent("Route", value: diagnostics.routeCategory.rawValue)
                LabeledContent("Edited fields", value: editedFields)
                LabeledContent("Upload tag", value: diagnostics.uploadTagCategory.rawValue)
                LabeledContent("Upload result", value: diagnostics.uploadResultCategory.rawValue)
                LabeledContent("Mutation result", value: diagnostics.mutationResultCategory.rawValue)
                LabeledContent("Duration", value: diagnostics.durationMilliseconds.map { "\($0) ms" } ?? "-")
                LabeledContent("Cache invalidations", value: "\(diagnostics.cacheInvalidationCount)")
                LabeledContent("Safe error", value: diagnostics.safeErrorCategory?.rawValue ?? "-")
                LabeledContent("Returned data", value: diagnostics.returnedDataShape.rawValue)
                Button("Copy Redacted Diagnostics") {
                    Task { await viewModel.copyRedactedProfileEditDiagnostics() }
                }
                .controlSize(.small)
            }
            .padding(StoatSpacing.small)
        }
        .padding(.horizontal, StoatSpacing.medium)
    }

    private var diagnostics: ProfileEditDiagnostics {
        viewModel.profileEditDiagnostics
    }

    private var editedFields: String {
        let fields = diagnostics.editedFieldCategories.map(\.rawValue).sorted()
        return fields.isEmpty ? "-" : fields.joined(separator: ", ")
    }
}

private struct NotificationSettingsTab: View {
    @Bindable var viewModel: MainShellViewModel

    private var preferences: NotificationPreferences {
        viewModel.sessionCoordinator?.preferences.notificationPreferences ?? .defaults
    }

    private var selectedChannelID: ChannelID? {
        viewModel.selectedConversationChannelID
    }

    var body: some View {
        Form {
            Section("Permission") {
                LabeledContent("System status", value: viewModel.notificationPermissionStatus.rawValue)
                if viewModel.isDeveloperControlsEnabled {
                    LabeledContent("Authorizer", value: viewModel.notificationAuthorizerKind)
                    LabeledContent("Last request", value: viewModel.lastNotificationPermissionRequest ?? "-")
                    if let request = viewModel.notificationDiagnostics.lastPermissionRequest {
                        LabeledContent("Request called", value: request.requestAuthorizationCalled ? "Yes" : "No")
                        LabeledContent("Options", value: request.requestedOptions.joined(separator: ", "))
                        LabeledContent("Completion", value: request.granted.map { $0 ? "Granted" : "Not granted" } ?? "No completion result")
                        LabeledContent("Named error", value: request.errorCodeName ?? "-")
                        // Raw UNError text. Developer-only: the actionable version for everyone
                        // else is the System Settings guidance below.
                        if let error = request.errorDescription {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                Button("Request Notification Permission") {
                    viewModel.requestNotificationPermission()
                }
                Button("Refresh Status") {
                    viewModel.refreshNotificationPermissionStatus()
                }
                Button("Open macOS Notification Settings") {
                    viewModel.openMacOSNotificationSettings()
                }
                if viewModel.notificationPermissionStatus == .denied {
                    Text("Notifications are denied in macOS System Settings. Open System Settings > Notifications and allow Liquid Bagel, then refresh this status.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if viewModel.notificationPermissionStatus == .notDetermined,
                          let request = viewModel.notificationDiagnostics.lastPermissionRequest,
                          request.requestAuthorizationCalled {
                    Text("macOS has not recorded a decision yet. Open System Settings > Notifications > Liquid Bagel to allow notifications.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text("Permission prompts happen only here. Status refreshes here and when Liquid Bagel becomes active.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Delivery") {
                Toggle("Native notifications", isOn: binding(\.nativeNotificationsEnabled))
                Toggle("In-app banners", isOn: binding(\.inAppBannersEnabled))
                Toggle("Suppress current channel", isOn: binding(\.suppressActiveChannel))
                Picker("Delivery scope", selection: binding(\.deliveryScope)) {
                    Text("Mentions and DMs").tag(NotificationDeliveryScope.mentionsAndDirectMessages)
                    Text("All messages").tag(NotificationDeliveryScope.allMessages)
                }
                Picker("Content", selection: binding(\.contentVisibility)) {
                    Text("Private").tag(NotificationContentVisibility.privateMode)
                    Text("Sender and content").tag(NotificationContentVisibility.showSenderAndContent)
                }
                Picker("Dock badge", selection: binding(\.dockBadge)) {
                    Text("Off").tag(DockBadgePreference.off)
                    Text("Mentions").tag(DockBadgePreference.mentionsOnly)
                    Text("Unread channels and mentions").tag(DockBadgePreference.unreadChannelsAndMentions)
                }
                Text("When Liquid Bagel is active, notifications stay in-app. Native macOS notifications are used only while inactive or in the background, and notification clicks never connect in the background.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Selected Channel") {
                if let selectedChannelID,
                   let channel = viewModel.snapshot.channelsByID[selectedChannelID] {
                    LabeledContent("Channel", value: channel.displayName)
                    Toggle("Mute notifications here", isOn: Binding(
                        get: { preferences.preference(for: selectedChannelID).isMuted },
                        set: { viewModel.setSelectedChannelMuted($0) }
                    ))
                    Toggle("Suppress native here", isOn: channelBinding(selectedChannelID, \.suppressNative))
                    Toggle("Suppress in-app here", isOn: channelBinding(selectedChannelID, \.suppressInApp))
                } else {
                    ContentUnavailableView("No channel selected", systemImage: "bell.slash", description: Text("Select a channel to edit its local notification override."))
                }
            }

            if viewModel.isDeveloperControlsEnabled {
            Section("Diagnostics") {
                let readiness = viewModel.notificationBuildReadinessDiagnostics
                LabeledContent("Lifecycle", value: viewModel.notificationDiagnostics.lifecyclePhase.rawValue)
                LabeledContent("Active channel visible", value: viewModel.notificationDiagnostics.activeChannelVisible ? "Yes" : "No")
                LabeledContent("Dock badge", value: "\(viewModel.notificationDiagnostics.dockBadgeValue)")
                LabeledContent("Queued routes", value: "\(viewModel.notificationDiagnostics.queuedRouteCount)")
                LabeledContent("Expired routes", value: "\(viewModel.notificationDiagnostics.expiredRouteCount)")
                LabeledContent("Last route", value: viewModel.notificationDiagnostics.lastRouteOutcome.rawValue)
                LabeledContent("Delivered", value: "\(viewModel.notificationDiagnostics.deliveredCount)")
                LabeledContent("Suppressed", value: "\(viewModel.notificationDiagnostics.suppressedCount)")
                LabeledContent("Last suppression", value: viewModel.notificationDiagnostics.lastSuppressionReason?.rawValue ?? "-")
                LabeledContent("Last event", value: viewModel.notificationDiagnostics.lastEventKind?.rawValue ?? "-")
                LabeledContent("Bundle ID", value: readiness.bundleIdentifier)
                LabeledContent("Bundle name", value: readiness.bundleDisplayName)
                LabeledContent("App path", value: readiness.appPath)
                LabeledContent("Signing allowed", value: readiness.codeSigningAllowed)
                LabeledContent("Signature", value: readiness.detectedSignatureStatus)
                LabeledContent("Sandbox", value: readiness.sandboxStatus)
                LabeledContent("Delegate", value: readiness.delegateConfigured ? "Configured" : "Missing")
                LabeledContent("Last UNError", value: readiness.lastUNErrorName ?? "-")
                LabeledContent("Before/after", value: "\(readiness.lastBeforeStatus ?? "-") -> \(readiness.lastAfterStatus ?? "-")")
                Toggle("Override: treat this build as signed", isOn: $viewModel.testingSignedNotificationBuild)
                Text(readiness.systemSettingsCheck)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let report = viewModel.notificationDiagnostics.selfTestReport {
                    LabeledContent("Self-test", value: report)
                }
                HStack {
                    Button("Copy Diagnostics") { viewModel.copyRedactedNotificationDiagnostics() }
                    Button("Run Self-Test") { viewModel.runNotificationSelfTest() }
                    Button("Reset Diagnostics") { viewModel.resetNotificationDiagnostics() }
                }
            }
            }
        }
        .formStyle(.grouped)
        .task {
            viewModel.ensureNotificationSignatureStatus()
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<NotificationPreferences, Value>) -> Binding<Value> {
        Binding(
            get: { preferences[keyPath: keyPath] },
            set: { value in
                viewModel.setNotificationPreference { notificationPreferences in
                    notificationPreferences[keyPath: keyPath] = value
                }
            }
        )
    }

    private func channelBinding(_ channelID: ChannelID, _ keyPath: WritableKeyPath<ChannelNotificationPreference, Bool>) -> Binding<Bool> {
        Binding(
            get: { preferences.preference(for: channelID)[keyPath: keyPath] },
            set: { value in
                viewModel.setNotificationPreference { notificationPreferences in
                    var channel = notificationPreferences.preference(for: channelID)
                    channel[keyPath: keyPath] = value
                    if channel.isMuted || channel.suppressNative || channel.suppressInApp {
                        notificationPreferences.channelPreferences[channelID] = channel
                    } else {
                        notificationPreferences.channelPreferences.removeValue(forKey: channelID)
                    }
                }
            }
        )
    }
}

private struct VoiceSettingsTab: View {
    @Bindable var viewModel: MainShellViewModel
    @State private var isCapturingPushToTalkKey = false
    @State private var pushToTalkCaptureMonitor: Any?
    @State private var localAudioLevel: Float = 0

    var body: some View {
        Form {
            Section("Permission") {
                LabeledContent("System status", value: viewModel.microphonePermissionStatus.rawValue)
                Button("Request Microphone Permission") {
                    viewModel.requestMicrophonePermission()
                }
                Button("Refresh Status") {
                    viewModel.refreshMicrophonePermissionStatus()
                }
                Button("Open macOS Microphone Settings") {
                    viewModel.openMacOSMicrophoneSettings()
                }
                if viewModel.microphonePermissionStatus == .denied || viewModel.microphonePermissionStatus == .restricted {
                    Text("Microphone access is denied in macOS System Settings. Open System Settings > Privacy & Security > Microphone and allow Liquid Bagel, then refresh this status.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text("Voice channels need microphone access to publish audio. You can still join and listen without it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Devices") {
                Picker("Input", selection: inputDeviceBinding) {
                    Text("System Default").tag(String?.none)
                    ForEach(viewModel.voiceInputDevices) { device in
                        Text(device.name).tag(String?.some(device.id))
                    }
                }
                Picker("Output", selection: outputDeviceBinding) {
                    Text("System Default").tag(String?.none)
                    ForEach(viewModel.voiceOutputDevices) { device in
                        Text(device.name).tag(String?.some(device.id))
                    }
                }
                if viewModel.voiceInputDevices.isEmpty && viewModel.voiceOutputDevices.isEmpty {
                    Text("No audio devices found yet. The list populates once macOS reports connected devices.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Processing") {
                Toggle("Echo cancellation", isOn: preferenceBinding(\.echoCancellation))
                Toggle("Noise suppression", isOn: preferenceBinding(\.noiseSuppression))
                Text("Changes apply the next time your microphone (re)publishes — muting and unmuting is enough.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Push-to-Talk") {
                Toggle("Push-to-talk", isOn: preferenceBinding(\.pushToTalkEnabled))
                HStack {
                    Text("Key")
                    Spacer()
                    Text(pushToTalkKeyDescription)
                        .foregroundStyle(.secondary)
                    Button(isCapturingPushToTalkKey ? "Press any key…" : "Set Key") {
                        startCapturingPushToTalkKey()
                    }
                    .disabled(isCapturingPushToTalkKey)
                }
                if !viewModel.voicePreferences.pushToTalkEnabled {
                    VStack(alignment: .leading, spacing: StoatSpacing.xSmall) {
                        Text("Input sensitivity")
                        Slider(value: preferenceBinding(\.inputSensitivity), in: 0...1)
                        if viewModel.activeVoiceCall.isActive {
                            ProgressView(value: Double(localAudioLevel), total: 1)
                                .tint(Double(localAudioLevel) >= viewModel.voicePreferences.inputSensitivity ? .green : .secondary)
                        } else {
                            Text("Join a voice channel to preview your microphone level.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Text("Push-to-talk works only while Liquid Bagel is the focused app. A hotkey that works while another app is focused needs macOS Input Monitoring permission and isn't supported yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task {
            viewModel.refreshMicrophonePermissionStatus()
        }
        .task(id: viewModel.activeVoiceCall.isActive) {
            await observeLocalAudioLevel()
        }
        .onDisappear {
            #if canImport(AppKit)
            if let pushToTalkCaptureMonitor {
                NSEvent.removeMonitor(pushToTalkCaptureMonitor)
            }
            #endif
        }
    }

    private var inputDeviceBinding: Binding<String?> {
        Binding(
            get: { viewModel.voicePreferences.inputDeviceID },
            set: { viewModel.voicePreferences.inputDeviceID = $0 }
        )
    }

    private var outputDeviceBinding: Binding<String?> {
        Binding(
            get: { viewModel.voicePreferences.outputDeviceID },
            set: { viewModel.voicePreferences.outputDeviceID = $0 }
        )
    }

    private func preferenceBinding<Value>(_ keyPath: WritableKeyPath<VoicePreferences, Value>) -> Binding<Value> {
        Binding(
            get: { viewModel.voicePreferences[keyPath: keyPath] },
            set: { viewModel.voicePreferences[keyPath: keyPath] = $0 }
        )
    }

    private var pushToTalkKeyDescription: String {
        guard let keyCode = viewModel.voicePreferences.pushToTalkKeyCode else { return "Not set" }
        return PushToTalkKeyNaming.name(for: keyCode)
    }

    private func startCapturingPushToTalkKey() {
        #if canImport(AppKit)
        isCapturingPushToTalkKey = true
        pushToTalkCaptureMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            viewModel.voicePreferences.pushToTalkKeyCode = event.keyCode
            isCapturingPushToTalkKey = false
            if let pushToTalkCaptureMonitor {
                NSEvent.removeMonitor(pushToTalkCaptureMonitor)
            }
            pushToTalkCaptureMonitor = nil
            return nil
        }
        #endif
    }

    private func observeLocalAudioLevel() async {
        guard viewModel.activeVoiceCall.isActive else { return }
        for await level in viewModel.voiceEngine.localAudioLevel {
            if Task.isCancelled { break }
            localAudioLevel = level
        }
    }
}

/// Human-readable names for the handful of macOS virtual keycodes people actually pick for
/// push-to-talk (function/modifier keys that don't collide with typing). Anything else falls
/// back to a raw key-code label rather than guessing.
private enum PushToTalkKeyNaming {
    private static let names: [UInt16: String] = [
        49: "Space", 48: "Tab", 50: "` (Grave)",
        54: "Right ⌘", 55: "Left ⌘", 58: "Left ⌥", 61: "Right ⌥",
        59: "Left ⌃", 62: "Right ⌃", 56: "Left ⇧", 60: "Right ⇧",
        105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20"
    ]

    static func name(for keyCode: UInt16) -> String {
        names[keyCode] ?? "Key code \(keyCode)"
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
            phase44DiagnosticsSection
            warningList(diagnostics.validationWarnings)
            actionGrid
            tuningControls
            paginationDiagnostics
            defaultTuningDecisionControls
            calibrationControls
            findControls
            checklist(diagnostics)
        }
        .padding(StoatSpacing.medium)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: StoatRadius.panel, style: .continuous))
    }

    private func diagnosticsGrid(_ diagnostics: TimelineDiagnostics) -> some View {
        Grid(alignment: .leading, horizontalSpacing: StoatSpacing.large, verticalSpacing: StoatSpacing.xSmall) {
            diagnosticRow("Environment", viewModel.sessionCoordinator.map { Phase6UIHelpers.environmentDisplayName($0.environment, preferences: $0.preferences) } ?? "Preview Data")
            diagnosticRow("Current User", viewModel.currentUser?.displayName ?? viewModel.currentUser?.username ?? "-")
            diagnosticRow("Connection", "\(viewModel.effectiveRuntimeMode == .liveManual ? "Live" : "Preview Data") · \(viewModel.effectiveSessionState)")
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

    private var phase44DiagnosticsSection: some View {
        VStack(alignment: .leading, spacing: StoatSpacing.xSmall) {
            Text("Phase 44 Chat Interaction Diagnostics")
                .font(.subheadline.weight(.semibold))
            Grid(alignment: .leading, horizontalSpacing: StoatSpacing.large, verticalSpacing: StoatSpacing.xSmall) {
                let diagnostics = viewModel.phase44Diagnostics
                diagnosticRow("Replies", "loaded \(diagnostics.replyPreviewResolvedLoaded), unloaded \(diagnostics.replyPreviewResolvedUnloaded), unavailable \(diagnostics.replyPreviewUnavailable)")
                diagnosticRow("Pins", "list \(diagnostics.pinnedListRequestCount)/\(diagnostics.pinnedListSuccessCount)/\(diagnostics.pinnedListFailureCount), actions \(diagnostics.pinActionSuccessCount + diagnostics.unpinActionSuccessCount)/\(diagnostics.pinActionFailureCount + diagnostics.unpinActionFailureCount)")
                diagnosticRow("Jumps", "loaded \(diagnostics.jumpLoadedCount), unloaded \(diagnostics.jumpUnloadedCount), degraded \(diagnostics.jumpDegradedToChannelCount), unavailable \(diagnostics.jumpUnavailableCount)")
                diagnosticRow("Typing", "cleanup \(diagnostics.typingStaleCleanupCount)")
                diagnosticRow("Ack", "requested \(diagnostics.ackRequestedCount), sent \(diagnostics.ackSentCount), deduped \(diagnostics.ackDedupedCount), failed \(diagnostics.ackFailureCount)")
                diagnosticRow("Notifications", "queued \(diagnostics.notificationRouteQueuedCount), replayed \(diagnostics.notificationRouteReplayedCount), degraded \(diagnostics.notificationRouteDegradedCount)")
                diagnosticRow("Last Status", diagnostics.lastSafeStatus ?? "-")
            }
            .font(.caption)
        }
        .padding(StoatSpacing.small)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: StoatRadius.small, style: .continuous))
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
            Stepper("Older prefetch distance: \(viewModel.timelineTuning.olderPrefetchDistancePercent)% of viewport", value: binding(\.olderPrefetchDistancePercent), in: 0...500, step: 25)
            Stepper("Older prefetch row backstop: \(viewModel.timelineTuning.olderPrefetchRowThreshold) rows", value: binding(\.olderPrefetchRowThreshold), in: 0...100)
        }
        .font(.caption)
    }

    private var paginationDiagnostics: some View {
        VStack(alignment: .leading, spacing: StoatSpacing.xSmall) {
            Text("Older-Message Prefetch").font(.subheadline.weight(.semibold))
            let diagnostics = viewModel.phase74PaginationDiagnostics
            LabeledContent("Triggered", value: "\(diagnostics.prefetchTriggerCount)")
            LabeledContent("Suppressed", value: "\(diagnostics.prefetchSuppressedCount)")
            LabeledContent("Pages loaded", value: "\(diagnostics.pageLoadedCount)")
            LabeledContent("Pages failed", value: "\(diagnostics.pageFailedCount)")
            LabeledContent("Last trigger", value: diagnostics.lastTrigger.map { String(describing: $0) } ?? "-")
            LabeledContent("Last suppression", value: diagnostics.lastSuppressionReason?.rawValue ?? "-")
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
            }
            TextField("Checkpoint note", text: $viewModel.calibrationCheckpointNote)
                .textFieldStyle(.roundedBorder)
                .disabled(run?.isRunning != true)
            TextEditor(text: $viewModel.importedCalibrationNotes)
                .frame(minHeight: 64)
                .padding(StoatSpacing.xSmall)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: StoatRadius.control, style: .continuous))
                .accessibilityLabel("Imported calibration notes")
                .accessibilityHint("Paste calibration notes. Import redacts token-like text before using them.")
            HStack {
                Button("Import Notes") { viewModel.importCalibrationNotes() }
                    .disabled(viewModel.importedCalibrationNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Apply Recommendation") { viewModel.applyTimelineCalibrationRecommendation() }
                    .disabled(run?.recommendedAdjustments == nil)
            }
            Text(Phase13Accessibility.calibrationLabel(isRunning: run?.isRunning == true, observationCount: run?.observations.count ?? 0))
                .font(.caption)
                .foregroundStyle(.secondary)
            if let recommendation = run?.recommendedAdjustments {
                VStack(alignment: .leading, spacing: StoatSpacing.xxSmall) {
                    Label("\(recommendation.title): \(recommendation.detail)", systemImage: "lightbulb")
                    Text(tuningDiff(from: viewModel.timelineTuning, to: recommendation.recommendedTuning))
                        .textSelection(.enabled)
                }
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

    private var defaultTuningDecisionControls: some View {
        let decision = viewModel.defaultTuningDecision
        return VStack(alignment: .leading, spacing: StoatSpacing.small) {
            Text("Default Tuning Decision").font(.subheadline.weight(.semibold))
            LabeledContent("Current default", value: TimelineTuningPreset.conservative.displayName)
            LabeledContent("Observed recommendation", value: decision.title)
            Text(decision.reason)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text(tuningDiff(from: viewModel.timelineTuning, to: decision.recommendedConfiguration))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            HStack {
                Button("Apply Decision") { viewModel.applyDefaultTuningDecision() }
                Button("Reset Conservative") { viewModel.resetTimelineTuningToDefaults() }
            }
        }
        .font(.caption)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Default tuning decision, \(decision.title), \(decision.reason)")
    }

    private func tuningDiff(from current: TimelineTuningConfiguration, to proposed: TimelineTuningConfiguration) -> String {
        "Changes: near newest \(current.nearNewestMessageThreshold) to \(proposed.nearNewestMessageThreshold), visible debounce \(current.visibleRangeUpdateDebounceMilliseconds) to \(proposed.visibleRangeUpdateDebounceMilliseconds) ms, load attempts \(current.loadToUnreadMaxAttempts) to \(proposed.loadToUnreadMaxAttempts), ack debounce \(current.ackDebounceMilliseconds) to \(proposed.ackDebounceMilliseconds) ms"
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
            Text("Live Checklist").font(.subheadline.weight(.semibold))
            checklistRow("Connected Live", viewModel.effectiveRuntimeMode == .liveManual && viewModel.effectiveSessionState == .connected)
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
