import Foundation
import Observation
import OSLog
import StoatAPI
import StoatDesignSystem
import StoatModels
import StoatPersistence
import StoatRealtime
import StoatUI
import SwiftUI
import UniformTypeIdentifiers

#if canImport(AppKit)
import AppKit
#endif

private enum StoatFeatureLayoutDiagnostics {
    private static let logger = Logger(subsystem: "LiquidBagel", category: "Layout")

    static func body(_ name: StaticString, detail: String = "") {
        #if DEBUG
        if detail.isEmpty {
            logger.debug("\(name) body")
        } else {
            logger.debug("\(name) body: \(detail)")
        }
        #endif
    }
}

#if canImport(UserNotifications)
@preconcurrency import UserNotifications
#endif

public enum AppRuntimeMode: Codable, Hashable, Sendable {
    case mock
    case liveManual
}

public enum AppStartupState: Hashable, Sendable {
    case loadingPreferences
    case noCredential
    case validatingCredential
    case connectingLive
    case ready
    case savedCredentialFailed(String)
    case startupFailed(AppStartupFailure)
}

public enum AppStartupFailure: Hashable, Sendable {
    case keychainUnavailable(String)
    case unknown(String)

    public var message: String {
        switch self {
        case let .keychainUnavailable(msg): msg
        case let .unknown(msg): msg
        }
    }
}

public enum SettingsSectionTab: String, Codable, Hashable, Sendable, CaseIterable {
    case account
    case sessions
    case connection
    case notifications
    case developer
}

public enum ProfileCardTab: String, Codable, Hashable, Sendable, CaseIterable {
    case profile = "Profile"
    case mutualGroups = "Mutual Groups"
    case mutualServers = "Mutual Servers"
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
        if snapshot.serversByID.isEmpty, !snapshot.channelsByID.values.contains(where: isVisibleTextChannel) {
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
           isVisibleTextChannel(channel) {
            if let serverID = channel.serverID, snapshot.serversByID[serverID] != nil {
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
            return ShellSelectionRestorationResult(
                selection: ShellSelection(
                    space: .directMessages,
                    dmChannelID: channelID,
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
        channel.kind == .textChannel || channel.kind == .directMessage || channel.kind == .group || channel.kind == .savedMessages
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
    public var emojiPickerDiagnostics: String?
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
    public var pendingAttachmentDrop: AttachmentDropReview?
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
    public var dmRouteDiagnostics = DMRouteDiagnostics()
    public var dmLiveTrace = DirectMessageLiveTrace()
    public var dmDiagnostics = DMDiagnostics()
    public var notificationPermissionStatus: NotificationPermissionStatus = .unknown
    public var notificationBanners: [NotificationEvent] = []
    public var notificationDiagnostics = NotificationDiagnostics()
    public var lastNotificationPermissionRequest: String?
    public var notificationAuthorizerKind: String = "unknown"
    public var lastServerSettingsButtonAction: String?
    public var memberListPerformanceDiagnostics = MemberListPerformanceDiagnostics()
    public var memberRoleSortDiagnostics = RoleSortDiagnostics()
    public var visibleIdentityDiagnostics = VisibleIdentityDiagnostics()
    public var freezePerformanceDiagnostics = FreezePerformanceDiagnostics()
    public var memberHydrationDiagnostics = MemberHydrationDiagnostics()
    public var memberHydrationLoadingServerIDs: Set<ServerID> = []
    public var memberHydrationErrorsByServerID: [ServerID: String] = [:]
    public var timelinePerformanceDiagnostics = TimelinePerformanceDiagnostics()
    public var appLifecyclePhase: AppLifecyclePhase = .active
    public var queuedNotificationRoutes: [QueuedNotificationRoute] = []
    public var friendsTab: FriendsTab = .online
    public var addFriendText: String = ""
    public var relationshipActionStatus: String?
    public var isRelationshipRefreshInProgress = false
    public var profileUserID: UserID?
    public var profilePresentationContext: ProfilePresentationContext?
    public var profileSelectedTab: ProfileCardTab = .profile
    public var userProfilesByID: [UserID: UserProfile] = [:]
    public var profileErrorsByID: [UserID: String] = [:]
    public var profileLoadingUserIDs: Set<UserID> = []
    public var profileEditDraft = ProfileEditDraftState()
    public var profileEditDiagnostics = ProfileEditDiagnostics()
    public var statusUpdateStatus: String?
    public var pendingRelationshipAction: PendingRelationshipAction?
    public var isJoinInvitePresented = false
    public var inviteInput = ""
    public var invitePreviewState: InvitePreviewState = .idle
    public var pendingInviteJoin: PendingInviteJoin?
    public var discoverState: DiscoverState = .webBacked
    public var isCreateServerPresented = false
    public var serverCreateName = ""
    public var serverCreateDescription = ""
    public var serverCreateIsNSFW = false
    public var serverCreateState: ServerCreateState = .idle
    public var isInviteManagementPresented = false
    public var inviteManagementState: InviteManagementState = .idle
    public var pendingInviteDeletion: PendingInviteDeletion?
    public var phase23Status: String?
    public var isServerOverviewPresented = false
    public var serverOverviewState: ManagementActionState<ServerOverviewDetails> = .idle
    public var isCreateChannelPresented = false
    public var channelCreateForm = ChannelCreateForm()
    public var channelCreateState: ManagementActionState<Channel> = .idle
    public var isChannelSettingsPresented = false
    public var channelEditForm: ChannelEditForm?
    public var channelEditState: ManagementActionState<Channel> = .idle
    public var pendingChannelDeletion: PendingChannelDeletion?
    public var phase24Status: String?
    public var selectedServerSettingsTab: ServerSettingsTab = .overview
    public var serverSettingsState: ManagementActionState<ServerSettingsDetails> = .idle
    public var serverSettingsForm: ServerSettingsForm?
    public var serverSettingsSaveState: ManagementActionState<Server> = .idle
    public var serverIconDraft: ServerMediaDraft?
    public var serverBannerDraft: ServerMediaDraft?
    public var categoryEditorForm: CategoryEditorForm?
    public var categoryEditorState: ManagementActionState<Server> = .idle
    public var roleEditorForm: RoleEditorForm?
    public var roleEditorState: ManagementActionState<Role> = .idle
    public var pendingRoleDeletion: Role?
    public var memberSearchText: String = ""
    public var selectedMemberDetailID: MemberCompositeKey?
    public var memberRoleDraft: MemberRoleAssignmentDraft?
    public var memberRoleSaveRequiresConfirmation = false
    public var memberNicknameDraft: String = ""
    public var memberTimeoutHours: Double = 1
    public var pendingMemberModerationAction: PendingMemberModerationAction?
    public var memberActionState: ManagementActionState<ServerMember> = .idle
    public var banListState: ManagementActionState<BanListResult> = .idle
    public var permissionEditDraft: PermissionEditDraft?
    public var permissionSaveRequiresConfirmation = false
    public var permissionEditorState: ManagementActionState<String> = .idle
    public var phase25Status: String?
    public var phase26Status: String?
    public var testingSignedNotificationBuild = false

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
    @ObservationIgnored public var communityAPIClient: any StoatAPIClient
    @ObservationIgnored public var notificationRouteCenter: NotificationRouteCenter
    @ObservationIgnored public var appLifecycleCenter: AppLifecycleCenter
    @ObservationIgnored private var snapshotObservationTask: Task<Void, Never>?
    @ObservationIgnored private var selectedChannelLoadTask: Task<Void, Never>?
    @ObservationIgnored private var typingEndTask: Task<Void, Never>?
    @ObservationIgnored private var ackTask: Task<Void, Never>?
    @ObservationIgnored private var referenceFetchTasks: [MessageID: Task<Void, Never>] = [:]
    @ObservationIgnored private var attachmentLoadTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var imageResourceLoadTasks: [ImageCacheKey: Task<Void, Never>] = [:]
    @ObservationIgnored private var queuedImageResourceRequests: [ImageCacheKey: ImageResourceRequest] = [:]
    @ObservationIgnored private let maxConcurrentImageResourceLoads = 6
    @ObservationIgnored private let maxConcurrentInlinePreviewLoads = 4
    @ObservationIgnored private var memberHydrationTasks: [ServerID: Task<Void, Never>] = [:]
    @ObservationIgnored private var memberHydrationGenerations: [ServerID: Int] = [:]
    @ObservationIgnored private var hydratedMemberServerIDs: Set<ServerID> = []
    @ObservationIgnored private var restHydratedMembersByServerID: [ServerID: [ServerMemberKey: ServerMember]] = [:]
    @ObservationIgnored private var lastMemberHydrationRequestedAt: [ServerID: Date] = [:]
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
    @ObservationIgnored private let profileMediaValidationPolicy = ProfileEditMediaValidationPolicy()
    @ObservationIgnored private var visibleRangeUpdateTasks: [ChannelID: Task<Void, Never>] = [:]
    @ObservationIgnored private var failedReferenceFetchMessageIDs: Set<MessageID> = []
    @ObservationIgnored private var selectedTimelineGroupCacheKey: String?
    @ObservationIgnored private var selectedTimelineGroupCache: [TimelineMessageGroup] = []
    @ObservationIgnored private var memberListGroupCacheKey: String?
    @ObservationIgnored private var memberListGroupCache: [MemberListGroup] = []
    @ObservationIgnored private var memberListDiagnosticsCache = RoleSortDiagnostics()
    @ObservationIgnored private var timelineVisibleRangeUpdateCount = 0
    @ObservationIgnored private var memberGroupingCount = 0
    @ObservationIgnored private var memberGroupingCacheHitCount = 0
    @ObservationIgnored private var imageCompletedCount = 0
    @ObservationIgnored private var diagnosticsPublishCount = 0
    @ObservationIgnored private var profileFetchMergeCount = 0
    @ObservationIgnored private var memberWrapperUserMergeCount = 0
    @ObservationIgnored private var transientStatusTask: Task<Void, Never>?
    @ObservationIgnored private var openingDirectMessageUserIDs: Set<UserID> = []

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
        communityAPIClient: (any StoatAPIClient)? = nil,
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
        self.notificationAuthorizerKind = String(describing: type(of: self.notificationPermissionManager))
        self.dockBadgeManager = dockBadgeManager ?? AppKitDockBadgeManager()
        self.communityAPIClient = communityAPIClient ?? MockStoatAPIClient()
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
        refreshDMDiagnosticsSnapshot()
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
        transientStatusTask?.cancel()
        referenceFetchTasks.values.forEach { $0.cancel() }
        attachmentLoadTasks.values.forEach { $0.cancel() }
        imageResourceLoadTasks.values.forEach { $0.cancel() }
        queuedImageResourceRequests.removeAll()
        memberHydrationTasks.values.forEach { $0.cancel() }
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

    public var activeConversation: ActiveConversation {
        ActiveConversation.resolve(selection: selection, snapshot: snapshot)
    }

    public var selectedConversationChannelID: ChannelID? {
        activeConversation.channelID
    }

    public var selectedConversationChannel: Channel? {
        guard let id = selectedConversationChannelID else { return nil }
        return snapshot.channelsByID[id]
    }

    public var isTimelineRouteActive: Bool {
        activeConversation != .none
    }

    public var rightSidebarContext: RightSidebarContext {
        switch activeConversation {
        case let .serverChannel(serverID, channelID):
            return .serverMembers(serverID: serverID, channelID: channelID)
        case let .directMessage(channelID), let .savedMessages(channelID):
            return .directMessageParticipants(channelID: channelID)
        case let .groupDM(channelID):
            return .groupDMParticipants(channelID: channelID)
        case .none:
            switch selection.space {
            case .home:
                return .hidden
            case .directMessages:
                return .hidden
            case .discover:
                return .hidden
            case .server:
                return .hidden
            }
        }
    }

    public var canRefreshSelectedServerMembers: Bool {
        if case .serverMembers = rightSidebarContext {
            return apiClientForMemberHydration() != nil
        }
        return false
    }

    public func directMessageParticipantItems(for channel: Channel) -> [MemberListItem] {
        guard DMChannelClassifier.isDirectMessageLike(channel) else { return [] }
        let ids: [UserID]
        if channel.kind == .savedMessages {
            ids = [currentUserID ?? channel.userID].compactMap { $0 }
        } else {
            var ordered = channel.recipients
            if let currentUserID, !ordered.contains(currentUserID) {
                ordered.insert(currentUserID, at: 0)
            }
            ids = ordered
        }
        return ids.map { userID in
            MemberListItem(userID: userID, user: snapshot.usersByID[userID] ?? (userID == currentUser?.id ? currentUser : nil), member: nil)
        }
    }

    public var selectedMessages: [Message] {
        guard let channelID = selectedConversationChannelID else { return [] }
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
        guard let channelID = selectedConversationChannelID else { return [] }
        let stateMessages = messageController.state(for: channelID).timelineMessages
        if !stateMessages.isEmpty {
            return stateMessages
        }
        return (snapshot.messagesByChannelID[channelID] ?? []).map { TimelineMessage(message: $0) }
    }

    public var selectedTimelineMessageGroups: [TimelineMessageGroup] {
        cachedSelectedTimelineMessageGroups()
    }

    public var selectedChannelMessageState: ChannelMessageState {
        messageController.state(for: selectedConversationChannelID)
    }

    public var phase27Diagnostics: Phase27Diagnostics {
        let channel = selectedConversationChannel
        let attachments = attachmentDiagnostics()
        return Phase27Diagnostics(
            selectedRouteDescription: String(describing: selection.route),
            selectedChannelID: channel?.id,
            selectedChannelKind: channel?.kind.rawAPIValue,
            dmLoadState: selection.dmChannelID.map { safeLoadResultDescription(for: $0) },
            lastSystemEventRender: selectedTimelineMessages.last(where: { $0.message.system != nil }).map { systemEventText(for: $0.message) },
            bannerPlacementState: selectedServer?.banner == nil ? "no banner" : "sidebar header",
            lastReadAckDecision: lastAckResult,
            embedRenderCount: selectedTimelineMessages.reduce(0) { $0 + ($1.message.embeds?.count ?? 0) },
            pendingDropAttachmentCount: attachments.queuedDraftCount,
            notificationStatus: notificationDiagnostics.permissionStatus.rawValue
        )
    }

    public var phase28DogfoodDiagnostics: Phase28DogfoodDiagnostics {
        let missingUserIDs = missingVisibleUserIDs()
        let memberDiagnostics = memberListPerformanceDiagnostics
        let timelineDiagnostics = timelinePerformanceDiagnostics
        return Phase28DogfoodDiagnostics(
            dmSelectionState: selection.dmChannelID.map { "selected \(TimelineCopyFormatter.shortID($0.rawValue))" } ?? "not selected",
            dmLoadState: selection.dmChannelID.map { safeLoadResultDescription(for: $0) } ?? "idle",
            missingUserCount: missingUserIDs.count,
            userHydrationQueueCount: 0,
            notificationAuthorizationStatus: notificationPermissionStatus.rawValue,
            notificationAuthorizerKind: notificationAuthorizerKind,
            lastNotificationPermissionRequest: lastNotificationPermissionRequest,
            serverSettingsButtonState: lastServerSettingsButtonAction ?? (selectedServer == nil ? "no selected server" : "ready"),
            memberListDiagnostics: "members \(memberDiagnostics.totalMembers) groups \(memberDiagnostics.groupCount) queue \(memberDiagnostics.avatarLoadQueueCount) source \(memberHydrationDiagnostics.source.rawValue)",
            timelinePerformanceDiagnostics: "loaded \(timelineDiagnostics.loadedMessageCount) grouped \(timelineDiagnostics.groupedMessageCount) queue \(timelineDiagnostics.avatarLoadQueueCount)"
        )
    }

    public var phase30ParityMatrix: ParityMatrix {
        Phase30ParityMatrixBuilder.build(dmLiveQAPassed: false)
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

    public var currentUserForPresentation: User? {
        if let currentUserID, let user = snapshot.usersByID[currentUserID] {
            return user
        }
        return sessionCoordinator?.currentUser ?? currentUser
    }

    public var profilePresentationUser: User? {
        guard let profileUserID else { return nil }
        if let user = snapshot.usersByID[profileUserID] {
            return user
        }
        if profileUserID == currentUser?.id {
            return currentUser
        }
        let fallback = UserDisplayResolver.shortenedID(profileUserID)
        return User(id: profileUserID, username: fallback, displayName: fallback)
    }

    public func profileContext(userID: UserID, serverID: ServerID?, source: ProfileOpenSource) -> ProfilePresentationContext {
        let user = snapshot.usersByID[userID] ?? (userID == currentUser?.id ? currentUser : nil)
        let member = serverID.flatMap { snapshot.membersByServerAndUserID[ServerMemberKey(serverID: $0, userID: userID)] }
        let display = resolvedUserDisplay(for: user, member: member, fallbackID: userID, serverID: serverID)
        let server = serverID.flatMap { snapshot.serversByID[$0] }
        let roles = RoleColorResolver.sortedRoles(member: member, server: server)
        let mutualGroups = snapshot.channelsByID.values
            .filter { $0.kind == .group && $0.recipients.contains(userID) }
            .map { $0.displayName.isEmpty ? "Group DM" : $0.displayName }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        let mutualServers = snapshot.membersByServerAndUserID.values
            .filter { $0.id.userID == userID }
            .compactMap { snapshot.serversByID[$0.id.serverID]?.name }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return ProfilePresentationContext(
            userID: userID,
            serverID: serverID,
            openSource: source,
            display: display,
            relationship: user.map { relationshipStatus(for: $0) } ?? .none,
            roles: roles,
            mutualGroups: mutualGroups,
            mutualServers: mutualServers,
            botOwnerID: user?.bot?.ownerID
        )
    }
    
    // MARK: - Private Helper Methods

    private func serverContextForProfile(userID: UserID) -> ServerID? {
        if case let .serverMembers(serverID, _) = rightSidebarContext,
           snapshot.membersByServerAndUserID[ServerMemberKey(serverID: serverID, userID: userID)] != nil {
            return serverID
        }
        if let channelServerID = selectedConversationChannel?.serverID,
           snapshot.membersByServerAndUserID[ServerMemberKey(serverID: channelServerID, userID: userID)] != nil {
            return channelServerID
        }
        return nil
    }

    public var title: String {
        switch selection.space {
        case .home:
            return "Home"
        case .discover:
            return "Discover"
        case .directMessages:
            if let channel = selectedConversationChannel {
                return directMessageTitle(for: channel)
            }
            return "Direct Messages"
        case .server:
            if let channel = selectedChannel { return "# \(channel.displayName)" }
            return selectedServer?.name ?? "Server"
        }
    }

    private func directMessageTitle(for channel: Channel) -> String {
        switch channel.kind {
        case .savedMessages:
            return "Saved Notes"
        case .group:
            return channel.displayName.isEmpty ? "Group DM" : channel.displayName
        default:
            let names = directMessageParticipantItems(for: channel)
                .filter { $0.userID != currentUserID }
                .map(\.displayName)
            return names.first ?? channel.displayName
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
        return users.sorted { ($0.displayName ?? $0.username) < ($1.displayName ?? $1.username) }
    }

    public func memberListGroups(for serverID: ServerID?, query: String = "") -> [MemberListGroup] {
        guard let serverID, let server = snapshot.serversByID[serverID] else {
            memberListPerformanceDiagnostics = MemberListPerformanceDiagnostics(avatarLoadQueueCount: imageResourceQueueCount)
            return []
        }
        let key = memberListCacheKey(serverID: serverID, query: query)
        if key == memberListGroupCacheKey {
            memberGroupingCacheHitCount += 1
            memberRoleSortDiagnostics = RoleSortDiagnostics(
                sortMode: memberListDiagnosticsCache.sortMode,
                groupOrder: memberListDiagnosticsCache.groupOrder,
                memberCountByGroupID: memberListDiagnosticsCache.memberCountByGroupID,
                duplicateSuppressionCount: memberListDiagnosticsCache.duplicateSuppressionCount,
                unknownRoleCount: memberListDiagnosticsCache.unknownRoleCount,
                cacheHit: true,
                durationMilliseconds: memberListDiagnosticsCache.durationMilliseconds
            )
            memberListPerformanceDiagnostics.avatarLoadQueueCount = imageResourceQueueCount
            updateFreezePerformanceDiagnostics(marker: "member grouping cache hit")
            return memberListGroupCache
        }
        let started = Date()
        memberGroupingCount += 1
        let result = MemberListDeriver.result(server: server, snapshot: snapshot, query: query)
        let groups = result.groups
        memberListGroupCacheKey = key
        memberListGroupCache = groups
        memberListDiagnosticsCache = result.diagnostics
        memberRoleSortDiagnostics = result.diagnostics
        let knownMemberCount = snapshot.membersByServerAndUserID.values.filter { $0.id.serverID == serverID }.count
        let knownUserCount = snapshot.usersByID.count
        let missingUserCount = snapshot.membersByServerAndUserID.values.filter { $0.id.serverID == serverID && snapshot.usersByID[$0.id.userID] == nil }.count
        let missingAvatarCount = groups.flatMap(\.items).filter { $0.avatar == nil }.count
        let total = groups.reduce(0) { $0 + $1.items.count }
        let dropped = max(0, knownMemberCount - total)
        memberListPerformanceDiagnostics = MemberListPerformanceDiagnostics(
            totalMembers: total,
            visibleMemberEstimate: min(total, 80),
            groupCount: groups.count,
            avatarLoadQueueCount: imageResourceQueueCount,
            lastGroupingDurationDescription: "\(Int(Date().timeIntervalSince(started) * 1000))ms",
            knownMemberCount: knownMemberCount,
            knownUserCount: knownUserCount,
            missingUserCount: missingUserCount,
            missingAvatarCount: missingAvatarCount,
            renderedMemberCount: total,
            droppedMemberCount: dropped,
            droppedReasonSummary: dropped == 0 ? "missing avatars \(missingAvatarCount)" : "Filtered by query; missing avatars \(missingAvatarCount)"
        )
        updateVisibleIdentityDiagnostics()
        updateFreezePerformanceDiagnostics(marker: "member grouping \(memberListPerformanceDiagnostics.lastGroupingDurationDescription ?? "-")")
        return groups
    }

    public func serverMembers(for serverID: ServerID?) -> [ServerMember] {
        guard let serverID else { return [] }
        return snapshot.membersByServerAndUserID.values
            .filter { $0.id.serverID == serverID }
            .sorted { $0.id.userID.rawValue < $1.id.userID.rawValue }
    }

    private var imageResourceQueueCount: Int {
        imageResourceLoadTasks.count + queuedImageResourceRequests.count
    }

    public func isMemberHydrationLoading(serverID: ServerID) -> Bool {
        memberHydrationLoadingServerIDs.contains(serverID)
    }

    public func memberHydrationStatusMessage(for serverID: ServerID) -> String? {
        if memberHydrationLoadingServerIDs.contains(serverID) {
            return "Refreshing members..."
        }
        if let error = memberHydrationErrorsByServerID[serverID] {
            return "Member refresh failed due to \(memberHydrationDiagnostics.apiDiagnostics?.errorCategory ?? "refresh error"): \(error)"
        }
        if hydratedMemberServerIDs.contains(serverID) {
            return "Members refreshed from Stoat"
        }
        if knownMemberCount(serverID: serverID) > 0 {
            return "Showing Ready members"
        }
        return nil
    }

    public func hydrateMembersForVisibleContextIfNeeded() {
        guard case let .serverMembers(serverID, _) = rightSidebarContext else {
            cancelMemberHydrationTasks(except: nil)
            return
        }
        Task { [weak self] in
            await self?.hydrateServerMembers(serverID: serverID, force: false, reason: "visible member panel")
        }
    }

    public func refreshSelectedServerMembers() async {
        guard case let .serverMembers(serverID, _) = rightSidebarContext else {
            placeholderStatus = "Open a server channel before refreshing members."
            return
        }
        await hydrateServerMembers(serverID: serverID, force: true, reason: "manual refresh")
    }

    public func hydrateServerMembers(serverID: ServerID, force: Bool = false, reason: String = "foreground") async {
        cancelMemberHydrationTasks(except: serverID)
        if !force, hydratedMemberServerIDs.contains(serverID) {
            memberHydrationDiagnostics.source = .restHydrated
            memberHydrationDiagnostics.lastMemberFetchServerID = serverID
            return
        }
        if !force,
           let requestedAt = lastMemberHydrationRequestedAt[serverID],
           Date().timeIntervalSince(requestedAt) < 2 {
            return
        }
        if let existing = memberHydrationTasks[serverID] {
            if force {
                existing.cancel()
            } else {
                return
            }
        }
        guard let apiClient = apiClientForMemberHydration() else {
            let message = "Member refresh requires a live session."
            memberHydrationErrorsByServerID[serverID] = message
            memberHydrationDiagnostics = MemberHydrationDiagnostics(
                source: .readyOnly,
                lastMemberFetchServerID: serverID,
                requestedCount: knownMemberCount(serverID: serverID),
                missingUserCount: missingUserCount(serverID: serverID),
                error: message,
                lastUpdatedAt: Date()
            )
            if force { placeholderStatus = message }
            return
        }

        let requestedCount = knownMemberCount(serverID: serverID)
        let generation = (memberHydrationGenerations[serverID] ?? 0) + 1
        memberHydrationGenerations[serverID] = generation
        lastMemberHydrationRequestedAt[serverID] = Date()
        memberHydrationLoadingServerIDs.insert(serverID)
        memberHydrationErrorsByServerID[serverID] = nil
        memberHydrationDiagnostics = MemberHydrationDiagnostics(
            source: .readyOnly,
            lastMemberFetchServerID: serverID,
            requestedCount: requestedCount,
            missingUserCount: missingUserCount(serverID: serverID),
            isLoading: true,
            lastUpdatedAt: Date()
        )

        let task = Task { [weak self] in
            do {
                let response = try await apiClient.fetchServerMembers(serverID: serverID)
                await MainActor.run {
                    self?.finishMemberHydration(
                        serverID: serverID,
                        generation: generation,
                        requestedCount: requestedCount,
                        response: response,
                        reason: reason
                    )
                }
            } catch is CancellationError {
                await MainActor.run {
                    self?.discardStaleMemberHydration(serverID: serverID, generation: generation)
                }
            } catch {
                await MainActor.run {
                    self?.failMemberHydration(
                        serverID: serverID,
                        generation: generation,
                        requestedCount: requestedCount,
                        error: error,
                        forced: force
                    )
                }
            }
        }
        memberHydrationTasks[serverID] = task
        await task.value
    }

    private func finishMemberHydration(
        serverID: ServerID,
        generation: Int,
        requestedCount: Int,
        response: ServerMembersResponse,
        reason: String
    ) {
        guard memberHydrationGenerations[serverID] == generation,
              isMemberHydrationContextCurrent(serverID: serverID)
        else {
            discardStaleMemberHydration(serverID: serverID, generation: generation)
            return
        }

        var returnedByKey: [ServerMemberKey: ServerMember] = [:]
        for user in response.users {
            upsertUser(user)
        }
        memberWrapperUserMergeCount += response.users.count
        for member in response.members {
            returnedByKey[ServerMemberKey(member.id)] = member
        }
        let previousCount = knownMemberCount(serverID: serverID)
        let readyByKey = snapshot.membersByServerAndUserID.filter { $0.key.serverID == serverID }
        snapshot.membersByServerAndUserID = snapshot.membersByServerAndUserID.filter { $0.key.serverID != serverID }
        for (key, member) in readyByKey where returnedByKey[key] == nil {
            snapshot.membersByServerAndUserID[key] = member
        }
        for (key, member) in returnedByKey {
            snapshot.membersByServerAndUserID[key] = member
        }
        restHydratedMembersByServerID[serverID] = returnedByKey
        hydratedMemberServerIDs.insert(serverID)
        memberHydrationTasks[serverID] = nil
        memberHydrationLoadingServerIDs.remove(serverID)
        memberHydrationErrorsByServerID[serverID] = nil
        memberListGroupCacheKey = nil
        updateVisibleIdentityDiagnostics()

        let missingUsers = missingUserCount(serverID: serverID)
        let dropped = max(0, previousCount - returnedByKey.count)
        memberHydrationDiagnostics = MemberHydrationDiagnostics(
            source: .restHydrated,
            lastMemberFetchServerID: serverID,
            requestedCount: requestedCount,
            returnedCount: response.members.count,
            mergedMemberCount: returnedByKey.count,
            mergedUserCount: response.users.count,
            missingUserCount: missingUsers,
            droppedCount: dropped,
            staleFetchDiscarded: false,
            isLoading: false,
            error: nil,
            apiDiagnostics: response.diagnostics,
            lastUpdatedAt: Date()
        )
        placeholderStatus = "Refreshed \(returnedByKey.count) members and \(response.users.count) users."
        quickSwitcherViewModel.update(snapshot: snapshot, selection: selection)
        loadVisibleIdentityImagesForCurrentSelection()
        if reason == "manual refresh" {
            lastServerSettingsButtonAction = "Member refresh completed"
        }
    }

    private func failMemberHydration(serverID: ServerID, generation: Int, requestedCount: Int, error: Error, forced: Bool) {
        guard memberHydrationGenerations[serverID] == generation else {
            discardStaleMemberHydration(serverID: serverID, generation: generation)
            return
        }
        let diagnosed = error as? StoatAPIDiagnosedError
        let message = diagnosed?.apiError.errorDescription ?? error.userFacingMessage
        memberHydrationTasks[serverID] = nil
        memberHydrationLoadingServerIDs.remove(serverID)
        memberHydrationErrorsByServerID[serverID] = message
        memberHydrationDiagnostics = MemberHydrationDiagnostics(
            source: hydratedMemberServerIDs.contains(serverID) ? .restHydrated : .readyOnly,
            lastMemberFetchServerID: serverID,
            requestedCount: requestedCount,
            missingUserCount: missingUserCount(serverID: serverID),
            isLoading: false,
            error: message,
            apiDiagnostics: diagnosed?.diagnostics,
            lastUpdatedAt: Date()
        )
        if forced {
            placeholderStatus = "Member refresh failed: \(message)"
        }
    }

    private func discardStaleMemberHydration(serverID: ServerID, generation: Int) {
        if memberHydrationGenerations[serverID] == generation {
            memberHydrationTasks[serverID] = nil
            memberHydrationLoadingServerIDs.remove(serverID)
        }
        memberHydrationDiagnostics.staleFetchDiscarded = true
        memberHydrationDiagnostics.isLoading = false
        memberHydrationDiagnostics.lastMemberFetchServerID = serverID
        memberHydrationDiagnostics.lastUpdatedAt = Date()
    }

    private func cancelMemberHydrationTasks(except keptServerID: ServerID?) {
        let staleServers = memberHydrationTasks.keys.filter { $0 != keptServerID }
        guard !staleServers.isEmpty else { return }
        for serverID in staleServers {
            memberHydrationTasks[serverID]?.cancel()
            memberHydrationTasks[serverID] = nil
            memberHydrationLoadingServerIDs.remove(serverID)
        }
        memberHydrationDiagnostics.staleFetchDiscarded = true
        memberHydrationDiagnostics.isLoading = !memberHydrationLoadingServerIDs.isEmpty
        memberHydrationDiagnostics.lastUpdatedAt = Date()
    }

    private func isMemberHydrationContextCurrent(serverID: ServerID) -> Bool {
        guard case let .serverMembers(currentServerID, _) = rightSidebarContext else { return false }
        return currentServerID == serverID
    }

    private func apiClientForMemberHydration() -> (any StoatAPIClient)? {
        sessionCoordinator?.apiClient ?? (effectiveRuntimeMode == .mock ? communityAPIClient : nil)
    }

    private func knownMemberCount(serverID: ServerID) -> Int {
        snapshot.membersByServerAndUserID.values.filter { $0.id.serverID == serverID }.count
    }

    private func missingUserCount(serverID: ServerID) -> Int {
        snapshot.membersByServerAndUserID.values.filter { member in
            member.id.serverID == serverID && snapshot.usersByID[member.id.userID] == nil
        }.count
    }

    private func cachedSelectedTimelineMessageGroups() -> [TimelineMessageGroup] {
        let messages = selectedTimelineMessages
        let key = timelineGroupCacheKey(messages: messages)
        if key == selectedTimelineGroupCacheKey {
            updateTimelinePerformanceDiagnostics(messages: messages, groups: selectedTimelineGroupCache)
            updateFreezePerformanceDiagnostics(marker: "timeline grouping cache hit")
            return selectedTimelineGroupCache
        }
        let started = Date()
        let groups = TimelineMessageGrouping.group(messages)
        selectedTimelineGroupCacheKey = key
        selectedTimelineGroupCache = groups
        freezePerformanceDiagnostics.timelineRenderPassCount += 1
        updateTimelinePerformanceDiagnostics(messages: messages, groups: groups, elapsed: Date().timeIntervalSince(started))
        return groups
    }

    private func timelineGroupCacheKey(messages: [TimelineMessage]) -> String {
        guard let channelID = selectedConversationChannelID else { return "none" }
        let newest = messages.last?.message.id.rawValue ?? "-"
        let oldest = messages.first?.message.id.rawValue ?? "-"
        let pending = messages.filter { $0.status != .confirmed }.map { $0.id.rawValue }.joined(separator: ",")
        return "\(channelID.rawValue)|\(messages.count)|\(oldest)|\(newest)|\(pending)"
    }

    private func memberListCacheKey(serverID: ServerID, query: String) -> String {
        let memberVersion = snapshot.membersByServerAndUserID.values
            .filter { $0.id.serverID == serverID }
            .map { member in
                "\(member.id.userID.rawValue):\(member.nickname ?? ""):\(member.roles.map(\.rawValue).joined(separator: ",")):\(member.avatar?.id.rawValue ?? "-")"
            }
            .sorted()
            .joined(separator: "|")
        let userVersion = snapshot.usersByID.values
            .map { "\($0.id.rawValue):\($0.displayName ?? ""):\($0.username):\($0.online):\($0.avatar?.id.rawValue ?? "-")" }
            .sorted()
            .joined(separator: "|")
        return "\(serverID.rawValue)|\(query)|\(memberVersion)|\(userVersion)"
    }

    private func updateTimelinePerformanceDiagnostics(messages: [TimelineMessage], groups: [TimelineMessageGroup], elapsed: TimeInterval? = nil) {
        timelinePerformanceDiagnostics = makeTimelinePerformanceDiagnostics(messages: messages, groups: groups, elapsed: elapsed)
        updateFreezePerformanceDiagnostics(marker: timelinePerformanceDiagnostics.lastSlowOperation)
    }

    private func makeTimelinePerformanceDiagnostics(messages: [TimelineMessage], groups: [TimelineMessageGroup], elapsed: TimeInterval? = nil) -> TimelinePerformanceDiagnostics {
        let visibleCount = selectedConversationChannelID.flatMap { visibleMessageIDsByChannelID[$0]?.count } ?? 0
        return TimelinePerformanceDiagnostics(
            loadedMessageCount: messages.count,
            renderedMessageEstimate: visibleCount == 0 ? min(messages.count, 80) : visibleCount,
            groupedMessageCount: groups.count,
            markdownCacheCount: 0,
            embedCacheCount: 0,
            avatarLoadQueueCount: imageResourceQueueCount,
            visibleRangeUpdateCount: timelineVisibleRangeUpdateCount,
            lastSlowOperation: elapsed.map { $0 > 0.05 ? "timeline grouping \(Int($0 * 1000))ms" : nil } ?? timelinePerformanceDiagnostics.lastSlowOperation
        )
    }

    private func missingVisibleUserIDs() -> Set<UserID> {
        var ids = Set<UserID>()
        for message in selectedTimelineMessages {
            if snapshot.usersByID[message.message.authorID] == nil {
                ids.insert(message.message.authorID)
            }
        }
        if let channel = selectedConversationChannel, DMChannelClassifier.isDirectMessageLike(channel) {
            for id in channel.recipients where snapshot.usersByID[id] == nil {
                ids.insert(id)
            }
        }
        if let serverID = selection.serverID {
            for member in snapshot.membersByServerAndUserID.values where member.id.serverID == serverID && snapshot.usersByID[member.id.userID] == nil {
                ids.insert(member.id.userID)
            }
        }
        return ids
    }

    public var selectedServerMember: ServerMember? {
        guard let serverID = selection.serverID, let currentUserID else { return nil }
        return snapshot.membersByServerAndUserID[ServerMemberKey(serverID: serverID, userID: currentUserID)]
    }

    public var selectedMemberDetail: ServerMember? {
        guard let selectedMemberDetailID else { return nil }
        return snapshot.membersByServerAndUserID[ServerMemberKey(selectedMemberDetailID)]
    }

    public func memberManagementItems(for details: ServerSettingsDetails) -> [MemberManagementItem] {
        let query = memberSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let items = details.members.map { member in
            MemberManagementItem(member: member, user: snapshot.usersByID[member.id.userID], server: details.server)
        }
        guard !query.isEmpty else { return items }
        return items.filter { item in
            item.displayName.localizedCaseInsensitiveContains(query)
                || item.username.localizedCaseInsensitiveContains(query)
                || item.roles.contains { $0.name.localizedCaseInsensitiveContains(query) }
                || (isDeveloperControlsEnabled && item.member.id.userID.rawValue.localizedCaseInsensitiveContains(query))
        }
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
            localReadStates: localReadStates,
            notificationPreferences: notificationPreferences,
            selectedChannelID: selectedConversationChannelID
        )
    }

    public var incomingFriendRequestCount: Int {
        Phase22Derivations.pendingIncomingCount(snapshot: snapshot, currentUserID: currentUserID, currentUser: currentUser)
    }

    public var canRefreshDMs: Bool {
        effectiveRuntimeMode == .mock ||
            (effectiveRuntimeMode == .liveManual && effectiveSessionState == .connected)
    }

    public func relationshipStatus(for user: User) -> RelationshipStatus {
        Phase22Derivations.relationshipStatus(for: user, currentUserID: currentUserID, currentUser: currentUser)
    }

    public func openFriends(tab: FriendsTab = .online) {
        friendsTab = tab
        selectDirectMessages()
    }

    public func openSavedNotes(source: DMOpenSource = .savedNotes) async {
        guard let currentUserID else {
            relationshipActionStatus = "Sign in before opening Saved Notes."
            failDMOpen(userID: UserID(rawValue: "current-user"), source: source, category: .authentication, message: "Sign in before opening Saved Notes.")
            return
        }
        await openDirectMessage(with: currentUserID, source: source)
    }

    public func showUserProfile(_ userID: UserID, source: ProfileOpenSource = .unknown, serverID explicitServerID: ServerID? = nil) {
        let serverID = explicitServerID ?? serverContextForProfile(userID: userID)
        profilePresentationContext = profileContext(userID: userID, serverID: serverID, source: source)
        profileSelectedTab = .profile
        profileUserID = userID
        selection.selectedUserID = userID
        Task { [weak self] in await self?.fetchUserProfileIfNeeded(userID) }
    }

    public func closeUserProfile() {
        profileUserID = nil
        profilePresentationContext = nil
    }

    public func setCurrentUserPresence(_ presence: Presence) async {
        guard let userID = currentUserID,
              let apiClient = apiClientForCommunityAction()
        else {
            statusUpdateStatus = "Reconnect before changing status."
            placeholderStatus = statusUpdateStatus
            return
        }

        let originalUser = currentUserForPresentation
        let existingStatus = originalUser?.status ?? UserStatus()
        var optimistic = originalUser ?? User(id: userID, username: UserDisplayResolver.shortenedID(userID))
        optimistic.status = UserStatus(text: existingStatus.text, presence: presence)
        optimistic.online = presence != .invisible
        upsertUser(optimistic)
        statusUpdateStatus = "Changing status to \(presence.displayName)..."
        placeholderStatus = statusUpdateStatus

        do {
            let updated = try await apiClient.editUser(userID: userID, draft: UserEditDraft(status: UserStatus(text: existingStatus.text, presence: presence)))
            upsertUser(updated)
            statusUpdateStatus = "Status changed to \(presence.displayName)."
            placeholderStatus = statusUpdateStatus
        } catch {
            if let originalUser {
                upsertUser(originalUser)
            }
            statusUpdateStatus = "Status change failed: \(error.userFacingMessage)"
            placeholderStatus = statusUpdateStatus
        }
    }

    public func fetchUserProfileIfNeeded(_ userID: UserID) async {
        guard userProfilesByID[userID] == nil,
              !profileLoadingUserIDs.contains(userID)
        else { return }
        guard let apiClient = sessionCoordinator?.apiClient ?? (effectiveRuntimeMode == .mock ? communityAPIClient : nil)
        else { return }
        profileLoadingUserIDs.insert(userID)
        profileErrorsByID[userID] = nil
        do {
            let profile = try await apiClient.fetchUserProfile(userID: userID)
            userProfilesByID[userID] = profile
            profileFetchMergeCount += 1
            updateVisibleIdentityDiagnostics()
            if profilePresentationContext?.userID == userID {
                profilePresentationContext = profileContext(userID: userID, serverID: profilePresentationContext?.serverID, source: profilePresentationContext?.openSource ?? .unknown)
            }
        } catch {
            profileErrorsByID[userID] = "Profile unavailable."
        }
        profileLoadingUserIDs.remove(userID)
    }

    public func openProfileEditorFromProfile() {
        selectedSettingsTab = .account
        isCredentialSetupPresented = true
        prepareProfileEditor(force: true)
        Task { [weak self] in await self?.ensureCurrentUserProfileForEditing() }
    }

    public func prepareProfileEditor(force: Bool = false) {
        guard let user = currentUserForPresentation else {
            if force || profileEditDraft.userID != nil {
                profileEditDraft = ProfileEditDraftState()
            }
            return
        }
        if !force,
           profileEditDraft.userID == user.id,
           (profileEditDraft.isDirty || profileEditDraft.isSaving) {
            return
        }
        profileEditDraft = ProfileEditDraftState(user: user, profile: userProfilesByID[user.id])
    }

    public func ensureCurrentUserProfileForEditing() async {
        guard let user = currentUserForPresentation else {
            prepareProfileEditor(force: true)
            return
        }
        await fetchUserProfileIfNeeded(user.id)
        if !profileEditDraft.isDirty && !profileEditDraft.isSaving {
            prepareProfileEditor(force: true)
        }
    }

    public var canSaveProfileEdit: Bool {
        profileEditDraft.canSave
    }

    public func cancelProfileEdit() {
        prepareProfileEditor(force: true)
    }

    public func chooseProfileAvatar() {
        chooseProfileMedia(kind: .avatar)
    }

    public func chooseProfileBackground() {
        chooseProfileMedia(kind: .background)
    }

    public func removeProfileAvatar() {
        profileEditDraft.safeErrorMessage = nil
        profileEditDraft.saveStatusMessage = nil
        profileEditDraft.avatarChange = profileEditDraft.originalAvatarFileID == nil ? .unchanged : .remove
    }

    public func removeProfileBackground() {
        profileEditDraft.safeErrorMessage = nil
        profileEditDraft.saveStatusMessage = nil
        profileEditDraft.backgroundChange = profileEditDraft.originalBackgroundFileID == nil ? .unchanged : .remove
    }

    public func stageProfileMedia(_ draft: ProfileEditMediaDraft) {
        profileEditDraft.safeErrorMessage = nil
        profileEditDraft.saveStatusMessage = nil
        switch draft.kind {
        case .avatar:
            profileEditDraft.avatarChange = .upload(draft)
        case .background:
            profileEditDraft.backgroundChange = .upload(draft)
        }
    }

    public func stageProfileMediaData(kind: ProfileEditMediaKind, data: Data, filename: String, mimeType: String) throws {
        let draft = try profileMediaValidationPolicy.draft(data: data, filename: filename, mimeType: mimeType, kind: kind)
        stageProfileMedia(draft)
    }

    public func stageProfileMediaFile(url: URL, kind: ProfileEditMediaKind) async {
        do {
            let draft = try profileMediaValidationPolicy.draft(for: url, kind: kind)
            stageProfileMedia(draft)
            profileEditDiagnostics = ProfileEditDiagnostics(
                lastAction: "staged \(kind.rawValue)",
                editedFieldCategories: profileEditDraft.editedFieldCategories,
                uploadTagCategory: kind.uploadTagCategory,
                uploadResultCategory: .skipped,
                mutationResultCategory: .idle
            )
        } catch {
            let category = ProfileEditSafeErrorCategory.categorize(error)
            profileEditDraft.safeErrorMessage = category.userFacingMessage
            profileEditDiagnostics = ProfileEditDiagnostics(
                lastAction: "stage \(kind.rawValue) failed",
                editedFieldCategories: profileEditDraft.editedFieldCategories,
                uploadTagCategory: kind.uploadTagCategory,
                uploadResultCategory: .failed,
                mutationResultCategory: .skipped,
                safeErrorCategory: category
            )
        }
    }

    public func saveProfileEdit() async {
        guard profileEditDraft.canSave else { return }
        guard let userID = currentUserID,
              let originalUser = currentUserForPresentation
        else {
            failProfileEdit(error: ProfileEditValidationError.missingCurrentUser, action: "save failed")
            return
        }
        guard let apiClient = apiClientForCommunityAction() else {
            failProfileEdit(error: ProfileEditValidationError.missingClient, action: "save failed")
            return
        }

        let started = Date()
        let originalProfile = userProfilesByID[userID]
        let stagedDraft = profileEditDraft
        var remove: [UserEditRemovedField] = []
        var displayName: String?
        var profileContent: String?
        var avatarUpload: ProfileEditMediaDraft?
        var backgroundUpload: ProfileEditMediaDraft?
        var uploadTagCategories: Set<ProfileEditUploadTagCategory> = []

        profileEditDraft.isSaving = true
        profileEditDraft.safeErrorMessage = nil
        profileEditDraft.saveStatusMessage = nil
        profileEditDiagnostics = ProfileEditDiagnostics(
            lastAction: "save started",
            routeCategory: .currentUserPatch,
            editedFieldCategories: stagedDraft.editedFieldCategories,
            uploadTagCategory: .none,
            uploadResultCategory: .skipped,
            mutationResultCategory: .pending,
            returnedDataShape: .none
        )

        do {
            let displayChange = try displayNameMutation(from: stagedDraft)
            displayName = displayChange.value
            if displayChange.remove {
                remove.append(.displayName)
            }

            let profileContentChange = try profileContentMutation(from: stagedDraft)
            profileContent = profileContentChange.value
            if profileContentChange.remove {
                remove.append(.profileContent)
            }

            switch stagedDraft.avatarChange {
            case .unchanged:
                break
            case .remove:
                remove.append(.avatar)
            case let .upload(draft):
                avatarUpload = draft
                uploadTagCategories.insert(.avatars)
            }

            switch stagedDraft.backgroundChange {
            case .unchanged:
                break
            case .remove:
                remove.append(.profileBackground)
            case let .upload(draft):
                backgroundUpload = draft
                uploadTagCategories.insert(.backgrounds)
            }
        } catch {
            failProfileEdit(error: error, action: "validation failed", started: started, fields: stagedDraft.editedFieldCategories)
            return
        }

        var uploadedAvatar: (fileID: FileID, draft: ProfileEditMediaDraft)?
        var uploadedBackground: (fileID: FileID, draft: ProfileEditMediaDraft)?
        do {
            if let avatarUpload {
                uploadedAvatar = try await uploadProfileMedia(avatarUpload, apiClient: apiClient, started: started, fields: stagedDraft.editedFieldCategories, uploadTagCategories: uploadTagCategories)
            }
            if let backgroundUpload {
                uploadedBackground = try await uploadProfileMedia(backgroundUpload, apiClient: apiClient, started: started, fields: stagedDraft.editedFieldCategories, uploadTagCategories: uploadTagCategories)
            }
        } catch {
            let category = ProfileEditSafeErrorCategory.uploadCategory(error)
            profileEditDraft.isSaving = false
            profileEditDraft.safeErrorMessage = category.userFacingMessage
            profileEditDiagnostics = ProfileEditDiagnostics(
                lastAction: "upload failed",
                routeCategory: .currentUserPatch,
                editedFieldCategories: stagedDraft.editedFieldCategories,
                uploadTagCategory: uploadTagCategory(from: uploadTagCategories),
                uploadResultCategory: .failed,
                mutationResultCategory: .skipped,
                durationMilliseconds: durationMilliseconds(since: started),
                safeErrorCategory: category,
                returnedDataShape: .none
            )
            return
        }

        let profileDraft = profileEditPayload(content: profileContent, backgroundFileID: uploadedBackground?.fileID)
        let mutationDraft = UserEditDraft(
            displayName: displayName,
            avatar: uploadedAvatar?.fileID.rawValue,
            profile: profileDraft,
            remove: remove
        )

        do {
            let updated = try await apiClient.editUser(userID: userID, draft: mutationDraft)
            upsertUser(updated)
            let overlayProfile = overlayProfileAfterEdit(
                userID: userID,
                original: originalProfile,
                profileContent: profileContent,
                removedContent: remove.contains(.profileContent),
                uploadedBackground: uploadedBackground,
                removedBackground: remove.contains(.profileBackground)
            )
            if stagedDraft.editedFieldCategories.contains(.profileContent) || stagedDraft.editedFieldCategories.contains(.profileBackground) {
                userProfilesByID[userID] = overlayProfile
            }
            let invalidationCount = await invalidateProfileEditImageCaches(
                oldUser: originalUser,
                oldProfile: originalProfile,
                newUser: updated,
                newProfile: overlayProfile,
                uploadedAvatar: uploadedAvatar,
                uploadedBackground: uploadedBackground
            )
            if profilePresentationContext?.userID == userID {
                profilePresentationContext = profileContext(userID: userID, serverID: profilePresentationContext?.serverID, source: profilePresentationContext?.openSource ?? .unknown)
            }
            profileEditDraft = ProfileEditDraftState(user: updated, profile: overlayProfile)
            profileEditDraft.saveStatusMessage = "Profile updated."
            placeholderStatus = "Profile updated."
            profileEditDiagnostics = ProfileEditDiagnostics(
                lastAction: "save succeeded",
                routeCategory: .currentUserPatch,
                editedFieldCategories: stagedDraft.editedFieldCategories,
                uploadTagCategory: uploadTagCategory(from: uploadTagCategories),
                uploadResultCategory: uploadTagCategories.isEmpty ? .skipped : .succeeded,
                mutationResultCategory: .succeeded,
                durationMilliseconds: durationMilliseconds(since: started),
                cacheInvalidationCount: invalidationCount,
                returnedDataShape: .fullUser
            )
        } catch {
            let category = ProfileEditSafeErrorCategory.categorize(error)
            profileEditDraft.isSaving = false
            profileEditDraft.safeErrorMessage = category.userFacingMessage
            profileEditDiagnostics = ProfileEditDiagnostics(
                lastAction: "mutation failed",
                routeCategory: .currentUserPatch,
                editedFieldCategories: stagedDraft.editedFieldCategories,
                uploadTagCategory: uploadTagCategory(from: uploadTagCategories),
                uploadResultCategory: uploadTagCategories.isEmpty ? .skipped : .succeeded,
                mutationResultCategory: .failed,
                durationMilliseconds: durationMilliseconds(since: started),
                safeErrorCategory: category,
                returnedDataShape: category == .decode ? .decodeFailed : .none
            )
        }
    }

    public func copyRedactedProfileEditDiagnostics() async {
        let text = ProfileEditDiagnosticsFormatter.redactedText(profileEditDiagnostics)
        await messageCopier.copy(text)
    }

    @discardableResult
    public func invalidateImageResource(for file: File?, kind: ImageResourceKind) async -> Int {
        guard let file else { return 0 }
        let key = ImageCacheKey(id: file.id.rawValue, kind: kind)
        loadedImageResources.removeValue(forKey: key)
        imageResourceStates.removeValue(forKey: key)
        queuedImageResourceRequests.removeValue(forKey: key)
        imageResourceLoadTasks[key]?.cancel()
        imageResourceLoadTasks.removeValue(forKey: key)
        await imageMemoryCache.remove(key)
        return 1
    }

    private func chooseProfileMedia(kind: ProfileEditMediaKind) {
        #if canImport(AppKit)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        panel.prompt = "Choose"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { [weak self] in
                await self?.stageProfileMediaFile(url: url, kind: kind)
            }
        }
        #else
        failProfileEdit(error: ProfileEditValidationError.unsupportedFileType, action: "file chooser unavailable")
        #endif
    }

    private func displayNameMutation(from draft: ProfileEditDraftState) throws -> (value: String?, remove: Bool) {
        let original = draft.originalDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard current != original else { return (nil, false) }
        if current.isEmpty {
            return (nil, true)
        }
        guard current.count >= 2, current.count <= 32 else {
            throw ProfileEditValidationError.invalidDisplayName
        }
        return (current, false)
    }

    private func profileContentMutation(from draft: ProfileEditDraftState) throws -> (value: String?, remove: Bool) {
        let original = draft.originalProfileContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : draft.originalProfileContent
        let current = draft.profileContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : draft.profileContent
        guard current != original else { return (nil, false) }
        guard current.count <= 2_000 else {
            throw ProfileEditValidationError.profileContentTooLong
        }
        if current.isEmpty {
            return (nil, true)
        }
        return (current, false)
    }

    private func profileEditPayload(content: String?, backgroundFileID: FileID?) -> UserProfileEditDraft? {
        guard content != nil || backgroundFileID != nil else { return nil }
        return UserProfileEditDraft(content: content, background: backgroundFileID?.rawValue)
    }

    private func uploadProfileMedia(
        _ draft: ProfileEditMediaDraft,
        apiClient: any StoatAPIClient,
        started: Date,
        fields: Set<ProfileEditFieldCategory>,
        uploadTagCategories: Set<ProfileEditUploadTagCategory>
    ) async throws -> (fileID: FileID, draft: ProfileEditMediaDraft) {
        profileEditDiagnostics = ProfileEditDiagnostics(
            lastAction: "uploading \(draft.kind.rawValue)",
            routeCategory: .currentUserPatch,
            editedFieldCategories: fields,
            uploadTagCategory: uploadTagCategory(from: uploadTagCategories),
            uploadResultCategory: .pending,
            mutationResultCategory: .skipped,
            durationMilliseconds: durationMilliseconds(since: started)
        )
        let uploaded = try await apiClient.uploadFile(
            data: draft.data,
            filename: draft.filename,
            mimeType: draft.mimeType,
            tag: draft.kind.uploadTag
        )
        return (uploaded.id, draft)
    }

    private func overlayProfileAfterEdit(
        userID: UserID,
        original: UserProfile?,
        profileContent: String?,
        removedContent: Bool,
        uploadedBackground: (fileID: FileID, draft: ProfileEditMediaDraft)?,
        removedBackground: Bool
    ) -> UserProfile {
        var profile = original ?? userProfilesByID[userID] ?? UserProfile()
        if removedContent {
            profile.content = nil
        } else if let profileContent {
            profile.content = profileContent
        }
        if removedBackground {
            profile.background = nil
        } else if let uploadedBackground {
            profile.background = profileMediaFile(id: uploadedBackground.fileID, draft: uploadedBackground.draft, userID: userID)
        }
        return profile
    }

    private func profileMediaFile(id: FileID, draft: ProfileEditMediaDraft, userID: UserID) -> File {
        File(
            id: id,
            tag: draft.kind.uploadTag.rawAPIValue,
            filename: draft.filename,
            metadata: .file,
            contentType: draft.mimeType,
            size: draft.byteCount,
            userID: userID
        )
    }

    private func invalidateProfileEditImageCaches(
        oldUser: User?,
        oldProfile: UserProfile?,
        newUser: User,
        newProfile: UserProfile,
        uploadedAvatar: (fileID: FileID, draft: ProfileEditMediaDraft)?,
        uploadedBackground: (fileID: FileID, draft: ProfileEditMediaDraft)?
    ) async -> Int {
        var keys: Set<ImageCacheKey> = []
        func add(_ file: File?, _ kind: ImageResourceKind) {
            guard let file else { return }
            keys.insert(ImageCacheKey(id: file.id.rawValue, kind: kind))
        }
        add(oldUser?.avatar, .userAvatar)
        add(newUser.avatar, .userAvatar)
        add(oldProfile?.background, .profileBackground)
        add(newProfile.background, .profileBackground)
        for key in keys {
            loadedImageResources.removeValue(forKey: key)
            imageResourceStates.removeValue(forKey: key)
            queuedImageResourceRequests.removeValue(forKey: key)
            imageResourceLoadTasks[key]?.cancel()
            imageResourceLoadTasks.removeValue(forKey: key)
            await imageMemoryCache.remove(key)
        }
        if let uploadedAvatar, let avatar = newUser.avatar {
            loadedImageResources[ImageCacheKey(id: avatar.id.rawValue, kind: .userAvatar)] = uploadedAvatar.draft.previewData ?? uploadedAvatar.draft.data
        }
        if let uploadedBackground, let background = newProfile.background {
            loadedImageResources[ImageCacheKey(id: background.id.rawValue, kind: .profileBackground)] = uploadedBackground.draft.previewData ?? uploadedBackground.draft.data
        }
        return keys.count
    }

    private func uploadTagCategory(from categories: Set<ProfileEditUploadTagCategory>) -> ProfileEditUploadTagCategory {
        let tags = categories.filter { $0 != .none }
        if tags.count > 1 { return .multiple }
        return tags.first ?? .none
    }

    private func failProfileEdit(
        error: any Error,
        action: String,
        started: Date? = nil,
        fields: Set<ProfileEditFieldCategory>? = nil
    ) {
        let category = ProfileEditSafeErrorCategory.categorize(error)
        profileEditDraft.isSaving = false
        profileEditDraft.safeErrorMessage = category.userFacingMessage
        profileEditDiagnostics = ProfileEditDiagnostics(
            lastAction: action,
            routeCategory: .currentUserPatch,
            editedFieldCategories: fields ?? profileEditDraft.editedFieldCategories,
            uploadTagCategory: .none,
            uploadResultCategory: .skipped,
            mutationResultCategory: .skipped,
            durationMilliseconds: started.map { durationMilliseconds(since: $0) },
            safeErrorCategory: category,
            returnedDataShape: category == .decode ? .decodeFailed : .none
        )
    }

    public func refreshRelationshipsAndDirectMessages() async {
        guard effectiveRuntimeMode != .mock else {
            await refreshDMs(source: .friends)
            return
        }
        guard effectiveRuntimeMode == .liveManual,
              effectiveSessionState == .connected,
              let apiClient = sessionCoordinator?.apiClient
        else {
            relationshipActionStatus = "Reconnect before refreshing friends and DMs."
            recordDMRefreshSkipped(source: .friends, category: .authentication)
            return
        }
        isRelationshipRefreshInProgress = true
        let started = Date()
        beginDMRefresh(source: .friends)
        defer { isRelationshipRefreshInProgress = false }
        do {
            let user = try await apiClient.fetchCurrentUser()
            applyRelationshipUser(user)
            let dms = try await apiClient.fetchDirectMessages()
            finishDMRefresh(channels: dms, source: .friends, started: started, successMessage: "Friends and DMs refreshed")
        } catch {
            failDMRefresh(error, source: .friends, started: started, userMessage: "Refresh failed.")
        }
    }

    public func refreshDMs(source: DMRefreshSource = .explicit) async {
        guard let apiClient = apiClientForDMRefresh(source: source) else { return }
        isRelationshipRefreshInProgress = true
        let started = Date()
        beginDMRefresh(source: source)
        defer { isRelationshipRefreshInProgress = false }
        do {
            let channels = try await apiClient.fetchDirectMessages()
            finishDMRefresh(channels: channels, source: source, started: started, successMessage: "DMs refreshed")
        } catch {
            failDMRefresh(error, source: source, started: started, userMessage: "DM refresh failed.")
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

    public func openDirectMessage(with userID: UserID, source: DMOpenSource = .directCall, forceNetwork: Bool = false) async {
        beginDMOpen(userID: userID, source: source)
        if !forceNetwork, let existing = knownDirectMessageChannel(for: userID) {
            selectChannel(existing.id)
            dmLiveTrace.clickedUserID = userID
            dmLiveTrace.clickedRowID = "user-\(userID.rawValue)"
            finishDMOpen(channelID: existing.id, userID: userID, source: source)
            return
        }
        guard !openingDirectMessageUserIDs.contains(userID) else {
            relationshipActionStatus = "Direct message is already opening."
            var diagnostics = dmDiagnostics
            diagnostics.lastOpenStatus = .skipped
            diagnostics.lastOpenSource = source
            diagnostics.lastOpenTarget = userID.rawValue
            dmDiagnostics = diagnostics
            refreshDMDiagnosticsSnapshot()
            return
        }
        openingDirectMessageUserIDs.insert(userID)
        defer {
            openingDirectMessageUserIDs.remove(userID)
        }
        if effectiveRuntimeMode == .mock {
            let channel = Channel(
                id: ChannelID(rawValue: "mock-dm-\(userID.rawValue)"),
                kind: userID == currentUserID ? .savedMessages : .directMessage,
                userID: userID == currentUserID ? currentUserID : nil,
                active: true,
                recipients: [currentUserID, userID].compactMap { $0 }
            )
            _ = mergeDMChannels([channel], source: .mock)
            selectChannel(channel.id)
            dmLiveTrace.clickedUserID = userID
            dmLiveTrace.clickedRowID = "user-\(userID.rawValue)"
            relationshipActionStatus = "Direct message opened"
            finishDMOpen(channelID: channel.id, userID: userID, source: source)
            return
        }
        guard let apiClient = availableRelationshipAPIClient() else {
            failDMOpen(userID: userID, source: source, category: .authentication, message: "Reconnect before opening direct messages.")
            return
        }
        do {
            let channel = try await apiClient.openDirectMessage(userID: userID)
            _ = mergeDMChannels([channel], source: .explicit)
            selectChannel(channel.id)
            dmLiveTrace.clickedUserID = userID
            dmLiveTrace.clickedRowID = "user-\(userID.rawValue)"
            relationshipActionStatus = "Direct message opened"
            finishDMOpen(channelID: channel.id, userID: userID, source: source)
        } catch {
            relationshipActionStatus = "Could not open direct message."
            let category = DMSafeErrorCategory.categorize(error)
            dmLiveTrace = DirectMessageLiveTrace(
                clickedRowID: "user-\(userID.rawValue)",
                clickedUserID: userID,
                clickedChannelExistsInSnapshot: false,
                selectedSpaceBefore: String(describing: selection.space),
                selectedSpaceAfter: String(describing: selection.space),
                selectedServerIDBefore: selection.serverID,
                selectedServerIDAfter: selection.serverID,
                selectedChannelIDBefore: selection.channelID ?? selection.dmChannelID,
                selectedChannelIDAfter: selection.channelID ?? selection.dmChannelID,
                selectedConversationChannelID: selectedConversationChannelID,
                lastError: "Could not open direct message."
            )
            failDMOpen(userID: userID, source: source, category: category, message: "Could not open direct message.")
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
            relationshipActionStatus = "Reconnect before using friend and DM actions."
            return nil
        }
        return apiClient
    }

    private func apiClientForDMRefresh(source: DMRefreshSource) -> (any StoatAPIClient)? {
        if effectiveRuntimeMode == .mock {
            return communityAPIClient
        }
        guard effectiveRuntimeMode == .liveManual,
              effectiveSessionState == .connected,
              let apiClient = sessionCoordinator?.apiClient
        else {
            relationshipActionStatus = "Reconnect before refreshing DMs."
            recordDMRefreshSkipped(source: source, category: .authentication)
            return nil
        }
        return apiClient
    }

    private func beginDMRefresh(source: DMRefreshSource) {
        var diagnostics = dmDiagnostics
        diagnostics.lastRefreshStatus = .loading
        diagnostics.lastRefreshSource = source
        diagnostics.lastRefreshErrorCategory = nil
        dmDiagnostics = diagnostics
        refreshDMDiagnosticsSnapshot()
    }

    private func finishDMRefresh(channels: [Channel], source: DMRefreshSource, started: Date, successMessage: String) {
        let result = mergeDMChannels(channels, source: source)
        var diagnostics = dmDiagnostics
        diagnostics.lastRefreshStatus = .succeeded
        diagnostics.lastRefreshSource = source
        diagnostics.lastRefreshCount = result.returnedCount
        diagnostics.lastRefreshDurationMilliseconds = durationMilliseconds(since: started)
        diagnostics.lastRefreshErrorCategory = nil
        diagnostics.duplicateMergeCount += result.updatedCount + result.duplicateCount
        dmDiagnostics = diagnostics
        refreshDMDiagnosticsSnapshot()
        relationshipActionStatus = nil
        placeholderStatus = successMessage
        lastTimelineActionResult = successMessage
        quickSwitcherViewModel.update(snapshot: snapshot, selection: selection)
        loadVisibleIdentityImagesForCurrentSelection()
    }

    private func failDMRefresh(_ error: any Error, source: DMRefreshSource, started: Date, userMessage: String) {
        let category = DMSafeErrorCategory.categorize(error)
        var diagnostics = dmDiagnostics
        diagnostics.lastRefreshStatus = .failed
        diagnostics.lastRefreshSource = source
        diagnostics.lastRefreshDurationMilliseconds = durationMilliseconds(since: started)
        diagnostics.lastRefreshErrorCategory = category
        diagnostics = diagnostics.addingErrorCategory(category)
        dmDiagnostics = diagnostics
        refreshDMDiagnosticsSnapshot()
        relationshipActionStatus = userMessage
        placeholderStatus = userMessage
        lastTimelineActionResult = userMessage
    }

    private func recordDMRefreshSkipped(source: DMRefreshSource, category: DMSafeErrorCategory?) {
        var diagnostics = dmDiagnostics
        diagnostics.lastRefreshStatus = .skipped
        diagnostics.lastRefreshSource = source
        diagnostics.lastRefreshErrorCategory = category
        diagnostics = diagnostics.addingErrorCategory(category)
        dmDiagnostics = diagnostics
        refreshDMDiagnosticsSnapshot()
    }

    @discardableResult
    private func mergeDMChannels(_ channels: [Channel], source: DMRefreshSource) -> DMChannelMergeResult {
        var result = DMChannelMergeResult(source: source)
        var seenIDs: Set<ChannelID> = []
        for channel in channels where DMChannelClassifier.isDirectMessageLike(channel) {
            result.returnedCount += 1
            guard seenIDs.insert(channel.id).inserted else {
                result.duplicateCount += 1
                continue
            }
            let existing = snapshot.channelsByID[channel.id]
            if existing == nil {
                result.insertedCount += 1
            } else {
                result.updatedCount += 1
            }
            snapshot.channelsByID[channel.id] = mergedDMChannel(existing: existing, incoming: channel)
        }
        refreshDMDiagnosticsSnapshot()
        return result
    }

    private func mergedDMChannel(existing: Channel?, incoming: Channel) -> Channel {
        guard let existing else { return incoming }
        var merged = incoming
        if merged.userID == nil { merged.userID = existing.userID }
        if merged.serverID == nil { merged.serverID = existing.serverID }
        if merged.name == nil { merged.name = existing.name }
        if merged.ownerID == nil { merged.ownerID = existing.ownerID }
        if merged.description == nil { merged.description = existing.description }
        if merged.active == nil { merged.active = existing.active }
        if merged.recipients.isEmpty { merged.recipients = existing.recipients }
        if merged.icon == nil { merged.icon = existing.icon }
        if merged.lastMessageID == nil { merged.lastMessageID = existing.lastMessageID }
        if merged.permissions == nil { merged.permissions = existing.permissions }
        if merged.defaultPermissions == nil { merged.defaultPermissions = existing.defaultPermissions }
        if merged.rolePermissions.isEmpty { merged.rolePermissions = existing.rolePermissions }
        if merged.voice == nil { merged.voice = existing.voice }
        if merged.slowmode == nil { merged.slowmode = existing.slowmode }
        return merged
    }

    private func knownDirectMessageChannel(for userID: UserID) -> Channel? {
        if userID == currentUserID {
            return snapshot.channelsByID.values.first { channel in
                guard channel.kind == .savedMessages, DMChannelClassifier.isDirectMessageLike(channel) else { return false }
                return channel.userID == userID || channel.recipients.contains(userID) || currentUserID == userID
            }
        }
        return snapshot.channelsByID.values.first { channel in
            guard channel.kind == .directMessage,
                  DMChannelClassifier.isDirectMessageLike(channel),
                  channel.recipients.contains(userID)
            else { return false }
            if let currentUserID {
                return channel.recipients.contains(currentUserID)
            }
            return true
        }
    }

    private func beginDMOpen(userID: UserID, source: DMOpenSource) {
        var diagnostics = dmDiagnostics
        diagnostics.lastOpenStatus = .loading
        diagnostics.lastOpenSource = source
        diagnostics.lastOpenTarget = userID.rawValue
        diagnostics.lastOpenErrorCategory = nil
        if source == .savedNotes || userID == currentUserID {
            diagnostics.savedNotesState = .opening
        }
        dmDiagnostics = diagnostics
        refreshDMDiagnosticsSnapshot()
    }

    private func finishDMOpen(channelID: ChannelID, userID: UserID, source: DMOpenSource) {
        var diagnostics = dmDiagnostics
        diagnostics.lastOpenStatus = .succeeded
        diagnostics.lastOpenSource = source
        diagnostics.lastOpenTarget = userID.rawValue
        diagnostics.lastOpenErrorCategory = nil
        if snapshot.channelsByID[channelID]?.kind == .savedMessages {
            diagnostics.savedNotesState = .available(channelID)
        }
        dmDiagnostics = diagnostics
        refreshDMDiagnosticsSnapshot()
    }

    private func failDMOpen(userID: UserID, source: DMOpenSource, category: DMSafeErrorCategory, message: String) {
        var diagnostics = dmDiagnostics
        diagnostics.lastOpenStatus = .failed
        diagnostics.lastOpenSource = source
        diagnostics.lastOpenTarget = userID.rawValue
        diagnostics.lastOpenErrorCategory = category
        if source == .savedNotes || userID == currentUserID {
            diagnostics.savedNotesState = .failed(category)
        }
        diagnostics = diagnostics.addingErrorCategory(category)
        dmDiagnostics = diagnostics
        refreshDMDiagnosticsSnapshot()
        relationshipActionStatus = message
        placeholderStatus = message
    }

    private func refreshDMDiagnosticsSnapshot() {
        let dmChannels = snapshot.channelsByID.values.filter(DMChannelClassifier.isDirectMessageLike)
        var diagnostics = dmDiagnostics
        diagnostics.knownDirectMessageCount = dmChannels.filter { $0.kind == .directMessage }.count
        diagnostics.knownGroupDMCount = dmChannels.filter { $0.kind == .group }.count
        if let saved = dmChannels.first(where: { $0.kind == .savedMessages }) {
            diagnostics.savedNotesState = .available(saved.id)
        } else {
            switch diagnostics.savedNotesState {
            case .opening, .failed:
                break
            case .available, .unavailable:
                diagnostics.savedNotesState = .unavailable
            }
        }
        diagnostics.missingRecipientUserCount = dmChannels.reduce(0) { partial, channel in
            let ids: [UserID]
            if channel.kind == .savedMessages {
                ids = [currentUserID ?? channel.userID].compactMap { $0 }
            } else {
                ids = channel.recipients
            }
            return partial + ids.filter { !knownUserExists($0) }.count
        }
        diagnostics.rawIDFallbackCount = directMessageItems.filter(\.usesRawIDFallback).count
        let counts = NotificationBadgeCalculator.counts(snapshot: snapshot, preferences: notificationPreferences, localReadStates: localReadStates)
        diagnostics.unreadChannelCount = counts.unreadChannelCount
        diagnostics.mentionCount = counts.mentionCount
        diagnostics.locallyClearedUnreadCount = locallyClearedUnreadChannelIDs.count
        diagnostics.lastAckSummary = lastAckResult
        dmDiagnostics = diagnostics
    }

    private func knownUserExists(_ userID: UserID) -> Bool {
        snapshot.usersByID[userID] != nil || currentUser?.id == userID || sessionCoordinator?.currentUser?.id == userID
    }

    private func durationMilliseconds(since started: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(started) * 1000))
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
        invalidateIdentityPresentationCaches()
    }

    private func invalidateIdentityPresentationCaches() {
        memberListGroupCacheKey = nil
        selectedTimelineGroupCacheKey = nil
        if let context = profilePresentationContext {
            profilePresentationContext = profileContext(userID: context.userID, serverID: context.serverID, source: context.openSource)
        }
    }
    
    // MARK: - Diagnostics Updates

    private func updateVisibleIdentityDiagnostics() {
        let visibleDisplays = selectedTimelineMessages.map { resolvedUserDisplay(for: $0.message) }
            + memberListGroupCache.flatMap(\.items).map { item in
                resolvedUserDisplay(for: item.user, member: item.member, fallbackID: item.userID, serverID: item.member?.id.serverID)
            }
        let failedAvatars = imageResourceStates.filter { key, state in
            key.kind == .userAvatar && {
                if case .failed = state { return true }
                return false
            }()
        }.count
        visibleIdentityDiagnostics = VisibleIdentityDiagnostics(
            unresolvedVisibleUserCount: missingVisibleUserIDs().count,
            shortenedVisibleIDCount: visibleDisplays.filter(\.isFallback).count,
            avatarFailureCacheCount: failedAvatars,
            profileFetchMergeCount: profileFetchMergeCount,
            memberWrapperUserMergeCount: memberWrapperUserMergeCount
        )
    }

    private func updateFreezePerformanceDiagnostics(marker: String? = nil) {
        diagnosticsPublishCount += 1
        let failedImages = imageResourceStates.values.filter {
            if case .failed = $0 { return true }
            return false
        }.count
        let avatarActive = imageResourceLoadTasks.values.filter { $0.isCancelled == false }.count
        let avatarQueued = queuedImageResourceRequests.values.filter { $0.kind == .userAvatar }.count
        let avatarFailed = imageResourceStates.filter { key, state in
            key.kind == .userAvatar && {
                if case .failed = state { return true }
                return false
            }()
        }.count
        let emojiActive = imageResourceLoadTasks.values.count
        let emojiQueued = queuedImageResourceRequests.values.filter { $0.kind == .customEmoji }.count
        let profileQueued = queuedImageResourceRequests.values.filter { $0.kind == .profileBackground || $0.kind == .userAvatar }.count
        let markdown = MarkdownMessageContent.cacheDiagnostics()
        freezePerformanceDiagnostics = FreezePerformanceDiagnostics(
            lastMainThreadMarker: marker ?? freezePerformanceDiagnostics.lastMainThreadMarker,
            timelineRenderPassCount: freezePerformanceDiagnostics.timelineRenderPassCount,
            memberGroupingCount: memberGroupingCount,
            memberGroupingCacheHitCount: memberGroupingCacheHitCount,
            markdownParseCount: markdown.parseCount,
            markdownCacheHitCount: markdown.cacheHitCount,
            imageActiveCount: imageResourceLoadTasks.count,
            imageQueuedCount: queuedImageResourceRequests.count,
            imageCompletedCount: imageCompletedCount,
            imageFailedCount: failedImages,
            avatarActiveQueuedFailed: "\(avatarActive)/\(avatarQueued)/\(avatarFailed)",
            customEmojiActiveQueued: "\(emojiActive)/\(emojiQueued)",
            profileMediaActiveQueued: "0/\(profileQueued)",
            visibleRangeUpdateCount: timelineVisibleRangeUpdateCount,
            diagnosticsPublishCount: diagnosticsPublishCount,
            lastStateLoopSuspicion: freezePerformanceDiagnostics.lastStateLoopSuspicion,
            mediaSafeModeEnabled: freezePerformanceDiagnostics.mediaSafeModeEnabled
        )
    }

    private func showTransientStatus(_ message: String, keyPath: ReferenceWritableKeyPath<MainShellViewModel, String?> = \.placeholderStatus, duration: Duration = .seconds(2)) {
        self[keyPath: keyPath] = message
        transientStatusTask?.cancel()
        transientStatusTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            await MainActor.run {
                guard self?[keyPath: keyPath] == message else { return }
                self?[keyPath: keyPath] = nil
            }
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

    public func openJoinInvite(prefill: String = "") {
        isJoinInvitePresented = true
        if !prefill.isEmpty {
            inviteInput = prefill
            invitePreviewState = .idle
        }
        phase23Status = nil
    }

    public func previewInviteFromInput() async {
        invitePreviewState = .parsing
        let parsed = InviteCodeParser.parse(inviteInput)
        guard case let .code(code) = parsed else {
            if case let .invalid(message) = parsed {
                invitePreviewState = .failed(nil, message)
            }
            return
        }
        guard let apiClient = apiClientForCommunityAction() else {
            invitePreviewState = .failed(code, "Reconnect before previewing invites.")
            return
        }
        invitePreviewState = .loading(code)
        do {
            let preview = try await apiClient.fetchInvitePreview(code: code)
            invitePreviewState = .loaded(markAlreadyJoined(preview))
            loadImageResource(for: preview.serverIcon, kind: .serverIcon)
        } catch {
            invitePreviewState = .failed(code, Phase23Safety.safeError(error))
        }
    }

    public func requestJoinLoadedInvite() {
        guard case let .loaded(preview) = invitePreviewState else { return }
        if preview.isAlreadyJoined, let serverID = preview.serverID, snapshot.serversByID[serverID] != nil {
            selectJoinedInvitePreview(preview)
            return
        }
        pendingInviteJoin = PendingInviteJoin(code: preview.code, preview: preview)
    }

    public func confirmPendingInviteJoin() async {
        guard let pendingInviteJoin else { return }
        self.pendingInviteJoin = nil
        guard let apiClient = apiClientForCommunityAction() else {
            invitePreviewState = .failed(pendingInviteJoin.code, "Reconnect before joining an invite.")
            return
        }
        invitePreviewState = .loading(pendingInviteJoin.code)
        do {
            let joined = try await apiClient.joinInvite(code: pendingInviteJoin.code)
            switch joined {
            case let .server(server, channels):
                applyJoinedOrCreatedServer(server, channels: channels, status: "Joined \(server.name)")
                invitePreviewState = .loaded(pendingInviteJoin.preview.markingAlreadyJoined(true))
                isJoinInvitePresented = false
            case let .group(channel, users):
                for user in users { snapshot.usersByID[user.id] = user }
                snapshot.channelsByID[channel.id] = channel
                selectChannel(channel.id)
                invitePreviewState = .loaded(pendingInviteJoin.preview.markingAlreadyJoined(true))
                isJoinInvitePresented = false
                phase23Status = "Joined group"
            case .unknown:
                invitePreviewState = .failed(pendingInviteJoin.code, "Invite joined, waiting for server data.")
                phase23Status = "Joined, waiting for server data."
            }
        } catch {
            invitePreviewState = .failed(pendingInviteJoin.code, Phase23Safety.safeError(error))
        }
    }

    public func openCreateServer() {
        isCreateServerPresented = true
        serverCreateState = .idle
        phase23Status = nil
    }

    public func createServerFromDraft() async {
        guard let apiClient = apiClientForCommunityAction() else {
            serverCreateState = .failed("Reconnect before creating a server.")
            return
        }
        let draft = ServerCreateDraft(
            name: serverCreateName,
            description: serverCreateDescription,
            nsfw: serverCreateIsNSFW ? true : nil
        )
        guard let validated = draft.validatedForCreate else {
            serverCreateState = .failed("Server name must be 1 to 32 characters.")
            return
        }
        serverCreateState = .creating
        do {
            let response = try await apiClient.createServer(draft: validated)
            applyJoinedOrCreatedServer(response.server, channels: response.channels, status: "Created \(response.server.name)")
            serverCreateState = .created(response.server.id)
            isCreateServerPresented = false
            serverCreateName = ""
            serverCreateDescription = ""
            serverCreateIsNSFW = false
        } catch {
            serverCreateState = .failed(Phase23Safety.safeError(error))
        }
    }

    public func openInviteManagement() {
        isInviteManagementPresented = true
        phase23Status = nil
        inviteManagementState = .idle
    }

    public func refreshServerInvites() async {
        guard let serverID = selection.serverID else {
            inviteManagementState = .failed("Select a server before managing invites.")
            return
        }
        guard let apiClient = apiClientForCommunityAction() else {
            inviteManagementState = .failed("Reconnect before managing invites.")
            return
        }
        inviteManagementState = .loading
        do {
            inviteManagementState = .loaded(try await apiClient.fetchServerInvites(serverID: serverID))
        } catch {
            inviteManagementState = .failed(Phase23Safety.safeError(error))
        }
    }

    public func createInviteForSelectedChannel() async {
        let fallbackChannelID = selection.serverID.flatMap { firstVisibleTextChannel(in: $0)?.id }
        guard let channelID = selection.channelID ?? fallbackChannelID else {
            inviteManagementState = .failed("Select or create a text channel before creating an invite.")
            return
        }
        guard let apiClient = apiClientForCommunityAction() else {
            inviteManagementState = .failed("Reconnect before creating invites.")
            return
        }
        do {
            let invite = try await apiClient.createInvite(channelID: channelID)
            let code = InviteCode(rawValue: invite.id.rawValue)
            await messageCopier.copy(InviteCodeParser.inviteURLString(code: code))
            phase23Status = "Invite copied"
            await refreshServerInvites()
        } catch {
            inviteManagementState = .failed(Phase23Safety.safeError(error))
        }
    }

    public func copyInvite(_ invite: Invite) async {
        let code = InviteCode(rawValue: invite.id.rawValue)
        await messageCopier.copy(InviteCodeParser.inviteURLString(code: code))
        phase23Status = "Invite copied"
    }

    public func requestDeleteInvite(_ invite: Invite) {
        pendingInviteDeletion = PendingInviteDeletion(code: InviteCode(rawValue: invite.id.rawValue))
    }

    public func confirmPendingInviteDeletion() async {
        guard let pendingInviteDeletion else { return }
        self.pendingInviteDeletion = nil
        guard let apiClient = apiClientForCommunityAction() else {
            inviteManagementState = .failed("Reconnect before revoking invites.")
            return
        }
        do {
            try await apiClient.deleteInvite(code: pendingInviteDeletion.code)
            phase23Status = "Invite revoked"
            await refreshServerInvites()
        } catch {
            inviteManagementState = .failed(Phase23Safety.safeError(error))
        }
    }

    public func openDiscoverInBrowser() {
        guard let url = URL(string: "https://stt.gg/discover/servers") else { return }
        #if canImport(AppKit)
        NSWorkspace.shared.open(url)
        #endif
        phase23Status = "Opened Discover in browser"
    }

    private func apiClientForCommunityAction() -> (any StoatAPIClient)? {
        if effectiveRuntimeMode == .mock {
            return communityAPIClient
        }
        guard effectiveRuntimeMode == .liveManual,
              effectiveSessionState == .connected,
              let apiClient = sessionCoordinator?.apiClient
        else {
            return nil
        }
        return apiClient
    }

    private func markAlreadyJoined(_ preview: InvitePreview) -> InvitePreview {
        guard let serverID = preview.serverID else { return preview }
        return preview.markingAlreadyJoined(snapshot.serversByID[serverID] != nil)
    }

    private func selectJoinedInvitePreview(_ preview: InvitePreview) {
        if let channelID = preview.channelID as ChannelID?, snapshot.channelsByID[channelID] != nil {
            selectChannel(channelID)
        } else if let serverID = preview.serverID {
            selectServer(serverID)
        }
        isJoinInvitePresented = false
        phase23Status = "Opened joined server"
    }

    private func applyJoinedOrCreatedServer(_ server: Server, channels: [Channel], status: String) {
        snapshot = Phase23SnapshotIntegrator.upserting(server: server, channels: channels, into: snapshot)
        selection = Phase23SnapshotIntegrator.selection(for: server, channels: channels, memberPanelVisible: selection.isMemberPanelVisible)
        placeholderStatus = nil
        phase23Status = status
        quickSwitcherViewModel.update(snapshot: snapshot, selection: selection)
        validateSelection()
        messageController.hydrate(from: snapshot)
        scheduleSelectedChannelLoad()
        loadImageResource(for: server.icon, kind: .serverIcon)
        loadImageResource(for: server.banner, kind: .serverBanner)
    }

    public func serverManagementCapabilities() -> ServerManagementCapabilities {
        let fallbackChannel = selection.serverID.flatMap { firstVisibleTextChannel(in: $0) }
        return Phase24Management.capabilities(
            server: selectedServer,
            selectedChannel: selectedChannel ?? fallbackChannel,
            currentUserID: currentUserID,
            runtimeMode: effectiveRuntimeMode,
            sessionState: effectiveSessionState
        )
    }

    public func channelManagementDisabledReason(destructive: Bool = false) -> String? {
        Phase24Management.disabledReasonForChannelManagement(serverManagementCapabilities(), destructive: destructive)
    }

    public func channelContextMenuItems(for channel: Channel) -> [ChannelContextMenuItem] {
        let baseReason = channelManagementDisabledReason()
        let settingsReason: String?
        if channel.kind == .textChannel {
            settingsReason = baseReason
        } else {
            settingsReason = "Only text channels can be edited."
        }
        var items: [ChannelContextMenuItem] = [
            ChannelContextMenuItem(
                kind: .settings,
                title: "Channel Settings",
                systemImage: "slider.horizontal.3",
                disabledReason: settingsReason
            ),
            ChannelContextMenuItem(
                kind: .createChannel,
                title: "Create Channel",
                systemImage: "plus",
                disabledReason: baseReason
            )
        ]
        if isDeveloperControlsEnabled {
            items.append(ChannelContextMenuItem(kind: .copyChannelID, title: "Copy Channel ID", systemImage: "doc.on.doc", isDeveloperOnly: true))
        }
        let deleteReason: String?
        if channel.kind == .textChannel {
            deleteReason = channelManagementDisabledReason(destructive: true)
        } else {
            deleteReason = "Only text channels can be deleted."
        }
        items.append(ChannelContextMenuItem(kind: .deleteChannel, title: "Delete Channel", systemImage: "trash", disabledReason: deleteReason, isDestructive: true))
        return items
    }

    public func performChannelContextMenuAction(_ kind: ChannelContextMenuActionKind, for channel: Channel) {
        switch kind {
        case .settings:
            selectChannel(channel.id)
            openChannelSettings()
        case .createChannel:
            if channel.serverID != nil {
                selectChannel(channel.id)
            }
            openCreateChannel()
        case .copyChannelID:
            guard isDeveloperControlsEnabled else {
                placeholderStatus = "Developer channel ID copy is disabled."
                return
            }
            Task { [messageCopier] in
                await messageCopier.copy(channel.id.rawValue)
            }
            placeholderStatus = "Channel ID copied"
        case .deleteChannel:
            selectChannel(channel.id)
            requestDeleteSelectedChannel()
        }
    }

    public func inviteManagementDisabledReason() -> String? {
        Phase24Management.disabledReasonForInvites(serverManagementCapabilities())
    }

    public func serverOverviewDetails() -> ServerOverviewDetails? {
        guard let server = selectedServer else { return nil }
        return ServerOverviewDetails(
            server: server,
            channels: channels(for: server.id),
            memberCount: serverMembers(for: server.id).count,
            runtimeLine: runtimeSubtitleForManagement,
            capabilities: serverManagementCapabilities()
        )
    }

    public func serverSettingsDetails() -> ServerSettingsDetails? {
        guard let server = selectedServer else { return nil }
        let fallbackChannel = selectedChannel ?? firstVisibleTextChannel(in: server.id)
        let permissionPreview = Phase25PermissionResolver.resolve(server: server, channel: fallbackChannel, member: selectedServerMember, currentUserID: currentUserID)
        return ServerSettingsDetails(
            server: server,
            channels: channels(for: server.id),
            members: serverMembers(for: server.id),
            runtimeLine: runtimeSubtitleForManagement,
            capabilities: serverManagementCapabilities(),
            permissionPreview: permissionPreview
        )
    }

    public func openServerOverview() {
        lastServerSettingsButtonAction = selectedServer.map { "opened \($0.id.rawValue)" } ?? "blocked: no selected server"
        isServerOverviewPresented = true
        selectedServerSettingsTab = .overview
        if let details = serverSettingsDetails() {
            serverSettingsState = .loaded(details)
            serverSettingsForm = ServerSettingsForm(server: details.server)
            categoryEditorForm = CategoryEditorForm(server: details.server)
            serverOverviewState = serverOverviewDetails().map { .loaded($0) } ?? .failed("Select a server before opening server overview.")
        } else {
            serverSettingsState = .failed("Select a server before opening server settings.")
            serverOverviewState = .failed("Select a server before opening server overview.")
        }
        phase24Status = nil
        phase25Status = nil
    }

    public func refreshSelectedServerDetails() async {
        guard let serverID = selection.serverID else {
            serverOverviewState = .failed("Select a server before refreshing details.")
            serverSettingsState = .failed("Select a server before refreshing details.")
            return
        }
        guard let apiClient = apiClientForCommunityAction() else {
            serverOverviewState = .failed("Reconnect before refreshing server details.")
            serverSettingsState = .failed("Reconnect before refreshing server details.")
            return
        }
        serverOverviewState = .loading
        serverSettingsState = .loading
        do {
            let response = try await apiClient.fetchServer(id: serverID, includeChannels: true)
            snapshot = Phase24SnapshotIntegrator.upserting(server: response.server, channels: response.channels, into: snapshot)
            quickSwitcherViewModel.update(snapshot: snapshot, selection: selection)
            if let details = serverOverviewDetails() {
                serverOverviewState = .loaded(details)
            }
            if let details = serverSettingsDetails() {
                serverSettingsState = .loaded(details)
                serverSettingsForm = ServerSettingsForm(server: details.server)
                categoryEditorForm = CategoryEditorForm(server: details.server)
            }
        } catch {
            serverOverviewState = .failed(Phase23Safety.safeError(error))
            serverSettingsState = .failed(Phase23Safety.safeError(error))
        }
    }

    public func serverSettingsDisabledReason() -> String? {
        let capabilities = serverManagementCapabilities()
        guard capabilities.isConnectedForLiveActions else { return "Reconnect to edit server settings." }
        guard capabilities.canManageServer else {
            return capabilities.permissionResolutionIncomplete ? "Permission resolution is incomplete for this action." : "You do not have permission to manage this server."
        }
        return nil
    }

    public func roleManagementDisabledReason() -> String? {
        let resolution = Phase25PermissionResolver.resolve(server: selectedServer, channel: selectedChannel, member: selectedServerMember, currentUserID: currentUserID)
        guard serverManagementCapabilities().isConnectedForLiveActions else { return "Reconnect to manage roles." }
        guard resolution.canManageRoles || currentUserID == selectedServer?.ownerID else {
            return resolution.warnings.isEmpty ? "You do not have permission to manage roles." : "Permission resolution is incomplete for role management."
        }
        return nil
    }

    public func saveServerSettings() async {
        guard let server = selectedServer, let form = serverSettingsForm else {
            serverSettingsSaveState = .failed("Select a server before saving settings.")
            return
        }
        guard let draft = form.draft(original: server) else {
            serverSettingsSaveState = .failed("Change the server name or description before saving.")
            return
        }
        guard serverSettingsDisabledReason() == nil else {
            serverSettingsSaveState = .failed(serverSettingsDisabledReason() ?? "Server settings are unavailable.")
            return
        }
        guard let apiClient = apiClientForCommunityAction() else {
            serverSettingsSaveState = .failed("Reconnect before editing server settings.")
            return
        }
        serverSettingsSaveState = .loading
        do {
            let saved = try await apiClient.editServer(id: server.id, draft: draft)
            snapshot = Phase24SnapshotIntegrator.upserting(server: saved, channels: [], into: snapshot)
            serverSettingsForm = ServerSettingsForm(server: saved)
            refreshLoadedServerSettings()
            quickSwitcherViewModel.update(snapshot: snapshot, selection: selection)
            serverSettingsSaveState = .loaded(saved)
            phase25Status = "Server settings updated"
        } catch {
            serverSettingsSaveState = .failed(Phase23Safety.safeError(error))
        }
    }

    public func chooseServerIconDraft() {
        chooseServerMediaDraft(tag: .icons)
    }

    public func chooseServerBannerDraft() {
        chooseServerMediaDraft(tag: .banners)
    }

    public func saveServerAppearance() async {
        guard let server = selectedServer else {
            serverSettingsSaveState = .failed("Select a server before saving appearance.")
            return
        }
        guard serverIconDraft != nil || serverBannerDraft != nil else {
            serverSettingsSaveState = .failed("Choose an icon or banner draft before saving.")
            return
        }
        guard serverSettingsDisabledReason() == nil else {
            serverSettingsSaveState = .failed(serverSettingsDisabledReason() ?? "Server appearance is unavailable.")
            return
        }
        guard let apiClient = apiClientForCommunityAction() else {
            serverSettingsSaveState = .failed("Reconnect before editing server appearance.")
            return
        }
        serverSettingsSaveState = .loading
        do {
            let iconID: FileID?
            if let draft = serverIconDraft {
                iconID = try await apiClient.uploadFile(data: draft.data, filename: draft.filename, mimeType: draft.mimeType, tag: .icons).id
            } else {
                iconID = nil
            }
            let bannerID: FileID?
            if let draft = serverBannerDraft {
                bannerID = try await apiClient.uploadFile(data: draft.data, filename: draft.filename, mimeType: draft.mimeType, tag: .banners).id
            } else {
                bannerID = nil
            }
            let saved = try await apiClient.editServer(id: server.id, draft: ServerEditDraft(icon: iconID, banner: bannerID))
            snapshot = Phase24SnapshotIntegrator.upserting(server: saved, channels: [], into: snapshot)
            serverIconDraft = nil
            serverBannerDraft = nil
            loadImageResource(for: saved.icon, kind: .serverIcon)
            loadImageResource(for: saved.banner, kind: .serverBanner)
            refreshLoadedServerSettings()
            serverSettingsSaveState = .loaded(saved)
            phase25Status = "Server appearance updated"
        } catch {
            serverSettingsSaveState = .failed(Phase23Safety.safeError(error))
        }
    }

    public func createCategoryDraft(title: String) {
        guard categoryEditorForm != nil else { return }
        let id = "local-category-\(UUID().uuidString)"
        categoryEditorForm?.createCategory(title: title, id: id)
    }

    public func applyCategoryChanges() async {
        guard let server = selectedServer, let form = categoryEditorForm else {
            categoryEditorState = .failed("Select a server before editing categories.")
            return
        }
        guard channelManagementDisabledReason() == nil else {
            categoryEditorState = .failed(channelManagementDisabledReason() ?? "Category editing is unavailable.")
            return
        }
        guard let apiClient = apiClientForCommunityAction() else {
            categoryEditorState = .failed("Reconnect before editing categories.")
            return
        }
        let draft = ServerEditDraft(categories: form.categories)
        guard draft.categories != server.categories else {
            categoryEditorState = .failed("Change categories before applying.")
            return
        }
        categoryEditorState = .loading
        do {
            let saved = try await apiClient.editServer(id: server.id, draft: draft)
            snapshot = Phase24SnapshotIntegrator.upserting(server: saved, channels: [], into: snapshot)
            categoryEditorForm = CategoryEditorForm(server: saved)
            refreshLoadedServerSettings()
            quickSwitcherViewModel.update(snapshot: snapshot, selection: selection)
            categoryEditorState = .loaded(saved)
            phase25Status = "Categories updated"
        } catch {
            categoryEditorState = .failed(Phase23Safety.safeError(error))
        }
    }

    public func openCreateRole() {
        guard roleManagementDisabledReason() == nil else {
            phase25Status = roleManagementDisabledReason()
            return
        }
        roleEditorForm = RoleEditorForm()
        roleEditorState = .idle
        selectedServerSettingsTab = .roles
    }

    public func openEditRole(_ role: Role) {
        guard roleManagementDisabledReason() == nil else {
            phase25Status = roleManagementDisabledReason()
            return
        }
        guard Phase25PermissionResolver.isRoleEditable(role, currentMember: selectedServerMember, server: selectedServer, currentUserID: currentUserID) else {
            phase25Status = "This role is at or above your role rank."
            return
        }
        roleEditorForm = RoleEditorForm(role: role)
        roleEditorState = .idle
        selectedServerSettingsTab = .roles
    }

    public func saveRoleEditor() async {
        guard let server = selectedServer, let form = roleEditorForm else {
            roleEditorState = .failed("Select a server before editing roles.")
            return
        }
        guard roleManagementDisabledReason() == nil else {
            roleEditorState = .failed(roleManagementDisabledReason() ?? "Role management is unavailable.")
            return
        }
        guard let apiClient = apiClientForCommunityAction() else {
            roleEditorState = .failed("Reconnect before editing roles.")
            return
        }
        roleEditorState = .loading
        do {
            if let roleID = form.roleID {
                guard let original = server.roles[roleID], let draft = form.editDraft(original: original) else {
                    roleEditorState = .failed("Change the role before saving.")
                    return
                }
                let role = try await apiClient.editRole(serverID: server.id, roleID: roleID, draft: draft)
                upsert(role: role, in: server.id)
                roleEditorState = .loaded(role)
                phase25Status = "Role updated"
            } else {
                guard let draft = form.createDraft() else {
                    roleEditorState = .failed("Role name must be 1 to 32 characters.")
                    return
                }
                let response = try await apiClient.createRole(serverID: server.id, draft: draft)
                upsert(role: response.role, in: server.id)
                roleEditorState = .loaded(response.role)
                phase25Status = "Role created"
            }
            roleEditorForm = nil
            refreshLoadedServerSettings()
        } catch {
            roleEditorState = .failed(Phase23Safety.safeError(error))
        }
    }

    public func requestDeleteRole(_ role: Role) {
        guard Phase25PermissionResolver.isRoleEditable(role, currentMember: selectedServerMember, server: selectedServer, currentUserID: currentUserID) else {
            phase25Status = "This role is at or above your role rank."
            return
        }
        pendingRoleDeletion = role
    }

    public func confirmDeleteRole(named confirmation: String) async {
        guard let server = selectedServer, let role = pendingRoleDeletion else { return }
        guard confirmation == role.name else {
            phase25Status = "Type the role name to confirm deletion."
            return
        }
        pendingRoleDeletion = nil
        guard roleManagementDisabledReason() == nil, let apiClient = apiClientForCommunityAction() else {
            phase25Status = roleManagementDisabledReason() ?? "Reconnect before deleting roles."
            return
        }
        do {
            try await apiClient.deleteRole(serverID: server.id, roleID: role.id)
            if var server = snapshot.serversByID[server.id] {
                server.roles.removeValue(forKey: role.id)
                snapshot.serversByID[server.id] = server
            }
            refreshLoadedServerSettings()
            phase25Status = "Role deleted"
        } catch {
            phase25Status = Phase23Safety.safeError(error)
        }
    }

    private func upsert(role: Role, in serverID: ServerID) {
        guard var server = snapshot.serversByID[serverID] else { return }
        server.roles[role.id] = role
        snapshot.serversByID[serverID] = server
        quickSwitcherViewModel.update(snapshot: snapshot, selection: selection)
    }

    public func openMemberDetail(_ member: ServerMember) {
        selectedMemberDetailID = member.id
        memberNicknameDraft = member.nickname ?? ""
        memberTimeoutHours = 1
        memberRoleDraft = nil
        memberRoleSaveRequiresConfirmation = false
        selectedServerSettingsTab = .members
    }

    public func closeMemberDetail() {
        selectedMemberDetailID = nil
        memberRoleDraft = nil
        memberRoleSaveRequiresConfirmation = false
        pendingMemberModerationAction = nil
    }

    public func memberRoleAssignmentDisabledReason(for member: ServerMember) -> String? {
        let resolution = Phase25PermissionResolver.resolve(server: selectedServer, channel: selectedChannel, member: selectedServerMember, currentUserID: currentUserID)
        guard serverManagementCapabilities().isConnectedForLiveActions else { return "Reconnect to assign roles." }
        guard member.id.userID != currentUserID else { return "You cannot assign roles to yourself from this guarded flow." }
        guard resolution.canAssignRoles || currentUserID == selectedServer?.ownerID else {
            return resolution.warnings.isEmpty ? "You do not have permission to assign roles." : "Permission resolution is incomplete for role assignment."
        }
        guard Phase26MemberSafety.canActOn(member: member, currentMember: selectedServerMember, server: selectedServer, currentUserID: currentUserID) || currentUserID == selectedServer?.ownerID else {
            return "Role rank is incomplete or this member is at or above your rank."
        }
        guard let server = selectedServer, !Phase26MemberSafety.assignableRoles(in: server, currentMember: selectedServerMember, currentUserID: currentUserID).isEmpty else {
            return "No assignable roles are below your rank."
        }
        return nil
    }

    public func openMemberRoleAssignment(_ member: ServerMember) {
        guard memberRoleAssignmentDisabledReason(for: member) == nil else {
            phase26Status = memberRoleAssignmentDisabledReason(for: member)
            return
        }
        openMemberDetail(member)
        memberRoleDraft = MemberRoleAssignmentDraft(member: member)
        memberRoleSaveRequiresConfirmation = false
    }

    public func toggleRole(_ roleID: RoleID, inMemberRoleDraft isOn: Bool) {
        guard memberRoleDraft != nil else { return }
        if isOn {
            memberRoleDraft?.selectedRoleIDs.insert(roleID)
        } else {
            memberRoleDraft?.selectedRoleIDs.remove(roleID)
        }
        memberRoleSaveRequiresConfirmation = false
    }

    public func requestSaveMemberRoles() {
        guard memberRoleDraft?.hasChanges == true else {
            phase26Status = "Change member roles before saving."
            return
        }
        memberRoleSaveRequiresConfirmation = true
    }

    public func confirmSaveMemberRoles() async {
        guard let server = selectedServer,
              let draft = memberRoleDraft,
              let memberDraft = draft.memberDraft()
        else {
            memberActionState = .failed("Change member roles before saving.")
            return
        }
        guard memberRoleAssignmentDisabledReason(for: draft.member) == nil else {
            memberActionState = .failed(memberRoleAssignmentDisabledReason(for: draft.member) ?? "Role assignment is unavailable.")
            return
        }
        guard memberRoleSaveRequiresConfirmation else {
            memberActionState = .failed("Review and confirm the role changes before saving.")
            return
        }
        guard let apiClient = apiClientForCommunityAction() else {
            memberActionState = .failed("Reconnect before assigning roles.")
            return
        }
        memberActionState = .loading
        do {
            let member = try await apiClient.editMember(serverID: server.id, userID: draft.member.id.userID, draft: memberDraft)
            upsert(member: member)
            memberRoleDraft = nil
            memberRoleSaveRequiresConfirmation = false
            refreshLoadedServerSettings()
            memberActionState = .loaded(member)
            phase26Status = "Member roles updated"
        } catch {
            memberActionState = .failed(Phase23Safety.safeError(error))
        }
    }

    public func memberActionDisabledReason(for member: ServerMember, action: MemberModerationAction) -> String? {
        let resolution = Phase25PermissionResolver.resolve(server: selectedServer, channel: selectedChannel, member: selectedServerMember, currentUserID: currentUserID)
        guard serverManagementCapabilities().isConnectedForLiveActions else { return "Reconnect before member moderation." }
        guard member.id.userID != currentUserID else { return "You cannot moderate yourself from this guarded flow." }
        guard Phase26MemberSafety.canActOn(member: member, currentMember: selectedServerMember, server: selectedServer, currentUserID: currentUserID) || currentUserID == selectedServer?.ownerID else {
            return "Rank data is incomplete or this member is protected."
        }
        let allowed: Bool
        switch action {
        case .saveNickname, .resetNickname:
            allowed = resolution.effectivePermissions.contains(.manageNicknames) || currentUserID == selectedServer?.ownerID
        case .removeAvatar:
            allowed = resolution.effectivePermissions.contains(.removeAvatars) || currentUserID == selectedServer?.ownerID
        case .kick:
            allowed = resolution.effectivePermissions.contains(.kickMembers) || currentUserID == selectedServer?.ownerID
        case .ban:
            allowed = resolution.effectivePermissions.contains(.banMembers) || currentUserID == selectedServer?.ownerID
        case .timeout, .clearTimeout:
            allowed = resolution.effectivePermissions.contains(.timeoutMembers) || currentUserID == selectedServer?.ownerID
        }
        guard allowed else {
            return resolution.warnings.isEmpty ? "You do not have permission for this member action." : "Permission resolution is incomplete for this member action."
        }
        return nil
    }

    public func requestMemberAction(_ action: MemberModerationAction, for member: ServerMember) {
        guard memberActionDisabledReason(for: member, action: action) == nil else {
            phase26Status = memberActionDisabledReason(for: member, action: action)
            return
        }
        let timeoutUntil = action == .timeout ? Date().addingTimeInterval(max(1, memberTimeoutHours) * 3600) : nil
        pendingMemberModerationAction = PendingMemberModerationAction(member: member, action: action, timeoutUntil: timeoutUntil)
    }

    public func confirmPendingMemberAction() async {
        guard let pending = pendingMemberModerationAction, let server = selectedServer else { return }
        guard memberActionDisabledReason(for: pending.member, action: pending.action) == nil else {
            memberActionState = .failed(memberActionDisabledReason(for: pending.member, action: pending.action) ?? "Member action is unavailable.")
            return
        }
        guard let apiClient = apiClientForCommunityAction() else {
            memberActionState = .failed("Reconnect before member moderation.")
            return
        }
        pendingMemberModerationAction = nil
        memberActionState = .loading
        do {
            switch pending.action {
            case .saveNickname:
                let nickname = memberNicknameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !nickname.isEmpty else {
                    memberActionState = .failed("Enter a nickname before saving.")
                    return
                }
                let member = try await apiClient.editMember(serverID: server.id, userID: pending.member.id.userID, draft: MemberEditDraft(nickname: String(nickname.prefix(32))))
                upsert(member: member)
                memberActionState = .loaded(member)
            case .resetNickname:
                let member = try await apiClient.editMember(serverID: server.id, userID: pending.member.id.userID, draft: MemberEditDraft(remove: [.nickname]))
                upsert(member: member)
                memberActionState = .loaded(member)
            case .removeAvatar:
                let member = try await apiClient.editMember(serverID: server.id, userID: pending.member.id.userID, draft: MemberEditDraft(remove: [.avatar]))
                upsert(member: member)
                memberActionState = .loaded(member)
            case .timeout:
                guard let timeoutUntil = pending.timeoutUntil else {
                    memberActionState = .failed("Choose a timeout duration before saving.")
                    return
                }
                let member = try await apiClient.editMember(serverID: server.id, userID: pending.member.id.userID, draft: MemberEditDraft(timeout: timeoutUntil))
                upsert(member: member)
                memberActionState = .loaded(member)
            case .clearTimeout:
                let member = try await apiClient.editMember(serverID: server.id, userID: pending.member.id.userID, draft: MemberEditDraft(remove: [.timeout]))
                upsert(member: member)
                memberActionState = .loaded(member)
            case .kick:
                try await apiClient.kickMember(serverID: server.id, userID: pending.member.id.userID)
                removeMember(serverID: server.id, userID: pending.member.id.userID)
                memberActionState = .idle
                selectedMemberDetailID = nil
            case .ban:
                _ = try await apiClient.banMember(serverID: server.id, userID: pending.member.id.userID, draft: BanCreateDraft(reason: pending.reason.isEmpty ? nil : pending.reason))
                removeMember(serverID: server.id, userID: pending.member.id.userID)
                memberActionState = .idle
                selectedMemberDetailID = nil
            }
            refreshLoadedServerSettings()
            phase26Status = "Member action completed"
        } catch {
            memberActionState = .failed(Phase23Safety.safeError(error))
        }
    }

    public func refreshBanList() async {
        guard let server = selectedServer else {
            banListState = .failed("Select a server before loading bans.")
            return
        }
        let resolution = Phase25PermissionResolver.resolve(server: selectedServer, channel: selectedChannel, member: selectedServerMember, currentUserID: currentUserID)
        guard serverManagementCapabilities().isConnectedForLiveActions else {
            banListState = .failed("Reconnect before loading bans.")
            return
        }
        guard resolution.effectivePermissions.contains(.banMembers) || currentUserID == server.ownerID else {
            banListState = .failed("You do not have permission to view bans.")
            return
        }
        guard let apiClient = apiClientForCommunityAction() else {
            banListState = .failed("Reconnect before loading bans.")
            return
        }
        banListState = .loading
        do {
            banListState = .loaded(try await apiClient.fetchServerBans(serverID: server.id))
        } catch {
            banListState = .failed(Phase23Safety.safeError(error))
        }
    }

    public func unban(userID: UserID) async {
        guard let server = selectedServer, let apiClient = apiClientForCommunityAction() else {
            banListState = .failed("Reconnect before removing bans.")
            return
        }
        do {
            try await apiClient.unbanMember(serverID: server.id, userID: userID)
            await refreshBanList()
        } catch {
            banListState = .failed(Phase23Safety.safeError(error))
        }
    }

    public func permissionEditingDisabledReason() -> String? {
        let resolution = Phase25PermissionResolver.resolve(server: selectedServer, channel: selectedChannel, member: selectedServerMember, currentUserID: currentUserID)
        guard serverManagementCapabilities().isConnectedForLiveActions else { return "Reconnect before editing permissions." }
        guard resolution.canManagePermissions || currentUserID == selectedServer?.ownerID else {
            return resolution.warnings.isEmpty ? "You do not have permission to manage permissions." : "Permission resolution is incomplete for permission editing."
        }
        return nil
    }

    public func openPermissionEditor(scope: PermissionEditScope) {
        guard permissionEditingDisabledReason() == nil else {
            phase26Status = permissionEditingDisabledReason()
            return
        }
        guard let draft = makePermissionEditDraft(scope: scope) else {
            phase26Status = "Permission editing is unavailable for this scope."
            return
        }
        permissionEditDraft = draft
        permissionSaveRequiresConfirmation = false
        selectedServerSettingsTab = .permissions
        permissionEditorState = .idle
    }

    public func setPermissionState(_ state: PermissionTriState, for key: PermissionKey) {
        permissionEditDraft?.set(state, for: key)
        permissionSaveRequiresConfirmation = false
    }

    public func requestSavePermissionEdit() {
        guard permissionEditDraft?.diff(keys: Phase26Permissions.editableKeys).isEmpty == false else {
            permissionEditorState = .failed("Change permissions before saving.")
            return
        }
        permissionSaveRequiresConfirmation = true
    }

    public func confirmSavePermissionEdit() async {
        guard let draft = permissionEditDraft else {
            permissionEditorState = .failed("Open a permission editor before saving.")
            return
        }
        guard permissionSaveRequiresConfirmation else {
            permissionEditorState = .failed("Review and confirm the permission diff before saving.")
            return
        }
        guard permissionEditingDisabledReason() == nil else {
            permissionEditorState = .failed(permissionEditingDisabledReason() ?? "Permission editing is unavailable.")
            return
        }
        guard let apiClient = apiClientForCommunityAction() else {
            permissionEditorState = .failed("Reconnect before editing permissions.")
            return
        }
        permissionEditorState = .loading
        do {
            switch draft.scope {
            case let .serverDefault(serverID):
                let server = try await apiClient.setServerDefaultPermissions(serverID: serverID, draft: ServerDefaultPermissionDraft(permissions: draft.defaultPermissionsDraft(keys: Phase26Permissions.editableKeys)))
                snapshot = Phase24SnapshotIntegrator.upserting(server: server, channels: [], into: snapshot)
            case let .serverRole(serverID, roleID):
                let server = try await apiClient.setServerRolePermissions(serverID: serverID, roleID: roleID, draft: ServerRolePermissionDraft(permissions: draft.overrideDraft(keys: Phase26Permissions.editableKeys)))
                snapshot = Phase24SnapshotIntegrator.upserting(server: server, channels: [], into: snapshot)
            case let .channelDefault(channelID):
                let channel = try await apiClient.setChannelDefaultPermissions(channelID: channelID, draft: .override(draft.overrideDraft(keys: Phase26Permissions.editableKeys)))
                snapshot = Phase24SnapshotIntegrator.upserting(channel: channel, into: snapshot)
            case let .channelRole(channelID, roleID):
                let channel = try await apiClient.setChannelRolePermissions(channelID: channelID, roleID: roleID, draft: ServerRolePermissionDraft(permissions: draft.overrideDraft(keys: Phase26Permissions.editableKeys)))
                snapshot = Phase24SnapshotIntegrator.upserting(channel: channel, into: snapshot)
            }
            permissionEditDraft = nil
            permissionSaveRequiresConfirmation = false
            refreshLoadedServerSettings()
            quickSwitcherViewModel.update(snapshot: snapshot, selection: selection)
            permissionEditorState = .loaded("Permissions updated")
            phase26Status = "Permissions updated"
        } catch {
            permissionEditorState = .failed(Phase23Safety.safeError(error))
        }
    }

    private func makePermissionEditDraft(scope: PermissionEditScope) -> PermissionEditDraft? {
        switch scope {
        case let .serverDefault(serverID):
            guard let server = snapshot.serversByID[serverID] else { return nil }
            return PermissionEditDraft(scope: scope, originalAllow: server.defaultPermissions, originalDeny: [], allowsInherit: false, keys: Phase26Permissions.editableKeys)
        case let .serverRole(serverID, roleID):
            guard let role = snapshot.serversByID[serverID]?.roles[roleID] else { return nil }
            return PermissionEditDraft(scope: scope, originalAllow: role.permissions.allow, originalDeny: role.permissions.deny, allowsInherit: true, keys: Phase26Permissions.editableKeys)
        case let .channelDefault(channelID):
            guard let channel = snapshot.channelsByID[channelID] else { return nil }
            let original = channel.defaultPermissions ?? PermissionOverride()
            return PermissionEditDraft(scope: scope, originalAllow: original.allow, originalDeny: original.deny, allowsInherit: true, keys: Phase26Permissions.editableKeys)
        case let .channelRole(channelID, roleID):
            guard let channel = snapshot.channelsByID[channelID] else { return nil }
            let original = channel.rolePermissions[roleID] ?? PermissionOverride()
            return PermissionEditDraft(scope: scope, originalAllow: original.allow, originalDeny: original.deny, allowsInherit: true, keys: Phase26Permissions.editableKeys)
        }
    }

    private func upsert(member: ServerMember) {
        snapshot.membersByServerAndUserID[ServerMemberKey(member.id)] = member
        selectedMemberDetailID = member.id
        invalidateIdentityPresentationCaches()
        updateVisibleIdentityDiagnostics()
    }

    private func removeMember(serverID: ServerID, userID: UserID) {
        snapshot.membersByServerAndUserID.removeValue(forKey: ServerMemberKey(serverID: serverID, userID: userID))
        invalidateIdentityPresentationCaches()
        updateVisibleIdentityDiagnostics()
    }

    private func refreshLoadedServerSettings() {
        if let settings = serverSettingsDetails() {
            serverSettingsState = .loaded(settings)
        }
        if let overview = serverOverviewDetails() {
            serverOverviewState = .loaded(overview)
        }
    }

    private func chooseServerMediaDraft(tag: UploadTag) {
        #if canImport(AppKit)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let filename = url.lastPathComponent
            let mimeType = filename.lowercased().hasSuffix(".jpg") || filename.lowercased().hasSuffix(".jpeg") ? "image/jpeg" : "image/png"
            let draft = ServerMediaDraft(data: data, filename: filename, mimeType: mimeType)
            if tag == .icons {
                serverIconDraft = draft
            } else {
                serverBannerDraft = draft
            }
            phase25Status = tag == .icons ? "Icon draft selected; save to upload." : "Banner draft selected; save to upload."
        } catch {
            phase25Status = "Could not read selected image."
        }
        #else
        phase25Status = "Image picking is unavailable on this platform."
        #endif
    }

    public func openCreateChannel(categoryID: String? = nil) {
        guard selectedServer != nil else {
            phase24Status = "Select a server before creating a channel."
            return
        }
        if let reason = channelManagementDisabledReason() {
            phase24Status = reason
            return
        }
        isCreateChannelPresented = true
        channelCreateForm = ChannelCreateForm(categoryID: categoryID)
        channelCreateState = .idle
        phase24Status = nil
    }

    public func createChannelFromDraft() async {
        guard let server = selectedServer else {
            channelCreateState = .failed("Select a server before creating a channel.")
            return
        }
        guard let draft = channelCreateForm.draft() else {
            channelCreateState = .failed("Channel name must be 1 to 32 characters.")
            return
        }
        guard let apiClient = apiClientForCommunityAction() else {
            channelCreateState = .failed("Reconnect before creating channels.")
            return
        }
        channelCreateState = .loading
        do {
            let channel = try await apiClient.createChannel(serverID: server.id, draft: draft)
            snapshot = Phase24SnapshotIntegrator.upserting(channel: channel, into: snapshot)
            if let categoryID = channelCreateForm.categoryID {
                let updatedServer = Phase24SnapshotIntegrator.server(snapshot.serversByID[server.id] ?? server, appending: channel.id, toCategory: categoryID)
                snapshot.serversByID[server.id] = updatedServer
                if effectiveRuntimeMode == .liveManual {
                    do {
                        let savedServer = try await apiClient.editServer(id: server.id, draft: ServerEditDraft(categories: updatedServer.categories))
                        snapshot.serversByID[server.id] = savedServer
                    } catch {
                        phase24Status = "Channel created; category update failed."
                    }
                }
            }
            selectChannel(channel.id)
            channelCreateState = .loaded(channel)
            isCreateChannelPresented = false
            channelCreateForm = ChannelCreateForm()
            phase24Status = "Channel created"
            quickSwitcherViewModel.update(snapshot: snapshot, selection: selection)
            messageController.hydrate(from: snapshot)
        } catch {
            channelCreateState = .failed(Phase23Safety.safeError(error))
        }
    }

    public func openChannelSettings() {
        guard let channel = selectedChannel else {
            phase24Status = "Select a channel before opening channel settings."
            return
        }
        if let reason = channelManagementDisabledReason() {
            phase24Status = reason
            return
        }
        channelEditForm = ChannelEditForm(channel: channel)
        channelEditState = .idle
        isChannelSettingsPresented = true
        phase24Status = nil
    }

    public func saveChannelSettings() async {
        guard let form = channelEditForm,
              let original = snapshot.channelsByID[form.channelID]
        else {
            channelEditState = .failed("Selected channel is no longer available.")
            return
        }
        guard let draft = form.draft(original: original) else {
            channelEditState = .failed("Change the channel name or description before saving.")
            return
        }
        guard let apiClient = apiClientForCommunityAction() else {
            channelEditState = .failed("Reconnect before editing channels.")
            return
        }
        channelEditState = .loading
        do {
            let channel = try await apiClient.editChannel(id: form.channelID, draft: draft)
            snapshot = Phase24SnapshotIntegrator.upserting(channel: channel, into: snapshot)
            channelEditState = .loaded(channel)
            isChannelSettingsPresented = false
            phase24Status = "Channel updated"
            quickSwitcherViewModel.update(snapshot: snapshot, selection: selection)
        } catch {
            channelEditState = .failed(Phase23Safety.safeError(error))
        }
    }

    public func requestDeleteSelectedChannel() {
        guard let channel = selectedChannel else {
            phase24Status = "Select a channel before deleting it."
            return
        }
        if let reason = channelManagementDisabledReason(destructive: true) {
            phase24Status = reason
            return
        }
        pendingChannelDeletion = PendingChannelDeletion(channel: channel)
    }

    public func confirmPendingChannelDeletion() async {
        guard let pendingChannelDeletion else { return }
        self.pendingChannelDeletion = nil
        guard let apiClient = apiClientForCommunityAction() else {
            phase24Status = "Reconnect before deleting channels."
            return
        }
        do {
            try await apiClient.deleteChannel(id: pendingChannelDeletion.channel.id)
            let result = Phase24SnapshotIntegrator.deleting(channelID: pendingChannelDeletion.channel.id, selectedChannelID: selection.channelID, in: snapshot)
            snapshot = result.0
            if let fallback = result.1 {
                selectChannel(fallback)
            } else if let serverID = pendingChannelDeletion.channel.serverID {
                selection.space = .server(serverID)
                selection.serverID = serverID
                selection.channelID = nil
            }
            phase24Status = "Channel deleted"
            quickSwitcherViewModel.update(snapshot: snapshot, selection: selection)
            messageController.hydrate(from: snapshot)
        } catch {
            phase24Status = Phase23Safety.safeError(error)
        }
    }

    private var runtimeSubtitleForManagement: String {
        switch effectiveRuntimeMode {
        case .mock:
            "Preview Data"
        case .liveManual:
            effectiveSessionState == .connected ? "Live connected" : "Live disconnected"
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
        let before = selection
        selection.space = .directMessages
        selection.serverID = nil
        selection.channelID = nil
        selection.dmChannelID = nil
        recordDMRouteSelection(clickedRowID: selection.dmChannelID?.rawValue ?? "direct-messages", clickedChannelID: selection.dmChannelID, before: before)
        clearTimelineSelection()
        reconcileSearchHighlightsForSelectedChannel()
        placeholderStatus = nil
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
        let before = selection
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
            recordDMRouteSelection(clickedRowID: id.rawValue, clickedChannelID: id, before: before)
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

    public func selectDirectMessageItem(_ item: DirectMessageListItem) {
        selectChannel(item.id)
        dmLiveTrace.clickedRowID = item.id.rawValue
        dmLiveTrace.clickedUserID = item.participants.first?.id
        dmLiveTrace.clickedChannelID = item.channel.id
        dmLiveTrace.clickedChannelKind = item.channel.kind.rawAPIValue
        dmLiveTrace.clickedChannelExistsInSnapshot = snapshot.channelsByID[item.id] != nil
    }

    private func recordDMRouteSelection(clickedRowID: String, clickedChannelID: ChannelID?, clickedUserID: UserID? = nil, before: ShellSelection) {
        guard let channelID = clickedChannelID,
              let channel = snapshot.channelsByID[channelID],
              DMChannelClassifier.isDirectMessageLike(channel)
        else { return }
        dmRouteDiagnostics.clickedChannelID = channelID
        dmRouteDiagnostics.selectedConversationChannelID = channelID
        dmRouteDiagnostics.selectedServerID = selection.serverID
        dmRouteDiagnostics.messageLoadRequested = false
        dmRouteDiagnostics.lastLoadResult = nil
        dmRouteDiagnostics.composerTargetDescription = directMessageTitle(for: channel)
        dmLiveTrace = DirectMessageLiveTrace(
            clickedRowID: clickedRowID,
            clickedChannelID: channelID,
            clickedUserID: clickedUserID,
            clickedChannelKind: channel.kind.rawAPIValue,
            clickedChannelExistsInSnapshot: true,
            selectedSpaceBefore: String(describing: before.space),
            selectedSpaceAfter: String(describing: selection.space),
            selectedServerIDBefore: before.serverID,
            selectedServerIDAfter: selection.serverID,
            selectedChannelIDBefore: before.channelID ?? before.dmChannelID,
            selectedChannelIDAfter: selection.channelID ?? selection.dmChannelID,
            selectedConversationChannelID: selectedConversationChannelID,
            messageLoadRequested: false,
            messageLoadChannelID: nil,
            messageLoadUsedREST: false,
            messageLoadResult: nil,
            timelineChannelID: selectedConversationChannelID,
            timelineMessageCount: selectedTimelineMessages.count,
            composerTargetChannelID: selectedConversationChannelID,
            sidebarParticipantCount: directMessageParticipantItems(for: channel).count,
            lastError: selectedConversationChannelID == channelID ? nil : "Selected conversation diverged from clicked DM."
        )
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
        placeholderStatus = selectedConversationChannel == nil ? "Select a channel before focusing the composer." : nil
    }

    public func refreshPlaceholder() {
        refreshCurrentContext()
    }

    public func refreshCurrentContext() {
        switch effectiveRuntimeMode {
        case .mock:
            if let channelID = selectedConversationChannelID {
                Task { [weak self] in
                    guard let self else { return }
                    await self.messageController.refreshMessages(channelID: channelID, snapshotMessages: self.snapshot.messagesByChannelID[channelID] ?? [])
                    self.showTransientStatus("Mock data refreshed")
                }
            } else {
                showTransientStatus("Mock data refreshed")
            }
        case .liveManual:
            switch effectiveConnectionState {
            case .ready:
                if let channelID = selectedConversationChannelID {
                    Task { [weak self] in
                        guard let self else { return }
                        await self.messageController.refreshMessages(channelID: channelID, snapshotMessages: self.snapshot.messagesByChannelID[channelID] ?? [])
                        self.sessionCoordinator?.markSelectedChannelMessageFetchSucceeded(channelID: channelID, isAvailable: self.snapshot.channelsByID[channelID] != nil)
                        if self.messageController.lastErrorByChannelID[channelID] == nil {
                            self.showTransientStatus("Channel messages refreshed")
                        }
                    }
                } else {
                    showTransientStatus("Live status refreshed")
                }
            case .disconnected, .failed, .idle:
                placeholderStatus = "Reconnect to refresh live state"
            case .connecting, .connected, .authenticating, .authenticated, .reconnecting:
                placeholderStatus = "Waiting for realtime data"
            }
        }
    }

    public func legacyRefreshSelectedChannel() {
        if let channelID = selectedConversationChannelID {
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
        prepareProfileEditor(force: false)
    }

    public func confirmLiveVerificationSend() async {
        guard let channelID = selectedConversationChannelID else {
            messageActionStatus = "Select a channel before sending a verification message."
            return
        }
        await sendDraft(for: channelID)
        let result = currentMessageSendDiagnostics().lastSendResult == .succeeded ? "Send action succeeded." : (messageActionStatus ?? "Send action attempted.")
        sessionCoordinator?.markLastMessageActionResult(result)
    }

    public func validateSelection() {
        switch selection.space {
        case .home, .discover, .directMessages:
            if selection.space == .directMessages,
               let dmChannelID = selection.dmChannelID,
               snapshot.channelsByID[dmChannelID] == nil {
                selection.dmChannelID = snapshot.channelsByID.values.first(where: DMChannelClassifier.isDirectMessageLike)?.id
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
        snapshot = snapshotWithHydratedMemberOverlay(sessionCoordinator.snapshot)
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
            loadVisibleIdentityImagesForCurrentSelection()
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

    public var commonEmojiItems: [String] {
        composerEmojiSections.flatMap(\.items)
    }

    public var composerEmojiSections: [EmojiPickerSection] {
        let common = ["👍", "❤️", "😂", "🥯", "✅", "👀", "🎉", "🙏", "🔥", "✨"]
        let smileys = ["😄", "😅", "😎", "😢", "😮", "🤔", "🫡", "👋", "🙌", "😆", "😋", "😴"]
        let serverID = selectedConversationChannelID.flatMap { snapshot.channelsByID[$0]?.serverID } ?? selection.serverID
        let custom = snapshot.emojisByID.values.map(CustomEmojiDisplayItem.init(emoji:)).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        let currentServer = custom.filter { item in
            guard let serverID else { return false }
            return item.serverID == serverID
        }.prefix(48).map(\.shortcode)
        let otherServers = custom.filter { item in
            guard let serverID else { return item.serverID != nil }
            return item.serverID != nil && item.serverID != serverID
        }.prefix(48).map(\.shortcode)
        return [
            EmojiPickerSection(id: "common", title: "Common", items: common),
            EmojiPickerSection(id: "smileys", title: "Unicode", items: smileys),
            EmojiPickerSection(id: "current-server", title: "Current Server", items: Array(currentServer)),
            EmojiPickerSection(id: "other-servers", title: "Other Servers", items: Array(otherServers))
        ].filter { !$0.items.isEmpty }
    }

    public func insertEmoji(_ emoji: String, in channelID: ChannelID?) {
        guard let channelID else { return }
        var state = composerDraftState(for: channelID)
        state.text += emoji
        composerDrafts[channelID] = state
        emojiPickerDiagnostics = emoji.hasPrefix(":") && emoji.hasSuffix(":") ? "Inserted custom emoji shortcode" : "Inserted Unicode emoji"
        requestFocus(.composer)
    }

    public func customEmojiDisplayItemsForCurrentContext() -> [CustomEmojiDisplayItem] {
        customEmojiDisplayItemsForContext(channelID: selectedConversationChannelID)
    }

    public func roleColor(for message: Message, highContrast: Bool = false) -> ResolvedRoleColor? {
        guard !highContrast,
              let channel = snapshot.channelsByID[message.channelID],
              channel.serverID != nil
        else { return nil }
        return resolvedUserDisplay(for: message).roleColor
    }

    public func roleColor(for userID: UserID, serverID: ServerID?, highContrast: Bool = false) -> ResolvedRoleColor? {
        guard let serverID,
              let server = snapshot.serversByID[serverID]
        else { return nil }
        let member = snapshot.membersByServerAndUserID[ServerMemberKey(serverID: serverID, userID: userID)]
        return RoleColorResolver.resolve(member: member, server: server, highContrast: highContrast)
    }

    public func customEmojiDisplayItem(for raw: String) -> CustomEmojiDisplayItem? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let emoji = snapshot.emojisByID[EmojiID(rawValue: trimmed)] {
            return CustomEmojiDisplayItem(emoji: emoji)
        }
        let normalized = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        return snapshot.emojisByID.values
            .map(CustomEmojiDisplayItem.init(emoji:))
            .first { $0.name.caseInsensitiveCompare(normalized) == .orderedSame || $0.shortcode.caseInsensitiveCompare(trimmed) == .orderedSame }
    }

    public func inlineCustomEmojiItems(for message: Message) -> [MessageInlineCustomEmojiItem] {
        guard let content = message.content, content.contains(":") else { return [] }
        return customEmojiDisplayItemsForContext(channelID: message.channelID)
            .filter { content.localizedCaseInsensitiveContains($0.shortcode) }
            .map { item in
                MessageInlineCustomEmojiItem(
                    shortcode: item.shortcode,
                    name: item.name,
                    imageData: imageData(for: item.file, kind: .customEmoji)
                )
            }
    }

    public func loadCustomEmojiImages(for message: Message) {
        for emojiKey in message.reactions.keys {
            if let item = customEmojiDisplayItem(for: emojiKey) {
                loadImageResource(for: item.file, kind: .customEmoji)
            }
        }
        for item in customEmojiDisplayItemsForContext(channelID: message.channelID) {
            if message.content?.localizedCaseInsensitiveContains(item.shortcode) == true {
                loadImageResource(for: item.file, kind: .customEmoji)
            }
        }
    }

    private func customEmojiDisplayItemsForContext(channelID: ChannelID?) -> [CustomEmojiDisplayItem] {
        let serverID = channelID.flatMap { snapshot.channelsByID[$0]?.serverID } ?? selection.serverID ?? selectedConversationChannel?.serverID
        return snapshot.emojisByID.values
            .map(CustomEmojiDisplayItem.init(emoji:))
            .filter { item in
                guard let serverID else { return true }
                return item.serverID == nil || item.serverID == serverID
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func addAttachmentURLs(_ urls: [URL], to channelID: ChannelID?) {
        guard let channelID else {
            composerError = "Select a channel or DM before dropping files."
            placeholderStatus = composerError
            lastAttachmentAction = "Drop rejected without selected channel"
            return
        }
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

    public func reviewDroppedAttachmentURLs(_ urls: [URL], to channelID: ChannelID?) {
        let target = channelID.flatMap { snapshot.channelsByID[$0] }
        let existingCount = channelID.map { composerDraftState(for: $0).attachments.count } ?? 0
        let blockedReason: String?
        if channelID == nil || target == nil {
            blockedReason = "Select a channel or DM before attaching files."
        } else if !canUploadFiles(in: target) {
            blockedReason = "You do not have permission to upload files here."
        } else if !isRuntimeSendCapable {
            blockedReason = effectiveRuntimeMode == .mock ? "Preview data cannot send messages." : "Reconnect before attaching files."
        } else {
            blockedReason = nil
        }

        var validatedCount = existingCount
        let items = urls.map { url -> AttachmentDropReviewItem in
            do {
                let draft = try attachmentValidationPolicy.draft(for: url, existingCount: validatedCount)
                validatedCount += 1
                return AttachmentDropReviewItem(draft: draft)
            } catch {
                return AttachmentDropReviewItem(url: url, error: error)
            }
        }
        pendingAttachmentDrop = AttachmentDropReview(
            channelID: channelID,
            channelName: target.map { composerPlaceholder(for: $0).replacingOccurrences(of: "Message ", with: "") },
            items: items,
            blockedReason: blockedReason
        )
        lastAttachmentAction = "Opened drag and drop attachment review"
    }

    public func reviewDroppedAttachmentURLsForSelectedChannel(_ urls: [URL]) {
        reviewDroppedAttachmentURLs(urls, to: selectedConversationChannelID)
    }

    public func removePendingDroppedAttachment(_ itemID: UUID) {
        pendingAttachmentDrop?.items.removeAll { $0.id == itemID }
        if pendingAttachmentDrop?.items.isEmpty == true {
            pendingAttachmentDrop = nil
        }
    }

    public func cancelPendingAttachmentDrop() {
        pendingAttachmentDrop = nil
        lastAttachmentAction = "Cancelled drag and drop attachment review"
    }

    public func addPendingDroppedAttachmentsToComposer() {
        guard let review = pendingAttachmentDrop,
              review.canAddToMessage,
              let channelID = review.channelID
        else {
            composerError = pendingAttachmentDrop?.blockedReason ?? "No attachable files are available."
            placeholderStatus = composerError
            return
        }
        var state = composerDraftState(for: channelID)
        for item in review.attachableItems {
            if let draft = item.draft {
                state.attachments.append(draft)
            }
        }
        composerDrafts[channelID] = state
        pendingAttachmentDrop = nil
        composerError = nil
        lastAttachmentAction = "Queued dropped attachments after confirmation"
    }

    public func addAttachmentURLsToSelectedChannel(_ urls: [URL]) {
        addAttachmentURLs(urls, to: selectedConversationChannelID)
    }

    public func reviewPastedImageData(_ data: Data, to channelID: ChannelID?) {
        do {
            let existingCount = channelID.map { composerDraftState(for: $0).attachments.count } ?? 0
            let draft = try attachmentValidationPolicy.imageDraft(data: data, existingCount: existingCount)
            reviewPastedAttachmentDrafts([draft], to: channelID, action: "Opened clipboard image attachment review")
        } catch {
            pendingAttachmentDrop = AttachmentDropReview(
                channelID: channelID,
                channelName: channelID.flatMap { snapshot.channelsByID[$0] }.map { composerPlaceholder(for: $0).replacingOccurrences(of: "Message ", with: "") },
                items: [AttachmentDropReviewItem(filename: "Pasted Image.png", error: error)],
                blockedReason: nil
            )
            composerError = error.userFacingMessage
            lastAttachmentAction = "Paste image rejected by validation"
        }
    }

    public func addPastedImageData(_ data: Data, to channelID: ChannelID?) {
        guard let channelID else {
            composerError = "Select a channel or DM before attaching files."
            placeholderStatus = composerError
            lastAttachmentAction = "Paste rejected without selected channel"
            return
        }
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

    public func pasteAttachmentFromClipboard() {
        #if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? []
        if !urls.isEmpty {
            reviewDroppedAttachmentURLs(urls, to: selectedConversationChannelID)
            lastAttachmentAction = "Opened clipboard file attachment review"
            return
        }
        if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            reviewPastedImageData(data, to: selectedConversationChannelID)
            return
        }
        composerError = "Clipboard does not contain an image or file attachment."
        placeholderStatus = composerError
        lastAttachmentAction = "Clipboard paste contained no attachment"
        #else
        composerError = "Clipboard attachment paste is available on macOS."
        placeholderStatus = composerError
        #endif
    }

    private func reviewPastedAttachmentDrafts(_ drafts: [ComposerAttachmentDraft], to channelID: ChannelID?, action: String) {
        let target = channelID.flatMap { snapshot.channelsByID[$0] }
        let blockedReason: String?
        if channelID == nil || target == nil {
            blockedReason = "Select a channel or DM before attaching files."
        } else if !canUploadFiles(in: target) {
            blockedReason = "You do not have permission to upload files here."
        } else if !isRuntimeSendCapable {
            blockedReason = effectiveRuntimeMode == .mock ? "Preview data cannot send messages." : "Reconnect before attaching files."
        } else {
            blockedReason = nil
        }
        pendingAttachmentDrop = AttachmentDropReview(
            channelID: channelID,
            channelName: target.map { composerPlaceholder(for: $0).replacingOccurrences(of: "Message ", with: "") },
            items: drafts.map(AttachmentDropReviewItem.init(draft:)),
            blockedReason: blockedReason
        )
        lastAttachmentAction = action
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
        let channelID = selectedConversationChannelID
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
            return (false, effectiveRuntimeMode == .mock ? "Preview data cannot send messages." : "Reconnect to send live messages.")
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
            return (false, effectiveRuntimeMode == .mock ? "Preview data cannot send messages." : "Reconnect to send live messages.")
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
            guard attachmentLoadTasks.count < maxConcurrentInlinePreviewLoads else {
                lastAttachmentAction = "Media-heavy safe mode: preview queue saturated"
                break
            }
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
        } catch is CancellationError {
            await MainActor.run {
                if case .loading = self.attachmentPreviewStates[item.id] {
                    self.attachmentPreviewStates[item.id] = .notLoaded
                }
                self.lastAttachmentAction = "Cancelled offscreen inline image preview"
            }
        } catch {
            let message = AttachmentSafety.safeErrorMessage(error)
            await MainActor.run {
                self.attachmentPreviewStates[item.id] = .failed(message)
                self.lastAttachmentAction = "Inline image preview failed"
            }
        }
    }

    private func cancelInlineImagePreviews(for message: Message) {
        for item in attachmentDisplayItems(for: message) {
            guard let task = attachmentLoadTasks[item.id] else { continue }
            task.cancel()
            attachmentLoadTasks[item.id] = nil
            if case .loading = attachmentPreviewStates[item.id] {
                attachmentPreviewStates[item.id] = .notLoaded
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
        if freezePerformanceDiagnostics.mediaSafeModeEnabled,
           kind == .attachmentPreview || kind == .customEmoji || kind == .profileBackground,
           queuedImageResourceRequests.count > maxConcurrentImageResourceLoads * 2 {
            lastImageResourceAction = "Media-heavy safe mode: tap-to-load placeholder"
            return
        }
        guard loadedImageResources[key] == nil,
              imageResourceLoadTasks[key] == nil,
              queuedImageResourceRequests[key] == nil
        else { return }
        if case .failed = imageResourceStates[key] {
            return
        }
        imageResourceStates[key] = .loading
        queuedImageResourceRequests[key] = request
        drainImageResourceQueue()
    }

    public func clearImageMemoryCache() async {
        await imageMemoryCache.removeAll()
        loadedImageResources.removeAll()
        imageResourceStates.removeAll()
        queuedImageResourceRequests.removeAll()
        lastImageResourceAction = "Cleared image memory cache"
    }

    public func reloadVisibleImages() {
        for message in selectedTimelineMessages.map(\.message) {
            loadInlineImagePreviews(for: message)
            loadImageResource(for: avatarFile(for: message), kind: .userAvatar)
        }
        loadVisibleIdentityImagesForCurrentSelection()
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
            activeTaskCount: imageResourceLoadTasks.count,
            queuedTaskCount: queuedImageResourceRequests.count,
            cacheEntryCount: snapshot.count,
            cacheByteCount: snapshot.byteCount,
            lastAction: lastImageResourceAction,
            activeCountByKind: countKinds(imageResourceLoadTasks.keys.map(\.kind)),
            queuedCountByKind: countKinds(queuedImageResourceRequests.values.map(\.kind)),
            failedCountByKind: countKinds(imageResourceStates.compactMap { key, state in
                if case .failed = state { return key.kind }
                return nil
            }),
            mediaSafeModeEnabled: freezePerformanceDiagnostics.mediaSafeModeEnabled
        )
    }

    private func countKinds(_ kinds: [ImageResourceKind]) -> [ImageResourceKind: Int] {
        kinds.reduce(into: [:]) { counts, kind in
            counts[kind, default: 0] += 1
        }
    }

    private func loadImageResource(_ request: ImageResourceRequest) async {
        defer {
            Task { @MainActor [weak self] in
                self?.imageResourceLoadTasks[request.cacheKey] = nil
                self?.drainImageResourceQueue()
            }
        }
        do {
            let loaded = try await imageResourceLoader.loadImage(request)
            await MainActor.run {
            self.loadedImageResources[request.cacheKey] = loaded.data
            self.imageResourceStates[request.cacheKey] = .readyRemote
                self.imageCompletedCount += 1
            self.lastImageResourceAction = loaded.fromCache ? "Loaded image from memory cache" : "Loaded image"
                self.updateFreezePerformanceDiagnostics(marker: self.lastImageResourceAction)
            }
        } catch is CancellationError {
            await MainActor.run {
                if case .loading = self.imageResourceStates[request.cacheKey] {
                    self.imageResourceStates[request.cacheKey] = .notLoaded
                }
                self.lastImageResourceAction = "Cancelled image load"
            }
        } catch {
            let message = AttachmentSafety.safeErrorMessage(error)
            await MainActor.run {
                self.imageResourceStates[request.cacheKey] = .failed(message)
                self.lastImageResourceAction = "Image load failed"
                self.updateVisibleIdentityDiagnostics()
                self.updateFreezePerformanceDiagnostics(marker: self.lastImageResourceAction)
            }
        }
    }

    private func drainImageResourceQueue() {
        while imageResourceLoadTasks.count < maxConcurrentImageResourceLoads,
              let next = queuedImageResourceRequests.first {
            queuedImageResourceRequests.removeValue(forKey: next.key)
            imageResourceLoadTasks[next.key] = Task { [weak self] in
                await self?.loadImageResource(next.value)
            }
        }
        if queuedImageResourceRequests.count > maxConcurrentImageResourceLoads * 2 {
            lastImageResourceAction = "Media-heavy safe mode: image queue saturated"
            freezePerformanceDiagnostics.mediaSafeModeEnabled = true
        }
        updateFreezePerformanceDiagnostics(marker: lastImageResourceAction)
    }

    private func loadVisibleIdentityImagesForCurrentSelection() {
        if let server = selectedServer {
            loadImageResource(for: server.icon, kind: .serverIcon)
            loadImageResource(for: server.banner, kind: .serverBanner)
        }
        for message in selectedTimelineMessages.prefix(80).map(\.message) {
            loadImageResource(for: avatarFile(for: message), kind: .userAvatar)
        }
        if let channel = selectedConversationChannel, DMChannelClassifier.isDirectMessageLike(channel) {
            for userID in channel.recipients.prefix(12) {
                loadImageResource(for: snapshot.usersByID[userID]?.avatar, kind: .userAvatar)
            }
        } else if let serverID = selection.serverID {
            for group in memberListGroups(for: serverID).prefix(4) {
                for item in group.items.prefix(24) {
                    loadImageResource(for: item.avatar, kind: .userAvatar)
                }
            }
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
        case .profileBackground:
            tag = file.tag.isEmpty ? "backgrounds" : file.tag
        case .customEmoji:
            tag = "emojis"
        }
        let filename = kind == .attachmentOriginal ? "original" : nil
        guard let url = try? LiveRemoteAttachmentLoader.mediaURL(baseURL: baseURL, tag: tag, fileID: file.id, filename: filename) else {
            return nil
        }
        let maxBytes: Int
        switch kind {
        case .serverBanner, .profileBackground:
            maxBytes = 4 * 1024 * 1024
        case .attachmentPreview:
            maxBytes = 8 * 1024 * 1024
        case .attachmentOriginal:
            maxBytes = 20 * 1024 * 1024
        case .userAvatar, .serverIcon, .customEmoji:
            maxBytes = 2 * 1024 * 1024
        }
        return ImageResourceRequest(id: file.id.rawValue, url: url, kind: kind, maxBytes: maxBytes, filename: file.filename)
    }

    public func member(for userID: UserID, serverID: ServerID?) -> ServerMember? {
        guard let serverID else { return nil }
        return snapshot.membersByServerAndUserID[ServerMemberKey(serverID: serverID, userID: userID)]
    }

    public func displayName(for user: User?, member: ServerMember? = nil, fallbackID: UserID? = nil) -> String {
        resolvedUserDisplay(for: user, member: member, fallbackID: fallbackID).displayName
    }

    public func resolvedUserDisplay(for user: User?, member: ServerMember? = nil, fallbackID: UserID? = nil, serverID: ServerID? = nil) -> ResolvedUserDisplay {
        UserDisplayResolver.resolved(
            userID: fallbackID ?? user?.id ?? member?.id.userID,
            user: user,
            member: member,
            server: serverID.flatMap { snapshot.serversByID[$0] }
        )
    }

    public func resolvedUserDisplay(for message: Message) -> ResolvedUserDisplay {
        let serverID = snapshot.channelsByID[message.channelID]?.serverID
        let member = message.member ?? member(for: message.authorID, serverID: serverID)
        let user = message.user ?? snapshot.usersByID[message.authorID]
        return resolvedUserDisplay(for: user, member: member, fallbackID: message.authorID, serverID: serverID)
    }

    public func avatarFile(for message: Message) -> File? {
        resolvedUserDisplay(for: message).avatarFile
    }

    public func composerPlaceholder(for channel: Channel) -> String {
        guard DMChannelClassifier.isDirectMessageLike(channel) else {
            return "Message #\(channel.displayName)"
        }
        switch channel.kind {
        case .savedMessages:
            return "Message Saved Notes"
        case .group:
            return "Message \(channel.displayName.isEmpty ? "group DM" : channel.displayName)"
        default:
            let names = directMessageParticipantItems(for: channel)
                .filter { $0.userID != currentUserID }
                .map(\.displayName)
            return "Message \(names.first ?? channel.displayName)"
        }
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
        guard message.system == nil else { return false }
        guard let channel = snapshot.channelsByID[message.channelID] else { return false }
        guard isRuntimeSendCapable else { return false }
        guard let permissions = resolvedPermissions(for: channel) else { return true }
        return permissions.contains(.react)
    }

    public func canEdit(_ message: Message) -> Bool {
        guard message.system == nil else { return false }
        return currentUserID == message.authorID && isRuntimeSendCapable
    }

    public func canEdit(_ timelineMessage: TimelineMessage) -> Bool {
        guard timelineMessage.status == .confirmed else { return false }
        guard timelineMessage.message.content?.isEmpty == false else { return false }
        return canEdit(timelineMessage.message)
    }

    public func canDelete(_ message: Message) -> Bool {
        guard message.system == nil else { return false }
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
        guard timelineMessage.message.system == nil else { return false }
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
        let member = member(for: timelineMessage.message.authorID, serverID: snapshot.channelsByID[timelineMessage.message.channelID]?.serverID)
        let authorName = timelineMessage.message.masquerade?.name ?? displayName(for: author, member: member, fallbackID: timelineMessage.message.authorID)
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
            messageActionStatus = nil
            if snapshot.channelsByID[channelID].map(DMChannelClassifier.isDirectMessageLike) == true {
                dmLiveTrace.composerTargetChannelID = channelID
                dmLiveTrace.timelineChannelID = selectedConversationChannelID
                dmLiveTrace.timelineMessageCount = selectedTimelineMessages.count
                dmLiveTrace.lastError = nil
            }
            acknowledgeSelectedChannel()
        } else {
            let error = messageController.lastErrorByChannelID[channelID] ?? "Message send failed."
            recordMessageSendDiagnostics(channelID: channelID, stage: .failed, result: .failed, error: error)
            messageActionStatus = error
            if snapshot.channelsByID[channelID].map(DMChannelClassifier.isDirectMessageLike) == true {
                dmLiveTrace.composerTargetChannelID = channelID
                dmLiveTrace.lastError = MessageSendDiagnosticsFormatter.redact(error)
            }
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
        guard let channelID = selectedConversationChannelID else { return }
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
        let items = Phase17MessageActions.actionItems(for: messageActionContext(for: timelineMessage))
        guard timelineMessage.message.system != nil else { return items }
        return items.filter { item in
            switch item.kind {
            case .copyText, .copyMessageID:
                return true
            default:
                return false
            }
        }
    }

    public func systemEventText(for message: Message) -> String {
        Phase27SystemEventPresenter.text(
            for: message,
            usersByID: snapshot.usersByID,
            membersByServerAndUserID: snapshot.membersByServerAndUserID,
            channel: snapshot.channelsByID[message.channelID]
        )
    }

    public func systemEventProfileTarget(for message: Message) -> UserID? {
        guard let target = Phase27SystemEventPresenter.profileTarget(for: message),
              snapshot.usersByID[target] != nil || member(for: target, serverID: snapshot.channelsByID[message.channelID]?.serverID) != nil
        else { return nil }
        return target
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
        let activeChannelID = selectedConversationChannelID
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
        let channelID = selectedConversationChannelID
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
            if let channelID = selectedConversationChannelID {
                acknowledgeSelectedChannel()
                scheduleLiveAckIfNeeded(channelID: channelID)
            }
        }
    }

    public func updateTimelineVisibility(messageID: MessageID, channelID: ChannelID, isVisible: Bool) {
        guard channelID == selectedConversationChannelID else { return }
        var visible = visibleMessageIDsByChannelID[channelID] ?? []
        let wasVisible = visible.contains(messageID)
        guard wasVisible != isVisible else { return }
        if isVisible {
            visible.insert(messageID)
        } else {
            visible.remove(messageID)
            if let message = selectedTimelineMessages.first(where: { $0.message.id == messageID })?.message {
                cancelInlineImagePreviews(for: message)
            }
        }
        timelineVisibleRangeUpdateCount += 1
        updateFreezePerformanceDiagnostics(marker: "visible range updated")
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
        guard let channelID = selectedConversationChannelID,
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
            let member = member(for: referenced.authorID, serverID: snapshot.channelsByID[referenced.channelID]?.serverID)
            let authorName = referenced.masquerade?.name ?? displayName(for: author, member: member, fallbackID: referenced.authorID)
            return "\(authorName): \(Self.replyPreviewText(for: referenced))"
        }
        if let resolution = resolvedReferencesByChannelID[message.channelID]?[replyID] {
            switch resolution {
            case let .loaded(referenced):
                let author = snapshot.usersByID[referenced.authorID]
                let member = member(for: referenced.authorID, serverID: snapshot.channelsByID[referenced.channelID]?.serverID)
                let authorName = referenced.masquerade?.name ?? displayName(for: author, member: member, fallbackID: referenced.authorID)
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
        let channelID = selectedConversationChannelID
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
        let channelID = selectedConversationChannelID
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
        let dm = dmRouteDiagnostics
        let dmTrace = DirectMessageLiveTraceFormatter.redactedText(dmLiveTrace)
        let members = memberListPerformanceDiagnostics
        let memberHydration = memberHydrationDiagnostics
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
        DM route diagnostics
        clickedChannel: \(TimelineCopyFormatter.shortID(dm.clickedChannelID?.rawValue))
        selectedConversation: \(TimelineCopyFormatter.shortID(dm.selectedConversationChannelID?.rawValue))
        selectedServer: \(TimelineCopyFormatter.shortID(dm.selectedServerID?.rawValue))
        loadRequested: \(dm.messageLoadRequested ? "yes" : "no")
        lastLoadResult: \(dm.lastLoadResult ?? "-")
        composerTarget: \(dm.composerTargetDescription ?? "-")
        Member list diagnostics
        knownMembers: \(members.knownMemberCount)
        knownUsers: \(members.knownUserCount)
        missingUsers: \(members.missingUserCount)
        renderedMembers: \(members.renderedMemberCount)
        droppedMembers: \(members.droppedMemberCount)
        droppedReason: \(members.droppedReasonSummary ?? "-")
        groups: \(members.groupCount)
        avatarQueue: \(members.avatarLoadQueueCount)
        Member hydration diagnostics
        source: \(memberHydration.source.rawValue)
        lastFetchServer: \(TimelineCopyFormatter.shortID(memberHydration.lastMemberFetchServerID?.rawValue))
        requested: \(memberHydration.requestedCount)
        returned: \(memberHydration.returnedCount)
        mergedMembers: \(memberHydration.mergedMemberCount)
        mergedUsers: \(memberHydration.mergedUserCount)
        missingUsersAfterMerge: \(memberHydration.missingUserCount)
        dropped: \(memberHydration.droppedCount)
        staleDiscarded: \(memberHydration.staleFetchDiscarded ? "yes" : "no")
        loading: \(memberHydration.isLoading ? "yes" : "no")
        error: \(memberHydration.error ?? "-")
        apiRoute: \(memberHydration.apiDiagnostics?.method ?? "-") \(memberHydration.apiDiagnostics?.route ?? "-")
        apiResource: \(memberHydration.apiDiagnostics?.redactedResourceID ?? "-")
        apiAuth: \(memberHydration.apiDiagnostics?.authHeaderPresent == true ? "present" : "missing")
        apiStatus: \(memberHydration.apiDiagnostics?.httpStatus.map(String.init) ?? "-")
        apiContentType: \(memberHydration.apiDiagnostics?.contentType ?? "-")
        apiShape: \(memberHydration.apiDiagnostics?.topLevelResponseShape ?? "-")
        apiDecoder: \(memberHydration.apiDiagnostics?.decoderSummary ?? "-")
        apiCategory: \(memberHydration.apiDiagnostics?.errorCategory ?? "-")
        apiRateRemaining: \(memberHydration.apiDiagnostics?.rateLimitInfo.remaining.map(String.init) ?? "-")
        """
        let text = Phase17MessageActions.redactedDiagnosticText(Phase6UIHelpers.safeDiagnostics(AttachmentDiagnosticsFormatter.redact(timeline + "\n" + attachmentText + "\n" + send + "\n" + dmTrace)))
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        placeholderStatus = "Timeline diagnostics copied"
        lastTimelineActionResult = "Copied redacted diagnostics"
    }

    public func copyRedactedDMTrace() {
        let text = DirectMessageLiveTraceFormatter.redactedText(dmLiveTrace)
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        placeholderStatus = "DM trace copied"
        lastTimelineActionResult = "Copied redacted DM trace"
    }

    public func copyRedactedDMDiagnostics() {
        refreshDMDiagnosticsSnapshot()
        let text = DMDiagnosticsFormatter.redactedText(dmDiagnostics)
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        placeholderStatus = "DM diagnostics copied"
        lastTimelineActionResult = "Copied redacted DM diagnostics"
    }

    public func copyRedactedParityDiagnostics() {
        let text = ParityMatrixFormatter.redactedText(phase30ParityMatrix)
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        placeholderStatus = "Parity diagnostics copied"
        lastTimelineActionResult = "Copied redacted parity diagnostics"
    }

    public func copyVisibleIdentityDiagnostics() {
        updateVisibleIdentityDiagnostics()
        updateFreezePerformanceDiagnostics(marker: "copied identity diagnostics")
        let identity = visibleIdentityDiagnostics
        let freeze = freezePerformanceDiagnostics
        let roles = memberRoleSortDiagnostics
        let text = Phase17MessageActions.redactedDiagnosticText(Phase6UIHelpers.safeDiagnostics("""
        Visible identity diagnostics
        unresolvedVisibleUsers: \(identity.unresolvedVisibleUserCount)
        shortenedVisibleIDs: \(identity.shortenedVisibleIDCount)
        avatarFailuresCached: \(identity.avatarFailureCacheCount)
        profileFetchMerges: \(identity.profileFetchMergeCount)
        memberWrapperUserMerges: \(identity.memberWrapperUserMergeCount)
        roleSortMode: \(roles.sortMode)
        roleGroupOrder: \(roles.groupOrder.joined(separator: ","))
        duplicateSuppression: \(roles.duplicateSuppressionCount)
        unknownRoles: \(roles.unknownRoleCount)
        memberGroupingCount: \(freeze.memberGroupingCount)
        memberGroupingCacheHits: \(freeze.memberGroupingCacheHitCount)
        markdownParse/cacheHits: \(freeze.markdownParseCount)/\(freeze.markdownCacheHitCount)
        imageActiveQueuedFailed: \(freeze.imageActiveCount)/\(freeze.imageQueuedCount)/\(freeze.imageFailedCount)
        mediaSafeMode: \(freeze.mediaSafeModeEnabled ? "yes" : "no")
        visibleRangeUpdates: \(freeze.visibleRangeUpdateCount)
        lastMarker: \(freeze.lastMainThreadMarker ?? "-")
        """))
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        placeholderStatus = "Identity diagnostics copied"
        lastTimelineActionResult = "Copied visible identity diagnostics"
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
        lastNotificationPermissionRequest = "requesting"
        updateNotificationDiagnostics()
        Task { [weak self, manager = notificationPermissionManager] in
            let result = await manager.requestAuthorization()
            await MainActor.run {
                self?.notificationPermissionStatus = result.statusAfter
                self?.notificationDiagnostics.lastPermissionRequest = result
                self?.lastNotificationPermissionRequest = result.summary
                self?.placeholderStatus = "Notification permission: \(result.statusAfter.rawValue)"
                self?.updateNotificationDiagnostics()
            }
        }
    }

    public func runNotificationSelfTest() {
        notificationDiagnostics.selfTestReport = "Self-test started"
        updateNotificationDiagnostics()
        let routeChannelID = selectedConversationChannelID ?? ChannelID(rawValue: "notification-self-test")
        Task { [weak self, manager = notificationPermissionManager, deliverer = notificationDeliverer] in
            let before = await manager.status()
            let request = await manager.requestAuthorization()
            let after = await manager.status()
            var steps = [
                "before \(before.rawValue)",
                "request \(request.granted == true ? "granted" : "not granted")",
                "after \(after.rawValue)"
            ]
            if after.allowsDelivery {
                let event = NotificationEvent(
                    id: "self-test-\(UUID().uuidString)",
                    route: NotificationRoute(channelID: routeChannelID),
                    title: "Liquid Bagel notification self-test",
                    body: "This local notification was scheduled by an explicit settings action.",
                    kind: .mention
                )
                do {
                    try await deliverer.deliver(event)
                    steps.append("scheduled local test")
                } catch {
                    steps.append("schedule failed \(error.localizedDescription)")
                }
            } else {
                steps.append("local test skipped")
            }
            await MainActor.run {
                self?.notificationPermissionStatus = after
                self?.notificationDiagnostics.lastPermissionRequest = request
                self?.lastNotificationPermissionRequest = request.summary
                self?.notificationDiagnostics.selfTestReport = steps.joined(separator: " -> ")
                self?.placeholderStatus = "Notification self-test complete"
                self?.updateNotificationDiagnostics()
            }
        }
    }

    public func resetNotificationDiagnostics() {
        notificationDiagnostics = NotificationDiagnostics(permissionStatus: notificationPermissionStatus, nativeEnabled: notificationPreferences.nativeNotificationsEnabled, inAppEnabled: notificationPreferences.inAppBannersEnabled)
        lastNotificationPermissionRequest = nil
        notificationBanners.removeAll()
        deliveredNotificationIDs.removeAll()
        expiredNotificationRouteCount = 0
        placeholderStatus = "Notification diagnostics reset"
        updateNotificationDiagnostics()
    }

    public func openMacOSNotificationSettings() {
        #if canImport(AppKit)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
            placeholderStatus = "Opened macOS Notification Settings"
        }
        #endif
    }

    public var notificationBuildReadinessDiagnostics: NotificationBuildReadinessDiagnostics {
        let bundleID = Bundle.main.bundleIdentifier ?? "-"
        let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "-"
        let appPath = NotificationContentFormatter.sanitize(Bundle.main.bundleURL.path)
        let sandbox = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] == nil ? "not reported" : "reported"
        #if canImport(UserNotifications)
        let isPackageTest = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || Bundle.main.bundleURL.path.contains("/Xcode.app/")
        let delegateConfigured = isPackageTest ? false : (UNUserNotificationCenter.current().delegate != nil)
        #else
        let delegateConfigured = false
        #endif
        let request = notificationDiagnostics.lastPermissionRequest
        return NotificationBuildReadinessDiagnostics(
            bundleIdentifier: bundleID,
            bundleDisplayName: displayName,
            appPath: appPath,
            codeSigningAllowed: "NO in checked Xcode build settings",
            detectedSignatureStatus: testingSignedNotificationBuild ? "user marked signed build" : "unsigned/debug likely",
            sandboxStatus: sandbox,
            delegateConfigured: delegateConfigured,
            lastUNErrorName: request?.errorCodeName,
            lastBeforeStatus: request?.statusBefore.rawValue,
            lastAfterStatus: request?.statusAfter.rawValue,
            systemSettingsCheck: "If unavailable here, check System Settings > Notifications > Liquid Bagel manually.",
            testingSignedBuild: testingSignedNotificationBuild
        )
    }

    public var notificationBuildSigningChecklist: String {
        notificationBuildReadinessDiagnostics.summary
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
        guard let channelID = selectedConversationChannelID else { return }
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
        guard let channel = selectedConversationChannel ?? snapshot.channelsByID.values.first(where: { $0.kind == .directMessage || $0.kind == .textChannel }) else {
            placeholderStatus = "No channel available for notification demo."
            return
        }
        let event = NotificationEvent(
            id: "demo-\(UUID().uuidString)",
            route: NotificationRoute(serverID: channel.serverID, channelID: channel.id, messageID: nil),
            title: "Liquid Bagel test notification",
            body: "This notification was sent from the explicit settings test action.",
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
        let extra = """
        authorizer: \(notificationAuthorizerKind)
        buildChecklist: \(notificationBuildReadinessDiagnostics.summary)
        bundleDisplayName: \(notificationBuildReadinessDiagnostics.bundleDisplayName)
        appPath: \(notificationBuildReadinessDiagnostics.appPath)
        codeSigningAllowed: \(notificationBuildReadinessDiagnostics.codeSigningAllowed)
        detectedSignature: \(notificationBuildReadinessDiagnostics.detectedSignatureStatus)
        systemSettingsCheck: \(notificationBuildReadinessDiagnostics.systemSettingsCheck)
        lastPermissionRequest: \(lastNotificationPermissionRequest ?? "-")
        requestDetails: \(notificationDiagnostics.lastPermissionRequest?.summary ?? "-")
        selfTest: \(notificationDiagnostics.selfTestReport ?? "-")
        """
        let text = Phase17MessageActions.redactedDiagnosticText(NotificationContentFormatter.sanitize(notificationDiagnostics.redactedText + "\n" + extra))
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        placeholderStatus = "Notification diagnostics copied"
    }

    public func openNotificationRoute(_ route: NotificationRoute) async {
        expiredNotificationRouteCount += removeExpiredQueuedNotificationRoutes()
        let knownChannel = snapshot.channelsByID[route.channelID]
        let isDMRoute = knownChannel.map(DMChannelClassifier.isDirectMessageLike) == true || route.serverID == nil
        if isDMRoute,
           effectiveRuntimeMode == .liveManual,
           (effectiveSessionState != .connected || sessionCoordinator?.hydrationStatus.readyReceived != true) {
            queueNotificationRoute(route)
            placeholderStatus = "Reconnect to open this message."
            recordNotificationRouteOutcome(.queuedAwaitingManualConnect)
            return
        }
        if isDMRoute,
           knownChannel == nil,
           effectiveRuntimeMode == .liveManual,
           effectiveSessionState == .connected,
           sessionCoordinator?.hydrationStatus.readyReceived == true {
            await refreshDMs(source: .notification)
            guard snapshot.channelsByID[route.channelID] != nil else {
                placeholderStatus = "Notification DM is not available."
                recordNotificationRouteOutcome(.failed)
                return
            }
        }
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
            placeholderStatus = "Reconnect to open this message."
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
        let channelID = selectedConversationChannelID
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
        guard result.channelID == selectedConversationChannelID else { return }
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
                  let channelID = selectedConversationChannelID,
                  let apiClient = sessionCoordinator?.apiClient
            else {
                let message = "Live search requires a connected live session."
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
        let activeChannelID = selectedConversationChannelID
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
        let activeChannelID = selectedConversationChannelID
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
        guard result.channelID == selectedConversationChannelID else { return }
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
        guard result.channelID == selectedConversationChannelID else { return }
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
        guard result.channelID == selectedConversationChannelID else { return }
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
        guard let channelID = selectedConversationChannelID else { return }
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
              let channelID = selectedConversationChannelID,
              let apiClient = sessionCoordinator?.apiClient
        else {
            remoteSearchStatus = "Reconnect before searching the selected channel."
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
            authorDisplayName: resolvedDisplayName(userID: result.authorID, channelID: result.channelID),
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
            authorDisplayName: resolvedDisplayName(userID: message.authorID, channelID: message.channelID),
            createdAt: message.createdAt,
            snippet: snippet,
            mode: mode,
            isPinned: message.isPinned || mode == .pinned,
            isLoaded: isLoaded,
            safeStatus: isLoaded ? nil : "Result outside loaded range"
        )
    }

    private func resolvedDisplayName(userID: UserID, channelID: ChannelID) -> String {
        let serverID = snapshot.channelsByID[channelID]?.serverID
        let user = snapshot.usersByID[userID]
        let member = serverID.flatMap { snapshot.membersByServerAndUserID[ServerMemberKey(serverID: $0, userID: userID)] }
        return resolvedUserDisplay(for: user, member: member, fallbackID: userID, serverID: serverID).displayName
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
        let activeChannelID = selectedConversationChannelID
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
        let activeChannelID = selectedConversationChannelID
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
        channels(for: serverID).first { $0.kind == .textChannel }
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
        let mergedSnapshot = snapshotWithHydratedMemberOverlay(snapshot)
        updateMemberSourceDiagnostics(previous: oldSnapshot, current: mergedSnapshot)
        self.snapshot = mergedSnapshot
        messageController.hydrate(from: mergedSnapshot)
        applyRealtimeDeleteDiff(previous: oldSnapshot, current: mergedSnapshot)
        processNotificationDiff(previous: oldSnapshot, current: mergedSnapshot)
        previousSnapshot = mergedSnapshot
        restoreOrValidateSelection()
        acknowledgeSelectedChannel()
        scheduleSelectedChannelLoad()
        reconcileTimelineSelection()
        quickSwitcherViewModel.update(snapshot: mergedSnapshot, selection: selection)
        updateDockBadge()
        updateNotificationDiagnostics()
        refreshDMDiagnosticsSnapshot()
        replayQueuedNotificationRoutesIfReady()
        if effectiveRuntimeMode == .liveManual, effectiveSessionState == .connected {
            loadVisibleIdentityImagesForCurrentSelection()
        }
    }

    private func snapshotWithHydratedMemberOverlay(_ incoming: RealtimeSnapshot) -> RealtimeSnapshot {
        guard !restHydratedMembersByServerID.isEmpty else { return incoming }
        var copy = incoming
        for (serverID, hydratedMembers) in restHydratedMembersByServerID {
            copy.membersByServerAndUserID = copy.membersByServerAndUserID.filter { $0.key.serverID != serverID }
            for (key, member) in hydratedMembers {
                copy.membersByServerAndUserID[key] = member
            }
        }
        return copy
    }

    private func updateMemberSourceDiagnostics(previous: RealtimeSnapshot, current: RealtimeSnapshot) {
        let previousKeys = Set(previous.membersByServerAndUserID.keys)
        let currentKeys = Set(current.membersByServerAndUserID.keys)
        guard previousKeys != currentKeys else { return }
        if let selectedServerID = selection.serverID {
            memberHydrationDiagnostics.missingUserCount = missingUserCount(serverID: selectedServerID)
        }
        if memberHydrationDiagnostics.source != .restHydrated {
            memberHydrationDiagnostics.source = previousKeys.isEmpty ? .readyOnly : .realtimeUpdate
        }
        memberHydrationDiagnostics.lastUpdatedAt = Date()
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
        appLifecyclePhase.selectedChannelIsVisible && selectedConversationChannelID != nil
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
            activeChannelID: selectedConversationChannelID,
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
        let channelID = selectedConversationChannelID
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
        guard let channelID = selectedConversationChannelID else { return }
        let snapshotMessages = snapshot.messagesByChannelID[channelID] ?? []
        let isDMRoute = snapshot.channelsByID[channelID].map(DMChannelClassifier.isDirectMessageLike) == true
        if isDMRoute {
            dmRouteDiagnostics.messageLoadRequested = true
            dmRouteDiagnostics.selectedConversationChannelID = channelID
            dmRouteDiagnostics.selectedServerID = selection.serverID
            dmRouteDiagnostics.composerTargetDescription = snapshot.channelsByID[channelID]?.displayName
            dmLiveTrace.messageLoadRequested = true
            dmLiveTrace.messageLoadChannelID = channelID
            dmLiveTrace.messageLoadUsedREST = effectiveRuntimeMode == .liveManual && effectiveSessionState == .connected
            dmLiveTrace.selectedConversationChannelID = selectedConversationChannelID
            dmLiveTrace.timelineChannelID = selectedConversationChannelID
            dmLiveTrace.composerTargetChannelID = selectedConversationChannelID
            if let channel = snapshot.channelsByID[channelID] {
                dmLiveTrace.sidebarParticipantCount = directMessageParticipantItems(for: channel).count
            }
        }
        selectedChannelLoadTask = Task { [weak self] in
            guard let self else { return }
            await self.messageController.loadInitialIfNeeded(channelID: channelID, snapshotMessages: snapshotMessages)
            if isDMRoute {
                let result = self.safeLoadResultDescription(for: channelID)
                self.dmRouteDiagnostics.lastLoadResult = result
                self.dmLiveTrace.messageLoadResult = result
                self.dmLiveTrace.timelineChannelID = self.selectedConversationChannelID
                self.dmLiveTrace.timelineMessageCount = self.selectedTimelineMessages.count
                self.dmLiveTrace.composerTargetChannelID = self.selectedConversationChannelID
                if let channel = self.snapshot.channelsByID[channelID] {
                    self.dmLiveTrace.sidebarParticipantCount = self.directMessageParticipantItems(for: channel).count
                }
                self.dmLiveTrace.lastError = result.hasPrefix("failed") ? result : nil
            }
            if self.timelineViewport.channelID != channelID || self.timelineViewport.pendingScrollIntent == nil {
                self.updateViewportForSelectedChannel()
            }
        }
    }

    private func safeLoadResultDescription(for channelID: ChannelID) -> String {
        switch messageController.state(for: channelID) {
        case .idle:
            return "idle"
        case .loading:
            return "loading"
        case let .loaded(messages, hasMoreBefore):
            return "loaded \(messages.count), hasMoreBefore \(hasMoreBefore ? "yes" : "no")"
        case let .loadingOlder(messages):
            return "loading older \(messages.count)"
        case .empty:
            return "empty"
        case let .failed(error, cachedMessages):
            return "failed \(MessageSendDiagnosticsFormatter.redact(error)), cached \(cachedMessages.count)"
        }
    }

    private func acknowledgeSelectedChannel() {
        guard let channelID = selectedConversationChannelID else { return }
        guard snapshot.channelsByID[channelID] != nil else {
            lastAckResult = "Skipped: selected channel missing"
            return
        }
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
        refreshDMDiagnosticsSnapshot()
    }

    private func scheduleLiveAckIfNeeded(channelID: ChannelID) {
        let decision = readAckDecision(channelID: channelID)
        lastAckResult = decision.diagnostic
        guard case let .send(messageID) = decision else {
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
                    self?.refreshDMDiagnosticsSnapshot()
                }
            } catch {
                await MainActor.run {
                    self?.lastAckResult = "Failed: \(error.userFacingMessage)"
                    self?.refreshDMDiagnosticsSnapshot()
                }
            }
        }
    }

    private func readAckDecision(channelID: ChannelID) -> Phase27ReadAckDecision {
        guard effectiveRuntimeMode == .liveManual else { return .skip("not live manual") }
        guard effectiveSessionState == .connected else { return .skip("not connected") }
        guard snapshot.channelsByID[channelID] != nil else { return .skip("channel missing") }
        guard timelineViewport.isAtNewest else { return .skip("not at newest") }
        let hasUnreadState = snapshot.unreadsByChannelID[channelID]?.lastMessageID != nil
            || (localReadStates[channelID]?.unreadCount ?? 0) > 0
            || (localReadStates[channelID]?.mentionCount ?? 0) > 0
        guard hasUnreadState else {
            return .skip("no unread state")
        }

        let candidates = messageController.state(for: channelID).timelineMessages
            .filter { $0.status == .confirmed && $0.message.channelID == channelID && $0.message.system == nil }
        let visibleID = timelineViewport.visibleRange?.lastVisibleMessageID
        let visibleMessageID = visibleID.flatMap { id in candidates.last(where: { $0.message.id == id })?.message.id }
        guard let messageID = visibleMessageID ?? candidates.last?.message.id else {
            return .skip("no normal message")
        }
        guard lastAckedMessageByChannelID[channelID] != messageID else { return .skip("duplicate") }
        return .send(messageID)
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
        case .openQuickSwitcher, .closeTransientUI, .refresh, .openAccountSettings, .openConnectionSettings, .openNotificationSettings, .toggleMemberPanel, .jumpToHome, .jumpToFriends, .jumpToAddFriend, .jumpToDiscover, .openJoinInvite, .openCreateServer, .openDiscoverInBrowser, .focusTimeline, .resetTimelineTuningDefault:
            return true
        case .pasteAttachment:
            return selectedConversationChannelID != nil
        case .openServerOverview, .openServerAppearance, .openCategoryEditor, .openRoles, .openPermissions, .openMembers:
            return selection.serverID != nil
        case .openPermissionEditor:
            return selection.serverID != nil && permissionEditingDisabledReason() == nil
        case .openBanList:
            return selection.serverID != nil && serverManagementCapabilities().isConnectedForLiveActions
        case .createRole:
            return selection.serverID != nil && roleManagementDisabledReason() == nil
        case .createCategory:
            return selection.serverID != nil && channelManagementDisabledReason() == nil
        case .openCreateChannel:
            return selection.serverID != nil && channelManagementDisabledReason() == nil
        case .openChannelSettings:
            return selectedChannel?.kind == .textChannel && channelManagementDisabledReason() == nil
        case .deleteSelectedChannel:
            return selectedChannel?.kind == .textChannel && channelManagementDisabledReason(destructive: true) == nil
        case .openInviteManagement:
            return selection.serverID != nil && inviteManagementDisabledReason() == nil
        case .createInviteForCurrentChannel:
            return (selection.channelID != nil || selection.serverID.flatMap { firstVisibleTextChannel(in: $0) } != nil) && inviteManagementDisabledReason() == nil
        case .openChannelSearch, .openLoadedMessageFind:
            return selectedConversationChannelID != nil
        case .openLiveChannelSearch:
            return selectedConversationChannelID != nil && effectiveRuntimeMode == .liveManual && effectiveSessionState == .connected
        case .openPinnedChannelSearch:
            return selectedConversationChannelID != nil
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
        case .copyTimelineDiagnostics:
            return isDeveloperControlsEnabled
        case .focusComposer:
            return selectedConversationChannelID != nil
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
            guard let channelID = selectedConversationChannelID else { return false }
            return !isTextEntryFocused && firstUnreadMessageID(for: channelID) != nil
        case .replyToSelectedMessage:
            return !isTextEntryFocused && selectedTimelineMessage.map { canReply(to: $0) } == true
        case .cancelReply:
            return replyContext(for: selectedConversationChannelID) != nil
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
        case .pasteAttachment:
            return "Select a channel before pasting an attachment."
        case .openServerOverview, .openServerAppearance, .openCategoryEditor, .openRoles, .openPermissions, .openMembers:
            return "Select a server before opening server settings."
        case .openPermissionEditor:
            return permissionEditingDisabledReason() ?? "Select a server before editing permissions."
        case .openBanList:
            return "Reconnect before loading the ban list."
        case .createRole:
            return roleManagementDisabledReason() ?? "Select a server before creating a role."
        case .createCategory:
            return channelManagementDisabledReason() ?? "Select a server before creating a category."
        case .openCreateChannel:
            return channelManagementDisabledReason() ?? "Select a server before creating a channel."
        case .openChannelSettings:
            return channelManagementDisabledReason() ?? "Select a text channel before opening channel settings."
        case .deleteSelectedChannel:
            return channelManagementDisabledReason(destructive: true) ?? "Select a text channel before deleting it."
        case .openInviteManagement:
            return inviteManagementDisabledReason() ?? "Select a server before managing invites."
        case .createInviteForCurrentChannel:
            return inviteManagementDisabledReason() ?? "Select a server text channel before creating an invite."
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
            if command == .openLiveChannelSearch { return "Live search requires a connected live session." }
            return "Select a channel before searching."
        case .selectNextSearchResult, .selectPreviousSearchResult, .jumpToSelectedSearchResult:
            return "No search result is selected."
        case .loadAroundSelectedSearchResult:
            return routeVerificationResult.aroundMessageFetch == .supported ? "Selected result is already loaded." : "Around-message route is not verified."
        case .clearSearchHighlights:
            return "No search highlights are active."
        case .startTimelineCalibration, .addTimelineCalibrationCheckpoint, .applyTimelineCalibrationRecommendation, .importCalibrationNotes, .copyTimelineCalibration, .copyTimelineDiagnostics:
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
        case .pasteAttachment:
            pasteAttachmentFromClipboard()
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
        case .openJoinInvite:
            openJoinInvite()
        case .openCreateServer:
            openCreateServer()
        case .openServerOverview:
            openServerOverview()
        case .openServerAppearance:
            openServerOverview()
            selectedServerSettingsTab = .appearance
        case .openCategoryEditor:
            openServerOverview()
            selectedServerSettingsTab = .categories
        case .openRoles:
            openServerOverview()
            selectedServerSettingsTab = .roles
        case .openPermissions:
            openServerOverview()
            selectedServerSettingsTab = .permissions
        case .openMembers:
            openServerOverview()
            selectedServerSettingsTab = .members
        case .openPermissionEditor:
            openServerOverview()
            if let serverID = selection.serverID {
                openPermissionEditor(scope: .serverDefault(serverID: serverID))
            }
        case .openBanList:
            openServerOverview()
            selectedServerSettingsTab = .members
            Task { [weak self] in await self?.refreshBanList() }
        case .createRole:
            openServerOverview()
            openCreateRole()
        case .createCategory:
            openServerOverview()
            selectedServerSettingsTab = .categories
            createCategoryDraft(title: "New Category")
        case .openCreateChannel:
            openCreateChannel()
        case .openChannelSettings:
            openChannelSettings()
        case .deleteSelectedChannel:
            requestDeleteSelectedChannel()
        case .openInviteManagement:
            openInviteManagement()
        case .createInviteForCurrentChannel:
            Task { [weak self] in await self?.createInviteForSelectedChannel() }
        case .openDiscoverInBrowser:
            openDiscoverInBrowser()
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
            cancelReply(for: selectedConversationChannelID)
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

@MainActor
@Observable
public final class LiquidBagelAppModel {
    public let coordinator: AppSessionCoordinator
    public let shell: MainShellViewModel
    public let loginViewModel: FirstRunLoginViewModel

    public init(coordinator: AppSessionCoordinator = AppSessionCoordinator()) {
        self.coordinator = coordinator
        self.shell = MainShellViewModel(
            snapshot: RealtimeSnapshot(),
            runtimeMode: .liveManual,
            sessionState: .signedOut,
            currentUser: nil
        )
        self.loginViewModel = FirstRunLoginViewModel(coordinator: coordinator)
    }

    public var startupState: AppStartupState {
        switch coordinator.sessionState {
        case .mock:
            return .ready
        case .signedOut:
            return .noCredential
        case .loadingCredential, .validatingCredential:
            return coordinator.hasSavedCredential ? .validatingCredential : .noCredential
        case .savedCredentialUnvalidated:
            return coordinator.hasSavedCredential ? .savedCredentialFailed("A saved session is available for this environment. Retry connection when you are ready.") : .noCredential
        case .validatedReady, .readyToConnect:
            return coordinator.hasSavedCredential ? .savedCredentialFailed("The saved session is ready, but realtime is not connected.") : .noCredential
        case .connecting:
            return .connectingLive
        case .connected:
            return .ready
        case let .validationFailed(msg), let .invalidSession(msg), let .connectionFailed(msg):
            return coordinator.hasSavedCredential ? .savedCredentialFailed(msg) : .noCredential
        case let .keychainFailed(msg):
            return .startupFailed(.keychainUnavailable(msg))
        case let .failed(msg):
            return .startupFailed(.unknown(msg))
        }
    }
}

@MainActor
@Observable
public final class FirstRunLoginViewModel {
    public var email: String = ""
    public var password: String = ""
    public var sessionName: String = "Liquid Bagel macOS"
    public var mfaResponse: String = ""
    public var manualToken: String = ""
    public var tokenLabel: String = ""
    public var isAdvancedExpanded: Bool = false
    public var loginError: LoginErrorDisplay?

    private let coordinator: AppSessionCoordinator

    public init(coordinator: AppSessionCoordinator) {
        self.coordinator = coordinator
    }

    public var flowState: LoginFlowState { coordinator.loginFlowState }
    public var mfaChallenge: LoginMFAChallenge? { coordinator.mfaChallenge }
    public var isLoading: Bool { flowState == .submitting }
    public var canSubmitLogin: Bool { !email.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty && !isLoading }
    public var canSubmitMFA: Bool { !mfaResponse.trimmingCharacters(in: .whitespaces).isEmpty && !isLoading }
    public var canSubmitToken: Bool { !manualToken.trimmingCharacters(in: .whitespaces).isEmpty && !isLoading }

    public func submitLogin() async {
        loginError = nil
        await coordinator.login(email: email, password: password, friendlyName: sessionName)
        updateLoginError()
        if flowState == .mfaRequired {
            mfaResponse = ""
        }
    }

    public func submitMFA() async {
        guard let challenge = mfaChallenge, let method = challenge.allowedMethods.first else { return }
        loginError = nil
        let response = mfaResponseValue(method: method, code: mfaResponse)
        await coordinator.continueLoginMFA(response: response, friendlyName: sessionName)
        updateLoginError()
    }

    private func mfaResponseValue(method: MFAMethod, code: String) -> MFAResponse {
        switch method {
        case .password: .password(code)
        case .recovery: .recoveryCode(code)
        case .totp: .totpCode(code)
        }
    }

    public func submitToken() async {
        loginError = nil
        let label = tokenLabel.trimmingCharacters(in: .whitespaces)
        await coordinator.validateImportedToken(manualToken, localLabel: label.isEmpty ? nil : label)
        updateLoginError()
        if flowState == .succeeded {
            manualToken = ""
            tokenLabel = ""
        }
    }

    public func clearForm() {
        email = ""
        password = ""
        sessionName = "Liquid Bagel macOS"
        mfaResponse = ""
        manualToken = ""
        tokenLabel = ""
        loginError = nil
    }

    private func updateLoginError() {
        loginError = coordinator.loginDiagnostics.lastErrorCategory
    }
}

public struct FirstRunLoginView: View {
    @Bindable private var viewModel: FirstRunLoginViewModel
    private let coordinator: AppSessionCoordinator

    public init(viewModel: FirstRunLoginViewModel, coordinator: AppSessionCoordinator) {
        self.viewModel = viewModel
        self.coordinator = coordinator
    }

    enum Field: Hashable {
        case email, password, sessionName, mfaCode, manualToken, tokenLabel
    }

    @FocusState private var focused: Field?

    public var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 60)
                    loginCard
                    Spacer(minLength: 60)
                }
            }
        }
        .frame(minWidth: 480, minHeight: 500)
    }

    @ViewBuilder
    private var loginCard: some View {
        VStack(spacing: 24) {
            header
            if let mfaChallenge = viewModel.mfaChallenge {
                mfaSection(challenge: mfaChallenge)
            } else {
                credentialsSection
            }
            if let error = viewModel.loginError {
                Text(error.localizedDescription)
                    .foregroundStyle(.red)
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel("Login error: \(error.localizedDescription)")
            }
            advancedSection
            signInButton
        }
        .padding(32)
        .frame(maxWidth: 440)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.12), radius: 20, y: 4)
    }

    @ViewBuilder
    private var header: some View {
        VStack(spacing: 12) {
            if let appIcon = NSImage(named: "AppIcon") {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .accessibilityLabel("Liquid Bagel app icon")
            }
            Text("Liquid Bagel")
                .font(.title.bold())
            environmentRow
        }
    }

    @ViewBuilder
    private var environmentRow: some View {
        let env = coordinator.environment
        let envLabel = env.isProduction ? "Production" : (env.apiBaseURL.host() ?? env.apiBaseURL.absoluteString)
        HStack(spacing: 4) {
            Image(systemName: "network")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(envLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel("Environment: \(envLabel)")
    }

    @ViewBuilder
    private var credentialsSection: some View {
        VStack(spacing: 12) {
            TextField("Email", text: $viewModel.email)
                .textFieldStyle(.roundedBorder)
                .textContentType(.emailAddress)
                .autocorrectionDisabled()
                .focused($focused, equals: .email)
                .accessibilityLabel("Email address")
                .onSubmit { focused = .password }

            SecureField("Password", text: $viewModel.password)
                .textFieldStyle(.roundedBorder)
                .focused($focused, equals: .password)
                .accessibilityLabel("Password")
                .onSubmit {
                    Task { await viewModel.submitLogin() }
                }

            TextField("Session name", text: $viewModel.sessionName)
                .textFieldStyle(.roundedBorder)
                .focused($focused, equals: .sessionName)
                .accessibilityLabel("Session name")
                .onSubmit {
                    Task { await viewModel.submitLogin() }
                }
        }
    }

    @ViewBuilder
    private func mfaSection(challenge: LoginMFAChallenge) -> some View {
        VStack(spacing: 12) {
            Text("Two-factor authentication required")
                .font(.headline)
            Text("Enter the code from your authenticator app or other MFA method.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            SecureField("Authentication code", text: $viewModel.mfaResponse)
                .textFieldStyle(.roundedBorder)
                .focused($focused, equals: .mfaCode)
                .accessibilityLabel("MFA authentication code")
                .onSubmit {
                    Task { await viewModel.submitMFA() }
                }
            Button("Continue") {
                Task { await viewModel.submitMFA() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canSubmitMFA)
        }
    }

    @ViewBuilder
    private var advancedSection: some View {
        DisclosureGroup(
            isExpanded: $viewModel.isAdvancedExpanded,
            content: {
                VStack(spacing: 12) {
                    SecureField("Session token", text: $viewModel.manualToken)
                        .textFieldStyle(.roundedBorder)
                        .focused($focused, equals: .manualToken)
                        .accessibilityLabel("Session token for manual import")
                    TextField("Token label (optional)", text: $viewModel.tokenLabel)
                        .textFieldStyle(.roundedBorder)
                        .focused($focused, equals: .tokenLabel)
                        .accessibilityLabel("Label for the imported token")
                    Button("Import Token") {
                        Task {
                            await viewModel.submitToken()
                        }
                    }
                    .disabled(!viewModel.canSubmitToken)
                }
                .padding(.top, 8)
            },
            label: {
                Text("Advanced")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        )
    }

    @ViewBuilder
    private var signInButton: some View {
        if viewModel.mfaChallenge == nil {
            HStack(spacing: 12) {
                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("Sign In") {
                    Task {
                        await viewModel.submitLogin()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canSubmitLogin)
                .keyboardShortcut(.defaultAction)
                .accessibilityLabel("Sign in with email and password")
            }
        }
    }
}

public struct SavedCredentialFailureView: View {
    public let message: String
    public let coordinator: AppSessionCoordinator

    public init(message: String, coordinator: AppSessionCoordinator) {
        self.message = message
        self.coordinator = coordinator
    }

    public var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
                Text("Session Unavailable")
                    .font(.title2.bold())
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                HStack(spacing: 12) {
                    Button("Try Again") {
                        Task { await coordinator.reconnectLiveManually() }
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Sign In Again") {
                        Task { await coordinator.forgetLocalSession() }
                    }
                    Button("Forget Session") {
                        Task { await coordinator.forgetLocalSession() }
                    }
                    .foregroundStyle(.red)
                }
            }
            .padding(40)
        }
    }
}

public struct StartupFailureView: View {
    public let failure: AppStartupFailure

    public init(failure: AppStartupFailure) {
        self.failure = failure
    }

    public var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 48))
                    .foregroundStyle(.red)
                Text("Startup Failed")
                    .font(.title2.bold())
                Text(failure.message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
            .padding(40)
        }
    }
}

private struct StartupProgressView: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                Text("Liquid Bagel")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

public struct LiquidBagelRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var appModel: LiquidBagelAppModel

    public init(appModel: LiquidBagelAppModel = LiquidBagelAppModel()) {
        _appModel = State(initialValue: appModel)
    }

    public var body: some View {
        Group {
            switch appModel.startupState {
            case .loadingPreferences, .validatingCredential, .connectingLive:
                StartupProgressView()
            case .noCredential:
                FirstRunLoginView(viewModel: appModel.loginViewModel, coordinator: appModel.coordinator)
            case let .savedCredentialFailed(message):
                SavedCredentialFailureView(message: message, coordinator: appModel.coordinator)
            case let .startupFailed(failure):
                StartupFailureView(failure: failure)
            case .ready:
                MainShellView(viewModel: appModel.shell)
            }
        }
        .task {
            appModel.shell.attachSessionCoordinator(appModel.coordinator)
            await appModel.coordinator.startLiveFirstSession()
            appModel.shell.syncFromSessionCoordinator()
        }
        .onChange(of: scenePhase) { _, phase in
            appModel.shell.updateAppLifecyclePhase(AppLifecyclePhase(phase))
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
            if viewModel.selection.isMemberPanelVisible, viewModel.rightSidebarContext.isPeopleContext {
                Divider()
                MemberPanelView(viewModel: viewModel, context: viewModel.rightSidebarContext)
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
        .sheet(isPresented: $viewModel.isJoinInvitePresented) {
            JoinInviteView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.isCreateServerPresented) {
            CreateServerView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.isInviteManagementPresented) {
            InviteManagementView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.isServerOverviewPresented) {
            ServerOverviewView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.isCreateChannelPresented) {
            CreateChannelView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.isChannelSettingsPresented) {
            ChannelSettingsView(viewModel: viewModel)
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
        .sheet(item: $viewModel.pendingAttachmentDrop) { review in
            AttachmentDropReviewSheet(
                review: review,
                onRemove: { itemID in viewModel.removePendingDroppedAttachment(itemID) },
                onCancel: { viewModel.cancelPendingAttachmentDrop() },
                onAdd: { viewModel.addPendingDroppedAttachmentsToComposer() }
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
        .confirmationDialog(
            "Join this server?",
            isPresented: Binding(
                get: { viewModel.pendingInviteJoin != nil },
                set: { if !$0 { viewModel.pendingInviteJoin = nil } }
            )
        ) {
            Button("Join Server") {
                Task { await viewModel.confirmPendingInviteJoin() }
            }
            Button("Cancel", role: .cancel) {
                viewModel.pendingInviteJoin = nil
            }
        } message: {
            Text("Liquid Bagel will join only after this confirmation.")
        }
        .confirmationDialog(
            "Revoke this invite?",
            isPresented: Binding(
                get: { viewModel.pendingInviteDeletion != nil },
                set: { if !$0 { viewModel.pendingInviteDeletion = nil } }
            )
        ) {
            Button("Revoke Invite", role: .destructive) {
                Task { await viewModel.confirmPendingInviteDeletion() }
            }
            Button("Cancel", role: .cancel) {
                viewModel.pendingInviteDeletion = nil
            }
        } message: {
            Text("This invite code stops working after the API confirms revocation.")
        }
        .confirmationDialog(
            "Delete \(viewModel.pendingChannelDeletion?.channel.displayName ?? "this channel")?",
            isPresented: Binding(
                get: { viewModel.pendingChannelDeletion != nil },
                set: { if !$0 { viewModel.pendingChannelDeletion = nil } }
            )
        ) {
            Button("Delete Channel", role: .destructive) {
                Task { await viewModel.confirmPendingChannelDeletion() }
            }
            Button("Cancel", role: .cancel) {
                viewModel.pendingChannelDeletion = nil
            }
        } message: {
            Text("This removes the channel after the API confirms deletion. Messages in that channel will no longer be visible here.")
        }
        .confirmationDialog(
            viewModel.pendingMemberModerationAction.map { "Confirm \($0.action.rawValue)" } ?? "Confirm member action?",
            isPresented: Binding(
                get: { viewModel.pendingMemberModerationAction != nil },
                set: { if !$0 { viewModel.pendingMemberModerationAction = nil } }
            )
        ) {
            if let pending = viewModel.pendingMemberModerationAction {
                Button("Confirm", role: memberActionRole(pending.action)) {
                    Task { await viewModel.confirmPendingMemberAction() }
                }
            }
            Button("Cancel", role: .cancel) {
                viewModel.pendingMemberModerationAction = nil
            }
        } message: {
            if let pending = viewModel.pendingMemberModerationAction {
                Text("Liquid Bagel will apply this action to \(viewModel.displayName(for: viewModel.snapshot.usersByID[pending.member.id.userID], member: pending.member, fallbackID: pending.member.id.userID)) only after confirmation.")
            }
        }
        .overlay(alignment: .bottom) {
            if let status = viewModel.placeholderStatus ?? viewModel.phase24Status ?? viewModel.phase23Status ?? viewModel.relationshipActionStatus ?? viewModel.messageActionStatus ?? viewModel.composerError ?? viewModel.sessionCoordinator?.lastErrorMessage {
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
                Text(viewModel.title)
                    .font(.headline)
            }
            ToolbarItemGroup {
                Button { viewModel.perform(.openQuickSwitcher) } label: { Label("Quick Switcher", systemImage: "magnifyingglass") }
                Button { viewModel.perform(.openAccountSettings) } label: { Label("Settings", systemImage: "gearshape") }
            }
        }
        .popover(isPresented: Binding(get: { viewModel.profileUserID != nil }, set: { if !$0 { viewModel.closeUserProfile() } })) {
            if let user = viewModel.profilePresentationUser {
                UserProfileCardView(viewModel: viewModel, user: user)
            } else {
                EmptyStateView(title: "Profile unavailable", message: "User data is not present in the current snapshot.", systemImage: "person.crop.circle.badge.questionmark")
                    .padding(StoatSpacing.large)
            }
        }
    }

    private func memberActionRole(_ action: MemberModerationAction) -> ButtonRole? {
        switch action {
        case .kick, .ban:
            return .destructive
        case .saveNickname, .resetNickname, .removeAvatar, .timeout, .clearTimeout:
            return nil
        }
    }

    @ViewBuilder private var content: some View {
        if viewModel.isTimelineRouteActive {
            ChatPlaceholderView(viewModel: viewModel)
        } else {
            switch viewModel.selection.space {
            case .home:
            HomeView(viewModel: viewModel)
            case .discover:
            DiscoverView(viewModel: viewModel)
            case .directMessages:
            FriendsPlaceholderView(viewModel: viewModel)
            case .server:
            ChatPlaceholderView(viewModel: viewModel)
            }
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

private struct AttachmentDropReviewSheet: View {
    let review: AttachmentDropReview
    let onRemove: (UUID) -> Void
    let onCancel: () -> Void
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: StoatSpacing.large) {
            HStack {
                Label("Attach Files", systemImage: "paperclip")
                    .font(.headline)
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }

            if let channelName = review.channelName {
                Text(channelName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let blocked = review.blockedReason {
                Label(blocked, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: StoatSpacing.small) {
                    ForEach(review.items, id: \.id) { item in
                        HStack(spacing: StoatSpacing.medium) {
                            itemPreview(item)
                            VStack(alignment: .leading, spacing: StoatSpacing.xxSmall) {
                                Text(item.filename)
                                    .font(.callout.weight(.medium))
                                    .lineLimit(1)
                                Text(statusText(for: item))
                                    .font(.caption)
                                    .foregroundStyle(statusColor(for: item))
                                    .lineLimit(2)
                            }
                            Spacer()
                            Button {
                                onRemove(item.id)
                            } label: {
                                Image(systemName: "xmark")
                            }
                            .buttonStyle(.borderless)
                            .help("Remove file")
                            .accessibilityLabel("Remove \(item.filename)")
                        }
                        .padding(StoatSpacing.small)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: StoatRadius.control, style: .continuous))
                    }
                }
            }
            .frame(minHeight: 180, maxHeight: 340)

            HStack {
                Text("\(review.attachableItems.count) ready to attach")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Add to Message") {
                    onAdd()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!review.canAddToMessage)
            }
        }
        .padding(StoatSpacing.large)
        .frame(width: 520)
    }

    @ViewBuilder private func itemPreview(_ item: AttachmentDropReviewItem) -> some View {
        #if canImport(AppKit)
        if let data = item.draft?.previewData, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: StoatRadius.small, style: .continuous))
        } else {
            genericIcon(item)
        }
        #else
        genericIcon(item)
        #endif
    }

    private func genericIcon(_ item: AttachmentDropReviewItem) -> some View {
        Image(systemName: item.systemImage)
            .font(.title3)
            .frame(width: 44, height: 44)
            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: StoatRadius.small, style: .continuous))
            .accessibilityHidden(true)
    }

    private func statusText(for item: AttachmentDropReviewItem) -> String {
        item.warning ?? item.subtitle
    }

    private func statusColor(for item: AttachmentDropReviewItem) -> Color {
        item.warning == nil ? .secondary : .orange
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
                    Button("Forget Session", role: .destructive) {
                        confirmForget = true
                    }
                    .disabled(viewModel.sessionCoordinator?.hasSavedCredential != true)

                    Button("Revoke Session on Server", role: .destructive) {
                        confirmRevoke = true
                    }
                    .disabled(viewModel.sessionCoordinator?.hasSavedCredential != true)

                }
            }

            Section("Manual Token Import") {
                TextField("Local label", text: $localLabel)
                SecureField("Session token", text: $token)
                HStack {
                    Button("Import and Connect") {
                        Task {
                            let submitted = token
                            token = ""
                            await viewModel.sessionCoordinator?.validateImportedToken(submitted, localLabel: localLabel)
                            viewModel.syncFromSessionCoordinator()
                        }
                    }
                    .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
                    .disabled(!viewModel.composerReadiness(for: viewModel.selectedConversationChannelID).canSend)
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

            if viewModel.isDeveloperControlsEnabled {
                developerDiagnosticsSection
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

    @ViewBuilder private var developerDiagnosticsSection: some View {
        let timeline = viewModel.timelineDiagnostics()
        let dm = viewModel.dmRouteDiagnostics
        let members = viewModel.memberListPerformanceDiagnostics
        let memberHydration = viewModel.memberHydrationDiagnostics
        let send = viewModel.currentMessageSendDiagnostics()
        let parity = viewModel.phase30ParityMatrix
        let identity = viewModel.visibleIdentityDiagnostics
        let freeze = viewModel.freezePerformanceDiagnostics
        let roleSort = viewModel.memberRoleSortDiagnostics
        let dmConversation = viewModel.dmDiagnostics
        Section("Developer Diagnostics") {
            LabeledContent("Timeline", value: "loaded \(timeline.loadedMessageCount), visible \(TimelineCopyFormatter.shortID(timeline.firstVisibleMessageID?.rawValue)) to \(TimelineCopyFormatter.shortID(timeline.lastVisibleMessageID?.rawValue))")
            LabeledContent("DM route", value: "clicked \(TimelineCopyFormatter.shortID(dm.clickedChannelID?.rawValue)), selected \(TimelineCopyFormatter.shortID(dm.selectedConversationChannelID?.rawValue)), load \(dm.messageLoadRequested ? "requested" : "idle")")
            if let result = dm.lastLoadResult {
                LabeledContent("DM load", value: result)
            }
            if let target = dm.composerTargetDescription {
                LabeledContent("DM composer", value: target)
            }
            LabeledContent("Sidebar", value: "\(viewModel.rightSidebarContext)")
            LabeledContent("Members", value: "known \(members.knownMemberCount), rendered \(members.renderedMemberCount), missing users \(members.missingUserCount), missing avatars \(members.missingAvatarCount), dropped \(members.droppedMemberCount), groups \(members.groupCount)")
            LabeledContent("Member role order", value: "\(roleSort.sortMode), cache \(roleSort.cacheHit ? "hit" : "miss"), unknown roles \(roleSort.unknownRoleCount), dupes \(roleSort.duplicateSuppressionCount)")
            LabeledContent("Member group order", value: roleSort.groupOrder.joined(separator: " -> "))
            if let dropSummary = members.droppedReasonSummary {
                LabeledContent("Member notes", value: dropSummary)
            }
            LabeledContent("Visible identity", value: "unresolved \(identity.unresolvedVisibleUserCount), shortened \(identity.shortenedVisibleIDCount), avatar failures \(identity.avatarFailureCacheCount)")
            LabeledContent("Identity merges", value: "profiles \(identity.profileFetchMergeCount), member wrapper users \(identity.memberWrapperUserMergeCount)")
            LabeledContent("Freeze markers", value: freeze.lastMainThreadMarker ?? "-")
            LabeledContent("Freeze counts", value: "timeline \(freeze.timelineRenderPassCount), grouping \(freeze.memberGroupingCount), grouping cache \(freeze.memberGroupingCacheHitCount), visible \(freeze.visibleRangeUpdateCount)")
            LabeledContent("Markdown cache", value: "parsed \(freeze.markdownParseCount), hits \(freeze.markdownCacheHitCount)")
            LabeledContent("Image queue", value: "active \(freeze.imageActiveCount), queued \(freeze.imageQueuedCount), completed \(freeze.imageCompletedCount), failed \(freeze.imageFailedCount), safe \(freeze.mediaSafeModeEnabled ? "yes" : "no")")
            LabeledContent("Member source", value: "\(memberHydration.source.rawValue), server \(TimelineCopyFormatter.shortID(memberHydration.lastMemberFetchServerID?.rawValue))")
            LabeledContent("Member REST", value: "requested \(memberHydration.requestedCount), returned \(memberHydration.returnedCount), merged \(memberHydration.mergedMemberCount), users \(memberHydration.mergedUserCount)")
            LabeledContent("Member stale/error", value: "stale \(memberHydration.staleFetchDiscarded ? "yes" : "no"), loading \(memberHydration.isLoading ? "yes" : "no"), error \(memberHydration.error ?? "-")")
            if let api = memberHydration.apiDiagnostics {
                LabeledContent("Member API route", value: "\(api.method) \(api.route), auth \(api.authHeaderPresent ? "present" : "missing")")
                LabeledContent("Member API response", value: "status \(api.httpStatus.map(String.init) ?? "-"), type \(api.contentType ?? "-"), shape \(api.topLevelResponseShape ?? "-")")
                LabeledContent("Member API decode", value: "\(api.errorCategory ?? "ok"): \(api.decoderSummary ?? "-")")
                LabeledContent("Member API rate limit", value: "remaining \(api.rateLimitInfo.remaining.map(String.init) ?? "-"), reset \(api.rateLimitInfo.resetAfterMilliseconds.map(String.init) ?? "-")")
            }
            LabeledContent("Member images", value: "queue \(members.avatarLoadQueueCount)")
            LabeledContent("Emoji", value: "known \(viewModel.snapshot.emojisByID.count), picker \(viewModel.commonEmojiItems.count)")
            if let emojiDiagnostics = viewModel.emojiPickerDiagnostics {
                LabeledContent("Emoji picker", value: emojiDiagnostics)
            }
            LabeledContent("Send", value: "canSend \(send.canSend ? "yes" : "no"), stage \(send.lastSendStage?.rawValue ?? "-"), result \(send.lastSendResult?.rawValue ?? "-")")
            if let error = send.lastError {
                LabeledContent("Send error", value: error)
            }
            LabeledContent("Notifications", value: "\(viewModel.notificationDiagnostics.permissionStatus.rawValue), queued \(viewModel.notificationDiagnostics.queuedRouteCount)")
            LabeledContent("Notification build", value: viewModel.notificationBuildSigningChecklist)
            if let selfTest = viewModel.notificationDiagnostics.selfTestReport {
                LabeledContent("Notification self-test", value: selfTest)
            }
            LabeledContent("DM trace channel", value: "clicked \(TimelineCopyFormatter.shortID(viewModel.dmLiveTrace.clickedChannelID?.rawValue)), load \(TimelineCopyFormatter.shortID(viewModel.dmLiveTrace.messageLoadChannelID?.rawValue)), composer \(TimelineCopyFormatter.shortID(viewModel.dmLiveTrace.composerTargetChannelID?.rawValue))")
            LabeledContent("DM trace state", value: "messages \(viewModel.dmLiveTrace.timelineMessageCount), participants \(viewModel.dmLiveTrace.sidebarParticipantCount), REST \(viewModel.dmLiveTrace.messageLoadUsedREST ? "yes" : "no")")
            if let error = viewModel.dmLiveTrace.lastError {
                LabeledContent("DM trace error", value: error)
            }
            LabeledContent("DM conversations", value: "direct \(dmConversation.knownDirectMessageCount), groups \(dmConversation.knownGroupDMCount), saved \(dmConversation.savedNotesState.label)")
            LabeledContent("DM refresh", value: "\(dmConversation.lastRefreshStatus.rawValue), source \(dmConversation.lastRefreshSource?.rawValue ?? "-"), count \(dmConversation.lastRefreshCount), duration \(dmConversation.lastRefreshDurationMilliseconds.map(String.init) ?? "-")ms")
            LabeledContent("DM open", value: "\(dmConversation.lastOpenStatus.rawValue), source \(dmConversation.lastOpenSource?.rawValue ?? "-"), target \(TimelineCopyFormatter.shortID(dmConversation.lastOpenTarget))")
            LabeledContent("DM merge/fallbacks", value: "duplicates \(dmConversation.duplicateMergeCount), missing users \(dmConversation.missingRecipientUserCount), raw fallbacks \(dmConversation.rawIDFallbackCount)")
            LabeledContent("DM unread/ack", value: "unread \(dmConversation.unreadChannelCount), mentions \(dmConversation.mentionCount), local clears \(dmConversation.locallyClearedUnreadCount), ack \(dmConversation.lastAckSummary ?? "-")")
            LabeledContent("DM safe errors", value: dmConversation.safeErrorCategories.map(\.rawValue).joined(separator: ", "))
            LabeledContent("Parity Matrix", value: "\(parity.count(.done)) done, \(parity.count(.partial)) partial, \(parity.count(.broken)) broken, \(parity.count(.blockedByUnverifiedAPI)) blocked, \(parity.count(.deferred)) deferred, \(parity.count(.outOfScope)) out of scope")
            if let dmParity = parity.items.first(where: { $0.section == "Core chat" && $0.name == "DMs" }) {
                LabeledContent("DM parity", value: "\(dmParity.status.rawValue): \(dmParity.recommendedNextAction)")
            }
            HStack {
                Button("Copy Timeline Diagnostics") {
                    viewModel.copyRedactedTimelineDiagnostics()
                }
                Button("Copy DM Trace") {
                    viewModel.copyRedactedDMTrace()
                }
                Button("Copy DM Diagnostics") {
                    viewModel.copyRedactedDMDiagnostics()
                }
                Button("Copy Parity Diagnostics") {
                    viewModel.copyRedactedParityDiagnostics()
                }
                Button("Copy Notification Diagnostics") {
                    viewModel.copyRedactedNotificationDiagnostics()
                }
                Button("Copy Identity Diagnostics") {
                    viewModel.copyVisibleIdentityDiagnostics()
                }
                Button("Refresh Members") {
                    Task { await viewModel.refreshSelectedServerMembers() }
                }
                .disabled(!viewModel.canRefreshSelectedServerMembers)
            }
            Text("Diagnostics are redacted and omit tokens, raw response bodies, message content, and local file paths.")
                .font(.caption)
                .foregroundStyle(.secondary)
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
        case .liveManual: "Live"
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
            if let user = viewModel.currentUserForPresentation {
                currentUserRailItem(user)
                    .onAppear {
                        viewModel.loadImageResource(for: user.avatar, kind: .userAvatar)
                    }
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

    private func currentUserRailItem(_ user: User) -> some View {
        let display = UserDisplayResolver.resolved(userID: user.id, user: user)
        return Button {
            viewModel.showUserProfile(user.id, source: .currentUser)
        } label: {
            ZStack(alignment: .topTrailing) {
                AvatarView(
                    title: display.displayName,
                    size: StoatSize.serverIcon,
                    isOnline: user.online,
                    presence: user.status?.presence,
                    imageData: viewModel.imageData(for: display.avatarFile, kind: .userAvatar)
                )
                if user.status?.presence == .busy {
                    Image(systemName: "bell.slash.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .offset(x: -1, y: -3)
                }
            }
            .frame(width: StoatSize.serverIcon, height: StoatSize.serverIcon)
        }
        .buttonStyle(.plain)
        .help("Profile and status")
        .contextMenu {
            statusMenuButton(.online)
            statusMenuButton(.idle)
            statusMenuButton(.focus)
            statusMenuButton(.busy)
            statusMenuButton(.invisible)
        }
        .accessibilityLabel("Profile and status, \(user.status?.presence?.displayName ?? (user.online ? "Online" : "Offline"))")
        .accessibilityHint("Open your profile, or right click to change status")
    }

    private func statusMenuButton(_ presence: Presence) -> some View {
        Button {
            Task { await viewModel.setCurrentUserPresence(presence) }
        } label: {
            Label(presence.displayName, systemImage: statusSystemImage(presence))
        }
    }

    private func statusSystemImage(_ presence: Presence) -> String {
        switch presence {
        case .online:
            return "circle.fill"
        case .idle:
            return "moon.fill"
        case .focus:
            return "scope"
        case .busy:
            return "bell.slash.fill"
        case .invisible:
            return "circle"
        case .unknown:
            return "questionmark.circle"
        }
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
        VStack(alignment: .leading, spacing: StoatSpacing.small) {
            HStack(alignment: .top, spacing: StoatSpacing.small) {
                VStack(alignment: .leading, spacing: StoatSpacing.xSmall) {
                    Text(headerTitle)
                        .font(StoatTypography.sidebarHeader)
                        .lineLimit(1)
                    Text(runtimeSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if viewModel.selection.serverID != nil {
                    GlassIconButton("Server overview", systemImage: "gearshape") {
                        viewModel.openServerOverview()
                    }
                    .frame(minWidth: 32, minHeight: 32)
                    .contentShape(Rectangle())
                    .zIndex(2)
                    .accessibilityLabel("Server overview")
                    .accessibilityHint("Open selected server overview and management actions")
                }
            }
            serverHeaderBanner
        }
        .padding(.horizontal, StoatSpacing.large)
        .onAppear {
            viewModel.loadImageResource(for: viewModel.selectedServer?.banner, kind: .serverBanner)
        }
        .onChange(of: viewModel.selectedServer?.id) { _, _ in
            viewModel.loadImageResource(for: viewModel.selectedServer?.banner, kind: .serverBanner)
        }
    }

    @ViewBuilder private var serverHeaderBanner: some View {
        #if canImport(AppKit)
        if let server = viewModel.selectedServer,
           let banner = server.banner {
            ZStack(alignment: .bottomLeading) {
                if let data = viewModel.imageData(for: banner, kind: .serverBanner),
                   let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(Color.primary.opacity(0.06))
                        .overlay {
                            if viewModel.imageResourceStates[ImageCacheKey(id: banner.id.rawValue, kind: .serverBanner)] == .loading {
                                ProgressView().controlSize(.small)
                            }
                        }
                }
                LinearGradient(colors: [.clear, .black.opacity(0.34)], startPoint: .top, endPoint: .bottom)
                Text(server.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(StoatSpacing.small)
            }
            .frame(height: 72)
            .clipShape(RoundedRectangle(cornerRadius: StoatRadius.control, style: .continuous))
            .allowsHitTesting(false)
            .accessibilityLabel("Server banner for \(server.name)")
        }
        #endif
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
                return "Connected"
            case .connecting, .loadingCredential, .validatingCredential:
                return "Connecting"
            case .signedOut:
                return "Signed out"
            case .readyToConnect, .validatedReady:
                return "Ready"
            case .savedCredentialUnvalidated:
                return "Saved credential"
            case .invalidSession:
                return "Invalid session"
            case .validationFailed, .connectionFailed, .keychainFailed, .failed:
                return "Needs attention"
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
            section("Direct Messages") {
                let items = viewModel.directMessageItems
                if !items.contains(where: { $0.channel.kind == .savedMessages }) {
                    SavedNotesEntryButton(viewModel: viewModel)
                        .padding(.horizontal, StoatSpacing.medium)
                }
                if items.isEmpty {
                    Text("No direct messages")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, StoatSpacing.medium)
                } else {
                    ForEach(items.prefix(8)) { item in
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
            section("Direct Messages") {
                HStack(spacing: StoatSpacing.small) {
                    Button {
                        Task { await viewModel.refreshDMs(source: .directMessages) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(!viewModel.canRefreshDMs || viewModel.isRelationshipRefreshInProgress)
                    .help("Refresh DMs")
                    .accessibilityLabel("Refresh DMs")
                    if viewModel.isRelationshipRefreshInProgress {
                        ProgressView()
                            .controlSize(.small)
                    }
                    if let status = viewModel.relationshipActionStatus {
                        Text(status)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .padding(.horizontal, StoatSpacing.medium)
                let items = viewModel.directMessageItems
                if !items.contains(where: { $0.channel.kind == .savedMessages }) {
                    SavedNotesEntryButton(viewModel: viewModel)
                        .padding(.horizontal, StoatSpacing.medium)
                }
                if items.isEmpty {
                    Text("No direct messages")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, StoatSpacing.medium)
                } else {
                    ForEach(items) { item in
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
            VStack(spacing: StoatSpacing.xSmall) {
                Button {
                    viewModel.openCreateChannel()
                } label: {
                    Label("Create Channel", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GlassButtonStyle())
                .disabled(viewModel.channelManagementDisabledReason() != nil)
                .accessibilityLabel("Create channel")
                .accessibilityHint(viewModel.channelManagementDisabledReason() ?? "Create a text channel in this server")

                if let channel = viewModel.selectedChannel {
                    Button {
                        viewModel.openChannelSettings()
                    } label: {
                        Label("Channel Settings", systemImage: "slider.horizontal.3")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GlassButtonStyle())
                    .disabled(channel.kind != .textChannel || viewModel.channelManagementDisabledReason() != nil)
                    .accessibilityLabel("Channel settings for \(channel.displayName)")
                    .accessibilityHint(viewModel.channelManagementDisabledReason() ?? "Edit this text channel")
                }
            }
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
        .contextMenu {
            ForEach(viewModel.channelContextMenuItems(for: channel)) { item in
                Button(role: item.isDestructive ? .destructive : nil) {
                    viewModel.performChannelContextMenuAction(item.kind, for: channel)
                } label: {
                    Label(item.title, systemImage: item.systemImage)
                }
                .disabled(item.disabledReason != nil)
                .help(item.disabledReason ?? item.title)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    Label(viewModel.selectedConversationChannel?.displayName ?? "No channel", systemImage: "number")
                        .font(.headline)
                    if let topic = viewModel.selectedConversationChannel?.description {
                        Text(topic).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    GlassIconButton("Pinned in this channel", systemImage: "pin") {
                        viewModel.openChannelSearch(mode: .pinned)
                    }
                    GlassIconButton("Search this channel", systemImage: "magnifyingglass") {
                        viewModel.openChannelSearch(mode: .loadedOnly)
                    }
                    if viewModel.rightSidebarContext.isPeopleContext {
                        let memberToggleLabel = viewModel.selection.isMemberPanelVisible ? "Hide Members" : "Show Members"
                        GlassIconButton(memberToggleLabel, systemImage: "sidebar.right") { viewModel.toggleMemberPanel() }
                            .accessibilityLabel(memberToggleLabel)
                    }
                    let channelSettingsDisabledReason = viewModel.selectedChannel?.kind == .textChannel ? viewModel.channelManagementDisabledReason() : "Select a text channel before opening channel settings."
                    GlassIconButton(channelSettingsDisabledReason ?? "Channel Settings", systemImage: "gearshape", isDisabled: channelSettingsDisabledReason != nil) {
                        viewModel.openChannelSettings()
                    }
                    .accessibilityLabel("Channel Settings")
                }
            }
            MessageTimelineView(viewModel: viewModel)
            if let channel = viewModel.selectedConversationChannel {
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
                    placeholder: inputReadiness.isEnabled ? viewModel.composerPlaceholder(for: channel) : inputReadiness.reason,
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
                        viewModel.reviewDroppedAttachmentURLs(urls, to: channel.id)
                    },
                    emojiItems: viewModel.commonEmojiItems,
                    emojiSections: viewModel.composerEmojiSections,
                    onInsertEmoji: { emoji in
                        viewModel.insertEmoji(emoji, in: channel.id)
                    },
                    onPasteImageData: { data in
                        viewModel.reviewPastedImageData(data, to: channel.id)
                    },
                    onPasteFileURLs: { urls in
                        viewModel.reviewDroppedAttachmentURLs(urls, to: channel.id)
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
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil) { providers in
            loadDroppedFileURLs(from: providers)
            return true
        }
    }

    private func loadDroppedFileURLs(from providers: [NSItemProvider]) {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = item as? URL
                }
                if let url {
                    Task { @MainActor in
                        viewModel.reviewDroppedAttachmentURLsForSelectedChannel([url])
                    }
                }
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
        let _ = StoatFeatureLayoutDiagnostics.body("MessageTimelineView", detail: "messages=\(viewModel.selectedTimelineMessages.count)")
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: viewModel.messageDensity == .compact ? StoatSpacing.small : StoatSpacing.medium) {
                    if viewModel.selectedConversationChannel == nil {
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
        if let channelID = viewModel.selectedConversationChannelID,
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
        let users = viewModel.typingUsers(for: viewModel.selectedConversationChannelID)
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
        if let channelID = viewModel.selectedConversationChannelID,
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
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private let group: TimelineMessageGroup
    private let author: User?
    private let viewModel: MainShellViewModel

    public init(group: TimelineMessageGroup, author: User?, viewModel: MainShellViewModel) {
        self.group = group
        self.author = author
        self.viewModel = viewModel
    }

    public var body: some View {
        let _ = StoatFeatureLayoutDiagnostics.body("TimelineMessageGroupView", detail: "id=\(group.id)")
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(group.messages.enumerated()), id: \.element.id) { index, timelineMessage in
                VStack(alignment: .leading, spacing: StoatSpacing.xSmall) {
                    if viewModel.inlineEditState?.messageID == timelineMessage.message.id {
                        InlineMessageEditor(viewModel: viewModel)
                            .padding(.leading, index == 0 ? 0 : StoatSize.avatar + StoatSpacing.medium)
                    } else if timelineMessage.message.system != nil {
                        systemEventRow(timelineMessage)
                    } else {
                        MessageRow(
                            message: timelineMessage.message,
                            author: author,
                            authorDisplayNameOverride: viewModel.resolvedUserDisplay(for: timelineMessage.message).displayName,
                            authorDisplayColor: roleColor(for: timelineMessage.message),
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
                            customEmojiItems: viewModel.inlineCustomEmojiItems(for: timelineMessage.message),
                            authorAvatarData: viewModel.imageData(for: viewModel.resolvedUserDisplay(for: timelineMessage.message).avatarFile, kind: .userAvatar),
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
                            },
                            onOpenAuthorProfile: {
                                let display = viewModel.resolvedUserDisplay(for: timelineMessage.message)
                                viewModel.showUserProfile(display.userID, source: .messageName, serverID: display.serverContextID)
                            }
                        )
                        .id(timelineMessage.message.id)
                        .onAppear {
                            viewModel.updateTimelineVisibility(messageID: timelineMessage.message.id, channelID: timelineMessage.message.channelID, isVisible: true)
                            viewModel.loadInlineImagePreviews(for: timelineMessage.message)
                            viewModel.loadImageResource(for: viewModel.resolvedUserDisplay(for: timelineMessage.message).avatarFile, kind: .userAvatar)
                            viewModel.loadCustomEmojiImages(for: timelineMessage.message)
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

    @ViewBuilder private func systemEventRow(_ timelineMessage: TimelineMessage) -> some View {
        let row = SystemEventRow(text: viewModel.systemEventText(for: timelineMessage.message))
        if let target = viewModel.systemEventProfileTarget(for: timelineMessage.message) {
            Button {
                viewModel.showUserProfile(target, source: .systemEventActor, serverID: viewModel.snapshot.channelsByID[timelineMessage.message.channelID]?.serverID)
            } label: {
                row
            }
            .buttonStyle(.plain)
            .help("Open Profile")
            .id(timelineMessage.message.id)
            .onAppear {
                viewModel.updateTimelineVisibility(messageID: timelineMessage.message.id, channelID: timelineMessage.message.channelID, isVisible: true)
            }
            .onDisappear {
                viewModel.updateTimelineVisibility(messageID: timelineMessage.message.id, channelID: timelineMessage.message.channelID, isVisible: false)
            }
        } else {
            row
                .id(timelineMessage.message.id)
                .onAppear {
                    viewModel.updateTimelineVisibility(messageID: timelineMessage.message.id, channelID: timelineMessage.message.channelID, isVisible: true)
                }
                .onDisappear {
                    viewModel.updateTimelineVisibility(messageID: timelineMessage.message.id, channelID: timelineMessage.message.channelID, isVisible: false)
                }
        }
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
            if let emoji = viewModel.customEmojiDisplayItem(for: $0.emoji) {
                return MessageReactionDisplayItem(
                    emoji: $0.emoji,
                    count: $0.count,
                    hasCurrentUserReacted: $0.hasCurrentUserReacted,
                    customEmojiName: emoji.name,
                    customEmojiImageData: viewModel.imageData(for: emoji.file, kind: .customEmoji)
                )
            }
            return MessageReactionDisplayItem(emoji: $0.emoji, count: $0.count, hasCurrentUserReacted: $0.hasCurrentUserReacted)
        }
    }

    private func buttonRole(for item: MessageActionItem) -> ButtonRole? {
        item.role == .destructive ? .destructive : nil
    }

    private func roleColor(for message: Message) -> Color? {
        guard colorSchemeContrast != .increased,
              let roleColor = viewModel.roleColor(for: message)
        else { return nil }
        return Color(red: roleColor.red, green: roleColor.green, blue: roleColor.blue)
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
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private let viewModel: MainShellViewModel
    private let context: RightSidebarContext

    public init(viewModel: MainShellViewModel, context: RightSidebarContext? = nil) {
        self.viewModel = viewModel
        self.context = context ?? viewModel.rightSidebarContext
    }

    public var body: some View {
        let _ = StoatFeatureLayoutDiagnostics.body("MemberSidebarView", detail: "\(context)")
        VStack(alignment: .leading, spacing: StoatSpacing.large) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                if case let .serverMembers(serverID, _) = context {
                    Button {
                        Task { await viewModel.hydrateServerMembers(serverID: serverID, force: true, reason: "panel refresh") }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(viewModel.isMemberHydrationLoading(serverID: serverID) || !viewModel.canRefreshSelectedServerMembers)
                    .help("Refresh Members")
                    .accessibilityLabel("Refresh members")
                }
                Text("\(count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            content
            Spacer()
        }
        .padding(StoatSpacing.large)
        .background(.thinMaterial)
        .task(id: context) {
            viewModel.hydrateMembersForVisibleContextIfNeeded()
        }
    }

    @ViewBuilder private var content: some View {
        switch context {
        case let .directMessageParticipants(channelID), let .groupDMParticipants(channelID):
            if let channel = viewModel.snapshot.channelsByID[channelID] {
                dmParticipants(channel)
            } else {
                EmptyStateView(title: "No participants", message: "Participant data is not present in the current snapshot.", systemImage: "person")
                    .frame(maxWidth: .infinity)
            }
        case .serverMembers:
            serverMembers
        case .hidden, .homeSummary, .friendsSummary, .discoverSummary:
            EmptyView()
        }
    }

    private var title: String {
        switch context {
        case let .directMessageParticipants(channelID), let .groupDMParticipants(channelID):
            if viewModel.snapshot.channelsByID[channelID]?.kind == .savedMessages {
                return "Saved Notes"
            }
            return "Participants"
        case .serverMembers:
            return "Members"
        case .hidden, .homeSummary, .friendsSummary, .discoverSummary:
            return ""
        }
    }

    private var count: Int {
        switch context {
        case let .directMessageParticipants(channelID), let .groupDMParticipants(channelID):
            guard let channel = viewModel.snapshot.channelsByID[channelID] else { return 0 }
            return viewModel.directMessageParticipantItems(for: channel).count
        case .serverMembers:
            return groups.reduce(0) { $0 + $1.items.count }
        case .hidden, .homeSummary, .friendsSummary, .discoverSummary:
            return 0
        }
    }

    private var groups: [MemberListGroup] {
        guard case let .serverMembers(serverID, _) = context else { return [] }
        return viewModel.memberListGroups(for: serverID)
    }

    @ViewBuilder private var legacyContent: some View {
        if let channel = viewModel.selectedConversationChannel, DMChannelClassifier.isDirectMessageLike(channel) {
            dmParticipants(channel)
        } else if viewModel.selection.serverID != nil {
            serverMembers
        } else {
            EmptyStateView(title: "No member list", message: "Open a server channel or DM to show people here.", systemImage: "person.2")
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private var serverMembers: some View {
        if case let .serverMembers(serverID, _) = context,
           let status = viewModel.memberHydrationStatusMessage(for: serverID) {
            HStack(spacing: StoatSpacing.small) {
                if viewModel.isMemberHydrationLoading(serverID: serverID) {
                    ProgressView().controlSize(.small)
                }
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer()
            }
        }
        if groups.isEmpty {
            EmptyStateView(title: "No members", message: emptyMemberMessage, systemImage: "person.2")
                .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: StoatSpacing.medium) {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: StoatSpacing.xSmall) {
                            Text(group.title.uppercased())
                                .font(StoatTypography.section)
                                .foregroundStyle(.secondary)
                            ForEach(group.items) { item in
                                memberListRow(item)
                                    .onAppear { viewModel.loadImageResource(for: item.avatar, kind: .userAvatar) }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var emptyMemberMessage: String {
        guard case let .serverMembers(serverID, _) = context else {
            return "Member data is not present in the current snapshot."
        }
        if viewModel.isMemberHydrationLoading(serverID: serverID) {
            return "Loading selected-server members."
        }
        if let error = viewModel.memberHydrationErrorsByServerID[serverID] {
            return "Refresh failed: \(error)"
        }
        if viewModel.canRefreshSelectedServerMembers {
            return "Ready has no members yet. Use refresh or wait for selected-server hydration."
        }
        return "Member data is not present in the current snapshot."
    }

    @ViewBuilder private func dmParticipants(_ channel: Channel) -> some View {
        let items = viewModel.directMessageParticipantItems(for: channel)
        if items.isEmpty {
            EmptyStateView(title: "No participants", message: "Participant data is not present in the current snapshot.", systemImage: "person")
                .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: StoatSpacing.xSmall) {
                    ForEach(items) { item in
                        memberListRow(item)
                            .onAppear { viewModel.loadImageResource(for: item.avatar, kind: .userAvatar) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func memberListRow(_ item: MemberListItem) -> some View {
        StoatFeatureLayoutDiagnostics.body("MemberRowView", detail: "id=\(item.userID.rawValue)")
        return Button {
            viewModel.showUserProfile(item.userID, source: item.member == nil ? .directMessageParticipant : .memberRow, serverID: item.member?.id.serverID)
        } label: {
            HStack(spacing: StoatSpacing.medium) {
                AvatarView(title: item.displayName, size: StoatSize.compactAvatar, isOnline: item.isOnline, presence: item.user?.status?.presence, imageData: viewModel.imageData(for: item.avatar, kind: .userAvatar))
                VStack(alignment: .leading, spacing: StoatSpacing.xxSmall) {
                    HStack(spacing: StoatSpacing.xSmall) {
                        Text(item.displayName)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(roleForeground(item.roleColor))
                            .lineLimit(1)
                        if item.isBot {
                            Text("BOT")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 4)
                                .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: StoatRadius.control, style: .continuous))
                        }
                    }
                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, StoatSpacing.xxSmall)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                Task { await viewModel.openDirectMessage(with: item.userID, source: .memberRow) }
            } label: {
                Label("Message", systemImage: "bubble.left.and.bubble.right")
            }
            if let member = item.member {
                Divider()
                Button {
                    viewModel.openMemberDetail(member)
                    viewModel.openServerOverview()
                } label: {
                    Label("Member Details", systemImage: "person.text.rectangle")
                }
                Divider()
                Button {
                    viewModel.requestMemberAction(.timeout, for: member)
                } label: {
                    Label("Timeout", systemImage: "clock.badge.exclamationmark")
                }
                .disabled(viewModel.memberActionDisabledReason(for: member, action: .timeout) != nil)
                Button {
                    viewModel.requestMemberAction(.clearTimeout, for: member)
                } label: {
                    Label("Clear Timeout", systemImage: "clock.arrow.circlepath")
                }
                .disabled(viewModel.memberActionDisabledReason(for: member, action: .clearTimeout) != nil)
                Button(role: .destructive) {
                    viewModel.requestMemberAction(.kick, for: member)
                } label: {
                    Label("Kick", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .disabled(viewModel.memberActionDisabledReason(for: member, action: .kick) != nil)
                Button(role: .destructive) {
                    viewModel.requestMemberAction(.ban, for: member)
                } label: {
                    Label("Ban", systemImage: "hand.raised.fill")
                }
                .disabled(viewModel.memberActionDisabledReason(for: member, action: .ban) != nil)
            }
        }
    }

    private func roleForeground(_ color: ResolvedRoleColor?) -> Color {
        guard colorSchemeContrast != .increased, let color else { return .primary }
        return Color(red: color.red, green: color.green, blue: color.blue)
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
            VStack(alignment: .leading, spacing: StoatSpacing.large) {
                HStack {
                    Text("Home")
                        .font(.title.weight(.semibold))
                    Spacer()
                    Button {
                        Task { await viewModel.refreshRelationshipsAndDirectMessages() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(GlassButtonStyle())
                    .disabled(!canRefreshRelationships || viewModel.isRelationshipRefreshInProgress)
                }

                VStack(alignment: .leading, spacing: StoatSpacing.medium) {
                    currentUserPanel
                    quickActions
                }

                HStack(alignment: .top, spacing: StoatSpacing.large) {
                    recentDMsPanel
                    friendRequestsPanel
                }
            }
            .padding(StoatSpacing.xxLarge)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var currentUserPanel: some View {
        GlassPanel {
            HStack(spacing: StoatSpacing.medium) {
                if let user = viewModel.currentUserID.flatMap({ viewModel.snapshot.usersByID[$0] }) ?? viewModel.currentUser {
                    Button {
                        viewModel.showUserProfile(user.id, source: .friendRow)
                    } label: {
                        MemberRow(user: user, subtitle: user.status?.text ?? user.status?.presence?.displayName, imageData: viewModel.imageData(for: user.avatar, kind: .userAvatar))
                    }
                    .buttonStyle(.plain)
                    .onAppear { viewModel.loadImageResource(for: user.avatar, kind: .userAvatar) }
                } else {
                    EmptyStateView(title: "Signed out", message: "Set up a session before connecting.", systemImage: "person.crop.circle.badge.exclamationmark")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
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
                let items = viewModel.directMessageItems
                if !items.contains(where: { $0.channel.kind == .savedMessages }) {
                    SavedNotesEntryButton(viewModel: viewModel)
                }
                if items.isEmpty {
                    EmptyStateView(title: "No DMs", message: viewModel.canRefreshDMs ? "Existing direct messages will appear after Ready or refresh." : "Connect before refreshing direct messages.", systemImage: "bubble.left.and.bubble.right")
                    Button {
                        Task { await viewModel.refreshDMs(source: .home) }
                    } label: {
                        Label("Refresh DMs", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(GlassButtonStyle())
                    .disabled(!viewModel.canRefreshDMs || viewModel.isRelationshipRefreshInProgress)
                } else {
                    ForEach(items.prefix(5)) { item in
                        DirectMessageItemButton(viewModel: viewModel, item: item)
                    }
                }
                if let status = viewModel.relationshipActionStatus {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .frame(maxWidth: 360, alignment: .topLeading)
    }

    private var friendRequestsPanel: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: StoatSpacing.medium) {
                Text("Friends").font(.headline)
                LabeledContent("Online", value: "\(viewModel.allFriendItems.filter { $0.relationshipStatus == .friend && $0.user.online }.count)")
                LabeledContent("Requests", value: "\(viewModel.incomingFriendRequestCount)")
                Button {
                    viewModel.openFriends(tab: viewModel.incomingFriendRequestCount > 0 ? .pending : .online)
                } label: {
                    Label("Open Friends", systemImage: "person.2")
                }
                .buttonStyle(GlassButtonStyle())
            }
        }
        .frame(maxWidth: 280, alignment: .topLeading)
    }

    private var quickActions: some View {
        HStack(spacing: StoatSpacing.medium) {
            Button("Friends") { viewModel.openFriends(tab: .online) }
            Button("Add Friend") { viewModel.openFriends(tab: .addFriend) }
            Button("Discover") { viewModel.selectDiscover() }
            Button("Account & Settings") { viewModel.showAccountSessions() }
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
            "Ready to connect"
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
            "A credential exists for this environment. Liquid Bagel will connect automatically on launch and you can retry here if needed."
        case .readyToConnect, .validatedReady:
            "Use retry if the live connection is not already ready."
        case .connected:
            viewModel.snapshot.serversByID.isEmpty ? "Ready arrived, but no servers are available in the live snapshot." : "Live data is ready."
        case .connecting, .loadingCredential, .validatingCredential:
            "Liquid Bagel is connecting to live Stoat."
        case .invalidSession, .validationFailed, .connectionFailed, .keychainFailed, .failed:
            viewModel.sessionCoordinator?.lastErrorMessage ?? "Open Account & Connection to repair the session."
        case .mock:
            "Preview data is available only for development."
        }
    }

    private var primaryActionTitle: String {
        viewModel.sessionCoordinator?.hasSavedCredential == true ? "Retry Connection" : "Set Up Session"
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
                    ForEach(filterTabs, id: \.self) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 340)
                Button {
                    viewModel.openFriends(tab: .addFriend)
                } label: {
                    Label("Add Friend", systemImage: "person.badge.plus")
                }
                .buttonStyle(GlassButtonStyle())
                .accessibilityLabel("Add Friend")
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

    private var filterTabs: [FriendsTab] {
        FriendsTab.allCases.filter { $0 != .addFriend }
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
            viewModel.selectDirectMessageItem(item)
        } label: {
            HStack(spacing: StoatSpacing.medium) {
                AvatarView(title: item.displayName, size: StoatSize.compactAvatar, isOnline: item.avatarUser?.online == true && item.channel.kind == .directMessage, presence: item.channel.kind == .directMessage ? item.avatarUser?.status?.presence : nil, imageData: avatarData)
                VStack(alignment: .leading, spacing: StoatSpacing.xxSmall) {
                    Text(item.displayName)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if item.isMuted {
                    Image(systemName: "bell.slash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("Muted")
                        .accessibilityLabel("Muted")
                }
                if item.mentionCount > 0 {
                    MentionBadge(count: item.mentionCount)
                } else if item.unreadCount > 0 {
                    Circle().fill(Color.secondary).frame(width: 7, height: 7)
                }
            }
            .padding(StoatSpacing.small)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(item.isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(item.isMuted ? 0.025 : 0.04), in: RoundedRectangle(cornerRadius: StoatRadius.row, style: .continuous))
            .opacity(item.isMuted ? 0.72 : 1)
        }
        .buttonStyle(.plain)
        .onAppear {
            if item.channel.kind == .group {
                viewModel.loadImageResource(for: item.groupIcon, kind: .serverIcon)
            } else if let user = item.avatarUser {
                viewModel.loadImageResource(for: user.avatar, kind: .userAvatar)
            }
        }
    }

    private var avatarData: Data? {
        if item.channel.kind == .group {
            return viewModel.imageData(for: item.groupIcon, kind: .serverIcon)
        }
        return item.avatarUser.flatMap { viewModel.imageData(for: $0.avatar, kind: .userAvatar) }
    }

    private var subtitle: String {
        switch item.channel.kind {
        case .savedMessages:
            return item.lastMessagePreview ?? "Private notes"
        case .group:
            let members = item.groupMemberCount == 1 ? "1 member" : "\(item.groupMemberCount) members"
            if let preview = item.lastMessagePreview {
                return "\(members) · \(preview)"
            }
            return members
        default:
            return item.lastMessagePreview ?? item.avatarUser?.status?.text ?? "No loaded messages"
        }
    }
}

private struct SavedNotesEntryButton: View {
    @Bindable var viewModel: MainShellViewModel

    var body: some View {
        Button {
            Task { await viewModel.openSavedNotes() }
        } label: {
            HStack(spacing: StoatSpacing.medium) {
                AvatarView(title: "Saved Notes", size: StoatSize.compactAvatar, imageData: nil)
                VStack(alignment: .leading, spacing: StoatSpacing.xxSmall) {
                    Text("Saved Notes")
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if case .opening = viewModel.dmDiagnostics.savedNotesState {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(StoatSpacing.small)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: StoatRadius.row, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Open Saved Notes")
        .accessibilityLabel("Open Saved Notes")
    }

    private var subtitle: String {
        switch viewModel.dmDiagnostics.savedNotesState {
        case .opening:
            return "Opening"
        case let .failed(category):
            return "Unavailable: \(category.rawValue)"
        case .available:
            return "Ready"
        case .unavailable:
            return "Open or refresh"
        }
    }
}

private struct FriendItemRow: View {
    @Bindable var viewModel: MainShellViewModel
    let item: FriendListItem

    var body: some View {
        HStack(spacing: StoatSpacing.medium) {
            Button {
                viewModel.showUserProfile(item.user.id, source: .friendRow)
            } label: {
                MemberRow(
                    user: item.user,
                    subtitle: subtitle,
                    imageData: viewModel.imageData(for: item.user.avatar, kind: .userAvatar)
                )
            }
            .buttonStyle(.plain)

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
            Button("Message") { Task { await viewModel.openDirectMessage(with: item.user.id, source: .friendsRow) } }
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
            Button("Profile") { viewModel.showUserProfile(item.user.id, source: .friendRow) }
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
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Bindable var viewModel: MainShellViewModel
    let user: User

    var body: some View {
        let _ = StoatFeatureLayoutDiagnostics.body("ProfilePopoverView", detail: "id=\(user.id.rawValue)")
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                profileBackground
                AvatarView(title: context.display.displayName, size: 72, isOnline: user.online, presence: user.status?.presence, imageData: viewModel.imageData(for: avatarFile, kind: .userAvatar))
                    .padding(.leading, StoatSpacing.large)
                    .offset(y: 28)
            }
            VStack(alignment: .leading, spacing: StoatSpacing.medium) {
                header
                actionRow
                Picker("Profile section", selection: $viewModel.profileSelectedTab) {
                    ForEach(ProfileCardTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                tabContent
            }
            .padding(.top, 36)
            .padding([.horizontal, .bottom], StoatSpacing.large)
        }
        .frame(width: 390, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: StoatRadius.panel, style: .continuous))
        .onAppear {
            viewModel.loadImageResource(for: avatarFile, kind: .userAvatar)
            if let background = viewModel.userProfilesByID[user.id]?.background {
                viewModel.loadImageResource(for: background, kind: .profileBackground)
            }
        }
        .onChange(of: viewModel.userProfilesByID[user.id]?.background) { _, background in
            viewModel.loadImageResource(for: background, kind: .profileBackground)
        }
    }

    private var context: ProfilePresentationContext {
        viewModel.profilePresentationContext ?? viewModel.profileContext(userID: user.id, serverID: nil, source: .unknown)
    }

    @ViewBuilder private var header: some View {
        VStack(alignment: .leading, spacing: StoatSpacing.xxSmall) {
            HStack(spacing: StoatSpacing.xSmall) {
                Text(context.display.displayName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(displayNameForeground)
                if user.bot != nil {
                    Text("BOT")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 5)
                        .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: StoatRadius.control, style: .continuous))
                }
            }
            Text("@\(user.username)#\(user.discriminator)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let statusText = user.status?.text, !statusText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let presence = user.status?.presence {
                Text(presence.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var actionRow: some View {
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

    @ViewBuilder private var tabContent: some View {
        switch viewModel.profileSelectedTab {
        case .profile:
            profileTab
        case .mutualGroups:
            mutualList(context.mutualGroups, empty: "No shared groups in the current snapshot.")
        case .mutualServers:
            mutualList(context.mutualServers, empty: "No shared servers in the current snapshot.")
        }
    }

    @ViewBuilder private var profileTab: some View {
        VStack(alignment: .leading, spacing: StoatSpacing.medium) {
            if let ownerID = context.botOwnerID {
                Text("Bot owner: \(ownerName(ownerID))")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            if !context.roles.isEmpty {
                roleChips
            }
            if viewModel.profileLoadingUserIDs.contains(user.id) {
                HStack(spacing: StoatSpacing.small) {
                    ProgressView().controlSize(.small)
                    Text("Loading profile")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let content = profileBio {
                MarkdownMessageContent(content)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let error = viewModel.profileErrorsByID[user.id] {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No profile information is available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var roleChips: some View {
        HStack(spacing: StoatSpacing.xSmall) {
            ForEach(context.roles) { role in
                let roleColor = ResolvedRoleColor(rawValue: role.colour, highContrast: colorSchemeContrast == .increased, sourceRoleID: role.id)
                Text(role.name)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, StoatSpacing.small)
                    .padding(.vertical, StoatSpacing.xxSmall)
                    .foregroundStyle(roleForeground(roleColor))
                    .background(roleForeground(roleColor).opacity(0.12), in: RoundedRectangle(cornerRadius: StoatRadius.control, style: .continuous))
            }
        }
    }

    private func mutualList(_ values: [String], empty: String) -> some View {
        VStack(alignment: .leading, spacing: StoatSpacing.small) {
            if values.isEmpty {
                Text(empty)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(values, id: \.self) { value in
                    Text(value)
                        .font(.callout)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var profileActions: some View {
        let status = viewModel.relationshipStatus(for: user)
        switch status {
        case .user:
            Button("Saved Notes") { Task { await viewModel.openSavedNotes(source: .profilePopover) } }
                .buttonStyle(GlassButtonStyle())
            Button("Edit Profile") { viewModel.openProfileEditorFromProfile() }
                .buttonStyle(GlassButtonStyle())
            Button("Account") { viewModel.showAccountSessions() }
                .buttonStyle(GlassButtonStyle())
        case .friend:
            messageProfileButton
            Button("Remove") { viewModel.requestRelationshipAction(.remove, userID: user.id) }
                .buttonStyle(GlassButtonStyle())
        case .incoming:
            messageProfileButton
            Button("Accept") { Task { await viewModel.performRelationshipAction(.accept, userID: user.id) } }
                .buttonStyle(GlassButtonStyle())
            Button("Deny") { viewModel.requestRelationshipAction(.deny, userID: user.id) }
                .buttonStyle(GlassButtonStyle())
        case .outgoing:
            messageProfileButton
            Button("Cancel") { viewModel.requestRelationshipAction(.remove, userID: user.id) }
                .buttonStyle(GlassButtonStyle())
        case .blocked:
            Button("Unblock") { viewModel.requestRelationshipAction(.unblock, userID: user.id) }
                .buttonStyle(GlassButtonStyle())
        case .none:
            messageProfileButton
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

    private var messageProfileButton: some View {
        Button("Message") { Task { await viewModel.openDirectMessage(with: user.id, source: .profilePopover) } }
            .buttonStyle(GlassButtonStyle())
    }

    private var displayName: String {
        context.display.displayName
    }

    private var avatarFile: File? {
        context.display.avatarFile
    }

    @ViewBuilder private var profileBackground: some View {
        if let background = viewModel.userProfilesByID[user.id]?.background,
           let data = viewModel.imageData(for: background, kind: .profileBackground) {
            #if canImport(AppKit)
            if let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 96)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .accessibilityLabel("Profile banner")
            }
            #endif
        } else {
            LinearGradient(colors: [Color.accentColor.opacity(0.22), Color.primary.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .frame(height: 96)
                .frame(maxWidth: .infinity)
        }
    }

    private var profileBio: String? {
        let content = viewModel.userProfilesByID[user.id]?.content?.trimmingCharacters(in: .whitespacesAndNewlines)
        return content?.isEmpty == false ? content : nil
    }

    private var member: ServerMember? {
        guard let serverID = viewModel.selection.serverID else { return nil }
        return viewModel.snapshot.membersByServerAndUserID[ServerMemberKey(serverID: serverID, userID: user.id)]
    }

    private func roleForeground(_ color: ResolvedRoleColor?) -> Color {
        guard colorSchemeContrast != .increased, let color else { return .secondary }
        return Color(red: color.red, green: color.green, blue: color.blue)
    }

    private var displayNameForeground: Color {
        guard colorSchemeContrast != .increased,
              let color = context.display.roleColor
        else { return .primary }
        return Color(red: color.red, green: color.green, blue: color.blue)
    }

    private func ownerName(_ ownerID: UserID) -> String {
        let owner = viewModel.snapshot.usersByID[ownerID]
        return UserDisplayResolver.displayName(user: owner, fallbackID: ownerID)
    }
}

public struct DiscoverView: View {
    @Bindable private var viewModel: MainShellViewModel

    public init(viewModel: MainShellViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StoatSpacing.xLarge) {
                Text("Discover")
                    .font(.largeTitle.weight(.semibold))
                GlassPanel {
                    VStack(alignment: .leading, spacing: StoatSpacing.large) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: StoatSpacing.xSmall) {
                                Text("Web-backed Discover")
                                    .font(.title3.weight(.semibold))
                                Text("Native community listings are deferred until a first-party Discover API is verified.")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                viewModel.openDiscoverInBrowser()
                            } label: {
                                Label("Open Browser", systemImage: "safari")
                            }
                            .buttonStyle(GlassButtonStyle())
                            .accessibilityLabel("Open Discover in browser")
                        }
                        HStack(spacing: StoatSpacing.small) {
                            Button {
                                viewModel.openJoinInvite()
                            } label: {
                                Label("Join Invite", systemImage: "link")
                            }
                            Button {
                                viewModel.openCreateServer()
                            } label: {
                                Label("Create Server", systemImage: "plus.circle")
                            }
                            .buttonStyle(GlassButtonStyle())
                        }
                        .buttonStyle(GlassButtonStyle())
                    }
                }
                GlassPanel {
                    VStack(alignment: .leading, spacing: StoatSpacing.medium) {
                        Text("Invite")
                            .font(.title3.weight(.semibold))
                        HStack {
                            TextField("Paste invite code or link", text: $viewModel.inviteInput)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    viewModel.openJoinInvite(prefill: viewModel.inviteInput)
                                    Task { await viewModel.previewInviteFromInput() }
                                }
                                .accessibilityLabel("Invite code or link")
                            Button {
                                viewModel.openJoinInvite(prefill: viewModel.inviteInput)
                                Task { await viewModel.previewInviteFromInput() }
                            } label: {
                                Label("Preview", systemImage: "eye")
                            }
                            .buttonStyle(GlassButtonStyle())
                        }
                    }
                }
                Spacer(minLength: StoatSpacing.xxLarge)
            }
            .padding(StoatSpacing.xxLarge)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

public struct JoinInviteView: View {
    @Bindable private var viewModel: MainShellViewModel

    public init(viewModel: MainShellViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: StoatSpacing.large) {
            HStack {
                Text("Join Invite")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Close") { viewModel.isJoinInvitePresented = false }
                    .keyboardShortcut(.cancelAction)
            }
            HStack {
                TextField("Invite code or link", text: $viewModel.inviteInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await viewModel.previewInviteFromInput() } }
                    .accessibilityLabel("Invite code or link")
                    .accessibilityHint("Paste a Stoat invite code or supported invite URL")
                Button {
                    Task { await viewModel.previewInviteFromInput() }
                } label: {
                    Label("Preview", systemImage: "eye")
                }
                .buttonStyle(GlassButtonStyle())
            }
            inviteState
            Spacer()
        }
        .padding(StoatSpacing.large)
        .frame(width: 520, height: 360, alignment: .topLeading)
    }

    @ViewBuilder private var inviteState: some View {
        switch viewModel.invitePreviewState {
        case .idle, .parsing:
            EmptyStateView(title: "No invite preview", message: "Preview runs only when you press Preview.", systemImage: "link")
        case let .loading(code):
            ProgressView("Loading \(InviteCodeParser.sanitizeDisplay(code))")
        case let .failed(_, message):
            EmptyStateView(title: "Invite unavailable", message: message, systemImage: "exclamationmark.triangle")
        case let .loaded(preview):
            InvitePreviewCard(viewModel: viewModel, preview: preview)
        }
    }
}

private struct InvitePreviewCard: View {
    @Bindable var viewModel: MainShellViewModel
    let preview: InvitePreview

    var body: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: StoatSpacing.medium) {
                HStack(spacing: StoatSpacing.medium) {
                    ServerIconView(name: preview.serverName ?? preview.channelName, imageData: viewModel.imageData(for: preview.serverIcon, kind: .serverIcon))
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: StoatSpacing.xSmall) {
                        Text(preview.serverName ?? preview.channelName)
                            .font(.headline)
                        Text(channelLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                if let description = preview.channelDescription, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                HStack {
                    if let memberCount = preview.memberCount {
                        Label("\(memberCount) members", systemImage: "person.2")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        viewModel.requestJoinLoadedInvite()
                    } label: {
                        Label(preview.isAlreadyJoined ? "Open" : "Join", systemImage: preview.isAlreadyJoined ? "arrow.right.circle" : "plus.circle")
                    }
                    .buttonStyle(GlassButtonStyle())
                    .accessibilityLabel(preview.isAlreadyJoined ? "Open joined server" : "Join server")
                }
            }
        }
        .onAppear {
            viewModel.loadImageResource(for: preview.serverIcon, kind: .serverIcon)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Invite preview for \(preview.serverName ?? preview.channelName)")
    }

    private var channelLine: String {
        if preview.kind == .server {
            return "# \(preview.channelName) · invited by \(preview.inviterName)"
        }
        return "Group · invited by \(preview.inviterName)"
    }
}

public struct CreateServerView: View {
    @Bindable private var viewModel: MainShellViewModel

    public init(viewModel: MainShellViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: StoatSpacing.large) {
            HStack {
                Text("Create Server")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Close") { viewModel.isCreateServerPresented = false }
                    .keyboardShortcut(.cancelAction)
            }
            TextField("Server name", text: $viewModel.serverCreateName)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Server name")
            TextField("Description", text: $viewModel.serverCreateDescription)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Server description")
            Toggle("Age-restricted", isOn: $viewModel.serverCreateIsNSFW)
                .accessibilityLabel("Age-restricted server")
            if case let .failed(message) = viewModel.serverCreateState {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button {
                    Task { await viewModel.createServerFromDraft() }
                } label: {
                    Label("Create", systemImage: "plus.circle")
                }
                .buttonStyle(GlassButtonStyle())
                .disabled(isCreating)
            }
        }
        .padding(StoatSpacing.large)
        .frame(width: 460, height: 300, alignment: .topLeading)
    }

    private var isCreating: Bool {
        if case .creating = viewModel.serverCreateState { return true }
        return false
    }
}

public struct InviteManagementView: View {
    @Bindable private var viewModel: MainShellViewModel

    public init(viewModel: MainShellViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: StoatSpacing.large) {
            HStack {
                Text("Server Invites")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Close") { viewModel.isInviteManagementPresented = false }
                    .keyboardShortcut(.cancelAction)
            }
            HStack {
                Button {
                    Task { await viewModel.createInviteForSelectedChannel() }
                } label: {
                    Label("Create Invite", systemImage: "link.badge.plus")
                }
                Button {
                    Task { await viewModel.refreshServerInvites() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(GlassButtonStyle())
            inviteList
            Spacer()
        }
        .padding(StoatSpacing.large)
        .frame(width: 560, height: 420, alignment: .topLeading)
    }

    @ViewBuilder private var inviteList: some View {
        switch viewModel.inviteManagementState {
        case .idle:
            EmptyStateView(title: "No invite list", message: "Refresh runs only when requested.", systemImage: "link")
        case .loading:
            ProgressView("Loading invites")
        case let .failed(message):
            EmptyStateView(title: "Invites unavailable", message: message, systemImage: "exclamationmark.triangle")
        case let .loaded(invites):
            if invites.isEmpty {
                EmptyStateView(title: "No invites", message: "Create an invite for the selected channel.", systemImage: "link")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: StoatSpacing.small) {
                        ForEach(invites) { invite in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(invite.id.rawValue)
                                        .font(.body.monospaced())
                                    Text(invite.channelID.rawValue)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    Task { await viewModel.copyInvite(invite) }
                                } label: {
                                    Label("Copy", systemImage: "doc.on.doc")
                                }
                                Button(role: .destructive) {
                                    viewModel.requestDeleteInvite(invite)
                                } label: {
                                    Label("Revoke", systemImage: "trash")
                                }
                            }
                            .padding(StoatSpacing.small)
                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: StoatRadius.small, style: .continuous))
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Invite \(invite.id.rawValue)")
                        }
                    }
                }
            }
        }
    }
}

public struct ServerOverviewView: View {
    @Bindable private var viewModel: MainShellViewModel
    @State private var newCategoryTitle = ""
    @State private var roleDeleteConfirmation = ""

    public init(viewModel: MainShellViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StoatSpacing.large) {
                HStack {
                    Text("Server Settings")
                        .font(.title2.weight(.semibold))
                    Spacer()
                    Button("Close") { viewModel.isServerOverviewPresented = false }
                }

                switch viewModel.serverSettingsState {
                case .idle:
                    EmptyStateView(title: "No server selected", message: "Select a server to review settings.", systemImage: "server.rack")
                case .loading:
                    ProgressView("Loading server details")
                case let .failed(message):
                    EmptyStateView(title: "Server settings unavailable", message: message, systemImage: "exclamationmark.triangle")
                case let .loaded(details):
                    settings(details)
                }
            }
            .padding(StoatSpacing.xLarge)
        }
        .frame(width: 680)
        .frame(minHeight: 620)
        .onAppear {
            if let details = viewModel.serverSettingsDetails() {
                viewModel.serverSettingsState = .loaded(details)
                viewModel.serverSettingsForm = viewModel.serverSettingsForm ?? ServerSettingsForm(server: details.server)
                viewModel.categoryEditorForm = viewModel.categoryEditorForm ?? CategoryEditorForm(server: details.server)
            }
        }
        .accessibilityLabel("Server settings")
    }

    private func settings(_ details: ServerSettingsDetails) -> some View {
        VStack(alignment: .leading, spacing: StoatSpacing.large) {
            Picker("Section", selection: $viewModel.selectedServerSettingsTab) {
                ForEach(ServerSettingsTab.allCases, id: \.self) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityHint("Choose a server settings section")

            switch viewModel.selectedServerSettingsTab {
            case .overview:
                overview(details)
            case .appearance:
                appearance(details)
            case .categories:
                categories(details)
            case .roles:
                roles(details)
            case .permissions:
                permissions(details)
            case .members:
                members(details)
            case .danger:
                EmptyStateView(title: "Server deletion deferred", message: "Danger Zone is intentionally disabled in Phase 25.", systemImage: "lock.shield")
            }
        }
    }

    private func overview(_ details: ServerSettingsDetails) -> some View {
        VStack(alignment: .leading, spacing: StoatSpacing.large) {
            GlassPanel {
                VStack(alignment: .leading, spacing: StoatSpacing.medium) {
                    HStack(spacing: StoatSpacing.medium) {
                        ServerIconView(name: details.server.name, imageData: viewModel.imageData(for: details.server.icon, kind: .serverIcon))
                        VStack(alignment: .leading, spacing: StoatSpacing.xxSmall) {
                            Text(details.server.name)
                                .font(.title3.weight(.semibold))
                            Text(details.server.description?.isEmpty == false ? details.server.description! : "No description")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    LabeledContent("Channels", value: "\(details.channels.count)")
                    LabeledContent("Members", value: "\(details.members.count)")
                    LabeledContent("Roles", value: "\(details.server.roles.count)")
                    LabeledContent("Categories", value: "\(details.server.categories?.count ?? 0)")
                    LabeledContent("Runtime", value: details.runtimeLine)
                    LabeledContent("Owner", value: details.server.ownerID.rawValue)
                }
            }

            GlassPanel {
                VStack(alignment: .leading, spacing: StoatSpacing.medium) {
                    Text("Overview")
                        .font(.headline)
                    if viewModel.serverSettingsForm != nil {
                        TextField("Server name", text: Binding(
                            get: { viewModel.serverSettingsForm?.name ?? "" },
                            set: { viewModel.serverSettingsForm?.name = $0 }
                        ))
                        TextField("Description", text: Binding(
                            get: { viewModel.serverSettingsForm?.description ?? "" },
                            set: { viewModel.serverSettingsForm?.description = $0 }
                        ))
                    }
                    stateMessage(viewModel.serverSettingsSaveState, loading: "Saving server", success: "Server updated")
                    HStack {
                        Button {
                            viewModel.serverSettingsForm = ServerSettingsForm(server: details.server)
                        } label: {
                            Label("Cancel", systemImage: "xmark")
                        }
                        Spacer()
                        Button {
                            Task { await viewModel.saveServerSettings() }
                        } label: {
                            Label("Save", systemImage: "checkmark")
                        }
                        .buttonStyle(GlassButtonStyle())
                        .disabled(viewModel.serverSettingsForm?.draft(original: details.server) == nil || viewModel.serverSettingsDisabledReason() != nil)
                        .accessibilityHint(viewModel.serverSettingsDisabledReason() ?? "Save server name and description")
                    }
                }
            }
        }
    }

    private func appearance(_ details: ServerSettingsDetails) -> some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: StoatSpacing.medium) {
                Text("Appearance")
                    .font(.headline)
                HStack(spacing: StoatSpacing.large) {
                    ServerIconView(name: details.server.name, imageData: viewModel.serverIconDraft?.data ?? viewModel.imageData(for: details.server.icon, kind: .serverIcon))
                    VStack(alignment: .leading) {
                        Button { viewModel.chooseServerIconDraft() } label: { Label("Choose Icon", systemImage: "photo") }
                        Text(viewModel.serverIconDraft == nil ? "No icon draft selected" : "Icon draft selected; save to upload.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Button { viewModel.chooseServerBannerDraft() } label: { Label("Choose Banner", systemImage: "rectangle") }
                    Text(viewModel.serverBannerDraft == nil ? "No banner draft selected" : "Banner draft selected; save to upload.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                stateMessage(viewModel.serverSettingsSaveState, loading: "Saving appearance", success: "Appearance updated")
                HStack {
                    Button { viewModel.serverIconDraft = nil; viewModel.serverBannerDraft = nil } label: { Label("Clear Drafts", systemImage: "trash") }
                    Spacer()
                    Button { Task { await viewModel.saveServerAppearance() } } label: { Label("Save Appearance", systemImage: "square.and.arrow.up") }
                        .buttonStyle(GlassButtonStyle())
                        .disabled((viewModel.serverIconDraft == nil && viewModel.serverBannerDraft == nil) || viewModel.serverSettingsDisabledReason() != nil)
                        .accessibilityHint("Uploads selected media only after this button is pressed")
                }
            }
        }
    }

    private func categories(_ details: ServerSettingsDetails) -> some View {
        VStack(alignment: .leading, spacing: StoatSpacing.medium) {
            GlassPanel {
                VStack(alignment: .leading, spacing: StoatSpacing.medium) {
                    Text("Categories")
                        .font(.headline)
                    HStack {
                        TextField("New category", text: $newCategoryTitle)
                        Button { viewModel.createCategoryDraft(title: newCategoryTitle); newCategoryTitle = "" } label: { Label("Add", systemImage: "plus") }
                            .disabled(newCategoryTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.channelManagementDisabledReason() != nil)
                    }
                    ForEach(viewModel.categoryEditorForm?.categories ?? []) { category in
                        HStack {
                            TextField("Category title", text: Binding(
                                get: { viewModel.categoryEditorForm?.categories.first(where: { $0.id == category.id })?.title ?? category.title },
                                set: { viewModel.categoryEditorForm?.renameCategory(id: category.id, title: $0) }
                            ))
                            Text("\(category.channels.count)")
                                .foregroundStyle(.secondary)
                            Button(role: .destructive) { viewModel.categoryEditorForm?.deleteCategory(id: category.id) } label: { Image(systemName: "trash") }
                                .accessibilityHint("Deletes this category draft; channels become uncategorized after Apply")
                        }
                    }
                    ForEach(details.channels) { channel in
                        Picker(channel.displayName, selection: Binding(
                            get: { categoryID(containing: channel.id) },
                            set: { viewModel.categoryEditorForm?.move(channelID: channel.id, toCategory: $0) }
                        )) {
                            Text("Uncategorized").tag(String?.none)
                            ForEach(viewModel.categoryEditorForm?.categories ?? []) { category in
                                Text(category.title).tag(Optional(category.id))
                            }
                        }
                    }
                    stateMessage(viewModel.categoryEditorState, loading: "Applying categories", success: "Categories updated")
                    HStack {
                        Spacer()
                        Button { Task { await viewModel.applyCategoryChanges() } } label: { Label("Apply Categories", systemImage: "checkmark") }
                            .buttonStyle(GlassButtonStyle())
                            .disabled(viewModel.channelManagementDisabledReason() != nil)
                    }
                }
            }
        }
    }

    private func roles(_ details: ServerSettingsDetails) -> some View {
        VStack(alignment: .leading, spacing: StoatSpacing.medium) {
            GlassPanel {
                VStack(alignment: .leading, spacing: StoatSpacing.medium) {
                    HStack {
                        Text("Roles")
                            .font(.headline)
                        Spacer()
                        Button { viewModel.openCreateRole() } label: { Label("Create Role", systemImage: "plus") }
                            .disabled(viewModel.roleManagementDisabledReason() != nil)
                    }
                    ForEach(details.server.roles.values.sorted { $0.rank < $1.rank }) { role in
                        HStack {
                            Circle()
                                .fill(roleColor(role.colour))
                                .frame(width: 10, height: 10)
                            VStack(alignment: .leading) {
                                Text(role.name)
                                Text("Rank \(role.rank) · \(permissionSummary(role.permissions.allow))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { viewModel.openEditRole(role) } label: { Image(systemName: "pencil") }
                                .disabled(viewModel.roleManagementDisabledReason() != nil)
                            Button(role: .destructive) { viewModel.requestDeleteRole(role) } label: { Image(systemName: "trash") }
                                .disabled(viewModel.roleManagementDisabledReason() != nil)
                        }
                    }
                    if let pending = viewModel.pendingRoleDeletion {
                        Divider()
                        Text("Type \(pending.name) to delete this role.")
                            .font(.caption)
                            .foregroundStyle(.red)
                        TextField("Role name", text: $roleDeleteConfirmation)
                        HStack {
                            Button("Cancel") { viewModel.pendingRoleDeletion = nil; roleDeleteConfirmation = "" }
                            Spacer()
                            Button("Delete Role", role: .destructive) {
                                Task { await viewModel.confirmDeleteRole(named: roleDeleteConfirmation); roleDeleteConfirmation = "" }
                            }
                            .disabled(roleDeleteConfirmation != pending.name)
                        }
                    }
                    if viewModel.roleEditorForm != nil {
                        Divider()
                        Text(viewModel.roleEditorForm?.roleID == nil ? "Create Role" : "Edit Role")
                            .font(.headline)
                        TextField("Role name", text: Binding(get: { viewModel.roleEditorForm?.name ?? "" }, set: { viewModel.roleEditorForm?.name = $0 }))
                        TextField("Colour", text: Binding(get: { viewModel.roleEditorForm?.colour ?? "" }, set: { viewModel.roleEditorForm?.colour = $0 }))
                        Toggle("Show separately", isOn: Binding(get: { viewModel.roleEditorForm?.hoist ?? false }, set: { viewModel.roleEditorForm?.hoist = $0 }))
                        stateMessage(viewModel.roleEditorState, loading: "Saving role", success: "Role saved")
                        HStack {
                            Button("Cancel") { viewModel.roleEditorForm = nil }
                            Spacer()
                            Button { Task { await viewModel.saveRoleEditor() } } label: { Label("Save Role", systemImage: "checkmark") }
                                .buttonStyle(GlassButtonStyle())
                        }
                    }
                }
            }
        }
    }

    private func permissions(_ details: ServerSettingsDetails) -> some View {
        VStack(alignment: .leading, spacing: StoatSpacing.medium) {
            GlassPanel {
                VStack(alignment: .leading, spacing: StoatSpacing.medium) {
                    HStack {
                        Text("Permission Preview")
                            .font(.headline)
                        Spacer()
                        Button { viewModel.openPermissionEditor(scope: .serverDefault(serverID: details.server.id)) } label: { Label("Edit Defaults", systemImage: "slider.horizontal.3") }
                            .disabled(viewModel.permissionEditingDisabledReason() != nil)
                    }
                    LabeledContent("Effective bits", value: "\(details.permissionPreview.effectivePermissions.rawValue)")
                    LabeledContent("Manage server", value: details.permissionPreview.canManageServer ? "Allowed" : "Denied")
                    LabeledContent("Manage channels", value: details.permissionPreview.canManageChannels ? "Allowed" : "Denied")
                    LabeledContent("Manage roles", value: details.permissionPreview.canManageRoles ? "Allowed" : "Denied")
                    LabeledContent("Assign roles", value: details.permissionPreview.canAssignRoles ? "Allowed" : "Denied")
                    LabeledContent("Upload files", value: details.permissionPreview.canUploadFiles ? "Allowed" : "Denied")
                    if !details.permissionPreview.warnings.isEmpty {
                        Text("Resolution warnings: \(details.permissionPreview.warnings.map(\.rawValue).joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            GlassPanel {
                VStack(alignment: .leading, spacing: StoatSpacing.medium) {
                    Text("Permission Scopes")
                        .font(.headline)
                    Button { viewModel.openPermissionEditor(scope: .serverDefault(serverID: details.server.id)) } label: { Label("Server defaults", systemImage: "server.rack") }
                        .disabled(viewModel.permissionEditingDisabledReason() != nil)
                    ForEach(details.server.roles.values.sorted { $0.rank < $1.rank }) { role in
                        HStack {
                            Text(role.name)
                            Spacer()
                            Button { viewModel.openPermissionEditor(scope: .serverRole(serverID: details.server.id, roleID: role.id)) } label: { Label("Edit", systemImage: "pencil") }
                                .disabled(viewModel.permissionEditingDisabledReason() != nil || !Phase25PermissionResolver.isRoleEditable(role, currentMember: viewModel.selectedServerMember, server: details.server, currentUserID: viewModel.currentUserID))
                        }
                    }
                    ForEach(details.channels.filter { $0.kind == .textChannel }) { channel in
                        HStack {
                            Text(channel.displayName)
                            Spacer()
                            Button { viewModel.openPermissionEditor(scope: .channelDefault(channelID: channel.id)) } label: { Label("Default", systemImage: "number") }
                                .disabled(viewModel.permissionEditingDisabledReason() != nil)
                        }
                    }
                }
            }

            if let draft = viewModel.permissionEditDraft {
                permissionEditor(draft)
            }
        }
    }

    private func permissionEditor(_ draft: PermissionEditDraft) -> some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: StoatSpacing.medium) {
                HStack {
                    Text("Permission Editor")
                        .font(.headline)
                    Spacer()
                    Text(draft.scope.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(Dictionary(grouping: Phase26Permissions.editableKeys, by: \.group).keys.sorted(), id: \.self) { group in
                    Text(group)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(Phase26Permissions.editableKeys.filter { $0.group == group }) { key in
                        HStack {
                            Text(key.title)
                            if key.isDangerous {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                            }
                            Spacer()
                            Picker(key.title, selection: Binding(
                                get: { viewModel.permissionEditDraft?.state(for: key) ?? .inherit },
                                set: { viewModel.setPermissionState($0, for: key) }
                            )) {
                                if draft.allowsInherit {
                                    Text("Inherit").tag(PermissionTriState.inherit)
                                }
                                Text("Allow").tag(PermissionTriState.allow)
                                Text("Deny").tag(PermissionTriState.deny)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: draft.allowsInherit ? 240 : 160)
                        }
                    }
                }
                let diff = draft.diff(keys: Phase26Permissions.editableKeys)
                if viewModel.permissionSaveRequiresConfirmation {
                    Divider()
                    Text("Diff Preview")
                        .font(.headline)
                    ForEach(diff) { row in
                        Text("\(row.key.title): \(row.previous.rawValue) -> \(row.next.rawValue)")
                            .font(.caption)
                            .foregroundStyle(row.key.isDangerous ? .orange : .secondary)
                    }
                }
                stateMessage(viewModel.permissionEditorState, loading: "Saving permissions", success: "Permissions saved")
                HStack {
                    Button("Cancel") {
                        viewModel.permissionEditDraft = nil
                        viewModel.permissionSaveRequiresConfirmation = false
                    }
                    Spacer()
                    if viewModel.permissionSaveRequiresConfirmation {
                        Button(role: .destructive) { Task { await viewModel.confirmSavePermissionEdit() } } label: { Label("Confirm Save", systemImage: "checkmark.shield") }
                            .buttonStyle(GlassButtonStyle())
                    } else {
                        Button { viewModel.requestSavePermissionEdit() } label: { Label("Review Diff", systemImage: "doc.text.magnifyingglass") }
                            .buttonStyle(GlassButtonStyle())
                            .disabled(diff.isEmpty)
                    }
                }
            }
        }
    }

    private func members(_ details: ServerSettingsDetails) -> some View {
        VStack(alignment: .leading, spacing: StoatSpacing.medium) {
            GlassPanel {
                VStack(alignment: .leading, spacing: StoatSpacing.medium) {
                    HStack {
                        Text("Members")
                            .font(.headline)
                        Spacer()
                        Button { Task { await viewModel.refreshBanList() } } label: { Label("Ban List", systemImage: "hand.raised") }
                            .disabled(viewModel.serverManagementCapabilities().isConnectedForLiveActions == false)
                    }
                    TextField("Search members", text: $viewModel.memberSearchText)
                        .textFieldStyle(.roundedBorder)
                    if details.members.isEmpty {
                        Text("Member management is available when member data is present in the current snapshot.")
                            .foregroundStyle(.secondary)
                    }
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: StoatSpacing.small) {
                            ForEach(viewModel.memberManagementItems(for: details)) { item in
                                HStack {
                                    AvatarView(title: item.displayName, size: 32, isOnline: item.user?.online == true, presence: item.user?.status?.presence, imageData: viewModel.imageData(for: item.member.avatar ?? item.user?.avatar, kind: .userAvatar))
                                    VStack(alignment: .leading, spacing: StoatSpacing.xxSmall) {
                                        Text(item.displayName)
                                        Text("\(item.username) · \(item.roles.map(\.name).joined(separator: ", ").isEmpty ? "No roles" : item.roles.map(\.name).joined(separator: ", "))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        if let timeoutSummary = item.timeoutSummary {
                                            Text(timeoutSummary)
                                                .font(.caption)
                                                .foregroundStyle(.orange)
                                        }
                                    }
                                    Spacer()
                                    Button { viewModel.openMemberDetail(item.member) } label: { Label("Details", systemImage: "person.text.rectangle") }
                                }
                                .onAppear {
                                    viewModel.loadImageResource(for: item.member.avatar ?? item.user?.avatar, kind: .userAvatar)
                                }
                            }
                            if viewModel.isDeveloperControlsEnabled {
                                Text("Member list \(viewModel.memberListPerformanceDiagnostics.totalMembers) · image queue \(viewModel.memberListPerformanceDiagnostics.avatarLoadQueueCount)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(minHeight: 160, maxHeight: 420)
                }
            }

            if let member = viewModel.selectedMemberDetail {
                memberDetail(member, details: details)
            }

            banList()
        }
    }

    private func memberDetail(_ member: ServerMember, details: ServerSettingsDetails) -> some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: StoatSpacing.medium) {
                let user = viewModel.snapshot.usersByID[member.id.userID]
                HStack {
                    Text(member.nickname ?? user?.displayName ?? user?.username ?? "Member")
                        .font(.headline)
                    Spacer()
                    Button("Close") { viewModel.closeMemberDetail() }
                }
                Text(user.map { "@\($0.username)#\($0.discriminator)" } ?? "Unknown user")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if viewModel.isDeveloperControlsEnabled {
                    LabeledContent("User ID", value: member.id.userID.rawValue)
                }

                HStack {
                    TextField("Nickname", text: $viewModel.memberNicknameDraft)
                    Button { viewModel.requestMemberAction(.saveNickname, for: member) } label: { Label("Save", systemImage: "checkmark") }
                        .disabled(viewModel.memberActionDisabledReason(for: member, action: .saveNickname) != nil)
                    Button { viewModel.requestMemberAction(.resetNickname, for: member) } label: { Label("Reset", systemImage: "xmark") }
                        .disabled(viewModel.memberActionDisabledReason(for: member, action: .resetNickname) != nil)
                }

                HStack {
                    Button { viewModel.openMemberRoleAssignment(member) } label: { Label("Assign Roles", systemImage: "person.badge.key") }
                        .disabled(viewModel.memberRoleAssignmentDisabledReason(for: member) != nil)
                    Button { viewModel.requestMemberAction(.removeAvatar, for: member) } label: { Label("Remove Avatar", systemImage: "person.crop.circle.badge.xmark") }
                        .disabled(viewModel.memberActionDisabledReason(for: member, action: .removeAvatar) != nil)
                    Button(role: .destructive) { viewModel.requestMemberAction(.kick, for: member) } label: { Label("Kick", systemImage: "rectangle.portrait.and.arrow.right") }
                        .disabled(viewModel.memberActionDisabledReason(for: member, action: .kick) != nil)
                    Button(role: .destructive) { viewModel.requestMemberAction(.ban, for: member) } label: { Label("Ban", systemImage: "hand.raised.fill") }
                        .disabled(viewModel.memberActionDisabledReason(for: member, action: .ban) != nil)
                }

                HStack {
                    Stepper(value: $viewModel.memberTimeoutHours, in: 1...168, step: 1) {
                        Text("Timeout \(Int(viewModel.memberTimeoutHours))h")
                    }
                    Button { viewModel.requestMemberAction(.timeout, for: member) } label: { Label("Apply Timeout", systemImage: "clock.badge.exclamationmark") }
                        .disabled(viewModel.memberActionDisabledReason(for: member, action: .timeout) != nil)
                    Button { viewModel.requestMemberAction(.clearTimeout, for: member) } label: { Label("Clear Timeout", systemImage: "clock.arrow.circlepath") }
                        .disabled(viewModel.memberActionDisabledReason(for: member, action: .clearTimeout) != nil)
                }

                if let draft = viewModel.memberRoleDraft {
                    roleAssignment(draft, details: details)
                }
                if let pending = viewModel.pendingMemberModerationAction {
                    Divider()
                    Text("Confirm \(pending.action.rawValue)")
                        .font(.headline)
                    Text("This action affects \(user?.username ?? UserDisplayResolver.shortenedID(pending.member.id.userID)).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Cancel") { viewModel.pendingMemberModerationAction = nil }
                        Spacer()
                        Button("Confirm", role: .destructive) { Task { await viewModel.confirmPendingMemberAction() } }
                    }
                }
                stateMessage(viewModel.memberActionState, loading: "Applying member action", success: "Member updated")
            }
        }
    }

    private func roleAssignment(_ draft: MemberRoleAssignmentDraft, details: ServerSettingsDetails) -> some View {
        VStack(alignment: .leading, spacing: StoatSpacing.small) {
            Divider()
            Text("Role Assignment")
                .font(.headline)
            ForEach(Phase26MemberSafety.assignableRoles(in: details.server, currentMember: viewModel.selectedServerMember, currentUserID: viewModel.currentUserID)) { role in
                Toggle(role.name, isOn: Binding(
                    get: { viewModel.memberRoleDraft?.selectedRoleIDs.contains(role.id) == true },
                    set: { viewModel.toggleRole(role.id, inMemberRoleDraft: $0) }
                ))
            }
            if viewModel.memberRoleSaveRequiresConfirmation {
                Text("Added: \(draft.addedRoleIDs.compactMap { details.server.roles[$0]?.name }.joined(separator: ", "))")
                    .font(.caption)
                Text("Removed: \(draft.removedRoleIDs.compactMap { details.server.roles[$0]?.name }.joined(separator: ", "))")
                    .font(.caption)
            }
            HStack {
                Button("Cancel") { viewModel.memberRoleDraft = nil }
                Spacer()
                if viewModel.memberRoleSaveRequiresConfirmation {
                    Button(role: .destructive) { Task { await viewModel.confirmSaveMemberRoles() } } label: { Label("Confirm Roles", systemImage: "checkmark.shield") }
                } else {
                    Button { viewModel.requestSaveMemberRoles() } label: { Label("Review Diff", systemImage: "doc.text.magnifyingglass") }
                        .disabled(!draft.hasChanges)
                }
            }
        }
    }

    @ViewBuilder private func banList() -> some View {
        switch viewModel.banListState {
        case .idle:
            EmptyView()
        case .loading:
            ProgressView("Loading bans")
        case let .failed(message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
        case let .loaded(result):
            GlassPanel {
                VStack(alignment: .leading, spacing: StoatSpacing.medium) {
                    Text("Ban List")
                        .font(.headline)
                    if result.bans.isEmpty {
                        Text("No bans returned.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(result.bans) { ban in
                        HStack {
                            Text(result.users.first { $0.id == ban.id.userID }?.username ?? UserDisplayResolver.shortenedID(ban.id.userID))
                            Spacer()
                            Button("Unban") { Task { await viewModel.unban(userID: ban.id.userID) } }
                        }
                    }
                }
            }
        }
    }

    private func categoryID(containing channelID: ChannelID) -> String? {
        viewModel.categoryEditorForm?.categories.first { $0.channels.contains(channelID) }?.id
    }

    private func permissionSummary(_ permissions: Permissions) -> String {
        var labels: [String] = []
        if permissions.contains(.manageServer) { labels.append("Manage Server") }
        if permissions.contains(.manageChannel) { labels.append("Manage Channels") }
        if permissions.contains(.manageRole) { labels.append("Manage Roles") }
        if permissions.contains(.assignRoles) { labels.append("Assign Roles") }
        if permissions.contains(.uploadFiles) { labels.append("Upload Files") }
        return labels.isEmpty ? "No highlighted permissions" : labels.joined(separator: ", ")
    }

    private func roleColor(_ hex: String?) -> Color {
        guard let hex, let color = NSColor.phase25Hex(hex) else { return .secondary }
        return Color(nsColor: color)
    }

    @ViewBuilder private func stateMessage<Value: Hashable & Sendable>(_ state: ManagementActionState<Value>, loading: String, success: String) -> some View {
        switch state {
        case .idle:
            Text("Changes apply only after an explicit save.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .loading:
            ProgressView(loading)
        case let .failed(message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
        case .loaded:
            Text(success)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

public struct CreateChannelView: View {
    @Bindable private var viewModel: MainShellViewModel

    public init(viewModel: MainShellViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: StoatSpacing.large) {
            HStack {
                Text("Create Channel")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Close") { viewModel.isCreateChannelPresented = false }
            }
            TextField("Channel name", text: $viewModel.channelCreateForm.name)
                .accessibilityLabel("Channel name")
            TextField("Description", text: $viewModel.channelCreateForm.description)
                .accessibilityLabel("Channel description")
            Toggle("Age restricted", isOn: $viewModel.channelCreateForm.isNSFW)
                .accessibilityHint("Marks the channel as age restricted")

            if let categories = viewModel.selectedServer?.categories, !categories.isEmpty {
                Picker("Category", selection: $viewModel.channelCreateForm.categoryID) {
                    Text("No category").tag(String?.none)
                    ForEach(categories) { category in
                        Text(category.title).tag(Optional(category.id))
                    }
                }
                .accessibilityHint("Choose an existing category for the new channel")
            }

            stateMessage(viewModel.channelCreateState)

            HStack {
                Spacer()
                Button("Create") {
                    Task { await viewModel.createChannelFromDraft() }
                }
                .buttonStyle(GlassButtonStyle())
                .disabled(viewModel.channelCreateForm.draft() == nil)
                .accessibilityLabel("Create channel")
                .accessibilityHint("Creates the channel only after this button is pressed")
            }
        }
        .padding(StoatSpacing.xLarge)
        .frame(width: 440)
    }

    @ViewBuilder private func stateMessage(_ state: ManagementActionState<Channel>) -> some View {
        switch state {
        case .idle:
            Text("Create runs only when requested.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .loading:
            ProgressView("Creating channel")
        case let .failed(message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
        case .loaded:
            Text("Channel created")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

public struct ChannelSettingsView: View {
    @Bindable private var viewModel: MainShellViewModel

    public init(viewModel: MainShellViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: StoatSpacing.large) {
            HStack {
                Text("Channel Settings")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Close") { viewModel.isChannelSettingsPresented = false }
            }
            if viewModel.channelEditForm != nil {
                TextField("Channel name", text: Binding(
                    get: { viewModel.channelEditForm?.name ?? "" },
                    set: { viewModel.channelEditForm?.name = $0 }
                ))
                .accessibilityLabel("Channel name")
                TextField("Description", text: Binding(
                    get: { viewModel.channelEditForm?.description ?? "" },
                    set: { viewModel.channelEditForm?.description = $0 }
                ))
                .accessibilityLabel("Channel description")
                Toggle("Age restricted", isOn: Binding(
                    get: { viewModel.channelEditForm?.isNSFW ?? false },
                    set: { viewModel.channelEditForm?.isNSFW = $0 }
                ))

                stateMessage(viewModel.channelEditState)

                HStack {
                    Button("Delete Channel", role: .destructive) {
                        viewModel.requestDeleteSelectedChannel()
                    }
                    .buttonStyle(GlassButtonStyle())
                    .accessibilityHint("Requires confirmation before deleting this channel")
                    Spacer()
                    Button("Save") {
                        Task { await viewModel.saveChannelSettings() }
                    }
                    .buttonStyle(GlassButtonStyle())
                    .disabled(saveDisabled)
                    .accessibilityLabel("Save channel settings")
                }
            } else {
                EmptyStateView(title: "No channel selected", message: "Select a text channel before editing.", systemImage: "number")
            }
        }
        .padding(StoatSpacing.xLarge)
        .frame(width: 440)
    }

    private var saveDisabled: Bool {
        guard let form = viewModel.channelEditForm,
              let original = viewModel.snapshot.channelsByID[form.channelID]
        else { return true }
        return form.draft(original: original) == nil
    }

    @ViewBuilder private func stateMessage(_ state: ManagementActionState<Channel>) -> some View {
        switch state {
        case .idle:
            Text("Save runs only when requested.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .loading:
            ProgressView("Saving channel")
        case let .failed(message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
        case .loaded:
            Text("Channel updated")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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
            Text(viewModel.effectiveRuntimeMode == .liveManual && viewModel.effectiveSessionState == .connected ? "Live channel search runs only when you press Search." : "Live search requires a connected live session.")
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
            VStack(spacing: StoatSpacing.medium) {
                ContentUnavailableView("No results", systemImage: query.mode == .pinned ? "pin.slash" : "magnifyingglass", description: Text(query.mode.displayName))
                if query.mode == .loadedOnly, viewModel.effectiveRuntimeMode == .liveManual, viewModel.effectiveSessionState == .connected {
                    Button("Search Channel Remotely") {
                        viewModel.channelSearchQuery.mode = .liveChannel
                        Task { await viewModel.runChannelSearch() }
                    }
                    .buttonStyle(GlassButtonStyle())
                }
            }
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
                        Text(result.authorDisplayName ?? UserDisplayResolver.shortenedID(result.authorID))
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

private extension NSColor {
    static func phase25Hex(_ value: String) -> NSColor? {
        var hex = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") {
            hex.removeFirst()
        }
        guard hex.count == 6, let int = UInt64(hex, radix: 16) else { return nil }
        return NSColor(
            red: CGFloat((int >> 16) & 0xFF) / 255,
            green: CGFloat((int >> 8) & 0xFF) / 255,
            blue: CGFloat(int & 0xFF) / 255,
            alpha: 1
        )
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

@MainActor
private func phase30DMPreviewModel(reduceGlass: Bool = false) -> MainShellViewModel {
    let model = MainShellViewModel(snapshot: MockShellData.snapshot)
    model.reduceGlassIntensity = reduceGlass
    if let item = model.directMessageItems.first {
        model.selectDirectMessageItem(item)
    }
    return model
}

@MainActor
private func phase37PreviewModel(reduceGlass: Bool = false, highContrast: Bool = false) -> MainShellViewModel {
    var snapshot = MockShellData.snapshot
    let serverID: ServerID = "01HX0000000000000000000201"
    let adminRole = Role(id: "phase37-admin-role", name: "Administrators", permissions: PermissionOverride(allow: [.manageServer, .manageRole, .manageMessages]), colour: "#FF5C7A", hoist: true, rank: 90)
    let managerRole = Role(id: "phase37-manager-role", name: "Managers", permissions: PermissionOverride(allow: [.manageServer, .manageChannel]), colour: "#5FA8FF", hoist: true, rank: 70)
    let botRole = Role(id: "phase37-bot-role", name: "Automation", permissions: PermissionOverride(allow: [.sendMessage, .react]), colour: "#49C98A", hoist: true, rank: 40)
    let memberRole = Role(id: "phase37-member-role", name: "Members", permissions: PermissionOverride(allow: [.viewChannel, .readMessageHistory]), colour: "#B38CFF", hoist: false, rank: 10)
    snapshot.serversByID[serverID]?.roles[adminRole.id] = adminRole
    snapshot.serversByID[serverID]?.roles[managerRole.id] = managerRole
    snapshot.serversByID[serverID]?.roles[botRole.id] = botRole
    snapshot.serversByID[serverID]?.roles[memberRole.id] = memberRole

    let adminID: UserID = "phase37-admin-user"
    let botID: UserID = "phase37-bot-user"
    let offlineID: UserID = "phase37-offline-user"
    let unknownRoleID: UserID = "phase37-unknown-role-user"
    snapshot.usersByID[adminID] = User(id: adminID, username: "admin", discriminator: "1001", displayName: "Admin Ada", status: UserStatus(text: "Keeping order", presence: .online), relationship: .friend, online: true)
    snapshot.usersByID[botID] = User(id: botID, username: "bagelbot", discriminator: "2002", displayName: "Bagel Bot", status: UserStatus(text: "Automating triage", presence: .focus), bot: BotInformation(ownerID: MockShellData.currentUserID), relationship: .none, online: true)
    snapshot.usersByID[offlineID] = User(id: offlineID, username: "quietops", discriminator: "3003", displayName: "Quiet Ops", status: UserStatus(text: nil, presence: .invisible), relationship: .friend, online: false)
    snapshot.usersByID[unknownRoleID] = User(id: unknownRoleID, username: "driftcase", discriminator: "4004", displayName: "Role Drift", status: UserStatus(text: "Testing fallback", presence: .idle), relationship: .none, online: true)

    let joinedAt = Date(timeIntervalSince1970: 1_700_000_000)
    snapshot.membersByServerAndUserID[ServerMemberKey(serverID: serverID, userID: adminID)] = ServerMember(id: MemberCompositeKey(serverID: serverID, userID: adminID), joinedAt: joinedAt, nickname: "Ada Admin", roles: [memberRole.id, adminRole.id])
    snapshot.membersByServerAndUserID[ServerMemberKey(serverID: serverID, userID: botID)] = ServerMember(id: MemberCompositeKey(serverID: serverID, userID: botID), joinedAt: joinedAt, roles: [botRole.id])
    snapshot.membersByServerAndUserID[ServerMemberKey(serverID: serverID, userID: offlineID)] = ServerMember(id: MemberCompositeKey(serverID: serverID, userID: offlineID), joinedAt: joinedAt, roles: [memberRole.id])
    snapshot.membersByServerAndUserID[ServerMemberKey(serverID: serverID, userID: unknownRoleID)] = ServerMember(id: MemberCompositeKey(serverID: serverID, userID: unknownRoleID), joinedAt: joinedAt, roles: ["phase37-missing-role"])

    let model = MainShellViewModel(snapshot: snapshot)
    model.reduceGlassIntensity = reduceGlass
    model.selectServer(serverID)
    model.userProfilesByID[botID] = UserProfile(content: "### About\nAutomation helper for **member hydration** and _safe media_ checks.", background: File(id: "phase37-profile-background", tag: "backgrounds", filename: "banner.png", metadata: .image(width: 1200, height: 360, thumbhash: nil, animated: false), contentType: "image/png", size: 128_000, userID: botID))
    model.showUserProfile(botID, source: .memberRow, serverID: serverID)
    return model
}

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
#Preview("Phase 29 Timeline Without Diagnostics") {
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
#Preview("Phase 29 DM Loaded") {
    let model = MainShellViewModel(snapshot: MockShellData.snapshot)
    model.selectDirectMessages()
    return MainShellView(viewModel: model)
        .frame(width: 1180, height: 760)
}

@available(macOS 15.0, *)
#Preview("Phase 29 Developer Diagnostics") {
    let model = MainShellViewModel(snapshot: MockShellData.snapshot)
    model.selectServer(model.servers[0].id)
    model.showCredentialSetup()
    return CredentialSetupView(viewModel: model)
}

@available(macOS 15.0, *)
#Preview("Phase 30 DM Selected Loaded") {
    let model = MainShellViewModel(snapshot: MockShellData.snapshot)
    if let item = model.directMessageItems.first {
        model.selectDirectMessageItem(item)
    }
    return MainShellView(viewModel: model)
        .frame(width: 1180, height: 760)
}

@available(macOS 15.0, *)
#Preview("Phase 30 DM Participants Sidebar") {
    let model = MainShellViewModel(snapshot: MockShellData.snapshot)
    if let item = model.directMessageItems.first {
        model.selectDirectMessageItem(item)
    }
    return MemberPanelView(viewModel: model)
        .frame(width: 300, height: 620)
}

@available(macOS 15.0, *)
#Preview("Phase 30 DM Trace Developer Panel") {
    let model = MainShellViewModel(snapshot: MockShellData.snapshot)
    if let item = model.directMessageItems.first {
        model.selectDirectMessageItem(item)
    }
    model.showCredentialSetup()
    return CredentialSetupView(viewModel: model)
}

@available(macOS 15.0, *)
#Preview("Phase 30 Parity Matrix Summary") {
    let model = MainShellViewModel(snapshot: MockShellData.snapshot)
    model.showCredentialSetup()
    return CredentialSetupView(viewModel: model)
}

@available(macOS 15.0, *)
#Preview("Phase 30 High Contrast DM") {
    MainShellView(viewModel: phase30DMPreviewModel())
        .preferredColorScheme(.dark)
        .frame(width: 1180, height: 760)
}

@available(macOS 15.0, *)
#Preview("Phase 30 Reduce Transparency DM") {
    MainShellView(viewModel: phase30DMPreviewModel(reduceGlass: true))
        .frame(width: 1180, height: 760)
}

@available(macOS 15.0, *)
#Preview("Phase 34 Compact Home") {
    MainShellView(viewModel: MainShellViewModel(snapshot: MockShellData.snapshot))
        .frame(width: 1180, height: 760)
}

@available(macOS 15.0, *)
#Preview("Phase 34 Server Members Role Colors") {
    let model = MainShellViewModel(snapshot: MockShellData.snapshot)
    model.selectServer(model.servers[0].id)
    return MemberPanelView(viewModel: model, context: model.rightSidebarContext)
        .frame(width: 300, height: 620)
}

@available(macOS 15.0, *)
#Preview("Phase 37 Role Ordered Member List") {
    let model = phase37PreviewModel()
    return MemberPanelView(viewModel: model, context: model.rightSidebarContext)
        .frame(width: 320, height: 680)
}

@available(macOS 15.0, *)
#Preview("Phase 37 Role Colored Message Authors") {
    let model = phase37PreviewModel()
    return MessageTimelineView(viewModel: model)
        .frame(width: 760, height: 560)
}

@available(macOS 15.0, *)
#Preview("Phase 37 Native Profile Popover") {
    let model = phase37PreviewModel()
    return UserProfileCardView(viewModel: model, user: model.profilePresentationUser ?? model.snapshot.usersByID["phase37-bot-user"]!)
        .frame(width: 420)
        .preferredColorScheme(.dark)
}

@available(macOS 15.0, *)
#Preview("Phase 37 Mutual Profile Tabs") {
    let model = phase37PreviewModel(reduceGlass: true)
    model.profileSelectedTab = .mutualServers
    return UserProfileCardView(viewModel: model, user: model.profilePresentationUser ?? model.snapshot.usersByID["phase37-bot-user"]!)
        .frame(width: 420)
}

@available(macOS 15.0, *)
#Preview("Phase 37 High Contrast Role Colors") {
    let model = phase37PreviewModel(highContrast: true)
    MainShellView(viewModel: model)
        .frame(width: 1180, height: 760)
}

@available(macOS 15.0, *)
#Preview("Phase 37 Media Safe Mode Placeholder") {
    let model = phase37PreviewModel()
    model.freezePerformanceDiagnostics.mediaSafeModeEnabled = true
    model.lastImageResourceAction = "Media safe mode: showing visible tap-to-load placeholders."
    return CredentialSetupView(viewModel: model)
        .frame(width: 620, height: 620)
}

@available(macOS 15.0, *)
#Preview("Phase 37 Notification Build Readiness") {
    let model = phase37PreviewModel()
    model.showCredentialSetup()
    model.selectedSettingsTab = .notifications
    return CredentialSetupView(viewModel: model)
        .frame(width: 620, height: 620)
}

@available(macOS 15.0, *)
#Preview("Phase 34 Home No Member Sidebar") {
    let model = MainShellViewModel(snapshot: MockShellData.snapshot)
    model.selection.isMemberPanelVisible = true
    return MainShellView(viewModel: model)
        .frame(width: 980, height: 640)
}

@available(macOS 15.0, *)
#Preview("Phase 29 Compact Composer") {
    let model = MainShellViewModel(snapshot: MockShellData.snapshot)
    model.selectServer(model.servers[0].id)
    return ChatPlaceholderView(viewModel: model)
        .frame(width: 760, height: 620)
}

@available(macOS 15.0, *)
#Preview("Phase 29 Capped Composer") {
    let model = MainShellViewModel(snapshot: MockShellData.snapshot)
    model.selectServer(model.servers[0].id)
    if let channelID = model.selectedConversationChannelID {
        model.updateDraft(String(repeating: "Long composer preview line. ", count: 32), for: channelID)
    }
    return ChatPlaceholderView(viewModel: model)
        .frame(width: 760, height: 620)
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
#Preview("Live - Ready To Connect") {
    MainShellView(viewModel: MainShellViewModel(snapshot: RealtimeSnapshot(), runtimeMode: .liveManual, sessionState: .readyToConnect, currentUser: nil))
        .frame(width: 1180, height: 760)
}

@available(macOS 15.0, *)
#Preview("Live - Connecting") {
    MainShellView(viewModel: MainShellViewModel(snapshot: RealtimeSnapshot(), connectionState: .authenticating, runtimeMode: .liveManual, sessionState: .connecting, currentUser: nil))
        .frame(width: 1180, height: 760)
}

@available(macOS 15.0, *)
#Preview("Live - Ready Snapshot") {
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
#Preview("Live - No Servers") {
    MainShellView(viewModel: MainShellViewModel(snapshot: RealtimeSnapshot(), connectionState: .ready, runtimeMode: .liveManual, sessionState: .connected, currentUser: nil))
        .frame(width: 1180, height: 760)
}

@available(macOS 15.0, *)
#Preview("Live - Reconnecting") {
    MainShellView(viewModel: MainShellViewModel(snapshot: MockShellData.snapshot, connectionState: .reconnecting(attempt: 2, nextDelay: .seconds(4)), runtimeMode: .liveManual, sessionState: .connecting, currentUser: MockShellData.snapshot.usersByID[MockShellData.currentUserID]))
        .frame(width: 1180, height: 760)
}
