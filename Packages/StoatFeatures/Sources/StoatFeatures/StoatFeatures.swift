import Foundation
import Observation
import StoatAPI
import StoatDesignSystem
import StoatModels
import StoatPersistence
import StoatRealtime
import StoatUI
import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

public enum AppRuntimeMode: Codable, Hashable, Sendable {
    case mock
    case liveManual
}

public enum SettingsSectionTab: String, Codable, Hashable, Sendable, CaseIterable {
    case account
    case sessions
    case connection
    case developer
}

public enum ShellSpace: Codable, Hashable, Sendable {
    case home
    case server(ServerID)
    case directMessages
    case discover
}

public enum ShellRoute: Codable, Hashable, Sendable {
    case home
    case friends
    case discover
    case server(ServerID, ChannelID?)
    case directMessage(ChannelID?)
}

public struct ShellSelection: Codable, Hashable, Sendable {
    public var space: ShellSpace
    public var serverID: ServerID?
    public var channelID: ChannelID?
    public var dmChannelID: ChannelID?
    public var selectedUserID: UserID?
    public var isMemberPanelVisible: Bool

    public init(
        space: ShellSpace = .home,
        serverID: ServerID? = nil,
        channelID: ChannelID? = nil,
        dmChannelID: ChannelID? = nil,
        selectedUserID: UserID? = nil,
        isMemberPanelVisible: Bool = true
    ) {
        self.space = space
        self.serverID = serverID
        self.channelID = channelID
        self.dmChannelID = dmChannelID
        self.selectedUserID = selectedUserID
        self.isMemberPanelVisible = isMemberPanelVisible
    }

    public var route: ShellRoute {
        switch space {
        case .home: .home
        case .discover: .discover
        case .directMessages: .directMessage(dmChannelID)
        case let .server(id): .server(id, channelID)
        }
    }
}

public struct MessageGroup: Hashable, Sendable, Identifiable {
    public var id: String
    public var authorID: UserID
    public var channelID: ChannelID
    public var messages: [Message]
    public var startsAt: Date

    public init(id: String, authorID: UserID, channelID: ChannelID, messages: [Message], startsAt: Date) {
        self.id = id
        self.authorID = authorID
        self.channelID = channelID
        self.messages = messages
        self.startsAt = startsAt
    }
}

public enum MessageGrouping {
    public static let defaultThreshold: TimeInterval = 6 * 60

    public static func group(_ messages: [Message], threshold: TimeInterval = defaultThreshold) -> [MessageGroup] {
        let sorted = messages.sorted { timestamp(for: $0) < timestamp(for: $1) }
        var groups: [MessageGroup] = []

        for message in sorted {
            let messageDate = timestamp(for: message)
            guard var last = groups.last,
                  let previous = last.messages.last
            else {
                groups.append(makeGroup(message, startsAt: messageDate))
                continue
            }

            let previousDate = timestamp(for: previous)
            let canGroup = previous.authorID == message.authorID
                && previous.channelID == message.channelID
                && previous.system == nil
                && message.system == nil
                && previous.replies?.isEmpty != false
                && message.replies?.isEmpty != false
                && messageDate.timeIntervalSince(previousDate) <= threshold

            if canGroup {
                last.messages.append(message)
                groups[groups.count - 1] = last
            } else {
                groups.append(makeGroup(message, startsAt: messageDate))
            }
        }

        return groups
    }

    private static func makeGroup(_ message: Message, startsAt: Date) -> MessageGroup {
        MessageGroup(id: "\(message.channelID.rawValue)-\(message.id.rawValue)", authorID: message.authorID, channelID: message.channelID, messages: [message], startsAt: startsAt)
    }

    private static func timestamp(for message: Message) -> Date {
        message.createdAt ?? Date(timeIntervalSince1970: 0)
    }
}

public struct TimelineMessageGroup: Hashable, Sendable, Identifiable {
    public var id: String
    public var authorID: UserID
    public var channelID: ChannelID
    public var messages: [TimelineMessage]
    public var startsAt: Date

    public init(id: String, authorID: UserID, channelID: ChannelID, messages: [TimelineMessage], startsAt: Date) {
        self.id = id
        self.authorID = authorID
        self.channelID = channelID
        self.messages = messages
        self.startsAt = startsAt
    }
}

public enum TimelineMessageGrouping {
    public static func group(_ messages: [TimelineMessage], threshold: TimeInterval = MessageGrouping.defaultThreshold) -> [TimelineMessageGroup] {
        let sorted = messages.sorted { timestamp(for: $0.message) < timestamp(for: $1.message) }
        var groups: [TimelineMessageGroup] = []

        for timelineMessage in sorted {
            let message = timelineMessage.message
            let messageDate = timestamp(for: message)
            guard var last = groups.last,
                  let previous = last.messages.last
            else {
                groups.append(makeGroup(timelineMessage, startsAt: messageDate))
                continue
            }

            let previousMessage = previous.message
            let previousDate = timestamp(for: previousMessage)
            let canGroup = previousMessage.authorID == message.authorID
                && previousMessage.channelID == message.channelID
                && previousMessage.system == nil
                && message.system == nil
                && previousMessage.replies?.isEmpty != false
                && message.replies?.isEmpty != false
                && previous.status == .confirmed
                && timelineMessage.status == .confirmed
                && messageDate.timeIntervalSince(previousDate) <= threshold

            if canGroup {
                last.messages.append(timelineMessage)
                groups[groups.count - 1] = last
            } else {
                groups.append(makeGroup(timelineMessage, startsAt: messageDate))
            }
        }

        return groups
    }

    private static func makeGroup(_ timelineMessage: TimelineMessage, startsAt: Date) -> TimelineMessageGroup {
        let message = timelineMessage.message
        return TimelineMessageGroup(id: "\(message.channelID.rawValue)-\(message.id.rawValue)", authorID: message.authorID, channelID: message.channelID, messages: [timelineMessage], startsAt: startsAt)
    }

    private static func timestamp(for message: Message) -> Date {
        message.createdAt ?? Date.distantFuture
    }
}

public struct EditingMessageDraft: Hashable, Sendable, Identifiable {
    public var id: MessageID { message.id }
    public var message: Message
    public var content: String

    public init(message: Message, content: String) {
        self.message = message
        self.content = content
    }
}

@MainActor
@Observable
public final class MainShellViewModel {
    public var selection: ShellSelection
    public var snapshot: RealtimeSnapshot
    public var connectionState: RealtimeConnectionState
    public var diagnostics: RealtimeDiagnostics?
    public var runtimeMode: AppRuntimeMode
    public var sessionState: AppSessionState
    public var currentUser: User?
    public var sessionCoordinator: AppSessionCoordinator?
    public var messageController: ChannelMessageController
    public var isQuickSwitcherPresented = false
    public var placeholderStatus: String?
    public var shouldFocusComposer = false
    public var composerDrafts: [ChannelID: String] = [:]
    public var composerError: String?
    public var editingDraft: EditingMessageDraft?
    public var pendingDeletion: TimelineMessage?
    public var messageActionStatus: String?
    public var isCredentialSetupPresented = false
    public var isTestSendConfirmationPresented = false
    public var selectedSettingsTab: SettingsSectionTab = .account
    public var messageDensity: MessageDensityPreference = .comfortable
    public var reduceGlassIntensity = false

    @ObservationIgnored public var messageActionHandler: any MessageActionHandling
    @ObservationIgnored private var snapshotObservationTask: Task<Void, Never>?
    @ObservationIgnored private var selectedChannelLoadTask: Task<Void, Never>?
    @ObservationIgnored private var typingEndTask: Task<Void, Never>?
    @ObservationIgnored private var activeTypingChannelID: ChannelID?
    @ObservationIgnored private var lastTypingBeginAt: [ChannelID: Date] = [:]
    @ObservationIgnored private var locallyClearedUnreadChannelIDs: Set<ChannelID> = []

    public init(
        selection: ShellSelection = ShellSelection(),
        snapshot: RealtimeSnapshot = MockShellData.snapshot,
        connectionState: RealtimeConnectionState = .idle,
        diagnostics: RealtimeDiagnostics? = nil,
        runtimeMode: AppRuntimeMode = .mock,
        sessionState: AppSessionState = .mock,
        currentUser: User? = nil,
        sessionCoordinator: AppSessionCoordinator? = nil,
        snapshotSource: (any ShellSnapshotSource)? = nil,
        messageController: ChannelMessageController? = nil,
        messageActionHandler: (any MessageActionHandling)? = nil
    ) {
        self.selection = selection
        self.snapshot = snapshot
        self.connectionState = connectionState
        self.diagnostics = diagnostics
        self.runtimeMode = runtimeMode
        self.sessionState = sessionState
        self.currentUser = currentUser ?? snapshot.usersByID[MockShellData.currentUserID]
        self.sessionCoordinator = sessionCoordinator
        self.messageController = messageController ?? ChannelMessageController(runtimeMode: runtimeMode, currentUserID: currentUser?.id ?? MockShellData.currentUserID)
        self.messageActionHandler = messageActionHandler ?? MockMessageActionHandler(currentUserID: currentUser?.id ?? MockShellData.currentUserID)
        validateSelection()
        self.messageController.hydrate(from: snapshot)
        if let snapshotSource {
            observe(snapshotSource: snapshotSource)
        }
    }

    deinit {
        snapshotObservationTask?.cancel()
        selectedChannelLoadTask?.cancel()
        typingEndTask?.cancel()
    }

    public var servers: [Server] {
        snapshot.serversByID.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public var selectedServer: Server? {
        guard let id = selection.serverID else { return nil }
        return snapshot.serversByID[id]
    }

    public var selectedChannel: Channel? {
        guard let id = selection.channelID else { return nil }
        return snapshot.channelsByID[id]
    }

    public var selectedMessages: [Message] {
        guard let channelID = selection.channelID ?? selection.dmChannelID else { return [] }
        let timelineMessages = selectedTimelineMessages
        if !timelineMessages.isEmpty {
            return timelineMessages.map(\.message)
        }
        return snapshot.messagesByChannelID[channelID] ?? []
    }

    public var selectedMessageGroups: [MessageGroup] {
        MessageGrouping.group(selectedMessages)
    }

    public var selectedTimelineMessages: [TimelineMessage] {
        guard let channelID = selection.channelID ?? selection.dmChannelID else { return [] }
        let stateMessages = messageController.state(for: channelID).timelineMessages
        if !stateMessages.isEmpty {
            return stateMessages
        }
        return (snapshot.messagesByChannelID[channelID] ?? []).map { TimelineMessage(message: $0) }
    }

    public var selectedTimelineMessageGroups: [TimelineMessageGroup] {
        TimelineMessageGrouping.group(selectedTimelineMessages)
    }

    public var selectedChannelMessageState: ChannelMessageState {
        messageController.state(for: selection.channelID ?? selection.dmChannelID)
    }

    public var effectiveRuntimeMode: AppRuntimeMode {
        sessionCoordinator?.mode ?? runtimeMode
    }

    public var effectiveSessionState: AppSessionState {
        sessionCoordinator?.sessionState ?? sessionState
    }

    public var effectiveConnectionState: RealtimeConnectionState {
        sessionCoordinator?.connectionState ?? connectionState
    }

    public var effectiveDiagnostics: RealtimeDiagnostics? {
        sessionCoordinator?.diagnostics ?? diagnostics
    }

    public var currentUserID: UserID? {
        if effectiveRuntimeMode == .mock {
            return (sessionCoordinator?.currentUser ?? currentUser)?.id ?? MockShellData.currentUserID
        }
        return sessionCoordinator?.currentUser?.id ?? currentUser?.id
    }

    public var title: String {
        switch selection.space {
        case .home:
            return "Home"
        case .discover:
            return "Discover"
        case .directMessages:
            return "Direct Messages"
        case .server:
            if let channel = selectedChannel { return "# \(channel.displayName)" }
            return selectedServer?.name ?? "Server"
        }
    }

    public func channels(for serverID: ServerID?) -> [Channel] {
        guard let serverID else { return [] }
        let server = snapshot.serversByID[serverID]
        let channels = snapshot.channelsByID.values.filter { $0.serverID == serverID }
        if let orderedIDs = server?.channelIDs, !orderedIDs.isEmpty {
            return orderedIDs.compactMap { id in channels.first { $0.id == id } }
        }
        return channels.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    public func members(for serverID: ServerID?) -> [User] {
        guard let serverID else { return [] }
        let ids = snapshot.membersByServerAndUserID.keys
            .filter { $0.serverID == serverID }
            .map(\.userID)
        let users = ids.compactMap { snapshot.usersByID[$0] }
        if users.isEmpty {
            return snapshot.usersByID.values.sorted { $0.username < $1.username }
        }
        return users.sorted { ($0.displayName ?? $0.username) < ($1.displayName ?? $1.username) }
    }

    public func selectHome() {
        endTypingForActiveChannel()
        selection.space = .home
        selection.serverID = nil
        selection.channelID = nil
        selection.dmChannelID = nil
        placeholderStatus = nil
    }

    public func selectDiscover() {
        endTypingForActiveChannel()
        selection.space = .discover
        selection.serverID = nil
        selection.channelID = nil
        selection.dmChannelID = nil
        placeholderStatus = nil
    }

    public func selectDirectMessages() {
        endTypingForActiveChannel()
        selection.space = .directMessages
        selection.serverID = nil
        selection.channelID = nil
        selection.dmChannelID = snapshot.channelsByID.values.first { $0.kind == .directMessage }?.id
        placeholderStatus = nil
        acknowledgeSelectedChannel()
        scheduleSelectedChannelLoad()
    }

    public func selectServer(_ id: ServerID) {
        endTypingForActiveChannel()
        guard snapshot.serversByID[id] != nil else {
            validateSelection()
            return
        }
        selection.space = .server(id)
        selection.serverID = id
        selection.channelID = firstVisibleTextChannel(in: id)?.id
        selection.dmChannelID = nil
        placeholderStatus = nil
        acknowledgeSelectedChannel()
        scheduleSelectedChannelLoad()
    }

    public func selectServer(atOneBasedIndex index: Int) {
        let zeroBased = index - 1
        guard servers.indices.contains(zeroBased) else { return }
        selectServer(servers[zeroBased].id)
    }

    public func selectChannel(_ id: ChannelID) {
        endTypingForActiveChannel()
        guard let channel = snapshot.channelsByID[id] else {
            validateSelection()
            return
        }
        if let serverID = channel.serverID {
            selection.space = .server(serverID)
            selection.serverID = serverID
            selection.channelID = id
            selection.dmChannelID = nil
        } else {
            selection.space = .directMessages
            selection.serverID = nil
            selection.channelID = nil
            selection.dmChannelID = id
        }
        placeholderStatus = nil
        acknowledgeSelectedChannel()
        scheduleSelectedChannelLoad()
    }

    public func toggleMemberPanel() {
        selection.isMemberPanelVisible.toggle()
        Task { [weak self] in
            guard let self else { return }
            await self.sessionCoordinator?.updatePreferences { preferences in
                preferences.memberPanelVisible = self.selection.isMemberPanelVisible
            }
        }
    }

    public func showQuickSwitcher() {
        isQuickSwitcherPresented = true
        placeholderStatus = "Quick switcher is a Phase 3 placeholder."
    }

    public func focusComposer() {
        shouldFocusComposer.toggle()
        placeholderStatus = selectedChannel == nil ? "Select a channel before focusing the composer." : nil
    }

    public func refreshPlaceholder() {
        if let channelID = selection.channelID ?? selection.dmChannelID {
            Task { [weak self] in
                guard let self else { return }
                await self.messageController.refreshMessages(channelID: channelID, snapshotMessages: self.snapshot.messagesByChannelID[channelID] ?? [])
                self.sessionCoordinator?.markSelectedChannelMessageFetchSucceeded(channelID: channelID, isAvailable: self.snapshot.channelsByID[channelID] != nil)
            }
        } else {
            placeholderStatus = "Select a channel before refreshing messages."
        }
    }

    public func settingsPlaceholder() {
        selectedSettingsTab = .account
        isCredentialSetupPresented = true
    }

    public func showCredentialSetup() {
        selectedSettingsTab = .developer
        isCredentialSetupPresented = true
    }

    public func showConnectionSettings() {
        selectedSettingsTab = .connection
        isCredentialSetupPresented = true
    }

    public func showAccountSessions() {
        selectedSettingsTab = .account
        isCredentialSetupPresented = true
    }

    public func confirmLiveVerificationSend() async {
        guard let channelID = selection.channelID ?? selection.dmChannelID else {
            messageActionStatus = "Select a channel before sending a verification message."
            return
        }
        await sendDraft(for: channelID)
        sessionCoordinator?.markLastMessageActionResult(messageActionStatus ?? "Send action attempted.")
    }

    public func validateSelection() {
        switch selection.space {
        case .home, .discover, .directMessages:
            if selection.space == .directMessages,
               let dmChannelID = selection.dmChannelID,
               snapshot.channelsByID[dmChannelID] == nil {
                selection.dmChannelID = snapshot.channelsByID.values.first { $0.kind == .directMessage }?.id
            }
        case let .server(serverID):
            if snapshot.serversByID[serverID] == nil {
                selectHome()
                return
            }
            selection.serverID = serverID
            if let channelID = selection.channelID,
               snapshot.channelsByID[channelID]?.serverID == serverID {
                return
            }
            selection.channelID = firstVisibleTextChannel(in: serverID)?.id
        }
    }

    public func attachSessionCoordinator(_ coordinator: AppSessionCoordinator) {
        sessionCoordinator = coordinator
        syncFromSessionCoordinator()
    }

    public func startMockSession() async {
        guard let sessionCoordinator else { return }
        await sessionCoordinator.startMockSession()
        syncFromSessionCoordinator()
    }

    public func connectLiveManually() async {
        guard let sessionCoordinator else { return }
        await sessionCoordinator.connectLiveManually()
        syncFromSessionCoordinator()
    }

    public func disconnectLive() async {
        guard let sessionCoordinator else { return }
        await sessionCoordinator.disconnectLive()
        syncFromSessionCoordinator()
    }

    public func resetToMock() async {
        guard let sessionCoordinator else { return }
        await sessionCoordinator.resetToMock()
        syncFromSessionCoordinator()
    }

    public func syncFromSessionCoordinator() {
        guard let sessionCoordinator else { return }
        runtimeMode = sessionCoordinator.mode
        sessionState = sessionCoordinator.sessionState
        connectionState = sessionCoordinator.connectionState
        diagnostics = sessionCoordinator.diagnostics
        currentUser = sessionCoordinator.currentUser
        selection.isMemberPanelVisible = sessionCoordinator.preferences.memberPanelVisible
        messageDensity = sessionCoordinator.preferences.messageDensity
        reduceGlassIntensity = sessionCoordinator.preferences.reduceGlassIntensity
        snapshot = sessionCoordinator.snapshot
        messageActionHandler = sessionCoordinator.messageActionHandler
        let liveAPIClient = sessionCoordinator.mode == .liveManual ? sessionCoordinator.apiClient : nil
        messageController.configure(
            runtimeMode: sessionCoordinator.mode,
            apiClient: liveAPIClient,
            currentUserID: sessionCoordinator.currentUser?.id ?? (sessionCoordinator.mode == .mock ? MockShellData.currentUserID : nil)
        )
        observe(snapshotSource: sessionCoordinator.snapshotSource)
        validateSelection()
        messageController.hydrate(from: snapshot)
        scheduleSelectedChannelLoad()
    }

    public func observe(snapshotSource: any ShellSnapshotSource) {
        snapshotObservationTask?.cancel()
        snapshotObservationTask = Task { [weak self] in
            let current = await snapshotSource.currentSnapshot()
            await MainActor.run {
                self?.applySnapshot(current)
            }
            for await snapshot in snapshotSource.snapshots {
                await MainActor.run {
                    self?.applySnapshot(snapshot)
                }
            }
        }
    }

    public func draft(for channelID: ChannelID?) -> String {
        guard let channelID else { return "" }
        return composerDrafts[channelID, default: ""]
    }

    public func updateDraft(_ draft: String, for channelID: ChannelID?) {
        guard let channelID else { return }
        composerDrafts[channelID] = draft
        scheduleTyping(for: channelID, draft: draft)
    }

    public func composerReadiness(for channelID: ChannelID?) -> (canSend: Bool, reason: String) {
        guard let channelID, let channel = snapshot.channelsByID[channelID] else {
            return (false, "Select a channel to send a message.")
        }
        let draft = draft(for: channelID).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.isEmpty else {
            return (false, "Write a message to send.")
        }
        guard isRuntimeSendCapable else {
            return (false, effectiveRuntimeMode == .mock ? "Mock runtime is unavailable." : "Connect Live Manual before sending.")
        }
        if let permissions = resolvedPermissions(for: channel), !permissions.contains(.sendMessage) {
            return (false, "You do not have permission to send messages here.")
        }
        if messageController.sendingChannelIDs.contains(channelID) {
            return (false, "Sending the previous message.")
        }
        return (true, "Send message")
    }

    public func composerInputReadiness(for channelID: ChannelID?) -> (isEnabled: Bool, reason: String) {
        guard let channelID, let channel = snapshot.channelsByID[channelID] else {
            return (false, "Select a channel to send a message.")
        }
        guard isRuntimeSendCapable else {
            return (false, effectiveRuntimeMode == .mock ? "Mock runtime is unavailable." : "Connect Live Manual before sending.")
        }
        if let permissions = resolvedPermissions(for: channel), !permissions.contains(.sendMessage) {
            return (false, "You do not have permission to send messages here.")
        }
        if messageController.sendingChannelIDs.contains(channelID) {
            return (false, "Sending the previous message.")
        }
        return (true, "Message #\(channel.displayName)")
    }

    public func canUploadFiles(in channel: Channel?) -> Bool {
        guard let channel else { return false }
        guard let permissions = resolvedPermissions(for: channel) else { return true }
        return permissions.contains(.uploadFiles)
    }

    public func canReact(to message: Message) -> Bool {
        guard let channel = snapshot.channelsByID[message.channelID] else { return false }
        guard isRuntimeSendCapable else { return false }
        guard let permissions = resolvedPermissions(for: channel) else { return true }
        return permissions.contains(.react)
    }

    public func canEdit(_ message: Message) -> Bool {
        currentUserID == message.authorID && isRuntimeSendCapable
    }

    public func canDelete(_ message: Message) -> Bool {
        guard isRuntimeSendCapable else { return false }
        if currentUserID == message.authorID { return true }
        guard let channel = snapshot.channelsByID[message.channelID],
              let permissions = resolvedPermissions(for: channel)
        else { return false }
        return permissions.contains(.manageMessages)
    }

    public func sendDraft(for channelID: ChannelID?) async {
        guard let channelID else { return }
        let readiness = composerReadiness(for: channelID)
        guard readiness.canSend else {
            composerError = readiness.reason
            return
        }
        let content = draft(for: channelID).trimmingCharacters(in: .whitespacesAndNewlines)
        composerDrafts[channelID] = ""
        composerError = nil
        _ = await messageController.sendMessage(channelID: channelID, content: content, handler: messageActionHandler)
    }

    public func retry(_ timelineMessage: TimelineMessage) async {
        _ = await messageController.retrySend(timelineMessage, handler: messageActionHandler)
    }

    public func loadOlderSelectedMessages() async {
        guard let channelID = selection.channelID ?? selection.dmChannelID else { return }
        await messageController.loadOlderMessages(channelID: channelID)
    }

    public func beginEditing(_ timelineMessage: TimelineMessage) {
        guard canEdit(timelineMessage.message) else { return }
        editingDraft = EditingMessageDraft(message: timelineMessage.message, content: timelineMessage.message.content ?? "")
    }

    public func saveEditingDraft() async {
        guard let editingDraft else { return }
        do {
            let edited = try await messageActionHandler.editMessage(
                channelID: editingDraft.message.channelID,
                messageID: editingDraft.message.id,
                content: editingDraft.content
            )
            messageController.applyEditedMessage(edited)
            self.editingDraft = nil
            messageActionStatus = nil
        } catch {
            messageActionStatus = "Edit failed: \(error.userFacingMessage)"
        }
    }

    public func requestDelete(_ timelineMessage: TimelineMessage) {
        guard canDelete(timelineMessage.message) else { return }
        pendingDeletion = timelineMessage
    }

    public func confirmPendingDelete() async {
        guard let pendingDeletion else { return }
        do {
            try await messageActionHandler.deleteMessage(channelID: pendingDeletion.message.channelID, messageID: pendingDeletion.message.id)
            messageController.removeMessage(channelID: pendingDeletion.message.channelID, messageID: pendingDeletion.message.id)
            self.pendingDeletion = nil
            messageActionStatus = nil
        } catch {
            messageActionStatus = "Delete failed: \(error.userFacingMessage)"
        }
    }

    public func toggleReaction(_ emoji: String, on timelineMessage: TimelineMessage) async {
        guard canReact(to: timelineMessage.message), let currentUserID else { return }
        let hasReacted = timelineMessage.message.reactions[emoji]?.contains(currentUserID) == true
        do {
            if hasReacted {
                try await messageActionHandler.removeReaction(channelID: timelineMessage.message.channelID, messageID: timelineMessage.message.id, emoji: emoji)
            } else {
                try await messageActionHandler.addReaction(channelID: timelineMessage.message.channelID, messageID: timelineMessage.message.id, emoji: emoji)
            }
            messageController.applyReaction(channelID: timelineMessage.message.channelID, messageID: timelineMessage.message.id, emoji: emoji, userID: currentUserID, isAdding: !hasReacted)
            messageActionStatus = nil
        } catch {
            messageActionStatus = "Reaction failed: \(error.userFacingMessage)"
        }
    }

    public func copyMessage(_ message: Message) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.content ?? message.id.rawValue, forType: .string)
        #endif
    }

    public func typingUsers(for channelID: ChannelID?) -> [User] {
        guard let channelID else { return [] }
        let currentUserID = currentUserID
        return (snapshot.typingUsersByChannelID[channelID] ?? [])
            .filter { $0 != currentUserID }
            .compactMap { snapshot.usersByID[$0] }
            .sorted { ($0.displayName ?? $0.username) < ($1.displayName ?? $1.username) }
    }

    public func unread(for channelID: ChannelID) -> ChannelUnread? {
        guard let unread = snapshot.unreadsByChannelID[channelID] else { return nil }
        if locallyClearedUnreadChannelIDs.contains(channelID) || selection.channelID == channelID || selection.dmChannelID == channelID {
            if unread.mentions.isEmpty {
                return nil
            }
            return ChannelUnread(id: unread.id, lastMessageID: nil, mentions: unread.mentions)
        }
        return unread
    }

    private func firstVisibleTextChannel(in serverID: ServerID) -> Channel? {
        channels(for: serverID).first { $0.kind == .textChannel || $0.kind == .group || $0.kind == .savedMessages }
    }

    private var isRuntimeSendCapable: Bool {
        switch effectiveRuntimeMode {
        case .mock:
            return true
        case .liveManual:
            return effectiveSessionState == .connected
        }
    }

    private func resolvedPermissions(for channel: Channel) -> Permissions? {
        if let permissions = channel.permissions {
            return permissions
        }
        if let serverID = channel.serverID,
           let server = snapshot.serversByID[serverID] {
            return server.defaultPermissions
        }
        return nil
    }

    private func applySnapshot(_ snapshot: RealtimeSnapshot) {
        self.snapshot = snapshot
        messageController.hydrate(from: snapshot)
        validateSelection()
        acknowledgeSelectedChannel()
        scheduleSelectedChannelLoad()
    }

    private func scheduleSelectedChannelLoad() {
        selectedChannelLoadTask?.cancel()
        guard let channelID = selection.channelID ?? selection.dmChannelID else { return }
        let snapshotMessages = snapshot.messagesByChannelID[channelID] ?? []
        selectedChannelLoadTask = Task { [weak self] in
            guard let self else { return }
            await self.messageController.loadInitialIfNeeded(channelID: channelID, snapshotMessages: snapshotMessages)
        }
    }

    private func acknowledgeSelectedChannel() {
        guard let channelID = selection.channelID ?? selection.dmChannelID else { return }
        locallyClearedUnreadChannelIDs.insert(channelID)
    }

    private func scheduleTyping(for channelID: ChannelID, draft: String) {
        guard isRuntimeSendCapable else { return }
        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            endTypingForActiveChannel()
            return
        }

        let now = Date()
        if activeTypingChannelID != channelID || now.timeIntervalSince(lastTypingBeginAt[channelID] ?? .distantPast) > 8 {
            activeTypingChannelID = channelID
            lastTypingBeginAt[channelID] = now
            Task { [handler = messageActionHandler] in
                try? await handler.beginTyping(channelID: channelID)
            }
        }

        typingEndTask?.cancel()
        typingEndTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            await MainActor.run {
                guard let self, self.activeTypingChannelID == channelID else { return }
                self.endTypingForActiveChannel()
            }
        }
    }

    private func endTypingForActiveChannel() {
        typingEndTask?.cancel()
        guard let channelID = activeTypingChannelID else { return }
        activeTypingChannelID = nil
        Task { [handler = messageActionHandler] in
            try? await handler.endTyping(channelID: channelID)
        }
    }
}

public enum ShellCommandNotification {
    public static let quickSwitcher = Notification.Name("LiquidBagelShowQuickSwitcher")
    public static let focusComposer = Notification.Name("LiquidBagelFocusComposer")
    public static let refresh = Notification.Name("LiquidBagelRefresh")
    public static let toggleMembers = Notification.Name("LiquidBagelToggleMembers")
    public static let settings = Notification.Name("LiquidBagelShowSettingsPlaceholder")
    public static func selectServer(_ index: Int) -> Notification.Name {
        Notification.Name("LiquidBagelSelectServer\(index)")
    }
}

public enum MockShellData {
    public static let currentUserID: UserID = "01HX0000000000000000000001"
    public static let snapshot: RealtimeSnapshot = makeSnapshot()

    public static func makeSnapshot() -> RealtimeSnapshot {
        let user = User(id: currentUserID, username: "liquidbagel", discriminator: "0001", displayName: "Liquid Bagel", status: UserStatus(text: "Building the native shell", presence: .online), relationship: .user, online: true)
        let stoat = User(id: "01HX0000000000000000000002", username: "stoat-system", displayName: "Stoat System", relationship: .friend, online: true)
        let design = User(id: "01HX0000000000000000000003", username: "designpilot", displayName: "Design Pilot", relationship: .friend, online: false)
        let ops = User(id: "01HX0000000000000000000004", username: "macops", displayName: "Mac Ops", relationship: .friend, online: true)

        let general: ChannelID = "01HX0000000000000000000101"
        let api: ChannelID = "01HX0000000000000000000102"
        let native: ChannelID = "01HX0000000000000000000103"
        let voice: ChannelID = "01HX0000000000000000000104"
        let dm: ChannelID = "01HX0000000000000000000105"
        let lab: ServerID = "01HX0000000000000000000201"
        let orchard: ServerID = "01HX0000000000000000000202"

        let permissions: Permissions = [.viewChannel, .readMessageHistory, .sendMessage, .react]
        let role = Role(id: "01HX0000000000000000000301", name: "Core Crew", permissions: PermissionOverride(allow: permissions), colour: "#62D6E8", hoist: true, rank: 1)

        let servers = [
            Server(id: lab, ownerID: user.id, name: "Bagel Lab", description: "Native macOS client workshop", channelIDs: [general, api, native, voice], categories: [
                ServerCategory(id: "cat-text", title: "Text Channels", channels: [general, api, native]),
                ServerCategory(id: "cat-voice", title: "Voice", channels: [voice])
            ], roles: [role.id: role], defaultPermissions: permissions),
            Server(id: orchard, ownerID: design.id, name: "Stoat Orchard", description: "Quiet preview server", channelIDs: [], defaultPermissions: [.viewChannel, .readMessageHistory])
        ]

        let channels = [
            Channel(id: general, kind: .textChannel, serverID: lab, name: "general", description: "Daily shell progress and native app notes"),
            Channel(id: api, kind: .textChannel, serverID: lab, name: "api-research", description: "REST and realtime research"),
            Channel(id: native, kind: .textChannel, serverID: lab, name: "macos-native", description: "SwiftUI, materials, and keyboard polish"),
            Channel(id: voice, kind: .voiceChannel, serverID: lab, name: "design crit", description: "Voice is deferred", permissions: [.viewChannel]),
            Channel(id: dm, kind: .directMessage, active: true, recipients: [user.id, design.id])
        ]

        let messagesByChannel: [ChannelID: [Message]] = [
            general: [
                Message(id: "01J00000000000000000000001", channelID: general, authorID: user.id, content: "Phase 3 is finally making the shell feel like an actual native client."),
                Message(id: "01J00000010000000000000001", channelID: general, authorID: user.id, content: "The composer is intentionally local-only for now, but it already has the right weight."),
                Message(id: "01J00000020000000000000001", channelID: general, authorID: stoat.id, content: "Realtime snapshots can hydrate this later without changing the view hierarchy.", reactions: ["🥯": [user.id, design.id]]),
                Message(id: "01J00000030000000000000001", channelID: general, authorID: design.id, content: "The rail/sidebar/chat/member layout is stable enough to build the MVP on top of."),
                Message(id: "01J000000A0000000000000001", channelID: general, authorID: ops.id, content: "I added a note: avoid auto-connecting on launch until login and runtime mode are explicit.", editedAt: Date(timeIntervalSince1970: 1_725_000_000))
            ],
            api: [
                Message(id: "01J00000040000000000000001", channelID: api, authorID: design.id, content: "Ready hydration is the source of truth for server/channel collections."),
                Message(id: "01J00000050000000000000001", channelID: api, authorID: stoat.id, content: "REST remains available for verified channel/message endpoints once credentials exist.")
            ],
            native: [
                Message(id: "01J00000060000000000000001", channelID: native, authorID: user.id, content: "Use standard SwiftUI controls first, then glass only where it clarifies hierarchy."),
                Message(id: "01J00000070000000000000001", channelID: native, authorID: ops.id, content: "Focus rings, labels, and reduced transparency are already part of the foundation.")
            ],
            dm: [
                Message(id: "01J00000080000000000000001", channelID: dm, authorID: design.id, content: "DMs are represented as a placeholder route for now."),
                Message(id: "01J00000090000000000000001", channelID: dm, authorID: user.id, content: "Perfect. Full friends and messaging can land in later phases.")
            ]
        ]

        let members = [user, stoat, design, ops].map {
            ServerMember(id: MemberCompositeKey(serverID: lab, userID: $0.id), joinedAt: Date(timeIntervalSince1970: 1_700_000_000), roles: $0.id == user.id ? [role.id] : [])
        }

        return RealtimeSnapshot(
            usersByID: Dictionary(uniqueKeysWithValues: [user, stoat, design, ops].map { ($0.id, $0) }),
            serversByID: Dictionary(uniqueKeysWithValues: servers.map { ($0.id, $0) }),
            channelsByID: Dictionary(uniqueKeysWithValues: channels.map { ($0.id, $0) }),
            messagesByChannelID: messagesByChannel,
            membersByServerAndUserID: Dictionary(uniqueKeysWithValues: members.map { (ServerMemberKey($0.id), $0) }),
            unreadsByChannelID: [
                api: ChannelUnread(id: ChannelCompositeKey(channelID: api, userID: user.id), lastMessageID: "01J00000040000000000000001", mentions: []),
                native: ChannelUnread(id: ChannelCompositeKey(channelID: native, userID: user.id), lastMessageID: "01J00000060000000000000001", mentions: ["01J00000070000000000000001"])
            ],
            typingUsersByChannelID: [general: [design.id]]
        )
    }
}

public struct LiquidBagelRootView: View {
    @State private var sessionCoordinator: AppSessionCoordinator
    @State private var viewModel: MainShellViewModel

    public init(
        viewModel: MainShellViewModel = MainShellViewModel(runtimeMode: .mock),
        sessionCoordinator: AppSessionCoordinator = AppSessionCoordinator()
    ) {
        _sessionCoordinator = State(initialValue: sessionCoordinator)
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        MainShellView(viewModel: viewModel)
            .task {
                viewModel.attachSessionCoordinator(sessionCoordinator)
                await viewModel.startMockSession()
            }
    }
}

public struct MainShellView: View {
    @Bindable private var viewModel: MainShellViewModel

    public init(viewModel: MainShellViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        HStack(spacing: 0) {
            ServerRailView(viewModel: viewModel)
                .frame(width: StoatSize.serverRailWidth)
            Divider()
            ChannelListView(viewModel: viewModel)
                .frame(width: StoatSize.channelSidebarWidth)
            Divider()
            content
            if viewModel.selection.isMemberPanelVisible {
                Divider()
                MemberPanelView(viewModel: viewModel)
                    .frame(width: StoatSize.memberPanelWidth)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $viewModel.isQuickSwitcherPresented) {
            QuickSwitcherPlaceholderView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.isCredentialSetupPresented) {
            AccountConnectionSettingsView(viewModel: viewModel)
        }
        .sheet(item: $viewModel.editingDraft) { _ in
            EditMessageSheet(viewModel: viewModel)
        }
        .confirmationDialog(
            "Send current composer text?",
            isPresented: $viewModel.isTestSendConfirmationPresented
        ) {
            Button("Send Verification Message") {
                Task { await viewModel.confirmLiveVerificationSend() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This sends the text already in the selected channel composer. Liquid Bagel will not create an automatic test message.")
        }
        .confirmationDialog(
            "Delete this message?",
            isPresented: Binding(
                get: { viewModel.pendingDeletion != nil },
                set: { if !$0 { viewModel.pendingDeletion = nil } }
            )
        ) {
            Button("Delete Message", role: .destructive) {
                Task { await viewModel.confirmPendingDelete() }
            }
            Button("Cancel", role: .cancel) {
                viewModel.pendingDeletion = nil
            }
        } message: {
            Text("This removes the message from the local timeline after the API confirms deletion.")
        }
        .overlay(alignment: .bottom) {
            if let status = viewModel.placeholderStatus ?? viewModel.messageActionStatus ?? viewModel.composerError ?? viewModel.sessionCoordinator?.lastErrorMessage {
                Text(status)
                    .font(.caption)
                    .padding(.horizontal, StoatSpacing.medium)
                    .padding(.vertical, StoatSpacing.small)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, StoatSpacing.medium)
                    .transition(.opacity)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: ShellCommandNotification.quickSwitcher)) { _ in viewModel.showQuickSwitcher() }
        .onReceive(NotificationCenter.default.publisher(for: ShellCommandNotification.focusComposer)) { _ in viewModel.focusComposer() }
        .onReceive(NotificationCenter.default.publisher(for: ShellCommandNotification.refresh)) { _ in viewModel.refreshPlaceholder() }
        .onReceive(NotificationCenter.default.publisher(for: ShellCommandNotification.toggleMembers)) { _ in viewModel.toggleMemberPanel() }
        .onReceive(NotificationCenter.default.publisher(for: ShellCommandNotification.settings)) { _ in viewModel.settingsPlaceholder() }
        .modifier(ServerShortcutReceiver(viewModel: viewModel))
        .onAppear { viewModel.validateSelection() }
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: StoatSpacing.small) {
                    Text(viewModel.title)
                        .font(.headline)
                    connectionChip
                }
            }
            ToolbarItemGroup {
                Button { viewModel.showQuickSwitcher() } label: { Label("Quick Switcher", systemImage: "magnifyingglass") }
                Button { viewModel.toggleMemberPanel() } label: { Label("Toggle Members", systemImage: "sidebar.right") }
                Button { viewModel.showAccountSessions() } label: { Label("Settings", systemImage: "gearshape") }
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch viewModel.selection.space {
        case .home:
            HomeView(viewModel: viewModel)
        case .discover:
            DiscoverPlaceholderView()
        case .directMessages:
            FriendsPlaceholderView(viewModel: viewModel)
        case .server:
            ChatPlaceholderView(viewModel: viewModel)
        }
    }

    private var connectionChip: some View {
        Menu {
            LabeledContent("Mode", value: runtimeModeText)
            LabeledContent("Session", value: sessionStateText)
            LabeledContent("Connection", value: connectionText)
            if let latency = viewModel.effectiveDiagnostics?.lastLatencyMilliseconds {
                LabeledContent("Latency", value: "\(latency) ms")
            }
            if let lastEvent = viewModel.effectiveDiagnostics?.lastReceivedEventAt {
                LabeledContent("Last Event", value: lastEvent.formatted(date: .omitted, time: .standard))
            }
            if let session = viewModel.sessionCoordinator {
                LabeledContent("Credential", value: session.hasSavedCredential ? "Saved" : "Missing")
            }
            Divider()
            Button("Account & Sessions…") {
                viewModel.showAccountSessions()
            }
            Button("Connection Settings…") {
                viewModel.showConnectionSettings()
            }
            if viewModel.sessionCoordinator?.preferences.showDeveloperRuntimeControls != false {
                Button("Developer Verification…") {
                    viewModel.showCredentialSetup()
                }
            }
            if viewModel.sessionCoordinator?.hasSavedCredential == true {
                Button("Validate Saved Session") {
                    Task { await viewModel.sessionCoordinator?.validateSavedSession(); viewModel.syncFromSessionCoordinator() }
                }
            }
            if viewModel.sessionCoordinator?.hasSavedCredential == true {
                Button("Connect Manually") {
                    Task { await viewModel.connectLiveManually() }
                }
                .disabled(isDisconnectable)
            }
            Button("Disconnect") {
                Task { await viewModel.disconnectLive() }
            }
            .disabled(!isDisconnectable)
            Button("Reset to Mock") {
                Task { await viewModel.resetToMock() }
            }
        } label: {
            Text("\(runtimeModeText) · \(connectionText)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, StoatSpacing.small)
                .padding(.vertical, StoatSpacing.xSmall)
        .background(Color.primary.opacity(viewModel.reduceGlassIntensity ? 0.10 : 0.06), in: Capsule())
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel("Runtime \(runtimeModeText), connection state \(connectionText)")
    }

    private var connectionText: String {
        switch viewModel.effectiveConnectionState {
        case .idle: "Mock"
        case .ready: "Ready"
        case .connecting, .authenticating, .authenticated, .connected: "Connecting"
        case .reconnecting: "Reconnecting"
        case .disconnected: "Offline"
        case .failed: "Failed"
        }
    }

    private var runtimeModeText: String {
        switch viewModel.effectiveRuntimeMode {
        case .mock: "Mock"
        case .liveManual: "Live Manual"
        }
    }

    private var sessionStateText: String {
        switch viewModel.effectiveSessionState {
        case .mock: "Mock"
        case .signedOut: "Signed Out"
        case .loadingCredential: "Loading Credential"
        case .savedCredentialUnvalidated: "Saved Credential"
        case .validatingCredential: "Validating"
        case .validatedReady: "Validated"
        case .readyToConnect: "Ready"
        case .connecting: "Connecting"
        case .connected: "Connected"
        case .invalidSession: "Invalid Session"
        case .validationFailed: "Validation Failed"
        case .connectionFailed: "Connection Failed"
        case .keychainFailed: "Keychain Failed"
        case .failed: "Failed"
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
}

public struct CredentialSetupView: View {
    @Bindable private var viewModel: MainShellViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @State private var localLabel = "Main Stoat"
    @State private var email = ""
    @State private var password = ""
    @State private var mfaCode = ""
    @State private var selectedMFAMethod: MFAMethod = .totp
    @State private var useCustomEnvironment = false
    @State private var apiURL: String
    @State private var eventsURL: String
    @State private var mediaURL: String
    @State private var environmentError: String?
    @State private var confirmForget = false
    @State private var confirmRevoke = false

    public init(viewModel: MainShellViewModel) {
        self.viewModel = viewModel
        let environment = viewModel.sessionCoordinator?.environment ?? .production
        _apiURL = State(initialValue: environment.apiBaseURL.absoluteString)
        _eventsURL = State(initialValue: environment.eventsURL.absoluteString)
        _mediaURL = State(initialValue: environment.mediaBaseURL?.absoluteString ?? "")
        _useCustomEnvironment = State(initialValue: !environment.isProduction)
    }

    public var body: some View {
        Form {
            Section("Session") {
                sessionStatusRows
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
                }
                HStack {
                    Button("Forget Session", role: .destructive) {
                        confirmForget = true
                    }
                    .disabled(viewModel.sessionCoordinator?.hasSavedCredential != true)

                    Button("Revoke Session on Server", role: .destructive) {
                        confirmRevoke = true
                    }
                    .disabled(viewModel.sessionCoordinator?.hasSavedCredential != true)

                    Button("Reset to Mock") {
                        Task { await viewModel.resetToMock() }
                    }
                }
            }

            Section("Manual Token Import") {
                TextField("Local label", text: $localLabel)
                SecureField("Session token", text: $token)
                HStack {
                    Button("Validate") {
                        Task {
                            let submitted = token
                            token = ""
                            await viewModel.sessionCoordinator?.validateImportedToken(submitted, localLabel: localLabel)
                            viewModel.syncFromSessionCoordinator()
                        }
                    }
                    .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Save") {
                        Task {
                            await viewModel.sessionCoordinator?.savePendingValidatedSession()
                            viewModel.syncFromSessionCoordinator()
                        }
                    }
                    .disabled(viewModel.sessionCoordinator?.pendingValidatedSession == nil)
                }
            }

            Section("Login") {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                SecureField("Password", text: $password)
                Button("Login") {
                    Task {
                        let submittedPassword = password
                        password = ""
                        await viewModel.sessionCoordinator?.login(email: email, password: submittedPassword, friendlyName: localLabel.isEmpty ? "Liquid Bagel macOS" : localLabel)
                        viewModel.syncFromSessionCoordinator()
                    }
                }
                .disabled(email.isEmpty || password.isEmpty)

                if let challenge = viewModel.sessionCoordinator?.mfaChallenge {
                    Picker("MFA Method", selection: $selectedMFAMethod) {
                        ForEach(challenge.allowedMethods, id: \.self) { method in
                            Text(mfaMethodTitle(method)).tag(method)
                        }
                    }
                    SecureField("MFA code or password", text: $mfaCode)
                    Button("Continue MFA") {
                        Task {
                            let submitted = mfaCode
                            mfaCode = ""
                            await viewModel.sessionCoordinator?.continueLoginMFA(
                                response: mfaResponse(method: selectedMFAMethod, value: submitted),
                                friendlyName: localLabel.isEmpty ? "Liquid Bagel macOS" : localLabel
                            )
                            viewModel.syncFromSessionCoordinator()
                        }
                    }
                    .disabled(mfaCode.isEmpty)
                }
            }

            Section("Environment") {
                Toggle("Use custom environment", isOn: $useCustomEnvironment)
                if useCustomEnvironment {
                    TextField("API base URL", text: $apiURL)
                    TextField("Events WebSocket URL", text: $eventsURL)
                    TextField("Media base URL (optional)", text: $mediaURL)
                } else {
                    LabeledContent("API", value: StoatAPIEnvironment.production.apiBaseURL.absoluteString)
                    LabeledContent("Events", value: StoatAPIEnvironment.production.eventsURL.absoluteString)
                }
                if let environmentError {
                    Text(environmentError).foregroundStyle(.red)
                }
                ForEach((viewModel.sessionCoordinator?.environment.securityWarnings() ?? []), id: \.self) { warning in
                    Text(warning).foregroundStyle(.orange)
                }
                Button("Apply Environment") {
                    applyEnvironment()
                }
            }

            Section("Live Verification") {
                verificationRows
                HStack {
                    Button("Reload Selected Channel Messages") {
                        viewModel.refreshPlaceholder()
                    }
                    Button("Send Composer Text") {
                        viewModel.isTestSendConfirmationPresented = true
                    }
                    .disabled(!viewModel.composerReadiness(for: viewModel.selection.channelID ?? viewModel.selection.dmChannelID).canSend)
                }
            }

            Section("Safe Diagnostics") {
                LabeledContent("Credential", value: viewModel.sessionCoordinator?.hasSavedCredential == true ? "Saved" : "Missing")
                LabeledContent("Environment ID", value: viewModel.sessionCoordinator?.environment.stableID ?? "production")
                if let latency = viewModel.effectiveDiagnostics?.lastLatencyMilliseconds {
                    LabeledContent("Ping latency", value: "\(latency) ms")
                }
                if let lastError = viewModel.sessionCoordinator?.lastErrorMessage {
                    Text(lastError)
                        .foregroundStyle(.secondary)
                }
                Text("Tokens are never shown in this panel.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 680, height: 760)
        .confirmationDialog("Forget saved session?", isPresented: $confirmForget) {
            Button("Forget Session", role: .destructive) {
                Task {
                    await viewModel.sessionCoordinator?.forgetLocalSession()
                    viewModel.syncFromSessionCoordinator()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes the Keychain credential for the selected environment and disconnects live realtime.")
        }
        .confirmationDialog("Revoke session on server?", isPresented: $confirmRevoke) {
            Button("Revoke Session", role: .destructive) {
                Task {
                    await viewModel.sessionCoordinator?.revokeCurrentSessionOnServer()
                    viewModel.syncFromSessionCoordinator()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This asks Stoat to invalidate this session, then removes the local Keychain credential if the server accepts the request.")
        }
    }

    @ViewBuilder private var sessionStatusRows: some View {
        LabeledContent("Mode", value: runtimeModeText)
        LabeledContent("State", value: sessionStateText)
        LabeledContent("Environment", value: viewModel.sessionCoordinator?.environment.isProduction == true ? "Production" : "Custom")
        if let user = viewModel.sessionCoordinator?.currentUser {
            LabeledContent("Current user", value: user.displayName ?? user.username)
        }
    }

    @ViewBuilder private var verificationRows: some View {
        let state = viewModel.sessionCoordinator?.verificationState ?? LiveVerificationState()
        VerificationRow(title: "Credential loaded", isComplete: state.credentialLoaded)
        VerificationRow(title: "Current user fetched", isComplete: state.currentUserFetched)
        VerificationRow(title: "WebSocket connected", isComplete: state.webSocketConnected)
        VerificationRow(title: "Authenticated", isComplete: state.authenticated)
        VerificationRow(title: "Ready received", isComplete: state.readyReceived)
        VerificationRow(title: "Users received", isComplete: state.usersReceived)
        VerificationRow(title: "Servers received", isComplete: state.serversReceived)
        VerificationRow(title: "Channels received", isComplete: state.channelsReceived)
        VerificationRow(title: "Selected channel available", isComplete: state.selectedChannelAvailable)
        VerificationRow(title: "Message fetch succeeded", isComplete: state.messageFetchSucceeded)
        if let lastRealtimeEventAt = state.lastRealtimeEventAt {
            LabeledContent("Last realtime event", value: lastRealtimeEventAt.formatted(date: .omitted, time: .standard))
        }
        if let lastPingLatencyMilliseconds = state.lastPingLatencyMilliseconds {
            LabeledContent("Last ping latency", value: "\(lastPingLatencyMilliseconds) ms")
        }
        if let lastMessageActionResult = state.lastMessageActionResult {
            LabeledContent("Last message action", value: lastMessageActionResult)
        }
    }

    private var isDisconnectable: Bool {
        switch viewModel.effectiveConnectionState {
        case .connecting, .connected, .authenticating, .authenticated, .ready, .reconnecting:
            true
        case .idle, .disconnected, .failed:
            false
        }
    }

    private var runtimeModeText: String {
        switch viewModel.effectiveRuntimeMode {
        case .mock: "Mock"
        case .liveManual: "Live Manual"
        }
    }

    private var sessionStateText: String {
        switch viewModel.effectiveSessionState {
        case .mock: "Mock"
        case .signedOut: "Signed Out"
        case .loadingCredential: "Loading Credential"
        case .savedCredentialUnvalidated: "Saved Credential"
        case .validatingCredential: "Validating"
        case .validatedReady: "Validated"
        case .readyToConnect: "Ready"
        case .connecting: "Connecting"
        case .connected: "Connected"
        case .invalidSession: "Invalid Session"
        case .validationFailed: "Validation Failed"
        case .connectionFailed: "Connection Failed"
        case .keychainFailed: "Keychain Failed"
        case .failed: "Failed"
        }
    }

    private func applyEnvironment() {
        environmentError = nil
        let environment: StoatAPIEnvironment
        do {
            if useCustomEnvironment {
                guard let api = URL(string: apiURL), let events = URL(string: eventsURL) else {
                    throw StoatAPIError.invalidEnvironment("API and events URLs must be valid.")
                }
                let media = mediaURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : URL(string: mediaURL)
                environment = try StoatAPIEnvironment.custom(apiBaseURL: api, eventsURL: events, mediaBaseURL: media ?? nil)
            } else {
                environment = .production
                apiURL = environment.apiBaseURL.absoluteString
                eventsURL = environment.eventsURL.absoluteString
                mediaURL = environment.mediaBaseURL?.absoluteString ?? ""
            }
            Task {
                await viewModel.sessionCoordinator?.setEnvironment(environment)
                viewModel.syncFromSessionCoordinator()
            }
        } catch {
            environmentError = error.userFacingMessage
        }
    }

    private func mfaMethodTitle(_ method: MFAMethod) -> String {
        switch method {
        case .password: "Password"
        case .recovery: "Recovery Code"
        case .totp: "Authenticator App"
        }
    }

    private func mfaResponse(method: MFAMethod, value: String) -> MFAResponse {
        switch method {
        case .password: .password(value)
        case .recovery: .recoveryCode(value)
        case .totp: .totpCode(value)
        }
    }
}

private struct VerificationRow: View {
    var title: String
    var isComplete: Bool

    var body: some View {
        LabeledContent(title, value: isComplete ? "Passed" : "Waiting")
            .foregroundStyle(isComplete ? .primary : .secondary)
    }
}

private struct ServerShortcutReceiver: ViewModifier {
    let viewModel: MainShellViewModel

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: ShellCommandNotification.selectServer(1))) { _ in viewModel.selectServer(atOneBasedIndex: 1) }
            .onReceive(NotificationCenter.default.publisher(for: ShellCommandNotification.selectServer(2))) { _ in viewModel.selectServer(atOneBasedIndex: 2) }
            .onReceive(NotificationCenter.default.publisher(for: ShellCommandNotification.selectServer(3))) { _ in viewModel.selectServer(atOneBasedIndex: 3) }
            .onReceive(NotificationCenter.default.publisher(for: ShellCommandNotification.selectServer(4))) { _ in viewModel.selectServer(atOneBasedIndex: 4) }
            .onReceive(NotificationCenter.default.publisher(for: ShellCommandNotification.selectServer(5))) { _ in viewModel.selectServer(atOneBasedIndex: 5) }
            .onReceive(NotificationCenter.default.publisher(for: ShellCommandNotification.selectServer(6))) { _ in viewModel.selectServer(atOneBasedIndex: 6) }
            .onReceive(NotificationCenter.default.publisher(for: ShellCommandNotification.selectServer(7))) { _ in viewModel.selectServer(atOneBasedIndex: 7) }
            .onReceive(NotificationCenter.default.publisher(for: ShellCommandNotification.selectServer(8))) { _ in viewModel.selectServer(atOneBasedIndex: 8) }
            .onReceive(NotificationCenter.default.publisher(for: ShellCommandNotification.selectServer(9))) { _ in viewModel.selectServer(atOneBasedIndex: 9) }
    }
}

public struct ServerRailView: View {
    private let viewModel: MainShellViewModel

    public init(viewModel: MainShellViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: StoatSpacing.small) {
            ServerRailItem(title: "Home", systemImage: "house.fill", isSelected: viewModel.selection.space == .home) {
                viewModel.selectHome()
            }
            Divider().padding(.horizontal, StoatSpacing.medium)
            ScrollView {
                LazyVStack(spacing: StoatSpacing.small) {
                    ForEach(viewModel.servers) { server in
                        let unread = unreadCount(for: server)
                        let mentions = mentionCount(for: server)
                        ServerRailItem(title: server.name, isSelected: viewModel.selection.serverID == server.id, unreadCount: unread, mentionCount: mentions) {
                            viewModel.selectServer(server.id)
                        }
                    }
                }
            }
            Spacer()
            ServerRailItem(title: "Discover", systemImage: "safari", isSelected: viewModel.selection.space == .discover) {
                viewModel.selectDiscover()
            }
            ServerRailItem(title: "Add Server unavailable in Phase 3", systemImage: "plus", isDisabled: true) {}
        }
        .padding(.vertical, StoatSpacing.medium)
        .background(.regularMaterial)
    }

    private func unreadCount(for server: Server) -> Int {
        server.channelIDs.reduce(0) { count, channelID in
            let unread = viewModel.unread(for: channelID)
            return count + (unread?.lastMessageID == nil ? 0 : 1)
        }
    }

    private func mentionCount(for server: Server) -> Int {
        server.channelIDs.reduce(0) { count, channelID in
            count + (viewModel.unread(for: channelID)?.mentions.count ?? 0)
        }
    }
}

public struct ChannelListView: View {
    private let viewModel: MainShellViewModel

    public init(viewModel: MainShellViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        GlassSidebar {
            VStack(alignment: .leading, spacing: StoatSpacing.large) {
                header
                GlassSearchField(title: "Jump to channel") {
                    viewModel.showQuickSwitcher()
                }
                .padding(.horizontal, StoatSpacing.large)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: StoatSpacing.medium) {
                        switch viewModel.selection.space {
                        case .home:
                            homeRows
                        case .discover:
                            Label("Server Discovery", systemImage: "safari")
                                .padding(.horizontal, StoatSpacing.large)
                        case .directMessages:
                            dmRows
                        case .server:
                            serverChannelRows
                        }
                    }
                    .padding(.horizontal, StoatSpacing.small)
                }
            }
            .padding(.top, StoatSpacing.large)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: StoatSpacing.xSmall) {
            Text(headerTitle)
                .font(StoatTypography.sidebarHeader)
                .lineLimit(1)
            Text(runtimeSubtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, StoatSpacing.large)
    }

    private var headerTitle: String {
        switch viewModel.selection.space {
        case .home: "Liquid Bagel"
        case .discover: "Discover"
        case .directMessages: "Direct Messages"
        case .server: viewModel.selectedServer?.name ?? "Server"
        }
    }

    private var runtimeSubtitle: String {
        switch viewModel.effectiveRuntimeMode {
        case .mock:
            return "Mock runtime · no live connection"
        case .liveManual:
            switch viewModel.effectiveSessionState {
            case .connected:
                return "Live Manual · connected"
            case .connecting, .loadingCredential, .validatingCredential:
                return "Live Manual · connecting"
            case .signedOut:
                return "Live Manual · no credential"
            case .readyToConnect, .validatedReady:
                return "Live Manual · ready"
            case .savedCredentialUnvalidated:
                return "Live Manual · saved credential"
            case .invalidSession:
                return "Live Manual · invalid session"
            case .validationFailed, .connectionFailed, .keychainFailed, .failed:
                return "Live Manual · failed"
            case .mock:
                return "Mock runtime · no live connection"
            }
        }
    }

    private var homeRows: some View {
        VStack(alignment: .leading, spacing: StoatSpacing.xSmall) {
            SidebarButton(title: "Friends", systemImage: "person.2", isSelected: false) {
                viewModel.selectDirectMessages()
            }
            SidebarButton(title: "Discover", systemImage: "safari", isSelected: false) {
                viewModel.selectDiscover()
            }
        }
    }

    private var dmRows: some View {
        VStack(alignment: .leading, spacing: StoatSpacing.xSmall) {
            SidebarButton(title: "Friends", systemImage: "person.2.fill", isSelected: true) {}
            ForEach(viewModel.snapshot.channelsByID.values.filter { $0.kind == .directMessage }) { channel in
                ChannelRow(channel: channel, isSelected: viewModel.selection.dmChannelID == channel.id) {
                    viewModel.selectChannel(channel.id)
                }
            }
        }
    }

    private var serverChannelRows: some View {
        VStack(alignment: .leading, spacing: StoatSpacing.medium) {
            if let server = viewModel.selectedServer, let categories = server.categories, !categories.isEmpty {
                ForEach(categories) { category in
                    section(category.title) {
                        ForEach(category.channels.compactMap { viewModel.snapshot.channelsByID[$0] }) { channel in
                            channelRow(channel)
                        }
                    }
                }
            } else if let serverID = viewModel.selection.serverID {
                section("Channels") {
                    ForEach(viewModel.channels(for: serverID)) { channel in
                        channelRow(channel)
                    }
                }
            }
            Button("Create Channel unavailable in Phase 3") {}
                .buttonStyle(GlassButtonStyle())
                .disabled(true)
                .padding(.horizontal, StoatSpacing.medium)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: StoatSpacing.xSmall) {
            Text(title.uppercased())
                .font(StoatTypography.section)
                .foregroundStyle(.secondary)
                .padding(.horizontal, StoatSpacing.medium)
            content()
        }
    }

    private func channelRow(_ channel: Channel) -> some View {
        let unread = viewModel.unread(for: channel.id)
        return ChannelRow(channel: channel, isSelected: viewModel.selection.channelID == channel.id, unreadCount: unread == nil ? 0 : 1, mentionCount: unread?.mentions.count ?? 0) {
            viewModel.selectChannel(channel.id)
        }
    }
}

private struct SidebarButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, StoatSpacing.medium)
                .frame(minHeight: StoatSize.minimumRowHeight)
                .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: StoatRadius.row, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

public struct ChatPlaceholderView: View {
    private let viewModel: MainShellViewModel

    public init(viewModel: MainShellViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            GlassToolbar {
                HStack(spacing: StoatSpacing.medium) {
                    Label(viewModel.selectedChannel?.displayName ?? "No channel", systemImage: "number")
                        .font(.headline)
                    if let topic = viewModel.selectedChannel?.description {
                        Text(topic).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    GlassIconButton("Pinned messages unavailable in Phase 3", systemImage: "pin", isDisabled: true) {}
                    GlassIconButton("Search unavailable in Phase 3", systemImage: "magnifyingglass", isDisabled: true) {}
                    GlassIconButton("Toggle member panel", systemImage: "sidebar.right") { viewModel.toggleMemberPanel() }
                    GlassIconButton("Channel settings unavailable in Phase 3", systemImage: "gearshape", isDisabled: true) {}
                }
            }
            MessageTimelineView(viewModel: viewModel)
            if let channel = viewModel.selectedChannel {
                let sendReadiness = viewModel.composerReadiness(for: channel.id)
                let inputReadiness = viewModel.composerInputReadiness(for: channel.id)
                GlassComposer(
                    text: Binding(
                        get: { viewModel.draft(for: channel.id) },
                        set: { viewModel.updateDraft($0, for: channel.id) }
                    ),
                    placeholder: inputReadiness.isEnabled ? "Message #\(channel.displayName)" : inputReadiness.reason,
                    isEnabled: inputReadiness.isEnabled,
                    canSend: sendReadiness.canSend,
                    disabledReason: sendReadiness.canSend ? nil : sendReadiness.reason,
                    isSending: viewModel.messageController.sendingChannelIDs.contains(channel.id),
                    canAttach: viewModel.canUploadFiles(in: channel),
                    onSend: {
                        Task { await viewModel.sendDraft(for: channel.id) }
                    }
                ) {
                    viewModel.focusComposer()
                }
                .padding([.horizontal, .bottom], StoatSpacing.large)
            }
        }
    }
}

public struct MessageTimelineView: View {
    private let viewModel: MainShellViewModel

    public init(viewModel: MainShellViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: viewModel.messageDensity == .compact ? StoatSpacing.small : StoatSpacing.medium) {
                if viewModel.selectedChannel == nil {
                    EmptyStateView(title: "Choose a channel", message: "Pick a server channel or DM to open the timeline.")
                        .frame(maxWidth: .infinity)
                } else {
                    timelineContent
                }
            }
            .padding(StoatSpacing.xLarge)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var timelineContent: some View {
        switch viewModel.selectedChannelMessageState {
        case .idle, .loading:
            if viewModel.selectedTimelineMessages.isEmpty {
                LoadingStateView()
                    .frame(maxWidth: .infinity)
            } else {
                timelineMessages(showLoadOlder: false, isLoadingOlder: false)
            }
        case .empty:
            EmptyStateView(title: "Nothing here yet", message: "No messages are loaded for this channel.")
                .frame(maxWidth: .infinity)
        case let .failed(message, cachedMessages):
            if cachedMessages.isEmpty {
                ErrorStateView(message)
                    .frame(maxWidth: .infinity)
                retryButton
            } else {
                inlineError(message)
                timelineMessages(showLoadOlder: false, isLoadingOlder: false)
            }
        case let .loaded(messages, hasMoreBefore):
            if messages.isEmpty {
                EmptyStateView(title: "Nothing here yet", message: "No messages are loaded for this channel.")
                    .frame(maxWidth: .infinity)
            } else {
                timelineMessages(showLoadOlder: hasMoreBefore, isLoadingOlder: false)
            }
        case .loadingOlder:
            timelineMessages(showLoadOlder: false, isLoadingOlder: true)
        }
    }

    @ViewBuilder private func timelineMessages(showLoadOlder: Bool, isLoadingOlder: Bool) -> some View {
        if isLoadingOlder {
            ProgressView("Loading older messages")
                .controlSize(.small)
                .frame(maxWidth: .infinity)
        } else if showLoadOlder {
            Button {
                Task { await viewModel.loadOlderSelectedMessages() }
            } label: {
                Label("Load Older Messages", systemImage: "arrow.up.to.line")
            }
            .buttonStyle(GlassButtonStyle())
            .frame(maxWidth: .infinity)
        }
        unreadSeparator
        ForEach(viewModel.selectedTimelineMessageGroups) { group in
            TimelineMessageGroupView(group: group, author: viewModel.snapshot.usersByID[group.authorID], viewModel: viewModel)
        }
        typingIndicator
    }

    private var retryButton: some View {
        Button {
            viewModel.refreshPlaceholder()
        } label: {
            Label("Retry", systemImage: "arrow.clockwise")
        }
        .buttonStyle(GlassButtonStyle())
        .frame(maxWidth: .infinity)
    }

    private func inlineError(_ message: String) -> some View {
        HStack(spacing: StoatSpacing.small) {
            Image(systemName: "exclamationmark.triangle")
            Text(message)
                .lineLimit(2)
            Spacer()
            Button("Retry") {
                viewModel.refreshPlaceholder()
            }
            .buttonStyle(GlassButtonStyle())
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(StoatSpacing.medium)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: StoatRadius.panel, style: .continuous))
    }

    @ViewBuilder private var typingIndicator: some View {
        let users = viewModel.typingUsers(for: viewModel.selection.channelID ?? viewModel.selection.dmChannelID)
        if !users.isEmpty {
            Text(typingText(users))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, StoatSpacing.small)
        }
    }

    private func typingText(_ users: [User]) -> String {
        let names = users.map { $0.displayName ?? $0.username }
        if names.count == 1 {
            return "\(names[0]) is typing..."
        }
        return "\(names.prefix(2).joined(separator: ", ")) are typing..."
    }

    @ViewBuilder private var unreadSeparator: some View {
        if let channelID = viewModel.selection.channelID ?? viewModel.selection.dmChannelID,
           viewModel.unread(for: channelID) != nil {
            HStack {
                Rectangle().frame(height: 1).foregroundStyle(Color.red.opacity(0.5))
                Text("Unread")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                Rectangle().frame(height: 1).foregroundStyle(Color.red.opacity(0.5))
            }
            .accessibilityLabel("Unread messages separator")
        }
    }
}

public struct TimelineMessageGroupView: View {
    private let group: TimelineMessageGroup
    private let author: User?
    private let viewModel: MainShellViewModel

    public init(group: TimelineMessageGroup, author: User?, viewModel: MainShellViewModel) {
        self.group = group
        self.author = author
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(group.messages.enumerated()), id: \.element.id) { index, timelineMessage in
                VStack(alignment: .leading, spacing: StoatSpacing.xSmall) {
                    MessageRow(message: timelineMessage.message, author: author, showsHeader: index == 0)
                        .contextMenu {
                            Button("Copy Message") {
                                viewModel.copyMessage(timelineMessage.message)
                            }
                            if viewModel.canEdit(timelineMessage.message) {
                                Button("Edit Message") {
                                    viewModel.beginEditing(timelineMessage)
                                }
                            }
                            if viewModel.canDelete(timelineMessage.message) {
                                Button("Delete Message", role: .destructive) {
                                    viewModel.requestDelete(timelineMessage)
                                }
                            }
                            if viewModel.canReact(to: timelineMessage.message) {
                                Divider()
                                ForEach(["👍", "❤️", "😂"], id: \.self) { emoji in
                                    Button("React \(emoji)") {
                                        Task { await viewModel.toggleReaction(emoji, on: timelineMessage) }
                                    }
                                }
                            }
                            #if DEBUG
                            Button("Copy Message ID") {
                                #if canImport(AppKit)
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(timelineMessage.message.id.rawValue, forType: .string)
                                #endif
                            }
                            #endif
                        }
                    statusView(for: timelineMessage)
                }
            }
        }
        .id(group.id)
    }

    @ViewBuilder private func statusView(for timelineMessage: TimelineMessage) -> some View {
        switch timelineMessage.status {
        case .confirmed:
            EmptyView()
        case .pending:
            Text("Sending...")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.leading, StoatSize.avatar + StoatSpacing.medium)
        case let .failed(message):
            HStack(spacing: StoatSpacing.small) {
                Text("Failed: \(message)")
                    .font(.caption2)
                    .foregroundStyle(.red)
                Button("Retry") {
                    Task { await viewModel.retry(timelineMessage) }
                }
                .buttonStyle(.borderless)
            }
            .padding(.leading, StoatSize.avatar + StoatSpacing.medium)
        }
    }
}

public struct EditMessageSheet: View {
    @Bindable private var viewModel: MainShellViewModel

    public init(viewModel: MainShellViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: StoatSpacing.large) {
            Text("Edit Message")
                .font(.headline)
            TextEditor(text: Binding(
                get: { viewModel.editingDraft?.content ?? "" },
                set: { viewModel.editingDraft?.content = $0 }
            ))
            .frame(minHeight: 120)
            HStack {
                Spacer()
                Button("Cancel") {
                    viewModel.editingDraft = nil
                }
                Button("Save") {
                    Task { await viewModel.saveEditingDraft() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.editingDraft?.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false)
            }
        }
        .padding(StoatSpacing.xLarge)
        .frame(width: 460)
    }
}

public struct MemberPanelView: View {
    private let viewModel: MainShellViewModel

    public init(viewModel: MainShellViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: StoatSpacing.large) {
            HStack {
                Text("Members")
                    .font(.headline)
                Spacer()
                Text("\(members.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if members.isEmpty {
                EmptyStateView(title: "No members", message: "Select a server to preview members.", systemImage: "person.2")
                    .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: StoatSpacing.xSmall) {
                        Text("ONLINE")
                            .font(StoatTypography.section)
                            .foregroundStyle(.secondary)
                        ForEach(members.filter(\.online)) { user in
                            MemberRow(user: user, subtitle: roleSubtitle(for: user))
                        }
                        Text("OFFLINE")
                            .font(StoatTypography.section)
                            .foregroundStyle(.secondary)
                            .padding(.top, StoatSpacing.medium)
                        ForEach(members.filter { !$0.online }) { user in
                            MemberRow(user: user, subtitle: roleSubtitle(for: user))
                        }
                    }
                }
            }
            Spacer()
        }
        .padding(StoatSpacing.large)
        .background(.thinMaterial)
    }

    private var members: [User] {
        viewModel.members(for: viewModel.selection.serverID)
    }

    private func roleSubtitle(for user: User) -> String {
        guard let serverID = viewModel.selection.serverID,
              let member = viewModel.snapshot.membersByServerAndUserID[ServerMemberKey(serverID: serverID, userID: user.id)],
              let roleID = member.roles.first,
              let role = viewModel.snapshot.serversByID[serverID]?.roles[roleID]
        else {
            return "@\(user.username)"
        }
        return role.name
    }
}

public struct HomeView: View {
    private let viewModel: MainShellViewModel

    public init(viewModel: MainShellViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StoatSpacing.xLarge) {
                Text("Home")
                    .font(.largeTitle.weight(.semibold))
                HStack(alignment: .top, spacing: StoatSpacing.large) {
                    GlassPanel {
                        VStack(alignment: .leading, spacing: StoatSpacing.medium) {
                            Text("Current User").font(.headline)
                            if let user = viewModel.snapshot.usersByID[MockShellData.currentUserID] {
                                MemberRow(user: user, subtitle: user.status?.text)
                            }
                        }
                    }
                    GlassPanel {
                        VStack(alignment: .leading, spacing: StoatSpacing.medium) {
                            Text("Recent DMs").font(.headline)
                            ForEach(viewModel.snapshot.channelsByID.values.filter { $0.kind == .directMessage }) { channel in
                                Button(channel.displayName) { viewModel.selectChannel(channel.id) }
                                    .buttonStyle(GlassButtonStyle())
                            }
                        }
                    }
                }
                FriendsPlaceholderView(viewModel: viewModel)
            }
            .padding(StoatSpacing.xxLarge)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

public struct FriendsPlaceholderView: View {
    private let viewModel: MainShellViewModel
    @State private var tab = "Online"
    private let tabs = ["Online", "All", "Pending", "Blocked"]

    public init(viewModel: MainShellViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: StoatSpacing.large) {
            HStack {
                Text("Friends")
                    .font(.title2.weight(.semibold))
                Spacer()
                Picker("Friend filter", selection: $tab) {
                    ForEach(tabs, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 330)
            }
            GlassPanel {
                VStack(alignment: .leading, spacing: StoatSpacing.medium) {
                    ForEach(friendRows) { user in
                        MemberRow(user: user, subtitle: user.relationship.rawAPIValue)
                    }
                    Button("Add Friend unavailable in Phase 3") {}
                        .buttonStyle(GlassButtonStyle())
                        .disabled(true)
                }
            }
        }
        .padding(StoatSpacing.xxLarge)
    }

    private var friendRows: [User] {
        viewModel.snapshot.usersByID.values
            .filter { $0.id != MockShellData.currentUserID }
            .sorted { $0.username < $1.username }
    }
}

public struct DiscoverPlaceholderView: View {
    @State private var invite = ""

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: StoatSpacing.xLarge) {
            Text("Discover")
                .font(.largeTitle.weight(.semibold))
            GlassPanel {
                VStack(alignment: .leading, spacing: StoatSpacing.large) {
                    Text("Server discovery placeholder")
                        .font(.title3.weight(.semibold))
                    Text("Discovery, invites, and joins are intentionally deferred.")
                        .foregroundStyle(.secondary)
                    HStack {
                        TextField("Paste invite code", text: $invite)
                            .textFieldStyle(.roundedBorder)
                        Button("Join") {}
                            .buttonStyle(GlassButtonStyle())
                            .disabled(true)
                    }
                }
            }
            EmptyStateView(title: "Public discovery comes later", message: "Phase 6 can wire real discovery and invite flows.", systemImage: "safari")
            Spacer()
        }
        .padding(StoatSpacing.xxLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

public struct QuickSwitcherPlaceholderView: View {
    private let viewModel: MainShellViewModel

    public init(viewModel: MainShellViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: StoatSpacing.large) {
            Text("Quick Switcher")
                .font(.title2.weight(.semibold))
            GlassSearchField(title: "Search is unavailable in Phase 3") {}
            ForEach(viewModel.servers.prefix(5)) { server in
                Button(server.name) {
                    viewModel.selectServer(server.id)
                    viewModel.isQuickSwitcherPresented = false
                }
                .buttonStyle(GlassButtonStyle(selected: viewModel.selection.serverID == server.id))
            }
        }
        .padding(StoatSpacing.xLarge)
        .frame(width: 440)
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
                LabeledContent("App phase", value: "Phase 5")
                LabeledContent("Runtime", value: "Mock by default, Live Manual only")
                LabeledContent("Credentials", value: "Keychain scoped by environment")
                LabeledContent("Custom environment", value: "Memory-only")
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
public typealias PhaseThreeStatus = PhaseOneStatus
public typealias PhaseFourStatus = PhaseOneStatus

@available(macOS 15.0, *)
#Preview("Shell Dark") {
    MainShellView(viewModel: MainShellViewModel(snapshot: MockShellData.snapshot, runtimeMode: .mock))
        .preferredColorScheme(.dark)
        .frame(width: 1180, height: 760)
}

@available(macOS 15.0, *)
#Preview("Shell Light") {
    MainShellView(viewModel: MainShellViewModel(snapshot: MockShellData.snapshot, runtimeMode: .mock))
        .preferredColorScheme(.light)
        .frame(width: 1180, height: 760)
}

@available(macOS 15.0, *)
#Preview("No Server Selected") {
    MainShellView(viewModel: MainShellViewModel(selection: ShellSelection(space: .home), snapshot: MockShellData.snapshot, runtimeMode: .mock))
        .frame(width: 980, height: 640)
}

@available(macOS 15.0, *)
#Preview("Member Panel Hidden") {
    MainShellView(viewModel: MainShellViewModel(selection: ShellSelection(space: .server("01HX0000000000000000000201"), serverID: "01HX0000000000000000000201", channelID: "01HX0000000000000000000101", isMemberPanelVisible: false), snapshot: MockShellData.snapshot, runtimeMode: .mock))
        .preferredColorScheme(.dark)
        .frame(width: 980, height: 640)
}

@available(macOS 15.0, *)
#Preview("Credential Setup - No Credential") {
    CredentialSetupView(viewModel: MainShellViewModel(runtimeMode: .liveManual, sessionState: .signedOut, currentUser: nil))
}

@available(macOS 15.0, *)
#Preview("Credential Setup - Token Entry") {
    CredentialSetupView(viewModel: MainShellViewModel(runtimeMode: .liveManual, sessionState: .signedOut, currentUser: nil))
}

@available(macOS 15.0, *)
#Preview("Credential Setup - Validating") {
    CredentialSetupView(viewModel: MainShellViewModel(runtimeMode: .liveManual, sessionState: .validatingCredential, currentUser: nil))
}

@available(macOS 15.0, *)
#Preview("Credential Setup - Validation Failed") {
    CredentialSetupView(viewModel: MainShellViewModel(runtimeMode: .liveManual, sessionState: .validationFailed("The session could not be validated."), currentUser: nil))
}

@available(macOS 15.0, *)
#Preview("Credential Setup - Ready") {
    CredentialSetupView(viewModel: MainShellViewModel(runtimeMode: .liveManual, sessionState: .readyToConnect, currentUser: MockShellData.snapshot.usersByID[MockShellData.currentUserID]))
}

@available(macOS 15.0, *)
#Preview("Credential Setup - Connected Diagnostics") {
    CredentialSetupView(viewModel: MainShellViewModel(runtimeMode: .liveManual, sessionState: .connected, currentUser: MockShellData.snapshot.usersByID[MockShellData.currentUserID]))
}

@available(macOS 15.0, *)
#Preview("Credential Setup - Invalid Session") {
    CredentialSetupView(viewModel: MainShellViewModel(runtimeMode: .liveManual, sessionState: .invalidSession("The saved session expired."), currentUser: nil))
}

@available(macOS 15.0, *)
#Preview("Credential Setup - Custom Environment") {
    CredentialSetupView(viewModel: MainShellViewModel(runtimeMode: .liveManual, sessionState: .savedCredentialUnvalidated, currentUser: nil))
}
