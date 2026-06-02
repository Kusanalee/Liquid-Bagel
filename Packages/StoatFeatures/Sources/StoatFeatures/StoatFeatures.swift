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
    case notifications
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
    public static let quickReactions = Phase17MessageActions.quickReactions
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
    public var timelineTuning: TimelineTuningConfiguration = .defaults
    public var timelineValidationWarnings: [TimelineValidationWarning] = []
    public var routeVerificationResult = TimelineRouteVerificationResult()
    public var lastRouteVerificationResult: String?
    public var lastTimelineActionResult: String?
    public var lastAckTargetMessageID: MessageID?
    public var lastAckResult: String?
    public var loadedMessageFindQuery = ""
    public var loadedMessageFindResults: [LoadedMessageFindResult] = []
    public var remoteSearchQuery = ""
    public var remoteSearchPinnedOnly = false
    public var remoteSearchResults: [LoadedMessageFindResult] = []
    public var remoteSearchStatus: String?
    public var isChannelSearchPresented = false
    public var channelSearchQuery = ChannelSearchQuery()
    public var channelSearchState: ChannelSearchState = .idle
    public var selectedSearchResultID: MessageID?
    public var searchHighlightState: TimelineSearchHighlightState?
    public var searchNavigationStatus: String?
    public var activeCalibrationRun: TimelineCalibrationRun?
    public var calibrationCheckpointNote = ""
    public var importedCalibrationNotes = ""
    public var selectedTimelineTuningPreset: TimelineTuningPreset = .conservative
    public var attachmentPreview: AttachmentPreviewSheetItem?
    public var attachmentPreviewStates: [String: AttachmentPreviewState] = [:]
    public var loadedAttachmentData: [String: RemoteAttachmentData] = [:]
    public var loadedAttachmentOriginalData: [String: RemoteAttachmentData] = [:]
    public var attachmentLocalFiles: [String: URL] = [:]
    public var lastAttachmentAction: String?
    public var inlineImagePreviewPolicy: InlineImagePreviewPolicy = .automaticSmallImages
    public var loadedImageResources: [ImageCacheKey: Data] = [:]
    public var imageResourceStates: [ImageCacheKey: AttachmentPreviewState] = [:]
    public var lastImageResourceAction: String?
    public var messageSendDiagnostics = MessageSendDiagnostics()
    public var notificationPermissionStatus: NotificationPermissionStatus = .unknown
    public var notificationBanners: [NotificationEvent] = []
    public var notificationDiagnostics = NotificationDiagnostics()
    public var appLifecyclePhase: AppLifecyclePhase = .active
    public var queuedNotificationRoutes: [QueuedNotificationRoute] = []
    public var friendsTab: FriendsTab = .online
    public var addFriendText: String = ""
    public var relationshipActionStatus: String?
    public var isRelationshipRefreshInProgress = false
    public var profileUserID: UserID?
    public var userProfilesByID: [UserID: UserProfile] = [:]
    public var profileErrorsByID: [UserID: String] = [:]
    public var profileLoadingUserIDs: Set<UserID> = []
    public var pendingRelationshipAction: PendingRelationshipAction?

    @ObservationIgnored public var messageActionHandler: any MessageActionHandling
    @ObservationIgnored public var messageCopier: any MessageCopying
    @ObservationIgnored public var attachmentUploadHandler: any AttachmentUploadHandling
    @ObservationIgnored public var remoteAttachmentLoader: any RemoteAttachmentLoading
    @ObservationIgnored public var imageResourceLoader: any ImageResourceLoading
    @ObservationIgnored public var imageMemoryCache: ImageMemoryCache
    @ObservationIgnored public var attachmentSaver: any AttachmentSaving
    @ObservationIgnored public var attachmentOpener: any AttachmentOpening
    @ObservationIgnored public var channelAckSender: any ChannelAckSending
    @ObservationIgnored public var messageReferenceResolver: any MessageReferenceResolving
    @ObservationIgnored public var notificationDeliverer: any NotificationDelivering
    @ObservationIgnored public var notificationPermissionManager: any NotificationPermissionManaging
    @ObservationIgnored public var dockBadgeManager: any DockBadgeManaging
    @ObservationIgnored public var notificationRouteCenter: NotificationRouteCenter
    @ObservationIgnored public var appLifecycleCenter: AppLifecycleCenter
    @ObservationIgnored private var snapshotObservationTask: Task<Void, Never>?
    @ObservationIgnored private var selectedChannelLoadTask: Task<Void, Never>?
    @ObservationIgnored private var typingEndTask: Task<Void, Never>?
    @ObservationIgnored private var ackTask: Task<Void, Never>?
    @ObservationIgnored private var referenceFetchTasks: [MessageID: Task<Void, Never>] = [:]
    @ObservationIgnored private var attachmentLoadTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var imageResourceLoadTasks: [ImageCacheKey: Task<Void, Never>] = [:]
    @ObservationIgnored private var activeTypingChannelID: ChannelID?
    @ObservationIgnored private var lastTypingBeginAt: [ChannelID: Date] = [:]
    @ObservationIgnored private var lastAckedMessageByChannelID: [ChannelID: MessageID] = [:]
    @ObservationIgnored private var visibleMessageIDsByChannelID: [ChannelID: Set<MessageID>] = [:]
    @ObservationIgnored private var resolvedReferencesByChannelID: [ChannelID: [MessageID: MessageReferenceResolution]] = [:]
    @ObservationIgnored private var locallyClearedUnreadChannelIDs: Set<ChannelID> = []
    @ObservationIgnored private var restoredLiveConnectionGeneration: Int?
    @ObservationIgnored private var notificationLiveConnectionGeneration: Int?
    @ObservationIgnored private var seenNotificationMessageIDsByChannelID: [ChannelID: Set<MessageID>] = [:]
    @ObservationIgnored private var deliveredNotificationIDs: Set<String> = []
    @ObservationIgnored private var expiredNotificationRouteCount = 0
    @ObservationIgnored private var previousSnapshot = RealtimeSnapshot()
    @ObservationIgnored private let selectionRestorer = ShellSelectionRestorer()
    @ObservationIgnored private let navigationHelper = ShellNavigationHelper()
    @ObservationIgnored private let viewportReducer = TimelineViewportReducer()
    @ObservationIgnored private let visibleRangeValidator = TimelineVisibleRangeValidator()
    @ObservationIgnored private let loadedMessageFinder = LoadedMessageFinder()
    @ObservationIgnored private let attachmentValidationPolicy = AttachmentValidationPolicy()
    @ObservationIgnored private var visibleRangeUpdateTasks: [ChannelID: Task<Void, Never>] = [:]
    @ObservationIgnored private var failedReferenceFetchMessageIDs: Set<MessageID> = []

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
        messageCopier: (any MessageCopying)? = nil,
        attachmentUploadHandler: (any AttachmentUploadHandling)? = nil,
        remoteAttachmentLoader: (any RemoteAttachmentLoading)? = nil,
        imageMemoryCache: ImageMemoryCache = ImageMemoryCache(),
        imageResourceLoader: (any ImageResourceLoading)? = nil,
        attachmentSaver: (any AttachmentSaving)? = nil,
        attachmentOpener: (any AttachmentOpening)? = nil,
        channelAckSender: (any ChannelAckSending)? = nil,
        messageReferenceResolver: (any MessageReferenceResolving)? = nil,
        notificationDeliverer: (any NotificationDelivering)? = nil,
        notificationPermissionManager: (any NotificationPermissionManaging)? = nil,
        dockBadgeManager: (any DockBadgeManaging)? = nil,
        notificationRouteCenter: NotificationRouteCenter = .shared,
        appLifecycleCenter: AppLifecycleCenter = .shared
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
        self.messageCopier = messageCopier ?? AppKitMessageCopier()
        self.attachmentUploadHandler = attachmentUploadHandler ?? MockAttachmentUploadHandler()
        self.remoteAttachmentLoader = remoteAttachmentLoader ?? MockRemoteAttachmentLoader()
        self.imageMemoryCache = imageMemoryCache
        self.imageResourceLoader = imageResourceLoader ?? MockImageResourceLoader()
        self.attachmentSaver = attachmentSaver ?? AppKitAttachmentSaver()
        self.attachmentOpener = attachmentOpener ?? AppKitAttachmentOpener()
        self.channelAckSender = channelAckSender ?? NoopChannelAckSender()
        self.messageReferenceResolver = messageReferenceResolver ?? DisabledMessageReferenceResolver()
        self.notificationDeliverer = notificationDeliverer ?? UserNotificationsNotificationService()
        self.notificationPermissionManager = notificationPermissionManager ?? UserNotificationsPermissionManager()
        self.dockBadgeManager = dockBadgeManager ?? AppKitDockBadgeManager()
        self.notificationRouteCenter = notificationRouteCenter
        self.appLifecycleCenter = appLifecycleCenter
        self.appLifecyclePhase = appLifecycleCenter.phase
        self.previousSnapshot = snapshot
        self.seenNotificationMessageIDsByChannelID = Self.messageIDMap(snapshot)
        self.quickSwitcherViewModel = QuickSwitcherViewModel(snapshot: snapshot, selection: selection)
        self.quickSwitcherViewModel = QuickSwitcherViewModel(
            snapshot: snapshot,
            selection: selection,
            canPerform: { [weak self] command in self?.canPerform(command) ?? false },
            disabledReason: { [weak self] command in self?.disabledReason(for: command) }
        )
        validateSelection()
        self.messageController.hydrate(from: snapshot)
        installNotificationRouteHandler()
        installAppLifecycleHandler()
        if let snapshotSource {
            observe(snapshotSource: snapshotSource)
        }
    }

    deinit {
        snapshotObservationTask?.cancel()
        selectedChannelLoadTask?.cancel()
        typingEndTask?.cancel()
        ackTask?.cancel()
        referenceFetchTasks.values.forEach { $0.cancel() }
        attachmentLoadTasks.values.forEach { $0.cancel() }
        imageResourceLoadTasks.values.forEach { $0.cancel() }
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

    public var friendItems: [FriendListItem] {
        Phase22Derivations.friendItems(
            for: friendsTab,
            snapshot: snapshot,
            currentUserID: currentUserID,
            currentUser: currentUser,
            localReadStates: localReadStates
        )
    }

    public var allFriendItems: [FriendListItem] {
        Phase22Derivations.friendItems(
            snapshot: snapshot,
            currentUserID: currentUserID,
            currentUser: currentUser,
            localReadStates: localReadStates
        )
    }

    public var directMessageItems: [DirectMessageListItem] {
        Phase22Derivations.directMessageItems(
            snapshot: snapshot,
            currentUserID: currentUserID,
            localReadStates: localReadStates
        )
    }

    public var incomingFriendRequestCount: Int {
        Phase22Derivations.pendingIncomingCount(snapshot: snapshot, currentUserID: currentUserID, currentUser: currentUser)
    }

    public func relationshipStatus(for user: User) -> RelationshipStatus {
        Phase22Derivations.relationshipStatus(for: user, currentUserID: currentUserID, currentUser: currentUser)
    }

    public func openFriends(tab: FriendsTab = .online) {
        friendsTab = tab
        selectDirectMessages()
    }

    public func showUserProfile(_ userID: UserID) {
        profileUserID = userID
        selection.selectedUserID = userID
        Task { [weak self] in await self?.fetchUserProfileIfNeeded(userID) }
    }

    public func closeUserProfile() {
        profileUserID = nil
    }

    public func fetchUserProfileIfNeeded(_ userID: UserID) async {
        guard userProfilesByID[userID] == nil,
              !profileLoadingUserIDs.contains(userID)
        else { return }
        guard effectiveRuntimeMode == .liveManual,
              effectiveSessionState == .connected,
              let apiClient = sessionCoordinator?.apiClient
        else { return }
        profileLoadingUserIDs.insert(userID)
        profileErrorsByID[userID] = nil
        do {
            let profile = try await apiClient.fetchUserProfile(userID: userID)
            userProfilesByID[userID] = profile
        } catch {
            profileErrorsByID[userID] = "Profile unavailable."
        }
        profileLoadingUserIDs.remove(userID)
    }

    public func refreshRelationshipsAndDirectMessages() async {
        guard effectiveRuntimeMode == .liveManual,
              effectiveSessionState == .connected,
              let apiClient = sessionCoordinator?.apiClient
        else {
            relationshipActionStatus = "Connect manually before refreshing friends and DMs."
            return
        }
        isRelationshipRefreshInProgress = true
        defer { isRelationshipRefreshInProgress = false }
        do {
            let user = try await apiClient.fetchCurrentUser()
            applyRelationshipUser(user)
            let dms = try await apiClient.fetchDirectMessages()
            for channel in dms {
                snapshot.channelsByID[channel.id] = channel
            }
            relationshipActionStatus = "Friends and DMs refreshed"
        } catch {
            relationshipActionStatus = "Refresh failed."
        }
    }

    public func sendFriendRequestFromInput() async {
        let username = addFriendText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty else {
            relationshipActionStatus = "Enter a username first."
            return
        }
        if effectiveRuntimeMode == .mock {
            guard let user = snapshot.usersByID.values.first(where: { "\($0.username)#\($0.discriminator)" == username || $0.username == username }) else {
                relationshipActionStatus = "User not found in preview data."
                return
            }
            updatePreviewRelationship(userID: user.id, status: .outgoing)
            addFriendText = ""
            relationshipActionStatus = "Friend request sent"
            return
        }
        guard let apiClient = availableRelationshipAPIClient() else { return }
        do {
            let user = try await apiClient.sendFriendRequest(username: username)
            upsertUser(user)
            addFriendText = ""
            relationshipActionStatus = "Friend request sent"
        } catch {
            relationshipActionStatus = "Friend request failed."
        }
    }

    public func requestRelationshipAction(_ kind: RelationshipActionKind, userID: UserID) {
        pendingRelationshipAction = PendingRelationshipAction(kind: kind, userID: userID)
    }

    public func confirmPendingRelationshipAction() async {
        guard let action = pendingRelationshipAction else { return }
        pendingRelationshipAction = nil
        await performRelationshipAction(action.kind, userID: action.userID)
    }

    public func performRelationshipAction(_ kind: RelationshipActionKind, userID: UserID) async {
        if effectiveRuntimeMode == .mock {
            switch kind {
            case .accept:
                updatePreviewRelationship(userID: userID, status: .friend)
            case .deny, .remove, .unblock:
                updatePreviewRelationship(userID: userID, status: .none)
            case .block:
                updatePreviewRelationship(userID: userID, status: .blocked)
            }
            relationshipActionStatus = relationshipSuccessMessage(for: kind)
            return
        }
        guard let apiClient = availableRelationshipAPIClient() else { return }
        do {
            let user: User
            switch kind {
            case .accept:
                user = try await apiClient.acceptFriendRequest(userID: userID)
            case .deny:
                user = try await apiClient.denyFriendRequest(userID: userID)
            case .remove:
                user = try await apiClient.removeFriend(userID: userID)
            case .block:
                user = try await apiClient.blockUser(userID: userID)
            case .unblock:
                user = try await apiClient.unblockUser(userID: userID)
            }
            upsertUser(user)
            relationshipActionStatus = relationshipSuccessMessage(for: kind)
        } catch {
            relationshipActionStatus = "Relationship action failed."
        }
    }

    public func openDirectMessage(with userID: UserID) async {
        if let existing = directMessageItems.first(where: { $0.participants.contains { $0.id == userID } }) {
            selectChannel(existing.id)
            return
        }
        if effectiveRuntimeMode == .mock {
            let channel = Channel(
                id: ChannelID(rawValue: "mock-dm-\(userID.rawValue)"),
                kind: userID == currentUserID ? .savedMessages : .directMessage,
                userID: userID == currentUserID ? currentUserID : nil,
                active: true,
                recipients: [currentUserID, userID].compactMap { $0 }
            )
            snapshot.channelsByID[channel.id] = channel
            selectChannel(channel.id)
            relationshipActionStatus = "Direct message opened"
            return
        }
        guard let apiClient = availableRelationshipAPIClient() else { return }
        do {
            let channel = try await apiClient.openDirectMessage(userID: userID)
            snapshot.channelsByID[channel.id] = channel
            selectChannel(channel.id)
            relationshipActionStatus = "Direct message opened"
        } catch {
            relationshipActionStatus = "Could not open direct message."
        }
    }

    private func availableRelationshipAPIClient() -> (any StoatAPIClient)? {
        if effectiveRuntimeMode == .mock {
            relationshipActionStatus = "Relationship actions use preview data here."
            return nil
        }
        guard effectiveSessionState == .connected,
              let apiClient = sessionCoordinator?.apiClient
        else {
            relationshipActionStatus = "Connect manually before using friend and DM actions."
            return nil
        }
        return apiClient
    }

    private func updatePreviewRelationship(userID: UserID, status: RelationshipStatus) {
        guard var user = snapshot.usersByID[userID] else { return }
        user.relationship = status
        snapshot.usersByID[userID] = user
        guard var currentUser else { return }
        currentUser.relations.removeAll { $0.id == userID }
        if status != .none {
            currentUser.relations.append(Relationship(id: userID, status: status))
        }
        self.currentUser = currentUser
    }

    private func applyRelationshipUser(_ user: User) {
        currentUser = user
        upsertUser(user)
        for relation in user.relations {
            if var related = snapshot.usersByID[relation.id] {
                related.relationship = relation.status
                snapshot.usersByID[relation.id] = related
            }
        }
    }

    private func upsertUser(_ user: User) {
        snapshot.usersByID[user.id] = user
        if currentUserID == user.id {
            currentUser = user
        }
    }

    private func relationshipSuccessMessage(for kind: RelationshipActionKind) -> String {
        switch kind {
        case .accept: "Friend request accepted"
        case .deny: "Friend request denied"
        case .remove: "Friend removed"
        case .block: "User blocked"
        case .unblock: "User unblocked"
        }
    }

    public func selectHome() {
        endTypingForActiveChannel()
        selection.space = .home
        selection.serverID = nil
        selection.channelID = nil
        selection.dmChannelID = nil
        clearTimelineSelection()
        reconcileSearchHighlightsForSelectedChannel()
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
        reconcileSearchHighlightsForSelectedChannel()
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
        reconcileSearchHighlightsForSelectedChannel()
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
        reconcileSearchHighlightsForSelectedChannel()
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
        reconcileSearchHighlightsForSelectedChannel()
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

    public func showNotificationSettings() {
        selectedSettingsTab = .notifications
        isCredentialSetupPresented = true
        refreshNotificationPermissionStatus()
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
        let previousNotificationGeneration = notificationLiveConnectionGeneration
        runtimeMode = sessionCoordinator.mode
        sessionState = sessionCoordinator.sessionState
        connectionState = sessionCoordinator.connectionState
        diagnostics = sessionCoordinator.diagnostics
        currentUser = sessionCoordinator.currentUser
        selection.isMemberPanelVisible = sessionCoordinator.preferences.memberPanelVisible
        messageDensity = sessionCoordinator.preferences.messageDensity
        reduceGlassIntensity = sessionCoordinator.preferences.reduceGlassIntensity
        inlineImagePreviewPolicy = sessionCoordinator.preferences.inlineImagePreviewPolicy
        timelineTuning = sessionCoordinator.preferences.timelineTuning.validated()
        snapshot = sessionCoordinator.snapshot
        if sessionCoordinator.mode == .liveManual,
           previousNotificationGeneration != sessionCoordinator.liveConnectionGeneration {
            seenNotificationMessageIDsByChannelID = Self.messageIDMap(snapshot)
            notificationLiveConnectionGeneration = sessionCoordinator.liveConnectionGeneration
            deliveredNotificationIDs.removeAll()
        } else if sessionCoordinator.mode != .liveManual {
            notificationLiveConnectionGeneration = nil
            seenNotificationMessageIDsByChannelID = Self.messageIDMap(snapshot)
            deliveredNotificationIDs.removeAll()
            notificationBanners.removeAll()
        }
        messageActionHandler = sessionCoordinator.messageActionHandler
        let liveAPIClient = sessionCoordinator.mode == .liveManual ? sessionCoordinator.apiClient : nil
        attachmentUploadHandler = liveAPIClient.map { LiveAttachmentUploadHandler(apiClient: $0) } ?? MockAttachmentUploadHandler()
        if sessionCoordinator.mode == .liveManual {
            remoteAttachmentLoader = LiveRemoteAttachmentLoader(environment: sessionCoordinator.environment)
            imageResourceLoader = LiveImageResourceLoader(cache: imageMemoryCache)
        } else {
            remoteAttachmentLoader = MockRemoteAttachmentLoader()
            imageResourceLoader = MockImageResourceLoader()
        }
        channelAckSender = liveAPIClient.map { LiveChannelAckSender(apiClient: $0) } ?? NoopChannelAckSender()
        if sessionCoordinator.mode == .mock {
            messageReferenceResolver = InMemoryMessageReferenceResolver(messagesByChannelID: snapshot.messagesByChannelID)
        } else if let liveAPIClient {
            let currentTuning = timelineTuning
            messageReferenceResolver = LiveMessageReferenceResolver(apiClient: liveAPIClient, tuning: { currentTuning })
        } else {
            messageReferenceResolver = DisabledMessageReferenceResolver()
        }
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
        updateDockBadge()
        updateNotificationDiagnostics()
        replayQueuedNotificationRoutesIfReady()
        if sessionCoordinator.mode != .liveManual {
            restoredLiveConnectionGeneration = nil
        }
        if sessionCoordinator.mode == .liveManual, sessionCoordinator.sessionState == .connected {
            loadIdentityImagesForCurrentSnapshot()
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

    public func addAttachmentURLs(_ urls: [URL], to channelID: ChannelID?) {
        guard let channelID else { return }
        var state = composerDraftState(for: channelID)
        for url in urls {
            do {
                let draft = try attachmentValidationPolicy.draft(for: url, existingCount: state.attachments.count)
                state.attachments.append(draft)
                composerError = nil
                lastAttachmentAction = "Queued attachment"
            } catch {
                composerError = error.userFacingMessage
            }
        }
        composerDrafts[channelID] = state
    }

    public func addPastedImageData(_ data: Data, to channelID: ChannelID?) {
        guard let channelID else { return }
        var state = composerDraftState(for: channelID)
        do {
            let draft = try attachmentValidationPolicy.imageDraft(data: data, existingCount: state.attachments.count)
            state.attachments.append(draft)
            composerError = nil
            lastAttachmentAction = "Queued pasted image"
        } catch {
            composerError = error.userFacingMessage
        }
        composerDrafts[channelID] = state
    }

    public func openAttachmentPicker(for channelID: ChannelID?) {
        guard let channelID else { return }
        #if canImport(AppKit)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.resolvesAliases = true
        panel.allowedContentTypes = attachmentValidationPolicy.allowedTypes
        if panel.runModal() == .OK {
            addAttachmentURLs(panel.urls, to: channelID)
        }
        #else
        composerError = "File picker is unavailable on this platform."
        #endif
    }

    public func removeAttachment(_ attachmentID: UUID, from channelID: ChannelID?) {
        guard let channelID else { return }
        var state = composerDraftState(for: channelID)
        state.attachments.removeAll { $0.id == attachmentID }
        composerDrafts[channelID] = state
        lastAttachmentAction = "Removed attachment"
    }

    public func retryAttachmentUpload(_ attachmentID: UUID, in channelID: ChannelID?) async {
        await uploadAttachment(attachmentID, in: channelID)
    }

    public func uploadQueuedAttachments(for channelID: ChannelID?) async {
        guard let channelID else { return }
        let ids = composerDraftState(for: channelID).attachments.map(\.id)
        for id in ids {
            await uploadAttachment(id, in: channelID)
        }
    }

    public func composerDraftState(for channelID: ChannelID?) -> ComposerDraftState {
        guard let channelID else {
            return ComposerDraftState(channelID: "")
        }
        return composerDrafts[channelID] ?? ComposerDraftState(channelID: channelID)
    }

    public func currentMessageSendDiagnostics() -> MessageSendDiagnostics {
        let channelID = selection.channelID ?? selection.dmChannelID
        let readiness = composerReadiness(for: channelID)
        var diagnostics = messageSendDiagnostics
        diagnostics.selectedChannelID = channelID
        diagnostics.runtimeMode = effectiveRuntimeMode
        diagnostics.sessionState = effectiveSessionState
        diagnostics.connectionStateDescription = MessageSendDiagnosticsFormatter.redact(String(describing: effectiveConnectionState))
        diagnostics.canSend = readiness.canSend
        diagnostics.disabledReason = readiness.canSend ? nil : MessageSendDiagnosticsFormatter.redact(readiness.reason)
        return diagnostics
    }

    private func recordMessageSendDiagnostics(
        channelID: ChannelID?,
        stage: MessageSendStage,
        result: MessageSendResult? = nil,
        error: String? = nil,
        attemptedAt: Date? = nil
    ) {
        let readiness = composerReadiness(for: channelID)
        messageSendDiagnostics = MessageSendDiagnostics(
            selectedChannelID: channelID,
            runtimeMode: effectiveRuntimeMode,
            sessionState: effectiveSessionState,
            connectionStateDescription: String(describing: effectiveConnectionState),
            canSend: readiness.canSend,
            disabledReason: readiness.canSend ? nil : readiness.reason,
            lastSendAttemptAt: attemptedAt ?? messageSendDiagnostics.lastSendAttemptAt,
            lastSendStage: stage,
            lastSendResult: result ?? messageSendDiagnostics.lastSendResult,
            lastError: error ?? messageSendDiagnostics.lastError
        )
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
        let state = composerDraftState(for: channelID)
        let draft = draft(for: channelID).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.isEmpty || !state.attachments.isEmpty else {
            return (false, "Type a message or attach a file.")
        }
        guard isRuntimeSendCapable else {
            return (false, effectiveRuntimeMode == .mock ? "Preview data cannot send messages." : "Connect manually to send live messages.")
        }
        if let permissions = resolvedPermissions(for: channel), !permissions.contains(.sendMessage) {
            return (false, "You do not have permission to send messages here.")
        }
        if !state.attachments.isEmpty, !canUploadFiles(in: channel) {
            return (false, "You do not have permission to upload files here.")
        }
        if state.attachments.contains(where: { $0.status.isWorking }) {
            return (false, "Attachment upload is already in progress.")
        }
        if state.attachments.contains(where: {
            if case .failed = $0.status { return true }
            return false
        }) {
            return (false, "Retry or remove failed attachments before sending.")
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
            return (false, effectiveRuntimeMode == .mock ? "Preview data cannot send messages." : "Connect manually to send live messages.")
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

    public func composerAttachmentChips(for channelID: ChannelID?) -> [ComposerAttachmentChip] {
        composerDraftState(for: channelID).attachments.map { attachment in
            ComposerAttachmentChip(
                id: attachment.id,
                filename: attachment.filename,
                subtitle: attachment.displaySize,
                systemImage: systemImage(for: attachment.kind),
                status: chipStatus(for: attachment.status),
                previewData: attachment.previewData
            )
        }
    }

    public func composerAttachmentSummary(for channelID: ChannelID?) -> String? {
        let attachments = composerDraftState(for: channelID).attachments
        guard !attachments.isEmpty else { return nil }
        let totalBytes = attachments.reduce(0) { $0 + $1.byteCount }
        let count = attachments.count == 1 ? "1 attachment" : "\(attachments.count) attachments"
        return "\(count) · \(ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file))"
    }

    private func systemImage(for kind: ComposerAttachmentKind) -> String {
        switch kind {
        case .image:
            return "photo"
        case .pdf:
            return "doc.richtext"
        case .text:
            return "doc.text"
        case .file:
            return "doc"
        }
    }

    private func chipStatus(for status: ComposerAttachmentUploadStatus) -> ComposerAttachmentChipStatus {
        switch status {
        case .queued:
            return .queued
        case .reading:
            return .reading
        case .uploading:
            return .uploading
        case .uploaded:
            return .uploaded
        case let .failed(message):
            return .failed(message)
        }
    }

    public func attachmentDisplayItems(for message: Message) -> [AttachmentDisplayItem] {
        (message.attachments ?? []).map { file in
            var item = AttachmentDisplayItem(file: file, previewState: attachmentPreviewStates["file-\(file.id.rawValue)"] ?? .notLoaded)
            if let loaded = loadedAttachmentData[item.id] {
                item.previewState = .readyRemote
                item.previewData = loaded.data
            }
            if attachmentLocalFiles[item.id] != nil {
                item.previewState = .readyLocal
            }
            return item
        }
    }

    public func loadInlineImagePreviews(for message: Message) {
        guard inlineImagePreviewPolicy == .automaticSmallImages else { return }
        guard effectiveRuntimeMode == .liveManual || effectiveRuntimeMode == .mock else { return }
        for item in attachmentDisplayItems(for: message) where shouldAutoLoadInlineImage(item) {
            guard attachmentLoadTasks[item.id] == nil else { continue }
            attachmentLoadTasks[item.id] = Task { [weak self] in
                await self?.loadInlineImagePreview(item)
            }
        }
    }

    private func shouldAutoLoadInlineImage(_ item: AttachmentDisplayItem) -> Bool {
        guard item.kind == .image, item.previewData == nil else { return false }
        guard item.source.isRemoteLoadable else { return false }
        guard item.byteCount.map({ $0 <= 8 * 1024 * 1024 }) ?? true else { return false }
        switch item.previewState {
        case .notLoaded:
            return true
        case .failed, .loading, .readyLocal, .readyRemote, .unsupported:
            return false
        }
    }

    private func loadInlineImagePreview(_ item: AttachmentDisplayItem) async {
        await MainActor.run {
            self.attachmentPreviewStates[item.id] = .loading
            self.lastAttachmentAction = "Loading inline image preview"
        }
        defer {
            Task { @MainActor [weak self] in
                self?.attachmentLoadTasks[item.id] = nil
            }
        }
        do {
            let loaded = try await remoteAttachmentLoader.load(item, purpose: .preview)
            await MainActor.run {
                self.loadedAttachmentData[item.id] = loaded
                self.attachmentPreviewStates[item.id] = .readyRemote
                self.lastAttachmentAction = "Loaded inline image preview"
            }
        } catch {
            let message = AttachmentSafety.safeErrorMessage(error)
            await MainActor.run {
                self.attachmentPreviewStates[item.id] = .failed(message)
                self.lastAttachmentAction = "Inline image preview failed"
            }
        }
    }

    public func imageData(for file: File?, kind: ImageResourceKind) -> Data? {
        guard let file else { return nil }
        return loadedImageResources[ImageCacheKey(id: file.id.rawValue, kind: kind)]
    }

    public func loadImageResource(for file: File?, kind: ImageResourceKind) {
        guard let request = imageResourceRequest(for: file, kind: kind) else { return }
        let key = request.cacheKey
        guard loadedImageResources[key] == nil, imageResourceLoadTasks[key] == nil else { return }
        imageResourceStates[key] = .loading
        imageResourceLoadTasks[key] = Task { [weak self] in
            await self?.loadImageResource(request)
        }
    }

    public func clearImageMemoryCache() async {
        await imageMemoryCache.removeAll()
        loadedImageResources.removeAll()
        imageResourceStates.removeAll()
        lastImageResourceAction = "Cleared image memory cache"
    }

    public func reloadVisibleImages() {
        for message in selectedTimelineMessages.map(\.message) {
            loadInlineImagePreviews(for: message)
            loadImageResource(for: avatarFile(for: message), kind: .userAvatar)
        }
        loadIdentityImagesForCurrentSnapshot()
        lastImageResourceAction = "Reloaded visible images"
    }

    public func imageResourceDiagnostics() async -> ImageResourceDiagnostics {
        let snapshot = await imageMemoryCache.snapshot()
        let failed = imageResourceStates.values.filter {
            if case .failed = $0 { return true }
            return false
        }.count
        return ImageResourceDiagnostics(
            loadedCount: loadedImageResources.count,
            failedCount: failed,
            cacheEntryCount: snapshot.count,
            cacheByteCount: snapshot.byteCount,
            lastAction: lastImageResourceAction
        )
    }

    private func loadImageResource(_ request: ImageResourceRequest) async {
        defer {
            Task { @MainActor [weak self] in
                self?.imageResourceLoadTasks[request.cacheKey] = nil
            }
        }
        do {
            let loaded = try await imageResourceLoader.loadImage(request)
            await MainActor.run {
                self.loadedImageResources[request.cacheKey] = loaded.data
                self.imageResourceStates[request.cacheKey] = .readyRemote
                self.lastImageResourceAction = loaded.fromCache ? "Loaded image from memory cache" : "Loaded image"
            }
        } catch {
            let message = AttachmentSafety.safeErrorMessage(error)
            await MainActor.run {
                self.imageResourceStates[request.cacheKey] = .failed(message)
                self.lastImageResourceAction = "Image load failed"
            }
        }
    }

    private func loadIdentityImagesForCurrentSnapshot() {
        for user in snapshot.usersByID.values {
            loadImageResource(for: user.avatar, kind: .userAvatar)
        }
        for member in snapshot.membersByServerAndUserID.values {
            loadImageResource(for: member.avatar, kind: .userAvatar)
        }
        for server in snapshot.serversByID.values {
            loadImageResource(for: server.icon, kind: .serverIcon)
            loadImageResource(for: server.banner, kind: .serverBanner)
        }
    }

    private func imageResourceRequest(for file: File?, kind: ImageResourceKind) -> ImageResourceRequest? {
        guard let file, file.deleted != true, file.reported != true else { return nil }
        guard let baseURL = sessionCoordinator?.environment.mediaBaseURL ?? StoatAPIEnvironment.production.mediaBaseURL else { return nil }
        let tag: String
        switch kind {
        case .attachmentPreview, .attachmentOriginal:
            tag = file.tag.isEmpty ? "attachments" : file.tag
        case .userAvatar:
            tag = "avatars"
        case .serverIcon:
            tag = "icons"
        case .serverBanner:
            tag = "banners"
        }
        let filename = kind == .attachmentOriginal ? "original" : nil
        guard let url = try? LiveRemoteAttachmentLoader.mediaURL(baseURL: baseURL, tag: tag, fileID: file.id, filename: filename) else {
            return nil
        }
        let maxBytes: Int
        switch kind {
        case .serverBanner:
            maxBytes = 4 * 1024 * 1024
        case .attachmentPreview:
            maxBytes = 8 * 1024 * 1024
        case .attachmentOriginal:
            maxBytes = 20 * 1024 * 1024
        case .userAvatar, .serverIcon:
            maxBytes = 2 * 1024 * 1024
        }
        return ImageResourceRequest(id: file.id.rawValue, url: url, kind: kind, maxBytes: maxBytes, filename: file.filename)
    }

    public func member(for userID: UserID, serverID: ServerID?) -> ServerMember? {
        guard let serverID else { return nil }
        return snapshot.membersByServerAndUserID[ServerMemberKey(serverID: serverID, userID: userID)]
    }

    public func displayName(for user: User?, member: ServerMember? = nil, fallbackID: UserID? = nil) -> String {
        member?.nickname ?? user?.displayName ?? user?.username ?? fallbackID?.rawValue ?? "Unknown"
    }

    public func avatarFile(for message: Message) -> File? {
        if let memberAvatar = message.member?.avatar { return memberAvatar }
        if let userAvatar = message.user?.avatar { return userAvatar }
        let member = member(for: message.authorID, serverID: snapshot.channelsByID[message.channelID]?.serverID)
        return member?.avatar ?? snapshot.usersByID[message.authorID]?.avatar
    }

    public func previewComposerAttachment(_ attachmentID: UUID, in channelID: ChannelID?) {
        guard let draft = composerDraftState(for: channelID).attachments.first(where: { $0.id == attachmentID }) else { return }
        var item = AttachmentDisplayItem(attachmentDraft: draft)
        var data = draft.previewData
        var localFile: URL?
        if case let .fileURL(url) = draft.source {
            localFile = url
            if data == nil, draft.kind == .image {
                let scoped = url.startAccessingSecurityScopedResource()
                defer {
                    if scoped { url.stopAccessingSecurityScopedResource() }
                }
                data = try? Data(contentsOf: url, options: [.mappedIfSafe])
            }
        }
        if data != nil || localFile != nil {
            item.previewState = .readyLocal
        } else if !item.kind.isPreviewable {
            item.previewState = .unsupported("Preview unavailable")
        }
        if let data {
            loadedAttachmentData[item.id] = RemoteAttachmentData(fileID: item.fileID, filename: item.displayName, contentType: item.contentType, byteCount: data.count, data: data)
        }
        if let localFile {
            attachmentLocalFiles[item.id] = localFile
        }
        attachmentPreview = AttachmentPreviewSheetItem(item: item, data: data, localFile: localFile, debugFileID: item.fileID?.rawValue)
        lastAttachmentAction = "Opened composer attachment preview"
    }

    public func previewAttachment(_ item: AttachmentDisplayItem) async {
        var current = itemWithCurrentPreviewState(item)
        if let data = loadedAttachmentData[current.id] {
            current.previewState = .readyRemote
            attachmentPreview = AttachmentPreviewSheetItem(item: current, data: data.data, localFile: attachmentLocalFiles[current.id], debugFileID: current.fileID?.rawValue)
            lastAttachmentAction = "Opened loaded attachment preview"
            return
        }
        if let localFile = attachmentLocalFiles[current.id] {
            current.previewState = .readyLocal
            attachmentPreview = AttachmentPreviewSheetItem(item: current, data: try? Data(contentsOf: localFile), localFile: localFile, debugFileID: current.fileID?.rawValue)
            lastAttachmentAction = "Opened local attachment preview"
            return
        }
        guard current.kind.isPreviewable else {
            current.previewState = .unsupported("Preview unavailable. Download instead.")
            attachmentPreviewStates[current.id] = current.previewState
            attachmentPreview = AttachmentPreviewSheetItem(item: current, debugFileID: current.fileID?.rawValue, statusMessage: "Preview unavailable. Download instead.")
            return
        }
        if case .loading = attachmentPreviewStates[current.id] {
            return
        }
        attachmentPreviewStates[current.id] = .loading
        lastAttachmentAction = "Loading attachment preview"
        do {
            let loaded = try await remoteAttachmentLoader.load(current, purpose: .preview)
            loadedAttachmentData[current.id] = loaded
            current.previewState = .readyRemote
            attachmentPreviewStates[current.id] = .readyRemote
            attachmentPreview = AttachmentPreviewSheetItem(item: current, data: loaded.data, localFile: attachmentLocalFiles[current.id], debugFileID: current.fileID?.rawValue)
            lastAttachmentAction = "Loaded attachment preview"
        } catch {
            let message = AttachmentSafety.safeErrorMessage(error)
            current.previewState = .failed(message)
            attachmentPreviewStates[current.id] = current.previewState
            attachmentPreview = AttachmentPreviewSheetItem(item: current, debugFileID: current.fileID?.rawValue, statusMessage: message)
            lastAttachmentAction = "Attachment preview failed"
        }
    }

    public func downloadAttachment(_ item: AttachmentDisplayItem) async {
        let current = itemWithCurrentPreviewState(item)
        do {
            let data: RemoteAttachmentData
            if let loaded = loadedAttachmentOriginalData[current.id] {
                data = loaded
            } else if current.source.isRemoteLoadable {
                data = try await remoteAttachmentLoader.load(current, purpose: .original)
                loadedAttachmentOriginalData[current.id] = data
            } else if let loaded = loadedAttachmentData[current.id] {
                data = loaded
            } else {
                throw AttachmentActionError.unavailable("Attachment is not available to save.")
            }
            try await attachmentSaver.save(data: data.data, suggestedFilename: current.displayName)
            lastAttachmentAction = "Saved attachment"
            placeholderStatus = "Attachment saved"
        } catch AttachmentActionError.cancelled {
            lastAttachmentAction = "Save cancelled"
        } catch {
            let message = AttachmentSafety.safeErrorMessage(error)
            lastAttachmentAction = "Save failed"
            placeholderStatus = message
        }
    }

    public func openAttachmentExternally(_ item: AttachmentDisplayItem) async {
        var current = itemWithCurrentPreviewState(item)
        do {
            let url: URL
            if let existing = attachmentLocalFiles[current.id] {
                url = existing
            } else if let original = loadedAttachmentOriginalData[current.id] ?? loadedAttachmentData[current.id] {
                url = try writeTemporaryAttachmentFile(data: original.data, filename: current.displayName)
                attachmentLocalFiles[current.id] = url
                current.previewState = .readyLocal
                attachmentPreviewStates[current.id] = .readyLocal
            } else {
                throw AttachmentActionError.unavailable("Preview or download this attachment before opening it.")
            }
            try await attachmentOpener.open(url)
            lastAttachmentAction = "Opened attachment externally"
        } catch {
            let message = AttachmentSafety.safeErrorMessage(error)
            lastAttachmentAction = "Open externally failed"
            placeholderStatus = message
        }
    }

    public func retryAttachmentPreview(_ item: AttachmentDisplayItem) async {
        attachmentPreviewStates[item.id] = .notLoaded
        loadedAttachmentData[item.id] = nil
        await previewAttachment(item)
    }

    public func closeAttachmentPreview() {
        attachmentPreview = nil
        lastAttachmentAction = "Closed attachment preview"
    }

    public func attachmentDiagnostics() -> AttachmentDiagnostics {
        let drafts = composerDrafts.values.flatMap(\.attachments)
        let queued = drafts.filter {
            if case .queued = $0.status { return true }
            return false
        }.count
        let working = drafts.filter(\.status.isWorking).count
        let failed = drafts.filter {
            if case .failed = $0.status { return true }
            return false
        }.count
        let displayed = selectedTimelineMessages.reduce(0) { count, timelineMessage in
            count + (timelineMessage.message.attachments?.count ?? 0)
        }
        let failedPreviews = attachmentPreviewStates.values.filter {
            if case .failed = $0 { return true }
            return false
        }.count
        return AttachmentDiagnostics(
            queuedDraftCount: queued,
            uploadingCount: working,
            failedUploadCount: failed,
            displayedAttachmentCount: displayed,
            loadedPreviewCount: loadedAttachmentData.count,
            failedPreviewCount: failedPreviews,
            lastAttachmentAction: lastAttachmentAction
        )
    }

    private func itemWithCurrentPreviewState(_ item: AttachmentDisplayItem) -> AttachmentDisplayItem {
        var current = item
        if let state = attachmentPreviewStates[item.id] {
            current.previewState = state
        }
        if loadedAttachmentData[item.id] != nil {
            current.previewState = .readyRemote
        }
        if attachmentLocalFiles[item.id] != nil {
            current.previewState = .readyLocal
        }
        return current
    }

    private func writeTemporaryAttachmentFile(data: Data, filename: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LiquidBagelAttachmentPreviews", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(UUID().uuidString + "-" + AttachmentDisplayFormatting.safeFilename(filename))
        try data.write(to: url, options: [.atomic])
        return url
    }

    private func cleanupTemporaryAttachmentFiles() {
        for url in attachmentLocalFiles.values where url.path.contains("LiquidBagelAttachmentPreviews") {
            try? FileManager.default.removeItem(at: url)
        }
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
        case .pending, .retrying, .deleting:
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
        recordMessageSendDiagnostics(channelID: channelID, stage: .validatingDraft, result: .pending, error: nil, attemptedAt: Date())
        guard let channelID else {
            recordMessageSendDiagnostics(channelID: nil, stage: .failed, result: .failed, error: "Select a channel to send a message.")
            return
        }
        recordMessageSendDiagnostics(channelID: channelID, stage: .checkingRuntime, result: .pending, error: nil)
        recordMessageSendDiagnostics(channelID: channelID, stage: .checkingPermissions, result: .pending, error: nil)
        let readiness = composerReadiness(for: channelID)
        guard readiness.canSend else {
            composerError = readiness.reason
            placeholderStatus = readiness.reason
            recordMessageSendDiagnostics(channelID: channelID, stage: .failed, result: .failed, error: readiness.reason)
            return
        }
        recordMessageSendDiagnostics(channelID: channelID, stage: .uploadingAttachments, result: .pending, error: nil)
        await uploadQueuedAttachments(for: channelID)
        let uploadedState = composerDraftState(for: channelID)
        guard !uploadedState.attachments.contains(where: {
            if case .failed = $0.status { return true }
            return $0.uploadedFileID == nil
        }) else {
            composerError = "One or more attachments could not be uploaded."
            placeholderStatus = "One or more attachments could not be uploaded."
            recordMessageSendDiagnostics(channelID: channelID, stage: .failed, result: .failed, error: "One or more attachments could not be uploaded.")
            return
        }
        recordMessageSendDiagnostics(channelID: channelID, stage: .buildingPayload, result: .pending, error: nil)
        let content = uploadedState.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let draftState = uploadedState
        let replies = draftState.replyContext.map { [MessageReply(id: $0.messageID, mention: draftState.shouldMentionReplyAuthor)] }
        let attachmentIDs = draftState.attachments.compactMap(\.uploadedFileID)
        let attachmentFiles = draftState.attachments.compactMap { draft -> File? in
            guard let id = draft.uploadedFileID else { return nil }
            let itemID = "file-\(id.rawValue)"
            if draft.kind == .image,
               let previewData = localImagePreviewData(for: draft) {
                loadedAttachmentData[itemID] = RemoteAttachmentData(fileID: id, filename: draft.filename, contentType: draft.mimeType, byteCount: previewData.count, data: previewData)
            }
            return File(attachmentDraft: draft, uploadedFileID: id)
        }
        composerDrafts[channelID] = ComposerDraftState(channelID: channelID)
        composerError = nil
        recordMessageSendDiagnostics(channelID: channelID, stage: .creatingOptimisticMessage, result: .pending, error: nil)
        recordMessageSendDiagnostics(channelID: channelID, stage: .sendingRequest, result: .pending, error: nil)
        let didSend = await messageController.sendMessage(channelID: channelID, content: content, replies: replies, attachments: attachmentIDs, attachmentFiles: attachmentFiles, handler: messageActionHandler)
        if didSend {
            recordMessageSendDiagnostics(channelID: channelID, stage: .decodingResponse, result: .pending, error: nil)
            recordMessageSendDiagnostics(channelID: channelID, stage: .reconciled, result: .succeeded, error: nil)
            messageActionStatus = "Message sent."
            acknowledgeSelectedChannel()
        } else {
            let error = messageController.lastErrorByChannelID[channelID] ?? "Message send failed."
            recordMessageSendDiagnostics(channelID: channelID, stage: .failed, result: .failed, error: error)
            messageActionStatus = error
        }
    }

    private func localImagePreviewData(for draft: ComposerAttachmentDraft) -> Data? {
        guard draft.kind == .image else { return nil }
        if let data = draft.previewData { return data }
        guard draft.byteCount <= 8 * 1024 * 1024 else { return nil }
        guard case let .fileURL(url) = draft.source else { return nil }
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
        return try? Data(contentsOf: url, options: [.mappedIfSafe])
    }

    private func uploadAttachment(_ attachmentID: UUID, in channelID: ChannelID?) async {
        guard let channelID else { return }
        var state = composerDraftState(for: channelID)
        guard let index = state.attachments.firstIndex(where: { $0.id == attachmentID }) else { return }
        switch state.attachments[index].status {
        case .uploaded, .reading, .uploading:
            return
        case .queued, .failed:
            break
        }

        state.attachments[index].status = .reading
        composerDrafts[channelID] = state
        lastAttachmentAction = "Started attachment upload"

        state = composerDraftState(for: channelID)
        guard let readingIndex = state.attachments.firstIndex(where: { $0.id == attachmentID }) else { return }
        let attachment = state.attachments[readingIndex]
        state.attachments[readingIndex].status = .uploading
        composerDrafts[channelID] = state

        do {
            let uploaded = try await attachmentUploadHandler.upload(attachment)
            var updated = composerDraftState(for: channelID)
            guard let updatedIndex = updated.attachments.firstIndex(where: { $0.id == attachmentID }) else { return }
            updated.attachments[updatedIndex].status = .uploaded(uploaded.id)
            composerDrafts[channelID] = updated
            composerError = nil
            lastAttachmentAction = "Uploaded attachment"
        } catch {
            var updated = composerDraftState(for: channelID)
            guard let updatedIndex = updated.attachments.firstIndex(where: { $0.id == attachmentID }) else { return }
            updated.attachments[updatedIndex].status = .failed(error.userFacingMessage)
            composerDrafts[channelID] = updated
            composerError = "Attachment upload failed."
            lastAttachmentAction = "Attachment upload failed"
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
        let anchor = timelineViewport.visibleRange?.firstVisibleMessageID ?? selectedTimelineMessages.first?.message.id
        let loaded = await messageController.loadOlderMessages(channelID: channelID)
        if loaded {
            let loadedIDs = Set(selectedTimelineMessages.map(\.message.id))
            let target = anchor.flatMap { loadedIDs.contains($0) ? $0 : nil } ?? selectedTimelineMessages.first?.message.id
            timelineViewport = viewportReducer.preserveAfterPrepend(timelineViewport, previousOldestID: target)
            lastTimelineActionResult = "Loaded older messages"
            recordTimelineCalibrationObservation(kind: .afterLoadOlder)
        } else {
            lastTimelineActionResult = "Load older unavailable or failed"
        }
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
            inlineEditState = nil
            editingDraft = nil
            messageController.updateFailedRecoveryContent(messageID: localFailed.message.id, channelID: editState.channelID, content: editState.draftContent)
            if let updated = messageController.state(for: editState.channelID).timelineMessages.first(where: { $0.message.id == localFailed.message.id }) {
                _ = await messageController.retrySend(updated, handler: messageActionHandler)
            }
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

    public func messageActionContext(for timelineMessage: TimelineMessage) -> MessageActionContext {
        MessageActionContext(
            timelineMessage: timelineMessage,
            currentUserID: currentUserID,
            canReply: canReply(to: timelineMessage),
            canEdit: canEdit(timelineMessage),
            canDelete: canDelete(timelineMessage),
            canReact: timelineMessage.status == .confirmed && canReact(to: timelineMessage.message),
            canPin: canPin(timelineMessage),
            developerControlsEnabled: isDeveloperControlsEnabled
        )
    }

    public func messageActionItems(for timelineMessage: TimelineMessage) -> [MessageActionItem] {
        Phase17MessageActions.actionItems(for: messageActionContext(for: timelineMessage))
    }

    public func reactionSummaries(for message: Message) -> [ReactionSummary] {
        Phase17MessageActions.reactionSummaries(for: message, currentUserID: currentUserID)
    }

    public func messageActionDiagnostics() -> MessageActionDiagnostics {
        let messages = selectedTimelineMessages
        let actions = messages.flatMap { messageActionItems(for: $0) }
        let reactions = messages.flatMap { reactionSummaries(for: $0.message) }
        return Phase17MessageActions.diagnostics(
            actions: actions,
            reactions: reactions,
            hasPendingDeleteConfirmation: pendingDeletion != nil
        )
    }

    public func isMessageActionAvailable(_ kind: MessageActionKind, for timelineMessage: TimelineMessage) -> Bool {
        messageActionItems(for: timelineMessage).contains { $0.kind == kind && $0.availability.isAvailable }
    }

    public func performMessageAction(_ actionID: String, on timelineMessage: TimelineMessage) {
        guard let item = messageActionItems(for: timelineMessage).first(where: { $0.id == actionID }),
              item.availability.isAvailable
        else {
            placeholderStatus = "Message action is unavailable."
            return
        }
        timelineSelection = TimelineSelection(channelID: timelineMessage.message.channelID, messageID: timelineMessage.message.id, source: .mouse, mode: .actionMenu)
        switch item.kind {
        case .copyText:
            Task { [weak self] in await self?.copyMessageText(timelineMessage.message) }
        case .copyMessageID:
            Task { [weak self] in await self?.copyMessageID(timelineMessage) }
        case .reply:
            beginReply(to: timelineMessage, source: .contextMenu)
        case .edit:
            beginEditing(timelineMessage)
        case .delete, .discardFailed:
            requestDelete(timelineMessage)
        case .retry:
            Task { [weak self] in await self?.retry(timelineMessage) }
        case .editAndRetry:
            editAndRetry(timelineMessage)
        case .pin, .unpin:
            Task { [weak self] in await self?.togglePin(timelineMessage) }
        case let .addReaction(emoji), let .removeReaction(emoji):
            Task { [weak self] in await self?.toggleReaction(emoji, on: timelineMessage) }
        }
    }

    @discardableResult
    public func copyMessageText(_ message: Message) async -> Bool {
        guard let text = Phase17MessageActions.copyableText(for: message) else {
            placeholderStatus = "Message has no copyable text."
            return false
        }
        await messageCopier.copy(Phase17MessageActions.redactedDiagnosticText(text))
        messageActionStatus = "Message text copied"
        return true
    }

    @discardableResult
    public func copyMessageID(_ timelineMessage: TimelineMessage) async -> Bool {
        guard isDeveloperControlsEnabled else {
            placeholderStatus = "Developer message ID copy is disabled."
            return false
        }
        guard let id = Phase17MessageActions.stableMessageID(for: timelineMessage) else {
            placeholderStatus = "Message ID is not available for local messages."
            return false
        }
        await messageCopier.copy(id.rawValue)
        messageActionStatus = "Message ID copied"
        return true
    }

    public static func copyableContent(for message: Message) -> String {
        Phase17MessageActions.copyableText(for: message) ?? ""
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
        recordTimelineCalibrationObservation(kind: .afterJumpNewest)
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
            if let unreadID = firstUnreadMessageID(for: activeChannelID) {
                messageController.updateUnreadRecovery(channelID: activeChannelID, state: .targetUnloaded(unreadID))
                placeholderStatus = "Unread message is not loaded."
            } else {
                placeholderStatus = "No unread marker in this channel."
            }
            return
        }
        messageController.updateUnreadRecovery(channelID: activeChannelID, state: .targetLoaded(unreadID))
        timelineSelection = TimelineSelection(channelID: activeChannelID, messageID: unreadID, source: .scrollJump)
        timelineViewport = viewportReducer.jumpFirstUnread(timelineViewport, unreadMessageID: unreadID, loadedMessageIDs: Set(selectedTimelineMessages.map(\.message.id)))
        requestFocus(.timeline)
        recordTimelineCalibrationObservation(kind: .afterJumpUnread)
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

    public func updateTimelineVisibility(messageID: MessageID, channelID: ChannelID, isVisible: Bool) {
        guard channelID == (selection.channelID ?? selection.dmChannelID) else { return }
        var visible = visibleMessageIDsByChannelID[channelID] ?? []
        if isVisible {
            visible.insert(messageID)
        } else {
            visible.remove(messageID)
        }
        visibleMessageIDsByChannelID[channelID] = visible
        let loadedIDs = selectedTimelineMessages.map(\.message.id)
        timelineViewport = viewportReducer.visibleRangeChanged(
            timelineViewport,
            channelID: channelID,
            visibleMessageIDs: Array(visible),
            loadedMessageIDs: loadedIDs,
            nearNewestMessageThreshold: timelineTuning.nearNewestMessageThreshold
        )
        validateTimelineState()
        if timelineViewport.isAtNewest {
            acknowledgeSelectedChannel()
            scheduleLiveAckIfNeeded(channelID: channelID)
        }
    }

    public func loadToFirstUnreadMessage() async {
        guard let channelID = selection.channelID ?? selection.dmChannelID,
              let unreadID = firstUnreadMessageID(for: channelID)
        else {
            placeholderStatus = "No unread marker in this channel."
            return
        }
        if selectedTimelineMessages.contains(where: { $0.message.id == unreadID }) {
            jumpToFirstUnreadMessage()
            return
        }
        let state = await messageController.loadOlderMessagesToTarget(
            channelID: channelID,
            targetMessageID: unreadID,
            maxAttempts: timelineTuning.loadToUnreadMaxAttempts
        )
        switch state {
        case .targetLoaded:
            jumpToFirstUnreadMessage()
        case .targetMissing:
            placeholderStatus = "Unread message could not be found."
        case let .failed(_, message):
            placeholderStatus = message
        default:
            placeholderStatus = "Unread message is outside the loaded range."
        }
    }

    public func resolvedReplyPreview(for message: Message) -> String? {
        guard let replyID = message.replies?.first else { return nil }
        if let referenced = selectedTimelineMessages.first(where: { $0.message.id == replyID })?.message {
            let author = snapshot.usersByID[referenced.authorID]
            let authorName = referenced.masquerade?.name ?? author?.displayName ?? author?.username ?? referenced.authorID.rawValue
            return "\(authorName): \(Self.replyPreviewText(for: referenced))"
        }
        if let resolution = resolvedReferencesByChannelID[message.channelID]?[replyID] {
            switch resolution {
            case let .loaded(referenced):
                let author = snapshot.usersByID[referenced.authorID]
                let authorName = referenced.masquerade?.name ?? author?.displayName ?? author?.username ?? referenced.authorID.rawValue
                return "\(authorName): \(Self.replyPreviewText(for: referenced))"
            case .deleted:
                return "Original message was deleted"
            case .forbidden:
                return "Original message is not accessible"
            case .notFound:
                return "Original message was not found"
            case .rateLimited:
                return "Original message is rate limited"
            case let .unavailable(message):
                return message
            case .notSupported:
                return "Live reference fetching is unavailable"
            }
        }
        resolveReferenceIfNeeded(channelID: message.channelID, messageID: replyID)
        return "Loading original message..."
    }

    public func timelineDiagnostics() -> TimelineDiagnostics {
        let channelID = selection.channelID ?? selection.dmChannelID
        let history = channelID.flatMap { messageController.historiesByChannelID[$0] }
        let messages = selectedTimelineMessages
        return TimelineDiagnostics(
            channelID: channelID,
            loadedMessageCount: messages.count,
            oldestLoadedMessageID: history?.loadedRange.oldestLoadedMessageID ?? messages.first?.message.id,
            newestLoadedMessageID: history?.loadedRange.newestLoadedMessageID ?? messages.last?.message.id,
            firstVisibleMessageID: timelineViewport.visibleRange?.firstVisibleMessageID,
            lastVisibleMessageID: timelineViewport.visibleRange?.lastVisibleMessageID,
            firstUnreadMessageID: channelID.flatMap { firstUnreadMessageID(for: $0) },
            atNewest: timelineViewport.isAtNewest,
            hasMoreBefore: history?.loadedRange.hasMoreBefore ?? false,
            hasMoreAfter: history?.loadedRange.hasMoreAfter ?? false,
            unreadRecoveryState: history?.unreadRecoveryState ?? .none,
            pendingReferenceFetchCount: history?.pendingReferenceFetchMessageIDs.count ?? 0,
            failedReferenceFetchCount: failedReferenceFetchMessageIDs.count,
            pendingRetryCount: messageController.retryingMessageIDs.count,
            lastAckTargetMessageID: lastAckTargetMessageID,
            lastAckResult: lastAckResult,
            lastTimelineActionResult: lastTimelineActionResult ?? messageActionStatus ?? placeholderStatus,
            lastRouteVerificationResult: lastRouteVerificationResult,
            tuningConfiguration: timelineTuning,
            validationWarnings: timelineValidationWarnings
        )
    }

    @discardableResult
    public func validateTimelineState() -> [TimelineValidationWarning] {
        let channelID = selection.channelID ?? selection.dmChannelID
        timelineValidationWarnings = visibleRangeValidator.warnings(
            channelID: channelID,
            loadedMessageIDs: selectedTimelineMessages.map(\.message.id),
            visibleRange: timelineViewport.visibleRange,
            atNewest: timelineViewport.isAtNewest,
            nearNewestMessageThreshold: timelineTuning.nearNewestMessageThreshold
        )
        lastTimelineActionResult = timelineValidationWarnings.isEmpty ? "Timeline validation passed" : "Timeline validation found \(timelineValidationWarnings.count) warning(s)"
        return timelineValidationWarnings
    }

    public func copyRedactedTimelineDiagnostics() {
        let timeline = TimelineCopyFormatter.diagnostics(timelineDiagnostics())
        let attachments = attachmentDiagnostics()
        let actions = messageActionDiagnostics()
        let send = MessageSendDiagnosticsFormatter.redactedText(currentMessageSendDiagnostics())
        let attachmentText = """
        Attachment diagnostics
        queuedDrafts: \(attachments.queuedDraftCount)
        uploading: \(attachments.uploadingCount)
        failedUploads: \(attachments.failedUploadCount)
        displayed: \(attachments.displayedAttachmentCount)
        loadedPreviews: \(attachments.loadedPreviewCount)
        failedPreviews: \(attachments.failedPreviewCount)
        lastAttachmentAction: \(attachments.lastAttachmentAction ?? "-")
        Message action diagnostics
        visibleActions: \(actions.visibleActionCount)
        availableActions: \(actions.availableActionCount)
        reactionGroups: \(actions.reactionGroupCount)
        currentUserReactions: \(actions.currentUserReactionCount)
        pendingDeleteConfirmation: \(actions.hasPendingDeleteConfirmation ? "yes" : "no")
        """
        let text = Phase17MessageActions.redactedDiagnosticText(Phase6UIHelpers.safeDiagnostics(AttachmentDiagnosticsFormatter.redact(timeline + "\n" + attachmentText + "\n" + send)))
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        placeholderStatus = "Timeline diagnostics copied"
        lastTimelineActionResult = "Copied redacted diagnostics"
    }

    public func resetTimelineDiagnostics() {
        timelineValidationWarnings = []
        failedReferenceFetchMessageIDs = []
        lastAckTargetMessageID = nil
        lastAckResult = nil
        lastTimelineActionResult = nil
        placeholderStatus = "Timeline diagnostics reset"
    }

    public func updateAppLifecyclePhase(_ phase: AppLifecyclePhase) {
        guard appLifecyclePhase != phase else {
            reconcileNotificationLifecycle()
            return
        }
        appLifecyclePhase = phase
        if phase == .active {
            refreshNotificationPermissionStatus()
        }
        reconcileNotificationLifecycle()
    }

    public func refreshNotificationPermissionStatus() {
        Task { [weak self, manager = notificationPermissionManager] in
            let status = await manager.status()
            await MainActor.run {
                self?.notificationPermissionStatus = status
                self?.updateNotificationDiagnostics()
            }
        }
    }

    public func requestNotificationPermission() {
        Task { [weak self, manager = notificationPermissionManager] in
            let status = await manager.requestAuthorization()
            await MainActor.run {
                self?.notificationPermissionStatus = status
                self?.placeholderStatus = "Notification permission: \(status.rawValue)"
                self?.updateNotificationDiagnostics()
            }
        }
    }

    public func saveNotificationPreferences(_ preferences: NotificationPreferences) {
        Task { [weak self] in
            guard let self else { return }
            await self.sessionCoordinator?.updatePreferences { appPreferences in
                appPreferences.notificationPreferences = preferences.validated()
            }
            self.syncFromSessionCoordinator()
        }
    }

    public func setNotificationPreference(_ update: @escaping (inout NotificationPreferences) -> Void) {
        var preferences = notificationPreferences
        update(&preferences)
        saveNotificationPreferences(preferences)
    }

    public func setSelectedChannelMuted(_ isMuted: Bool) {
        guard let channelID = selection.channelID ?? selection.dmChannelID else { return }
        setNotificationPreference { preferences in
            var channel = preferences.preference(for: channelID)
            channel.isMuted = isMuted
            if channel.isMuted || channel.suppressNative || channel.suppressInApp {
                preferences.channelPreferences[channelID] = channel
            } else {
                preferences.channelPreferences.removeValue(forKey: channelID)
            }
        }
    }

    public func dismissNotificationBanner(_ id: String) {
        notificationBanners.removeAll { $0.id == id }
        updateNotificationDiagnostics()
    }

    public func deliverMockNotificationDemo() {
        guard let channel = selectedChannel ?? selection.dmChannelID.flatMap({ snapshot.channelsByID[$0] }) ?? snapshot.channelsByID.values.first(where: { $0.kind == .directMessage || $0.kind == .textChannel }) else {
            placeholderStatus = "No channel available for notification demo."
            return
        }
        let event = NotificationEvent(
            id: "demo-\(UUID().uuidString)",
            route: NotificationRoute(serverID: channel.serverID, channelID: channel.id, messageID: nil),
            title: "Liquid Bagel notification demo",
            body: "This is an explicit mock notification preview.",
            kind: .mention
        )
        if notificationPreferences.inAppBannersEnabled {
            notificationBanners.append(event)
        }
        Task { [deliverer = notificationDeliverer] in
            try? await deliverer.deliver(event)
        }
        placeholderStatus = "Mock notification demo delivered"
    }

    public func copyRedactedNotificationDiagnostics() {
        let text = Phase17MessageActions.redactedDiagnosticText(notificationDiagnostics.redactedText)
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        placeholderStatus = "Notification diagnostics copied"
    }

    public func openNotificationRoute(_ route: NotificationRoute) async {
        expiredNotificationRouteCount += removeExpiredQueuedNotificationRoutes()
        selectChannel(route.channelID)
        guard let messageID = route.messageID else { return }
        if selectedTimelineMessages.contains(where: { $0.message.id == messageID }) {
            timelineSelection = TimelineSelection(channelID: route.channelID, messageID: messageID, source: .notification)
            timelineViewport = viewportReducer.keepVisible(timelineViewport, messageID: messageID, reason: .jumpCommand)
            placeholderStatus = "Opened notification"
            recordNotificationRouteOutcome(.opened)
            return
        }
        guard effectiveRuntimeMode == .liveManual else {
            placeholderStatus = "Notification message is not loaded."
            recordNotificationRouteOutcome(.failed)
            return
        }
        guard effectiveSessionState == .connected,
              sessionCoordinator?.hydrationStatus.readyReceived == true
        else {
            queueNotificationRoute(route)
            placeholderStatus = "Connect manually to open this message."
            recordNotificationRouteOutcome(.queuedAwaitingManualConnect)
            return
        }
        let loaded = await messageController.loadMessagesAround(channelID: route.channelID, targetMessageID: messageID)
        if loaded, selectedTimelineMessages.contains(where: { $0.message.id == messageID }) {
            timelineSelection = TimelineSelection(channelID: route.channelID, messageID: messageID, source: .notification)
            timelineViewport = viewportReducer.keepVisible(timelineViewport, messageID: messageID, reason: .jumpCommand)
            placeholderStatus = "Opened notification"
            recordNotificationRouteOutcome(.opened)
        } else {
            placeholderStatus = loaded ? "Notification target was not returned." : "Notification target could not be loaded."
            recordNotificationRouteOutcome(.failed)
        }
    }

    public func verifyTimelineRoutes() {
        routeVerificationResult = .sourceVerified
        lastRouteVerificationResult = routeVerificationResult.summary
        placeholderStatus = "Timeline routes verified from source"
    }

    public func updateTimelineTuning(_ tuning: TimelineTuningConfiguration) {
        let validated = tuning.validated()
        timelineTuning = validated
        Task { [weak sessionCoordinator] in
            await sessionCoordinator?.updatePreferences { preferences in
                preferences.timelineTuning = validated
            }
        }
        validateTimelineState()
    }

    public func applyTimelineTuningPreset(_ preset: TimelineTuningPreset) {
        selectedTimelineTuningPreset = preset
        updateTimelineTuning(preset.configuration)
        lastTimelineActionResult = "Applied \(preset.displayName) tuning preset"
    }

    public func resetTimelineTuningToDefaults() {
        selectedTimelineTuningPreset = .conservative
        updateTimelineTuning(.defaults)
        lastTimelineActionResult = "Reset timeline tuning to defaults"
    }

    public func startTimelineCalibration() {
        let channelID = selection.channelID ?? selection.dmChannelID
        activeCalibrationRun = TimelineCalibrationRun(
            environmentID: sessionCoordinator?.preferences.selectedEnvironmentProfile.id ?? "mock",
            channelID: channelID,
            tuning: timelineTuning
        )
        recordTimelineCalibrationObservation(kind: .manualCheckpoint, note: "Calibration started")
        placeholderStatus = "Timeline calibration started"
    }

    public func stopTimelineCalibration() {
        guard let run = activeCalibrationRun else { return }
        activeCalibrationRun = run.stopped()
        placeholderStatus = "Timeline calibration stopped"
    }

    public func addTimelineCalibrationCheckpoint(note: String? = nil) {
        let explicitNote = note ?? calibrationCheckpointNote
        let redacted = TimelineCopyFormatter.redactTokenLikeStrings(explicitNote)
        recordTimelineCalibrationObservation(kind: .manualCheckpoint, note: redacted.isEmpty ? nil : redacted)
        calibrationCheckpointNote = ""
        placeholderStatus = "Calibration checkpoint recorded"
    }

    public var defaultTuningDecision: TimelineDefaultTuningDecision {
        let notes = [importedCalibrationNotes] + (activeCalibrationRun?.observations.compactMap(\.note) ?? [])
        return TimelineDefaultTuningAdvisor.decision(notes: notes, recommendation: activeCalibrationRun?.recommendedAdjustments)
    }

    public func importCalibrationNotes() {
        let redacted = TimelineCopyFormatter.redactTokenLikeStrings(importedCalibrationNotes)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        importedCalibrationNotes = redacted
        if activeCalibrationRun?.isRunning == true, !redacted.isEmpty {
            recordTimelineCalibrationObservation(kind: .manualCheckpoint, note: redacted)
        }
        placeholderStatus = redacted.isEmpty ? "No calibration notes to import" : "Calibration notes imported"
        lastTimelineActionResult = "Imported redacted calibration notes"
    }

    public func applyDefaultTuningDecision() {
        updateTimelineTuning(defaultTuningDecision.recommendedConfiguration)
        lastTimelineActionResult = "Applied default tuning decision"
    }

    public func applyTimelineCalibrationRecommendation() {
        guard let recommendation = activeCalibrationRun?.recommendedAdjustments else {
            placeholderStatus = "No calibration recommendation to apply"
            return
        }
        updateTimelineTuning(recommendation.recommendedTuning)
        lastTimelineActionResult = "Applied calibration recommendation"
    }

    public func copyRedactedTimelineCalibration() {
        guard let run = activeCalibrationRun else {
            placeholderStatus = "No calibration run to copy"
            return
        }
        let text = TimelineCopyFormatter.calibration(run)
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        placeholderStatus = "Calibration copied"
        lastTimelineActionResult = "Copied redacted calibration"
    }

    public func recordTimelineCalibrationObservation(kind: TimelineCalibrationObservationKind, note: String? = nil) {
        guard let run = activeCalibrationRun, run.isRunning else { return }
        let warnings = validateTimelineState()
        let diagnostics = timelineDiagnostics()
        var updated = run.adding(TimelineCalibrationObservation(kind: warnings.isEmpty ? kind : .warning, diagnostics: diagnostics, note: note))
        if !warnings.isEmpty {
            updated.warnings = warnings
        }
        activeCalibrationRun = updated
    }

    public func refreshLoadedMessageFind() {
        loadedMessageFindResults = loadedMessageFinder.find(
            query: loadedMessageFindQuery,
            messages: selectedTimelineMessages
        )
        channelSearchQuery = ChannelSearchQuery(text: loadedMessageFindQuery, mode: .loadedOnly)
        let results = loadedMessageFindResults.map { channelSearchResult(from: $0, mode: .loadedOnly, isLoaded: true) }
        channelSearchState = results.isEmpty ? .empty(channelSearchQuery) : .results(channelSearchQuery, results)
        selectedSearchResultID = results.first?.messageID
        refreshSearchHighlightState()
    }

    public func jumpToLoadedFindResult(_ result: LoadedMessageFindResult) {
        guard result.channelID == (selection.channelID ?? selection.dmChannelID) else { return }
        timelineSelection = TimelineSelection(channelID: result.channelID, messageID: result.messageID, source: .quickSwitcher)
        timelineViewport = viewportReducer.keepVisible(timelineViewport, messageID: result.messageID, reason: .jumpCommand)
        lastTimelineActionResult = "Jumped to loaded find result"
        recordTimelineCalibrationObservation(kind: .afterSearchJump)
    }

    public func openChannelSearch(mode: ChannelSearchMode = .loadedOnly) {
        channelSearchQuery.mode = mode
        channelSearchQuery.pinnedOnly = mode == .pinned
        isChannelSearchPresented = true
        selectedSearchResultID = channelSearchState.results.first?.messageID
        refreshSearchHighlightState()
        previousFocusTarget = focusTarget
        focusTarget = .quickSwitcher
    }

    public func closeChannelSearch() {
        isChannelSearchPresented = false
        focusTarget = previousFocusTarget
    }

    public func runChannelSearch() async {
        let query = channelSearchQuery
        let trimmed = query.trimmedText
        selectedSearchResultID = nil
        searchHighlightState = nil
        searchNavigationStatus = nil

        switch query.mode {
        case .loadedOnly:
            let found = loadedMessageFinder.find(query: trimmed, messages: selectedTimelineMessages)
            loadedMessageFindQuery = query.text
            loadedMessageFindResults = found
            let results = found.map { channelSearchResult(from: $0, mode: .loadedOnly, isLoaded: true) }
            channelSearchState = results.isEmpty ? .empty(query) : .results(query, results)
            selectedSearchResultID = results.first?.messageID
            refreshSearchHighlightState()
        case .liveChannel, .pinned:
            guard effectiveRuntimeMode == .liveManual,
                  effectiveSessionState == .connected,
                  let channelID = selection.channelID ?? selection.dmChannelID,
                  let apiClient = sessionCoordinator?.apiClient
            else {
                let message = "Live search requires manual connection."
                channelSearchState = .failed(query, message)
                remoteSearchStatus = message
                return
            }
            guard query.mode == .pinned || !trimmed.isEmpty else {
                let message = "Enter search text or choose pinned in this channel."
                channelSearchState = .failed(query, message)
                remoteSearchStatus = message
                return
            }
            channelSearchState = .searching(query)
            do {
                let messages = try await apiClient.searchMessages(
                    channelID: channelID,
                    request: ChannelMessageSearchRequest(
                        query: query.mode == .pinned ? nil : trimmed,
                        pinned: query.mode == .pinned ? true : (query.pinnedOnly ? true : nil),
                        limit: 25,
                        sort: query.mode == .pinned ? .latest : .relevance
                    )
                )
                let loadedIDs = Set(selectedTimelineMessages.map(\.message.id))
                let results = messages.map { message in
                    channelSearchResult(from: message, mode: query.mode, matching: trimmed, loadedIDs: loadedIDs)
                }
                channelSearchState = results.isEmpty ? .empty(query) : .results(query, results)
                selectedSearchResultID = results.first?.messageID
                refreshSearchHighlightState()
                remoteSearchResults = results.map {
                    LoadedMessageFindResult(messageID: $0.messageID, channelID: $0.channelID, authorID: $0.authorID, createdAt: $0.createdAt, snippet: $0.snippet)
                }
                remoteSearchStatus = results.isEmpty ? "No selected-channel results." : "\(results.count) selected-channel result(s)."
                lastTimelineActionResult = "Selected-channel search completed"
            } catch {
                let message = "Selected-channel search failed: \(error.userFacingMessage)"
                channelSearchState = .failed(query, message)
                remoteSearchResults = []
                remoteSearchStatus = message
                lastTimelineActionResult = "Selected-channel search failed"
            }
        }
    }

    public var selectedSearchResult: ChannelSearchResult? {
        let results = channelSearchState.results
        guard let selectedSearchResultID else { return results.first }
        return results.first { $0.messageID == selectedSearchResultID } ?? results.first
    }

    public var searchResultCountLabel: String? {
        guard let state = searchHighlightState, !state.isEmpty else { return nil }
        return Phase13Accessibility.searchResultCountLabel(
            mode: state.mode,
            currentIndex: state.indexOfCurrent(),
            total: state.resultIDs.count,
            loaded: state.loadedResultIDs.count,
            unloaded: state.unloadedResultIDs.count
        )
    }

    public func searchHighlightStatus(for messageID: MessageID) -> String? {
        Phase13Accessibility.searchHighlightLabel(
            isHighlighted: searchHighlightState?.contains(messageID) == true,
            isCurrent: searchHighlightState?.isCurrent(messageID) == true
        )
    }

    public func isSearchHighlighted(_ messageID: MessageID) -> Bool {
        searchHighlightState?.contains(messageID) == true
    }

    public func isCurrentSearchResult(_ messageID: MessageID) -> Bool {
        searchHighlightState?.contains(messageID) == true && searchHighlightState?.isCurrent(messageID) == true
    }

    public func clearSearchHighlights() {
        channelSearchState = .idle
        selectedSearchResultID = nil
        searchHighlightState = nil
        searchNavigationStatus = nil
        loadedMessageFindResults = []
        remoteSearchResults = []
        remoteSearchStatus = nil
        lastTimelineActionResult = "Cleared search highlights"
    }

    public func reconcileSearchHighlightsForSelectedChannel() {
        let activeChannelID = selection.channelID ?? selection.dmChannelID
        guard searchHighlightState?.channelID == activeChannelID else {
            searchHighlightState = nil
            selectedSearchResultID = nil
            searchNavigationStatus = nil
            return
        }
        refreshSearchHighlightState()
    }

    private func refreshSearchHighlightState() {
        guard let query = channelSearchState.query else {
            searchHighlightState = nil
            return
        }
        let activeChannelID = selection.channelID ?? selection.dmChannelID
        let loadedIDs = Set(selectedTimelineMessages.map(\.message.id))
        searchHighlightState = TimelineSearchHighlightState.make(
            channelID: activeChannelID,
            query: query,
            results: channelSearchState.results,
            currentResultID: selectedSearchResultID,
            loadedMessageIDs: loadedIDs
        )
        if selectedSearchResultID == nil {
            selectedSearchResultID = searchHighlightState?.currentResultID
        }
    }

    private func scrollToSearchResult(_ result: ChannelSearchResult) {
        guard result.channelID == (selection.channelID ?? selection.dmChannelID) else { return }
        timelineSelection = TimelineSelection(channelID: result.channelID, messageID: result.messageID, source: .quickSwitcher)
        timelineViewport = viewportReducer.keepVisible(timelineViewport, messageID: result.messageID, reason: .jumpCommand)
    }

    public func selectSearchResult(_ result: ChannelSearchResult) {
        selectedSearchResultID = result.messageID
        refreshSearchHighlightState()
        let isLoadedNow = selectedTimelineMessages.contains { $0.message.id == result.messageID }
        searchNavigationStatus = isLoadedNow ? nil : "Result outside loaded range."
        if isLoadedNow {
            scrollToSearchResult(result)
        }
    }

    public func selectAdjacentSearchResult(_ delta: Int) {
        let results = channelSearchState.results
        guard !results.isEmpty else { return }
        let current = selectedSearchResultID.flatMap { id in results.firstIndex { $0.messageID == id } } ?? 0
        let next = (current + delta + results.count) % results.count
        selectSearchResult(results[next])
    }

    public func jumpToSelectedSearchResult() {
        guard let result = selectedSearchResult else { return }
        selectSearchResult(result)
        guard result.channelID == (selection.channelID ?? selection.dmChannelID) else { return }
        if selectedTimelineMessages.contains(where: { $0.message.id == result.messageID }) {
            scrollToSearchResult(result)
            searchNavigationStatus = "Jumped to search result"
            lastTimelineActionResult = "Jumped to search result"
            recordTimelineCalibrationObservation(kind: .afterSearchJump)
        } else {
            searchNavigationStatus = "Result outside loaded range."
            lastTimelineActionResult = "Search result outside loaded range"
        }
    }

    public func loadAroundSelectedSearchResult() async {
        guard let result = selectedSearchResult else { return }
        await loadAroundSearchResult(result)
    }

    public func loadAroundSearchResult(_ result: ChannelSearchResult) async {
        guard result.channelID == (selection.channelID ?? selection.dmChannelID) else { return }
        guard routeVerificationResult.aroundMessageFetch == .supported || lastRouteVerificationResult != nil else {
            searchNavigationStatus = "Around-message route is not verified."
            return
        }
        let loaded = await messageController.loadMessagesAround(channelID: result.channelID, targetMessageID: result.messageID)
        if loaded, selectedTimelineMessages.contains(where: { $0.message.id == result.messageID }) {
            timelineSelection = TimelineSelection(channelID: result.channelID, messageID: result.messageID, source: .quickSwitcher)
            timelineViewport = viewportReducer.keepVisible(timelineViewport, messageID: result.messageID, reason: .jumpCommand)
            searchNavigationStatus = "Loaded around result"
            lastTimelineActionResult = "Loaded around search result"
            markSearchResultLoaded(result.messageID)
            refreshSearchHighlightState()
            recordTimelineCalibrationObservation(kind: .afterSearchJump)
        } else if loaded {
            searchNavigationStatus = "Loaded around result, but target was not returned."
            lastTimelineActionResult = "Around-message fetch did not include target"
        } else {
            searchNavigationStatus = "Load around result failed."
            lastTimelineActionResult = "Load around search result failed"
        }
    }

    public func loadAroundMessage(_ messageID: MessageID) async {
        guard let channelID = selection.channelID ?? selection.dmChannelID else { return }
        let anchor = timelineViewport.visibleRange?.firstVisibleMessageID ?? selectedTimelineMessages.first?.message.id
        let loaded = await messageController.loadMessagesAround(channelID: channelID, targetMessageID: messageID)
        if loaded {
            if let anchor {
                timelineViewport = viewportReducer.keepVisible(timelineViewport, messageID: anchor, reason: .loadOlder)
            }
            lastTimelineActionResult = "Loaded messages around target"
            recordTimelineCalibrationObservation(kind: .afterLoadOlder)
        } else {
            lastTimelineActionResult = "Around-message fetch unavailable or failed"
        }
    }

    public func runSelectedChannelSearch() async {
        guard effectiveRuntimeMode == .liveManual,
              effectiveSessionState == .connected,
              let channelID = selection.channelID ?? selection.dmChannelID,
              let apiClient = sessionCoordinator?.apiClient
        else {
            remoteSearchStatus = "Connect Live Manual before searching the selected channel."
            remoteSearchResults = []
            return
        }
        let query = remoteSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard remoteSearchPinnedOnly || !query.isEmpty else {
            remoteSearchStatus = "Enter search text or choose pinned only."
            remoteSearchResults = []
            return
        }
        do {
            let messages = try await apiClient.searchMessages(
                channelID: channelID,
                request: ChannelMessageSearchRequest(
                    query: remoteSearchPinnedOnly ? nil : query,
                    pinned: remoteSearchPinnedOnly ? true : nil,
                    limit: 25,
                    sort: remoteSearchPinnedOnly ? .latest : .relevance
                )
            )
            let loadedIDs = Set(selectedTimelineMessages.map(\.message.id))
            remoteSearchResults = messages.map {
                LoadedMessageFindResult(
                    messageID: $0.id,
                    channelID: $0.channelID,
                    authorID: $0.authorID,
                    createdAt: $0.createdAt,
                    snippet: loadedIDs.contains($0.id) ? LoadedMessageFinder.snippet($0.content ?? "Message", matching: query.isEmpty ? ($0.content ?? "") : query) : "Result outside loaded range"
                )
            }
            remoteSearchStatus = messages.isEmpty ? "No selected-channel results." : "\(messages.count) selected-channel result(s)."
            lastTimelineActionResult = "Selected-channel search completed"
            channelSearchQuery = ChannelSearchQuery(text: remoteSearchQuery, mode: remoteSearchPinnedOnly ? .pinned : .liveChannel, pinnedOnly: remoteSearchPinnedOnly)
            let phase13Results = messages.map { channelSearchResult(from: $0, mode: remoteSearchPinnedOnly ? .pinned : .liveChannel, matching: query, loadedIDs: loadedIDs) }
            channelSearchState = phase13Results.isEmpty ? .empty(channelSearchQuery) : .results(channelSearchQuery, phase13Results)
            selectedSearchResultID = phase13Results.first?.messageID
            refreshSearchHighlightState()
        } catch {
            remoteSearchResults = []
            remoteSearchStatus = "Selected-channel search failed: \(error.userFacingMessage)"
            lastTimelineActionResult = "Selected-channel search failed"
            searchHighlightState = nil
        }
    }

    private func channelSearchResult(from result: LoadedMessageFindResult, mode: ChannelSearchMode, isLoaded: Bool) -> ChannelSearchResult {
        ChannelSearchResult(
            messageID: result.messageID,
            channelID: result.channelID,
            authorID: result.authorID,
            authorDisplayName: snapshot.usersByID[result.authorID]?.displayName ?? snapshot.usersByID[result.authorID]?.username,
            createdAt: result.createdAt,
            snippet: result.snippet,
            mode: mode,
            isLoaded: isLoaded,
            safeStatus: isLoaded ? nil : "Result outside loaded range"
        )
    }

    private func channelSearchResult(from message: Message, mode: ChannelSearchMode, matching query: String, loadedIDs: Set<MessageID>) -> ChannelSearchResult {
        let isLoaded = loadedIDs.contains(message.id)
        let snippet = isLoaded ? LoadedMessageFinder.snippet(message.content ?? "Message", matching: query.isEmpty ? (message.content ?? "") : query) : "Result outside loaded range"
        return ChannelSearchResult(
            messageID: message.id,
            channelID: message.channelID,
            authorID: message.authorID,
            authorDisplayName: snapshot.usersByID[message.authorID]?.displayName ?? snapshot.usersByID[message.authorID]?.username,
            createdAt: message.createdAt,
            snippet: snippet,
            mode: mode,
            isPinned: message.isPinned || mode == .pinned,
            isLoaded: isLoaded,
            safeStatus: isLoaded ? nil : "Result outside loaded range"
        )
    }

    private func markSearchResultLoaded(_ messageID: MessageID) {
        guard case let .results(query, results) = channelSearchState else { return }
        channelSearchState = .results(query, results.map { result in
            guard result.messageID == messageID else { return result }
            var updated = result
            updated.isLoaded = true
            updated.safeStatus = nil
            return updated
        })
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
        guard let selectedTimelineMessage else {
            placeholderStatus = "No selected message to copy."
            return
        }
        Task { [weak self] in
            await self?.copyMessageText(selectedTimelineMessage.message)
        }
    }

    public func copySelectedMessageID() {
        guard let selectedTimelineMessage else {
            placeholderStatus = "No selected message to copy."
            return
        }
        Task { [weak self] in
            await self?.copyMessageID(selectedTimelineMessage)
        }
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
        processNotificationDiff(previous: oldSnapshot, current: snapshot)
        previousSnapshot = snapshot
        restoreOrValidateSelection()
        acknowledgeSelectedChannel()
        scheduleSelectedChannelLoad()
        reconcileTimelineSelection()
        quickSwitcherViewModel.update(snapshot: snapshot, selection: selection)
        updateDockBadge()
        updateNotificationDiagnostics()
        replayQueuedNotificationRoutesIfReady()
        if effectiveRuntimeMode == .liveManual, effectiveSessionState == .connected {
            loadIdentityImagesForCurrentSnapshot()
        }
    }

    private func applyRealtimeDeleteDiff(previous: RealtimeSnapshot, current: RealtimeSnapshot) {
        for (channelID, oldMessages) in previous.messagesByChannelID {
            let currentIDs = Set((current.messagesByChannelID[channelID] ?? []).map(\.id))
            for message in oldMessages where !currentIDs.contains(message.id) {
                messageController.removeMessage(channelID: channelID, messageID: message.id)
            }
        }
    }

    private static func messageIDMap(_ snapshot: RealtimeSnapshot) -> [ChannelID: Set<MessageID>] {
        snapshot.messagesByChannelID.mapValues { Set($0.map(\.id)) }
    }

    private var notificationPreferences: NotificationPreferences {
        sessionCoordinator?.preferences.notificationPreferences ?? .defaults
    }

    private var isActiveChannelVisibleForNotifications: Bool {
        appLifecyclePhase.selectedChannelIsVisible && (selection.channelID != nil || selection.dmChannelID != nil)
    }

    private func processNotificationDiff(previous: RealtimeSnapshot, current: RealtimeSnapshot) {
        guard effectiveRuntimeMode == .liveManual,
              sessionCoordinator?.hydrationStatus.readyReceived == true
        else {
            seenNotificationMessageIDsByChannelID = Self.messageIDMap(current)
            return
        }

        let context = NotificationClassificationContext(
            runtimeMode: effectiveRuntimeMode,
            currentUserID: currentUserID,
            activeChannelID: selection.channelID ?? selection.dmChannelID,
            isActiveChannelVisible: isActiveChannelVisibleForNotifications,
            preferences: notificationPreferences,
            snapshot: current
        )

        for (channelID, messages) in current.messagesByChannelID {
            let previouslySeen = seenNotificationMessageIDsByChannelID[channelID] ?? Set((previous.messagesByChannelID[channelID] ?? []).map(\.id))
            for message in messages where !previouslySeen.contains(message.id) {
                handleNotificationClassification(NotificationClassifier.classify(message: message, context: context))
            }
        }
        seenNotificationMessageIDsByChannelID = Self.messageIDMap(current)
    }

    private func handleNotificationClassification(_ classification: NotificationClassification) {
        var diagnostics = notificationDiagnostics
        switch classification {
        case let .suppress(reason):
            diagnostics.suppressedCount += 1
            diagnostics.lastSuppressionReason = reason
            notificationDiagnostics = diagnostics
        case let .deliver(event):
            guard !deliveredNotificationIDs.contains(event.id) else { return }
            deliveredNotificationIDs.insert(event.id)
            diagnostics.deliveredCount += 1
            diagnostics.lastEventKind = event.kind
            notificationDiagnostics = diagnostics
            let channelPreference = notificationPreferences.preference(for: event.route.channelID)
            if notificationPreferences.inAppBannersEnabled && !channelPreference.suppressInApp {
                notificationBanners.append(event)
                if notificationBanners.count > 3 {
                    notificationBanners.removeFirst(notificationBanners.count - 3)
                }
            }
            if appLifecyclePhase != .active,
               notificationPreferences.nativeNotificationsEnabled,
               !channelPreference.suppressNative,
               notificationPermissionStatus.allowsDelivery {
                Task { [deliverer = notificationDeliverer] in
                    try? await deliverer.deliver(event)
                }
            }
        }
    }

    private func installNotificationRouteHandler() {
        notificationRouteCenter.setHandler { [weak self] route in
            Task { @MainActor [weak self] in
                await self?.openNotificationRoute(route)
            }
        }
        refreshNotificationPermissionStatus()
    }

    private func installAppLifecycleHandler() {
        appLifecycleCenter.setHandler { [weak self] phase in
            self?.updateAppLifecyclePhase(phase)
        }
    }

    private func reconcileNotificationLifecycle() {
        expiredNotificationRouteCount += removeExpiredQueuedNotificationRoutes()
        pruneNotificationBanners()
        updateDockBadge()
        updateNotificationDiagnostics()
    }

    private func pruneNotificationBanners(now: Date = Date()) {
        notificationBanners.removeAll { now.timeIntervalSince($0.createdAt) > 300 }
        if notificationBanners.count > 3 {
            notificationBanners.removeFirst(notificationBanners.count - 3)
        }
    }

    private func queueNotificationRoute(_ route: NotificationRoute, queuedAt: Date = Date()) {
        let queued = QueuedNotificationRoute(route: route, queuedAt: queuedAt)
        queuedNotificationRoutes.removeAll { $0.id == queued.id }
        queuedNotificationRoutes.append(queued)
        queuedNotificationRoutes = Array(queuedNotificationRoutes.suffix(10))
        updateNotificationDiagnostics()
    }

    @discardableResult
    private func removeExpiredQueuedNotificationRoutes(now: Date = Date()) -> Int {
        let before = queuedNotificationRoutes.count
        queuedNotificationRoutes.removeAll { $0.isExpired(at: now) }
        return before - queuedNotificationRoutes.count
    }

    private func replayQueuedNotificationRoutesIfReady() {
        expiredNotificationRouteCount += removeExpiredQueuedNotificationRoutes()
        guard effectiveRuntimeMode == .liveManual,
              effectiveSessionState == .connected,
              sessionCoordinator?.hydrationStatus.readyReceived == true,
              !queuedNotificationRoutes.isEmpty
        else {
            updateNotificationDiagnostics()
            return
        }
        let routes = queuedNotificationRoutes
        queuedNotificationRoutes.removeAll()
        updateNotificationDiagnostics()
        for queued in routes {
            Task { @MainActor [weak self] in
                await self?.openNotificationRoute(queued.route)
            }
        }
    }

    private func recordNotificationRouteOutcome(_ outcome: NotificationRouteOutcome) {
        notificationDiagnostics.lastRouteOutcome = outcome
        updateNotificationDiagnostics()
    }

    private func updateDockBadge() {
        let counts = NotificationBadgeCalculator.counts(snapshot: snapshot, preferences: notificationPreferences, localReadStates: localReadStates)
        let value = counts.badgeValue(mode: notificationPreferences.dockBadge)
        Task { [dockBadgeManager] in
            await dockBadgeManager.setBadgeCount(value)
        }
    }

    private func updateNotificationDiagnostics() {
        let counts = NotificationBadgeCalculator.counts(snapshot: snapshot, preferences: notificationPreferences, localReadStates: localReadStates)
        notificationDiagnostics.permissionStatus = notificationPermissionStatus
        notificationDiagnostics.nativeEnabled = notificationPreferences.nativeNotificationsEnabled
        notificationDiagnostics.inAppEnabled = notificationPreferences.inAppBannersEnabled
        notificationDiagnostics.dockBadgeValue = counts.badgeValue(mode: notificationPreferences.dockBadge)
        notificationDiagnostics.lifecyclePhase = appLifecyclePhase
        notificationDiagnostics.activeChannelVisible = isActiveChannelVisibleForNotifications
        notificationDiagnostics.queuedRouteCount = queuedNotificationRoutes.count + notificationRouteCenter.queuedRouteCount()
        notificationDiagnostics.expiredRouteCount = expiredNotificationRouteCount
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
        let newest = timelineViewport.isAtNewest
            ? (timelineViewport.visibleRange?.lastVisibleMessageID ?? currentMessages.last?.message.id ?? unread?.lastMessageID)
            : (timelineViewport.visibleRange?.lastVisibleMessageID ?? localReadStates[channelID]?.lastReadMessageID)
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
        updateDockBadge()
        updateNotificationDiagnostics()
    }

    private func scheduleLiveAckIfNeeded(channelID: ChannelID) {
        guard effectiveRuntimeMode == .liveManual,
              effectiveSessionState == .connected,
              timelineViewport.isAtNewest,
              let messageID = timelineViewport.visibleRange?.lastVisibleMessageID ?? messageController.state(for: channelID).timelineMessages.last?.message.id ?? snapshot.unreadsByChannelID[channelID]?.lastMessageID,
              lastAckedMessageByChannelID[channelID] != messageID
        else {
            return
        }
        lastAckTargetMessageID = messageID
        lastAckResult = "Scheduled"
        ackTask?.cancel()
        ackTask = Task { [weak self, sender = channelAckSender] in
            let delay = await MainActor.run { self?.timelineTuning.ackDebounceMilliseconds ?? TimelineTuningConfiguration.defaults.ackDebounceMilliseconds }
            try? await Task.sleep(for: .milliseconds(delay))
            do {
                try await sender.ackChannel(channelID: channelID, messageID: messageID)
                await MainActor.run {
                    self?.lastAckedMessageByChannelID[channelID] = messageID
                    self?.lastAckResult = "Sent"
                    self?.recordTimelineCalibrationObservation(kind: .afterAck)
                    if var state = self?.localReadStates[channelID] {
                        state.mentionCount = 0
                        self?.localReadStates[channelID] = state
                    }
                    self?.updateDockBadge()
                    self?.updateNotificationDiagnostics()
                }
            } catch {
                await MainActor.run {
                    self?.lastAckResult = "Failed"
                    self?.messageActionStatus = "Read acknowledgement failed: \(error.userFacingMessage)"
                }
            }
        }
    }

    private func resolveReferenceIfNeeded(channelID: ChannelID, messageID: MessageID) {
        guard resolvedReferencesByChannelID[channelID]?[messageID] == nil,
              referenceFetchTasks[messageID] == nil
        else {
            return
        }
        messageController.markReferenceFetchStarted(channelID: channelID, messageID: messageID)
        referenceFetchTasks[messageID] = Task { [weak self, resolver = messageReferenceResolver] in
            let resolution: MessageReferenceResolution
            do {
                resolution = try await resolver.resolveReference(channelID: channelID, messageID: messageID)
            } catch {
                resolution = .unavailable(error.userFacingMessage)
            }
            await MainActor.run {
                guard let self else { return }
                var channelReferences = self.resolvedReferencesByChannelID[channelID] ?? [:]
                channelReferences[messageID] = resolution
                self.resolvedReferencesByChannelID[channelID] = channelReferences
                switch resolution {
                case .loaded:
                    self.failedReferenceFetchMessageIDs.remove(messageID)
                default:
                    self.failedReferenceFetchMessageIDs.insert(messageID)
                }
                self.referenceFetchTasks[messageID] = nil
                self.messageController.markReferenceFetchFinished(channelID: channelID, messageID: messageID)
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
        case .openQuickSwitcher, .closeTransientUI, .refresh, .openAccountSettings, .openConnectionSettings, .openNotificationSettings, .toggleMemberPanel, .jumpToHome, .jumpToFriends, .jumpToAddFriend, .jumpToDiscover, .focusTimeline, .copyTimelineDiagnostics, .resetTimelineTuningDefault:
            return true
        case .openChannelSearch, .openLoadedMessageFind:
            return selectedChannel != nil || selection.dmChannelID != nil
        case .openLiveChannelSearch:
            return (selectedChannel != nil || selection.dmChannelID != nil) && effectiveRuntimeMode == .liveManual && effectiveSessionState == .connected
        case .openPinnedChannelSearch:
            return selectedChannel != nil || selection.dmChannelID != nil
        case .selectNextSearchResult, .selectPreviousSearchResult, .jumpToSelectedSearchResult:
            return !channelSearchState.results.isEmpty
        case .loadAroundSelectedSearchResult:
            return selectedSearchResult.map { result in
                selectedTimelineMessages.contains { $0.message.id == result.messageID } == false
            } == true && routeVerificationResult.aroundMessageFetch == .supported
        case .clearSearchHighlights:
            return searchHighlightState != nil || !channelSearchState.results.isEmpty
        case .startTimelineCalibration:
            return isDeveloperControlsEnabled
        case .addTimelineCalibrationCheckpoint:
            return isDeveloperControlsEnabled && activeCalibrationRun?.isRunning == true
        case .applyTimelineCalibrationRecommendation:
            return isDeveloperControlsEnabled && activeCalibrationRun?.recommendedAdjustments != nil
        case .importCalibrationNotes:
            return isDeveloperControlsEnabled && !importedCalibrationNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .copyTimelineCalibration:
            return isDeveloperControlsEnabled && activeCalibrationRun != nil
        case .focusComposer:
            return selectedChannel != nil || selection.dmChannelID != nil
        case .reconnect:
            return sessionCoordinator?.hasSavedCredential == true && !isConnecting
        case .disconnect:
            return isDisconnectable
        case .resetToMock:
            return isDeveloperControlsEnabled && (effectiveRuntimeMode != .mock || effectiveConnectionState != .idle)
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
            return !isTextEntryFocused && selectedTimelineMessage.map { isMessageActionAvailable(.copyText, for: $0) } == true
        case .copySelectedMessageID:
            return !isTextEntryFocused && selectedTimelineMessage.map { isMessageActionAvailable(.copyMessageID, for: $0) } == true
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
            return isDeveloperControlsEnabled ? "Already using preview data." : "Developer controls are disabled."
        case .selectServer:
            return "That server shortcut has no visible server."
        case .selectChannel:
            return "That channel is unavailable."
        case .selectNextChannel, .selectPreviousChannel, .selectNextUnreadChannel, .selectPreviousUnreadChannel, .selectNextMessage, .selectPreviousMessage, .jumpToNewestMessage, .jumpToFirstUnreadMessage:
            return isTextEntryFocused ? "Keyboard navigation is paused while typing." : "No selectable target."
        case .openChannelSearch, .openLoadedMessageFind, .openLiveChannelSearch, .openPinnedChannelSearch:
            if command == .openLiveChannelSearch { return "Live search requires manual connection." }
            return "Select a channel before searching."
        case .selectNextSearchResult, .selectPreviousSearchResult, .jumpToSelectedSearchResult:
            return "No search result is selected."
        case .loadAroundSelectedSearchResult:
            return routeVerificationResult.aroundMessageFetch == .supported ? "Selected result is already loaded." : "Around-message route is not verified."
        case .clearSearchHighlights:
            return "No search highlights are active."
        case .startTimelineCalibration, .addTimelineCalibrationCheckpoint, .applyTimelineCalibrationRecommendation, .importCalibrationNotes, .copyTimelineCalibration:
            return isDeveloperControlsEnabled ? "Start a calibration run first." : "Developer controls are disabled."
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
        case .openNotificationSettings:
            showNotificationSettings()
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
        case .jumpToFriends:
            openFriends(tab: .online)
        case .jumpToAddFriend:
            openFriends(tab: .addFriend)
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
        case .openChannelSearch:
            openChannelSearch(mode: .loadedOnly)
        case .openLoadedMessageFind:
            openChannelSearch(mode: .loadedOnly)
        case .openLiveChannelSearch:
            openChannelSearch(mode: .liveChannel)
        case .openPinnedChannelSearch:
            openChannelSearch(mode: .pinned)
        case .selectNextSearchResult:
            selectAdjacentSearchResult(1)
        case .selectPreviousSearchResult:
            selectAdjacentSearchResult(-1)
        case .jumpToSelectedSearchResult:
            jumpToSelectedSearchResult()
        case .loadAroundSelectedSearchResult:
            Task { [weak self] in await self?.loadAroundSelectedSearchResult() }
        case .clearSearchHighlights:
            clearSearchHighlights()
        case .startTimelineCalibration:
            startTimelineCalibration()
        case .addTimelineCalibrationCheckpoint:
            addTimelineCalibrationCheckpoint()
        case .applyTimelineCalibrationRecommendation:
            applyTimelineCalibrationRecommendation()
        case .resetTimelineTuningDefault:
            resetTimelineTuningToDefaults()
        case .importCalibrationNotes:
            importCalibrationNotes()
        case .copyTimelineCalibration:
            copyRedactedTimelineCalibration()
        case .copyTimelineDiagnostics:
            copyRedactedTimelineDiagnostics()
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
            } else if isChannelSearchPresented {
                closeChannelSearch()
            } else if inlineEditState != nil {
                cancelInlineEdit()
            } else if searchHighlightState != nil {
                clearSearchHighlights()
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

        let permissions: Permissions = [.viewChannel, .readMessageHistory, .sendMessage, .uploadFiles, .react]
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
    @Environment(\.scenePhase) private var scenePhase
    @State private var sessionCoordinator: AppSessionCoordinator
    @State private var viewModel: MainShellViewModel

    public init(
        viewModel: MainShellViewModel = MainShellViewModel(snapshot: RealtimeSnapshot(), runtimeMode: .liveManual, sessionState: .signedOut, currentUser: nil),
        sessionCoordinator: AppSessionCoordinator = AppSessionCoordinator()
    ) {
        _sessionCoordinator = State(initialValue: sessionCoordinator)
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        MainShellView(viewModel: viewModel)
            .task {
                viewModel.attachSessionCoordinator(sessionCoordinator)
                await sessionCoordinator.startLiveFirstSession()
                viewModel.syncFromSessionCoordinator()
            }
            .onChange(of: scenePhase) { _, phase in
                viewModel.updateAppLifecyclePhase(AppLifecyclePhase(phase))
            }
    }
}

private extension AppLifecyclePhase {
    init(_ phase: ScenePhase) {
        switch phase {
        case .active:
            self = .active
        case .inactive:
            self = .inactive
        case .background:
            self = .background
        @unknown default:
            self = .inactive
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
        .sheet(isPresented: $viewModel.isChannelSearchPresented) {
            ChannelSearchPanel(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.isCredentialSetupPresented) {
            AccountConnectionSettingsView(viewModel: viewModel)
        }
        .sheet(item: $viewModel.attachmentPreview, onDismiss: {
            viewModel.closeAttachmentPreview()
        }) { attachment in
            AttachmentPreviewSheet(
                preview: attachment,
                showDebug: viewModel.isDeveloperControlsEnabled,
                onDownload: {
                    Task { await viewModel.downloadAttachment(attachment.item) }
                },
                onOpenExternally: {
                    Task { await viewModel.openAttachmentExternally(attachment.item) }
                },
                onRetry: {
                    Task { await viewModel.retryAttachmentPreview(attachment.item) }
                }
            )
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
        .confirmationDialog(
            viewModel.pendingRelationshipAction?.confirmationTitle ?? "Confirm relationship action?",
            isPresented: Binding(
                get: { viewModel.pendingRelationshipAction != nil },
                set: { if !$0 { viewModel.pendingRelationshipAction = nil } }
            )
        ) {
            if let action = viewModel.pendingRelationshipAction {
                Button(action.buttonTitle, role: action.isDestructive ? .destructive : nil) {
                    Task { await viewModel.confirmPendingRelationshipAction() }
                }
            }
            Button("Cancel", role: .cancel) {
                viewModel.pendingRelationshipAction = nil
            }
        } message: {
            Text("Liquid Bagel will perform this friend or block action only after this confirmation.")
        }
        .overlay(alignment: .bottom) {
            if let status = viewModel.placeholderStatus ?? viewModel.relationshipActionStatus ?? viewModel.messageActionStatus ?? viewModel.composerError ?? viewModel.sessionCoordinator?.lastErrorMessage {
                Text(status)
                    .font(.caption)
                    .padding(.horizontal, StoatSpacing.medium)
                    .padding(.vertical, StoatSpacing.small)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, StoatSpacing.medium)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .topTrailing) {
            VStack(alignment: .trailing, spacing: StoatSpacing.small) {
                ForEach(viewModel.notificationBanners) { event in
                    Button {
                        Task { await viewModel.openNotificationRoute(event.route) }
                        viewModel.dismissNotificationBanner(event.id)
                    } label: {
                        VStack(alignment: .leading, spacing: StoatSpacing.xSmall) {
                            HStack {
                                Label(event.title, systemImage: event.kind == .mention ? "at" : "bell")
                                    .font(.caption.weight(.semibold))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(event.body)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .frame(width: 280, alignment: .leading)
                        .padding(StoatSpacing.small)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: StoatRadius.small, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Dismiss") { viewModel.dismissNotificationBanner(event.id) }
                    }
                }
            }
            .padding(StoatSpacing.medium)
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
            if viewModel.isDeveloperControlsEnabled {
                Button("Open Preview Data") {
                    Task { await viewModel.resetToMock() }
                }
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
        case .idle: viewModel.effectiveRuntimeMode == .mock ? "Preview" : "Idle"
        case .ready: "Ready"
        case .connecting, .authenticating, .authenticated, .connected: "Connecting"
        case .reconnecting: "Reconnecting"
        case .disconnected: "Offline"
        case .failed: "Failed"
        }
    }

    private var runtimeModeText: String {
        switch viewModel.effectiveRuntimeMode {
        case .mock: "Preview Data"
        case .liveManual: "Live Manual"
        }
    }

    private var sessionStateText: String {
        switch viewModel.effectiveSessionState {
        case .mock: "Preview Data"
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

private struct AttachmentPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let preview: AttachmentPreviewSheetItem
    let showDebug: Bool
    let onDownload: () -> Void
    let onOpenExternally: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: StoatSpacing.medium) {
            HStack {
                Label(preview.item.displayName, systemImage: preview.item.kind.systemImage)
                    .font(.headline)
                Spacer()
                Text(AttachmentDisplayFormatting.formattedSize(preview.item.byteCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            previewBody
                .frame(minWidth: 420, minHeight: 280)
            VStack(alignment: .leading, spacing: StoatSpacing.xSmall) {
                Text(metadataLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if showDebug, let id = preview.debugFileID {
                    Text("File ID \(id)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
                if let status = preview.statusMessage {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: StoatSpacing.small) {
                if preview.item.source.isRemoteLoadable || preview.data != nil {
                    Button {
                        onDownload()
                    } label: {
                        Label("Save As", systemImage: "square.and.arrow.down")
                    }
                }
                if preview.localFile != nil || preview.data != nil {
                    Button {
                        onOpenExternally()
                    } label: {
                        Label("Open Externally", systemImage: "arrow.up.forward.app")
                    }
                }
                if case .failed = preview.item.previewState {
                    Button {
                        onRetry()
                    } label: {
                        Label("Retry Preview", systemImage: "arrow.clockwise")
                    }
                }
                Spacer()
            }
            .buttonStyle(GlassButtonStyle())
        }
        .padding(StoatSpacing.large)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(StoatAccessibility.attachmentLabel(filename: preview.item.displayName, kind: preview.item.kind.label, size: AttachmentDisplayFormatting.formattedSize(preview.item.byteCount), state: preview.item.previewState.safeLabel))
    }

    @ViewBuilder private var previewBody: some View {
        #if canImport(AppKit)
        if let data = preview.data, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let url = preview.localFile,
                  preview.item.kind == .image,
                  let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            genericPreview
        }
        #else
        genericPreview
        #endif
    }

    private var genericPreview: some View {
        VStack(spacing: StoatSpacing.small) {
            Image(systemName: preview.item.kind.systemImage)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(genericPreviewText)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(preview.item.displayName)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: StoatRadius.panel, style: .continuous))
    }

    private var metadataLine: String {
        "\(preview.item.kind.label) · \(preview.item.contentType ?? "unknown type") · \(AttachmentDisplayFormatting.formattedSize(preview.item.byteCount))"
    }

    private var genericPreviewText: String {
        switch preview.item.previewState {
        case .loading:
            return "Loading preview"
        case let .failed(message):
            return message
        case let .unsupported(message):
            return message
        case .notLoaded:
            return preview.item.kind.isPreviewable ? "Preview not loaded" : "Preview unavailable"
        case .readyLocal, .readyRemote:
            return preview.item.kind == .image ? "Image preview unavailable" : "File details"
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

                    if viewModel.isDeveloperControlsEnabled {
                        Button("Open Preview Data") {
                            Task { await viewModel.resetToMock() }
                        }
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
                HStack {
                    Button("Reload Visible Images") {
                        viewModel.reloadVisibleImages()
                    }
                    Button("Clear Image Memory Cache") {
                        Task { await viewModel.clearImageMemoryCache() }
                    }
                }
                LabeledContent("Inline images", value: "\(viewModel.inlineImagePreviewPolicy)")
                LabeledContent("Loaded identity/media images", value: "\(viewModel.loadedImageResources.count)")
                if let last = viewModel.lastImageResourceAction {
                    Text(last)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
        case .mock: "Preview Data"
        case .liveManual: "Live Manual"
        }
    }

    private var sessionStateText: String {
        switch viewModel.effectiveSessionState {
        case .mock: "Preview Data"
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
                        ServerRailItem(
                            title: server.name,
                            isSelected: viewModel.selection.serverID == server.id,
                            unreadCount: unread,
                            mentionCount: mentions,
                            imageData: viewModel.imageData(for: server.icon, kind: .serverIcon)
                        ) {
                            viewModel.selectServer(server.id)
                        }
                        .onAppear {
                            viewModel.loadImageResource(for: server.icon, kind: .serverIcon)
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
            return "Preview Data"
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
                return "Preview Data"
            }
        }
    }

    private var homeRows: some View {
        VStack(alignment: .leading, spacing: StoatSpacing.xSmall) {
            SidebarButton(
                title: viewModel.incomingFriendRequestCount > 0 ? "Friends (\(viewModel.incomingFriendRequestCount))" : "Friends",
                systemImage: "person.2",
                isSelected: false
            ) {
                viewModel.openFriends(tab: .online)
            }
            if !viewModel.directMessageItems.isEmpty {
                section("Direct Messages") {
                    ForEach(viewModel.directMessageItems.prefix(8)) { item in
                        DirectMessageItemButton(viewModel: viewModel, item: item)
                            .padding(.horizontal, StoatSpacing.medium)
                    }
                }
            }
            SidebarButton(title: "Discover", systemImage: "safari", isSelected: false) {
                viewModel.selectDiscover()
            }
        }
    }

    private var dmRows: some View {
        VStack(alignment: .leading, spacing: StoatSpacing.xSmall) {
            SidebarButton(
                title: viewModel.incomingFriendRequestCount > 0 ? "Friends (\(viewModel.incomingFriendRequestCount))" : "Friends",
                systemImage: "person.2.fill",
                isSelected: viewModel.selection.dmChannelID == nil
            ) {
                viewModel.openFriends(tab: .online)
            }
            SidebarButton(title: "Add Friend", systemImage: "person.badge.plus", isSelected: viewModel.friendsTab == .addFriend) {
                viewModel.openFriends(tab: .addFriend)
            }
            section("Direct Messages") {
                if viewModel.directMessageItems.isEmpty {
                    Text("No direct messages")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, StoatSpacing.medium)
                } else {
                    ForEach(viewModel.directMessageItems) { item in
                        DirectMessageItemButton(viewModel: viewModel, item: item)
                            .padding(.horizontal, StoatSpacing.medium)
                    }
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
                ZStack {
                    serverBanner
                    HStack(spacing: StoatSpacing.medium) {
                        Label(viewModel.selectedChannel?.displayName ?? "No channel", systemImage: "number")
                            .font(.headline)
                        if let topic = viewModel.selectedChannel?.description {
                            Text(topic).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        GlassIconButton("Pinned in this channel", systemImage: "pin") {
                            viewModel.openChannelSearch(mode: .pinned)
                        }
                        GlassIconButton("Search this channel", systemImage: "magnifyingglass") {
                            viewModel.openChannelSearch(mode: .loadedOnly)
                        }
                        GlassIconButton("Toggle member panel", systemImage: "sidebar.right") { viewModel.toggleMemberPanel() }
                        GlassIconButton("Channel settings unavailable in Phase 3", systemImage: "gearshape", isDisabled: true) {}
                    }
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
                    attachments: viewModel.composerAttachmentChips(for: channel.id),
                    attachmentSummary: viewModel.composerAttachmentSummary(for: channel.id),
                    replyAuthor: draftState.replyContext?.authorDisplayName,
                    replyPreview: draftState.replyContext?.contentPreview,
                    focusRequestID: viewModel.composerFocusRequestID,
                    onCancelReply: {
                        viewModel.cancelReply(for: channel.id)
                    },
                    onAttach: {
                        viewModel.openAttachmentPicker(for: channel.id)
                    },
                    onUploadAttachment: { attachmentID in
                        Task { await viewModel.retryAttachmentUpload(attachmentID, in: channel.id) }
                    },
                    onRemoveAttachment: { attachmentID in
                        viewModel.removeAttachment(attachmentID, from: channel.id)
                    },
                    onPreviewAttachment: { attachmentID in
                        viewModel.previewComposerAttachment(attachmentID, in: channel.id)
                    },
                    onDropFileURLs: { urls in
                        viewModel.addAttachmentURLs(urls, to: channel.id)
                    },
                    onPasteImageData: { data in
                        viewModel.addPastedImageData(data, to: channel.id)
                    },
                    onPasteFileURLs: { urls in
                        viewModel.addAttachmentURLs(urls, to: channel.id)
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
        .onAppear {
            viewModel.loadImageResource(for: viewModel.selectedServer?.banner, kind: .serverBanner)
        }
        .onChange(of: viewModel.selectedServer?.id) { _, _ in
            viewModel.loadImageResource(for: viewModel.selectedServer?.banner, kind: .serverBanner)
        }
    }

    @ViewBuilder private var serverBanner: some View {
        #if canImport(AppKit)
        if let data = viewModel.imageData(for: viewModel.selectedServer?.banner, kind: .serverBanner),
           let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: 52)
                .clipped()
                .overlay(Color.black.opacity(0.28))
                .accessibilityHidden(true)
        }
        #endif
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
        case let .preserveVisibleAnchor(messageID):
            target = messageID
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
        unreadRecoveryBanner
        searchHighlightAffordance
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
        } else if viewModel.selectedChannelMessageState.timelineMessages.isEmpty == false {
            Text("Beginning of loaded history")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
        unreadSeparator
        ForEach(viewModel.selectedTimelineMessageGroups) { group in
            TimelineMessageGroupView(group: group, author: viewModel.snapshot.usersByID[group.authorID], viewModel: viewModel)
        }
        newestIndicator
        typingIndicator
        timelineDiagnosticsView
    }

    @ViewBuilder private var searchHighlightAffordance: some View {
        if let label = viewModel.searchResultCountLabel {
            HStack(spacing: StoatSpacing.small) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(label)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Spacer()
                Button {
                    viewModel.selectAdjacentSearchResult(-1)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Previous search result, \(label)")
                Button {
                    viewModel.selectAdjacentSearchResult(1)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Next search result, \(label)")
                if viewModel.canPerform(.loadAroundSelectedSearchResult) {
                    Button("Load Around Result") {
                        Task { await viewModel.loadAroundSelectedSearchResult() }
                    }
                    .buttonStyle(.borderless)
                    .accessibilityHint(Phase13Accessibility.loadAroundCurrentResultHint(canLoad: true))
                }
                Button {
                    viewModel.clearSearchHighlights()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Clear search highlights")
            }
            .font(.caption)
            .padding(.horizontal, StoatSpacing.medium)
            .padding(.vertical, StoatSpacing.small)
            .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: StoatRadius.control, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(label)
        }
    }

    @ViewBuilder private var unreadRecoveryBanner: some View {
        if let channelID = viewModel.selection.channelID ?? viewModel.selection.dmChannelID,
           let history = viewModel.messageController.historiesByChannelID[channelID] {
            switch history.unreadRecoveryState {
            case .none, .targetLoaded:
                EmptyView()
            case let .targetUnloaded(messageID):
                HStack(spacing: StoatSpacing.small) {
                    Image(systemName: "text.line.first.and.arrowtriangle.forward")
                    Text("Unread message is outside the loaded range.")
                    Spacer()
                    Button("Load Older") {
                        Task { await viewModel.loadToFirstUnreadMessage() }
                    }
                    .buttonStyle(GlassButtonStyle())
                }
                .font(.caption)
                .padding(StoatSpacing.medium)
                .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: StoatRadius.control, style: .continuous))
                .accessibilityLabel("Unread message is outside the loaded range. Load older messages to reach it. Target \(messageID.rawValue).")
            case let .loadingToTarget(_, attempts):
                HStack(spacing: StoatSpacing.small) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading to unread, attempt \(attempts)")
                    Spacer()
                }
                .font(.caption)
                .padding(StoatSpacing.medium)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: StoatRadius.control, style: .continuous))
            case .targetMissing:
                inlineError("Unread message could not be found.")
            case let .failed(_, message):
                inlineError(message)
            }
        }
    }

    @ViewBuilder private var timelineDiagnosticsView: some View {
        if viewModel.isDeveloperControlsEnabled {
            let diagnostics = viewModel.timelineDiagnostics()
            let attachments = viewModel.attachmentDiagnostics()
            let actions = viewModel.messageActionDiagnostics()
            let send = viewModel.currentMessageSendDiagnostics()
            VStack(alignment: .leading, spacing: StoatSpacing.xxSmall) {
                Text("Timeline Diagnostics")
                    .font(.caption.weight(.semibold))
                Text("Loaded \(diagnostics.loadedMessageCount) · visible \(diagnostics.firstVisibleMessageID?.rawValue ?? "-") to \(diagnostics.lastVisibleMessageID?.rawValue ?? "-") · at newest \(diagnostics.atNewest ? "yes" : "no") · pending refs \(diagnostics.pendingReferenceFetchCount) · retries \(diagnostics.pendingRetryCount)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text("Attachments displayed \(attachments.displayedAttachmentCount) · loaded previews \(attachments.loadedPreviewCount) · failed previews \(attachments.failedPreviewCount) · drafts queued \(attachments.queuedDraftCount) · failed uploads \(attachments.failedUploadCount)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text("Message actions visible \(actions.visibleActionCount) · available \(actions.availableActionCount) · reactions \(actions.reactionGroupCount) · mine \(actions.currentUserReactionCount) · delete confirm \(actions.hasPendingDeleteConfirmation ? "yes" : "no")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text("Send \(send.canSend ? "ready" : "blocked") · stage \(send.lastSendStage?.rawValue ?? "-") · result \(send.lastSendResult?.rawValue ?? "-") · reason \(send.disabledReason ?? "-") · error \(send.lastError ?? "-")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .padding(StoatSpacing.small)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: StoatRadius.control, style: .continuous))
        }
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
                            authorDisplayNameOverride: viewModel.displayName(
                                for: timelineMessage.message.user ?? author,
                                member: timelineMessage.message.member ?? viewModel.member(
                                    for: timelineMessage.message.authorID,
                                    serverID: viewModel.snapshot.channelsByID[timelineMessage.message.channelID]?.serverID
                                ),
                                fallbackID: timelineMessage.message.authorID
                            ),
                            showsHeader: index == 0,
                            statusText: accessibilityStatus(for: timelineMessage),
                            isSelected: viewModel.timelineSelection.messageID == timelineMessage.message.id,
                            isFocused: viewModel.timelineSelection.focus.messageID == timelineMessage.message.id && viewModel.timelineSelection.focus.mode != .none,
                            isSearchHighlighted: viewModel.isSearchHighlighted(timelineMessage.message.id),
                            isCurrentSearchResult: viewModel.isCurrentSearchResult(timelineMessage.message.id),
                            isCompactDensity: viewModel.messageDensity == .compact,
                            searchAccessibilityStatus: viewModel.searchHighlightStatus(for: timelineMessage.message.id),
                            replyPreview: viewModel.resolvedReplyPreview(for: timelineMessage.message),
                            attachmentItems: viewModel.attachmentDisplayItems(for: timelineMessage.message),
                            authorAvatarData: viewModel.imageData(for: viewModel.avatarFile(for: timelineMessage.message), kind: .userAvatar),
                            actionItems: rowActionItems(for: timelineMessage),
                            reactionItems: rowReactionItems(for: timelineMessage),
                            onMessageAction: { actionID in
                                select(timelineMessage, source: .contextMenu)
                                viewModel.performMessageAction(actionID, on: timelineMessage)
                            },
                            onToggleReaction: { emoji in
                                select(timelineMessage)
                                Task { await viewModel.toggleReaction(emoji, on: timelineMessage) }
                            },
                            onPreviewAttachment: { item in
                                Task { await viewModel.previewAttachment(item) }
                            },
                            onDownloadAttachment: { item in
                                Task { await viewModel.downloadAttachment(item) }
                            },
                            onOpenAttachment: { item in
                                Task { await viewModel.openAttachmentExternally(item) }
                            },
                            onRetryAttachment: { item in
                                Task { await viewModel.retryAttachmentPreview(item) }
                            }
                        )
                        .id(timelineMessage.message.id)
                        .onAppear {
                            viewModel.updateTimelineVisibility(messageID: timelineMessage.message.id, channelID: timelineMessage.message.channelID, isVisible: true)
                            viewModel.loadInlineImagePreviews(for: timelineMessage.message)
                            viewModel.loadImageResource(for: viewModel.avatarFile(for: timelineMessage.message), kind: .userAvatar)
                        }
                        .onDisappear {
                            viewModel.updateTimelineVisibility(messageID: timelineMessage.message.id, channelID: timelineMessage.message.channelID, isVisible: false)
                        }
                        .onTapGesture {
                            select(timelineMessage)
                        }
                        .contextMenu {
                            ForEach(viewModel.messageActionItems(for: timelineMessage)) { item in
                                Button(role: buttonRole(for: item)) {
                                    select(timelineMessage, source: .contextMenu)
                                    viewModel.performMessageAction(item.id, on: timelineMessage)
                                } label: {
                                    Label(item.title, systemImage: item.systemImage)
                                }
                                .disabled(!item.availability.isAvailable)
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

    private func rowActionItems(for timelineMessage: TimelineMessage) -> [MessageRowActionItem] {
        viewModel.messageActionItems(for: timelineMessage).map { item in
            MessageRowActionItem(
                id: item.id,
                title: item.title,
                systemImage: item.systemImage,
                role: item.role == .destructive ? .destructive : .standard,
                isEnabled: item.availability.isAvailable,
                isPrimary: item.isPrimary
            )
        }
    }

    private func rowReactionItems(for timelineMessage: TimelineMessage) -> [MessageReactionDisplayItem] {
        viewModel.reactionSummaries(for: timelineMessage.message).map {
            MessageReactionDisplayItem(emoji: $0.emoji, count: $0.count, hasCurrentUserReacted: $0.hasCurrentUserReacted)
        }
    }

    private func buttonRole(for item: MessageActionItem) -> ButtonRole? {
        item.role == .destructive ? .destructive : nil
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
        case let .retrying(metadata):
            HStack(spacing: StoatSpacing.small) {
                ProgressView()
                    .controlSize(.small)
                Text("Retrying... attempt \(metadata.attemptCount)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, StoatSize.avatar + StoatSpacing.medium)
            .accessibilityLabel("Retrying failed message, attempt \(metadata.attemptCount)")
        case let .failed(metadata):
            let message = metadata.lastError
            HStack(spacing: StoatSpacing.small) {
                Text("Failed after \(metadata.attemptCount) attempt\(metadata.attemptCount == 1 ? "" : "s"): \(message)")
                    .font(.caption2)
                    .foregroundStyle(.red)
                Button("Retry") {
                    Task { await viewModel.retry(timelineMessage) }
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.messageController.retryingMessageIDs.contains(timelineMessage.message.id))
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
        case .retrying:
            return "retrying failed send"
        case let .failed(metadata):
            return "failed to send after \(metadata.attemptCount) attempt\(metadata.attemptCount == 1 ? "" : "s")"
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
                            MemberRow(user: user, subtitle: roleSubtitle(for: user), displayName: displayName(for: user), imageData: avatarData(for: user))
                                .onAppear { loadAvatar(for: user) }
                        }
                        Text("OFFLINE")
                            .font(StoatTypography.section)
                            .foregroundStyle(.secondary)
                            .padding(.top, StoatSpacing.medium)
                        ForEach(members.filter { !$0.online }) { user in
                            MemberRow(user: user, subtitle: roleSubtitle(for: user), displayName: displayName(for: user), imageData: avatarData(for: user))
                                .onAppear { loadAvatar(for: user) }
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

    private func member(for user: User) -> ServerMember? {
        guard let serverID = viewModel.selection.serverID else { return nil }
        return viewModel.snapshot.membersByServerAndUserID[ServerMemberKey(serverID: serverID, userID: user.id)]
    }

    private func displayName(for user: User) -> String {
        viewModel.displayName(for: user, member: member(for: user), fallbackID: user.id)
    }

    private func avatarFile(for user: User) -> File? {
        member(for: user)?.avatar ?? user.avatar
    }

    private func avatarData(for user: User) -> Data? {
        viewModel.imageData(for: avatarFile(for: user), kind: .userAvatar)
    }

    private func loadAvatar(for user: User) {
        viewModel.loadImageResource(for: avatarFile(for: user), kind: .userAvatar)
    }
}

public struct HomeView: View {
    @Bindable private var viewModel: MainShellViewModel

    public init(viewModel: MainShellViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StoatSpacing.xLarge) {
                HStack {
                    Text("Home")
                        .font(.largeTitle.weight(.semibold))
                    Spacer()
                    Button("Refresh Friends & DMs") {
                        Task { await viewModel.refreshRelationshipsAndDirectMessages() }
                    }
                    .buttonStyle(GlassButtonStyle())
                    .disabled(!canRefreshRelationships || viewModel.isRelationshipRefreshInProgress)
                }

                HStack(alignment: .top, spacing: StoatSpacing.large) {
                    currentUserPanel
                    statusPanel
                    recentDMsPanel
                }

                quickActions

                FriendsPlaceholderView(viewModel: viewModel, compact: true)
            }
            .padding(StoatSpacing.xxLarge)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var currentUserPanel: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: StoatSpacing.medium) {
                Text("Current User").font(.headline)
                if let user = viewModel.currentUserID.flatMap({ viewModel.snapshot.usersByID[$0] }) ?? viewModel.currentUser {
                    Button {
                        viewModel.showUserProfile(user.id)
                    } label: {
                        MemberRow(user: user, subtitle: user.status?.text, imageData: viewModel.imageData(for: user.avatar, kind: .userAvatar))
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: Binding(get: { viewModel.profileUserID == user.id }, set: { if !$0 { viewModel.closeUserProfile() } })) {
                        UserProfileCardView(viewModel: viewModel, user: user)
                    }
                    .onAppear { viewModel.loadImageResource(for: user.avatar, kind: .userAvatar) }
                } else {
                    EmptyStateView(title: "Signed out", message: "Set up a session before connecting.", systemImage: "person.crop.circle.badge.exclamationmark")
                }
            }
        }
        .frame(maxWidth: 320, alignment: .topLeading)
    }

    private var statusPanel: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: StoatSpacing.small) {
                Text("Connection").font(.headline)
                LabeledContent("Session", value: sessionStateText)
                LabeledContent("DMs", value: "\(viewModel.directMessageItems.count)")
                LabeledContent("Friends", value: "\(viewModel.allFriendItems.filter { $0.relationshipStatus == .friend }.count)")
                LabeledContent("Requests", value: "\(viewModel.incomingFriendRequestCount)")
                if let status = viewModel.relationshipActionStatus {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: 280, alignment: .topLeading)
    }

    private var recentDMsPanel: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: StoatSpacing.medium) {
                Text("Recent DMs").font(.headline)
                if viewModel.directMessageItems.isEmpty {
                    EmptyStateView(title: "No DMs", message: "Existing direct messages will appear after Ready or manual refresh.", systemImage: "bubble.left.and.bubble.right")
                } else {
                    ForEach(viewModel.directMessageItems.prefix(5)) { item in
                        DirectMessageItemButton(viewModel: viewModel, item: item)
                    }
                }
            }
        }
        .frame(maxWidth: 360, alignment: .topLeading)
    }

    private var quickActions: some View {
        HStack(spacing: StoatSpacing.medium) {
            Button("Friends") { viewModel.openFriends(tab: .online) }
            Button("Pending Requests") { viewModel.openFriends(tab: .pending) }
            Button("Add Friend") { viewModel.openFriends(tab: .addFriend) }
            Button("Account & Connection") { viewModel.showAccountSessions() }
        }
        .buttonStyle(GlassButtonStyle())
    }

    private var canRefreshRelationships: Bool {
        viewModel.effectiveRuntimeMode == .mock ||
            (viewModel.effectiveRuntimeMode == .liveManual && viewModel.effectiveSessionState == .connected)
    }

    private var sessionStateText: String {
        switch viewModel.effectiveSessionState {
        case .mock: "Preview Data"
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
}

public struct LiveStartupView: View {
    @Bindable private var viewModel: MainShellViewModel

    public init(viewModel: MainShellViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: StoatSpacing.xLarge) {
            VStack(alignment: .leading, spacing: StoatSpacing.small) {
                Text("Liquid Bagel")
                    .font(.largeTitle.weight(.semibold))
                Text(statusTitle)
                    .font(.title3.weight(.medium))
                Text(statusMessage)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 520, alignment: .leading)
            }

            HStack(spacing: StoatSpacing.medium) {
                Button(primaryActionTitle) {
                    primaryAction()
                }
                .buttonStyle(GlassButtonStyle())

                Button("Account & Connection") {
                    viewModel.showAccountSessions()
                }
                .buttonStyle(GlassButtonStyle())

                if viewModel.sessionCoordinator?.hasSavedCredential == true {
                    Button("Validate Session") {
                        Task {
                            await viewModel.sessionCoordinator?.validateSavedSession()
                            viewModel.syncFromSessionCoordinator()
                        }
                    }
                    .buttonStyle(GlassButtonStyle())
                }
            }

            GlassPanel {
                VStack(alignment: .leading, spacing: StoatSpacing.small) {
                    LabeledContent("Environment", value: environmentText)
                    LabeledContent("Credential", value: viewModel.sessionCoordinator?.hasSavedCredential == true ? "Saved" : "Missing")
                    LabeledContent("Connection", value: connectionText)
                    LabeledContent("Ready", value: viewModel.sessionCoordinator?.hydrationStatus.readyReceived == true ? "Received" : "Waiting")
                }
            }
            .frame(maxWidth: 460, alignment: .leading)

            Spacer()
        }
        .padding(StoatSpacing.xxLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var statusTitle: String {
        switch viewModel.effectiveSessionState {
        case .signedOut:
            "Set up a live session"
        case .savedCredentialUnvalidated, .readyToConnect, .validatedReady:
            "Ready to connect manually"
        case .connecting, .loadingCredential, .validatingCredential:
            "Preparing live session"
        case .connected:
            viewModel.snapshot.serversByID.isEmpty ? "Connected with no servers" : "Connected"
        case .invalidSession, .validationFailed, .connectionFailed, .keychainFailed, .failed:
            "Live session needs attention"
        case .mock:
            "Preview data"
        }
    }

    private var statusMessage: String {
        switch viewModel.effectiveSessionState {
        case .signedOut:
            "No saved credential is available for this environment. Set up a session before connecting."
        case .savedCredentialUnvalidated:
            "A credential exists, but Liquid Bagel will not validate or connect until you ask."
        case .readyToConnect, .validatedReady:
            "Connect manually when you are ready to dogfood against live Stoat."
        case .connected:
            viewModel.snapshot.serversByID.isEmpty ? "Ready arrived, but no servers are available in the live snapshot." : "Live data is ready."
        case .connecting, .loadingCredential, .validatingCredential:
            "Live setup is running because you requested it."
        case .invalidSession, .validationFailed, .connectionFailed, .keychainFailed, .failed:
            viewModel.sessionCoordinator?.lastErrorMessage ?? "Open Account & Connection to repair the session."
        case .mock:
            "Preview data is available only for development."
        }
    }

    private var primaryActionTitle: String {
        viewModel.sessionCoordinator?.hasSavedCredential == true ? "Connect Manually" : "Set Up Session"
    }

    private func primaryAction() {
        if viewModel.sessionCoordinator?.hasSavedCredential == true {
            Task { await viewModel.connectLiveManually() }
        } else {
            viewModel.showAccountSessions()
        }
    }

    private var environmentText: String {
        guard let coordinator = viewModel.sessionCoordinator else { return "Stoat Production" }
        return Phase6UIHelpers.environmentDisplayName(coordinator.environment, preferences: coordinator.preferences)
    }

    private var connectionText: String {
        Phase6UIHelpers.connectionHealthText(
            state: viewModel.effectiveConnectionState,
            diagnostics: viewModel.effectiveDiagnostics,
            hydration: viewModel.sessionCoordinator?.hydrationStatus ?? .empty
        )
    }
}

public struct FriendsPlaceholderView: View {
    @Bindable private var viewModel: MainShellViewModel
    private let compact: Bool

    public init(viewModel: MainShellViewModel, compact: Bool = false) {
        self.viewModel = viewModel
        self.compact = compact
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: StoatSpacing.large) {
            HStack {
                Text("Friends")
                    .font(.title2.weight(.semibold))
                Spacer()
                Picker("Friend filter", selection: $viewModel.friendsTab) {
                    ForEach(FriendsTab.allCases, id: \.self) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 430)
            }

            if viewModel.friendsTab == .addFriend {
                addFriendPanel
            } else {
                GlassPanel {
                    VStack(alignment: .leading, spacing: StoatSpacing.medium) {
                        if viewModel.friendItems.isEmpty {
                            EmptyStateView(title: emptyTitle, message: emptyMessage, systemImage: emptyIcon)
                        } else if viewModel.friendsTab == .pending {
                            pendingSection(title: "Incoming", items: viewModel.friendItems.filter { $0.relationshipStatus == .incoming })
                            pendingSection(title: "Outgoing", items: viewModel.friendItems.filter { $0.relationshipStatus == .outgoing })
                        } else {
                            ForEach(viewModel.friendItems) { item in
                                FriendItemRow(viewModel: viewModel, item: item)
                            }
                        }
                    }
                }
            }
        }
        .padding(compact ? 0 : StoatSpacing.xxLarge)
    }

    private var addFriendPanel: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: StoatSpacing.medium) {
                HStack {
                    TextField("username#0000", text: $viewModel.addFriendText)
                        .textFieldStyle(.roundedBorder)
                    Button("Send Request") {
                        Task { await viewModel.sendFriendRequestFromInput() }
                    }
                    .buttonStyle(GlassButtonStyle())
                    .disabled(viewModel.addFriendText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let status = viewModel.relationshipActionStatus {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func pendingSection(title: String, items: [FriendListItem]) -> some View {
        VStack(alignment: .leading, spacing: StoatSpacing.small) {
            Text("\(title.uppercased()) - \(items.count)")
                .font(StoatTypography.section)
                .foregroundStyle(.secondary)
            if items.isEmpty {
                Text("Nobody here right now.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, StoatSpacing.small)
            } else {
                ForEach(items) { item in
                    FriendItemRow(viewModel: viewModel, item: item)
                }
            }
        }
    }

    private var emptyTitle: String {
        switch viewModel.friendsTab {
        case .online: "No friends online"
        case .all: "No friends"
        case .pending: "No pending requests"
        case .blocked: "No blocked users"
        case .addFriend: "Add Friend"
        }
    }

    private var emptyMessage: String {
        switch viewModel.friendsTab {
        case .online: "Online friends from Ready will appear here."
        case .all: "Friends from Ready or manual refresh will appear here."
        case .pending: "Incoming and outgoing requests will appear here."
        case .blocked: "Blocked users appear only when the relationship state is available."
        case .addFriend: ""
        }
    }

    private var emptyIcon: String {
        switch viewModel.friendsTab {
        case .blocked: "hand.raised"
        case .pending: "tray"
        default: "person.2"
        }
    }
}

private struct DirectMessageItemButton: View {
    @Bindable var viewModel: MainShellViewModel
    let item: DirectMessageListItem

    var body: some View {
        Button {
            viewModel.selectChannel(item.id)
        } label: {
            HStack(spacing: StoatSpacing.medium) {
                AvatarView(title: item.displayName, size: StoatSize.compactAvatar, isOnline: item.avatarUser?.online == true, imageData: item.avatarUser.flatMap { viewModel.imageData(for: $0.avatar, kind: .userAvatar) })
                VStack(alignment: .leading, spacing: StoatSpacing.xxSmall) {
                    Text(item.displayName)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text(item.lastMessagePreview ?? "No loaded messages")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if item.mentionCount > 0 {
                    MentionBadge(count: item.mentionCount)
                } else if item.unreadCount > 0 {
                    Circle().fill(Color.secondary).frame(width: 7, height: 7)
                }
            }
            .padding(StoatSpacing.small)
            .background(viewModel.selection.dmChannelID == item.id ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: StoatRadius.row, style: .continuous))
        }
        .buttonStyle(.plain)
        .onAppear {
            if let user = item.avatarUser {
                viewModel.loadImageResource(for: user.avatar, kind: .userAvatar)
            }
        }
    }
}

private struct FriendItemRow: View {
    @Bindable var viewModel: MainShellViewModel
    let item: FriendListItem

    var body: some View {
        HStack(spacing: StoatSpacing.medium) {
            Button {
                viewModel.showUserProfile(item.user.id)
            } label: {
                MemberRow(
                    user: item.user,
                    subtitle: subtitle,
                    imageData: viewModel.imageData(for: item.user.avatar, kind: .userAvatar)
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: Binding(get: { viewModel.profileUserID == item.user.id }, set: { if !$0 { viewModel.closeUserProfile() } })) {
                UserProfileCardView(viewModel: viewModel, user: item.user)
            }

            Spacer()

            if item.mentionCount > 0 {
                MentionBadge(count: item.mentionCount)
            } else if item.unreadCount > 0 {
                Circle().fill(Color.secondary).frame(width: 7, height: 7)
            }

            relationshipButtons
        }
        .onAppear { viewModel.loadImageResource(for: item.user.avatar, kind: .userAvatar) }
    }

    @ViewBuilder private var relationshipButtons: some View {
        switch item.relationshipStatus {
        case .friend:
            Button("Message") { Task { await viewModel.openDirectMessage(with: item.user.id) } }
                .buttonStyle(GlassButtonStyle())
            Button("Remove") { viewModel.requestRelationshipAction(.remove, userID: item.user.id) }
                .buttonStyle(GlassButtonStyle())
        case .incoming:
            Button("Accept") { Task { await viewModel.performRelationshipAction(.accept, userID: item.user.id) } }
                .buttonStyle(GlassButtonStyle())
            Button("Deny") { viewModel.requestRelationshipAction(.deny, userID: item.user.id) }
                .buttonStyle(GlassButtonStyle())
        case .outgoing:
            Button("Cancel") { viewModel.requestRelationshipAction(.remove, userID: item.user.id) }
                .buttonStyle(GlassButtonStyle())
        case .blocked:
            Button("Unblock") { viewModel.requestRelationshipAction(.unblock, userID: item.user.id) }
                .buttonStyle(GlassButtonStyle())
        case .none:
            Button("Add") {
                viewModel.addFriendText = "\(item.user.username)#\(item.user.discriminator)"
                Task { await viewModel.sendFriendRequestFromInput() }
            }
            .buttonStyle(GlassButtonStyle())
        case .user:
            Button("Profile") { viewModel.showUserProfile(item.user.id) }
                .buttonStyle(GlassButtonStyle())
        case .blockedOther, .unknown:
            Text(item.relationshipStatus.rawAPIValue)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var subtitle: String {
        let presence = item.user.online ? "Online" : "Offline"
        return "\(presence) · \(item.relationshipStatus.rawAPIValue)"
    }
}

private struct UserProfileCardView: View {
    @Bindable var viewModel: MainShellViewModel
    let user: User

    var body: some View {
        VStack(alignment: .leading, spacing: StoatSpacing.large) {
            HStack(alignment: .center, spacing: StoatSpacing.medium) {
                AvatarView(title: displayName, size: StoatSize.avatar, isOnline: user.online, imageData: viewModel.imageData(for: user.avatar, kind: .userAvatar))
                VStack(alignment: .leading, spacing: StoatSpacing.xxSmall) {
                    Text(displayName)
                        .font(.title3.weight(.semibold))
                    Text("@\(user.username)#\(user.discriminator)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(viewModel.relationshipStatus(for: user).rawAPIValue)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            if viewModel.profileLoadingUserIDs.contains(user.id) {
                HStack(spacing: StoatSpacing.small) {
                    ProgressView().controlSize(.small)
                    Text("Loading profile")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let profile = viewModel.userProfilesByID[user.id], let content = profile.content, !content.isEmpty {
                Text(content)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let error = viewModel.profileErrorsByID[user.id] {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: StoatSpacing.small) {
                profileActions
                Spacer()
                if viewModel.isDeveloperControlsEnabled {
                    Button("Copy ID") {
                        Task { await viewModel.messageCopier.copy(user.id.rawValue) }
                    }
                    .buttonStyle(GlassButtonStyle())
                }
            }
        }
        .padding(StoatSpacing.large)
        .frame(width: 360, alignment: .leading)
        .onAppear {
            viewModel.loadImageResource(for: user.avatar, kind: .userAvatar)
            Task { await viewModel.fetchUserProfileIfNeeded(user.id) }
        }
    }

    @ViewBuilder private var profileActions: some View {
        let status = viewModel.relationshipStatus(for: user)
        switch status {
        case .user:
            Button("Account") { viewModel.showAccountSessions() }
                .buttonStyle(GlassButtonStyle())
        case .friend:
            Button("Message") { Task { await viewModel.openDirectMessage(with: user.id) } }
                .buttonStyle(GlassButtonStyle())
            Button("Remove") { viewModel.requestRelationshipAction(.remove, userID: user.id) }
                .buttonStyle(GlassButtonStyle())
        case .incoming:
            Button("Accept") { Task { await viewModel.performRelationshipAction(.accept, userID: user.id) } }
                .buttonStyle(GlassButtonStyle())
            Button("Deny") { viewModel.requestRelationshipAction(.deny, userID: user.id) }
                .buttonStyle(GlassButtonStyle())
        case .outgoing:
            Button("Cancel") { viewModel.requestRelationshipAction(.remove, userID: user.id) }
                .buttonStyle(GlassButtonStyle())
        case .blocked:
            Button("Unblock") { viewModel.requestRelationshipAction(.unblock, userID: user.id) }
                .buttonStyle(GlassButtonStyle())
        case .none:
            Button("Add Friend") {
                viewModel.addFriendText = "\(user.username)#\(user.discriminator)"
                Task { await viewModel.sendFriendRequestFromInput() }
            }
            .buttonStyle(GlassButtonStyle())
        case .blockedOther, .unknown:
            Text(status.rawAPIValue)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var displayName: String {
        user.displayName?.isEmpty == false ? user.displayName! : user.username
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

public struct ChannelSearchPanel: View {
    @Bindable private var viewModel: MainShellViewModel
    @FocusState private var fieldFocused: Bool

    public init(viewModel: MainShellViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: StoatSpacing.medium) {
            HStack {
                Text("Search this channel")
                    .font(.headline)
                Spacer()
                Button("Done") { viewModel.closeChannelSearch() }
            }

            Picker("Search mode", selection: $viewModel.channelSearchQuery.mode) {
                ForEach(ChannelSearchMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Search mode")

            HStack {
                TextField(searchPlaceholder, text: $viewModel.channelSearchQuery.text)
                    .textFieldStyle(.roundedBorder)
                    .focused($fieldFocused)
                    .disabled(viewModel.channelSearchQuery.mode == .pinned)
                    .onSubmit { Task { await viewModel.runChannelSearch() } }
                    .accessibilityLabel(viewModel.channelSearchQuery.mode.displayName)
                Button("Search") {
                    Task { await viewModel.runChannelSearch() }
                }
                .keyboardShortcut(.return, modifiers: [])
            }

            modeStatus
            resultsContent
            navigationControls
        }
        .padding(StoatSpacing.large)
        .frame(minWidth: 560, minHeight: 420, alignment: .topLeading)
        .onAppear { fieldFocused = viewModel.channelSearchQuery.mode != .pinned }
        .accessibilityLabel(Phase13Accessibility.channelSearchPanelLabel(mode: viewModel.channelSearchQuery.mode, resultCount: viewModel.channelSearchState.results.count))
    }

    private var searchPlaceholder: String {
        switch viewModel.channelSearchQuery.mode {
        case .loadedOnly: "Find in loaded messages"
        case .liveChannel: "Search this channel"
        case .pinned: "Pinned messages in this channel"
        }
    }

    @ViewBuilder private var modeStatus: some View {
        switch viewModel.channelSearchQuery.mode {
        case .loadedOnly:
            Text("Loaded messages only. No network calls.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .liveChannel:
            Text(viewModel.effectiveRuntimeMode == .liveManual && viewModel.effectiveSessionState == .connected ? "Live channel search runs only when you press Search." : "Live search requires manual connection.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .pinned:
            Text("Pinned search is selected-channel only and runs only when you press Search.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var resultsContent: some View {
        switch viewModel.channelSearchState {
        case .idle:
            ContentUnavailableView("No search yet", systemImage: "magnifyingglass", description: Text("Search this channel or find in loaded messages."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .searching:
            LoadingStateView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .empty(query):
            ContentUnavailableView("No results", systemImage: query.mode == .pinned ? "pin.slash" : "magnifyingglass", description: Text(query.mode.displayName))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(_, message):
            ErrorStateView(message)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .results(_, results):
            ScrollView {
                LazyVStack(alignment: .leading, spacing: StoatSpacing.xSmall) {
                    ForEach(results) { result in
                        searchResultRow(result)
                    }
                }
            }
        }
    }

    private func searchResultRow(_ result: ChannelSearchResult) -> some View {
        let selected = viewModel.selectedSearchResultID == result.messageID
        return Button {
            viewModel.selectSearchResult(result)
        } label: {
            HStack(alignment: .top, spacing: StoatSpacing.small) {
                Image(systemName: result.isPinned ? "pin.fill" : (result.isLoaded ? "text.bubble" : "arrow.down.message"))
                    .frame(width: 20)
                    .foregroundStyle(result.isLoaded ? .primary : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(result.authorDisplayName ?? result.authorID.rawValue)
                            .font(.caption.weight(.semibold))
                        if let createdAt = result.createdAt {
                            Text(createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(result.mode == .loadedOnly ? "Loaded" : (result.isLoaded ? "Loaded" : "Outside range"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(result.snippet)
                        .font(.caption)
                        .foregroundStyle(result.isLoaded ? .primary : .secondary)
                        .lineLimit(2)
                }
            }
            .padding(StoatSpacing.small)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: StoatRadius.small, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Phase13Accessibility.channelSearchResultLabel(result, isSelected: selected))
    }

    private var navigationControls: some View {
        HStack {
            Button("Previous") { viewModel.selectAdjacentSearchResult(-1) }
                .disabled(viewModel.channelSearchState.results.isEmpty)
                .accessibilityLabel("Previous search result")
            Button("Next") { viewModel.selectAdjacentSearchResult(1) }
                .disabled(viewModel.channelSearchState.results.isEmpty)
                .accessibilityLabel("Next search result")
            Button("Jump") { viewModel.jumpToSelectedSearchResult() }
                .disabled(viewModel.selectedSearchResult == nil)
            Button("Load around result") {
                Task { await viewModel.loadAroundSelectedSearchResult() }
            }
            .disabled(viewModel.canPerform(.loadAroundSelectedSearchResult) == false)
            .accessibilityHint(Phase13Accessibility.loadAroundCurrentResultHint(canLoad: viewModel.canPerform(.loadAroundSelectedSearchResult)))
            Button("Clear") { viewModel.clearSearchHighlights() }
                .disabled(viewModel.canPerform(.clearSearchHighlights) == false)
            Spacer()
            if let status = viewModel.searchResultCountLabel ?? viewModel.searchNavigationStatus {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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
                LabeledContent("Runtime", value: "Live-first, manual connect only")
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
#Preview("Phase 11 Unloaded Unread") {
    let model = MainShellViewModel(snapshot: MockShellData.snapshot)
    if let channel = model.snapshot.channelsByID.values.first(where: { $0.displayName == "macos-native" }) {
        model.selectChannel(channel.id)
        model.localReadStates[channel.id] = LocalReadState(channelID: channel.id, firstUnreadMessageID: "missing-unread", unreadCount: 1, mentionCount: 0)
        model.jumpToFirstUnreadMessage()
    }
    return MessageTimelineView(viewModel: model)
        .frame(width: 760, height: 520)
}

@available(macOS 15.0, *)
#Preview("Phase 11 Timeline Diagnostics") {
    let model = MainShellViewModel(snapshot: MockShellData.snapshot)
    model.selectServer(model.servers[0].id)
    if let channelID = model.selection.channelID {
        for message in model.selectedTimelineMessages.suffix(2) {
            model.updateTimelineVisibility(messageID: message.message.id, channelID: channelID, isVisible: true)
        }
    }
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
