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

public struct ShellSelectionRestorationResult: Hashable, Sendable {
    public var selection: ShellSelection
    public var selectedServerAvailable: Bool
    public var selectedChannelAvailable: Bool
    public var message: String?

    public init(
        selection: ShellSelection,
        selectedServerAvailable: Bool,
        selectedChannelAvailable: Bool,
        message: String? = nil
    ) {
        self.selection = selection
        self.selectedServerAvailable = selectedServerAvailable
        self.selectedChannelAvailable = selectedChannelAvailable
        self.message = message
    }
}

public struct ShellSelectionRestorer: Sendable {
    public init() {}

    public func restore(
        preferredSelection: ShellSelection?,
        preferences: AppPreferences,
        snapshot: RealtimeSnapshot,
        mode: AppRuntimeMode
    ) -> ShellSelectionRestorationResult {
        guard mode == .liveManual else {
            return ShellSelectionRestorationResult(
                selection: preferredSelection ?? ShellSelection(isMemberPanelVisible: preferences.memberPanelVisible),
                selectedServerAvailable: true,
                selectedChannelAvailable: true
            )
        }

        let base = preferredSelection ?? ShellSelection(isMemberPanelVisible: preferences.memberPanelVisible)
        if snapshot.serversByID.isEmpty {
            return ShellSelectionRestorationResult(
                selection: ShellSelection(space: .home, isMemberPanelVisible: preferences.memberPanelVisible),
                selectedServerAvailable: false,
                selectedChannelAvailable: false,
                message: "No servers available"
            )
        }

        if (base.space == .home || base.space == .discover),
           preferences.lastSelectedServerID == nil,
           preferences.lastSelectedChannelID == nil {
            if firstServerWithVisibleTextChannel(snapshot: snapshot) != nil {
                return ShellSelectionRestorationResult(
                    selection: ShellSelection(space: base.space, isMemberPanelVisible: preferences.memberPanelVisible),
                    selectedServerAvailable: true,
                    selectedChannelAvailable: true
                )
            }
        }

        let preferredServerID = preferences.lastSelectedServerID ?? base.serverID
        let preferredChannelID = preferences.lastSelectedChannelID ?? base.channelID

        if let serverID = preferredServerID, snapshot.serversByID[serverID] != nil {
            return restore(inServer: serverID, preferredChannelID: preferredChannelID, preferences: preferences, snapshot: snapshot, preferredServerWasAvailable: true)
        }

        if let channelID = preferredChannelID,
           let channel = snapshot.channelsByID[channelID],
           let serverID = channel.serverID,
           snapshot.serversByID[serverID] != nil,
           isVisibleTextChannel(channel) {
            return ShellSelectionRestorationResult(
                selection: ShellSelection(
                    space: .server(serverID),
                    serverID: serverID,
                    channelID: channelID,
                    isMemberPanelVisible: preferences.memberPanelVisible
                ),
                selectedServerAvailable: true,
                selectedChannelAvailable: true
            )
        }

        guard let fallback = firstServerWithVisibleTextChannel(snapshot: snapshot) else {
            let server = orderedServers(snapshot: snapshot).first
            return ShellSelectionRestorationResult(
                selection: ShellSelection(
                    space: server.map { .server($0.id) } ?? .home,
                    serverID: server?.id,
                    isMemberPanelVisible: preferences.memberPanelVisible
                ),
                selectedServerAvailable: false,
                selectedChannelAvailable: false,
                message: "No text channels available"
            )
        }

        return ShellSelectionRestorationResult(
            selection: ShellSelection(
                space: .server(fallback.server.id),
                serverID: fallback.server.id,
                channelID: fallback.channel.id,
                isMemberPanelVisible: preferences.memberPanelVisible
            ),
            selectedServerAvailable: false,
            selectedChannelAvailable: false,
            message: "Selected channel no longer exists"
        )
    }

    private func restore(
        inServer serverID: ServerID,
        preferredChannelID: ChannelID?,
        preferences: AppPreferences,
        snapshot: RealtimeSnapshot,
        preferredServerWasAvailable: Bool
    ) -> ShellSelectionRestorationResult {
        if let channelID = preferredChannelID,
           let channel = snapshot.channelsByID[channelID],
           channel.serverID == serverID,
           isVisibleTextChannel(channel) {
            return ShellSelectionRestorationResult(
                selection: ShellSelection(space: .server(serverID), serverID: serverID, channelID: channelID, isMemberPanelVisible: preferences.memberPanelVisible),
                selectedServerAvailable: true,
                selectedChannelAvailable: true
            )
        }

        if let channel = firstVisibleTextChannel(in: serverID, snapshot: snapshot) {
            return ShellSelectionRestorationResult(
                selection: ShellSelection(space: .server(serverID), serverID: serverID, channelID: channel.id, isMemberPanelVisible: preferences.memberPanelVisible),
                selectedServerAvailable: preferredServerWasAvailable,
                selectedChannelAvailable: false,
                message: "Selected channel no longer exists"
            )
        }

        return ShellSelectionRestorationResult(
            selection: ShellSelection(space: .server(serverID), serverID: serverID, isMemberPanelVisible: preferences.memberPanelVisible),
            selectedServerAvailable: preferredServerWasAvailable,
            selectedChannelAvailable: false,
            message: "No text channels available"
        )
    }

    private func firstServerWithVisibleTextChannel(snapshot: RealtimeSnapshot) -> (server: Server, channel: Channel)? {
        for server in orderedServers(snapshot: snapshot) {
            if let channel = firstVisibleTextChannel(in: server.id, snapshot: snapshot) {
                return (server, channel)
            }
        }
        return nil
    }

    private func firstVisibleTextChannel(in serverID: ServerID, snapshot: RealtimeSnapshot) -> Channel? {
        let server = snapshot.serversByID[serverID]
        let channels = snapshot.channelsByID.values.filter { $0.serverID == serverID }
        let ordered: [Channel]
        if let ids = server?.channelIDs, !ids.isEmpty {
            ordered = ids.compactMap { id in channels.first { $0.id == id } }
        } else {
            ordered = channels.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        }
        return ordered.first(where: isVisibleTextChannel)
    }

    private func orderedServers(snapshot: RealtimeSnapshot) -> [Server] {
        snapshot.serversByID.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func isVisibleTextChannel(_ channel: Channel) -> Bool {
        channel.kind == .textChannel || channel.kind == .group || channel.kind == .savedMessages
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

public enum MessageQuickActions {
    public static let quickReactions = ["👍", "❤️", "😂", "👀", "✅"]
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
    public var quickSwitcherViewModel: QuickSwitcherViewModel
    public var placeholderStatus: String?
    public var shouldFocusComposer = false
    public var composerFocusRequestID = 0
    public var focusTarget: ShellFocusTarget?
    public var previousFocusTarget: ShellFocusTarget?
    public var composerDrafts: [ChannelID: ComposerDraftState] = [:]
    public var composerError: String?
    public var editingDraft: EditingMessageDraft?
    public var inlineEditState: InlineEditState?
    public var pendingDeletion: TimelineMessage?
    public var timelineSelection = TimelineSelection()
    public var timelineViewport = TimelineViewportState()
    public var localReadStates: [ChannelID: LocalReadState] = [:]
    public var messageActionStatus: String?
    public var isCredentialSetupPresented = false
    public var isTestSendConfirmationPresented = false
    public var selectedSettingsTab: SettingsSectionTab = .account
    public var messageDensity: MessageDensityPreference = .comfortable
    public var reduceGlassIntensity = false

    @ObservationIgnored public var messageActionHandler: any MessageActionHandling
    @ObservationIgnored public var channelAckSender: any ChannelAckSending
    @ObservationIgnored private var snapshotObservationTask: Task<Void, Never>?
    @ObservationIgnored private var selectedChannelLoadTask: Task<Void, Never>?
    @ObservationIgnored private var typingEndTask: Task<Void, Never>?
    @ObservationIgnored private var ackTask: Task<Void, Never>?
    @ObservationIgnored private var activeTypingChannelID: ChannelID?
    @ObservationIgnored private var lastTypingBeginAt: [ChannelID: Date] = [:]
    @ObservationIgnored private var lastAckedMessageByChannelID: [ChannelID: MessageID] = [:]
    @ObservationIgnored private var locallyClearedUnreadChannelIDs: Set<ChannelID> = []
    @ObservationIgnored private var restoredLiveConnectionGeneration: Int?
    @ObservationIgnored private var previousSnapshot = RealtimeSnapshot()
    @ObservationIgnored private let selectionRestorer = ShellSelectionRestorer()
    @ObservationIgnored private let navigationHelper = ShellNavigationHelper()
    @ObservationIgnored private let viewportReducer = TimelineViewportReducer()

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
        messageActionHandler: (any MessageActionHandling)? = nil,
        channelAckSender: (any ChannelAckSending)? = nil
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
        self.channelAckSender = channelAckSender ?? NoopChannelAckSender()
        self.previousSnapshot = snapshot
        self.quickSwitcherViewModel = QuickSwitcherViewModel(snapshot: snapshot, selection: selection)
        self.quickSwitcherViewModel = QuickSwitcherViewModel(
            snapshot: snapshot,
            selection: selection,
            canPerform: { [weak self] command in self?.canPerform(command) ?? false },
            disabledReason: { [weak self] command in self?.disabledReason(for: command) }
        )
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
        ackTask?.cancel()
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
        clearTimelineSelection()
        placeholderStatus = nil
        persistLiveSelectionIfNeeded()
    }

    public func selectDiscover() {
        endTypingForActiveChannel()
        selection.space = .discover
        selection.serverID = nil
        selection.channelID = nil
        selection.dmChannelID = nil
        clearTimelineSelection()
        placeholderStatus = nil
        persistLiveSelectionIfNeeded()
    }

    public func selectDirectMessages() {
        endTypingForActiveChannel()
        selection.space = .directMessages
        selection.serverID = nil
        selection.channelID = nil
        selection.dmChannelID = snapshot.channelsByID.values.first { $0.kind == .directMessage }?.id
        clearTimelineSelection()
        placeholderStatus = nil
        acknowledgeSelectedChannel()
        scheduleSelectedChannelLoad()
        persistLiveSelectionIfNeeded()
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
        clearTimelineSelection()
        updateViewportForSelectedChannel()
        placeholderStatus = nil
        acknowledgeSelectedChannel()
        scheduleSelectedChannelLoad()
        persistLiveSelectionIfNeeded()
    }

    public func selectServer(atOneBasedIndex index: Int) {
        guard let server = navigationHelper.server(atOneBasedIndex: index, snapshot: snapshot) else {
            placeholderStatus = "No server at shortcut \(index)."
            return
        }
        selectServer(server.id)
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
        clearTimelineSelection()
        updateViewportForSelectedChannel()
        placeholderStatus = nil
        requestFocus(.timeline)
        acknowledgeSelectedChannel()
        scheduleSelectedChannelLoad()
        persistLiveSelectionIfNeeded()
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
        previousFocusTarget = focusTarget
        requestFocus(.quickSwitcher)
        quickSwitcherViewModel.update(snapshot: snapshot, selection: selection)
        isQuickSwitcherPresented = true
        placeholderStatus = nil
    }

    public func closeQuickSwitcher() {
        isQuickSwitcherPresented = false
        requestFocus(previousFocusTarget ?? .timeline)
    }

    public func focusComposer() {
        shouldFocusComposer.toggle()
        composerFocusRequestID += 1
        requestFocus(.composer)
        placeholderStatus = selectedChannel == nil ? "Select a channel before focusing the composer." : nil
    }

    public func refreshPlaceholder() {
        refreshCurrentContext()
    }

    public func refreshCurrentContext() {
        switch effectiveRuntimeMode {
        case .mock:
            if let channelID = selection.channelID ?? selection.dmChannelID {
                Task { [weak self] in
                    guard let self else { return }
                    await self.messageController.refreshMessages(channelID: channelID, snapshotMessages: self.snapshot.messagesByChannelID[channelID] ?? [])
                    self.placeholderStatus = "Mock data refreshed"
                }
            } else {
                placeholderStatus = "Mock data refreshed"
            }
        case .liveManual:
            switch effectiveConnectionState {
            case .ready:
                if let channelID = selection.channelID ?? selection.dmChannelID {
                    Task { [weak self] in
                        guard let self else { return }
                        await self.messageController.refreshMessages(channelID: channelID, snapshotMessages: self.snapshot.messagesByChannelID[channelID] ?? [])
                        self.sessionCoordinator?.markSelectedChannelMessageFetchSucceeded(channelID: channelID, isAvailable: self.snapshot.channelsByID[channelID] != nil)
                        self.placeholderStatus = self.messageController.lastErrorByChannelID[channelID] == nil ? "Channel messages refreshed" : nil
                    }
                } else {
                    placeholderStatus = "Live status refreshed"
                }
            case .disconnected, .failed, .idle:
                placeholderStatus = "Reconnect to refresh live state"
            case .connecting, .connected, .authenticating, .authenticated, .reconnecting:
                placeholderStatus = "Waiting for realtime data"
            }
        }
    }

    public func legacyRefreshSelectedChannel() {
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

    public func reconnectLiveManually() async {
        guard let sessionCoordinator else { return }
        placeholderStatus = nil
        await sessionCoordinator.reconnectLiveManually()
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
        channelAckSender = liveAPIClient.map { LiveChannelAckSender(apiClient: $0) } ?? NoopChannelAckSender()
        messageController.configure(
            runtimeMode: sessionCoordinator.mode,
            apiClient: liveAPIClient,
            currentUserID: sessionCoordinator.currentUser?.id ?? (sessionCoordinator.mode == .mock ? MockShellData.currentUserID : nil)
        )
        observe(snapshotSource: sessionCoordinator.snapshotSource)
        validateSelection()
        messageController.hydrate(from: snapshot)
        quickSwitcherViewModel.update(snapshot: snapshot, selection: selection)
        scheduleSelectedChannelLoad()
        if sessionCoordinator.mode != .liveManual {
            restoredLiveConnectionGeneration = nil
        }
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
        return composerDraftState(for: channelID).text
    }

    public func updateDraft(_ draft: String, for channelID: ChannelID?) {
        guard let channelID else { return }
        var state = composerDraftState(for: channelID)
        state.text = draft
        composerDrafts[channelID] = state
        scheduleTyping(for: channelID, draft: draft)
    }

    public func composerDraftState(for channelID: ChannelID?) -> ComposerDraftState {
        guard let channelID else {
            return ComposerDraftState(channelID: "")
        }
        return composerDrafts[channelID] ?? ComposerDraftState(channelID: channelID)
    }

    public func replyContext(for channelID: ChannelID?) -> ReplyContext? {
        composerDraftState(for: channelID).replyContext
    }

    public func updateReplyMentionPreference(_ shouldMention: Bool, for channelID: ChannelID?) {
        guard let channelID else { return }
        var state = composerDraftState(for: channelID)
        state.shouldMentionReplyAuthor = shouldMention
        composerDrafts[channelID] = state
    }

    public func cancelReply(for channelID: ChannelID?) {
        guard let channelID else { return }
        var state = composerDraftState(for: channelID)
        state.replyContext = nil
        state.shouldMentionReplyAuthor = true
        composerDrafts[channelID] = state
        if timelineSelection.focus.mode == .replying {
            timelineSelection.focus.mode = timelineSelection.messageID == nil ? .none : .selected
        }
        requestFocus(.composer)
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

    public func canEdit(_ timelineMessage: TimelineMessage) -> Bool {
        guard timelineMessage.status == .confirmed else { return false }
        guard timelineMessage.message.content?.isEmpty == false else { return false }
        return canEdit(timelineMessage.message)
    }

    public func canDelete(_ message: Message) -> Bool {
        guard isRuntimeSendCapable else { return false }
        if currentUserID == message.authorID { return true }
        guard let channel = snapshot.channelsByID[message.channelID],
              let permissions = resolvedPermissions(for: channel)
        else { return false }
        return permissions.contains(.manageMessages)
    }

    public func canDelete(_ timelineMessage: TimelineMessage) -> Bool {
        switch timelineMessage.status {
        case .failed:
            return true
        case .pending, .deleting:
            return false
        case .confirmed:
            return canDelete(timelineMessage.message)
        }
    }

    public func canPin(_ timelineMessage: TimelineMessage) -> Bool {
        guard timelineMessage.status == .confirmed else { return false }
        guard isRuntimeSendCapable else { return false }
        guard let channel = snapshot.channelsByID[timelineMessage.message.channelID] else { return false }
        guard let permissions = resolvedPermissions(for: channel) else { return true }
        return permissions.contains(.manageMessages)
    }

    public func canReply(to timelineMessage: TimelineMessage) -> Bool {
        guard timelineMessage.status == .confirmed else { return false }
        guard timelineMessage.message.system == nil else { return false }
        guard snapshot.channelsByID[timelineMessage.message.channelID] != nil else { return false }
        return isRuntimeSendCapable
    }

    public func beginReply(to timelineMessage: TimelineMessage, source: MessageFocusSource = .keyboard) {
        guard canReply(to: timelineMessage) else {
            placeholderStatus = "Selected message cannot be replied to."
            return
        }
        let author = snapshot.usersByID[timelineMessage.message.authorID]
        let authorName = timelineMessage.message.masquerade?.name ?? author?.displayName ?? author?.username ?? timelineMessage.message.authorID.rawValue
        var draftState = composerDraftState(for: timelineMessage.message.channelID)
        draftState.replyContext = ReplyContext(
            channelID: timelineMessage.message.channelID,
            messageID: timelineMessage.message.id,
            authorDisplayName: authorName,
            contentPreview: Self.replyPreviewText(for: timelineMessage.message)
        )
        draftState.shouldMentionReplyAuthor = true
        composerDrafts[timelineMessage.message.channelID] = draftState
        timelineSelection = TimelineSelection(channelID: timelineMessage.message.channelID, messageID: timelineMessage.message.id, source: source, mode: .replying)
        timelineViewport = viewportReducer.keepVisible(timelineViewport, messageID: timelineMessage.message.id, reason: .jumpCommand)
        focusComposer()
    }

    public func sendDraft(for channelID: ChannelID?) async {
        guard let channelID else { return }
        let readiness = composerReadiness(for: channelID)
        guard readiness.canSend else {
            composerError = readiness.reason
            return
        }
        let content = draft(for: channelID).trimmingCharacters(in: .whitespacesAndNewlines)
        let draftState = composerDraftState(for: channelID)
        let replies = draftState.replyContext.map { [MessageReply(id: $0.messageID, mention: draftState.shouldMentionReplyAuthor)] }
        composerDrafts[channelID] = ComposerDraftState(channelID: channelID)
        composerError = nil
        if await messageController.sendMessage(channelID: channelID, content: content, replies: replies, handler: messageActionHandler) {
            acknowledgeSelectedChannel()
        }
    }

    public func retry(_ timelineMessage: TimelineMessage) async {
        messageController.markRetryStarted(timelineMessage)
        timelineSelection = TimelineSelection(channelID: timelineMessage.message.channelID, messageID: timelineMessage.message.id, source: .keyboard, mode: .failedRecovery)
        timelineViewport = viewportReducer.keepVisible(timelineViewport, messageID: timelineMessage.message.id, reason: .retrySend)
        _ = await messageController.retrySend(timelineMessage, handler: messageActionHandler)
        reconcileTimelineSelection()
    }

    public func loadOlderSelectedMessages() async {
        guard let channelID = selection.channelID ?? selection.dmChannelID else { return }
        let previousOldest = selectedTimelineMessages.first?.message.id
        await messageController.loadOlderMessages(channelID: channelID)
        timelineViewport = viewportReducer.preserveAfterPrepend(timelineViewport, previousOldestID: previousOldest)
    }

    public func beginEditing(_ timelineMessage: TimelineMessage) {
        guard canEdit(timelineMessage) else { return }
        let content = timelineMessage.message.content ?? ""
        inlineEditState = InlineEditState(
            channelID: timelineMessage.message.channelID,
            messageID: timelineMessage.message.id,
            originalContent: content,
            draftContent: content
        )
        editingDraft = EditingMessageDraft(message: timelineMessage.message, content: content)
        timelineSelection = TimelineSelection(channelID: timelineMessage.message.channelID, messageID: timelineMessage.message.id, source: .keyboard, mode: .editing)
        timelineViewport = viewportReducer.keepVisible(timelineViewport, messageID: timelineMessage.message.id, reason: .jumpCommand)
        requestFocus(.inlineEdit)
    }

    public func saveEditingDraft() async {
        guard var editState = inlineEditState else {
            guard let editingDraft else { return }
            inlineEditState = InlineEditState(channelID: editingDraft.message.channelID, messageID: editingDraft.message.id, originalContent: editingDraft.message.content ?? "", draftContent: editingDraft.content)
            await saveEditingDraft()
            return
        }
        if let editingDraft, editingDraft.id == editState.messageID {
            editState.draftContent = editingDraft.content
        }
        guard editState.canSave else { return }
        if let localFailed = selectedTimelineMessages.first(where: { $0.message.id == editState.messageID }),
           case .failed = localFailed.status {
            messageController.discardLocalMessage(localFailed)
            inlineEditState = nil
            editingDraft = nil
            var draftState = composerDraftState(for: editState.channelID)
            draftState.text = editState.draftContent
            composerDrafts[editState.channelID] = draftState
            await sendDraft(for: editState.channelID)
            requestFocus(.timeline)
            return
        }
        editState.isSaving = true
        editState.errorMessage = nil
        inlineEditState = editState
        editingDraft = EditingMessageDraft(message: selectedTimelineMessages.first { $0.message.id == editState.messageID }?.message ?? Message(id: editState.messageID, channelID: editState.channelID, authorID: currentUserID ?? MockShellData.currentUserID), content: editState.draftContent)
        do {
            let edited = try await messageActionHandler.editMessage(
                channelID: editState.channelID,
                messageID: editState.messageID,
                content: editState.draftContent
            )
            messageController.applyEditedMessage(edited)
            reconcileTimelineSelection(replacementHint: edited.id)
            timelineViewport = viewportReducer.keepVisible(timelineViewport, messageID: edited.id, reason: .editComplete)
            inlineEditState = nil
            self.editingDraft = nil
            messageActionStatus = nil
            requestFocus(.timeline)
        } catch {
            editState.isSaving = false
            editState.errorMessage = "Edit failed: \(error.userFacingMessage)"
            inlineEditState = editState
            messageActionStatus = editState.errorMessage
        }
    }

    public func cancelInlineEdit() {
        inlineEditState = nil
        editingDraft = nil
        requestFocus(.timeline)
    }

    public func updateInlineEditDraft(_ content: String) {
        guard var inlineEditState else { return }
        inlineEditState.draftContent = content
        inlineEditState.errorMessage = nil
        self.inlineEditState = inlineEditState
        if let editingDraft, editingDraft.id == inlineEditState.messageID {
            self.editingDraft = EditingMessageDraft(message: editingDraft.message, content: content)
        }
    }

    public func requestDelete(_ timelineMessage: TimelineMessage) {
        if case .failed = timelineMessage.status {
            discardFailedMessage(timelineMessage)
            return
        }
        guard canDelete(timelineMessage) else { return }
        pendingDeletion = timelineMessage
    }

    public func confirmPendingDelete() async {
        guard let pendingDeletion else { return }
        guard pendingDeletion.status == .confirmed else {
            self.pendingDeletion = nil
            return
        }
        do {
            try await messageActionHandler.deleteMessage(channelID: pendingDeletion.message.channelID, messageID: pendingDeletion.message.id)
            messageController.removeMessage(channelID: pendingDeletion.message.channelID, messageID: pendingDeletion.message.id)
            reconcileTimelineSelection(deletedHint: pendingDeletion.message.id)
            self.pendingDeletion = nil
            messageActionStatus = nil
        } catch {
            messageActionStatus = "Delete failed: \(error.userFacingMessage)"
        }
    }

    public func discardFailedMessage(_ timelineMessage: TimelineMessage) {
        guard case .failed = timelineMessage.status else { return }
        messageController.discardLocalMessage(timelineMessage)
        reconcileTimelineSelection(deletedHint: timelineMessage.message.id)
        messageActionStatus = "Failed message discarded"
    }

    public func editAndRetry(_ timelineMessage: TimelineMessage) {
        guard case .failed = timelineMessage.status else { return }
        let content = timelineMessage.message.content ?? ""
        inlineEditState = InlineEditState(
            channelID: timelineMessage.message.channelID,
            messageID: timelineMessage.message.id,
            originalContent: "",
            draftContent: content
        )
        editingDraft = EditingMessageDraft(message: timelineMessage.message, content: content)
        timelineSelection = TimelineSelection(channelID: timelineMessage.message.channelID, messageID: timelineMessage.message.id, source: .keyboard, mode: .failedRecovery)
        timelineViewport = viewportReducer.keepVisible(timelineViewport, messageID: timelineMessage.message.id, reason: .retrySend)
        requestFocus(.inlineEdit)
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

    public func togglePin(_ timelineMessage: TimelineMessage) async {
        guard canPin(timelineMessage) else {
            placeholderStatus = "Selected message cannot be pinned."
            return
        }
        let shouldPin = !timelineMessage.message.isPinned
        do {
            if shouldPin {
                try await messageActionHandler.pinMessage(channelID: timelineMessage.message.channelID, messageID: timelineMessage.message.id)
            } else {
                try await messageActionHandler.unpinMessage(channelID: timelineMessage.message.channelID, messageID: timelineMessage.message.id)
            }
            messageController.applyPinState(channelID: timelineMessage.message.channelID, messageID: timelineMessage.message.id, isPinned: shouldPin)
            messageActionStatus = shouldPin ? "Message pinned" : "Message unpinned"
        } catch {
            messageActionStatus = "Pin action failed: \(error.userFacingMessage)"
        }
    }

    public func copyMessage(_ message: Message) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Self.copyableContent(for: message), forType: .string)
        #endif
    }

    public func copyMessageID(_ message: Message) {
        guard isDeveloperControlsEnabled else {
            placeholderStatus = "Developer message ID copy is disabled."
            return
        }
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.id.rawValue, forType: .string)
        #endif
        messageActionStatus = "Message ID copied"
    }

    public static func copyableContent(for message: Message) -> String {
        if let content = message.content, !content.isEmpty { return content }
        if let system = message.system?.content, !system.isEmpty { return system }
        return ""
    }

    public static func replyPreviewText(for message: Message, maxLength: Int = 96) -> String {
        let raw = copyableContent(for: message).trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = raw.isEmpty ? "Message" : raw
        guard fallback.count > maxLength else { return fallback }
        return String(fallback.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    public var isDeveloperControlsEnabled: Bool {
        sessionCoordinator?.preferences.showDeveloperRuntimeControls ?? true
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
        if let local = localReadStates[channelID], local.unreadCount == 0 {
            guard local.mentionCount > 0,
                  let original = snapshot.unreadsByChannelID[channelID]
            else { return nil }
            return ChannelUnread(id: original.id, lastMessageID: nil, mentions: original.mentions)
        }
        guard let unread = snapshot.unreadsByChannelID[channelID] else { return nil }
        if locallyClearedUnreadChannelIDs.contains(channelID) || selection.channelID == channelID || selection.dmChannelID == channelID {
            if unread.mentions.isEmpty {
                return nil
            }
            return ChannelUnread(id: unread.id, lastMessageID: nil, mentions: unread.mentions)
        }
        return unread
    }

    public func firstUnreadMessageID(for channelID: ChannelID?) -> MessageID? {
        guard let channelID else { return nil }
        if let local = localReadStates[channelID]?.firstUnreadMessageID {
            return local
        }
        return snapshot.unreadsByChannelID[channelID]?.lastMessageID
    }

    public func requestFocus(_ target: ShellFocusTarget?) {
        if focusTarget != target {
            previousFocusTarget = focusTarget
        }
        focusTarget = target
    }

    public func selectNextServer() {
        guard let server = navigationHelper.adjacentServer(from: selection.serverID, direction: 1, snapshot: snapshot) else {
            placeholderStatus = "No next server."
            return
        }
        selectServer(server.id)
    }

    public func selectPreviousServer() {
        guard let server = navigationHelper.adjacentServer(from: selection.serverID, direction: -1, snapshot: snapshot) else {
            placeholderStatus = "No previous server."
            return
        }
        selectServer(server.id)
    }

    public func selectNextChannel() {
        guard let channel = navigationHelper.adjacentChannel(from: selection.channelID, serverID: selection.serverID, direction: 1, snapshot: snapshot) else {
            placeholderStatus = "No next channel."
            return
        }
        selectChannel(channel.id)
    }

    public func selectPreviousChannel() {
        guard let channel = navigationHelper.adjacentChannel(from: selection.channelID, serverID: selection.serverID, direction: -1, snapshot: snapshot) else {
            placeholderStatus = "No previous channel."
            return
        }
        selectChannel(channel.id)
    }

    public func selectNextUnreadChannel() {
        guard let channel = navigationHelper.adjacentUnreadChannel(from: selection.channelID, serverID: selection.serverID, direction: 1, snapshot: snapshot, unreadProvider: unread(for:)) else {
            placeholderStatus = "No next unread channel."
            return
        }
        selectChannel(channel.id)
    }

    public func selectPreviousUnreadChannel() {
        guard let channel = navigationHelper.adjacentUnreadChannel(from: selection.channelID, serverID: selection.serverID, direction: -1, snapshot: snapshot, unreadProvider: unread(for:)) else {
            placeholderStatus = "No previous unread channel."
            return
        }
        selectChannel(channel.id)
    }

    public func selectNextMessage() {
        selectAdjacentMessage(direction: 1)
    }

    public func selectPreviousMessage() {
        selectAdjacentMessage(direction: -1)
    }

    public func jumpToNewestMessage() {
        guard let newest = selectedTimelineMessages.last else {
            placeholderStatus = "No message to select."
            return
        }
        timelineSelection = TimelineSelection(channelID: newest.message.channelID, messageID: newest.message.id, source: .scrollJump)
        timelineViewport = viewportReducer.jumpNewest(timelineViewport, newestMessageID: newest.message.id)
        requestFocus(.timeline)
        acknowledgeSelectedChannel()
    }

    public func jumpToFirstUnreadMessage() {
        let activeChannelID = selection.channelID ?? selection.dmChannelID
        guard let activeChannelID else {
            placeholderStatus = "Select a channel before jumping to unread messages."
            return
        }
        guard let unreadID = firstUnreadMessageID(for: activeChannelID),
              selectedTimelineMessages.contains(where: { $0.message.id == unreadID })
        else {
            placeholderStatus = firstUnreadMessageID(for: activeChannelID) == nil ? "No unread marker in this channel." : "Unread message is not loaded."
            return
        }
        timelineSelection = TimelineSelection(channelID: activeChannelID, messageID: unreadID, source: .scrollJump)
        timelineViewport = viewportReducer.jumpFirstUnread(timelineViewport, unreadMessageID: unreadID, loadedMessageIDs: Set(selectedTimelineMessages.map(\.message.id)))
        requestFocus(.timeline)
    }

    public var selectedTimelineMessage: TimelineMessage? {
        guard let messageID = timelineSelection.messageID else { return nil }
        return selectedTimelineMessages.first { $0.message.id == messageID }
    }

    public func clearTimelineSelection() {
        timelineSelection = TimelineSelection()
    }

    public func updateViewportForSelectedChannel() {
        let channelID = selection.channelID ?? selection.dmChannelID
        timelineViewport = viewportReducer.channelSelected(
            channelID: channelID,
            messages: selectedTimelineMessages,
            firstUnreadMessageID: channelID.flatMap { firstUnreadMessageID(for: $0) }
        )
    }

    public func consumeScrollIntent() {
        timelineViewport.pendingScrollIntent = nil
    }

    public func updateTimelineAtNewest(_ isAtNewest: Bool) {
        timelineViewport.isAtNewest = isAtNewest
        if isAtNewest {
            timelineViewport.hasNewerMessagesIndicator = false
            if let channelID = selection.channelID ?? selection.dmChannelID {
                acknowledgeSelectedChannel()
                scheduleLiveAckIfNeeded(channelID: channelID)
            }
        }
    }

    public func reconcileTimelineSelection(deletedHint: MessageID? = nil, replacementHint: MessageID? = nil) {
        let activeChannelID = selection.channelID ?? selection.dmChannelID
        guard timelineSelection.channelID == activeChannelID,
              let selectedID = timelineSelection.messageID
        else {
            clearTimelineSelection()
            return
        }
        let messages = selectedTimelineMessages
        if let replacementHint, messages.contains(where: { $0.message.id == replacementHint }) {
            timelineSelection = TimelineSelection(channelID: activeChannelID, messageID: replacementHint)
            return
        }
        guard !messages.contains(where: { $0.message.id == selectedID }) else { return }
        let fallback: TimelineMessage?
        if let deletedHint, let deletedDate = Message.dateFromULID(deletedHint.rawValue) {
            fallback = messages.last { ($0.message.createdAt ?? .distantPast) <= deletedDate } ?? messages.first
        } else {
            fallback = messages.last
        }
        timelineSelection = TimelineSelection(channelID: activeChannelID, messageID: fallback?.message.id, source: .realtimeFallback)
        if let messageID = fallback?.message.id {
            timelineViewport = viewportReducer.keepVisible(timelineViewport, messageID: messageID, reason: .deleteFallback)
        }
    }

    public func copySelectedMessage() {
        guard let message = selectedTimelineMessage?.message else {
            placeholderStatus = "No selected message to copy."
            return
        }
        copyMessage(message)
        messageActionStatus = "Message copied"
    }

    public func copySelectedMessageID() {
        guard let message = selectedTimelineMessage?.message else {
            placeholderStatus = "No selected message to copy."
            return
        }
        copyMessageID(message)
    }

    public func editSelectedMessage() {
        guard let selectedTimelineMessage, canEdit(selectedTimelineMessage) else {
            placeholderStatus = "Selected message cannot be edited."
            return
        }
        beginEditing(selectedTimelineMessage)
    }

    public func deleteSelectedMessage() {
        guard let selectedTimelineMessage, canDelete(selectedTimelineMessage) else {
            placeholderStatus = "Selected message cannot be deleted."
            return
        }
        requestDelete(selectedTimelineMessage)
    }

    public func reactToSelectedMessage(_ emoji: String) {
        guard let selectedTimelineMessage, canReact(to: selectedTimelineMessage.message) else {
            placeholderStatus = "Selected message cannot be reacted to."
            return
        }
        Task { [weak self] in
            await self?.toggleReaction(emoji, on: selectedTimelineMessage)
        }
    }

    public func retrySelectedMessage() {
        guard let selectedTimelineMessage else {
            placeholderStatus = "No selected message to retry."
            return
        }
        if case .failed = selectedTimelineMessage.status {
            Task { [weak self] in
                await self?.retry(selectedTimelineMessage)
            }
        } else {
            placeholderStatus = "Selected message does not need retry."
        }
    }

    public func discardSelectedFailedMessage() {
        guard let selectedTimelineMessage else {
            placeholderStatus = "No selected message to discard."
            return
        }
        guard case .failed = selectedTimelineMessage.status else {
            placeholderStatus = "Selected message is not failed."
            return
        }
        discardFailedMessage(selectedTimelineMessage)
    }

    public func editAndRetrySelectedFailedMessage() {
        guard let selectedTimelineMessage else {
            placeholderStatus = "No selected message to edit and retry."
            return
        }
        editAndRetry(selectedTimelineMessage)
    }

    public func pinOrUnpinSelectedMessage() {
        guard let selectedTimelineMessage else {
            placeholderStatus = "No selected message to pin."
            return
        }
        Task { [weak self] in
            await self?.togglePin(selectedTimelineMessage)
        }
    }

    private func selectAdjacentMessage(direction: Int) {
        let messages = selectedTimelineMessages
        guard !messages.isEmpty else {
            placeholderStatus = "No message to select."
            return
        }
        let activeChannelID = selection.channelID ?? selection.dmChannelID
        let nextIndex: Int
        if let selectedID = timelineSelection.messageID,
           let currentIndex = messages.firstIndex(where: { $0.message.id == selectedID }) {
            nextIndex = currentIndex + (direction >= 0 ? 1 : -1)
        } else {
            nextIndex = direction >= 0 ? 0 : messages.count - 1
        }
        guard messages.indices.contains(nextIndex) else {
            placeholderStatus = direction >= 0 ? "No next message." : "No previous message."
            return
        }
        timelineSelection = TimelineSelection(channelID: activeChannelID, messageID: messages[nextIndex].message.id)
        requestFocus(.timeline)
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
        let oldSnapshot = self.snapshot
        self.snapshot = snapshot
        messageController.hydrate(from: snapshot)
        applyRealtimeDeleteDiff(previous: oldSnapshot, current: snapshot)
        previousSnapshot = snapshot
        restoreOrValidateSelection()
        acknowledgeSelectedChannel()
        scheduleSelectedChannelLoad()
        reconcileTimelineSelection()
        quickSwitcherViewModel.update(snapshot: snapshot, selection: selection)
    }

    private func applyRealtimeDeleteDiff(previous: RealtimeSnapshot, current: RealtimeSnapshot) {
        for (channelID, oldMessages) in previous.messagesByChannelID {
            let currentIDs = Set((current.messagesByChannelID[channelID] ?? []).map(\.id))
            for message in oldMessages where !currentIDs.contains(message.id) {
                messageController.removeMessage(channelID: channelID, messageID: message.id)
            }
        }
    }

    private func restoreOrValidateSelection() {
        guard let coordinator = sessionCoordinator,
              coordinator.mode == .liveManual,
              coordinator.hydrationStatus.readyReceived
        else {
            validateSelection()
            return
        }

        if restoredLiveConnectionGeneration != coordinator.liveConnectionGeneration {
            let result = selectionRestorer.restore(
                preferredSelection: selection,
                preferences: coordinator.preferences,
                snapshot: snapshot,
                mode: coordinator.mode
            )
            selection = result.selection
            placeholderStatus = result.message
            coordinator.updateHydrationSelectionAvailability(
                serverAvailable: result.selectedServerAvailable,
                channelAvailable: result.selectedChannelAvailable,
                warning: result.message
            )
            restoredLiveConnectionGeneration = coordinator.liveConnectionGeneration
            persistLiveSelectionIfNeeded()
        } else {
            validateSelection()
            let serverAvailable = selection.serverID.map { snapshot.serversByID[$0] != nil } ?? true
            let channelAvailable = selection.channelID.map { snapshot.channelsByID[$0] != nil } ?? true
            coordinator.updateHydrationSelectionAvailability(
                serverAvailable: serverAvailable,
                channelAvailable: channelAvailable,
                warning: channelAvailable ? nil : "Channel no longer exists"
            )
        }
    }

    private func persistLiveSelectionIfNeeded() {
        guard let coordinator = sessionCoordinator,
              coordinator.mode == .liveManual,
              coordinator.hydrationStatus.readyReceived
        else {
            return
        }
        let serverID = selection.serverID
        let channelID = selection.channelID
        guard serverID == nil || snapshot.serversByID[serverID!] != nil else { return }
        guard channelID == nil || snapshot.channelsByID[channelID!] != nil else { return }
        Task { [weak coordinator] in
            await coordinator?.updatePreferences { preferences in
                preferences.lastSelectedServerID = serverID
                preferences.lastSelectedChannelID = channelID
            }
        }
    }

    private func scheduleSelectedChannelLoad() {
        selectedChannelLoadTask?.cancel()
        guard let channelID = selection.channelID ?? selection.dmChannelID else { return }
        let snapshotMessages = snapshot.messagesByChannelID[channelID] ?? []
        selectedChannelLoadTask = Task { [weak self] in
            guard let self else { return }
            await self.messageController.loadInitialIfNeeded(channelID: channelID, snapshotMessages: snapshotMessages)
            if self.timelineViewport.channelID != channelID || self.timelineViewport.pendingScrollIntent == nil {
                self.updateViewportForSelectedChannel()
            }
        }
    }

    private func acknowledgeSelectedChannel() {
        guard let channelID = selection.channelID ?? selection.dmChannelID else { return }
        let unread = snapshot.unreadsByChannelID[channelID]
        let currentMessages = messageController.state(for: channelID).timelineMessages
        let firstUnread = localReadStates[channelID]?.firstUnreadMessageID ?? unread?.lastMessageID
        let newest = currentMessages.last?.message.id ?? unread?.lastMessageID
        localReadStates[channelID] = LocalReadState(
            channelID: channelID,
            firstUnreadMessageID: firstUnread,
            lastReadMessageID: newest,
            unreadCount: 0,
            mentionCount: unread?.mentions.count ?? localReadStates[channelID]?.mentionCount ?? 0
        )
        messageController.moveUnreadMarker(channelID: channelID, messageID: firstUnread)
        messageController.markRead(channelID: channelID, lastReadMessageID: newest)
        locallyClearedUnreadChannelIDs.insert(channelID)
        scheduleLiveAckIfNeeded(channelID: channelID)
    }

    private func scheduleLiveAckIfNeeded(channelID: ChannelID) {
        guard effectiveRuntimeMode == .liveManual,
              effectiveSessionState == .connected,
              timelineViewport.isAtNewest,
              let messageID = messageController.state(for: channelID).timelineMessages.last?.message.id ?? snapshot.unreadsByChannelID[channelID]?.lastMessageID,
              lastAckedMessageByChannelID[channelID] != messageID
        else {
            return
        }
        ackTask?.cancel()
        ackTask = Task { [weak self, sender = channelAckSender] in
            try? await Task.sleep(for: .milliseconds(1500))
            do {
                try await sender.ackChannel(channelID: channelID, messageID: messageID)
                await MainActor.run {
                    self?.lastAckedMessageByChannelID[channelID] = messageID
                    if var state = self?.localReadStates[channelID] {
                        state.mentionCount = 0
                        self?.localReadStates[channelID] = state
                    }
                }
            } catch {
                await MainActor.run {
                    self?.messageActionStatus = "Read acknowledgement failed: \(error.userFacingMessage)"
                }
            }
        }
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

extension MainShellViewModel: AppCommandHandling {
    public func canPerform(_ command: AppCommand) -> Bool {
        switch command {
        case .openQuickSwitcher, .closeTransientUI, .refresh, .openAccountSettings, .openConnectionSettings, .toggleMemberPanel, .jumpToHome, .jumpToDiscover, .focusTimeline:
            return true
        case .focusComposer:
            return selectedChannel != nil || selection.dmChannelID != nil
        case .reconnect:
            return sessionCoordinator?.hasSavedCredential == true && !isConnecting
        case .disconnect:
            return isDisconnectable
        case .resetToMock:
            return effectiveRuntimeMode != .mock || effectiveConnectionState != .idle
        case .toggleDeveloperControls:
            return sessionCoordinator != nil
        case let .selectServer(index):
            return navigationHelper.server(atOneBasedIndex: index, snapshot: snapshot) != nil
        case let .selectChannel(channelID):
            return snapshot.channelsByID[channelID].map(navigationHelper.isSelectable) == true
        case .selectNextServer:
            return navigationHelper.adjacentServer(from: selection.serverID, direction: 1, snapshot: snapshot) != nil
        case .selectPreviousServer:
            return navigationHelper.adjacentServer(from: selection.serverID, direction: -1, snapshot: snapshot) != nil
        case .selectNextChannel:
            return !isTextEntryFocused && navigationHelper.adjacentChannel(from: selection.channelID, serverID: selection.serverID, direction: 1, snapshot: snapshot) != nil
        case .selectPreviousChannel:
            return !isTextEntryFocused && navigationHelper.adjacentChannel(from: selection.channelID, serverID: selection.serverID, direction: -1, snapshot: snapshot) != nil
        case .selectNextUnreadChannel:
            return !isTextEntryFocused && navigationHelper.adjacentUnreadChannel(from: selection.channelID, serverID: selection.serverID, direction: 1, snapshot: snapshot, unreadProvider: unread(for:)) != nil
        case .selectPreviousUnreadChannel:
            return !isTextEntryFocused && navigationHelper.adjacentUnreadChannel(from: selection.channelID, serverID: selection.serverID, direction: -1, snapshot: snapshot, unreadProvider: unread(for:)) != nil
        case .selectNextMessage, .selectPreviousMessage, .jumpToNewestMessage:
            return !isTextEntryFocused && !selectedTimelineMessages.isEmpty
        case .jumpToFirstUnreadMessage:
            guard let channelID = selection.channelID ?? selection.dmChannelID else { return false }
            return !isTextEntryFocused && firstUnreadMessageID(for: channelID) != nil
        case .replyToSelectedMessage:
            return !isTextEntryFocused && selectedTimelineMessage.map { canReply(to: $0) } == true
        case .cancelReply:
            return replyContext(for: selection.channelID ?? selection.dmChannelID) != nil
        case .copySelectedMessage:
            return !isTextEntryFocused && selectedTimelineMessage != nil
        case .copySelectedMessageID:
            return !isTextEntryFocused && isDeveloperControlsEnabled && selectedTimelineMessage != nil
        case .editSelectedMessage:
            return !isTextEntryFocused && selectedTimelineMessage.map { canEdit($0) } == true
        case .deleteSelectedMessage:
            return !isTextEntryFocused && selectedTimelineMessage.map { canDelete($0) } == true
        case let .reactToSelectedMessage(emoji):
            return !isTextEntryFocused && !emoji.isEmpty && selectedTimelineMessage.map { canReact(to: $0.message) } == true
        case .retrySelectedMessage:
            guard let selectedTimelineMessage else { return false }
            if case .failed = selectedTimelineMessage.status { return !isTextEntryFocused }
            return false
        case .discardSelectedFailedMessage, .editAndRetrySelectedFailedMessage:
            guard let selectedTimelineMessage else { return false }
            if case .failed = selectedTimelineMessage.status { return !isTextEntryFocused }
            return false
        case .pinOrUnpinSelectedMessage:
            return !isTextEntryFocused && selectedTimelineMessage.map { canPin($0) } == true
        }
    }

    public func disabledReason(for command: AppCommand) -> String? {
        guard !canPerform(command) else { return nil }
        switch command {
        case .focusComposer:
            return "Select a channel before focusing the composer."
        case .reconnect:
            return sessionCoordinator?.hasSavedCredential == true ? "Realtime is already connecting." : "No saved credential for this environment."
        case .disconnect:
            return "No live realtime session is connected."
        case .resetToMock:
            return "Already using mock runtime."
        case .selectServer:
            return "That server shortcut has no visible server."
        case .selectChannel:
            return "That channel is unavailable."
        case .selectNextChannel, .selectPreviousChannel, .selectNextUnreadChannel, .selectPreviousUnreadChannel, .selectNextMessage, .selectPreviousMessage, .jumpToNewestMessage, .jumpToFirstUnreadMessage:
            return isTextEntryFocused ? "Keyboard navigation is paused while typing." : "No selectable target."
        case .copySelectedMessage, .copySelectedMessageID, .editSelectedMessage, .deleteSelectedMessage, .reactToSelectedMessage, .retrySelectedMessage, .discardSelectedFailedMessage, .editAndRetrySelectedFailedMessage, .pinOrUnpinSelectedMessage, .replyToSelectedMessage:
            if isTextEntryFocused { return "Message actions are paused while typing." }
            if command == .copySelectedMessageID && !isDeveloperControlsEnabled { return "Developer controls are disabled." }
            return "No compatible message is selected."
        case .cancelReply:
            return "No reply is active."
        default:
            return "Unavailable."
        }
    }

    public func perform(_ command: AppCommand) {
        guard canPerform(command) || command == .closeTransientUI else {
            placeholderStatus = disabledReason(for: command)
            return
        }
        switch command {
        case .openQuickSwitcher:
            showQuickSwitcher()
        case .focusComposer:
            focusComposer()
        case .focusTimeline:
            requestFocus(.timeline)
        case .refresh:
            refreshCurrentContext()
        case .reconnect:
            Task { [weak self] in await self?.reconnectLiveManually() }
        case .disconnect:
            Task { [weak self] in await self?.disconnectLive() }
        case .resetToMock:
            Task { [weak self] in await self?.resetToMock() }
        case .openAccountSettings:
            showAccountSessions()
        case .openConnectionSettings:
            showConnectionSettings()
        case .toggleMemberPanel:
            toggleMemberPanel()
        case .toggleDeveloperControls:
            Task { [weak self] in
                guard let self else { return }
                await self.sessionCoordinator?.updatePreferences { preferences in
                    preferences.showDeveloperRuntimeControls.toggle()
                }
                self.syncFromSessionCoordinator()
            }
        case let .selectServer(index):
            selectServer(atOneBasedIndex: index)
        case let .selectChannel(channelID):
            selectChannel(channelID)
        case .selectNextServer:
            selectNextServer()
        case .selectPreviousServer:
            selectPreviousServer()
        case .selectNextChannel:
            selectNextChannel()
        case .selectPreviousChannel:
            selectPreviousChannel()
        case .selectNextUnreadChannel:
            selectNextUnreadChannel()
        case .selectPreviousUnreadChannel:
            selectPreviousUnreadChannel()
        case .jumpToHome:
            selectHome()
        case .jumpToDiscover:
            selectDiscover()
        case .selectNextMessage:
            selectNextMessage()
        case .selectPreviousMessage:
            selectPreviousMessage()
        case .jumpToNewestMessage:
            jumpToNewestMessage()
        case .jumpToFirstUnreadMessage:
            jumpToFirstUnreadMessage()
        case .replyToSelectedMessage:
            if let selectedTimelineMessage {
                beginReply(to: selectedTimelineMessage)
            }
        case .cancelReply:
            cancelReply(for: selection.channelID ?? selection.dmChannelID)
        case .copySelectedMessage:
            copySelectedMessage()
        case .copySelectedMessageID:
            copySelectedMessageID()
        case .editSelectedMessage:
            editSelectedMessage()
        case .deleteSelectedMessage:
            deleteSelectedMessage()
        case let .reactToSelectedMessage(emoji):
            reactToSelectedMessage(emoji)
        case .retrySelectedMessage:
            retrySelectedMessage()
        case .discardSelectedFailedMessage:
            discardSelectedFailedMessage()
        case .editAndRetrySelectedFailedMessage:
            editAndRetrySelectedFailedMessage()
        case .pinOrUnpinSelectedMessage:
            pinOrUnpinSelectedMessage()
        case .closeTransientUI:
            if isQuickSwitcherPresented {
                closeQuickSwitcher()
            } else if inlineEditState != nil {
                cancelInlineEdit()
            } else {
                requestFocus(nil)
            }
        }
    }

    private var isTextEntryFocused: Bool {
        focusTarget == .composer || focusTarget == .quickSwitcher || focusTarget == .inlineEdit
    }

    private var isDisconnectable: Bool {
        switch effectiveConnectionState {
        case .connecting, .connected, .authenticating, .authenticated, .ready, .reconnecting:
            return true
        case .idle, .disconnected, .failed:
            return false
        }
    }

    private var isConnecting: Bool {
        switch effectiveConnectionState {
        case .connecting, .connected, .authenticating, .authenticated, .reconnecting:
            return true
        case .idle, .ready, .disconnected, .failed:
            return false
        }
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
            QuickSwitcherView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.isCredentialSetupPresented) {
            AccountConnectionSettingsView(viewModel: viewModel)
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
        .focusedSceneValue(\.appCommandHandler, viewModel)
        .onExitCommand {
            viewModel.perform(.closeTransientUI)
        }
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
                Button { viewModel.perform(.openQuickSwitcher) } label: { Label("Quick Switcher", systemImage: "magnifyingglass") }
                Button { viewModel.perform(.toggleMemberPanel) } label: { Label("Toggle Members", systemImage: "sidebar.right") }
                Button { viewModel.perform(.openAccountSettings) } label: { Label("Settings", systemImage: "gearshape") }
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
            LabeledContent("Health", value: Phase6UIHelpers.connectionHealthText(state: viewModel.effectiveConnectionState, diagnostics: viewModel.effectiveDiagnostics, hydration: viewModel.sessionCoordinator?.hydrationStatus ?? .empty))
            if let latency = viewModel.effectiveDiagnostics?.lastLatencyMilliseconds {
                LabeledContent("Latency", value: "\(latency) ms")
            }
            if let ready = viewModel.effectiveDiagnostics?.readyAt {
                LabeledContent("Last Ready", value: ready.formatted(date: .omitted, time: .standard))
            }
            if let lastEvent = viewModel.effectiveDiagnostics?.lastReceivedEventAt {
                LabeledContent("Last Event", value: lastEvent.formatted(date: .omitted, time: .standard))
            }
            if let hydration = viewModel.sessionCoordinator?.hydrationStatus {
                LabeledContent("Hydration", value: Phase6UIHelpers.hydrationLabel(hydration))
            }
            if let session = viewModel.sessionCoordinator {
                LabeledContent("Credential", value: session.hasSavedCredential ? "Saved" : "Missing")
                LabeledContent("Environment", value: Phase6UIHelpers.environmentDisplayName(session.environment, preferences: session.preferences))
                if let user = session.currentUser {
                    LabeledContent("Current User", value: user.displayName ?? user.username)
                }
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
            Button("Reconnect") {
                Task { await viewModel.reconnectLiveManually() }
            }
            .disabled(viewModel.sessionCoordinator?.hasSavedCredential != true || isConnecting)
            Button("Refresh Selected Channel") {
                viewModel.refreshCurrentContext()
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
        .accessibilityLabel(StoatAccessibility.runtimeLabel(
            mode: runtimeModeText,
            connection: connectionText,
            health: Phase6UIHelpers.connectionHealthText(
                state: viewModel.effectiveConnectionState,
                diagnostics: viewModel.effectiveDiagnostics,
                hydration: viewModel.sessionCoordinator?.hydrationStatus ?? .empty
            )
        ))
        .accessibilityHint("Open runtime and connection actions")
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

    private var isConnecting: Bool {
        switch viewModel.effectiveConnectionState {
        case .connecting, .connected, .authenticating, .authenticated, .reconnecting:
            return true
        case .idle, .ready, .disconnected, .failed:
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
                    Button("Reconnect") {
                        Task { await viewModel.reconnectLiveManually() }
                    }
                    .disabled(viewModel.sessionCoordinator?.hasSavedCredential != true || isConnecting)
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
                        viewModel.refreshCurrentContext()
                    }
                    Button("Reconnect") {
                        Task { await viewModel.reconnectLiveManually() }
                    }
                    .disabled(viewModel.sessionCoordinator?.hasSavedCredential != true || isConnecting)
                    Button("Send Composer Text") {
                        viewModel.isTestSendConfirmationPresented = true
                    }
                    .disabled(!viewModel.composerReadiness(for: viewModel.selection.channelID ?? viewModel.selection.dmChannelID).canSend)
                }
            }

            Section("Safe Diagnostics") {
                LabeledContent("Credential", value: viewModel.sessionCoordinator?.hasSavedCredential == true ? "Saved" : "Missing")
                if let coordinator = viewModel.sessionCoordinator {
                    LabeledContent("Environment", value: Phase6UIHelpers.environmentDisplayName(coordinator.environment, preferences: coordinator.preferences))
                    LabeledContent("Environment ID", value: coordinator.environment.stableID)
                    LabeledContent("Health", value: Phase6UIHelpers.connectionHealthText(state: coordinator.connectionState, diagnostics: coordinator.diagnostics, hydration: coordinator.hydrationStatus))
                    LabeledContent("Hydration", value: Phase6UIHelpers.hydrationLabel(coordinator.hydrationStatus))
                    LabeledContent("Servers", value: "\(coordinator.hydrationStatus.serverCount)")
                    LabeledContent("Channels", value: "\(coordinator.hydrationStatus.channelCount)")
                    LabeledContent("Unreads", value: "\(coordinator.hydrationStatus.unreadCount)")
                    LabeledContent("Ready received", value: coordinator.hydrationStatus.readyReceived ? "Yes" : "No")
                    LabeledContent("Selected server", value: coordinator.hydrationStatus.selectedServerAvailable ? "Available" : "Unavailable")
                    LabeledContent("Selected channel", value: coordinator.hydrationStatus.selectedChannelAvailable ? "Available" : "Unavailable")
                    if let hydrated = coordinator.hydrationStatus.lastHydratedAt {
                        LabeledContent("Last Ready", value: hydrated.formatted(date: .abbreviated, time: .standard))
                    }
                    if case let .reconnecting(attempt, delay) = coordinator.connectionState {
                        LabeledContent("Reconnect attempt", value: "\(attempt)")
                        LabeledContent("Next retry", value: "\(Int(Self.seconds(delay).rounded()))s")
                    }
                }
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

    private var isConnecting: Bool {
        switch viewModel.effectiveConnectionState {
        case .connecting, .connected, .authenticating, .authenticated, .reconnecting:
            true
        case .idle, .ready, .disconnected, .failed:
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

    private static func seconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
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
                    let channels = viewModel.channels(for: serverID)
                    if channels.isEmpty {
                        Text("No text channels available")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, StoatSpacing.medium)
                    } else {
                        ForEach(channels) { channel in
                            channelRow(channel)
                        }
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
                let draftState = viewModel.composerDraftState(for: channel.id)
                GlassComposer(
                    text: Binding(
                        get: { viewModel.draft(for: channel.id) },
                        set: { viewModel.updateDraft($0, for: channel.id) }
                    ),
                    shouldMentionReplyAuthor: Binding(
                        get: { viewModel.composerDraftState(for: channel.id).shouldMentionReplyAuthor },
                        set: { viewModel.updateReplyMentionPreference($0, for: channel.id) }
                    ),
                    placeholder: inputReadiness.isEnabled ? "Message #\(channel.displayName)" : inputReadiness.reason,
                    isEnabled: inputReadiness.isEnabled,
                    canSend: sendReadiness.canSend,
                    disabledReason: sendReadiness.canSend ? nil : sendReadiness.reason,
                    isSending: viewModel.messageController.sendingChannelIDs.contains(channel.id),
                    canAttach: viewModel.canUploadFiles(in: channel),
                    replyAuthor: draftState.replyContext?.authorDisplayName,
                    replyPreview: draftState.replyContext?.contentPreview,
                    focusRequestID: viewModel.composerFocusRequestID,
                    onCancelReply: {
                        viewModel.cancelReply(for: channel.id)
                    },
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(viewModel: MainShellViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: viewModel.messageDensity == .compact ? StoatSpacing.small : StoatSpacing.medium) {
                    if viewModel.selectedChannel == nil {
                        EmptyStateView(title: emptyTitle, message: emptyMessage)
                            .frame(maxWidth: .infinity)
                    } else {
                        timelineContent
                    }
                }
                .padding(StoatSpacing.xLarge)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: viewModel.timelineViewport.pendingScrollIntent) { _, intent in
                guard let intent else { return }
                performScroll(intent, proxy: proxy)
                viewModel.consumeScrollIntent()
            }
        }
    }

    private func performScroll(_ intent: TimelineScrollIntent, proxy: ScrollViewProxy) {
        let target: MessageID?
        let anchor: UnitPoint?
        switch intent {
        case let .message(id, scrollAnchor, _):
            target = id
            anchor = unitPoint(for: scrollAnchor)
        case .newest:
            target = viewModel.selectedTimelineMessages.last?.message.id
            anchor = .bottom
        case let .firstUnread(id):
            target = id
            anchor = .center
        case let .preservePositionAfterPrepend(previousOldestID):
            target = previousOldestID
            anchor = .top
        }
        guard let target else { return }
        let scroll = { proxy.scrollTo(target, anchor: anchor) }
        if reduceMotion {
            scroll()
        } else {
            withAnimation(.easeInOut(duration: 0.18), scroll)
        }
    }

    private func unitPoint(for anchor: TimelineScrollAnchor) -> UnitPoint? {
        switch anchor {
        case .top: .top
        case .center: .center
        case .bottom: .bottom
        case .nearest: nil
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

    private var emptyTitle: String {
        if viewModel.effectiveRuntimeMode == .liveManual,
           viewModel.sessionCoordinator?.hydrationStatus.readyReceived != true {
            return "Waiting for realtime data"
        }
        if viewModel.effectiveRuntimeMode == .liveManual,
           viewModel.snapshot.serversByID.isEmpty {
            return "No servers available"
        }
        if viewModel.selection.serverID != nil {
            return "No text channels available"
        }
        return "Choose a channel"
    }

    private var emptyMessage: String {
        if viewModel.effectiveRuntimeMode == .liveManual,
           viewModel.effectiveConnectionState != .ready {
            return "Reconnect to refresh live state."
        }
        if viewModel.selection.serverID != nil {
            return "This server has no visible text channels in the current live snapshot."
        }
        return "Pick a server channel or DM to open the timeline."
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
        newestIndicator
        typingIndicator
    }

    @ViewBuilder private var newestIndicator: some View {
        if viewModel.timelineViewport.hasNewerMessagesIndicator {
            Button {
                viewModel.jumpToNewestMessage()
            } label: {
                Label("Jump to Newest", systemImage: "arrow.down.to.line")
            }
            .buttonStyle(GlassButtonStyle())
            .frame(maxWidth: .infinity)
            .accessibilityLabel(StoatAccessibility.jumpNewestLabel(hasNewMessages: true))
            .accessibilityHint("Scrolls to the newest loaded message and marks this channel read locally")
        }
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
           viewModel.firstUnreadMessageID(for: channelID) != nil {
            HStack {
                Rectangle().frame(height: 1).foregroundStyle(Color.red.opacity(0.5))
                Text("Unread")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                Rectangle().frame(height: 1).foregroundStyle(Color.red.opacity(0.5))
            }
            .accessibilityLabel("Unread messages separator")
            .accessibilityHint("Jump to first unread message")
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
                    if viewModel.inlineEditState?.messageID == timelineMessage.message.id {
                        InlineMessageEditor(viewModel: viewModel)
                            .padding(.leading, index == 0 ? 0 : StoatSize.avatar + StoatSpacing.medium)
                    } else {
                        MessageRow(
                            message: timelineMessage.message,
                            author: author,
                            showsHeader: index == 0,
                            statusText: accessibilityStatus(for: timelineMessage),
                            isSelected: viewModel.timelineSelection.messageID == timelineMessage.message.id,
                            isFocused: viewModel.timelineSelection.focus.messageID == timelineMessage.message.id && viewModel.timelineSelection.focus.mode != .none,
                            replyPreview: replyPreview(for: timelineMessage.message)
                        )
                        .id(timelineMessage.message.id)
                        .onAppear {
                            if timelineMessage.message.id == viewModel.selectedTimelineMessages.last?.message.id {
                                viewModel.updateTimelineAtNewest(true)
                            }
                        }
                        .onDisappear {
                            if timelineMessage.message.id == viewModel.selectedTimelineMessages.last?.message.id {
                                viewModel.updateTimelineAtNewest(false)
                            }
                        }
                        .onTapGesture {
                            select(timelineMessage)
                        }
                            .contextMenu {
                                Button("Copy Message") {
                                    select(timelineMessage)
                                    viewModel.perform(.copySelectedMessage)
                                }
                                if viewModel.isDeveloperControlsEnabled {
                                    Button("Copy Message ID") {
                                        select(timelineMessage)
                                        viewModel.perform(.copySelectedMessageID)
                                    }
                                }
                                if viewModel.canEdit(timelineMessage) {
                                    Button("Edit Message") {
                                        select(timelineMessage)
                                        viewModel.perform(.editSelectedMessage)
                                    }
                                }
                                if viewModel.canReply(to: timelineMessage) {
                                    Button("Reply") {
                                        select(timelineMessage, source: .contextMenu)
                                        viewModel.perform(.replyToSelectedMessage)
                                    }
                                }
                                if viewModel.canDelete(timelineMessage) {
                                    Button(timelineMessage.status == .confirmed ? "Delete Message" : "Discard Failed Message", role: .destructive) {
                                        select(timelineMessage)
                                        viewModel.perform(timelineMessage.status == .confirmed ? .deleteSelectedMessage : .discardSelectedFailedMessage)
                                    }
                                }
                                if case .failed = timelineMessage.status {
                                    Button("Retry Send") {
                                        select(timelineMessage)
                                        viewModel.perform(.retrySelectedMessage)
                                    }
                                    Button("Edit & Retry") {
                                        select(timelineMessage)
                                        viewModel.perform(.editAndRetrySelectedFailedMessage)
                                    }
                                }
                                if viewModel.canPin(timelineMessage) {
                                    Button(timelineMessage.message.isPinned ? "Unpin Message" : "Pin Message") {
                                        select(timelineMessage)
                                        viewModel.perform(.pinOrUnpinSelectedMessage)
                                    }
                                }
                                if viewModel.canReact(to: timelineMessage.message) {
                                    Divider()
                                    ForEach(MessageQuickActions.quickReactions, id: \.self) { emoji in
                                        Button("React \(emoji)") {
                                            select(timelineMessage)
                                            viewModel.perform(.reactToSelectedMessage(emoji))
                                        }
                                    }
                                }
                            }
                    }
                    statusView(for: timelineMessage)
                }
            }
        }
        .id(group.id)
    }

    private func select(_ timelineMessage: TimelineMessage, source: MessageFocusSource = .mouse) {
        viewModel.timelineSelection = TimelineSelection(channelID: timelineMessage.message.channelID, messageID: timelineMessage.message.id, source: source)
        viewModel.requestFocus(.timeline)
    }

    private func replyPreview(for message: Message) -> String? {
        guard let replyID = message.replies?.first else { return nil }
        guard let referenced = viewModel.selectedTimelineMessages.first(where: { $0.message.id == replyID })?.message else {
            return "Original message unavailable"
        }
        let author = viewModel.snapshot.usersByID[referenced.authorID]
        let authorName = referenced.masquerade?.name ?? author?.displayName ?? author?.username ?? referenced.authorID.rawValue
        return "\(authorName): \(MainShellViewModel.replyPreviewText(for: referenced))"
    }

    @ViewBuilder private func statusView(for timelineMessage: TimelineMessage) -> some View {
        switch timelineMessage.status {
        case .confirmed:
            EmptyView()
        case .deleting:
            HStack(spacing: StoatSpacing.small) {
                ProgressView()
                    .controlSize(.small)
                Text("Deleting...")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, StoatSize.avatar + StoatSpacing.medium)
        case .pending:
            HStack(spacing: StoatSpacing.small) {
                ProgressView()
                    .controlSize(.small)
                Text("Sending...")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, StoatSize.avatar + StoatSpacing.medium)
            .accessibilityLabel("Message sending")
        case let .failed(message):
            HStack(spacing: StoatSpacing.small) {
                Text("Failed: \(message)")
                    .font(.caption2)
                    .foregroundStyle(.red)
                Button("Retry") {
                    Task { await viewModel.retry(timelineMessage) }
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(StoatAccessibility.failedMessageActionLabel(action: "Retry", error: message))
                Button("Edit & Retry") {
                    viewModel.editAndRetry(timelineMessage)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(StoatAccessibility.failedMessageActionLabel(action: "Edit and retry", error: message))
                Button("Discard") {
                    viewModel.discardFailedMessage(timelineMessage)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(StoatAccessibility.failedMessageActionLabel(action: "Discard", error: message))
            }
            .padding(.leading, StoatSize.avatar + StoatSpacing.medium)
        }
    }

    private func accessibilityStatus(for timelineMessage: TimelineMessage) -> String? {
        switch timelineMessage.status {
        case .confirmed:
            return nil
        case .deleting:
            return "deleting"
        case .pending:
            return "sending"
        case .failed:
            return "failed to send"
        }
    }
}

public struct InlineMessageEditor: View {
    @Bindable private var viewModel: MainShellViewModel

    public init(viewModel: MainShellViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        if let state = viewModel.inlineEditState {
            VStack(alignment: .leading, spacing: StoatSpacing.small) {
                TextEditor(text: Binding(
                    get: { viewModel.inlineEditState?.draftContent ?? "" },
                    set: { viewModel.updateInlineEditDraft($0) }
                ))
                .frame(minHeight: 70, maxHeight: 140)
                .padding(StoatSpacing.small)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: StoatRadius.control, style: .continuous))
                .accessibilityLabel(StoatAccessibility.inlineEditLabel(isSaving: state.isSaving, errorMessage: state.errorMessage))
                .accessibilityHint("Edit message content. Shift Return inserts a new line.")
                HStack(spacing: StoatSpacing.small) {
                    if state.isSaving {
                        ProgressView()
                            .controlSize(.small)
                    }
                    if let error = state.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }
                    Spacer()
                    Button("Cancel") {
                        viewModel.cancelInlineEdit()
                    }
                    .keyboardShortcut(.escape, modifiers: [])
                    Button("Save") {
                        Task { await viewModel.saveEditingDraft() }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(!state.canSave)
                }
            }
            .padding(StoatSpacing.medium)
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: StoatRadius.row, style: .continuous))
            .onAppear {
                viewModel.requestFocus(.inlineEdit)
            }
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
                            if let user = viewModel.currentUserID.flatMap({ viewModel.snapshot.usersByID[$0] }) ?? viewModel.currentUser {
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

public struct QuickSwitcherView: View {
    @Bindable private var viewModel: MainShellViewModel
    @FocusState private var searchFocused: Bool

    public init(viewModel: MainShellViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: StoatSpacing.small) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Jump to server, channel, or command", text: $viewModel.quickSwitcherViewModel.query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onSubmit { activateSelectedResult() }
            }
            .padding(StoatSpacing.large)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: StoatSpacing.xSmall) {
                    if viewModel.quickSwitcherViewModel.results.isEmpty {
                        EmptyStateView(title: "No local results", message: "Try a server, channel, or command name.", systemImage: "magnifyingglass")
                            .frame(maxWidth: .infinity)
                            .padding(StoatSpacing.xLarge)
                    } else {
                        ForEach(Array(viewModel.quickSwitcherViewModel.results.enumerated()), id: \.element.id) { index, result in
                            QuickSwitcherResultRow(
                                result: result,
                                isSelected: index == viewModel.quickSwitcherViewModel.selectedIndex
                            ) {
                                viewModel.quickSwitcherViewModel.selectedIndex = index
                                activate(result)
                            }
                        }
                    }
                }
                .padding(StoatSpacing.small)
            }
        }
        .frame(width: 520, height: 460)
        .onAppear {
            viewModel.quickSwitcherViewModel.update(snapshot: viewModel.snapshot, selection: viewModel.selection)
            searchFocused = true
        }
        .onMoveCommand { direction in
            switch direction {
            case .up:
                viewModel.quickSwitcherViewModel.moveSelection(-1)
            case .down:
                viewModel.quickSwitcherViewModel.moveSelection(1)
            default:
                break
            }
        }
        .onExitCommand {
            viewModel.perform(.closeTransientUI)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quick switcher")
    }

    private func activateSelectedResult() {
        guard let result = viewModel.quickSwitcherViewModel.selectedResult else { return }
        activate(result)
    }

    private func activate(_ result: QuickSwitcherResult) {
        guard let command = viewModel.quickSwitcherViewModel.command(for: result) else {
            viewModel.placeholderStatus = result.disabledReason ?? "Result is unavailable."
            return
        }
        viewModel.perform(command)
        viewModel.closeQuickSwitcher()
    }
}

private struct QuickSwitcherResultRow: View {
    let result: QuickSwitcherResult
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: StoatSpacing.medium) {
                Image(systemName: iconName)
                    .frame(width: 22)
                    .foregroundStyle(result.isEnabled ? .secondary : .tertiary)
                VStack(alignment: .leading, spacing: StoatSpacing.xxSmall) {
                    Text(result.title)
                        .font(.callout.weight(isSelected ? .semibold : .regular))
                        .lineLimit(1)
                    if let subtitle = subtitleText {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(subtitleColor)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if let badgeText = result.badgeText {
                    Text(badgeText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, StoatSpacing.small)
                        .padding(.vertical, StoatSpacing.xxSmall)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                }
            }
            .padding(.horizontal, StoatSpacing.medium)
            .frame(minHeight: 44)
            .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: StoatRadius.row, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!result.isEnabled)
        .accessibilityLabel(result.accessibilityLabel)
        .accessibilityValue(isSelected ? "Selected" : "")
        .accessibilityHint(result.isEnabled ? "Press Return to activate" : (result.disabledReason ?? "Unavailable"))
    }

    private var subtitleText: String? {
        result.disabledReason ?? result.subtitle
    }

    private var subtitleColor: Color {
        result.disabledReason == nil ? Color.secondary : Color.red
    }

    private var iconName: String {
        switch result.kind {
        case .server:
            return "circle.grid.2x2.fill"
        case .channel:
            return "number"
        case .directMessage:
            return "person"
        case .command:
            return "command"
        case .route(.home):
            return "house.fill"
        case .route(.discover):
            return "safari"
        case .route:
            return "arrow.turn.down.right"
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
#Preview("Quick Switcher") {
    let model = MainShellViewModel(snapshot: MockShellData.snapshot)
    model.showQuickSwitcher()
    return QuickSwitcherView(viewModel: model)
}

@available(macOS 15.0, *)
#Preview("Focused Composer") {
    let model = MainShellViewModel(snapshot: MockShellData.snapshot)
    model.selectServer(model.servers[0].id)
    model.focusComposer()
    return ChatPlaceholderView(viewModel: model)
        .frame(width: 760, height: 620)
}

@available(macOS 15.0, *)
#Preview("Selected Message") {
    let model = MainShellViewModel(snapshot: MockShellData.snapshot)
    model.selectServer(model.servers[0].id)
    model.jumpToNewestMessage()
    return MessageTimelineView(viewModel: model)
        .frame(width: 760, height: 520)
}

@available(macOS 15.0, *)
#Preview("Compact Density") {
    let model = MainShellViewModel(snapshot: MockShellData.snapshot)
    model.selectServer(model.servers[0].id)
    model.messageDensity = .compact
    return ChatPlaceholderView(viewModel: model)
        .frame(width: 760, height: 620)
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

@available(macOS 15.0, *)
#Preview("Live Manual - Ready To Connect") {
    MainShellView(viewModel: MainShellViewModel(snapshot: RealtimeSnapshot(), runtimeMode: .liveManual, sessionState: .readyToConnect, currentUser: nil))
        .frame(width: 1180, height: 760)
}

@available(macOS 15.0, *)
#Preview("Live Manual - Connecting") {
    MainShellView(viewModel: MainShellViewModel(snapshot: RealtimeSnapshot(), connectionState: .authenticating, runtimeMode: .liveManual, sessionState: .connecting, currentUser: nil))
        .frame(width: 1180, height: 760)
}

@available(macOS 15.0, *)
#Preview("Live Manual - Ready Snapshot") {
    MainShellView(viewModel: MainShellViewModel(
        selection: ShellSelection(space: .server("01HX0000000000000000000201"), serverID: "01HX0000000000000000000201", channelID: "01HX0000000000000000000101"),
        snapshot: MockShellData.snapshot,
        connectionState: .ready,
        runtimeMode: .liveManual,
        sessionState: .connected,
        currentUser: MockShellData.snapshot.usersByID[MockShellData.currentUserID]
    ))
    .frame(width: 1180, height: 760)
}

@available(macOS 15.0, *)
#Preview("Live Manual - No Servers") {
    MainShellView(viewModel: MainShellViewModel(snapshot: RealtimeSnapshot(), connectionState: .ready, runtimeMode: .liveManual, sessionState: .connected, currentUser: nil))
        .frame(width: 1180, height: 760)
}

@available(macOS 15.0, *)
#Preview("Live Manual - Reconnecting") {
    MainShellView(viewModel: MainShellViewModel(snapshot: MockShellData.snapshot, connectionState: .reconnecting(attempt: 2, nextDelay: .seconds(4)), runtimeMode: .liveManual, sessionState: .connecting, currentUser: MockShellData.snapshot.usersByID[MockShellData.currentUserID]))
        .frame(width: 1180, height: 760)
}
