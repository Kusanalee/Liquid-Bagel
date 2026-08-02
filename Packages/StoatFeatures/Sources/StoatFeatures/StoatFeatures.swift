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
    case appearance
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
        // Optimistic messages have no server-issued ULID timestamp yet. Treat them as having
        // been created during this grouping pass, rather than at distant future, so their
        // position and group header do not jump when confirmation supplies the real ULID.
        let optimisticSendDate = Date()
        let sorted = messages.sorted {
            timestamp(for: $0, optimisticSendDate: optimisticSendDate)
                < timestamp(for: $1, optimisticSendDate: optimisticSendDate)
        }
        var groups: [TimelineMessageGroup] = []

        for timelineMessage in sorted {
            let message = timelineMessage.message
            let messageDate = timestamp(for: timelineMessage, optimisticSendDate: optimisticSendDate)
            guard var last = groups.last,
                  let previous = last.messages.last
            else {
                groups.append(makeGroup(timelineMessage, startsAt: messageDate))
                continue
            }

            let previousMessage = previous.message
            let previousDate = timestamp(for: previous, optimisticSendDate: optimisticSendDate)
            let canGroup = previousMessage.authorID == message.authorID
                && previousMessage.channelID == message.channelID
                && previousMessage.system == nil
                && message.system == nil
                && previousMessage.replies?.isEmpty != false
                && message.replies?.isEmpty != false
                // Optimistic local sends must use the same grouping rule as their confirmed
                // replacement. Otherwise a pending row renders its own avatar and loses it as
                // soon as the server confirmation joins the preceding local-message group.
                && isGroupableStatus(previous.status)
                && isGroupableStatus(timelineMessage.status)
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

    private static func isGroupableStatus(_ status: TimelineMessageStatus) -> Bool {
        switch status {
        case .pending, .confirmed:
            true
        case .failed, .retrying, .deleting:
            false
        }
    }

    private static func timestamp(for timelineMessage: TimelineMessage, optimisticSendDate: Date) -> Date {
        timelineMessage.message.createdAt
            ?? (timelineMessage.status == .pending ? optimisticSendDate : Date.distantFuture)
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

private struct ModerationPermissionResolutionCacheKey: Hashable {
    var prewarmKey: Phase46ModerationPrewarmKey
    var runtimeMode: AppRuntimeMode
    var sessionState: AppSessionState
    var generation: Int
}

private struct ModerationBaseContextCacheKey: Hashable {
    var prewarmKey: Phase46ModerationPrewarmKey
    var routeAvailability: ModerationRouteAvailability
    var isConnectedForLiveActions: Bool
    var generation: Int
}

private struct ModerationMenuStateCacheKey: Hashable {
    var prewarmKey: Phase46ModerationPrewarmKey
    var targetUserID: UserID
    var targetServerID: ServerID?
    var allowNonMemberBan: Bool
    var timeoutBucket: String
}

@MainActor
@Observable
public final class MainShellViewModel {
    public var selection: ShellSelection {
        didSet {
            guard oldValue.serverID != selection.serverID
                || oldValue.channelID != selection.channelID
                || oldValue.dmChannelID != selection.dmChannelID
                || oldValue.space != selection.space
            else { return }
            let oldConversationID = ActiveConversation.resolve(selection: oldValue, snapshot: snapshot).channelID
            let newConversationID = ActiveConversation.resolve(selection: selection, snapshot: snapshot).channelID
            if oldConversationID != newConversationID {
                resetPhase60TimelineWork(previousChannelID: oldConversationID)
            }
            phase46ModerationVersions.bumpSelectionVersions()
            invalidateCapabilityCache()
            phase51SelectionRevision &+= 1
            schedulePhase51ShellPresentationRefresh(reason: "selection")
            if effectiveRuntimeMode == .liveManual, effectiveSessionState == .connected {
                warmIdentityImagesForCurrentSelection()
            }
            if isServerOverviewPresented {
                schedulePhase51ServerSettingsPreparation()
            }
        }
    }
    public private(set) var snapshot: RealtimeSnapshot {
        didSet {
            snapshotRevision &+= 1
            if oldValue.emojisByID != snapshot.emojisByID {
                phase68EmojiCatalogRevision &+= 1
                phase68CustomEmojiIndex = nil
                composerEmojiSectionCacheKey = nil
                composerEmojiSectionCache = []
            }
            // Do NOT unconditionally nil memberListGroupCacheKey here: it fires on every
            // realtime event (including pure message traffic), and eagerly clearing it defeats
            // the fingerprint-based cache in memberListCacheKey(serverID:query:), forcing a full
            // re-derivation of the member list on every event. memberListGroups/
            // prepareMemberListGroups already recompute correctly whenever the fingerprint
            // (member/role/identity fields) actually changes.
            if isServerOverviewPresented {
                schedulePhase51ServerSettingsPreparation()
            }
        }
    }
    public var connectionState: RealtimeConnectionState
    public var diagnostics: RealtimeDiagnostics?
    public var runtimeMode: AppRuntimeMode {
        didSet { invalidateCapabilityCache() }
    }
    public var sessionState: AppSessionState {
        didSet { invalidateCapabilityCache() }
    }
    public var currentUser: User? {
        didSet {
            guard oldValue != currentUser else { return }
            if let currentUser {
                mergePhase43User(currentUser, source: .readyUser)
            }
            phase46ModerationVersions.bumpMemberVersion()
            invalidateCapabilityCache()
            phase51ShellDataRevision &+= 1
            schedulePhase51ShellPresentationRefresh(reason: "current user")
        }
    }
    public var sessionCoordinator: AppSessionCoordinator?
    public var messageController: ChannelMessageController
    public var isQuickSwitcherPresented = false
    public var quickSwitcherViewModel: QuickSwitcherViewModel
    public var placeholderStatus: String? {
        didSet { routeLegacyStatusToNotice(placeholderStatus) }
    }
    public private(set) var transientNotice: TransientAppNotice?
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
    /// Set just before a send inserts its optimistic message; consumed by the next grouping pass
    /// for that channel, which fires an unconditional scroll-to-newest. The intent cannot be set
    /// in `sendDraft` directly: the row only becomes scrollable after
    /// `prepareSelectedTimelineGrouping` rebuilds `selectedTimelineRenderItems`.
    @ObservationIgnored var pendingOwnSendScrollChannelID: ChannelID?
    public var localReadStates: [ChannelID: LocalReadState] = [:] {
        didSet {
            guard oldValue != localReadStates else { return }
            phase51ShellDataRevision &+= 1
            schedulePhase51ShellPresentationRefresh(reason: "local read state")
        }
    }
    public var messageActionStatus: String?
    public var isCredentialSetupPresented = false
    public var isTestSendConfirmationPresented = false
    public var selectedSettingsTab: SettingsSectionTab = .account
    public var messageDensity: MessageDensityPreference = .comfortable
    public var reduceGlassIntensity = false
    public var liquidGlassTransparency = AppPreferences.clampedLiquidGlassTransparency(1.0)
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
    public var targetMessageHighlightState: TargetMessageHighlightState?
    public var isPinnedMessagesPresented = false
    public var pinnedMessagesState = PinnedMessagesState()
    public var typingIndicatorState = TypingIndicatorState()
    public var phase44Diagnostics = Phase44ChatInteractionDiagnostics()
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
    private var clipboardPasteQueuedAttachment = false
    private var clipboardPasteRejectedAttachment = false
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
    public private(set) var memberListGroupsRevision = 0
    public private(set) var selectedMemberListPublicationRevision = 0
    public var visibleIdentityDiagnostics = VisibleIdentityDiagnostics()
    @ObservationIgnored public var phase43IdentitySnapshots = Phase43IdentitySnapshotStore()
    public var phase43IdentityGeneration = 0
    public var freezePerformanceDiagnostics = FreezePerformanceDiagnostics()
    public private(set) var phase51PerformanceDiagnostics = Phase51PerformanceDiagnostics()
    public private(set) var phase59ReactionDiagnostics = Phase59ReactionDiagnostics()
    @ObservationIgnored public private(set) var phase60Diagnostics = Phase60Diagnostics()
    @ObservationIgnored public private(set) var phase63ComposerDiagnostics = Phase63ComposerDiagnostics()
    @ObservationIgnored public private(set) var phase68TraceDiagnostics = Phase68TraceDiagnostics()
    public private(set) var phase52FreezeDiagnostics = Phase52FreezeDiagnostics()
    public private(set) var timelinePresentationState: TimelinePresentationState = .idle
    public private(set) var timelinePresentationDiagnostics = TimelinePresentationDiagnostics()
    public private(set) var shellPresentationSnapshot = ShellPresentationSnapshot()
    public private(set) var serverSettingsPresentationState: ManagementActionState<ServerSettingsPresentationSnapshot> = .idle
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
    public var isPresentingNewDirectMessage = false
    public var isPresentingCustomStatusEditor = false
    public var customStatusDraft = ""
    public var isPresentingNewGroup = false
    public var groupCreateName = ""
    public var groupCreateSearch = ""
    public var groupCreateSelectedUserIDs: Set<UserID> = []
    public var groupCreateState: GroupCreateState = .idle
    public var isPresentingAddGroupMembers = false
    public var addGroupMembersChannelID: ChannelID?
    public var addGroupMembersSearch = ""
    public var addGroupMembersSelectedUserIDs: Set<UserID> = []
    public var groupMembershipActionState: GroupMembershipActionState = .idle
    public var pendingGroupMemberRemoval: PendingGroupMemberRemoval?
    public var composerAutocompleteTrigger: InlineComposerTrigger?
    public var composerAutocompleteCandidates: [ComposerAutocompleteCandidate] = []
    public var composerAutocompleteHighlightedID: String?
    public var composerCursorRequest: ComposerCursorRequest?
    private var composerCursorRequestCounter = 0
    private var autocompleteIndexCache: [ComposerAutocompleteKind: (scopeID: String, revision: Int, index: Phase58MentionCandidateIndex)] = [:]
    public var settingsSyncState: SettingsSyncState = .idle
    private var localSettingsSyncTimestamp: Int64?
    public var newDirectMessageSearch = ""
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
    public var isServerOverviewPresented = false {
        didSet {
            if isServerOverviewPresented {
                schedulePhase51ServerSettingsPreparation()
            } else {
                phase51ServerSettingsTask?.cancel()
                phase51ServerSettingsTask = nil
            }
        }
    }
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
    public var serverEmojiName = ""
    public var serverEmojiDraft: ServerMediaDraft?
    public var serverEmojiManagementState: ManagementActionState<[Emoji]> = .idle
    public var pendingServerEmojiDeletion: Emoji?
    public var categoryEditorForm: CategoryEditorForm?
    public var categoryEditorState: ManagementActionState<Server> = .idle
    public var roleEditorForm: RoleEditorForm?
    public var roleEditorState: ManagementActionState<Role> = .idle
    public var pendingRoleDeletion: Role?
    public var memberSearchText: String = "" {
        didSet {
            guard oldValue != memberSearchText, isServerOverviewPresented else { return }
            schedulePhase51ServerSettingsPreparation(debounce: true)
        }
    }
    public var selectedMemberDetailID: MemberCompositeKey?
    public var memberRoleDraft: MemberRoleAssignmentDraft?
    public var memberRoleSaveRequiresConfirmation = false
    public var memberNicknameDraft: String = ""
    public var memberTimeoutHours: Double = 1
    public var pendingMemberModerationAction: PendingMemberModerationAction?
    public var memberActionState: ManagementActionState<ServerMember> = .idle
    public var banListState: ManagementActionState<BanListResult> = .idle {
        didSet {
            banListGeneration &+= 1
            phase46ModerationVersions.bumpBanVersion()
            invalidateModerationAvailabilityCaches()
        }
    }
    public var moderationBanSearchText: String = ""
    public var moderationTimeoutSearchText: String = ""
    public var pendingModerationConfirmation: PendingModerationConfirmation?
    public var moderationActionState: ManagementActionState<String> = .idle
    public var moderationDiagnostics = ModerationDiagnostics()
    public var permissionEditDraft: PermissionEditDraft?
    public var permissionSaveRequiresConfirmation = false
    public var permissionEditorState: ManagementActionState<String> = .idle
    public var phase25Status: String?
    public var phase26Status: String?
    public var testingSignedNotificationBuild = false
    public private(set) var notificationSignatureCheckState: NotificationSignatureCheckState = .notStarted
    // Cached per-server capability snapshot — updated lazily whenever snapshot/selection/session state changes.
    // Context-menu disabled checks read from this; never recompute on every SwiftUI layout pass.
    public private(set) var cachedServerCapabilities: ServerManagementCapabilities = ServerManagementCapabilities(canManageServer: false, canManageChannels: false, canInvite: false, isConnectedForLiveActions: false)
    public private(set) var cachedCurrentPermissionResolution: PermissionResolutionResult = PermissionResolutionResult(effectivePermissions: [], warnings: [.missingServer])

    @ObservationIgnored public var messageActionHandler: any MessageActionHandling
    @ObservationIgnored public var messageCopier: any MessageCopying
    @ObservationIgnored public var attachmentUploadHandler: any AttachmentUploadHandling
    @ObservationIgnored public var remoteAttachmentLoader: any RemoteAttachmentLoading
    @ObservationIgnored public var imageResourceLoader: any ImageResourceLoading
    @ObservationIgnored public var imageMemoryCache: ImageMemoryCache
    @ObservationIgnored public var imageDiskCache: any ImageDiskCaching = NoopImageDiskCache()
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
    @ObservationIgnored private var phase51ShellPresentationTask: Task<Void, Never>?
    @ObservationIgnored private var phase51ServerSettingsTask: Task<Void, Never>?
    @ObservationIgnored private var phase51TimelinePresentationTask: Task<Void, Never>?
    @ObservationIgnored private var phase51DiagnosticsPublishTask: Task<Void, Never>?
    @ObservationIgnored private var phase68VisibleIdentityDiagnosticsTask: Task<Void, Never>?
    @ObservationIgnored private var notificationSignatureCheckTask: Task<Void, Never>?
    @ObservationIgnored private var notificationSignatureCheckStartCount = 0
    @ObservationIgnored private var notificationSignatureCheckCompletionCount = 0
    @ObservationIgnored private var notificationSignatureCheckCacheHitCount = 0
    @ObservationIgnored private var notificationSignatureStatusPreparer: @Sendable (URL) async -> String = { bundleURL in
        await Task.detached(priority: .utility) {
            NotificationSignatureChecker.detectedSignatureStatus(bundleURL: bundleURL, overrideAsSigned: false)
        }.value
    }
    @ObservationIgnored private var phase68VisibleIdentityDiagnosticsGeneration = 0
    @ObservationIgnored private var phase68VisibleIdentityDiagnosticsPreparer: @Sendable (Phase68VisibleIdentityDiagnosticsInput) async -> VisibleIdentityDiagnostics = { input in
        await Task.detached(priority: .utility) {
            Phase68VisibleIdentityDiagnosticsPreparer.prepare(input)
        }.value
    }
    @ObservationIgnored private var selectedChannelLoadTask: Task<Void, Never>?
    @ObservationIgnored private var selectedChannelLoadTaskChannelID: ChannelID?
    @ObservationIgnored private var typingEndTask: Task<Void, Never>?
    @ObservationIgnored private var typingEndDeadline: Date?
    @ObservationIgnored private var typingCleanupTask: Task<Void, Never>?
    @ObservationIgnored private var ackTasksByChannelID: [ChannelID: Task<Void, Never>] = [:]
    @ObservationIgnored private var pendingAckMessageIDsByChannelID: [ChannelID: MessageID] = [:]
    @ObservationIgnored private var lastAckRequestAtByChannelID: [ChannelID: Date] = [:]
    @ObservationIgnored private var messageNavigationCoordinator = MessageNavigationCoordinator()
    @ObservationIgnored private var targetHighlightClearTask: Task<Void, Never>?
    @ObservationIgnored private var pinnedMessagesFetchTask: Task<Void, Never>?
    @ObservationIgnored private var pinnedMessageActionTasks: [MessageID: Task<Void, Never>] = [:]
    @ObservationIgnored private var inFlightReactionMutations: Set<ReactionMutationKey> = []
    @ObservationIgnored private var referenceFetchTasks: [MessageID: Task<Void, Never>] = [:]
    @ObservationIgnored private var attachmentLoadTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var imageResourceLoadTasks: [ImageCacheKey: Task<Void, Never>] = [:]
    @ObservationIgnored private var queuedImageResourceRequests: [ImageCacheKey: PrioritizedImageResourceRequest] = [:]
    @ObservationIgnored private var imageResourceQueueSequence: UInt64 = 0
    @ObservationIgnored private var imageResourceFailureDates: [ImageCacheKey: Date] = [:]
    @ObservationIgnored private var imagePresentationOrder: [ImageCacheKey] = []
    @ObservationIgnored private var imagePresentationByteCount = 0
    @ObservationIgnored private let maxImagePresentationBytes = 64 * 1024 * 1024
    @ObservationIgnored private var visibleImageResourceRequestsByConsumer: [String: ImageResourceRequest] = [:]
    @ObservationIgnored private var memberAvatarHideTasksByConsumer: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var timelineAvatarReleaseDeadlinesByConsumer: [String: Date] = [:]
    @ObservationIgnored private var inlinePreviewReleaseDeadlinesByMessageID: [MessageID: (channelID: ChannelID, deadline: Date)] = [:]
    @ObservationIgnored private var timelineVisibilityLeaseTask: Task<Void, Never>?
    @ObservationIgnored private var selectedTimelineMessagesByIDCache: [MessageID: TimelineMessage] = [:]
    @ObservationIgnored private var composerEmojiSectionCacheKey: String?
    @ObservationIgnored private var composerEmojiSectionCache: [EmojiPickerSection] = []
    @ObservationIgnored private var emojiAutocompleteCache: (revision: Int, serverID: ServerID?, candidates: [ComposerAutocompleteCandidate])?
    @ObservationIgnored private var phase68CustomEmojiIndex: Phase68CustomEmojiIndex?
    @ObservationIgnored private var phase68EmojiCatalogRevision = 0
    @ObservationIgnored private var composerAttachmentPresentationCache: [ChannelID: (attachments: [ComposerAttachmentDraft], chips: [ComposerAttachmentChip], summary: String?)] = [:]
    @ObservationIgnored private var imagePresentationEvictedKeys: Set<ImageCacheKey> = []
    @ObservationIgnored private var imagePresentationEvictedOrder: [ImageCacheKey] = []
    @ObservationIgnored private var imagePresentationEvictionCount = 0
    @ObservationIgnored private var imageReloadAfterEvictionCount = 0
    @ObservationIgnored private var imageQueueEnqueueCount = 0
    @ObservationIgnored private var timelineMediaInvalidationCount = 0
    @ObservationIgnored private var attachmentPreviewOrder: [String] = []
    @ObservationIgnored private var attachmentPreviewByteCount = 0
    @ObservationIgnored private let maxAttachmentPreviewBytes = 64 * 1024 * 1024
    @ObservationIgnored private let maxConcurrentImageResourceLoads = 8
    @ObservationIgnored private let maxConcurrentInlinePreviewLoads = 6
    @ObservationIgnored private var imageResourceFailureCounts: [ImageCacheKey: Int] = [:]
    @ObservationIgnored private var queuedInlinePreviewItems: [AttachmentDisplayItem] = []
    @ObservationIgnored private var lastRequestedDockBadgeValue: Int?
    @ObservationIgnored private var dockBadgeApplyTask: Task<Void, Never>?
    @ObservationIgnored private var pendingTimelineMediaInvalidation = false
    @ObservationIgnored public var phase43HydrationPolicy = Phase43HydrationPolicy()
    @ObservationIgnored private var phase43IdentityHydrationTasks: [UserID: Task<Void, Never>] = [:]
    @ObservationIgnored private var phase43QueuedIdentityHydration: [UserID: Phase43IdentityHydrationSource] = [:]
    @ObservationIgnored private var phase43IdentityHydrationFailuresByUserID: [UserID: (count: Int, cooldownUntil: Date)] = [:]
    @ObservationIgnored private var phase43Now: () -> Date = Date.init
    @ObservationIgnored private var memberHydrationTasks: [ServerID: Task<Void, Never>] = [:]
    @ObservationIgnored private var memberHydrationGenerations: [ServerID: Int] = [:]
    @ObservationIgnored private var hydratedMemberServerIDs: Set<ServerID> = []
    @ObservationIgnored private var restHydratedMembersByServerID: [ServerID: [ServerMemberKey: ServerMember]] = [:]
    @ObservationIgnored private var restHydratedUsersByServerID: [ServerID: [UserID: User]] = [:]
    @ObservationIgnored private var memberHydrationScope: String?
    @ObservationIgnored private var lastMemberHydrationRequestedAt: [ServerID: Date] = [:]
    @ObservationIgnored private var activeTypingChannelID: ChannelID?
    @ObservationIgnored private var lastTypingBeginAt: [ChannelID: Date] = [:]
    @ObservationIgnored private var lastAckedMessageByChannelID: [ChannelID: MessageID] = [:]
    @ObservationIgnored private var visibleMessageIDsByChannelID: [ChannelID: Set<MessageID>] = [:]
    @ObservationIgnored private var pendingVisibleMessageIDsByChannelID: [ChannelID: Set<MessageID>] = [:]
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
    @ObservationIgnored private var selectedTimelineGroupCacheChannelID: ChannelID?
    @ObservationIgnored private var selectedTimelineGroupCache: [TimelineMessageGroup] = []
    @ObservationIgnored private var selectedTimelineRenderItemCache: [TimelineRenderItem] = []
    @ObservationIgnored private var timelineRowPresentationCacheKey: String?
    @ObservationIgnored private var timelineRowPresentationCacheChannelID: ChannelID?
    @ObservationIgnored private var timelineRowPresentationCache: [MessageID: TimelineRowPresentation] = [:]
    @ObservationIgnored private var phase60RowPresentationStates: [MessageID: TimelineRowPresentationState] = [:]
    @ObservationIgnored private var phase60DesiredRowKeys: [MessageID: TimelineRowPreparationKey] = [:]
    @ObservationIgnored private var phase60QueuedRows: [TimelineRowPreparationKey: Phase60QueuedRowPreparation] = [:]
    @ObservationIgnored private var phase60RowQueueSequence: UInt64 = 0
    @ObservationIgnored private var phase60RowWorkerTask: Task<Void, Never>?
    @ObservationIgnored private var phase60ActiveRowKey: TimelineRowPreparationKey?
    @ObservationIgnored private var phase60VisibleSkeletonIDs: Set<MessageID> = []
    @ObservationIgnored private var phase61LocalSendMessageIDByNonce: [ChannelID: [String: MessageID]] = [:]
    @ObservationIgnored private var memberListGroupCacheKey: MemberListCacheKey?
    @ObservationIgnored private var memberListGroupCache: [MemberListGroup] = []
    @ObservationIgnored private var memberListDiagnosticsCache = RoleSortDiagnostics()
    @ObservationIgnored private var phase68MemberIdentityRevisionByServerID: [ServerID: Int] = [:]
    @ObservationIgnored private var snapshotRevision: Int = 0
    @ObservationIgnored private var phase51SelectionRevision: Int = 0
    @ObservationIgnored private var phase51MediaRevision: Int = 0
    @ObservationIgnored private var phase51ShellDataRevision: Int = 0
    @ObservationIgnored private var phase51ShellGeneration: Int = 0
    @ObservationIgnored private var phase51ShellBuiltKey: Phase51PresentationRevision?
    @ObservationIgnored private var phase51ShellActiveKey: Phase51PresentationRevision?
    @ObservationIgnored private var phase51ShellDesiredKey: Phase51PresentationRevision?
    @ObservationIgnored private var phase51ServerSettingsGeneration: Int = 0
    @ObservationIgnored private var phase51LastDiagnosticsPublishAt = Date.distantPast
    @ObservationIgnored private var freezeDiagnosticsPublishTask: Task<Void, Never>?
    @ObservationIgnored private var freezeDiagnosticsLastPublishAt = Date.distantPast
    @ObservationIgnored private var pendingFreezeDiagnosticsMarker: String?
    @ObservationIgnored private var memberDiagnosticsPublishPending = false
    @ObservationIgnored private var memberListLastCacheHit = false
    @ObservationIgnored private var memberListLastGroupingElapsed: TimeInterval = 0
    @ObservationIgnored private var memberListLastGroupingServerID: ServerID? = nil
    @ObservationIgnored private var timelineVisibleRangeUpdateCount = 0
    @ObservationIgnored private var memberGroupingCount = 0
    @ObservationIgnored private var memberGroupingCacheHitCount = 0
    @ObservationIgnored private var capabilityCacheUpdateCount = 0
    @ObservationIgnored public private(set) var moderationCacheDiagnostics = ModerationCacheDiagnostics()
    @ObservationIgnored public private(set) var channelsForServerInvocationCount = 0
    @ObservationIgnored private var moderationCacheGeneration = 0
    @ObservationIgnored private var banListGeneration = 0
    @ObservationIgnored private var moderationBaseContextCacheKey: ModerationBaseContextCacheKey?
    @ObservationIgnored private var moderationBaseContextCache: ModerationBaseContextSnapshot?
    @ObservationIgnored private var moderationPermissionResolutionCache: [ModerationPermissionResolutionCacheKey: PermissionResolutionResult] = [:]
    @ObservationIgnored private var memberModerationMenuStateCache: [ModerationMenuStateCacheKey: MemberModerationMenuState] = [:]
    @ObservationIgnored private var phase46ModerationVersions = Phase46ModerationSignatureSummary()
    @ObservationIgnored private var imageCompletedCount = 0
    @ObservationIgnored private var diagnosticsPublishCount = 0
    @ObservationIgnored private var profileFetchMergeCount = 0
    @ObservationIgnored private var memberWrapperUserMergeCount = 0
    @ObservationIgnored private var phase43IdentityHydrationSuccessCount = 0
    @ObservationIgnored private var phase43IdentityHydrationFailureCount = 0
    @ObservationIgnored private var phase43IdentityHydrationDedupeHits = 0
    @ObservationIgnored private var phase43IdentityHydrationCooldownSkips = 0
    @ObservationIgnored private var phase43AvatarMetadataPreservedAfterMemberRemovalCount = 0
    @ObservationIgnored private var phase43ProfileOpensFromSystemEventsCount = 0
    @ObservationIgnored private var phase43CurrentUserEditSnapshotMergeCount = 0
    @ObservationIgnored private var phase43MemberRemovalIdentityPreservationCount = 0
    public private(set) var memberPanelModerationPrewarmToken = Phase46ModerationPrewarmKey()
    public private(set) var phase46MemberPanelPrewarmState = Phase46MemberPanelPrewarmState()
    public private(set) var phase46FreezePreventionDiagnostics = Phase46FreezePreventionDiagnostics()
    @ObservationIgnored private var transientStatusTask: Task<Void, Never>?
    @ObservationIgnored private var transientNoticeTask: Task<Void, Never>?
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
        appLifecycleCenter: AppLifecycleCenter = .shared,
        notificationSignatureStatusPreparer: (@Sendable (URL) async -> String)? = nil
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
        if let notificationSignatureStatusPreparer {
            self.notificationSignatureStatusPreparer = notificationSignatureStatusPreparer
        }
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
        mergePhase43SnapshotIdentities(snapshot, source: .readyUser)
        if let currentUser = self.currentUser {
            mergePhase43User(currentUser, source: .readyUser)
        }
        validateSelection()
        invalidateCapabilityCache()
        self.messageController.hydrate(from: snapshot)
        refreshDMDiagnosticsSnapshot()
        installNotificationRouteHandler()
        installAppLifecycleHandler()
        // Bootstrap once so command routing and tests have a coherent snapshot before the
        // first SwiftUI frame. Subsequent revisions are prepared off-main and swapped atomically.
        // The builder only throws on cancellation, which cannot happen during this synchronous
        // bootstrap, so an empty snapshot is a safe fallback.
        self.shellPresentationSnapshot = (try? Phase51PresentationBuilder.shell(
            revision: Phase51PresentationRevision(),
            snapshot: snapshot,
            selection: selection,
            currentUserID: self.currentUserID,
            currentUser: self.currentUser,
            localReadStates: [:],
            locallyClearedUnreadChannelIDs: [],
            notificationPreferences: self.notificationPreferences
        )) ?? ShellPresentationSnapshot()
        self.phase51PerformanceDiagnostics.shellBuildCount = 1
        self.phase51PerformanceDiagnostics.shellRelationshipCandidateCount = self.shellPresentationSnapshot.allFriendItems.count
        self.phase51ShellBuiltKey = Phase51PresentationRevision()
        self.phase51ShellDesiredKey = Phase51PresentationRevision()
        if let snapshotSource {
            observe(snapshotSource: snapshotSource)
        }
    }

    deinit {
        snapshotObservationTask?.cancel()
        phase51ShellPresentationTask?.cancel()
        phase51ServerSettingsTask?.cancel()
        phase51TimelinePresentationTask?.cancel()
        phase60RowWorkerTask?.cancel()
        phase51DiagnosticsPublishTask?.cancel()
        notificationSignatureCheckTask?.cancel()
        freezeDiagnosticsPublishTask?.cancel()
        selectedChannelLoadTask?.cancel()
        typingEndTask?.cancel()
        timelineVisibilityLeaseTask?.cancel()
        typingCleanupTask?.cancel()
        ackTasksByChannelID.values.forEach { $0.cancel() }
        visibleRangeUpdateTasks.values.forEach { $0.cancel() }
        targetHighlightClearTask?.cancel()
        pinnedMessagesFetchTask?.cancel()
        pinnedMessageActionTasks.values.forEach { $0.cancel() }
        transientStatusTask?.cancel()
        transientNoticeTask?.cancel()
        referenceFetchTasks.values.forEach { $0.cancel() }
        attachmentLoadTasks.values.forEach { $0.cancel() }
        imageResourceLoadTasks.values.forEach { $0.cancel() }
        queuedImageResourceRequests.removeAll()
        phase43IdentityHydrationTasks.values.forEach { $0.cancel() }
        phase43QueuedIdentityHydration.removeAll()
        memberHydrationTasks.values.forEach { $0.cancel() }
    }

    public var servers: [Server] {
        shellPresentationSnapshot.servers
    }

    public func serverRailPresentation(for serverID: ServerID) -> ServerRailPresentationItem? {
        shellPresentationSnapshot.serverRailItemsByID[serverID]
    }

    private func schedulePhase51ShellPresentationRefresh(reason: String = "state") {
        phase51PerformanceDiagnostics.shellRequestCount += 1
        phase51PerformanceDiagnostics.lastShellInvalidationReason = reason
        let revision = Phase51PresentationRevision(
            snapshot: phase51ShellDataRevision,
            selection: phase51SelectionRevision,
            identity: 0,
            media: 0
        )
        phase51ShellDesiredKey = revision
        guard revision != phase51ShellBuiltKey else {
            phase51PerformanceDiagnostics.shellCacheHitCount += 1
            return
        }
        guard phase51ShellPresentationTask == nil else {
            if revision != phase51ShellActiveKey {
                phase51PerformanceDiagnostics.shellCoalescedCount += 1
            } else {
                phase51PerformanceDiagnostics.shellCacheHitCount += 1
            }
            return
        }
        phase51ShellGeneration &+= 1
        let generation = phase51ShellGeneration
        phase51ShellActiveKey = revision
        let snapshot = snapshot
        let selection = selection
        let currentUserID = currentUserID
        let currentUser = currentUser
        let localReadStates = localReadStates
        let locallyCleared = locallyClearedUnreadChannelIDs
        let preferences = notificationPreferences
        phase51ShellPresentationTask = Task { [weak self] in
            let started = ContinuousClock.now
            let worker = Task.detached(priority: .userInitiated) {
                try Phase51PresentationBuilder.shell(
                    revision: revision,
                    snapshot: snapshot,
                    selection: selection,
                    currentUserID: currentUserID,
                    currentUser: currentUser,
                    localReadStates: localReadStates,
                    locallyClearedUnreadChannelIDs: locallyCleared,
                    notificationPreferences: preferences
                )
            }
            // Cancelling this task (on supersede) also cancels the detached worker so a stale
            // build stops at its next checkpoint instead of running to completion.
            let result: ShellPresentationSnapshot
            do {
                result = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
            } catch {
                return
            }
            guard let self else { return }
            let isCurrent = !Task.isCancelled
                && generation == self.phase51ShellGeneration
                && revision == self.phase51ShellDesiredKey
            if isCurrent {
                self.shellPresentationSnapshot = result
                self.quickSwitcherViewModel.update(snapshot: snapshot, selection: selection)
                self.phase51ShellBuiltKey = revision
                self.phase51PerformanceDiagnostics.shellBuildCount += 1
                self.phase51PerformanceDiagnostics.shellRelationshipCandidateCount = result.allFriendItems.count
                self.recordPhase51Operation("shell-presentation", started: started)
            } else {
                self.phase51PerformanceDiagnostics.shellDiscardedCount += 1
            }
            self.phase51ShellPresentationTask = nil
            self.phase51ShellActiveKey = nil
            if self.phase51ShellDesiredKey != self.phase51ShellBuiltKey {
                self.schedulePhase51ShellPresentationRefresh(reason: "coalesced latest")
            }
        }
    }

    private func invalidateShellPresentation(reason: String) {
        phase51ShellDataRevision &+= 1
        schedulePhase51ShellPresentationRefresh(reason: reason)
    }

    private func schedulePhase51ServerSettingsPreparation(debounce: Bool = false) {
        phase51ServerSettingsGeneration &+= 1
        let generation = phase51ServerSettingsGeneration
        phase51ServerSettingsTask?.cancel()
        guard isServerOverviewPresented, let serverID = selection.serverID else {
            serverSettingsPresentationState = .failed("Select a server before opening server settings.")
            return
        }
        serverSettingsPresentationState = .loading
        let revision = Phase51PresentationRevision(
            snapshot: snapshotRevision,
            selection: phase51SelectionRevision,
            identity: phase43IdentityGeneration,
            media: phase51MediaRevision
        )
        let snapshot = snapshot
        let selectedChannelID = selection.channelID
        let currentUserID = currentUserID
        let runtimeLine = runtimeSubtitleForManagement
        let capabilities = cachedServerCapabilities
        let identitySnapshots = phase43IdentitySnapshots
        let normalizedQuery = memberSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        phase51ServerSettingsTask = Task { [weak self] in
            if debounce {
                do {
                    try await Task.sleep(for: .milliseconds(150))
                } catch {
                    return
                }
            }
            let started = ContinuousClock.now
            let worker = Task.detached(priority: .userInitiated) {
                Phase51PresentationBuilder.serverSettings(
                    revision: revision,
                    snapshot: snapshot,
                    serverID: serverID,
                    selectedChannelID: selectedChannelID,
                    currentUserID: currentUserID,
                    runtimeLine: runtimeLine,
                    capabilities: capabilities,
                    identitySnapshots: identitySnapshots,
                    normalizedMemberQuery: normalizedQuery
                )
            }
            let result = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard !Task.isCancelled, let self, generation == self.phase51ServerSettingsGeneration else {
                if let self {
                    self.phase51PerformanceDiagnostics.serverSettingsCancellationCount += 1
                }
                return
            }
            guard let result else {
                self.serverSettingsPresentationState = .failed("Selected server is no longer available.")
                return
            }
            self.serverSettingsPresentationState = .loaded(result)
            self.serverSettingsState = .loaded(result.details)
            self.serverSettingsForm = self.serverSettingsForm ?? ServerSettingsForm(server: result.details.server)
            self.categoryEditorForm = self.categoryEditorForm ?? CategoryEditorForm(server: result.details.server)
            self.serverOverviewState = .loaded(
                ServerOverviewDetails(
                    server: result.details.server,
                    channels: result.details.channels,
                    memberCount: result.details.members.count,
                    runtimeLine: result.details.runtimeLine,
                    capabilities: result.details.capabilities
                )
            )
            self.phase51PerformanceDiagnostics.serverSettingsBuildCount += 1
            self.recordPhase51Operation("server-settings-presentation", started: started)
        }
    }

    private func recordPhase51Operation(_ category: String, started: ContinuousClock.Instant) {
        let duration = started.duration(to: .now)
        let milliseconds = Int(duration.components.seconds * 1_000)
            + Int(duration.components.attoseconds / 1_000_000_000_000_000)
        phase51PerformanceDiagnostics.lastOperationCategory = category
        phase51PerformanceDiagnostics.lastOperationMilliseconds = milliseconds
        if milliseconds > 50, Thread.isMainThread {
            phase51PerformanceDiagnostics.mainThreadBudgetViolationCount += 1
        }
        schedulePhase51DiagnosticsPublish()
    }

    private func schedulePhase51DiagnosticsPublish() {
        let now = Date()
        let elapsed = now.timeIntervalSince(phase51LastDiagnosticsPublishAt)
        if elapsed >= 0.25 {
            phase51LastDiagnosticsPublishAt = now
            phase51PerformanceDiagnostics.diagnosticsPublishCount += 1
            return
        }
        phase51PerformanceDiagnostics.diagnosticsThrottleCount += 1
        guard phase51DiagnosticsPublishTask == nil else { return }
        let delay = max(0, 0.25 - elapsed)
        phase51DiagnosticsPublishTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard let self else { return }
            self.phase51LastDiagnosticsPublishAt = Date()
            self.phase51PerformanceDiagnostics.diagnosticsPublishCount += 1
            self.phase51DiagnosticsPublishTask = nil
        }
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
            let user = snapshot.usersByID[userID] ?? (userID == currentUser?.id ? currentUser : nil)
            let display = phase43IdentitySnapshots.resolvedDisplay(userID: userID, user: user, member: nil, server: nil)
            return MemberListItem(userID: userID, user: user, member: nil, display: display)
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

    public var selectedTimelineRenderItems: [TimelineRenderItem] {
        guard selectedTimelineGroupCacheChannelID == selectedConversationChannelID else { return [] }
        return selectedTimelineRenderItemCache
    }

    public var selectedTimelinePresentationRevision: Int {
        messageController.presentationRevision(for: selectedConversationChannelID)
    }

    public var selectedTimelineGroupingToken: String {
        timelineGroupingCacheKey()
    }

    public var selectedTimelinePresentationToken: String {
        timelineRowPresentationCacheKeyValue()
    }

    public func prepareSelectedTimelinePresentation() async {
        await prepareSelectedTimelineGrouping()
        if selectedTimelineMessageGroups.isEmpty, !selectedTimelineMessages.isEmpty {
            await Task.yield()
            await prepareSelectedTimelineGrouping()
        }
        await prepareSelectedTimelineRows()
    }

    public func prepareSelectedTimelineGrouping() async {
        let messages = selectedTimelineMessages
        let key = timelineGroupingCacheKey()
        if key == selectedTimelineGroupCacheKey {
            phase51PerformanceDiagnostics.timelineCacheHitCount += 1
            updateTimelinePerformanceDiagnostics(messages: messages, groups: selectedTimelineGroupCache)
            return
        }
        guard let channelID = selectedConversationChannelID else {
            timelinePresentationState = .idle
            return
        }
        let previousGroups = cachedSelectedTimelineMessageGroups()
        timelinePresentationState = .preparing(
            channelID: channelID,
            loadedMessageCount: messages.count,
            visibleGroupCount: previousGroups.count
        )
        let worker = Task.detached(priority: .userInitiated) {
            TimelineMessageGrouping.group(messages)
        }
        let groups = await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
        guard !Task.isCancelled else {
            timelinePresentationDiagnostics.cancellationCount += 1
            return
        }
        guard key == timelineGroupingCacheKey(), selectedConversationChannelID == channelID else {
            timelinePresentationDiagnostics.staleResultDiscardCount += 1
            return
        }
        let previousCacheChannelID = selectedTimelineGroupCacheChannelID
        let previousNewestID = selectedTimelineGroupCache.last?.messages.last?.message.id
        selectedTimelineGroupCacheKey = key
        selectedTimelineGroupCacheChannelID = channelID
        selectedTimelineGroupCache = groups
        selectedTimelineRenderItemCache = TimelineRenderItemBuilder.flatten(groups, currentUserID: currentUserID)
        selectedTimelineMessagesByIDCache = Dictionary(
            selectedTimelineRenderItemCache.map { ($0.id, $0.timelineMessage) },
            uniquingKeysWith: { _, latest in latest }
        )
        synchronizeTimelineRowStates(items: selectedTimelineRenderItemCache, channelID: channelID)
        updateTimelineViewportAfterGroupingPass(
            channelID: channelID,
            previousCacheChannelID: previousCacheChannelID,
            previousNewestID: previousNewestID,
            newestID: groups.last?.messages.last?.message.id
        )
        timelinePresentationState = .ready(
            channelID: channelID,
            messageCount: messages.count,
            groupCount: groups.count
        )
        timelinePresentationDiagnostics.groupingBuildCount += 1
        timelinePresentationDiagnostics.visibleMessageCount = messages.count
        timelinePresentationDiagnostics.visibleGroupCount = groups.count
        updateTimelinePerformanceDiagnostics(messages: messages, groups: groups)
        phase51PerformanceDiagnostics.timelineBuildCount += 1
        schedulePhase51DiagnosticsPublish()
    }

    /// Runs after every grouping rebuild, once the new rows are actually scrollable. An own send
    /// scrolls to newest unconditionally (standard chat behavior, even when scrolled up reading
    /// history); any other newest-message change flows through the reducer's `newMessage` rule --
    /// auto-follow when pinned to the bottom, the Jump-to-Newest indicator otherwise.
    private func updateTimelineViewportAfterGroupingPass(
        channelID: ChannelID,
        previousCacheChannelID: ChannelID?,
        previousNewestID: MessageID?,
        newestID: MessageID?
    ) {
        if let pending = pendingOwnSendScrollChannelID, pending != channelID {
            pendingOwnSendScrollChannelID = nil
        }
        if pendingOwnSendScrollChannelID == channelID {
            pendingOwnSendScrollChannelID = nil
            timelineViewport = viewportReducer.jumpNewest(timelineViewport, newestMessageID: newestID)
            return
        }
        guard let newestID,
              previousCacheChannelID == channelID,
              timelineViewport.channelID == channelID,
              let previousNewestID,
              previousNewestID != newestID
        else { return }
        timelineViewport = viewportReducer.newMessage(
            timelineViewport,
            newestMessageID: newestID,
            isActiveChannel: true
        )
    }

    public func prepareSelectedTimelineRows() async {
        guard let channelID = selectedConversationChannelID else { return }
        if selectedTimelineRenderItems.isEmpty, !selectedTimelineMessages.isEmpty {
            await prepareSelectedTimelineGrouping()
        }
        let items = selectedTimelineRenderItems
        synchronizeTimelineRowStates(items: items, channelID: channelID)
        let anchor = initialTimelinePreparationAnchor()
        let startupTargets = TimelineRowPreparationPlanner.startupTargets(
            items: items,
            anchorMessageID: anchor
        )
        let visibleTargets = TimelineRowPreparationPlanner.visibleTargets(
            items: items,
            visibleMessageIDs: pendingVisibleMessageIDsByChannelID[channelID]
                ?? visibleMessageIDsByChannelID[channelID]
                ?? []
        )
        enqueueTimelineRowPreparation(
            visibleTargets + startupTargets,
            channelID: channelID
        )
        await phase60RowWorkerTask?.value
    }

    public func timelineRowPresentation(for messageID: MessageID) -> TimelineRowPresentation? {
        timelineRowPresentationState(for: messageID)?.presentation
    }

    public func timelineRowPresentationState(for messageID: MessageID) -> TimelineRowPresentationState? {
        guard let channelID = selectedConversationChannelID,
              let state = phase60RowPresentationStates[messageID],
              state.channelID == channelID
        else { return nil }
        return state
    }

    private func synchronizeTimelineRowStates(items: [TimelineRenderItem], channelID: ChannelID) {
        migrateLocalSendTracking(items: items, channelID: channelID)
        let validIDs = Set(items.map(\.id))
        phase60RowPresentationStates = phase60RowPresentationStates.filter {
            validIDs.contains($0.key) && $0.value.channelID == channelID
        }
        phase60DesiredRowKeys = phase60DesiredRowKeys.filter {
            validIDs.contains($0.key) && $0.value.channelID == channelID
        }
        for item in items {
            let revision = TimelineRowRevision.value(
                for: item.timelineMessage,
                inlineMediaRevision: phase51MediaRevision
            )
            let key = TimelineRowPreparationKey(
                channelID: channelID,
                messageID: item.id,
                revision: revision
            )
            phase60DesiredRowKeys[item.id] = key
            if let state = phase60RowPresentationStates[item.id] {
                let wasPrepared = state.presentation != nil
                state.request(revision: revision)
                let visible = pendingVisibleMessageIDsByChannelID[channelID]
                    ?? visibleMessageIDsByChannelID[channelID]
                    ?? []
                if wasPrepared,
                   state.presentation == nil,
                   visible.contains(item.id) {
                    phase60VisibleSkeletonIDs.insert(item.id)
                }
            } else {
                phase60RowPresentationStates[item.id] = TimelineRowPresentationState(
                    messageID: item.id,
                    channelID: channelID,
                    revision: revision
                )
            }
        }
        let staleQueuedKeys = phase60QueuedRows.keys.filter {
            phase60DesiredRowKeys[$0.messageID] != $0
        }
        for key in staleQueuedKeys {
            phase60QueuedRows[key] = nil
        }
        phase60Diagnostics.staleRowDiscardCount += staleQueuedKeys.count
        phase60Diagnostics.activeSkeletonCount = phase60VisibleSkeletonIDs.count
    }

    /// A locally-sent message keeps its nonce across pending -> confirmed -> realtime-echo
    /// reconciliation, but its real `MessageID` changes at confirmation. Visibility/skeleton
    /// tracking is keyed by that real id (preparation targeting needs it), so move the tracked
    /// entry to the new id directly -- never through `imageResourceBecameHidden`/`Visible`,
    /// which would evict and re-request the avatar resource for no reason.
    private func migrateLocalSendTracking(items: [TimelineRenderItem], channelID: ChannelID) {
        var messageIDByNonce = phase61LocalSendMessageIDByNonce[channelID] ?? [:]
        for item in items {
            guard let nonce = item.timelineMessage.message.nonce else { continue }
            if let previousID = messageIDByNonce[nonce], previousID != item.id {
                if visibleMessageIDsByChannelID[channelID]?.remove(previousID) != nil {
                    visibleMessageIDsByChannelID[channelID]?.insert(item.id)
                }
                if pendingVisibleMessageIDsByChannelID[channelID]?.remove(previousID) != nil {
                    pendingVisibleMessageIDsByChannelID[channelID]?.insert(item.id)
                }
                phase60VisibleSkeletonIDs.remove(previousID)
            }
            messageIDByNonce[nonce] = item.id
        }
        let currentNonces = Set(items.compactMap { $0.timelineMessage.message.nonce })
        phase61LocalSendMessageIDByNonce[channelID] = messageIDByNonce.filter { currentNonces.contains($0.key) }
    }

    private func initialTimelinePreparationAnchor() -> MessageID? {
        switch timelineViewport.pendingScrollIntent {
        case let .message(messageID, _, _):
            return messageID
        case let .firstUnread(messageID):
            return messageID
        case let .preservePositionAfterPrepend(messageID), let .preserveVisibleAnchor(messageID):
            return messageID
        case .newest, .none:
            break
        }
        guard let channelID = selectedConversationChannelID else { return nil }
        return firstUnreadMessageID(for: channelID)
    }

    private func enqueueTimelineRowPreparation(
        _ targets: [TimelineRowPreparationTarget],
        channelID: ChannelID
    ) {
        guard channelID == selectedConversationChannelID else { return }
        let itemsByID = Dictionary(uniqueKeysWithValues: selectedTimelineRenderItems.map { ($0.id, $0) })
        for target in targets {
            guard let item = itemsByID[target.messageID],
                  let key = phase60DesiredRowKeys[target.messageID],
                  key.channelID == channelID,
                  let state = phase60RowPresentationStates[target.messageID]
            else { continue }
            phase60Diagnostics.rowRequestCount += 1
            if state.revision == key.revision, state.presentation != nil {
                phase60Diagnostics.rowDedupeCount += 1
                continue
            }
            if phase60ActiveRowKey == key {
                phase60Diagnostics.rowDedupeCount += 1
                continue
            }
            if var queued = phase60QueuedRows[key] {
                if target.priority.rawValue < queued.priority.rawValue {
                    queued.priority = target.priority
                    phase60QueuedRows[key] = queued
                }
                phase60Diagnostics.rowDedupeCount += 1
                continue
            }

            let message = item.timelineMessage.message
            let channel = snapshot.channelsByID[message.channelID]
            let permissions = channel?.permissions ?? channel?.serverID.flatMap {
                snapshot.serversByID[$0]?.defaultPermissions
            }
            phase60RowQueueSequence &+= 1
            phase60QueuedRows[key] = Phase60QueuedRowPreparation(
                key: key,
                timelineMessage: item.timelineMessage,
                priority: target.priority,
                sequence: phase60RowQueueSequence,
                snapshot: snapshot,
                identitySnapshots: phase43IdentitySnapshots,
                imageDataByKey: loadedImageResources,
                customEmojiIndex: phase68CustomEmojiIndexValue(),
                currentUserID: currentUserID,
                permissions: permissions,
                isRuntimeSendCapable: isRuntimeSendCapable,
                developerControlsEnabled: isDeveloperControlsEnabled
            )
            phase60Diagnostics.maximumQueueDepth = max(
                phase60Diagnostics.maximumQueueDepth,
                phase60QueuedRows.count + (phase60ActiveRowKey == nil ? 0 : 1)
            )
        }
        startTimelineRowPreparationWorkerIfNeeded()
    }

    private func startTimelineRowPreparationWorkerIfNeeded() {
        guard phase60RowWorkerTask == nil, !phase60QueuedRows.isEmpty else { return }
        phase60RowWorkerTask = Task { [weak self] in
            await self?.drainTimelineRowPreparationQueue()
        }
    }

    private func drainTimelineRowPreparationQueue() async {
        defer {
            phase60ActiveRowKey = nil
            phase60RowWorkerTask = nil
            if !phase60QueuedRows.isEmpty {
                startTimelineRowPreparationWorkerIfNeeded()
            }
        }
        while !Task.isCancelled {
            guard let next = phase60QueuedRows.values.min(by: {
                if $0.priority.rawValue != $1.priority.rawValue {
                    return $0.priority.rawValue < $1.priority.rawValue
                }
                return $0.sequence < $1.sequence
            }) else { return }
            phase60QueuedRows[next.key] = nil
            phase60ActiveRowKey = next.key
            let worker = Task.detached(priority: .userInitiated) {
                Phase60TimelineRowPreparer.prepare(
                    timelineMessage: next.timelineMessage,
                    snapshot: next.snapshot,
                    identitySnapshots: next.identitySnapshots,
                    imageDataByKey: next.imageDataByKey,
                    customEmojiIndex: next.customEmojiIndex,
                    currentUserID: next.currentUserID,
                    permissions: next.permissions,
                    isRuntimeSendCapable: next.isRuntimeSendCapable,
                    developerControlsEnabled: next.developerControlsEnabled
                )
            }
            let presentation = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard !Task.isCancelled else { return }
            guard selectedConversationChannelID == next.key.channelID,
                  phase60DesiredRowKeys[next.key.messageID] == next.key,
                  let state = phase60RowPresentationStates[next.key.messageID],
                  state.channelID == next.key.channelID,
                  state.revision == next.key.revision
            else {
                phase60Diagnostics.staleRowDiscardCount += 1
                continue
            }
            if phase60VisibleSkeletonIDs.remove(next.key.messageID) != nil {
                phase60Diagnostics.activeSkeletonCount = max(
                    0,
                    phase60Diagnostics.activeSkeletonCount - 1
                )
            }
            state.publish(presentation, revision: next.key.revision)
            phase60Diagnostics.rowCompletionCount += 1
            phase60ActiveRowKey = nil
        }
    }

    private func requestVisibleTimelineRows() {
        guard let channelID = selectedConversationChannelID else { return }
        let visibleIDs = pendingVisibleMessageIDsByChannelID[channelID] ?? []
        enqueueTimelineRowPreparation(
            TimelineRowPreparationPlanner.visibleTargets(
                items: selectedTimelineRenderItems,
                visibleMessageIDs: visibleIDs
            ),
            channelID: channelID
        )
    }

    public func timelineSkeletonVisibilityChanged(messageID: MessageID, isVisible: Bool) {
        if isVisible {
            guard phase60RowPresentationStates[messageID]?.presentation == nil,
                  phase60VisibleSkeletonIDs.insert(messageID).inserted
            else { return }
            phase60Diagnostics.activeSkeletonCount = phase60VisibleSkeletonIDs.count
        } else {
            phase60VisibleSkeletonIDs.remove(messageID)
            phase60Diagnostics.activeSkeletonCount = phase60VisibleSkeletonIDs.count
        }
    }

    private func resetPhase60TimelineWork(previousChannelID: ChannelID?) {
        if let previousChannelID {
            visibleRangeUpdateTasks[previousChannelID]?.cancel()
            visibleRangeUpdateTasks[previousChannelID] = nil
            pendingVisibleMessageIDsByChannelID[previousChannelID] = nil
        }
        phase60Diagnostics.staleRowDiscardCount += phase60QueuedRows.count
            + (phase60ActiveRowKey == nil ? 0 : 1)
        phase60RowWorkerTask?.cancel()
        phase60ActiveRowKey = nil
        phase60QueuedRows.removeAll(keepingCapacity: true)
        phase60DesiredRowKeys.removeAll(keepingCapacity: true)
        phase60RowPresentationStates.removeAll(keepingCapacity: true)
        phase60VisibleSkeletonIDs.removeAll(keepingCapacity: true)
        selectedTimelineRenderItemCache.removeAll(keepingCapacity: true)
        phase60Diagnostics.activeSkeletonCount = 0
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
        Phase30ParityMatrixBuilder.build()
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
        let sessionUser = sessionCoordinator?.currentUser ?? currentUser
        if let currentUserID, var user = snapshot.usersByID[currentUserID] {
            // Gateway events can wholesale-replace the snapshot user with a partial object that
            // omits identity fields. Presence/status must keep flowing from the snapshot, but
            // nil identity fields fill from the authenticated ready user -- otherwise the server
            // rail renders initials forever even though the avatar bytes are already cached.
            if let sessionUser, sessionUser.id == user.id {
                if user.avatar == nil {
                    user.avatar = sessionUser.avatar
                }
                if user.displayName == nil {
                    user.displayName = sessionUser.displayName
                }
            }
            return user
        }
        return sessionUser
    }

    public var profilePresentationUser: User? {
        guard let profileUserID else { return nil }
        if let user = snapshot.usersByID[profileUserID] {
            return user
        }
        if profileUserID == currentUser?.id {
            return currentUser
        }
        if let identity = phase43IdentitySnapshots.snapshot(for: profileUserID) {
            let username = identity.username ?? identity.displayName ?? "unknown"
            return User(id: profileUserID, username: username, displayName: identity.displayName ?? identity.username, avatar: identity.avatarFile, bot: identity.isBot ? BotInformation(ownerID: identity.botOwnerID) : nil)
        }
        return User(id: profileUserID, username: "unknown", displayName: "Unknown member")
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
            botOwnerID: user?.bot?.ownerID ?? phase43IdentitySnapshots.snapshot(for: userID)?.botOwnerID
        )
    }

    public func setPhase43NowProvider(_ provider: @escaping () -> Date) {
        phase43Now = provider
    }

    public func phase43IdentitySnapshot(for userID: UserID) -> Phase43IdentitySnapshot? {
        phase43IdentitySnapshots.snapshot(for: userID)
    }

    public func noteVisibleIdentity(
        userID: UserID,
        user: User? = nil,
        member: ServerMember? = nil,
        serverID: ServerID? = nil,
        source: Phase43IdentityHydrationSource
    ) {
        if let user {
            mergePhase43User(user, source: source == .visibleMember ? .readyUser : .messageUser)
        }
        if let member {
            mergePhase43Member(member, user: user, source: source == .visibleMember ? .readyMember : .messageMember)
        }
        let server = serverID.flatMap { snapshot.serversByID[$0] }
        let resolved = phase43IdentitySnapshots.resolvedDisplay(userID: userID, user: user ?? snapshot.usersByID[userID], member: member, server: server)
        if resolved.isFallback {
            enqueuePhase43IdentityHydrationIfNeeded(userID, source: source)
        }
    }
    
    // MARK: - Private Helper Methods

    private func mergePhase43SnapshotIdentities(_ snapshot: RealtimeSnapshot, source: Phase43IdentitySource) {
        for user in snapshot.usersByID.values {
            mergePhase43User(user, source: source)
        }
        for member in snapshot.membersByServerAndUserID.values {
            mergePhase43Member(member, user: snapshot.usersByID[member.id.userID], source: source == .readyUser ? .readyMember : source)
        }
    }

    private func mergePhase43User(_ user: User, source: Phase43IdentitySource) {
        let before = phase43IdentitySnapshots.snapshot(for: user.id)
        let previousAvatar = phase43IdentitySnapshots.snapshot(for: user.id)?.avatarFile
        applyPhase43AvatarCacheTransition(
            .resolve(previous: previousAvatar, incoming: user.avatar, source: source),
            userID: user.id
        )
        if phase43IdentitySnapshots.merge(user: user, source: source, now: phase43Now()) {
            phase43IdentityGeneration = phase43IdentitySnapshots.generation
            updatePhase68MemberIdentityRevisions(
                before: before,
                after: phase43IdentitySnapshots.snapshot(for: user.id)
            )
        } else {
            phase68TraceDiagnostics.identityNoOpMergeCount += 1
        }
    }

    private func mergePhase43Member(_ member: ServerMember, user: User?, source: Phase43IdentitySource) {
        let before = phase43IdentitySnapshots.snapshot(for: member.id.userID)
        let previousAvatar = phase43IdentitySnapshots.snapshot(for: member.id.userID)?
            .serverOverlays[member.id.serverID]?.avatarFile
        applyPhase43ServerAvatarCacheTransition(
            .resolve(previous: previousAvatar, incoming: member.avatar, source: source)
        )
        if phase43IdentitySnapshots.merge(member: member, user: user, source: source, now: phase43Now()) {
            phase43IdentityGeneration = phase43IdentitySnapshots.generation
            updatePhase68MemberIdentityRevisions(
                before: before,
                after: phase43IdentitySnapshots.snapshot(for: member.id.userID),
                including: [member.id.serverID]
            )
        } else {
            phase68TraceDiagnostics.identityNoOpMergeCount += 1
        }
    }

    private func mergePhase43MessageIdentity(_ message: Message) {
        if let user = message.user {
            mergePhase43User(user, source: .messageUser)
        }
        if let member = message.member {
            mergePhase43Member(member, user: message.user ?? snapshot.usersByID[message.authorID], source: .messageMember)
        }
    }

    private func mergePhase43Profile(_ profile: UserProfile, userID: UserID) {
        if phase43IdentitySnapshots.merge(profile: profile, userID: userID, now: phase43Now()) {
            phase43IdentityGeneration = phase43IdentitySnapshots.generation
        } else {
            phase68TraceDiagnostics.identityNoOpMergeCount += 1
        }
    }

    private func preservePhase43IdentityBeforeMemberRemoval(serverID: ServerID, userID: UserID) {
        let member = snapshot.membersByServerAndUserID[ServerMemberKey(serverID: serverID, userID: userID)]
        let user = snapshot.usersByID[userID] ?? (userID == currentUser?.id ? currentUser : nil)
        if let user {
            mergePhase43User(user, source: .moderationAction)
        }
        if let member {
            let beforeAvatar = phase43IdentitySnapshots.snapshot(for: userID)?.avatarFile
            mergePhase43Member(member, user: user, source: .moderationAction)
            if beforeAvatar == nil, phase43IdentitySnapshots.snapshot(for: userID)?.avatarFile != nil {
                phase43AvatarMetadataPreservedAfterMemberRemovalCount += 1
            }
        }
        let beforeRemoval = phase43IdentitySnapshots.snapshot(for: userID)
        if phase43IdentitySnapshots.markMemberRemoved(userID: userID, serverID: serverID, now: phase43Now()) {
            phase43MemberRemovalIdentityPreservationCount += 1
            phase43IdentityGeneration = phase43IdentitySnapshots.generation
            updatePhase68MemberIdentityRevisions(
                before: beforeRemoval,
                after: phase43IdentitySnapshots.snapshot(for: userID),
                including: [serverID]
            )
        } else {
            phase68TraceDiagnostics.identityNoOpMergeCount += 1
        }
    }

    private func updatePhase68MemberIdentityRevisions(
        before: Phase43IdentitySnapshot?,
        after: Phase43IdentitySnapshot?,
        including serverIDs: Set<ServerID> = []
    ) {
        var affectedServerIDs = serverIDs
        if let before {
            affectedServerIDs.formUnion(before.serverOverlays.keys)
        }
        if let after {
            affectedServerIDs.formUnion(after.serverOverlays.keys)
        }
        for serverID in affectedServerIDs where
            Phase68MemberIdentityPresentationSignature(snapshot: before, serverID: serverID)
                != Phase68MemberIdentityPresentationSignature(snapshot: after, serverID: serverID) {
            advanceMemberIdentityPresentationRevision(for: serverID)
        }
    }

    private func advanceMemberIdentityPresentationRevision(for serverID: ServerID) {
        phase68MemberIdentityRevisionByServerID[serverID, default: 0] &+= 1
        phase68TraceDiagnostics.memberListRelevantInvalidationCount += 1
        guard selection.serverID == serverID else { return }
        selectedMemberListPublicationRevision &+= 1
        phase68TraceDiagnostics.selectedMemberListPublicationCount += 1
    }

    private func preserveRemovedRealtimeMemberIdentities(previous: RealtimeSnapshot, current: RealtimeSnapshot) {
        let previousKeys = Set(previous.membersByServerAndUserID.keys)
        let currentKeys = Set(current.membersByServerAndUserID.keys)
        for key in previousKeys.subtracting(currentKeys) {
            if let member = previous.membersByServerAndUserID[key] {
                mergePhase43Member(member, user: previous.usersByID[key.userID], source: .realtimeMemberUpdate)
            }
            let before = phase43IdentitySnapshots.snapshot(for: key.userID)
            if phase43IdentitySnapshots.markMemberRemoved(userID: key.userID, serverID: key.serverID, now: phase43Now()) {
                phase43MemberRemovalIdentityPreservationCount += 1
                phase43IdentityGeneration = phase43IdentitySnapshots.generation
                updatePhase68MemberIdentityRevisions(
                    before: before,
                    after: phase43IdentitySnapshots.snapshot(for: key.userID),
                    including: [key.serverID]
                )
            } else {
                phase68TraceDiagnostics.identityNoOpMergeCount += 1
            }
        }
    }

    private func applyPhase43AvatarCacheTransition(
        _ transition: Phase43AvatarCacheTransition,
        userID: UserID
    ) {
        switch transition {
        case .preserve:
            return
        case let .replace(previous, next):
            if userID == currentUserID,
               visibleImageResourceRequestsByConsumer["shell-current-user-avatar"] != nil,
               let request = imageResourceRequest(for: next, kind: .userAvatar) {
                visibleImageResourceRequestsByConsumer["shell-current-user-avatar"] = request
                enqueueImageResourceRequest(request, priority: .visibleMember)
            }
            if let previous {
                invalidatePhase43AvatarCache(previous)
            }
        case let .remove(previous):
            if userID == currentUserID {
                visibleImageResourceRequestsByConsumer.removeValue(forKey: "shell-current-user-avatar")
            }
            invalidatePhase43AvatarCache(previous)
        }
    }

    private func invalidatePhase43AvatarCache(_ file: File) {
        let key = ImageCacheKey(id: file.id.rawValue, kind: .userAvatar)
        removeImagePresentationData(for: key)
        imageResourceStates.removeValue(forKey: key)
        imageResourceFailureDates.removeValue(forKey: key)
        queuedImageResourceRequests.removeValue(forKey: key)
        imageResourceLoadTasks[key]?.cancel()
        imageResourceLoadTasks.removeValue(forKey: key)
        Task { await imageMemoryCache.remove(key) }
    }

    private func applyPhase43ServerAvatarCacheTransition(_ transition: Phase43ServerAvatarCacheTransition) {
        switch transition {
        case .preserve:
            return
        case let .replace(previous, _):
            if let previous {
                invalidatePhase43AvatarCache(previous)
            }
        case let .remove(previous):
            invalidatePhase43AvatarCache(previous)
        }
    }

    public func enqueuePhase43IdentityHydration(userID: UserID, source: Phase43IdentityHydrationSource = .visibleMessage) {
        enqueuePhase43IdentityHydrationIfNeeded(userID, source: source)
    }

    private func enqueuePhase43IdentityHydrationIfNeeded(_ userID: UserID, source: Phase43IdentityHydrationSource) {
        guard !phase43IdentitySnapshots.hasReadableIdentity(for: userID),
              snapshot.usersByID[userID] == nil,
              currentUser?.id != userID,
              sessionCoordinator?.currentUser?.id != userID
        else { return }
        if phase43QueuedIdentityHydration[userID] != nil || phase43IdentityHydrationTasks[userID] != nil {
            phase43IdentityHydrationDedupeHits += 1
            updateVisibleIdentityDiagnostics()
            return
        }
        if let failure = phase43IdentityHydrationFailuresByUserID[userID],
           failure.cooldownUntil > phase43Now() {
            phase43IdentityHydrationCooldownSkips += 1
            updateVisibleIdentityDiagnostics()
            return
        }
        guard phase43QueuedIdentityHydration.count < phase43HydrationPolicy.maxBatchEnqueue else {
            phase43IdentityHydrationDedupeHits += 1
            updateVisibleIdentityDiagnostics()
            return
        }
        phase43QueuedIdentityHydration[userID] = source
        updateVisibleIdentityDiagnostics()
        drainPhase43IdentityHydrationQueue()
    }

    private func drainPhase43IdentityHydrationQueue() {
        while phase43IdentityHydrationTasks.count < phase43HydrationPolicy.maxConcurrentFetches,
              let next = phase43QueuedIdentityHydration.first {
            phase43QueuedIdentityHydration.removeValue(forKey: next.key)
            let userID = next.key
            phase43IdentityHydrationTasks[userID] = Task { [weak self] in
                await self?.loadPhase43Identity(userID: userID)
            }
        }
        updateVisibleIdentityDiagnostics()
    }

    private func loadPhase43Identity(userID: UserID) async {
        defer {
            phase43IdentityHydrationTasks[userID] = nil
            drainPhase43IdentityHydrationQueue()
        }
        guard let apiClient = apiClientForPhase43IdentityHydration() else {
            recordPhase43IdentityHydrationFailure(userID: userID)
            return
        }
        do {
            var user = try await apiClient.fetchUser(userID: userID)
            if let existingUser = snapshot.usersByID[userID] {
                // A single-user profile REST fetch can lag behind the gateway's live
                // presence; the gateway is never staler while connected, so don't let this
                // regress an already-known user's online/status (previously caused offline
                // members to show a stale green presence dot after their profile loaded).
                user.online = existingUser.online
                user.status = existingUser.status
            }
            upsertUser(user, source: .hydrationFetch)
            phase43IdentityHydrationFailuresByUserID.removeValue(forKey: userID)
            phase43IdentityHydrationSuccessCount += 1
        } catch is CancellationError {
            return
        } catch {
            recordPhase43IdentityHydrationFailure(userID: userID)
        }
    }

    private func recordPhase43IdentityHydrationFailure(userID: UserID) {
        let previous = phase43IdentityHydrationFailuresByUserID[userID]?.count ?? 0
        let count = previous + 1
        let cooldown = phase43HydrationPolicy.cooldownInterval(afterFailureCount: count)
        phase43IdentityHydrationFailuresByUserID[userID] = (count, phase43Now().addingTimeInterval(cooldown))
        phase43IdentityHydrationFailureCount += 1
        updateVisibleIdentityDiagnostics()
    }

    private func apiClientForPhase43IdentityHydration() -> (any StoatAPIClient)? {
        sessionCoordinator?.apiClient ?? (effectiveRuntimeMode == .mock ? communityAPIClient : nil)
    }

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
        if let orderedIDs = server?.channelIDs, !orderedIDs.isEmpty {
            return orderedIDs.compactMap { snapshot.channelsByID[$0] }
        }
        return snapshot.channelsByID.values
            .filter { $0.serverID == serverID }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
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
        guard let serverID, let server = snapshot.serversByID[serverID] else { return [] }
        let key = memberListCacheKey(serverID: serverID, query: query)
        if key == memberListGroupCacheKey {
            return memberListGroupCache
        }
        let started = Date()
        let result = MemberListDeriver.result(server: server, snapshot: snapshot, query: query)
        let groups = result.groups.map { group in
            MemberListGroup(
                id: group.id,
                title: group.title,
                items: group.items.map { item in
                    let display = phase43IdentitySnapshots.resolvedDisplay(
                        userID: item.userID,
                        user: item.user,
                        member: item.member,
                        server: server
                    )
                    return MemberListItem(
                        userID: item.userID,
                        user: item.user,
                        member: item.member,
                        display: display,
                        server: server
                    )
                }
            )
        }
        memberGroupingCount += 1
        memberListGroupCacheKey = key
        memberListGroupCache = groups
        memberListGroupsRevision &+= 1
        memberListDiagnosticsCache = result.diagnostics
        memberRoleSortDiagnostics = result.diagnostics
        memberListLastGroupingElapsed = Date().timeIntervalSince(started)
        memberListLastGroupingServerID = serverID
        let knownMembers = snapshot.membersByServerAndUserID.values.filter { $0.id.serverID == serverID }
        let renderedCount = groups.reduce(0) { $0 + $1.items.count }
        memberListPerformanceDiagnostics = MemberListPerformanceDiagnostics(
            totalMembers: knownMembers.count,
            visibleMemberEstimate: renderedCount,
            groupCount: groups.count,
            avatarLoadQueueCount: imageResourceQueueCount,
            lastGroupingDurationDescription: String(format: "%.3f s", memberListLastGroupingElapsed),
            knownMemberCount: knownMembers.count,
            knownUserCount: snapshot.usersByID.count,
            missingUserCount: knownMembers.filter { snapshot.usersByID[$0.id.userID] == nil }.count,
            missingAvatarCount: groups.flatMap(\.items).filter { $0.avatar == nil }.count,
            renderedMemberCount: renderedCount,
            droppedMemberCount: max(0, knownMembers.count - renderedCount),
            droppedReasonSummary: "No members dropped"
        )
        return groups
    }

    public var memberListPresentationToken: String {
        guard let serverID = selection.serverID else { return "none" }
        let key = memberListCacheKey(serverID: serverID, query: "")
        return "\(serverID.rawValue)|\(key.membersFingerprint)|\(key.presentationRevision)|\(selectedMemberListPublicationRevision)"
    }

    public func cachedMemberListGroups(for serverID: ServerID?) -> [MemberListGroup] {
        guard let serverID, memberListLastGroupingServerID == serverID else { return [] }
        return memberListGroupCache
    }

    public func prepareMemberListGroups(for serverID: ServerID?, query: String = "") async {
        guard let serverID, let server = snapshot.serversByID[serverID] else { return }
        let key = memberListCacheKey(serverID: serverID, query: query)
        if key == memberListGroupCacheKey {
            memberGroupingCacheHitCount += 1
            return
        }
        let inputSnapshot = snapshot
        let inputIdentities = phase43IdentitySnapshots
        let worker = Task.detached(priority: .userInitiated) {
            try Phase52MemberListPreparer.prepare(
                server: server,
                snapshot: inputSnapshot,
                identitySnapshots: inputIdentities,
                query: query
            )
        }
        let preparation: Phase52MemberListPreparation
        do {
            preparation = try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: {
                worker.cancel()
            }
        } catch {
            return
        }
        guard !Task.isCancelled,
              selection.serverID == serverID,
              memberListCacheKey(serverID: serverID, query: query) == key
        else { return }
        memberListGroupCacheKey = key
        memberListGroupCache = preparation.groups
        memberListGroupsRevision &+= 1
        memberListLastGroupingServerID = serverID
        memberListDiagnosticsCache = preparation.roleDiagnostics
        memberRoleSortDiagnostics = preparation.roleDiagnostics
        memberGroupingCount += 1
        let total = preparation.groups.reduce(0) { $0 + $1.items.count }
        memberListPerformanceDiagnostics = MemberListPerformanceDiagnostics(
            totalMembers: total,
            visibleMemberEstimate: min(total, 80),
            groupCount: preparation.groups.count,
            avatarLoadQueueCount: imageResourceQueueCount,
            lastGroupingDurationDescription: "\(preparation.durationMilliseconds)ms",
            knownMemberCount: preparation.knownMemberCount,
            knownUserCount: preparation.knownUserCount,
            missingUserCount: preparation.missingUserCount,
            missingAvatarCount: preparation.missingAvatarCount,
            renderedMemberCount: total,
            droppedMemberCount: max(0, preparation.knownMemberCount - total),
            droppedReasonSummary: "Prepared off main; missing avatars \(preparation.missingAvatarCount)"
        )
        updateVisibleIdentityDiagnostics()
        updateFreezePerformanceDiagnostics(marker: "member grouping prepared off main")
    }

    private func scheduleDeferredMemberDiagnosticsPublish() {
        guard !memberDiagnosticsPublishPending else { return }
        memberDiagnosticsPublishPending = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.memberDiagnosticsPublishPending = false
            self.flushMemberDiagnostics()
        }
    }

    private func flushMemberDiagnostics() {
        if memberListLastCacheHit {
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
        } else if let serverID = memberListLastGroupingServerID {
            let groups = memberListGroupCache
            memberRoleSortDiagnostics = memberListDiagnosticsCache
            let knownMemberCount = snapshot.membersByServerAndUserID.values.filter { $0.id.serverID == serverID }.count
            let knownUserCount = snapshot.usersByID.count
            let missingUserCount = snapshot.membersByServerAndUserID.values.filter { $0.id.serverID == serverID && snapshot.usersByID[$0.id.userID] == nil }.count
            let missingAvatarCount = groups.flatMap(\.items).filter { $0.avatar == nil }.count
            let total = groups.reduce(0) { $0 + $1.items.count }
            let dropped = max(0, knownMemberCount - total)
            let elapsedMs = "\(Int(memberListLastGroupingElapsed * 1000))ms"
            memberListPerformanceDiagnostics = MemberListPerformanceDiagnostics(
                totalMembers: total,
                visibleMemberEstimate: min(total, 80),
                groupCount: groups.count,
                avatarLoadQueueCount: imageResourceQueueCount,
                lastGroupingDurationDescription: elapsedMs,
                knownMemberCount: knownMemberCount,
                knownUserCount: knownUserCount,
                missingUserCount: missingUserCount,
                missingAvatarCount: missingAvatarCount,
                renderedMemberCount: total,
                droppedMemberCount: dropped,
                droppedReasonSummary: dropped == 0 ? "missing avatars \(missingAvatarCount)" : "Filtered by query; missing avatars \(missingAvatarCount)"
            )
            updateVisibleIdentityDiagnostics()
            updateFreezePerformanceDiagnostics(marker: "member grouping \(elapsedMs)")
        } else {
            memberListPerformanceDiagnostics = MemberListPerformanceDiagnostics(avatarLoadQueueCount: imageResourceQueueCount)
            updateFreezePerformanceDiagnostics(marker: nil)
        }
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
                guard let self else { return }
                let inputSnapshot = self.snapshot
                let inputIdentities = self.phase43IdentitySnapshots
                let started = ContinuousClock.now
                let worker = Task.detached(priority: .userInitiated) {
                    try Phase52MemberHydrationPreparer.prepare(
                        serverID: serverID,
                        response: response,
                        snapshot: inputSnapshot,
                        identitySnapshots: inputIdentities
                    )
                }
                let preparation = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                guard !Task.isCancelled else { return }
                self.finishMemberHydration(
                    serverID: serverID,
                    generation: generation,
                    requestedCount: requestedCount,
                    response: response,
                    preparation: preparation,
                    preparationStarted: started,
                    reason: reason
                )
            } catch is CancellationError {
                self?.discardStaleMemberHydration(serverID: serverID, generation: generation)
            } catch {
                self?.failMemberHydration(
                    serverID: serverID,
                    generation: generation,
                    requestedCount: requestedCount,
                    error: error,
                    forced: force
                )
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
        preparation: Phase52MemberHydrationPreparation,
        preparationStarted: ContinuousClock.Instant,
        reason: String
    ) {
        guard memberHydrationGenerations[serverID] == generation,
              isMemberHydrationContextCurrent(serverID: serverID)
        else {
            discardStaleMemberHydration(serverID: serverID, generation: generation)
            return
        }

        let commitStarted = ContinuousClock.now
        phase43IdentitySnapshots = preparation.identitySnapshots
        phase43IdentityGeneration = preparation.identitySnapshots.generation
        advanceMemberIdentityPresentationRevision(for: serverID)
        for key in preparation.invalidatedAvatarKeys {
            removeImagePresentationData(for: key)
            imageResourceStates.removeValue(forKey: key)
            imageResourceFailureDates.removeValue(forKey: key)
            queuedImageResourceRequests.removeValue(forKey: key)
            imageResourceLoadTasks[key]?.cancel()
            imageResourceLoadTasks.removeValue(forKey: key)
            Task { await imageMemoryCache.remove(key) }
        }
        memberWrapperUserMergeCount += response.users.count
        snapshot = preparation.snapshot
        phase52FreezeDiagnostics.snapshotInstallCount += 1
        phase52FreezeDiagnostics.memberHydrationCommitCount += 1
        phase52FreezeDiagnostics.identityBatchCommitCount += 1
        restHydratedMembersByServerID[serverID] = preparation.returnedMembersByKey
        restHydratedUsersByServerID[serverID] = preparation.returnedUsersByID
        hydratedMemberServerIDs.insert(serverID)
        memberHydrationTasks[serverID] = nil
        memberHydrationLoadingServerIDs.remove(serverID)
        memberHydrationErrorsByServerID[serverID] = nil
        memberListGroupCacheKey = nil
        updateVisibleIdentityDiagnostics()

        let dropped = max(0, preparation.previousMemberCount - preparation.returnedMembersByKey.count)
        memberHydrationDiagnostics = MemberHydrationDiagnostics(
            source: .restHydrated,
            lastMemberFetchServerID: serverID,
            requestedCount: requestedCount,
            returnedCount: response.members.count,
            mergedMemberCount: preparation.returnedMembersByKey.count,
            mergedUserCount: response.users.count,
            missingUserCount: preparation.missingUserCount,
            droppedCount: dropped,
            staleFetchDiscarded: false,
            isLoading: false,
            error: nil,
            apiDiagnostics: response.diagnostics,
            lastUpdatedAt: Date()
        )
        let preparationDuration = preparationStarted.duration(to: .now)
        phase52FreezeDiagnostics.lastMemberPreparationMilliseconds = Self.milliseconds(preparationDuration)
        let commitMilliseconds = Self.milliseconds(commitStarted.duration(to: .now))
        if commitMilliseconds > 50 {
            phase52FreezeDiagnostics.mainThreadBudgetViolationCount += 1
        }
        placeholderStatus = "Refreshed \(preparation.returnedMembersByKey.count) members and \(response.users.count) users."
        loadVisibleIdentityImagesForCurrentSelection()
        if reason == "manual refresh" {
            lastServerSettingsButtonAction = "Member refresh completed"
        }
    }

    private static func milliseconds(_ duration: Duration) -> Int {
        Int(duration.components.seconds * 1_000)
            + Int(duration.components.attoseconds / 1_000_000_000_000_000)
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
        guard !messages.isEmpty else { return [] }
        if timelineGroupingCacheKey() == selectedTimelineGroupCacheKey {
            return selectedTimelineGroupCache
        }
        // First paint must not wait for the detached presentation pass. Histories are capped
        // at 250 messages, so this small pure grouping pass is cheap enough to render a newly
        // selected channel or optimistic send immediately. The asynchronous preparer still
        // owns the persistent cache and all heavier row presentation work.
        return TimelineMessageGrouping.group(messages)
    }

    private func timelineGroupingCacheKey() -> String {
        guard let channelID = selectedConversationChannelID else { return "none" }
        return "\(channelID.rawValue)|\(messageController.presentationRevision(for: channelID))"
    }

    private func timelineRowPresentationCacheKeyValue() -> String {
        "\(timelineGroupingCacheKey())|\(snapshotRevision)|\(phase51MediaRevision)|\(phase43IdentityGeneration)|\(isRuntimeSendCapable)"
    }

    private func invalidateTimelineMediaPresentation() {
        phase51MediaRevision &+= 1
        timelineRowPresentationCacheKey = nil
    }

    /// Coalesces a burst of media-load completions (custom emoji/reactions still baked into
    /// the row cache) into a single timeline row rebuild instead of one per image. Without
    /// this, loading N images in a media-heavy channel forced N full timeline row rebuilds.
    /// Uses a pending flag + a single `Task.yield()` hop (no timers/sleep) so any number of
    /// synchronous store/remove calls within one main-actor turn collapse into one rebuild.
    private func scheduleTimelineMediaInvalidation() {
        guard !pendingTimelineMediaInvalidation else { return }
        pendingTimelineMediaInvalidation = true
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, self.pendingTimelineMediaInvalidation else { return }
            self.pendingTimelineMediaInvalidation = false
            self.timelineMediaInvalidationCount += 1
            self.invalidateTimelineMediaPresentation()
        }
    }

    private struct MemberListCacheKey: Hashable {
        let serverID: ServerID
        let normalizedQuery: String
        let membersFingerprint: Int
        let presentationRevision: Int
    }

    private func memberListCacheKey(serverID: ServerID, query: String) -> MemberListCacheKey {
        MemberListCacheKey(
            serverID: serverID,
            normalizedQuery: query,
            membersFingerprint: memberListFingerprint(for: serverID),
            presentationRevision: phase68MemberIdentityRevisionByServerID[serverID, default: 0]
        )
    }

    /// Cheap, order-independent digest of the member/role fields that actually affect
    /// grouping and sort order, so unrelated snapshot churn (e.g. new messages) doesn't
    /// force a full re-derivation of a multi-thousand-member list.
    private func memberListFingerprint(for serverID: ServerID) -> Int {
        guard let server = snapshot.serversByID[serverID] else { return 0 }
        var combined = 0
        for member in snapshot.membersByServerAndUserID.values where member.id.serverID == serverID {
            let user = snapshot.usersByID[member.id.userID]
            var hasher = Hasher()
            hasher.combine(member.id.userID)
            hasher.combine(user?.online ?? false)
            hasher.combine(user?.status)
            hasher.combine(user?.username)
            hasher.combine(user?.displayName)
            hasher.combine(member.nickname)
            hasher.combine(member.roles)
            hasher.combine(user?.bot != nil)
            combined ^= hasher.finalize()
        }
        var roleHasher = Hasher()
        roleHasher.combine(server.ownerID)
        for role in server.roles.values.sorted(by: { $0.id.rawValue < $1.id.rawValue }) {
            roleHasher.combine(role.id)
            roleHasher.combine(role.name)
            roleHasher.combine(role.rank)
            roleHasher.combine(role.hoist)
            // A colour-only role edit must re-derive the member list, or rows keep rendering the
            // stale colour until an unrelated change lands (latent pre-Phase 63 bug).
            roleHasher.combine(role.colour)
        }
        combined ^= roleHasher.finalize()
        return combined
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
            if message.message.system != nil {
                if let target = Phase27SystemEventPresenter.profileTarget(for: message.message),
                   systemEventProfileTarget(for: message.message) == nil {
                    ids.insert(target)
                }
            } else if resolvedUserDisplay(for: message.message).isFallback {
                ids.insert(message.message.authorID)
            }
        }
        if let channel = selectedConversationChannel, DMChannelClassifier.isDirectMessageLike(channel) {
            for id in channel.recipients where resolvedUserDisplay(for: snapshot.usersByID[id], fallbackID: id).isFallback {
                ids.insert(id)
            }
        }
        if let serverID = selection.serverID {
            for member in snapshot.membersByServerAndUserID.values where member.id.serverID == serverID && resolvedUserDisplay(for: snapshot.usersByID[member.id.userID], member: member, fallbackID: member.id.userID, serverID: serverID).isFallback {
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
            let user = snapshot.usersByID[member.id.userID]
            let display = resolvedUserDisplay(for: user, member: member, fallbackID: member.id.userID, serverID: member.id.serverID)
            return MemberManagementItem(member: member, user: user, display: display, server: details.server)
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
        switch friendsTab {
        case .online:
            shellPresentationSnapshot.allFriendItems.filter { $0.relationshipStatus == .friend && $0.isOnline }
        case .all:
            shellPresentationSnapshot.allFriendItems.filter { $0.relationshipStatus == .friend }
        case .pending:
            shellPresentationSnapshot.allFriendItems.filter { $0.relationshipStatus == .incoming || $0.relationshipStatus == .outgoing }
        case .blocked:
            shellPresentationSnapshot.allFriendItems.filter { $0.relationshipStatus == .blocked }
        case .addFriend:
            []
        }
    }

    public var allFriendItems: [FriendListItem] {
        shellPresentationSnapshot.allFriendItems
    }

    public var directMessageItems: [DirectMessageListItem] {
        shellPresentationSnapshot.directMessageItems
    }

    public var incomingFriendRequestCount: Int {
        shellPresentationSnapshot.allFriendItems.filter { $0.relationshipStatus == .incoming }.count
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

    /// Friends available to start a direct message with, filtered by the picker search text.
    public var newDirectMessageCandidates: [FriendListItem] {
        let friends = shellPresentationSnapshot.allFriendItems.filter { $0.relationshipStatus == .friend }
        let query = newDirectMessageSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return friends }
        return friends.filter { item in
            item.user.username.lowercased().contains(query) ||
                (item.user.displayName?.lowercased().contains(query) ?? false)
        }
    }

    public func openNewDirectMessage() {
        newDirectMessageSearch = ""
        isPresentingNewDirectMessage = true
    }

    public func startDirectMessage(with userID: UserID) async {
        isPresentingNewDirectMessage = false
        newDirectMessageSearch = ""
        await openDirectMessage(with: userID, source: .newMessagePicker)
    }

    /// Friends available to add to a new group, filtered by the group picker search text.
    public var newGroupCandidates: [FriendListItem] {
        let friends = shellPresentationSnapshot.allFriendItems.filter { $0.relationshipStatus == .friend }
        let query = groupCreateSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return friends }
        return friends.filter { item in
            item.user.username.lowercased().contains(query) ||
                (item.user.displayName?.lowercased().contains(query) ?? false)
        }
    }

    public func openNewGroup() {
        groupCreateName = ""
        groupCreateSearch = ""
        groupCreateSelectedUserIDs = []
        groupCreateState = .idle
        isPresentingNewDirectMessage = false
        isPresentingNewGroup = true
    }

    public func toggleNewGroupCandidate(_ userID: UserID) {
        if groupCreateSelectedUserIDs.contains(userID) {
            groupCreateSelectedUserIDs.remove(userID)
        } else {
            groupCreateSelectedUserIDs.insert(userID)
        }
    }

    public func createGroupFromDraft() async {
        guard let apiClient = apiClientForCommunityAction() else {
            groupCreateState = .failed("Reconnect before creating a group.")
            return
        }
        let draft = GroupChannelCreateDraft(
            name: groupCreateName,
            users: groupCreateSelectedUserIDs.sorted { $0.rawValue < $1.rawValue }
        )
        guard let validated = draft.validatedForCreate else {
            groupCreateState = .failed("Group name must be 1 to 32 characters.")
            return
        }
        groupCreateState = .creating
        do {
            let channel = try await apiClient.createGroupChannel(draft: validated)
            _ = mergeDMChannels([channel], source: effectiveRuntimeMode == .mock ? .mock : .explicit)
            selectChannel(channel.id)
            groupCreateState = .created(channel.id)
            isPresentingNewGroup = false
            groupCreateName = ""
            groupCreateSearch = ""
            groupCreateSelectedUserIDs = []
        } catch {
            groupCreateState = .failed(Phase23Safety.safeError(error))
        }
    }

    /// Friends available to add to an existing group, excluding current recipients.
    /// Backend gating (Docs/Research.md Phase 58 Notes): any current group member may add a
    /// recipient, subject to the adder being friends with the target -- this is not owner-gated.
    public func addGroupMemberCandidates(for channelID: ChannelID) -> [FriendListItem] {
        let existingRecipients = Set(snapshot.channelsByID[channelID]?.recipients ?? [])
        let friends = shellPresentationSnapshot.allFriendItems.filter {
            $0.relationshipStatus == .friend && !existingRecipients.contains($0.user.id)
        }
        let query = addGroupMembersSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return friends }
        return friends.filter { item in
            item.user.username.lowercased().contains(query) ||
                (item.user.displayName?.lowercased().contains(query) ?? false)
        }
    }

    public func openAddGroupMembers(for channelID: ChannelID) {
        addGroupMembersChannelID = channelID
        addGroupMembersSearch = ""
        addGroupMembersSelectedUserIDs = []
        groupMembershipActionState = .idle
        isPresentingAddGroupMembers = true
    }

    public func toggleAddGroupMemberCandidate(_ userID: UserID) {
        if addGroupMembersSelectedUserIDs.contains(userID) {
            addGroupMembersSelectedUserIDs.remove(userID)
        } else {
            addGroupMembersSelectedUserIDs.insert(userID)
        }
    }

    public func addSelectedGroupMembers() async {
        guard let channelID = addGroupMembersChannelID else { return }
        guard let apiClient = apiClientForCommunityAction() else {
            groupMembershipActionState = .failed("Reconnect before adding group members.")
            return
        }
        let userIDs = addGroupMembersSelectedUserIDs.sorted { $0.rawValue < $1.rawValue }
        guard !userIDs.isEmpty else { return }
        groupMembershipActionState = .working
        var failureMessage: String?
        for userID in userIDs {
            do {
                try await apiClient.addGroupRecipient(channelID: channelID, userID: userID)
                if var channel = snapshot.channelsByID[channelID], !channel.recipients.contains(userID) {
                    channel.recipients.append(userID)
                    snapshot.channelsByID[channelID] = channel
                }
            } catch {
                failureMessage = Phase23Safety.safeError(error)
            }
        }
        if let failureMessage {
            groupMembershipActionState = .failed(failureMessage)
        } else {
            invalidateShellPresentation(reason: "group recipients added")
            groupMembershipActionState = .idle
            isPresentingAddGroupMembers = false
            addGroupMembersSearch = ""
            addGroupMembersSelectedUserIDs = []
        }
    }

    /// Only ever offered to the group owner, targeting another member. Self-removal must
    /// continue to route through the existing leave/close-group flow, not this recipients API
    /// (the backend rejects self-removal here with `CannotRemoveYourself`).
    public func requestRemoveGroupMember(_ userID: UserID, from channelID: ChannelID, displayName: String) {
        guard userID != currentUserID else { return }
        guard snapshot.channelsByID[channelID]?.ownerID == currentUserID else { return }
        pendingGroupMemberRemoval = PendingGroupMemberRemoval(channelID: channelID, userID: userID, displayName: displayName)
    }

    public func cancelRemoveGroupMember() {
        pendingGroupMemberRemoval = nil
    }

    public func confirmRemoveGroupMember() async {
        guard let pending = pendingGroupMemberRemoval else { return }
        guard let apiClient = apiClientForCommunityAction() else {
            groupMembershipActionState = .failed("Reconnect before removing group members.")
            return
        }
        groupMembershipActionState = .working
        do {
            try await apiClient.removeGroupRecipient(channelID: pending.channelID, userID: pending.userID)
            if var channel = snapshot.channelsByID[pending.channelID] {
                channel.recipients.removeAll { $0 == pending.userID }
                snapshot.channelsByID[pending.channelID] = channel
            }
            invalidateShellPresentation(reason: "group recipient removed")
            groupMembershipActionState = .idle
            pendingGroupMemberRemoval = nil
        } catch {
            groupMembershipActionState = .failed(Phase23Safety.safeError(error))
            pendingGroupMemberRemoval = nil
        }
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
        if source == .systemEventParticipant {
            phase43ProfileOpensFromSystemEventsCount += 1
        }
        enqueuePhase43IdentityHydrationIfNeeded(userID, source: .profileOpen)
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

    /// Maximum accepted custom status text length, matching the verified user edit schema bound.
    public static let customStatusTextLimit = 128

    public func openCustomStatusEditor() {
        customStatusDraft = currentUserForPresentation?.status?.text ?? ""
        isPresentingCustomStatusEditor = true
    }

    public func submitCustomStatusDraft() async {
        let trimmed = customStatusDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= Self.customStatusTextLimit else {
            statusUpdateStatus = "Custom status must be \(Self.customStatusTextLimit) characters or fewer."
            placeholderStatus = statusUpdateStatus
            return
        }
        isPresentingCustomStatusEditor = false
        await setCurrentUserStatusText(trimmed.isEmpty ? nil : trimmed)
    }

    public func clearCustomStatus() async {
        isPresentingCustomStatusEditor = false
        await setCurrentUserStatusText(nil)
    }

    public func setCurrentUserStatusText(_ text: String?) async {
        guard let userID = currentUserID,
              let apiClient = apiClientForCommunityAction()
        else {
            statusUpdateStatus = "Reconnect before changing status."
            placeholderStatus = statusUpdateStatus
            return
        }

        let originalUser = currentUserForPresentation
        let existingStatus = originalUser?.status ?? UserStatus()
        guard text != existingStatus.text else { return }

        var optimistic = originalUser ?? User(id: userID, username: UserDisplayResolver.shortenedID(userID))
        optimistic.status = UserStatus(text: text, presence: existingStatus.presence)
        upsertUser(optimistic)
        statusUpdateStatus = text == nil ? "Clearing custom status..." : "Setting custom status..."
        placeholderStatus = statusUpdateStatus

        do {
            let draft: UserEditDraft
            if let text {
                draft = UserEditDraft(status: UserStatus(text: text, presence: existingStatus.presence))
            } else {
                draft = UserEditDraft(remove: [.statusText])
            }
            let updated = try await apiClient.editUser(userID: userID, draft: draft)
            upsertUser(updated)
            statusUpdateStatus = text == nil ? "Custom status cleared." : "Custom status set."
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
            mergePhase43Profile(profile, userID: userID)
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
            let policy = profileMediaValidationPolicy
            let draft = try await Task.detached(priority: .userInitiated) {
                try policy.draft(for: url, kind: kind)
            }.value
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
            upsertUser(updated, source: .currentUserEdit)
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
            mergePhase43Profile(overlayProfile, userID: userID)
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
        imageResourceFailureDates.removeValue(forKey: key)
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
            removeImagePresentationData(for: key)
            imageResourceStates.removeValue(forKey: key)
            imageResourceFailureDates.removeValue(forKey: key)
            queuedImageResourceRequests.removeValue(forKey: key)
            imageResourceLoadTasks[key]?.cancel()
            imageResourceLoadTasks.removeValue(forKey: key)
            await imageMemoryCache.remove(key)
        }
        if let uploadedAvatar, let avatar = newUser.avatar {
            storeImagePresentationData(
                uploadedAvatar.draft.previewData ?? uploadedAvatar.draft.data,
                for: ImageCacheKey(id: avatar.id.rawValue, kind: .userAvatar)
            )
        }
        if let uploadedBackground, let background = newProfile.background {
            storeImagePresentationData(
                uploadedBackground.draft.previewData ?? uploadedBackground.draft.data,
                for: ImageCacheKey(id: background.id.rawValue, kind: .profileBackground)
            )
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
            upsertUser(user, source: .relationship)
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
            upsertUser(user, source: .relationship)
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
        if result.insertedCount > 0 || result.updatedCount > 0 {
            invalidateShellPresentation(reason: "DM merge")
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
        mergePhase43User(user, source: .relationship)
        guard var currentUser else { return }
        currentUser.relations.removeAll { $0.id == userID }
        if status != .none {
            currentUser.relations.append(Relationship(id: userID, status: status))
        }
        self.currentUser = currentUser
    }

    private func applyRelationshipUser(_ user: User) {
        currentUser = user
        upsertUser(user, source: .relationship)
        for relation in user.relations {
            if var related = snapshot.usersByID[relation.id] {
                related.relationship = relation.status
                snapshot.usersByID[relation.id] = related
                mergePhase43User(related, source: .relationship)
            }
        }
    }

    private func upsertUser(_ user: User, source: Phase43IdentitySource = .hydrationFetch) {
        snapshot.usersByID[user.id] = user
        if currentUserID == user.id {
            currentUser = user
        }
        mergePhase43User(user, source: source)
        if source == .currentUserEdit {
            phase43CurrentUserEditSnapshotMergeCount += 1
        }
        if currentUser?.relations.contains(where: { $0.id == user.id }) == true
            || snapshot.channelsByID.values.contains(where: {
                DMChannelClassifier.isDirectMessageLike($0) && $0.recipients.contains(user.id)
            }) {
            invalidateShellPresentation(reason: "relationship or DM user")
        }
        invalidateIdentityPresentationCaches()
    }

    private func invalidateIdentityPresentationCaches() {
        timelineRowPresentationCacheKey = nil
        if let context = profilePresentationContext {
            profilePresentationContext = profileContext(userID: context.userID, serverID: context.serverID, source: context.openSource)
        }
    }
    
    // MARK: - Diagnostics Updates

    private func updateVisibleIdentityDiagnostics() {
        phase68TraceDiagnostics.visibleIdentityDiagnosticsRequestCount += 1
        phase68VisibleIdentityDiagnosticsGeneration &+= 1
        guard phase68VisibleIdentityDiagnosticsTask == nil else {
            phase68TraceDiagnostics.visibleIdentityDiagnosticsCoalescedCount += 1
            return
        }
        startPhase68VisibleIdentityDiagnosticsBuild()
    }

    private func startPhase68VisibleIdentityDiagnosticsBuild() {
        phase68VisibleIdentityDiagnosticsTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled else { return }
            let generation = self.phase68VisibleIdentityDiagnosticsGeneration
            let input = self.phase68VisibleIdentityDiagnosticsInput()
            let preparer = self.phase68VisibleIdentityDiagnosticsPreparer
            self.phase68TraceDiagnostics.visibleIdentityDiagnosticsBuildCount += 1
            let diagnostics = await preparer(input)
            guard !Task.isCancelled else { return }
            if generation == self.phase68VisibleIdentityDiagnosticsGeneration {
                self.visibleIdentityDiagnostics = diagnostics
                self.phase68VisibleIdentityDiagnosticsTask = nil
            } else {
                self.phase68TraceDiagnostics.visibleIdentityDiagnosticsStaleResultCount += 1
                self.phase68VisibleIdentityDiagnosticsTask = nil
                self.startPhase68VisibleIdentityDiagnosticsBuild()
            }
        }
    }

    private func refreshVisibleIdentityDiagnosticsSynchronously() {
        phase68VisibleIdentityDiagnosticsTask?.cancel()
        phase68VisibleIdentityDiagnosticsTask = nil
        phase68VisibleIdentityDiagnosticsGeneration &+= 1
        phase68TraceDiagnostics.visibleIdentityDiagnosticsBuildCount += 1
        visibleIdentityDiagnostics = Phase68VisibleIdentityDiagnosticsPreparer.prepare(
            phase68VisibleIdentityDiagnosticsInput()
        )
    }

    func waitForPhase68VisibleIdentityDiagnosticsForTesting() async {
        while let task = phase68VisibleIdentityDiagnosticsTask {
            await task.value
        }
    }

    func setPhase68VisibleIdentityDiagnosticsPreparerForTesting(
        _ preparer: @escaping @Sendable (Phase68VisibleIdentityDiagnosticsInput) async -> VisibleIdentityDiagnostics
    ) {
        phase68VisibleIdentityDiagnosticsPreparer = preparer
    }

    private func phase68VisibleIdentityDiagnosticsInput() -> Phase68VisibleIdentityDiagnosticsInput {
        let failedAvatars = imageResourceStates.filter { key, state in
            key.kind == .userAvatar && {
                if case .failed = state { return true }
                return false
            }()
        }.count
        return Phase68VisibleIdentityDiagnosticsInput(
            snapshot: snapshot,
            identitySnapshots: phase43IdentitySnapshots,
            timelineMessages: selectedTimelineMessages,
            memberGroups: memberListGroupCache,
            selectedChannelID: selectedConversationChannelID,
            selectedServerID: selection.serverID,
            currentUser: currentUserForPresentation,
            failedAvatarCount: failedAvatars,
            profileFetchMergeCount: profileFetchMergeCount,
            memberWrapperUserMergeCount: memberWrapperUserMergeCount,
            hydrationQueuedCount: phase43QueuedIdentityHydration.count,
            hydrationInFlightCount: phase43IdentityHydrationTasks.count,
            hydrationSuccessCount: phase43IdentityHydrationSuccessCount,
            hydrationFailureCount: phase43IdentityHydrationFailureCount,
            hydrationDedupeHits: phase43IdentityHydrationDedupeHits,
            hydrationCooldownSkips: phase43IdentityHydrationCooldownSkips,
            avatarMetadataPreservedCount: phase43AvatarMetadataPreservedAfterMemberRemovalCount,
            profileSystemEventOpenCount: phase43ProfileOpensFromSystemEventsCount,
            currentUserEditMergeCount: phase43CurrentUserEditSnapshotMergeCount,
            memberRemovalPreservationCount: phase43MemberRemovalIdentityPreservationCount
        )
    }

    private func updateFreezePerformanceDiagnostics(marker: String? = nil) {
        if let marker {
            pendingFreezeDiagnosticsMarker = marker
        }
        let now = Date()
        let elapsed = now.timeIntervalSince(freezeDiagnosticsLastPublishAt)
        if elapsed >= 0.25 {
            freezeDiagnosticsLastPublishAt = now
            publishFreezePerformanceDiagnostics(marker: pendingFreezeDiagnosticsMarker)
            pendingFreezeDiagnosticsMarker = nil
            return
        }
        guard freezeDiagnosticsPublishTask == nil else { return }
        freezeDiagnosticsPublishTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(max(0, 0.25 - elapsed)))
            } catch {
                return
            }
            guard let self else { return }
            self.freezeDiagnosticsLastPublishAt = Date()
            self.publishFreezePerformanceDiagnostics(marker: self.pendingFreezeDiagnosticsMarker)
            self.pendingFreezeDiagnosticsMarker = nil
            self.freezeDiagnosticsPublishTask = nil
        }
    }

    private func publishFreezePerformanceDiagnostics(marker: String? = nil) {
        diagnosticsPublishCount += 1
        let failedImages = imageResourceStates.values.filter {
            if case .failed = $0 { return true }
            return false
        }.count
        let avatarActive = imageResourceLoadTasks.values.filter { $0.isCancelled == false }.count
        let avatarQueued = queuedImageResourceRequests.values.filter { $0.request.kind == .userAvatar }.count
        let avatarFailed = imageResourceStates.filter { key, state in
            key.kind == .userAvatar && {
                if case .failed = state { return true }
                return false
            }()
        }.count
        let emojiActive = imageResourceLoadTasks.values.count
        let emojiQueued = queuedImageResourceRequests.values.filter { $0.request.kind == .customEmoji }.count
        let profileQueued = queuedImageResourceRequests.values.filter {
            $0.request.kind == .profileBackground || $0.request.kind == .userAvatar
        }.count
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
            mediaSafeModeEnabled: freezePerformanceDiagnostics.mediaSafeModeEnabled,
            capabilityCacheUpdateCount: capabilityCacheUpdateCount,
            visibleImageResourceCount: visibleImageResourceKeys.count,
            imagePresentationEvictionCount: imagePresentationEvictionCount,
            imageReloadAfterEvictionCount: imageReloadAfterEvictionCount,
            imageQueueEnqueueCount: imageQueueEnqueueCount,
            timelineMediaInvalidationCount: timelineMediaInvalidationCount
        )
    }

    private func invalidateCapabilityCache() {
        capabilityCacheUpdateCount += 1
        phase46ModerationVersions.bumpCapabilityVersion()
        invalidateModerationAvailabilityCaches()
        #if DEBUG
        #endif
        let moderationChannel = selectedOrFallbackModerationTextChannel()
        cachedServerCapabilities = Phase24Management.capabilities(
            server: selectedServer,
            selectedChannel: moderationChannel,
            currentUserID: currentUserID,
            runtimeMode: effectiveRuntimeMode,
            sessionState: effectiveSessionState
        )
        cachedCurrentPermissionResolution = cachedModerationPermissionResolution(
            server: selectedServer,
            channel: moderationChannel,
            member: selectedServerMember,
            currentUserID: currentUserID
        )
        refreshPhase46ModerationPrewarmToken()
    }

    @discardableResult
    private func updatePhase46ModerationVersions(previous: RealtimeSnapshot, current: RealtimeSnapshot) -> Bool {
        var changed = false
        if previous.serversByID != current.serversByID {
            phase46ModerationVersions.serverVersion &+= 1
            phase46ModerationVersions.roleVersion &+= 1
            phase46ModerationVersions.permissionVersion &+= 1
            changed = true
        }
        if previous.channelsByID != current.channelsByID {
            phase46ModerationVersions.channelVersion &+= 1
            phase46ModerationVersions.permissionVersion &+= 1
            changed = true
        }
        if previous.membersByServerAndUserID != current.membersByServerAndUserID {
            phase46ModerationVersions.memberVersion &+= 1
            changed = true
        }
        return changed
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

    public func presentNotice(
        _ message: String,
        severity: TransientAppNoticeSeverity,
        duration: Duration? = nil
    ) {
        let notice = TransientAppNotice(message: message, severity: severity)
        transientNoticeTask?.cancel()
        transientNotice = notice
        transientNoticeTask = Task { [weak self] in
            do {
                try await Task.sleep(for: duration ?? severity.defaultDuration)
            } catch {
                return
            }
            guard let self, self.transientNotice?.id == notice.id else { return }
            self.transientNotice = nil
            self.transientNoticeTask = nil
        }
    }

    public func dismissTransientNotice() {
        transientNoticeTask?.cancel()
        transientNoticeTask = nil
        transientNotice = nil
    }

    private func routeLegacyStatusToNotice(_ status: String?) {
        guard let status else { return }
        guard let severity = TransientAppNoticePolicy.severity(for: status) else {
            dismissTransientNotice()
            return
        }
        presentNotice(status, severity: severity)
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
        cachedServerCapabilities
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
        selectedServerSettingsTab = .overview
        serverSettingsState = .loading
        serverSettingsPresentationState = .loading
        isServerOverviewPresented = true
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

    public func chooseServerEmojiDraft() {
        chooseServerMediaDraft(tag: .emojis)
    }

    public func emojiManagementDisabledReason() -> String? {
        let capabilities = serverManagementCapabilities()
        guard capabilities.isConnectedForLiveActions else {
            return "Reconnect to manage server emoji."
        }
        guard let server = selectedServer else {
            return "Select a server before managing emoji."
        }
        if currentUserID == server.ownerID {
            return nil
        }
        let resolution = Phase25PermissionResolver.resolve(
            server: server,
            channel: selectedChannel,
            member: selectedServerMember,
            currentUserID: currentUserID
        )
        guard resolution.effectivePermissions.contains(.manageCustomisation) else {
            return resolution.warnings.isEmpty
                ? "You do not have permission to manage server emoji."
                : "Permission resolution is incomplete for server emoji management."
        }
        return nil
    }

    public func refreshServerEmojis() async {
        guard let server = selectedServer else {
            serverEmojiManagementState = .failed("Select a server before refreshing emoji.")
            return
        }
        guard let apiClient = apiClientForCommunityAction() else {
            serverEmojiManagementState = .failed("Reconnect before refreshing server emoji.")
            return
        }
        serverEmojiManagementState = .loading
        do {
            let emojis = try await apiClient.fetchServerEmojis(serverID: server.id)
            snapshot.emojisByID = snapshot.emojisByID.filter { _, emoji in
                if case let .server(serverID) = emoji.parent {
                    return serverID != server.id
                }
                return true
            }
            for emoji in emojis {
                snapshot.emojisByID[emoji.id] = emoji
            }
            serverEmojiManagementState = .loaded(emojis)
            invalidateTimelineMediaPresentation()
        } catch {
            serverEmojiManagementState = .failed(Phase23Safety.safeError(error))
        }
    }

    public func createServerEmoji() async {
        guard let server = selectedServer else {
            serverEmojiManagementState = .failed("Select a server before creating emoji.")
            return
        }
        guard let draft = serverEmojiDraft else {
            serverEmojiManagementState = .failed("Choose an emoji image before creating it.")
            return
        }
        let createDraft = EmojiCreateDraft(name: serverEmojiName, serverID: server.id)
        guard let validated = createDraft.validated else {
            serverEmojiManagementState = .failed("Emoji name must be 1 to 32 characters.")
            return
        }
        if let reason = emojiManagementDisabledReason() {
            serverEmojiManagementState = .failed(reason)
            return
        }
        guard let apiClient = apiClientForCommunityAction() else {
            serverEmojiManagementState = .failed("Reconnect before creating server emoji.")
            return
        }
        serverEmojiManagementState = .loading
        do {
            let upload = try await apiClient.uploadFile(
                data: draft.data,
                filename: draft.filename,
                mimeType: draft.mimeType,
                tag: .emojis
            )
            let emoji = try await apiClient.createEmoji(uploadID: upload.id, draft: validated)
            snapshot.emojisByID[emoji.id] = emoji
            serverEmojiName = ""
            serverEmojiDraft = nil
            serverEmojiManagementState = .loaded(
                snapshot.emojisByID.values.filter {
                    if case let .server(serverID) = $0.parent {
                        return serverID == server.id
                    }
                    return false
                }
            )
            invalidateTimelineMediaPresentation()
            loadImageResource(
                for: CustomEmojiDisplayItem(emoji: emoji).file,
                kind: .customEmoji
            )
        } catch {
            serverEmojiManagementState = .failed(Phase23Safety.safeError(error))
        }
    }

    public func requestDeleteServerEmoji(_ id: EmojiID) {
        guard let emoji = snapshot.emojisByID[id] else {
            serverEmojiManagementState = .failed("That emoji is no longer available.")
            return
        }
        pendingServerEmojiDeletion = emoji
    }

    public func confirmDeleteServerEmoji() async {
        guard let emoji = pendingServerEmojiDeletion else { return }
        if let reason = emojiManagementDisabledReason() {
            serverEmojiManagementState = .failed(reason)
            pendingServerEmojiDeletion = nil
            return
        }
        guard let apiClient = apiClientForCommunityAction() else {
            serverEmojiManagementState = .failed("Reconnect before deleting server emoji.")
            pendingServerEmojiDeletion = nil
            return
        }
        serverEmojiManagementState = .loading
        do {
            try await apiClient.deleteEmoji(id: emoji.id)
            snapshot.emojisByID.removeValue(forKey: emoji.id)
            pendingServerEmojiDeletion = nil
            serverEmojiManagementState = .loaded(
                snapshot.emojisByID.values.filter {
                    if case let .server(serverID) = $0.parent {
                        return serverID == selectedServer?.id
                    }
                    return false
                }
            )
            invalidateTimelineMediaPresentation()
        } catch {
            pendingServerEmojiDeletion = nil
            serverEmojiManagementState = .failed(Phase23Safety.safeError(error))
        }
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
        mergePhase43Member(member, user: snapshot.usersByID[member.id.userID], source: .readyMember)
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

    public func memberModerationMenuState(for item: MemberListItem) -> MemberModerationMenuState {
        memberModerationMenuState(targetUserID: item.userID, member: item.member)
    }

    public func cachedMemberModerationMenuState(for item: MemberListItem) -> MemberModerationMenuState {
        cachedMemberModerationMenuState(targetUserID: item.userID, member: item.member)
    }

    public func cachedMemberModerationMenuState(targetUserID: UserID, member: ServerMember? = nil, allowNonMemberBan: Bool = false) -> MemberModerationMenuState {
        let resolvedMember = resolvedModerationTargetMember(targetUserID: targetUserID, member: member)
        let key = moderationMenuStateCacheKey(
            prewarmKey: memberPanelModerationPrewarmToken,
            targetUserID: targetUserID,
            member: resolvedMember,
            allowNonMemberBan: allowNonMemberBan
        )
        return memberModerationMenuStateCache[key] ?? preparingModerationMenuState(targetUserID: targetUserID)
    }

    public func memberPanelBecameVisibleForModerationPrewarm() async {
        prewarmModerationMenuStateCachesIfNeeded(trigger: .memberPanelVisible)
    }

    public func profilePopoverBecameVisibleForModerationPrewarm() async {
        prewarmModerationMenuStateCachesIfNeeded(trigger: .profilePopoverVisible)
    }

    public func serverSettingsModerationBecameVisibleForPrewarm() async {
        prewarmModerationMenuStateCachesIfNeeded(trigger: .serverSettingsModerationVisible)
    }

    public func memberModerationMenuState(targetUserID: UserID, member: ServerMember? = nil, allowNonMemberBan: Bool = false) -> MemberModerationMenuState {
        let resolvedMember = resolvedModerationTargetMember(targetUserID: targetUserID, member: member)
        let prewarmKey = phase46ModerationPrewarmKey()
        let baseContext = moderationBaseContextSnapshot(prewarmKey: prewarmKey)
        let key = moderationMenuStateCacheKey(
            prewarmKey: prewarmKey,
            targetUserID: targetUserID,
            member: resolvedMember,
            allowNonMemberBan: allowNonMemberBan
        )
        if let cached = memberModerationMenuStateCache[key] {
            moderationCacheDiagnostics.memberMenuStateCacheHits += 1
            moderationCacheDiagnostics.moderationContextLookupHits += 1
            return cached
        }
        moderationCacheDiagnostics.memberMenuStateCacheMisses += 1
        moderationCacheDiagnostics.moderationContextLookupMisses += 1
        let state = MemberModerationMenuStateResolver.menuState(
            targetUserID: targetUserID,
            targetMember: resolvedMember,
            baseContext: baseContext,
            allowNonMemberBan: allowNonMemberBan
        )
        memberModerationMenuStateCache[key] = state
        return state
    }

    // Compatibility helper for command/action revalidation. SwiftUI row or context-menu
    // rendering must use cachedMemberModerationMenuState(...) so menu construction stays O(1).
    public func memberActionDisabledReason(for member: ServerMember, action: MemberModerationAction) -> String? {
        if let moderationAction = moderationAction(for: action) {
            return memberModerationMenuState(targetUserID: member.id.userID, member: member)[moderationAction].disabledReasonText
        }
        guard cachedServerCapabilities.isConnectedForLiveActions else { return "Reconnect before member moderation." }
        guard member.id.userID != currentUserID else { return "You cannot edit yourself from this guarded flow." }
        guard Phase26MemberSafety.canActOn(member: member, currentMember: selectedServerMember, server: selectedServer, currentUserID: currentUserID) || currentUserID == selectedServer?.ownerID else {
            return "Rank data is incomplete or this member is protected."
        }
        let resolution = cachedCurrentPermissionResolution
        let allowed: Bool
        switch action {
        case .saveNickname, .resetNickname:
            allowed = resolution.effectivePermissions.contains(.manageNicknames) || currentUserID == selectedServer?.ownerID
        case .removeAvatar:
            allowed = resolution.effectivePermissions.contains(.removeAvatars) || currentUserID == selectedServer?.ownerID
        case .kick, .ban, .timeout, .clearTimeout:
            allowed = false
        }
        guard allowed else {
            return resolution.warnings.isEmpty ? "You do not have permission for this member action." : "Permission resolution is incomplete for this member action."
        }
        return nil
    }

    public func requestMemberAction(_ action: MemberModerationAction, for member: ServerMember) {
        if let moderationAction = moderationAction(for: action) {
            requestModerationAction(moderationAction, targetUserID: member.id.userID, member: member)
            return
        }
        guard memberActionDisabledReason(for: member, action: action) == nil else {
            phase26Status = memberActionDisabledReason(for: member, action: action)
            return
        }
        pendingMemberModerationAction = PendingMemberModerationAction(member: member, action: action)
    }

    public func moderationDisabledReason(for action: ModerationAction, targetUserID: UserID, member: ServerMember? = nil, allowNonMemberBan: Bool = false) -> ModerationDisabledReason? {
        memberModerationMenuState(targetUserID: targetUserID, member: member, allowNonMemberBan: allowNonMemberBan)[action].disabledReason
    }

    public func moderationDisabledReasonText(for action: ModerationAction, targetUserID: UserID, member: ServerMember? = nil, allowNonMemberBan: Bool = false) -> String? {
        memberModerationMenuState(targetUserID: targetUserID, member: member, allowNonMemberBan: allowNonMemberBan)[action].disabledReasonText
    }

    public func availableModerationActions(for targetUserID: UserID, member: ServerMember? = nil, allowNonMemberBan: Bool = false) -> [ModerationAction] {
        let state = memberModerationMenuState(targetUserID: targetUserID, member: member, allowNonMemberBan: allowNonMemberBan)
        return ModerationAction.allCases.filter { !state[$0].isDisabled }
    }

    public func requestModerationAction(_ action: ModerationAction, targetUserID: UserID, member: ServerMember? = nil, allowNonMemberBan: Bool = false) {
        guard let server = selectedServer else {
            let reason = ModerationDisabledReason.noSelectedServer
            phase26Status = reason.message
            updateModerationDiagnostics(action: action, targetUserID: targetUserID, targetMember: member, permissionResult: reason.rawValue, requestResult: "blocked", routeCategory: routeCategory(for: action), memberMutation: "none")
            return
        }
        let resolvedMember = member ?? snapshot.membersByServerAndUserID[ServerMemberKey(serverID: server.id, userID: targetUserID)]
        if let reason = moderationDisabledReason(for: action, targetUserID: targetUserID, member: resolvedMember, allowNonMemberBan: allowNonMemberBan) {
            phase26Status = reason.message
            updateModerationDiagnostics(action: action, targetUserID: targetUserID, targetMember: resolvedMember, permissionResult: reason.rawValue, requestResult: "blocked", routeCategory: routeCategory(for: action), memberMutation: "none")
            return
        }
        let user = snapshot.usersByID[targetUserID]
        let displayName = displayName(for: user, member: resolvedMember, fallbackID: targetUserID)
        pendingModerationConfirmation = PendingModerationConfirmation(
            action: action,
            serverID: server.id,
            serverName: server.name,
            targetUserID: targetUserID,
            targetMember: resolvedMember,
            displayName: displayName,
            allowNonMemberBan: allowNonMemberBan
        )
        moderationActionState = .idle
        updateModerationDiagnostics(action: action, targetUserID: targetUserID, targetMember: resolvedMember, permissionResult: "allowed", requestResult: "pendingConfirmation", routeCategory: routeCategory(for: action), memberMutation: "none")
    }

    public func requestUnban(userID: UserID) {
        requestModerationAction(.unban, targetUserID: userID)
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
            case .timeout, .clearTimeout, .kick, .ban:
                memberActionState = .failed("Use the Phase 42 moderation confirmation flow for this action.")
                return
            }
            refreshLoadedServerSettings()
            phase26Status = "Member action completed"
        } catch {
            memberActionState = .failed(Phase23Safety.safeError(error))
        }
    }

    public func confirmPendingModerationAction() async {
        guard let pending = pendingModerationConfirmation,
              let apiClient = apiClientForCommunityAction()
        else {
            moderationActionState = .failed("Reconnect before member moderation.")
            return
        }
        let resolvedMember = pending.targetMember ?? snapshot.membersByServerAndUserID[ServerMemberKey(serverID: pending.serverID, userID: pending.targetUserID)]
        if let reason = moderationDisabledReason(for: pending.action, targetUserID: pending.targetUserID, member: resolvedMember, allowNonMemberBan: pending.allowNonMemberBan) {
            moderationActionState = .failed(reason.message)
            updateModerationDiagnostics(action: pending.action, targetUserID: pending.targetUserID, targetMember: resolvedMember, permissionResult: reason.rawValue, requestResult: "blocked", routeCategory: routeCategory(for: pending.action), memberMutation: "none")
            return
        }

        moderationActionState = .loading
        memberActionState = .loading
        let startedAt = Date()
        do {
            let mutationCategory: String
            let responseShape: String
            switch pending.action {
            case .kick:
                try await apiClient.kickMember(serverID: pending.serverID, userID: pending.targetUserID)
                removeMember(serverID: pending.serverID, userID: pending.targetUserID)
                selectedMemberDetailID = nil
                mutationCategory = "removedMember"
                responseShape = "empty204"
            case .ban:
                let trimmedReason = pending.reason.trimmingCharacters(in: .whitespacesAndNewlines)
                let ban = try await apiClient.banMember(
                    serverID: pending.serverID,
                    userID: pending.targetUserID,
                    draft: BanCreateDraft(reason: trimmedReason.isEmpty ? nil : String(trimmedReason.prefix(1024)), deleteMessageSeconds: nil)
                )
                removeMember(serverID: pending.serverID, userID: pending.targetUserID)
                patchBanListAfterBan(ban)
                selectedMemberDetailID = nil
                mutationCategory = "removedMemberAddedBan"
                responseShape = "serverBan"
            case .unban:
                try await apiClient.unbanMember(serverID: pending.serverID, userID: pending.targetUserID)
                patchBanListAfterUnban(serverID: pending.serverID, userID: pending.targetUserID)
                mutationCategory = "removedBanOnly"
                responseShape = "empty204"
            case .timeout:
                guard let timeoutUntil = pending.timeoutUntil() else {
                    moderationActionState = .failed("Choose a timeout duration before saving.")
                    memberActionState = .failed("Choose a timeout duration before saving.")
                    return
                }
                let member = try await apiClient.editMember(serverID: pending.serverID, userID: pending.targetUserID, draft: MemberEditDraft(timeout: timeoutUntil))
                upsert(member: member)
                mutationCategory = "updatedMemberTimeout"
                responseShape = "member"
            case .removeTimeout:
                let member = try await apiClient.editMember(serverID: pending.serverID, userID: pending.targetUserID, draft: MemberEditDraft(remove: [.timeout]))
                upsert(member: member)
                mutationCategory = "clearedMemberTimeout"
                responseShape = "member"
            }
            pendingModerationConfirmation = nil
            moderationActionState = .loaded("\(pending.action.title) completed")
            memberActionState = .idle
            refreshLoadedServerSettings()
            phase26Status = "\(pending.action.title) completed"
            updateModerationDiagnostics(
                action: pending.action,
                targetUserID: pending.targetUserID,
                targetMember: resolvedMember,
                permissionResult: "allowed",
                requestResult: "success",
                routeCategory: routeCategory(for: pending.action),
                responseShape: responseShape,
                durationBucket: pending.action == .timeout ? pending.timeoutPreset.diagnosticsBucket : "none",
                memberMutation: mutationCategory,
                elapsed: Date().timeIntervalSince(startedAt)
            )
        } catch {
            let safe = Phase23Safety.safeError(error)
            moderationActionState = .failed(safe)
            memberActionState = .failed(safe)
            updateModerationDiagnostics(
                action: pending.action,
                targetUserID: pending.targetUserID,
                targetMember: resolvedMember,
                permissionResult: "allowed",
                requestResult: "failed",
                routeCategory: routeCategory(for: pending.action),
                responseShape: "error",
                safeError: moderationSafeErrorCategory(error),
                durationBucket: pending.action == .timeout ? pending.timeoutPreset.diagnosticsBucket : "none",
                memberMutation: "none",
                elapsed: Date().timeIntervalSince(startedAt)
            )
        }
    }

    public func refreshBanList() async {
        guard let server = selectedServer else {
            banListState = .failed("Select a server before loading bans.")
            updateModerationDiagnostics(action: nil, targetUserID: nil, targetMember: nil, permissionResult: "noSelectedServer", requestResult: "blocked", routeCategory: "fetchBans", memberMutation: "none")
            return
        }
        let resolution = Phase25PermissionResolver.resolve(server: selectedServer, channel: selectedChannel, member: selectedServerMember, currentUserID: currentUserID)
        guard serverManagementCapabilities().isConnectedForLiveActions else {
            banListState = .failed("Reconnect before loading bans.")
            updateModerationDiagnostics(action: nil, targetUserID: nil, targetMember: nil, permissionResult: "disconnected", requestResult: "blocked", routeCategory: "fetchBans", memberMutation: "none")
            return
        }
        guard resolution.effectivePermissions.contains(.banMembers) || currentUserID == server.ownerID else {
            banListState = .failed("You do not have permission to view bans.")
            updateModerationDiagnostics(action: nil, targetUserID: nil, targetMember: nil, permissionResult: resolution.warnings.isEmpty ? "missingPermission" : "permissionIncomplete", requestResult: "blocked", routeCategory: "fetchBans", memberMutation: "none")
            return
        }
        guard let apiClient = apiClientForCommunityAction() else {
            banListState = .failed("Reconnect before loading bans.")
            updateModerationDiagnostics(action: nil, targetUserID: nil, targetMember: nil, permissionResult: "disconnected", requestResult: "blocked", routeCategory: "fetchBans", memberMutation: "none")
            return
        }
        banListState = .loading
        let startedAt = Date()
        updateModerationDiagnostics(action: nil, targetUserID: nil, targetMember: nil, permissionResult: "allowed", requestResult: "loading", routeCategory: "fetchBans", memberMutation: "none")
        do {
            let result = try await apiClient.fetchServerBans(serverID: server.id)
            mergeBanListIdentities(result)
            banListState = .loaded(result)
            await hydrateMissingBanUsersIfNeeded(result, apiClient: apiClient)
            updateModerationDiagnostics(action: nil, targetUserID: nil, targetMember: nil, permissionResult: "allowed", requestResult: "success", routeCategory: "fetchBans", responseShape: "banList", memberMutation: "none", elapsed: Date().timeIntervalSince(startedAt))
        } catch {
            banListState = .failed(Phase23Safety.safeError(error))
            updateModerationDiagnostics(action: nil, targetUserID: nil, targetMember: nil, permissionResult: "allowed", requestResult: "failed", routeCategory: "fetchBans", responseShape: "error", safeError: moderationSafeErrorCategory(error), memberMutation: "none", elapsed: Date().timeIntervalSince(startedAt))
        }
    }

    public func unban(userID: UserID) async {
        requestUnban(userID: userID)
        await confirmPendingModerationAction()
    }

    private func moderationAction(for action: MemberModerationAction) -> ModerationAction? {
        switch action {
        case .kick:
            .kick
        case .ban:
            .ban
        case .timeout:
            .timeout
        case .clearTimeout:
            .removeTimeout
        case .saveNickname, .resetNickname, .removeAvatar:
            nil
        }
    }

    private func invalidateModerationAvailabilityCaches() {
        moderationCacheGeneration &+= 1
        moderationBaseContextCacheKey = nil
        moderationBaseContextCache = nil
        moderationPermissionResolutionCache.removeAll(keepingCapacity: true)
        memberModerationMenuStateCache.removeAll(keepingCapacity: true)
        phase46MemberPanelPrewarmState = Phase46MemberPanelPrewarmState(
            preparedKey: nil,
            inFlightKey: nil,
            lastTrigger: .stateMutation,
            lastResult: .idle,
            preparedMemberCount: phase46MemberPanelPrewarmState.preparedMemberCount,
            attemptCount: phase46MemberPanelPrewarmState.attemptCount,
            dedupeCount: phase46MemberPanelPrewarmState.dedupeCount
        )
        refreshPhase46ModerationPrewarmToken()
    }

    private func prewarmModerationMenuStateCachesIfNeeded(trigger: Phase46PrewarmTrigger) {
        let prewarmKey = memberPanelModerationPrewarmToken
        guard prewarmKey.selectedServerID != nil else {
            recordPhase46Prewarm(trigger: trigger, key: prewarmKey, result: .skippedNoServer, preparedMemberCount: 0)
            return
        }
        if phase46MemberPanelPrewarmState.preparedKey == prewarmKey {
            recordPhase46Prewarm(trigger: trigger, key: prewarmKey, result: .deduped, preparedMemberCount: phase46MemberPanelPrewarmState.preparedMemberCount)
            return
        }
        if phase46MemberPanelPrewarmState.inFlightKey == prewarmKey {
            recordPhase46Prewarm(trigger: trigger, key: prewarmKey, result: .skippedInFlight, preparedMemberCount: phase46MemberPanelPrewarmState.preparedMemberCount)
            return
        }

        phase46MemberPanelPrewarmState.inFlightKey = prewarmKey
        let baseContext = moderationBaseContextSnapshot(prewarmKey: prewarmKey)
        let targets = moderationPrewarmTargets(for: prewarmKey.selectedServerID)
        guard !targets.isEmpty else {
            recordPhase46Prewarm(trigger: trigger, key: prewarmKey, result: .skippedNoMembers, preparedMemberCount: 0)
            return
        }

        for target in targets {
            let state = MemberModerationMenuStateResolver.menuState(
                targetUserID: target.userID,
                targetMember: target.member,
                baseContext: baseContext,
                allowNonMemberBan: target.allowNonMemberBan
            )
            let key = moderationMenuStateCacheKey(
                prewarmKey: prewarmKey,
                targetUserID: target.userID,
                member: target.member,
                allowNonMemberBan: target.allowNonMemberBan
            )
            memberModerationMenuStateCache[key] = state
        }
        recordPhase46Prewarm(trigger: trigger, key: prewarmKey, result: .prepared, preparedMemberCount: targets.count)
    }

    private func moderationBaseContextSnapshot(prewarmKey: Phase46ModerationPrewarmKey) -> ModerationBaseContextSnapshot {
        let server = selectedServer
        let userID = currentUserID
        let currentMember = selectedServerMember
        let channel = prewarmKey.selectedOrFallbackTextChannelID.flatMap { snapshot.channelsByID[$0] }
        let routeAvailability = ModerationRouteAvailability()
        let bannedIDs = knownBannedUserIDs
        let key = ModerationBaseContextCacheKey(
            prewarmKey: prewarmKey,
            routeAvailability: routeAvailability,
            isConnectedForLiveActions: cachedServerCapabilities.isConnectedForLiveActions,
            generation: moderationCacheGeneration
        )
        if key == moderationBaseContextCacheKey, let cached = moderationBaseContextCache {
            moderationCacheDiagnostics.moderationBaseContextCacheHits += 1
            return cached
        }
        moderationCacheDiagnostics.moderationBaseContextCacheMisses += 1
        let resolution = cachedModerationPermissionResolution(server: server, channel: channel, member: currentMember, currentUserID: userID)
        let base = ModerationBaseContextSnapshot(
            serverID: server?.id,
            currentUserID: userID,
            server: server,
            currentMember: currentMember,
            selectedOrFallbackTextChannelID: channel?.id,
            permissionResolution: resolution,
            isConnectedForLiveActions: cachedServerCapabilities.isConnectedForLiveActions,
            routeAvailability: routeAvailability,
            knownBannedUserIDs: bannedIDs,
            generation: moderationCacheGeneration
        )
        moderationBaseContextCacheKey = key
        moderationBaseContextCache = base
        return base
    }

    private func cachedModerationPermissionResolution(server: Server?, channel: Channel?, member: ServerMember?, currentUserID: UserID?) -> PermissionResolutionResult {
        let prewarmKey = phase46ModerationPrewarmKey(selectedOrFallbackTextChannelID: channel?.id)
        let key = ModerationPermissionResolutionCacheKey(
            prewarmKey: prewarmKey,
            runtimeMode: effectiveRuntimeMode,
            sessionState: effectiveSessionState,
            generation: moderationCacheGeneration
        )
        if let cached = moderationPermissionResolutionCache[key] {
            moderationCacheDiagnostics.permissionResolutionCacheHits += 1
            return cached
        }
        moderationCacheDiagnostics.permissionResolutionCacheMisses += 1
        let resolution = Phase25PermissionResolver.resolve(server: server, channel: channel, member: member, currentUserID: currentUserID)
        moderationPermissionResolutionCache[key] = resolution
        return resolution
    }

    private func refreshPhase46ModerationPrewarmToken() {
        memberPanelModerationPrewarmToken = phase46ModerationPrewarmKey()
    }

    private func phase46ModerationPrewarmKey(selectedOrFallbackTextChannelID explicitChannelID: ChannelID? = nil) -> Phase46ModerationPrewarmKey {
        let channelID = explicitChannelID ?? selectedOrFallbackModerationTextChannel()?.id
        return Phase46ModerationPrewarmKey(
            selectedServerID: selection.serverID,
            selectedChannelID: selection.channelID,
            selectedOrFallbackTextChannelID: channelID,
            currentUserID: currentUserID,
            serverVersion: phase46ModerationVersions.serverVersion,
            memberVersion: phase46ModerationVersions.memberVersion,
            roleVersion: phase46ModerationVersions.roleVersion,
            channelVersion: phase46ModerationVersions.channelVersion,
            permissionVersion: phase46ModerationVersions.permissionVersion,
            banVersion: phase46ModerationVersions.banVersion,
            capabilityVersion: phase46ModerationVersions.capabilityVersion
        )
    }

    private func moderationMenuStateCacheKey(
        prewarmKey: Phase46ModerationPrewarmKey,
        targetUserID: UserID,
        member: ServerMember?,
        allowNonMemberBan: Bool
    ) -> ModerationMenuStateCacheKey {
        ModerationMenuStateCacheKey(
            prewarmKey: prewarmKey,
            targetUserID: targetUserID,
            targetServerID: member?.id.serverID ?? prewarmKey.selectedServerID,
            allowNonMemberBan: allowNonMemberBan,
            timeoutBucket: moderationTimeoutBucket(member?.timeout)
        )
    }

    private func preparingModerationMenuState(targetUserID: UserID) -> MemberModerationMenuState {
        MemberModerationMenuState(
            targetUserID: targetUserID,
            actions: Dictionary(uniqueKeysWithValues: ModerationAction.allCases.map { action in
                (action, MemberModerationActionState.disabled("Preparing moderation state"))
            })
        )
    }

    private func moderationPrewarmTargets(for serverID: ServerID?) -> [(userID: UserID, member: ServerMember?, allowNonMemberBan: Bool)] {
        guard let serverID else { return [] }
        var seen = Set<UserID>()
        var targets: [(userID: UserID, member: ServerMember?, allowNonMemberBan: Bool)] = []
        for member in snapshot.membersByServerAndUserID.values where member.id.serverID == serverID {
            seen.insert(member.id.userID)
            targets.append((member.id.userID, member, false))
        }
        for userID in knownBannedUserIDs where !seen.contains(userID) {
            targets.append((userID, nil, false))
        }
        return targets
    }

    private func recordPhase46Prewarm(
        trigger: Phase46PrewarmTrigger,
        key: Phase46ModerationPrewarmKey,
        result: Phase46PrewarmResult,
        preparedMemberCount: Int
    ) {
        let previous = phase46MemberPanelPrewarmState
        let attemptCount = previous.attemptCount + 1
        let dedupeCount = previous.dedupeCount + (result == .deduped || result == .skippedInFlight ? 1 : 0)
        phase46MemberPanelPrewarmState = Phase46MemberPanelPrewarmState(
            preparedKey: result == .prepared ? key : previous.preparedKey,
            inFlightKey: nil,
            lastTrigger: trigger,
            lastResult: result,
            preparedMemberCount: result == .prepared ? preparedMemberCount : previous.preparedMemberCount,
            attemptCount: attemptCount,
            dedupeCount: dedupeCount
        )
        phase46FreezePreventionDiagnostics = Phase46FreezePreventionDiagnostics(
            renderCacheOnlyHits: phase46FreezePreventionDiagnostics.renderCacheOnlyHits,
            renderCacheOnlyMisses: phase46FreezePreventionDiagnostics.renderCacheOnlyMisses,
            lifecyclePrewarmAttempts: attemptCount,
            lifecyclePrewarmDedupes: dedupeCount,
            lastTrigger: trigger,
            lastResult: result,
            lastPreparedMemberCount: result == .prepared ? preparedMemberCount : previous.preparedMemberCount
        )
    }

    private func selectedOrFallbackModerationTextChannel() -> Channel? {
        selectedOrFallbackModerationTextChannel(in: selectedServer, snapshot: snapshot)
    }

    private func selectedOrFallbackModerationTextChannel(in server: Server?, snapshot: RealtimeSnapshot) -> Channel? {
        guard let server else { return nil }
        if let channelID = selection.channelID,
           let channel = snapshot.channelsByID[channelID],
           channel.serverID == server.id,
           channel.kind == .textChannel {
            return channel
        }
        return firstModerationTextChannel(in: server, snapshot: snapshot)
    }

    private func firstModerationTextChannel(in server: Server, snapshot: RealtimeSnapshot) -> Channel? {
        if !server.channelIDs.isEmpty {
            for channelID in server.channelIDs {
                guard let channel = snapshot.channelsByID[channelID],
                      channel.serverID == server.id,
                      channel.kind == .textChannel
                else {
                    continue
                }
                return channel
            }
            return nil
        }
        var first: Channel?
        for channel in snapshot.channelsByID.values where channel.serverID == server.id && channel.kind == .textChannel {
            guard let current = first else {
                first = channel
                continue
            }
            if channel.displayName.localizedCaseInsensitiveCompare(current.displayName) == .orderedAscending {
                first = channel
            }
        }
        return first
    }

    private func resolvedModerationTargetMember(targetUserID: UserID, member: ServerMember?) -> ServerMember? {
        if let member { return member }
        guard let serverID = selectedServer?.id else { return nil }
        return snapshot.membersByServerAndUserID[ServerMemberKey(serverID: serverID, userID: targetUserID)]
    }

    private func moderationTimeoutBucket(_ timeout: Date?) -> String {
        guard let timeout else { return "none" }
        return timeout > Date() ? "active" : "expired"
    }

    private func moderationContext(targetUserID: UserID, member: ServerMember?, allowNonMemberBan: Bool) -> ModerationActionContext {
        let baseContext = moderationBaseContextSnapshot(prewarmKey: phase46ModerationPrewarmKey())
        return ModerationActionContext(
            currentUserID: baseContext.currentUserID,
            server: baseContext.server,
            currentMember: baseContext.currentMember,
            targetUserID: targetUserID,
            targetMember: resolvedModerationTargetMember(targetUserID: targetUserID, member: member),
            knownBannedUserIDs: baseContext.knownBannedUserIDs,
            permissionResolution: baseContext.permissionResolution,
            isConnectedForLiveActions: baseContext.isConnectedForLiveActions,
            routeAvailability: baseContext.routeAvailability,
            allowNonMemberBan: allowNonMemberBan
        )
    }

    private var knownBannedUserIDs: Set<UserID> {
        guard case let .loaded(result) = banListState else { return [] }
        return Set(result.bans.map(\.id.userID))
    }

    private func routeCategory(for action: ModerationAction) -> String {
        switch action {
        case .kick:
            "DELETE /servers/{server_id}/members/{member_id}"
        case .ban:
            "PUT /servers/{server}/bans/{target}"
        case .unban:
            "DELETE /servers/{server}/bans/{target}"
        case .timeout, .removeTimeout:
            "PATCH /servers/{server_id}/members/{member_id}"
        }
    }

    private func moderationSafeErrorCategory(_ error: any Error) -> String {
        if let apiError = error as? StoatAPIError {
            switch apiError {
            case .missingAuthentication, .unauthorized:
                return "authentication"
            case .forbidden:
                return "permission"
            case .notFound:
                return "notFound"
            case .rateLimited:
                return "rateLimited"
            case .decodingFailed:
                return "decode"
            case .transport:
                return "network"
            case .unimplementedEndpoint:
                return "routeUnavailable"
            case .invalidEnvironment:
                return "environment"
            case .serverError:
                return "server"
            case .invalidURL, .unknown:
                return "unknown"
            }
        }
        return "unknown"
    }

    private func updateModerationDiagnostics(
        action: ModerationAction?,
        targetUserID: UserID?,
        targetMember: ServerMember?,
        permissionResult: String,
        requestResult: String,
        routeCategory: String,
        responseShape: String = "none",
        safeError: String = "none",
        durationBucket: String = "none",
        memberMutation: String,
        elapsed: TimeInterval? = nil
    ) {
        let counts = moderationDashboardCounts()
        moderationDiagnostics = ModerationDiagnostics(
            lastActionCategory: action?.diagnosticsCategory ?? routeCategory,
            selectedServerPresenceCategory: selectedServer == nil ? "none" : "selected",
            targetCategory: moderationTargetCategory(userID: targetUserID, member: targetMember),
            permissionResultCategory: permissionResult,
            routeCategory: routeCategory,
            requestResultCategory: requestResult,
            responseShapeCategory: responseShape,
            safeErrorCategory: safeError,
            durationBucket: durationBucket,
            memberCacheMutationCategory: memberMutation,
            bansKnownCount: counts.knownBans,
            bansRenderedCount: counts.renderedBans,
            bansPendingCount: counts.pendingBans,
            timeoutsKnownCount: counts.knownTimeouts,
            timeoutsRenderedCount: counts.renderedTimeouts,
            timeoutsPendingCount: counts.pendingTimeouts,
            elapsedDurationBucket: elapsed.map(ModerationDiagnosticsFormatter.elapsedBucket) ?? "none",
            copiedDiagnosticsRedactedReasonText: true,
            targetIDPrefix: ModerationDiagnosticsFormatter.shortID(targetUserID?.rawValue),
            serverIDPrefix: ModerationDiagnosticsFormatter.shortID(selectedServer?.id.rawValue),
            cacheDiagnostics: moderationCacheDiagnostics,
            phase46Diagnostics: phase46FreezePreventionDiagnostics
        )
    }

    public func moderationDashboardCounts() -> ModerationDashboardCounts {
        let banCount: Int
        let pendingBans: Int
        switch banListState {
        case let .loaded(result):
            banCount = result.bans.count
            pendingBans = 0
        case .loading:
            banCount = 0
            pendingBans = 1
        case .idle, .failed:
            banCount = 0
            pendingBans = 0
        }
        let timeoutCount = selectedServer.map { server in
            serverMembers(for: server.id).filter { member in
                guard let timeout = member.timeout else { return false }
                return timeout > Date()
            }.count
        } ?? 0
        return ModerationDashboardCounts(
            knownBans: banCount,
            renderedBans: banCount,
            pendingBans: pendingBans,
            knownTimeouts: timeoutCount,
            renderedTimeouts: timeoutCount,
            pendingTimeouts: 0
        )
    }

    private func moderationTargetCategory(userID: UserID?, member: ServerMember?) -> String {
        guard let userID else { return "unknown" }
        if userID == currentUserID { return "self" }
        if knownBannedUserIDs.contains(userID) { return "banned" }
        if let member {
            if let timeout = member.timeout, timeout > Date() {
                return "timedOut"
            }
            return "member"
        }
        return "unknown"
    }

    private func mergeBanListIdentities(_ result: BanListResult) {
        for banned in result.users {
            upsertUser(User(id: banned.id, username: banned.username, discriminator: banned.discriminator ?? "0000", avatar: banned.avatar), source: .banList)
        }
    }

    private func hydrateMissingBanUsersIfNeeded(_ result: BanListResult, apiClient: any StoatAPIClient) async {
        let userIDsFromResult = Set(result.users.map(\.id))
        let missing = result.bans
            .map(\.id.userID)
            .filter { !userIDsFromResult.contains($0) && snapshot.usersByID[$0] == nil }
            .prefix(8)
        for userID in missing {
            if Task.isCancelled { return }
            if let user = try? await apiClient.fetchUser(userID: userID) {
                upsertUser(user, source: .banList)
            }
        }
    }

    private func patchBanListAfterBan(_ ban: ServerBan) {
        guard case var .loaded(result) = banListState else { return }
        result.bans.removeAll { $0.id == ban.id }
        result.bans.append(ban)
        result.bans.sort { $0.id.userID.rawValue < $1.id.userID.rawValue }
        banListState = .loaded(result)
    }

    private func patchBanListAfterUnban(serverID: ServerID, userID: UserID) {
        guard case var .loaded(result) = banListState else { return }
        result.bans.removeAll { $0.id.serverID == serverID && $0.id.userID == userID }
        result.users.removeAll { $0.id == userID }
        banListState = .loaded(result)
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
        mergePhase43Member(member, user: snapshot.usersByID[member.id.userID], source: .moderationAction)
        selectedMemberDetailID = member.id
        invalidateIdentityPresentationCaches()
        updateVisibleIdentityDiagnostics()
    }

    private func removeMember(serverID: ServerID, userID: UserID) {
        preservePhase43IdentityBeforeMemberRemoval(serverID: serverID, userID: userID)
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
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let data = try await Phase52FileIO.read(url)
                    let filename = url.lastPathComponent
                    let mimeType = filename.lowercased().hasSuffix(".jpg") || filename.lowercased().hasSuffix(".jpeg") ? "image/jpeg" : "image/png"
                    let draft = ServerMediaDraft(data: data, filename: filename, mimeType: mimeType)
                    if tag == .icons {
                        self.serverIconDraft = draft
                    } else if tag == .banners {
                        self.serverBannerDraft = draft
                    } else if tag == .emojis {
                        self.serverEmojiDraft = draft
                    }
                    switch tag {
                    case .icons:
                        self.phase25Status = "Icon draft selected; save to upload."
                    case .banners:
                        self.phase25Status = "Banner draft selected; save to upload."
                    case .emojis:
                        self.phase25Status = "Emoji draft selected; create to upload."
                    default:
                        break
                    }
                } catch {
                    self.phase25Status = "Could not read selected image."
                }
            }
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
            invalidateShellPresentation(reason: "channel created")
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
            channelEditState = .failed("Change a channel setting before saving.")
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
            invalidateShellPresentation(reason: "channel updated")
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
            invalidateShellPresentation(reason: "channel deleted")
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
        clearTypingIndicatorState()
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
        clearTypingIndicatorState()
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
        refreshTypingIndicatorState()
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
        // Resolve pending timeline visibility grace work while the departing channel is still
        // selected, so its message index is still valid for the final preview cancellations.
        if selectedConversationChannelID != id {
            clearTimelineVisibilityGrace()
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
        refreshTypingIndicatorState()
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

    public func showAppearanceSettings() {
        selectedSettingsTab = .appearance
        isCredentialSetupPresented = true
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

    public func syncFromSessionCoordinator() {
        guard let sessionCoordinator else { return }
        let nextMemberHydrationScope = [
            String(describing: sessionCoordinator.mode),
            sessionCoordinator.environment.stableID,
            sessionCoordinator.currentUser?.id.rawValue ?? "no-user",
            String(sessionCoordinator.liveConnectionGeneration)
        ].joined(separator: "|")
        if memberHydrationScope != nextMemberHydrationScope {
            clearMemberHydrationOverlay()
            memberHydrationScope = nextMemberHydrationScope
        }
        let previousNotificationGeneration = notificationLiveConnectionGeneration
        runtimeMode = sessionCoordinator.mode
        sessionState = sessionCoordinator.sessionState
        connectionState = sessionCoordinator.connectionState
        diagnostics = sessionCoordinator.diagnostics
        currentUser = sessionCoordinator.currentUser
        selection.isMemberPanelVisible = sessionCoordinator.preferences.memberPanelVisible
        messageDensity = sessionCoordinator.preferences.messageDensity
        reduceGlassIntensity = sessionCoordinator.preferences.reduceGlassIntensity
        liquidGlassTransparency = AppPreferences.clampedLiquidGlassTransparency(sessionCoordinator.preferences.liquidGlassTransparency)
        inlineImagePreviewPolicy = sessionCoordinator.preferences.inlineImagePreviewPolicy
        timelineTuning = sessionCoordinator.preferences.timelineTuning.validated()
        snapshot = snapshotWithHydratedMemberOverlay(sessionCoordinator.snapshot)
        phase51ShellDataRevision &+= 1
        schedulePhase51ShellPresentationRefresh(reason: "session snapshot")
        if sessionCoordinator.mode == .liveManual,
           previousNotificationGeneration != sessionCoordinator.liveConnectionGeneration {
            seenNotificationMessageIDsByChannelID = Self.messageIDMap(snapshot)
            notificationLiveConnectionGeneration = sessionCoordinator.liveConnectionGeneration
            deliveredNotificationIDs.removeAll()
            clearTypingIndicatorState(channelID: selectedConversationChannelID)
        } else if sessionCoordinator.mode != .liveManual {
            notificationLiveConnectionGeneration = nil
            seenNotificationMessageIDsByChannelID = Self.messageIDMap(snapshot)
            deliveredNotificationIDs.removeAll()
            notificationBanners.removeAll()
            clearTypingIndicatorState(channelID: selectedConversationChannelID)
        }
        messageActionHandler = sessionCoordinator.messageActionHandler
        let liveAPIClient = sessionCoordinator.mode == .liveManual ? sessionCoordinator.apiClient : nil
        attachmentUploadHandler = liveAPIClient.map { LiveAttachmentUploadHandler(apiClient: $0) } ?? MockAttachmentUploadHandler()
        if sessionCoordinator.mode == .liveManual {
            if imageDiskCache is NoopImageDiskCache {
                imageDiskCache = FileImageDiskCache()
            }
            remoteAttachmentLoader = LiveRemoteAttachmentLoader(environment: sessionCoordinator.environment, diskCache: imageDiskCache)
            imageResourceLoader = LiveImageResourceLoader(cache: imageMemoryCache, diskCache: imageDiskCache)
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
        var channelMessageCache: (any ChannelMessageCaching)?
        if sessionCoordinator.mode == .liveManual, let currentUserID = sessionCoordinator.currentUser?.id {
            channelMessageCache = FileChannelMessageCache(
                scopeIdentifier: "\(sessionCoordinator.environment.stableID)|\(currentUserID.rawValue)"
            )
        }
        messageController.configure(
            runtimeMode: sessionCoordinator.mode,
            apiClient: liveAPIClient,
            currentUserID: sessionCoordinator.currentUser?.id ?? (sessionCoordinator.mode == .mock ? MockShellData.currentUserID : nil),
            loadGeneration: sessionCoordinator.mode == .liveManual ? sessionCoordinator.liveConnectionGeneration : nil,
            messageCache: channelMessageCache
        )
        observe(snapshotSource: sessionCoordinator.snapshotSource)
        validateSelection()
        messageController.hydrate(from: snapshot)
        refreshTypingIndicatorState()
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
            let updates = snapshotSource.updates
            let current = await snapshotSource.currentSnapshot()
            await MainActor.run {
                self?.applySnapshotUpdate(
                    RealtimeSnapshotUpdate(
                        snapshot: current,
                        changes: RealtimeSnapshotChangeSet(isFullReplacement: true)
                    )
                )
            }
            for await update in updates {
                await MainActor.run {
                    self?.applySnapshotUpdate(update)
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
        guard state.text != draft else {
            phase63ComposerDiagnostics.duplicateDraftMutationCount += 1
            return
        }
        state.text = draft
        composerDrafts[channelID] = state
        phase63ComposerDiagnostics.acceptedDraftMutationCount += 1
        phase63ComposerDiagnostics.timelineGroupingBuildCountAtLastEdit = timelinePresentationDiagnostics.groupingBuildCount
        phase63ComposerDiagnostics.timelineRowRequestCountAtLastEdit = phase60Diagnostics.rowRequestCount
        phase63ComposerDiagnostics.viewportFlushCountAtLastEdit = phase60Diagnostics.coalescedViewportFlushCount
        scheduleTyping(for: channelID, draft: draft)
    }

    public func noteNativeComposerEdit() {
        phase63ComposerDiagnostics.nativeEditEventCount += 1
    }

    public func noteSuppressedComposerInlineTrigger() {
        phase63ComposerDiagnostics.inlineTriggerSuppressionCount += 1
    }

    public var commonEmojiItems: [String] {
        composerEmojiSections.flatMap(\.items).map(\.insertionText)
    }

    public var composerEmojiSections: [EmojiPickerSection] {
        composerEmojiCatalogSections
    }

    public func composerCustomEmojiImageData(for item: EmojiPickerItem) -> Data? {
        guard let mediaKey = item.customMediaKey else { return item.imageData }
        return loadedImageResources[ImageCacheKey(id: mediaKey, kind: .customEmoji)] ?? item.imageData
    }

    private var composerEmojiCatalogSections: [EmojiPickerSection] {
        let serverID = selectedConversationChannelID.flatMap { snapshot.channelsByID[$0]?.serverID } ?? selection.serverID
        let cacheKey = "\(phase68EmojiCatalogRevision)|\(serverID?.rawValue ?? "no-server")"
        if composerEmojiSectionCacheKey == cacheKey {
            return composerEmojiSectionCache
        }
        let common = Self.dedupedEmojiItems(["👍", "❤️", "😂", "🥯", "✅", "👀", "🎉", "🙏", "🔥", "✨", "🚀", "💯", "💬", "📌", "⭐", "❌"])
            .map(EmojiPickerItem.unicode)
        let smileys = Self.dedupedEmojiItems(["😄", "😅", "😎", "😢", "😮", "🤔", "🫡", "👋", "🙌", "😆", "😋", "😴", "😭", "😬", "😤", "🥳", "🤝", "🫶"])
            .map(EmojiPickerItem.unicode)
        let custom = phase68CustomEmojiIndexValue().sortedItems
        let currentServer = Self.dedupedCustomEmojiItems(custom.filter { item in
            guard let serverID else { return false }
            return item.serverID == serverID
        })
        let currentServerKeys = Set(currentServer.map { $0.shortcode.lowercased() })
        let otherServers = Self.dedupedCustomEmojiItems(custom.filter { item in
            guard let serverID else { return item.serverID != nil }
            return item.serverID != nil && item.serverID != serverID
        }).filter { !currentServerKeys.contains($0.shortcode.lowercased()) }
        let sections = [
            EmojiPickerSection(id: "common", title: "Common", items: common),
            EmojiPickerSection(id: "smileys", title: "Unicode", items: smileys),
            EmojiPickerSection(
                id: "current-server",
                title: "Current Server",
                items: currentServer.prefix(48).map(Self.composerEmojiPickerItem)
            ),
            EmojiPickerSection(
                id: "other-servers",
                title: "Other Servers",
                items: otherServers.prefix(48).map(Self.composerEmojiPickerItem)
            )
        ].filter { !$0.items.isEmpty }
        composerEmojiSectionCacheKey = cacheKey
        composerEmojiSectionCache = sections
        return sections
    }

    private static func composerEmojiPickerItem(_ item: CustomEmojiDisplayItem) -> EmojiPickerItem {
        let candidate = ComposerAutocompleteCandidate(
            kind: .emoji,
            rawID: item.id.rawValue,
            name: item.name
        )
        return EmojiPickerItem(
            id: "custom-\(item.id.rawValue)",
            insertionText: Phase71ComposerToken.insertionText(for: candidate),
            displayName: item.name,
            searchTerms: [item.name, item.shortcode],
            customMediaKey: item.file.id.rawValue
        )
    }

    private static func dedupedEmojiItems(_ items: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for item in items where seen.insert(item).inserted {
            result.append(item)
        }
        return result
    }

    private static func dedupedCustomEmojiItems(_ items: [CustomEmojiDisplayItem]) -> [CustomEmojiDisplayItem] {
        var seen: Set<String> = []
        return items.filter { item in
            let key = item.shortcode.lowercased()
            return seen.insert(key).inserted
        }
    }

    public func insertEmoji(_ emoji: String, at utf16Offset: Int? = nil, in channelID: ChannelID?) {
        guard let channelID else { return }
        let currentLength = (draft(for: channelID) as NSString).length
        let location = utf16Offset ?? currentLength
        _ = spliceComposerDraft(emoji, replacingUTF16Range: NSRange(location: location, length: 0), in: channelID)
        emojiPickerDiagnostics = emoji.hasPrefix(":") && emoji.hasSuffix(":") ? "Inserted custom emoji shortcode" : "Inserted Unicode emoji"
        requestFocus(.composer)
        composerFocusRequestID += 1
    }

    public func requestComposerCustomEmojiImage(_ item: EmojiPickerItem) {
        guard let mediaKey = item.customMediaKey,
              let emoji = snapshot.emojisByID[EmojiID(rawValue: mediaKey)]
        else { return }
        loadImageResource(for: CustomEmojiDisplayItem(emoji: emoji).file, kind: .customEmoji)
    }

    /// Server members for a server channel, or DM/group/Saved Notes participants otherwise --
    /// the raw candidate pool a `Phase58MentionCandidateIndex` sorts and searches.
    private func mentionCandidateSource(for channelID: ChannelID) -> [ComposerAutocompleteCandidate] {
        guard let channel = snapshot.channelsByID[channelID] else { return [] }
        let items: [MemberListItem]
        if let serverID = channel.serverID {
            items = cachedMemberListGroups(for: serverID).flatMap(\.items)
        } else {
            items = directMessageParticipantItems(for: channel)
        }
        return items
            .filter { $0.userID != currentUserID }
            .map { item in
                ComposerAutocompleteCandidate.user(
                    userID: item.userID,
                    name: item.displayName,
                    subtitle: item.subtitle,
                    avatarData: imageData(for: item.avatar, kind: .userAvatar),
                    searchAliases: [item.user?.username].compactMap { $0 }
                )
            }
    }

    /// Phase 58: rebuilds the candidate index only when the channel or snapshot revision changes,
    /// so a run of keystrokes within the same `@query` never re-derives it from scratch.
    private func autocompleteCandidateIndex(
        kind: ComposerAutocompleteKind,
        channelID: ChannelID
    ) -> Phase58MentionCandidateIndex {
        let channel = snapshot.channelsByID[channelID]
        let serverID = channel?.serverID
        let revision = kind == .emoji ? phase68EmojiCatalogRevision : snapshotRevision
        let scopeID = kind == .user ? channelID.rawValue : (serverID?.rawValue ?? "no-server")
        if kind == .emoji {
            _ = phase68CustomEmojiIndexValue()
        }
        if let cached = autocompleteIndexCache[kind], cached.scopeID == scopeID, cached.revision == revision {
            return cached.index
        }
        let candidates: [ComposerAutocompleteCandidate]
        switch kind {
        case .user:
            candidates = mentionCandidateSource(for: channelID)
        case .channel:
            candidates = channelAutocompleteCandidates(for: channelID)
        case .role:
            candidates = roleAutocompleteCandidates(for: channelID)
        case .emoji:
            candidates = emojiAutocompleteCandidates(for: serverID)
        }
        let index = Phase58MentionCandidateIndex(candidates: candidates)
        autocompleteIndexCache[kind] = (scopeID: scopeID, revision: revision, index: index)
        return index
    }

    private func channelAutocompleteCandidates(for channelID: ChannelID) -> [ComposerAutocompleteCandidate] {
        guard let serverID = snapshot.channelsByID[channelID]?.serverID else { return [] }
        return navigationHelper.visibleSelectableChannels(in: serverID, snapshot: snapshot)
            .filter { $0.kind == .textChannel }
            .map { channel in
                ComposerAutocompleteCandidate(
                    kind: .channel,
                    rawID: channel.id.rawValue,
                    name: channel.displayName,
                    subtitle: snapshot.serversByID[serverID]?.name
                )
            }
    }

    private func roleAutocompleteCandidates(for channelID: ChannelID) -> [ComposerAutocompleteCandidate] {
        guard let serverID = snapshot.channelsByID[channelID]?.serverID,
              let server = snapshot.serversByID[serverID]
        else { return [] }
        return server.roles.values.sorted {
            $0.rank == $1.rank
                ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                : $0.rank < $1.rank
        }.map { role in
            let color = ResolvedRoleColor(rawValue: role.colour, sourceRoleID: role.id)
            return ComposerAutocompleteCandidate(
                kind: .role,
                rawID: role.id.rawValue,
                name: role.name,
                subtitle: server.name,
                roleColor: color.map {
                    MessageInlineMentionColorComponents(red: $0.red, green: $0.green, blue: $0.blue)
                }
            )
        }
    }

    private func emojiAutocompleteCandidates(for serverID: ServerID?) -> [ComposerAutocompleteCandidate] {
        if let cache = emojiAutocompleteCache,
           cache.revision == phase68EmojiCatalogRevision,
           cache.serverID == serverID {
            return cache.candidates
        }
        let all = phase68CustomEmojiIndexValue().sortedItems
        let current = Self.dedupedCustomEmojiItems(all.filter { $0.serverID == serverID && serverID != nil })
        let currentShortcodes = Set(current.map { $0.shortcode.lowercased() })
        let other = Self.dedupedCustomEmojiItems(all.filter { item in
            item.serverID != nil && item.serverID != serverID
        }).filter { !currentShortcodes.contains($0.shortcode.lowercased()) }
        let candidates = (current + other).map { item in
            ComposerAutocompleteCandidate(
                kind: .emoji,
                rawID: item.id.rawValue,
                name: item.name,
                subtitle: item.serverID.flatMap { snapshot.serversByID[$0]?.name },
                avatarData: loadedImageResources[ImageCacheKey(id: item.file.id.rawValue, kind: .customEmoji)],
                literalText: ":\(item.shortcode):",
                searchAliases: [item.shortcode]
            )
        }
        emojiAutocompleteCache = (phase68EmojiCatalogRevision, serverID, candidates)
        return candidates
    }

    public func requestComposerAutocompleteEmojiImage(_ candidate: ComposerAutocompleteCandidate) {
        guard candidate.kind == .emoji,
              let emoji = snapshot.emojisByID[EmojiID(rawValue: candidate.rawID)]
        else { return }
        loadImageResource(for: CustomEmojiDisplayItem(emoji: emoji).file, kind: .customEmoji)
    }

    public func composerInlineTriggerChanged(_ trigger: InlineComposerTrigger?, for channelID: ChannelID?) {
        phase63ComposerDiagnostics.inlineTriggerPublicationCount += 1
        guard let channelID, let trigger else {
            clearComposerAutocomplete()
            return
        }
        composerAutocompleteTrigger = trigger
        let matches = autocompleteCandidateIndex(kind: trigger.kind, channelID: channelID)
            .matches(prefix: trigger.query, limit: 10)
        composerAutocompleteCandidates = matches
        if let highlighted = composerAutocompleteHighlightedID, matches.contains(where: { $0.id == highlighted }) {
            return
        }
        composerAutocompleteHighlightedID = matches.first?.id
    }

    public func navigateComposerMentionAutocomplete(_ direction: MentionAutocompleteNavigation) {
        guard !composerAutocompleteCandidates.isEmpty else { return }
        let ids = composerAutocompleteCandidates.map(\.id)
        guard let highlighted = composerAutocompleteHighlightedID, let currentIndex = ids.firstIndex(of: highlighted) else {
            composerAutocompleteHighlightedID = ids.first
            return
        }
        switch direction {
        case .up:
            composerAutocompleteHighlightedID = ids[max(0, currentIndex - 1)]
        case .down:
            composerAutocompleteHighlightedID = ids[min(ids.count - 1, currentIndex + 1)]
        }
    }

    public func selectHighlightedComposerMentionCandidate(for channelID: ChannelID?) {
        guard let candidate = composerAutocompleteCandidates.first(where: { $0.id == composerAutocompleteHighlightedID }) else {
            clearComposerAutocomplete()
            return
        }
        selectComposerAutocompleteCandidate(candidate, for: channelID)
    }

    /// Splices the verified `<@ULID>` token (Docs/Research.md Phase 58 Notes) into the composer
    /// draft at the trigger's exact range, then requests the caret land right after it.
    public func selectComposerAutocompleteCandidate(_ candidate: ComposerAutocompleteCandidate, for channelID: ChannelID?) {
        defer { clearComposerAutocomplete() }
        guard let channelID, let trigger = composerAutocompleteTrigger else { return }
        _ = spliceComposerDraft(
            Phase71ComposerToken.insertionText(for: candidate),
            replacingUTF16Range: NSRange(location: trigger.utf16Location, length: trigger.utf16Length),
            in: channelID
        )
    }

    @discardableResult
    private func spliceComposerDraft(
        _ replacement: String,
        replacingUTF16Range range: NSRange,
        in channelID: ChannelID
    ) -> Bool {
        guard range.location >= 0, range.length >= 0 else { return false }
        let currentText = draft(for: channelID)
        let nsText = currentText as NSString
        let location = min(range.location, nsText.length)
        let length = min(range.length, nsText.length - location)
        let effectiveRange = NSRange(location: location, length: length)
        guard Range(effectiveRange, in: currentText) != nil else { return false }
        updateDraft(nsText.replacingCharacters(in: effectiveRange, with: replacement), for: channelID)
        composerCursorRequestCounter += 1
        composerCursorRequest = ComposerCursorRequest(
            id: composerCursorRequestCounter,
            utf16Offset: location + (replacement as NSString).length
        )
        return true
    }

    public func clearComposerAutocomplete() {
        guard composerAutocompleteTrigger != nil || !composerAutocompleteCandidates.isEmpty || composerAutocompleteHighlightedID != nil else {
            phase63ComposerDiagnostics.inlineTriggerSuppressionCount += 1
            return
        }
        composerAutocompleteTrigger = nil
        composerAutocompleteCandidates = []
        composerAutocompleteHighlightedID = nil
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
        phase68CustomEmojiIndexValue().item(for: raw, serverID: nil)
    }

    public func inlineCustomEmojiItems(for message: Message) -> [MessageInlineCustomEmojiItem] {
        let serverID = snapshot.channelsByID[message.channelID]?.serverID
        return phase68CustomEmojiIndexValue().matches(in: message.content, serverID: serverID)
            .map { match in
                let item = match.item
                return MessageInlineCustomEmojiItem(
                    shortcode: match.token,
                    name: item.name,
                    imageData: imageData(for: item.file, kind: .customEmoji)
                )
            }
    }

    public func loadCustomEmojiImages(for message: Message) {
        let serverID = snapshot.channelsByID[message.channelID]?.serverID
        let index = phase68CustomEmojiIndexValue()
        var requestedIDs: Set<EmojiID> = []
        for emojiKey in message.reactions.keys {
            if let item = index.item(for: emojiKey, serverID: serverID), requestedIDs.insert(item.id).inserted {
                loadImageResource(for: item.file, kind: .customEmoji)
            }
        }
        for item in index.items(in: message.content, serverID: serverID) where requestedIDs.insert(item.id).inserted {
            loadImageResource(for: item.file, kind: .customEmoji)
        }
    }

    private func customEmojiDisplayItemsForContext(channelID: ChannelID?) -> [CustomEmojiDisplayItem] {
        let serverID = channelID.flatMap { snapshot.channelsByID[$0]?.serverID } ?? selection.serverID ?? selectedConversationChannel?.serverID
        return phase68CustomEmojiIndexValue().sortedItems.filter { item in
                guard let serverID else { return true }
                return item.serverID == nil || item.serverID == serverID
            }
    }

    private func phase68CustomEmojiIndexValue() -> Phase68CustomEmojiIndex {
        if let phase68CustomEmojiIndex {
            phase68TraceDiagnostics.emojiIndexCacheHitCount += 1
            return phase68CustomEmojiIndex
        }
        let index = Phase68CustomEmojiIndex(emojisByID: snapshot.emojisByID)
        phase68CustomEmojiIndex = index
        phase68TraceDiagnostics.emojiIndexBuildCount += 1
        return index
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

    /// Records whether the immediate native paste path made it through the existing attachment
    /// validation policy. The next coordinator diagnostic consumes this aggregate result, so the
    /// developer-only log can distinguish a queued paste from a limit/size rejection.
    public func addPastedImageDataFromClipboard(_ data: Data, to channelID: ChannelID?) {
        let attachmentCountBefore = channelID.map { composerDraftState(for: $0).attachments.count } ?? 0
        addPastedImageData(data, to: channelID)
        recordClipboardPasteQueueMutation(
            attachmentCountBefore: attachmentCountBefore,
            channelID: channelID
        )
    }

    public func addAttachmentURLsFromClipboard(_ urls: [URL], to channelID: ChannelID?) {
        let attachmentCountBefore = channelID.map { composerDraftState(for: $0).attachments.count } ?? 0
        addAttachmentURLs(urls, to: channelID)
        recordClipboardPasteQueueMutation(
            attachmentCountBefore: attachmentCountBefore,
            channelID: channelID
        )
    }

    public func recordComposerPasteDiagnostic(_ diagnostic: ComposerPasteDiagnostic) {
        var resolvedDiagnostic = diagnostic
        if diagnostic.outcome == .queued,
           !clipboardPasteQueuedAttachment,
           clipboardPasteRejectedAttachment {
            resolvedDiagnostic.outcome = .rejected
        }
        clipboardPasteQueuedAttachment = false
        clipboardPasteRejectedAttachment = false
        lastAttachmentAction = resolvedDiagnostic.redactedDescription
        switch resolvedDiagnostic.outcome {
        case .rejected:
            placeholderStatus = composerError
        case .unsupported:
            composerError = "Clipboard media could not be read as an attachment."
            placeholderStatus = composerError
        case .queued:
            break
        }
    }

    private func recordClipboardPasteQueueMutation(
        attachmentCountBefore: Int,
        channelID: ChannelID?
    ) {
        let attachmentCountAfter = channelID.map { composerDraftState(for: $0).attachments.count } ?? 0
        if attachmentCountAfter > attachmentCountBefore {
            clipboardPasteQueuedAttachment = true
        } else {
            clipboardPasteRejectedAttachment = true
        }
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
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            let urls = panel.urls
            Task { @MainActor [weak self] in
                self?.addAttachmentURLs(urls, to: channelID)
            }
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
        composerAttachmentPresentation(for: channelID).chips
    }

    public func composerAttachmentPresentation(for channelID: ChannelID?) -> (chips: [ComposerAttachmentChip], summary: String?) {
        guard let channelID else { return ([], nil) }
        let attachments = composerDraftState(for: channelID).attachments
        if let cached = composerAttachmentPresentationCache[channelID], cached.attachments == attachments {
            return (cached.chips, cached.summary)
        }
        let chips = attachments.map { attachment in
            ComposerAttachmentChip(
                id: attachment.id,
                filename: attachment.filename,
                subtitle: attachment.displaySize,
                systemImage: systemImage(for: attachment.kind),
                status: chipStatus(for: attachment.status),
                previewData: attachment.previewData
            )
        }
        let summary: String?
        if attachments.isEmpty {
            summary = nil
        } else {
            let totalBytes = attachments.reduce(0) { $0 + $1.byteCount }
            let count = attachments.count == 1 ? "1 attachment" : "\(attachments.count) attachments"
            summary = "\(count) · \(ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file))"
        }
        composerAttachmentPresentationCache[channelID] = (attachments, chips, summary)
        return (chips, summary)
    }

    public func composerAttachmentSummary(for channelID: ChannelID?) -> String? {
        composerAttachmentPresentation(for: channelID).summary
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
            hydrateAttachmentPreviewState(AttachmentDisplayItem(file: file))
        }
    }

    public func embedDisplayItems(for message: Message) -> [MessageEmbedDisplayItem] {
        (message.embeds ?? []).enumerated().map { index, embed in
            hydratedEmbedDisplayItem(embed: embed, id: "embed-\(message.id.rawValue)-\(index)")
        }
    }

    private func hydratedEmbedDisplayItem(embed: Embed, id: String) -> MessageEmbedDisplayItem {
        let baseMediaItem = embed.media.map { AttachmentDisplayItem(file: $0) } ?? ExternalEmbedMediaFactory.mediaItem(for: embed)
        let mediaItem = baseMediaItem.map { hydrateAttachmentPreviewState($0) }
        return MessageEmbedDisplayItem(
            id: id,
            embed: embed,
            mediaItem: mediaItem,
            mediaPreviewData: mediaItem?.previewData
        )
    }

    /// Overlays current load state (progress/data/local-file) onto an already-constructed
    /// display item. Shared by the live per-message builders above and by
    /// `hydratedAttachmentItems`/`hydratedEmbedItems`, which apply the same overlay to items
    /// coming from the cached `TimelineRowPresentation` so images can appear as soon as they
    /// finish loading without forcing a full timeline row rebuild.
    private func hydrateAttachmentPreviewState(_ item: AttachmentDisplayItem) -> AttachmentDisplayItem {
        var item = item
        if item.kind == .video,
           case let .remote(fileID, tag, .none) = item.source,
           let baseURL = sessionCoordinator?.environment.mediaBaseURL ?? StoatAPIEnvironment.production.mediaBaseURL,
           let url = try? LiveRemoteAttachmentLoader.mediaURL(baseURL: baseURL, tag: tag, fileID: fileID, filename: nil) {
            item.source = .remote(fileID: fileID, tag: tag, url: url)
        }
        let imageKey = item.fileID.map { ImageCacheKey(id: $0.rawValue, kind: .attachmentPreview) }
        if let state = attachmentPreviewStates[item.id] ?? imageKey.flatMap({ imageResourceStates[$0] }) {
            item.previewState = state
        }
        if let loaded = loadedAttachmentData[item.id] {
            item.previewState = .readyRemote
            item.previewData = loaded.data
        } else if let imageKey, let data = loadedImageResources[imageKey] {
            item.previewState = .readyRemote
            item.previewData = data
        }
        if attachmentLocalFiles[item.id] != nil {
            item.previewState = .readyLocal
        }
        return item
    }

    /// Hydrates attachment items that came from the cached `TimelineRowPresentation` (which
    /// intentionally omits preview data/state so it isn't pinned in the row cache) with the
    /// current live load state. Call this at render time instead of reading
    /// `TimelineRowPresentation.attachmentItems` directly.
    public func hydratedAttachmentItems(_ items: [AttachmentDisplayItem]) -> [AttachmentDisplayItem] {
        items.map(hydrateAttachmentPreviewState)
    }

    /// Embed counterpart of `hydratedAttachmentItems(_:)`.
    public func hydratedEmbedItems(_ items: [MessageEmbedDisplayItem]) -> [MessageEmbedDisplayItem] {
        items.map { item in
            guard let mediaItem = item.mediaItem else { return item }
            let hydrated = hydrateAttachmentPreviewState(mediaItem)
            return MessageEmbedDisplayItem(
                id: item.id,
                embed: item.embed,
                mediaItem: hydrated,
                mediaPreviewData: hydrated.previewData
            )
        }
    }

    public func loadInlineImagePreviews(for message: Message) {
        guard inlineImagePreviewPolicy == .automaticSmallImages else { return }
        guard effectiveRuntimeMode == .liveManual || effectiveRuntimeMode == .mock else { return }
        for item in attachmentDisplayItems(for: message) where shouldAutoLoadInlineImage(item) {
            guard attachmentLoadTasks[item.id] == nil else { continue }
            guard !queuedInlinePreviewItems.contains(where: { $0.id == item.id }) else { continue }
            queuedInlinePreviewItems.append(item)
        }
        drainInlinePreviewQueue()
    }

    private func drainInlinePreviewQueue() {
        while attachmentLoadTasks.count < maxConcurrentInlinePreviewLoads, !queuedInlinePreviewItems.isEmpty {
            let item = queuedInlinePreviewItems.removeFirst()
            guard attachmentLoadTasks[item.id] == nil, shouldAutoLoadInlineImage(item) else { continue }
            attachmentLoadTasks[item.id] = Task { [weak self] in
                await self?.loadInlineImagePreview(item)
            }
        }
    }

    public func loadModeledEmbedMediaPreviews(for message: Message) {
        guard effectiveRuntimeMode == .liveManual || effectiveRuntimeMode == .mock else { return }
        for embed in message.embeds ?? [] {
            if let media = embed.media {
                let item = AttachmentDisplayItem(file: media)
                guard item.kind == .image else { continue }
                guard item.byteCount.map({ $0 <= 8 * 1024 * 1024 }) ?? true else { continue }
                loadImageResource(for: media, kind: .attachmentPreview)
            } else if let item = ExternalEmbedMediaFactory.mediaItem(for: embed).map(hydrateAttachmentPreviewState), item.kind == .image, shouldAutoLoadInlineImage(item) {
                guard attachmentLoadTasks[item.id] == nil else { continue }
                guard !queuedInlinePreviewItems.contains(where: { $0.id == item.id }) else { continue }
                queuedInlinePreviewItems.append(item)
            }
        }
        drainInlinePreviewQueue()
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
                self?.drainInlinePreviewQueue()
            }
        }
        do {
            let loaded = try await remoteAttachmentLoader.load(item, purpose: .preview)
            await MainActor.run {
                self.storeAttachmentPreviewData(loaded, for: item.id)
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
            queuedInlinePreviewItems.removeAll { $0.id == item.id }
            guard let task = attachmentLoadTasks[item.id] else { continue }
            task.cancel()
            attachmentLoadTasks[item.id] = nil
            if case .loading = attachmentPreviewStates[item.id] {
                attachmentPreviewStates[item.id] = .notLoaded
            }
        }
        drainInlinePreviewQueue()
    }

    public func imageData(for file: File?, kind: ImageResourceKind) -> Data? {
        guard let file else { return nil }
        return loadedImageResources[ImageCacheKey(id: file.id.rawValue, kind: kind)]
    }

    public func imageResourceBecameVisible(_ file: File?, kind: ImageResourceKind, consumerID: String) {
        guard let request = imageResourceRequest(for: file, kind: kind) else {
            visibleImageResourceRequestsByConsumer.removeValue(forKey: consumerID)
            return
        }
        visibleImageResourceRequestsByConsumer[consumerID] = request
        let priority: ImageResourceRequestPriority = consumerID.hasPrefix("timeline-avatar-")
            ? .visibleTimeline
            : .visibleMember
        enqueueImageResourceRequest(request, priority: priority)
    }

    public func imageResourceBecameHidden(consumerID: String) {
        visibleImageResourceRequestsByConsumer.removeValue(forKey: consumerID)
    }

    func memberAvatarBecameVisible(_ file: File?, consumerID: String) {
        memberAvatarHideTasksByConsumer.removeValue(forKey: consumerID)?.cancel()
        imageResourceBecameVisible(file, kind: .userAvatar, consumerID: consumerID)
    }

    func memberAvatarBecameHidden(consumerID: String) {
        memberAvatarHideTasksByConsumer.removeValue(forKey: consumerID)?.cancel()
        memberAvatarHideTasksByConsumer[consumerID] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(750))
            guard !Task.isCancelled else { return }
            self?.visibleImageResourceRequestsByConsumer.removeValue(forKey: consumerID)
            self?.memberAvatarHideTasksByConsumer.removeValue(forKey: consumerID)
        }
    }

    func clearMemberAvatarVisibility() {
        memberAvatarHideTasksByConsumer.values.forEach { $0.cancel() }
        memberAvatarHideTasksByConsumer.removeAll()
        visibleImageResourceRequestsByConsumer = visibleImageResourceRequestsByConsumer.filter {
            !$0.key.hasPrefix("member-panel-avatar-")
        }
    }

    var pendingMemberAvatarHideCount: Int {
        memberAvatarHideTasksByConsumer.count
    }

    /// Grace period before offscreen timeline rows release their visibility work. Rows bounce in
    /// and out of the lazy viewport on every scroll tick; releasing immediately (the pre-Phase 63
    /// behavior) thrashed avatar requests and inline-preview loads during fast scrolling. The
    /// member panel got the identical treatment in Phase 62.
    static let timelineVisibilityHideGraceMilliseconds = 750

    func timelineAvatarBecameVisible(_ file: File?, consumerID: String) {
        if timelineAvatarReleaseDeadlinesByConsumer.removeValue(forKey: consumerID) != nil {
            phase63ComposerDiagnostics.visibilityLeaseCancellationCount += 1
        }
        imageResourceBecameVisible(file, kind: .userAvatar, consumerID: consumerID)
    }

    func timelineAvatarBecameHidden(consumerID: String) {
        timelineAvatarReleaseDeadlinesByConsumer[consumerID] = Date().addingTimeInterval(
            Double(Self.timelineVisibilityHideGraceMilliseconds) / 1_000
        )
        phase63ComposerDiagnostics.visibilityLeaseScheduleCount += 1
        scheduleTimelineVisibilityLeaseFlushIfNeeded()
    }

    /// Called on conversation switch: the departing channel's rows are gone for sure, so pending
    /// grace work is resolved immediately instead of firing 750 ms into the new channel.
    func clearTimelineVisibilityGrace() {
        timelineVisibilityLeaseTask?.cancel()
        timelineVisibilityLeaseTask = nil
        timelineAvatarReleaseDeadlinesByConsumer.removeAll()
        visibleImageResourceRequestsByConsumer = visibleImageResourceRequestsByConsumer.filter {
            !$0.key.hasPrefix("timeline-avatar-")
        }
        let pendingCancellations = inlinePreviewReleaseDeadlinesByMessageID
        inlinePreviewReleaseDeadlinesByMessageID.removeAll()
        for messageID in pendingCancellations.keys {
            if let message = timelineMessageForVisibility(messageID)?.message {
                cancelInlineImagePreviews(for: message)
            }
        }
    }

    var pendingTimelineAvatarHideCount: Int {
        timelineAvatarReleaseDeadlinesByConsumer.count
    }

    var pendingInlinePreviewCancelCount: Int {
        inlinePreviewReleaseDeadlinesByMessageID.count
    }

    var hasActiveTimelineVisibilityLeaseWorker: Bool {
        timelineVisibilityLeaseTask != nil
    }

    private func scheduleInlinePreviewCancellation(for messageID: MessageID, channelID: ChannelID) {
        inlinePreviewReleaseDeadlinesByMessageID[messageID] = (
            channelID,
            Date().addingTimeInterval(Double(Self.timelineVisibilityHideGraceMilliseconds) / 1_000)
        )
        phase63ComposerDiagnostics.visibilityLeaseScheduleCount += 1
        scheduleTimelineVisibilityLeaseFlushIfNeeded()
    }

    private func scheduleTimelineVisibilityLeaseFlushIfNeeded() {
        guard timelineVisibilityLeaseTask == nil else { return }
        let deadlines = Array(timelineAvatarReleaseDeadlinesByConsumer.values)
            + inlinePreviewReleaseDeadlinesByMessageID.values.map(\.deadline)
        guard let earliest = deadlines.min() else { return }
        timelineVisibilityLeaseTask = Task { [weak self] in
            let delay = max(0, earliest.timeIntervalSinceNow)
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.timelineVisibilityLeaseTask = nil
            self.flushExpiredTimelineVisibilityLeases()
            self.scheduleTimelineVisibilityLeaseFlushIfNeeded()
        }
    }

    private func flushExpiredTimelineVisibilityLeases(now: Date = Date()) {
        let expiredAvatarConsumers = timelineAvatarReleaseDeadlinesByConsumer.compactMap { consumerID, deadline in
            deadline <= now ? consumerID : nil
        }
        for consumerID in expiredAvatarConsumers {
            timelineAvatarReleaseDeadlinesByConsumer[consumerID] = nil
            visibleImageResourceRequestsByConsumer[consumerID] = nil
            phase63ComposerDiagnostics.visibilityLeaseExpirationCount += 1
        }

        let expiredPreviewIDs = inlinePreviewReleaseDeadlinesByMessageID.compactMap { messageID, lease in
            lease.deadline <= now ? messageID : nil
        }
        for messageID in expiredPreviewIDs {
            guard let lease = inlinePreviewReleaseDeadlinesByMessageID.removeValue(forKey: messageID) else { continue }
            let visible = pendingVisibleMessageIDsByChannelID[lease.channelID]
                ?? visibleMessageIDsByChannelID[lease.channelID]
                ?? []
            guard !visible.contains(messageID) else { continue }
            if let message = timelineMessageForVisibility(messageID)?.message {
                cancelInlineImagePreviews(for: message)
            }
            phase63ComposerDiagnostics.visibilityLeaseExpirationCount += 1
        }
    }

    /// O(1) message lookup for the scroll-time visibility paths; the index is rebuilt with the
    /// timeline grouping cache, with a linear fallback for the brief window where the cache
    /// hasn't caught up to freshly arrived messages.
    private func timelineMessageForVisibility(_ messageID: MessageID) -> TimelineMessage? {
        if selectedTimelineGroupCacheChannelID == selectedConversationChannelID,
           let cached = selectedTimelineMessagesByIDCache[messageID] {
            return cached
        }
        return selectedTimelineMessages.first { $0.message.id == messageID }
    }

    func currentUserRailAvatarBecameVisible(_ file: File?) {
        imageResourceBecameVisible(
            file,
            kind: .userAvatar,
            consumerID: "shell-current-user-avatar"
        )
    }

    func currentUserRailAvatarBecameHidden() {
        imageResourceBecameHidden(consumerID: "shell-current-user-avatar")
    }

    private var visibleImageResourceKeys: Set<ImageCacheKey> {
        Set(visibleImageResourceRequestsByConsumer.values.map(\.cacheKey))
    }

    private func notePresentationEviction(_ key: ImageCacheKey) {
        imagePresentationEvictionCount += 1
        imagePresentationEvictedKeys.insert(key)
        imagePresentationEvictedOrder.removeAll { $0 == key }
        imagePresentationEvictedOrder.append(key)
        while imagePresentationEvictedOrder.count > 512, let oldest = imagePresentationEvictedOrder.first {
            imagePresentationEvictedOrder.removeFirst()
            imagePresentationEvictedKeys.remove(oldest)
        }
    }

    private func shouldInvalidateTimeline(for key: ImageCacheKey) -> Bool {
        switch key.kind {
        case .attachmentPreview:
            return true
        case .customEmoji:
            // Picker cells share the custom-emoji cache but must not rebuild up to 250 timeline
            // rows as their artwork arrives. Rebuild only when the selected timeline actually
            // contains this emoji in message content or reactions.
            guard let emoji = snapshot.emojisByID[EmojiID(rawValue: key.id)] else { return false }
            let shortcode = ":\(emoji.name):"
            return selectedTimelineMessages.contains { timelineMessage in
                timelineMessage.message.content?.localizedCaseInsensitiveContains(shortcode) == true
                    || timelineMessage.message.reactions.keys.contains { reactionKey in
                        reactionKey.caseInsensitiveCompare(key.id) == .orderedSame
                            || reactionKey.caseInsensitiveCompare(shortcode) == .orderedSame
                    }
            }
        case .userAvatar:
            // Avatar data is read directly by the row/member view. Rebuilding prepared
            // Markdown, actions, embeds, and reactions for an avatar completion caused
            // avoidable whole-timeline churn.
            return false
        case .attachmentOriginal, .serverIcon, .serverBanner, .profileBackground:
            return false
        }
    }

    private func storeImagePresentationData(_ data: Data, for key: ImageCacheKey) {
        if let existing = loadedImageResources[key] {
            imagePresentationByteCount -= existing.count
        }
        loadedImageResources[key] = data
        if key.kind == .customEmoji {
            emojiAutocompleteCache = nil
            autocompleteIndexCache[.emoji] = nil
            for index in composerAutocompleteCandidates.indices
                where composerAutocompleteCandidates[index].kind == .emoji
                    && composerAutocompleteCandidates[index].rawID == key.id {
                composerAutocompleteCandidates[index].avatarData = data
            }
        }
        imagePresentationByteCount += data.count
        imagePresentationOrder.removeAll { $0 == key }
        imagePresentationOrder.append(key)
        while imagePresentationByteCount > maxImagePresentationBytes, !imagePresentationOrder.isEmpty {
            let visibleKeys = visibleImageResourceKeys
            let evictionIndex = imagePresentationOrder.firstIndex { !visibleKeys.contains($0) } ?? imagePresentationOrder.startIndex
            let evicted = imagePresentationOrder.remove(at: evictionIndex)
            if let removed = loadedImageResources.removeValue(forKey: evicted) {
                imagePresentationByteCount -= removed.count
                imageResourceStates[evicted] = .notLoaded
                notePresentationEviction(evicted)
            }
        }
        if shouldInvalidateTimeline(for: key) {
            scheduleTimelineMediaInvalidation()
        }
    }

    private func removeImagePresentationData(for key: ImageCacheKey) {
        imagePresentationOrder.removeAll { $0 == key }
        if let removed = loadedImageResources.removeValue(forKey: key) {
            imagePresentationByteCount -= removed.count
        }
        if shouldInvalidateTimeline(for: key) {
            scheduleTimelineMediaInvalidation()
        }
    }

    private func storeAttachmentPreviewData(_ data: RemoteAttachmentData, for id: String) {
        if let existing = loadedAttachmentData[id] {
            attachmentPreviewByteCount -= existing.data.count
        }
        loadedAttachmentData[id] = data
        attachmentPreviewByteCount += data.data.count
        attachmentPreviewOrder.removeAll { $0 == id }
        attachmentPreviewOrder.append(id)
        while attachmentPreviewByteCount > maxAttachmentPreviewBytes,
              let oldest = attachmentPreviewOrder.first {
            attachmentPreviewOrder.removeFirst()
            if let removed = loadedAttachmentData.removeValue(forKey: oldest) {
                attachmentPreviewByteCount -= removed.data.count
                attachmentPreviewStates[oldest] = .notLoaded
            }
        }
        scheduleTimelineMediaInvalidation()
    }

    private func removeAttachmentPreviewData(for id: String) {
        attachmentPreviewOrder.removeAll { $0 == id }
        if let removed = loadedAttachmentData.removeValue(forKey: id) {
            attachmentPreviewByteCount -= removed.data.count
        }
        scheduleTimelineMediaInvalidation()
    }

    public func loadImageResource(for file: File?, kind: ImageResourceKind) {
        guard let request = imageResourceRequest(for: file, kind: kind) else { return }
        enqueueImageResourceRequest(request, priority: defaultImagePriority(for: kind))
    }

    private func enqueueImageResourceRequest(
        _ request: ImageResourceRequest,
        priority: ImageResourceRequestPriority
    ) {
        let key = request.cacheKey
        if freezePerformanceDiagnostics.mediaSafeModeEnabled,
           request.kind == .attachmentPreview || request.kind == .customEmoji || request.kind == .profileBackground,
           queuedImageResourceRequests.count > maxConcurrentImageResourceLoads * 2 {
            lastImageResourceAction = "Media-heavy safe mode: tap-to-load placeholder"
            return
        }
        guard loadedImageResources[key] == nil, imageResourceLoadTasks[key] == nil else { return }
        if var queued = queuedImageResourceRequests[key] {
            if priority < queued.priority {
                queued.priority = priority
                queuedImageResourceRequests[key] = queued
            }
            return
        }
        if imagePresentationEvictedKeys.remove(key) != nil {
            imagePresentationEvictedOrder.removeAll { $0 == key }
            imageReloadAfterEvictionCount += 1
        }
        if case .failed = imageResourceStates[key] {
            let failureCount = max(1, imageResourceFailureCounts[key] ?? 1)
            let retryDelay = min(60.0, 5.0 * pow(2.0, Double(failureCount - 1)))
            if let failedAt = imageResourceFailureDates[key],
               phase43Now().timeIntervalSince(failedAt) >= retryDelay {
                imageResourceStates.removeValue(forKey: key)
                imageResourceFailureDates.removeValue(forKey: key)
            } else {
                return
            }
        }
        imageResourceStates[key] = .loading
        imageResourceQueueSequence &+= 1
        queuedImageResourceRequests[key] = PrioritizedImageResourceRequest(
            request: request,
            priority: priority,
            sequence: imageResourceQueueSequence
        )
        imageQueueEnqueueCount += 1
        drainImageResourceQueue()
    }

    public func clearImageMemoryCache() async {
        await imageMemoryCache.removeAll()
        await imageDiskCache.removeAll()
        loadedImageResources.removeAll()
        imagePresentationOrder.removeAll()
        imagePresentationByteCount = 0
        imageResourceStates.removeAll()
        imageResourceFailureDates.removeAll()
        imageResourceFailureCounts.removeAll()
        queuedImageResourceRequests.removeAll()
        imagePresentationEvictedKeys.removeAll()
        imagePresentationEvictedOrder.removeAll()
        invalidateTimelineMediaPresentation()
        lastImageResourceAction = "Cleared image memory cache"
    }

    public func reloadVisibleImages() {
        for request in visibleImageResourceRequestsByConsumer.values {
            enqueueImageResourceRequest(request, priority: .visibleMember)
        }
        for message in selectedTimelineMessages.map(\.message) {
            loadInlineImagePreviews(for: message)
            loadModeledEmbedMediaPreviews(for: message)
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
            queuedCountByKind: countKinds(queuedImageResourceRequests.values.map(\.request.kind)),
            failedCountByKind: countKinds(imageResourceStates.compactMap { key, state in
                if case .failed = state { return key.kind }
                return nil
            }),
            mediaSafeModeEnabled: freezePerformanceDiagnostics.mediaSafeModeEnabled,
            visibleResourceCount: visibleImageResourceKeys.count,
            presentationEvictionCount: imagePresentationEvictionCount,
            reloadAfterEvictionCount: imageReloadAfterEvictionCount,
            queueEnqueueCount: imageQueueEnqueueCount,
            timelineMediaInvalidationCount: timelineMediaInvalidationCount
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
            if request.kind == .userAvatar {
                for pixelSize in [64, 76] {
                    let decodedKey = DecodedImageKey(data: loaded.data, pixelSize: pixelSize)
                    _ = await DecodedImagePipeline.prepare(data: loaded.data, key: decodedKey)
                }
            }
            await MainActor.run {
                self.storeImagePresentationData(loaded.data, for: request.cacheKey)
                self.imageResourceStates[request.cacheKey] = self.loadedImageResources[request.cacheKey] == nil ? .notLoaded : .readyRemote
                self.imageResourceFailureDates.removeValue(forKey: request.cacheKey)
                self.imageResourceFailureCounts.removeValue(forKey: request.cacheKey)
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
                self.imageResourceFailureDates[request.cacheKey] = self.phase43Now()
                self.imageResourceFailureCounts[request.cacheKey, default: 0] += 1
                self.lastImageResourceAction = "Image load failed"
                self.updateVisibleIdentityDiagnostics()
                self.updateFreezePerformanceDiagnostics(marker: self.lastImageResourceAction)
            }
        }
    }

    private func drainImageResourceQueue() {
        while imageResourceLoadTasks.count < maxConcurrentImageResourceLoads,
              let next = nextQueuedImageResourceRequest() {
            queuedImageResourceRequests.removeValue(forKey: next.key)
            imageResourceLoadTasks[next.key] = Task { [weak self] in
                await self?.loadImageResource(next.value.request)
            }
        }
        if queuedImageResourceRequests.count > maxConcurrentImageResourceLoads * 2 {
            lastImageResourceAction = "Media-heavy safe mode: image queue saturated"
            freezePerformanceDiagnostics.mediaSafeModeEnabled = true
        } else if freezePerformanceDiagnostics.mediaSafeModeEnabled, queuedImageResourceRequests.isEmpty {
            lastImageResourceAction = "Image queue drained: media safe mode off"
            freezePerformanceDiagnostics.mediaSafeModeEnabled = false
        }
        updateFreezePerformanceDiagnostics(marker: lastImageResourceAction)
    }

    private func nextQueuedImageResourceRequest() -> (key: ImageCacheKey, value: PrioritizedImageResourceRequest)? {
        queuedImageResourceRequests.min { lhs, rhs in
            if lhs.value.priority != rhs.value.priority {
                return lhs.value.priority < rhs.value.priority
            }
            return lhs.value.sequence < rhs.value.sequence
        }
    }

    private func loadVisibleIdentityImagesForCurrentSelection() {
        warmIdentityImagesForCurrentSelection()
    }

    private func warmIdentityImagesForCurrentSelection(limit: Int = 32) {
        var requests: [(ImageResourceRequest, ImageResourceRequestPriority)] = []
        var seen: Set<ImageCacheKey> = []

        func append(_ file: File?, kind: ImageResourceKind, priority: ImageResourceRequestPriority) {
            guard requests.count < limit,
                  let request = imageResourceRequest(for: file, kind: kind),
                  seen.insert(request.cacheKey).inserted
            else { return }
            requests.append((request, priority))
        }

        append(currentUser?.avatar, kind: .userAvatar, priority: .shellCritical)
        if let server = selectedServer {
            append(server.icon, kind: .serverIcon, priority: .shellCritical)
        }
        for timelineMessage in selectedTimelineMessages.reversed() where requests.count < limit {
            append(avatarFile(for: timelineMessage.message), kind: .userAvatar, priority: .identity)
        }
        for (request, priority) in requests {
            enqueueImageResourceRequest(request, priority: priority)
        }
        if let banner = selectedServer?.banner {
            guard let request = imageResourceRequest(for: banner, kind: .serverBanner) else { return }
            enqueueImageResourceRequest(request, priority: .background)
        }
    }

    private func defaultImagePriority(for kind: ImageResourceKind) -> ImageResourceRequestPriority {
        switch kind {
        case .userAvatar, .serverIcon:
            .identity
        case .customEmoji:
            .media
        case .attachmentPreview, .attachmentOriginal:
            .media
        case .serverBanner, .profileBackground:
            .background
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
        let userID = fallbackID ?? user?.id ?? member?.id.userID ?? UserID(rawValue: "unknown")
        return phase43IdentitySnapshots.resolvedDisplay(
            userID: userID,
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

    public func previewComposerAttachment(_ attachmentID: UUID, in channelID: ChannelID?) async {
        guard let draft = composerDraftState(for: channelID).attachments.first(where: { $0.id == attachmentID }) else { return }
        var item = AttachmentDisplayItem(attachmentDraft: draft)
        var data = draft.previewData
        var localFile: URL?
        if case let .fileURL(url) = draft.source {
            localFile = url
            if data == nil, draft.kind == .image {
                data = try? await Phase52FileIO.read(url)
            }
        }
        if data != nil || localFile != nil {
            item.previewState = .readyLocal
        } else if !item.kind.isPreviewable {
            item.previewState = .unsupported("Preview unavailable")
        }
        if let data {
            storeAttachmentPreviewData(
                RemoteAttachmentData(fileID: item.fileID, filename: item.displayName, contentType: item.contentType, byteCount: data.count, data: data),
                for: item.id
            )
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
            let data = try? await Phase52FileIO.read(localFile)
            attachmentPreview = AttachmentPreviewSheetItem(item: current, data: data, localFile: localFile, debugFileID: current.fileID?.rawValue)
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
            storeAttachmentPreviewData(loaded, for: current.id)
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

    public func previewEmbedMedia(_ item: AttachmentDisplayItem) async {
        seedAttachmentPreviewDataIfPresent(item)
        await previewAttachment(item)
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

    public func downloadEmbedMedia(_ item: AttachmentDisplayItem) async {
        seedAttachmentPreviewDataIfPresent(item)
        await downloadAttachment(item)
    }

    public func openAttachmentExternally(_ item: AttachmentDisplayItem) async {
        var current = itemWithCurrentPreviewState(item)
        do {
            let url: URL
            if let existing = attachmentLocalFiles[current.id] {
                url = existing
            } else if let original = loadedAttachmentOriginalData[current.id] ?? loadedAttachmentData[current.id] {
                url = try await Phase52FileIO.writeTemporaryAttachment(data: original.data, filename: current.displayName)
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

    public func openEmbedMediaExternally(_ item: AttachmentDisplayItem) async {
        seedAttachmentPreviewDataIfPresent(item)
        await openAttachmentExternally(item)
    }

    public func retryAttachmentPreview(_ item: AttachmentDisplayItem) async {
        attachmentPreviewStates[item.id] = .notLoaded
        removeAttachmentPreviewData(for: item.id)
        await previewAttachment(item)
    }

    public func retryEmbedMediaPreview(_ item: AttachmentDisplayItem) async {
        if let fileID = item.fileID {
            let key = ImageCacheKey(id: fileID.rawValue, kind: .attachmentPreview)
            removeImagePresentationData(for: key)
            imageResourceStates[key] = nil
            imageResourceFailureDates[key] = nil
        }
        await retryAttachmentPreview(item)
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

    private func seedAttachmentPreviewDataIfPresent(_ item: AttachmentDisplayItem) {
        guard let data = item.previewData, loadedAttachmentData[item.id] == nil else { return }
        storeAttachmentPreviewData(
            RemoteAttachmentData(
                fileID: item.fileID,
                filename: item.displayName,
                contentType: item.contentType,
                byteCount: data.count,
                data: data
            ),
            for: item.id
        )
        attachmentPreviewStates[item.id] = .readyRemote
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
        phase44Diagnostics.replyComposerSetCount += 1
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
        let authorIdentity = localSendAuthorIdentity(for: channelID)
        let replies = draftState.replyContext.map { [MessageReply(id: $0.messageID, mention: draftState.shouldMentionReplyAuthor)] }
        let attachmentIDs = draftState.attachments.compactMap(\.uploadedFileID)
        let attachmentFiles = draftState.attachments.compactMap { draft -> File? in
            guard let id = draft.uploadedFileID else { return nil }
            let itemID = "file-\(id.rawValue)"
            if draft.kind == .image,
               let previewData = localImagePreviewData(for: draft) {
                storeAttachmentPreviewData(
                    RemoteAttachmentData(fileID: id, filename: draft.filename, contentType: draft.mimeType, byteCount: previewData.count, data: previewData),
                    for: itemID
                )
            }
            return File(attachmentDraft: draft, uploadedFileID: id)
        }
        composerError = nil
        recordMessageSendDiagnostics(channelID: channelID, stage: .creatingOptimisticMessage, result: .pending, error: nil)
        recordMessageSendDiagnostics(channelID: channelID, stage: .sendingRequest, result: .pending, error: nil)
        pendingOwnSendScrollChannelID = channelID
        let didSend = await messageController.sendMessage(
            channelID: channelID,
            content: content,
            replies: replies,
            attachments: attachmentIDs,
            attachmentFiles: attachmentFiles,
            authorUser: authorIdentity.user,
            authorMember: authorIdentity.member,
            handler: messageActionHandler
        )
        if didSend {
            composerDrafts[channelID] = ComposerDraftState(channelID: channelID)
            phase44Diagnostics.replyComposerClearedAfterSendCount += draftState.replyContext == nil ? 0 : 1
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
            // A failed send may never have inserted an optimistic row, so no grouping pass would
            // consume the flag -- clear it rather than let a later incoming message trigger a jump.
            pendingOwnSendScrollChannelID = nil
            let error = messageController.lastErrorByChannelID[channelID] ?? "Message send failed."
            recordMessageSendDiagnostics(channelID: channelID, stage: .failed, result: .failed, error: error)
            messageActionStatus = error
            phase44Diagnostics.replyComposerPreservedAfterFailureCount += draftState.replyContext == nil ? 0 : 1
            if snapshot.channelsByID[channelID].map(DMChannelClassifier.isDirectMessageLike) == true {
                dmLiveTrace.composerTargetChannelID = channelID
                dmLiveTrace.lastError = MessageSendDiagnosticsFormatter.redact(error)
            }
        }
    }

    private func localImagePreviewData(for draft: ComposerAttachmentDraft) -> Data? {
        guard draft.kind == .image else { return nil }
        return draft.previewData
    }

    private func localSendAuthorIdentity(for channelID: ChannelID) -> (user: User?, member: ServerMember?) {
        guard let currentUserID else { return (nil, nil) }
        let snapshotUser = snapshot.usersByID[currentUserID]
        let presentationUser = currentUserForPresentation?.id == currentUserID ? currentUserForPresentation : nil
        let serverID = snapshot.channelsByID[channelID]?.serverID
        return (
            user: snapshotUser ?? presentationUser,
            member: member(for: currentUserID, serverID: serverID)
        )
    }

    /// Synchronous fallback presentation for any row whose phase60 preparation hasn't completed
    /// yet -- a just-sent local message, or any message re-entering a warmed channel after
    /// `synchronizeTimelineRowStates` discarded the previous channel's prepared states. Built
    /// entirely from live snapshot data (zero retention, cannot go stale); avatar bytes already
    /// in `loadedImageResources` render immediately instead of flashing initials. System rows
    /// return nil and keep the skeleton: they need prepared event pieces.
    func pendingRowFallbackPresentation(for timelineMessage: TimelineMessage) -> TimelineRowPresentation? {
        guard timelineMessage.message.system == nil else { return nil }
        let message = timelineMessage.message
        return TimelineRowPresentation(
            messageID: message.id,
            authorDisplay: resolvedUserDisplay(for: message),
            isSystemEvent: message.system != nil,
            attachmentItems: message.attachments?.map { AttachmentDisplayItem(file: $0) } ?? [],
            embedItems: message.embeds?.enumerated().map { index, embed in
                MessageEmbedDisplayItem(
                    id: "embed-\(message.id.rawValue)-\(index)",
                    embed: embed,
                    mediaItem: embed.media.map { AttachmentDisplayItem(file: $0) }
                )
            } ?? [],
            reactionItems: Phase17MessageActions.reactionSummaries(for: message, currentUserID: currentUserID).map { summary in
                MessageReactionDisplayItem(
                    emoji: summary.emoji,
                    count: summary.count,
                    hasCurrentUserReacted: summary.hasCurrentUserReacted
                )
            },
            mentionsCurrentUser: Phase52TimelineInteractionPreparer.mentionsCurrentUser(message, currentUserID: currentUserID)
        )
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
        phase59ReactionDiagnostics.attemptCount += 1
        guard timelineMessage.status == .confirmed else {
            rejectReaction("Wait for the message to finish sending before reacting.")
            return
        }
        guard let currentUserID else {
            rejectReaction("Reaction unavailable because the current account is unresolved.")
            return
        }
        guard canReact(to: timelineMessage.message) else {
            rejectReaction(
                isRuntimeSendCapable
                    ? "Reaction unavailable in this channel."
                    : "Reconnect before reacting."
            )
            return
        }
        let mutationKey = ReactionMutationKey(
            channelID: timelineMessage.message.channelID,
            messageID: timelineMessage.message.id,
            emoji: emoji
        )
        guard inFlightReactionMutations.insert(mutationKey).inserted else {
            phase59ReactionDiagnostics.deduplicatedCount += 1
            phase59ReactionDiagnostics.lastOutcome = "duplicate in-flight mutation"
            return
        }
        defer { inFlightReactionMutations.remove(mutationKey) }
        let hasReacted = timelineMessage.message.reactions[emoji]?.contains(currentUserID) == true
        messageController.applyReaction(
            channelID: timelineMessage.message.channelID,
            messageID: timelineMessage.message.id,
            emoji: emoji,
            userID: currentUserID,
            isAdding: !hasReacted
        )
        phase59ReactionDiagnostics.optimisticMutationCount += 1
        phase59ReactionDiagnostics.lastOutcome = hasReacted ? "optimistic remove" : "optimistic add"
        do {
            if hasReacted {
                try await messageActionHandler.removeReaction(channelID: timelineMessage.message.channelID, messageID: timelineMessage.message.id, emoji: emoji)
            } else {
                try await messageActionHandler.addReaction(channelID: timelineMessage.message.channelID, messageID: timelineMessage.message.id, emoji: emoji)
            }
            messageActionStatus = nil
            phase59ReactionDiagnostics.successCount += 1
            phase59ReactionDiagnostics.lastOutcome = hasReacted ? "remove confirmed" : "add confirmed"
        } catch {
            messageController.applyReaction(
                channelID: timelineMessage.message.channelID,
                messageID: timelineMessage.message.id,
                emoji: emoji,
                userID: currentUserID,
                isAdding: hasReacted
            )
            messageActionStatus = "Reaction failed: \(error.userFacingMessage)"
            phase59ReactionDiagnostics.rollbackCount += 1
            phase59ReactionDiagnostics.lastOutcome = "rolled back after failure"
            presentNotice("Reaction failed: \(error.userFacingMessage)", severity: .error)
        }
    }

    private func rejectReaction(_ message: String) {
        messageActionStatus = message
        phase59ReactionDiagnostics.unavailableCount += 1
        phase59ReactionDiagnostics.lastOutcome = "unavailable"
        presentNotice(message, severity: .warning)
    }

    public func currentReactionItems(for message: Message) -> [MessageReactionDisplayItem] {
        Phase52TimelineAssetContext(
            snapshot: snapshot,
            imageDataByKey: loadedImageResources,
            customEmojiIndex: phase68CustomEmojiIndexValue()
        ).reactionItems(for: message, currentUserID: currentUserID)
    }

    public func togglePin(_ timelineMessage: TimelineMessage) async {
        guard canPin(timelineMessage) else {
            placeholderStatus = "Selected message cannot be pinned."
            return
        }
        guard !pinnedMessagesState.inFlightActionMessageIDs.contains(timelineMessage.message.id) else {
            phase44Diagnostics.lastSafeStatus = "Duplicate pin action deduped"
            return
        }
        pinnedMessagesState.inFlightActionMessageIDs.insert(timelineMessage.message.id)
        defer {
            pinnedMessagesState.inFlightActionMessageIDs.remove(timelineMessage.message.id)
        }
        let shouldPin = !timelineMessage.message.isPinned
        do {
            if shouldPin {
                try await messageActionHandler.pinMessage(channelID: timelineMessage.message.channelID, messageID: timelineMessage.message.id)
            } else {
                try await messageActionHandler.unpinMessage(channelID: timelineMessage.message.channelID, messageID: timelineMessage.message.id)
            }
            messageController.applyPinState(channelID: timelineMessage.message.channelID, messageID: timelineMessage.message.id, isPinned: shouldPin)
            if shouldPin {
                phase44Diagnostics.pinActionSuccessCount += 1
            } else {
                phase44Diagnostics.unpinActionSuccessCount += 1
                updatePinnedMessagesLocalState(messageID: timelineMessage.message.id, isPinned: false)
            }
            messageActionStatus = shouldPin ? "Message pinned" : "Message unpinned"
        } catch {
            if shouldPin {
                phase44Diagnostics.pinActionFailureCount += 1
            } else {
                phase44Diagnostics.unpinActionFailureCount += 1
            }
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
        systemEventPresentation(for: message).plainText
    }

    public func systemEventProfileTarget(for message: Message) -> UserID? {
        guard let target = Phase27SystemEventPresenter.profileTarget(for: message),
              !resolvedUserDisplay(for: snapshot.usersByID[target], member: member(for: target, serverID: snapshot.channelsByID[message.channelID]?.serverID), fallbackID: target, serverID: snapshot.channelsByID[message.channelID]?.serverID).isFallback
        else { return nil }
        return target
    }

    public func systemEventPresentation(for message: Message) -> SystemEventPresentation {
        let channel = snapshot.channelsByID[message.channelID]
        let serverID = channel?.serverID
        return Phase27SystemEventPresenter.presentation(for: message) { [weak self] userID, role in
            guard let self else { return nil }
            let member = serverID.flatMap { self.snapshot.membersByServerAndUserID[ServerMemberKey(serverID: $0, userID: userID)] }
            let user = self.snapshot.usersByID[userID] ?? (userID == self.currentUser?.id ? self.currentUser : nil)
            let display = self.resolvedUserDisplay(for: user, member: member, fallbackID: userID, serverID: serverID)
            guard !display.isFallback else { return nil }
            let confidence: SystemEventParticipantConfidence = member != nil || user != nil ? .high : .medium
            return SystemEventParticipant(userID: userID, role: role, display: display, confidence: confidence)
        }
    }

    public func noteVisibleSystemEvent(_ message: Message) {
        mergePhase43MessageIdentity(message)
        let presentation = systemEventPresentation(for: message)
        if let target = Phase27SystemEventPresenter.profileTarget(for: message),
           systemEventProfileTarget(for: message) == nil {
            enqueuePhase43IdentityHydrationIfNeeded(target, source: .systemEvent)
        }
        for piece in presentation.pieces {
            if case let .participant(participant) = piece {
                enqueuePhase43IdentityHydrationIfNeeded(participant.userID, source: .systemEvent)
            }
        }
        updateVisibleIdentityDiagnostics()
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
        guard let channelID, typingIndicatorState.channelID == channelID else { return [] }
        return typingIndicatorState.activeUserIDs
            .compactMap { snapshot.usersByID[$0] }
            .sorted { ($0.displayName ?? $0.username) < ($1.displayName ?? $1.username) }
    }

    public func typingIndicatorText(for channelID: ChannelID?) -> String? {
        guard let channelID, typingIndicatorState.channelID == channelID else { return nil }
        let names = typingIndicatorState.activeUserIDs.map { typingDisplayName(userID: $0, channelID: channelID) }
        return TypingIndicatorState.displayText(names: names)
    }

    private func typingDisplayName(userID: UserID, channelID: ChannelID) -> String {
        let serverID = snapshot.channelsByID[channelID]?.serverID
        let display = resolvedUserDisplay(
            for: snapshot.usersByID[userID],
            member: member(for: userID, serverID: serverID),
            fallbackID: userID,
            serverID: serverID
        )
        return display.isFallback ? "Someone" : display.displayName
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
        var visible = pendingVisibleMessageIDsByChannelID[channelID]
            ?? visibleMessageIDsByChannelID[channelID]
            ?? []
        let wasVisible = visible.contains(messageID)
        guard wasVisible != isVisible else { return }
        if isVisible {
            visible.insert(messageID)
            if inlinePreviewReleaseDeadlinesByMessageID.removeValue(forKey: messageID) != nil {
                phase63ComposerDiagnostics.visibilityLeaseCancellationCount += 1
            }
        } else {
            visible.remove(messageID)
            // Cancellation waits out the recycling grace period; a row scrolled straight back
            // into view keeps its in-flight preview loads instead of restarting them.
            scheduleInlinePreviewCancellation(for: messageID, channelID: channelID)
        }
        pendingVisibleMessageIDsByChannelID[channelID] = visible
        phase60Diagnostics.visibilityEventCount += 1
        requestVisibleTimelineRows()

        visibleRangeUpdateTasks[channelID]?.cancel()
        let delay = timelineTuning.visibleRangeUpdateDebounceMilliseconds
        visibleRangeUpdateTasks[channelID] = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(for: .milliseconds(delay))
            }
            guard !Task.isCancelled else { return }
            self?.flushTimelineVisibility(channelID: channelID)
        }
    }

    private func flushTimelineVisibility(channelID: ChannelID) {
        visibleRangeUpdateTasks[channelID] = nil
        guard channelID == selectedConversationChannelID,
              let visible = pendingVisibleMessageIDsByChannelID[channelID]
        else { return }
        pendingVisibleMessageIDsByChannelID[channelID] = nil
        visibleMessageIDsByChannelID[channelID] = visible
        timelineVisibleRangeUpdateCount += 1
        phase60Diagnostics.coalescedViewportFlushCount += 1
        updateFreezePerformanceDiagnostics(marker: "visible range coalesced")
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
        replyPreviewState(for: message)?.plainText
    }

    public func replyPreviewItem(for message: Message) -> MessageRowReplyPreviewItem? {
        guard let state = replyPreviewState(for: message) else { return nil }
        let icon: String
        switch state.resolution {
        case .loaded:
            icon = "arrowshape.turn.up.left.fill"
        case .loading:
            icon = "arrowshape.turn.up.left"
        case .deleted, .inaccessible, .notFound, .unavailable, .notSupported:
            icon = "exclamationmark.bubble"
        }
        return MessageRowReplyPreviewItem(
            id: state.id,
            authorName: state.authorDisplayName,
            summary: state.summary,
            systemImage: icon,
            canOpen: state.canOpenTarget,
            accessibilityLabel: state.canOpenTarget ? "Jump to replied message, \(state.plainText)" : "Reply preview unavailable, \(state.plainText)"
        )
    }

    public func replyPreviewState(for message: Message) -> ReplyPreviewState? {
        guard let replyID = message.replies?.first else { return nil }
        if let referenced = selectedTimelineMessages.first(where: { $0.message.id == replyID })?.message {
            return replyPreviewState(message: message, referenced: referenced, canOpenTarget: true)
        }
        if let resolution = resolvedReferencesByChannelID[message.channelID]?[replyID] {
            switch resolution {
            case let .loaded(referenced):
                return replyPreviewState(message: message, referenced: referenced, canOpenTarget: true)
            case .deleted:
                return ReplyPreviewState(channelID: message.channelID, messageID: message.id, targetMessageID: replyID, resolution: .deleted, summary: "Original message was deleted", canOpenTarget: false)
            case .forbidden:
                return ReplyPreviewState(channelID: message.channelID, messageID: message.id, targetMessageID: replyID, resolution: .inaccessible, summary: "Original message is not accessible", canOpenTarget: false)
            case .notFound:
                return ReplyPreviewState(channelID: message.channelID, messageID: message.id, targetMessageID: replyID, resolution: .notFound, summary: "Original message was not found", canOpenTarget: false)
            case .rateLimited:
                return ReplyPreviewState(channelID: message.channelID, messageID: message.id, targetMessageID: replyID, resolution: .unavailable, summary: "Original message is temporarily unavailable", canOpenTarget: true)
            case let .unavailable(unavailableMessage):
                return ReplyPreviewState(channelID: message.channelID, messageID: message.id, targetMessageID: replyID, resolution: .unavailable, summary: unavailableMessage, canOpenTarget: true)
            case .notSupported:
                return ReplyPreviewState(channelID: message.channelID, messageID: message.id, targetMessageID: replyID, resolution: .notSupported, summary: "Live reference fetching is unavailable", canOpenTarget: false)
            }
        }
        return ReplyPreviewState(
            channelID: message.channelID,
            messageID: message.id,
            targetMessageID: replyID,
            resolution: .loading,
            summary: "Loading original message...",
            canOpenTarget: effectiveRuntimeMode == .liveManual
        )
    }

    public func prepareReplyPreview(for message: Message) {
        guard let replyID = message.replies?.first else { return }
        if selectedTimelineMessages.contains(where: { $0.message.id == replyID }) {
            phase44Diagnostics.replyPreviewResolvedLoaded += 1
            return
        }
        guard resolvedReferencesByChannelID[message.channelID]?[replyID] == nil else { return }
        phase44Diagnostics.replyPreviewResolvedUnloaded += 1
        resolveReferenceIfNeeded(channelID: message.channelID, messageID: replyID)
    }

    public func openReplyPreview(for message: Message) async {
        guard let replyID = message.replies?.first else { return }
        await navigateToMessage(
            MessageNavigationRequest(
                serverID: snapshot.channelsByID[message.channelID]?.serverID,
                channelID: message.channelID,
                messageID: replyID,
                source: .replyPreview,
                allowChannelFallback: false
            )
        )
    }

    private func replyPreviewState(message: Message, referenced: Message, canOpenTarget: Bool) -> ReplyPreviewState {
        let display = resolvedUserDisplay(for: referenced)
        let authorName = Phase44SafeSummary.safeDisplayName(referenced.masquerade?.name) ?? Phase44SafeSummary.safeDisplayName(display.displayName) ?? "Someone"
        return ReplyPreviewState(
            channelID: message.channelID,
            messageID: message.id,
            targetMessageID: referenced.id,
            resolution: .loaded,
            authorDisplayName: authorName,
            avatarFile: display.avatarFile,
            summary: Phase44SafeSummary.messageSummary(for: referenced),
            canOpenTarget: canOpenTarget
        )
    }

    @discardableResult
    public func navigateToMessage(_ request: MessageNavigationRequest) async -> MessageNavigationResult {
        recordPhase44JumpSource(request.source)
        guard messageNavigationCoordinator.begin(request) else {
            phase44Diagnostics.lastSafeStatus = "Duplicate message navigation deduped"
            return .deduped
        }
        defer {
            messageNavigationCoordinator.finish(request)
        }

        let started = Date()
        guard snapshot.channelsByID[request.channelID] != nil else {
            phase44Diagnostics.jumpUnavailableCount += 1
            phase44Diagnostics.lastSafeStatus = "Message channel unavailable"
            placeholderStatus = "Channel is unavailable."
            recordPhase44Duration("jump", startedAt: started)
            return .unavailable
        }

        if selectedConversationChannelID != request.channelID {
            selectChannel(request.channelID)
        }

        guard let messageID = request.messageID else {
            phase44Diagnostics.jumpDegradedToChannelCount += 1
            phase44Diagnostics.lastSafeStatus = "Navigated to channel only"
            placeholderStatus = nil
            recordPhase44Duration("jump", startedAt: started)
            return .channelOnly
        }

        if selectedTimelineMessages.contains(where: { $0.message.id == messageID }) {
            focusTargetMessage(channelID: request.channelID, messageID: messageID, source: request.source, duration: request.highlightDuration)
            phase44Diagnostics.jumpLoadedCount += 1
            phase44Diagnostics.lastSafeStatus = "Navigated to loaded message"
            recordTimelineCalibrationObservation(kind: .afterSearchJump)
            recordPhase44Duration("jump", startedAt: started)
            return .loaded
        }

        phase44Diagnostics.jumpUnloadedCount += 1
        guard effectiveRuntimeMode == .liveManual,
              effectiveSessionState == .connected,
              sessionCoordinator?.hydrationStatus.readyReceived == true
        else {
            if request.allowChannelFallback {
                phase44Diagnostics.jumpDegradedToChannelCount += 1
                phase44Diagnostics.lastSafeStatus = "Message unavailable, degraded to channel"
                placeholderStatus = "Opened channel; message is not loaded."
                recordPhase44Duration("jump", startedAt: started)
                return .channelOnly
            }
            phase44Diagnostics.jumpUnavailableCount += 1
            phase44Diagnostics.lastSafeStatus = "Message unavailable without live context"
            placeholderStatus = "Message is not loaded."
            recordPhase44Duration("jump", startedAt: started)
            return .unavailable
        }

        let loaded = await messageController.loadMessagesAround(channelID: request.channelID, targetMessageID: messageID)
        if loaded, selectedTimelineMessages.contains(where: { $0.message.id == messageID }) {
            focusTargetMessage(channelID: request.channelID, messageID: messageID, source: request.source, duration: request.highlightDuration)
            phase44Diagnostics.jumpLoadedCount += 1
            phase44Diagnostics.lastSafeStatus = "Loaded context and navigated to message"
            recordTimelineCalibrationObservation(kind: .afterSearchJump)
            recordPhase44Duration("jump", startedAt: started)
            return .loadedAfterContextFetch
        }

        if request.allowChannelFallback {
            phase44Diagnostics.jumpDegradedToChannelCount += 1
            phase44Diagnostics.lastSafeStatus = "Target unavailable, degraded to channel"
            placeholderStatus = loaded ? "Opened channel; target was not returned." : "Opened channel; target could not be loaded."
            recordPhase44Duration("jump", startedAt: started)
            return .channelOnly
        }

        phase44Diagnostics.jumpUnavailableCount += 1
        phase44Diagnostics.lastSafeStatus = loaded ? "Target was not returned" : "Target could not be loaded"
        placeholderStatus = loaded ? "Target message was not returned." : "Target message could not be loaded."
        recordPhase44Duration("jump", startedAt: started)
        return .unavailable
    }

    private func focusTargetMessage(channelID: ChannelID, messageID: MessageID, source: MessageNavigationSource, duration: TimeInterval) {
        timelineSelection = TimelineSelection(channelID: channelID, messageID: messageID, source: focusSource(for: source))
        let isVisible = timelineViewport.visibleRange?.channelID == channelID && timelineViewport.visibleRange?.visibleMessageIDs.contains(messageID) == true
        if !isVisible || timelineViewport.selectedMessageID != messageID {
            timelineViewport = viewportReducer.keepVisible(timelineViewport, messageID: messageID, reason: .jumpCommand)
        }
        setTargetHighlight(channelID: channelID, messageID: messageID, source: source, duration: duration)
        requestFocus(.timeline)
    }

    private func focusSource(for source: MessageNavigationSource) -> MessageFocusSource {
        switch source {
        case .notification:
            return .notification
        case .replyPreview, .pinnedMessage, .loadedSearch, .remoteSearch, .directRoute:
            return .mouse
        case .unreadMarker:
            return .scrollJump
        case .command:
            return .keyboard
        }
    }

    private func setTargetHighlight(channelID: ChannelID, messageID: MessageID, source: MessageNavigationSource, duration: TimeInterval) {
        targetHighlightClearTask?.cancel()
        let state = TargetMessageHighlightState(channelID: channelID, messageID: messageID, source: source, duration: duration)
        targetMessageHighlightState = state
        phase44Diagnostics.targetHighlightCount += 1
        targetHighlightClearTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(state.expiresAt.timeIntervalSince(state.startedAt) * 1_000)))
            await MainActor.run {
                guard self?.targetMessageHighlightState == state else { return }
                self?.targetMessageHighlightState = nil
            }
        }
    }

    public func isTargetMessageHighlighted(_ messageID: MessageID, channelID: ChannelID) -> Bool {
        guard let targetMessageHighlightState,
              targetMessageHighlightState.channelID == channelID,
              targetMessageHighlightState.messageID == messageID,
              targetMessageHighlightState.isActive()
        else { return false }
        return true
    }

    private func recordPhase44JumpSource(_ source: MessageNavigationSource) {
        phase44Diagnostics.jumpSourceCounts[source.rawValue, default: 0] += 1
    }

    private func recordPhase44SearchBucket(remote: Bool, count: Int) {
        let key = Phase44SafeSummary.bucket(for: count)
        if remote {
            phase44Diagnostics.searchRemoteResultBuckets[key, default: 0] += 1
        } else {
            phase44Diagnostics.searchLocalResultBuckets[key, default: 0] += 1
        }
    }

    private func recordPhase44Duration(_ prefix: String, startedAt: Date) {
        let elapsed = Date().timeIntervalSince(startedAt)
        let bucket: String
        switch elapsed {
        case ..<0.1:
            bucket = "\(prefix)<100ms"
        case ..<0.5:
            bucket = "\(prefix)<500ms"
        case ..<1.5:
            bucket = "\(prefix)<1500ms"
        default:
            bucket = "\(prefix)>=1500ms"
        }
        phase44Diagnostics.durationBuckets[bucket, default: 0] += 1
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
        Phase 60 timeline hardening
        visibilityEvents: \(phase60Diagnostics.visibilityEventCount)
        coalescedViewportFlushes: \(phase60Diagnostics.coalescedViewportFlushCount)
        rowRequests: \(phase60Diagnostics.rowRequestCount)
        rowDedupes: \(phase60Diagnostics.rowDedupeCount)
        rowCompletions: \(phase60Diagnostics.rowCompletionCount)
        staleRowDiscards: \(phase60Diagnostics.staleRowDiscardCount)
        activeSkeletons: \(phase60Diagnostics.activeSkeletonCount)
        maximumQueueDepth: \(phase60Diagnostics.maximumQueueDepth)
        Phase 63 composer isolation
        nativeEditEvents: \(phase63ComposerDiagnostics.nativeEditEventCount)
        acceptedDraftMutations: \(phase63ComposerDiagnostics.acceptedDraftMutationCount)
        duplicateDraftMutations: \(phase63ComposerDiagnostics.duplicateDraftMutationCount)
        inlineTriggerPublications: \(phase63ComposerDiagnostics.inlineTriggerPublicationCount)
        inlineTriggerSuppressions: \(phase63ComposerDiagnostics.inlineTriggerSuppressionCount)
        typingDeadlineResets: \(phase63ComposerDiagnostics.typingDeadlineResetCount)
        groupingBuildsAtLastEdit: \(phase63ComposerDiagnostics.timelineGroupingBuildCountAtLastEdit)
        rowRequestsAtLastEdit: \(phase63ComposerDiagnostics.timelineRowRequestCountAtLastEdit)
        viewportFlushesAtLastEdit: \(phase63ComposerDiagnostics.viewportFlushCountAtLastEdit)
        visibilityLeasesScheduled: \(phase63ComposerDiagnostics.visibilityLeaseScheduleCount)
        visibilityLeasesCancelled: \(phase63ComposerDiagnostics.visibilityLeaseCancellationCount)
        visibilityLeasesExpired: \(phase63ComposerDiagnostics.visibilityLeaseExpirationCount)
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
        let phase44 = Phase44DiagnosticsFormatter.redactedText(phase44Diagnostics)
        let text = Phase17MessageActions.redactedDiagnosticText(Phase6UIHelpers.safeDiagnostics(AttachmentDiagnosticsFormatter.redact(timeline + "\n" + attachmentText + "\n" + send + "\n" + dmTrace + "\n" + phase44)))
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

    public func copyRedactedModerationDiagnostics() {
        moderationDiagnostics.cacheDiagnostics = moderationCacheDiagnostics
        moderationDiagnostics.phase46Diagnostics = phase46FreezePreventionDiagnostics
        let text = ModerationDiagnosticsFormatter.redactedText(moderationDiagnostics)
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        placeholderStatus = "Moderation diagnostics copied"
        lastTimelineActionResult = "Copied redacted moderation diagnostics"
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
        refreshVisibleIdentityDiagnosticsSynchronously()
        publishFreezePerformanceDiagnostics(marker: "copied identity diagnostics")
        let identity = visibleIdentityDiagnostics
        let freeze = freezePerformanceDiagnostics
        let phase51 = phase51PerformanceDiagnostics
        let roles = memberRoleSortDiagnostics
        let text = Phase17MessageActions.redactedDiagnosticText(Phase6UIHelpers.safeDiagnostics("""
        Visible identity diagnostics
        unresolvedVisibleUsers: \(identity.unresolvedVisibleUserCount)
        shortenedVisibleIDs: \(identity.shortenedVisibleIDCount)
        avatarFailuresCached: \(identity.avatarFailureCacheCount)
        profileFetchMerges: \(identity.profileFetchMergeCount)
        memberWrapperUserMerges: \(identity.memberWrapperUserMergeCount)
        \(Phase43IdentityDiagnosticsFormatter.redactedText(identity.phase43))
        roleSortMode: \(roles.sortMode)
        roleGroupOrder: \(roles.groupOrder.joined(separator: ","))
        duplicateSuppression: \(roles.duplicateSuppressionCount)
        unknownRoles: \(roles.unknownRoleCount)
        memberGroupingCount: \(freeze.memberGroupingCount)
        memberGroupingCacheHits: \(freeze.memberGroupingCacheHitCount)
        capabilityCacheUpdates: \(freeze.capabilityCacheUpdateCount)
        markdownParse/cacheHits: \(freeze.markdownParseCount)/\(freeze.markdownCacheHitCount)
        imageActiveQueuedFailed: \(freeze.imageActiveCount)/\(freeze.imageQueuedCount)/\(freeze.imageFailedCount)
        imageVisible/evicted/reloaded: \(freeze.visibleImageResourceCount)/\(freeze.imagePresentationEvictionCount)/\(freeze.imageReloadAfterEvictionCount)
        imageEnqueued/timelineInvalidations: \(freeze.imageQueueEnqueueCount)/\(freeze.timelineMediaInvalidationCount)
        mediaSafeMode: \(freeze.mediaSafeModeEnabled ? "yes" : "no")
        visibleRangeUpdates: \(freeze.visibleRangeUpdateCount)
        lastMarker: \(freeze.lastMainThreadMarker ?? "-")
        phase51ShellBuilds: \(phase51.shellBuildCount)
        phase59ShellRequests/builds/skips: \(phase51.shellRequestCount)/\(phase51.shellBuildCount)/\(phase51.shellCacheHitCount)
        phase59ShellCoalesced/discarded: \(phase51.shellCoalescedCount)/\(phase51.shellDiscardedCount)
        phase59RelationshipCandidates: \(phase51.shellRelationshipCandidateCount)
        phase59LastShellReason: \(phase51.lastShellInvalidationReason ?? "-")
        phase51TimelineBuilds/cacheHits: \(phase51.timelineBuildCount)/\(phase51.timelineCacheHitCount)
        phase51ServerSettingsBuilds/cancellations: \(phase51.serverSettingsBuildCount)/\(phase51.serverSettingsCancellationCount)
        phase51DiagnosticsPublished/throttled: \(phase51.diagnosticsPublishCount)/\(phase51.diagnosticsThrottleCount)
        phase51MainThreadBudgetViolations: \(phase51.mainThreadBudgetViolationCount)
        phase51LastOperation: \(phase51.lastOperationCategory ?? "-") \(phase51.lastOperationMilliseconds.map(String.init) ?? "-")ms
        phase68IdentityNoOpMerges: \(phase68TraceDiagnostics.identityNoOpMergeCount)
        phase68MemberInvalidations: \(phase68TraceDiagnostics.memberListRelevantInvalidationCount)
        phase69SelectedMemberPublications: \(phase68TraceDiagnostics.selectedMemberListPublicationCount)
        phase68EmojiIndexBuilds/cacheHits: \(phase68TraceDiagnostics.emojiIndexBuildCount)/\(phase68TraceDiagnostics.emojiIndexCacheHitCount)
        phase68DiagnosticsRequests/coalesced/builds/stale: \(phase68TraceDiagnostics.visibleIdentityDiagnosticsRequestCount)/\(phase68TraceDiagnostics.visibleIdentityDiagnosticsCoalescedCount)/\(phase68TraceDiagnostics.visibleIdentityDiagnosticsBuildCount)/\(phase68TraceDiagnostics.visibleIdentityDiagnosticsStaleResultCount)
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
        let signatureStatus = testingSignedNotificationBuild
            ? "user marked signed build"
            : notificationSignatureCheckState.statusText
        return NotificationBuildReadinessDiagnostics(
            bundleIdentifier: bundleID,
            bundleDisplayName: displayName,
            appPath: appPath,
            codeSigningAllowed: "YES (ad-hoc) in checked Xcode build settings",
            detectedSignatureStatus: signatureStatus,
            sandboxStatus: sandbox,
            delegateConfigured: delegateConfigured,
            lastUNErrorName: request?.errorCodeName,
            lastBeforeStatus: request?.statusBefore.rawValue,
            lastAfterStatus: request?.statusAfter.rawValue,
            systemSettingsCheck: "If unavailable here, check System Settings > Notifications > Liquid Bagel manually.",
            testingSignedBuild: testingSignedNotificationBuild,
            signatureChecksStarted: notificationSignatureCheckStartCount,
            signatureChecksCompleted: notificationSignatureCheckCompletionCount,
            signatureCheckCacheHits: notificationSignatureCheckCacheHitCount
        )
    }

    @MainActor
    public func ensureNotificationSignatureStatus() {
        guard notificationSignatureCheckState == .notStarted else {
            notificationSignatureCheckCacheHitCount += 1
            return
        }

        notificationSignatureCheckState = .checking
        notificationSignatureCheckStartCount += 1
        let bundleURL = Bundle.main.bundleURL
        let prepare = notificationSignatureStatusPreparer
        notificationSignatureCheckTask = Task { [weak self] in
            let status = await prepare(bundleURL)
            guard !Task.isCancelled, let self else { return }
            notificationSignatureCheckCompletionCount += 1
            notificationSignatureCheckState = .finished(status)
            notificationSignatureCheckTask = nil
        }
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

    /// The namespaced `/sync/settings` key holding Liquid Bagel's allowlisted preferences.
    public static let cloudPreferencesKey = "liquidbagel:preferences"

    private var lastSettingsSyncTimestamp: Int64? {
        sessionCoordinator?.preferences.lastSettingsSyncTimestamp ?? localSettingsSyncTimestamp
    }

    public func fetchCloudPreferences(applyOlder: Bool = false) async {
        guard let apiClient = apiClientForCommunityAction() else {
            settingsSyncState = .failed("Reconnect before syncing preferences.")
            return
        }
        settingsSyncState = .working
        do {
            let response = try await apiClient.fetchSyncedSettings(keys: [Self.cloudPreferencesKey])
            guard let value = response[Self.cloudPreferencesKey] else {
                settingsSyncState = .empty
                return
            }
            if let last = lastSettingsSyncTimestamp, value.timestamp <= last, !applyOlder {
                settingsSyncState = .staleRemote(value.timestamp)
                return
            }
            let synced = try JSONDecoder().decode(SyncedClientPreferences.self, from: Data(value.rawValue.utf8))
            await applyCloudPreferences(synced, timestamp: value.timestamp)
            settingsSyncState = .applied(value.timestamp)
        } catch is DecodingError {
            settingsSyncState = .failed("Cloud preferences are in an unrecognized format.")
        } catch {
            settingsSyncState = .failed(Phase23Safety.safeError(error))
        }
    }

    public func pushCloudPreferences() async {
        guard let apiClient = apiClientForCommunityAction() else {
            settingsSyncState = .failed("Reconnect before syncing preferences.")
            return
        }
        settingsSyncState = .working
        let synced = SyncedClientPreferences(
            messageDensity: messageDensity,
            liquidGlassTransparency: liquidGlassTransparency,
            inlineImagePreviewPolicy: inlineImagePreviewPolicy,
            notificationPreferences: notificationPreferences
        )
        do {
            let payload = String(decoding: try JSONEncoder().encode(synced), as: UTF8.self)
            let timestamp = max(Int64(Date().timeIntervalSince1970 * 1000), (lastSettingsSyncTimestamp ?? 0) + 1)
            try await apiClient.setSyncedSettings([Self.cloudPreferencesKey: payload], timestamp: timestamp)
            localSettingsSyncTimestamp = timestamp
            await sessionCoordinator?.updatePreferences { preferences in
                preferences.lastSettingsSyncTimestamp = timestamp
            }
            settingsSyncState = .pushed(timestamp)
        } catch {
            settingsSyncState = .failed(Phase23Safety.safeError(error))
        }
    }

    private func applyCloudPreferences(_ synced: SyncedClientPreferences, timestamp: Int64) async {
        localSettingsSyncTimestamp = timestamp
        if let sessionCoordinator {
            await sessionCoordinator.updatePreferences { preferences in
                synced.apply(to: &preferences)
                preferences.lastSettingsSyncTimestamp = timestamp
            }
            syncFromSessionCoordinator()
        } else {
            messageDensity = synced.messageDensity
            liquidGlassTransparency = AppPreferences.clampedLiquidGlassTransparency(synced.liquidGlassTransparency)
            inlineImagePreviewPolicy = synced.inlineImagePreviewPolicy
        }
    }

    public func setSelectedChannelMuted(_ isMuted: Bool) {
        guard let channelID = selectedConversationChannelID else { return }
        phase44Diagnostics.muteSuppressionDecisionCounts[isMuted ? "localChannelMuteEnabled" : "localChannelMuteDisabled", default: 0] += 1
        phase44Diagnostics.lastSafeStatus = "Channel mute preference is local per-channel notification preference; server-wide cloud mute is not verified"
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
        let targetLoaded = route.messageID.map { messageID in
            selectedConversationChannelID == route.channelID && selectedTimelineMessages.contains { $0.message.id == messageID }
        } ?? true
        if effectiveRuntimeMode == .liveManual,
           !targetLoaded,
           (effectiveSessionState != .connected || sessionCoordinator?.hydrationStatus.readyReceived != true) {
            queueNotificationRoute(route)
            placeholderStatus = "Reconnect to open this message."
            recordNotificationRouteOutcome(.queuedAwaitingManualConnect)
            return
        }
        let result = await navigateToMessage(
            MessageNavigationRequest(
                serverID: route.serverID,
                channelID: route.channelID,
                messageID: route.messageID,
                source: .notification,
                allowChannelFallback: true
            )
        )
        switch result {
        case .loaded, .loadedAfterContextFetch, .channelOnly, .deduped:
            placeholderStatus = "Opened notification"
            recordNotificationRouteOutcome(.opened)
            if result == .channelOnly, route.messageID != nil {
                phase44Diagnostics.notificationRouteDegradedCount += 1
            }
        case .queued:
            recordNotificationRouteOutcome(.queuedAwaitingManualConnect)
        case .unavailable, .failed:
            placeholderStatus = "Notification target could not be opened."
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
        Task { [weak self] in
            await self?.navigateToMessage(
                MessageNavigationRequest(channelID: result.channelID, messageID: result.messageID, source: .loadedSearch)
            )
        }
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

    public func openPinnedMessages() {
        guard selectedConversationChannelID != nil else {
            placeholderStatus = "Select a channel before opening pinned messages."
            return
        }
        isPinnedMessagesPresented = true
        previousFocusTarget = focusTarget
        focusTarget = .quickSwitcher
        Task { [weak self] in
            await self?.refreshPinnedMessages()
        }
    }

    public func closePinnedMessages() {
        isPinnedMessagesPresented = false
        focusTarget = previousFocusTarget
    }

    public func closeChannelSearch() {
        isChannelSearchPresented = false
        focusTarget = previousFocusTarget
    }

    public func refreshPinnedMessages() async {
        guard effectiveRuntimeMode == .liveManual,
              effectiveSessionState == .connected,
              let channelID = selectedConversationChannelID,
              let apiClient = sessionCoordinator?.apiClient
        else {
            let message = "Pinned messages require a connected live session."
            pinnedMessagesState.loadState = selectedConversationChannelID.map { .failed($0, message) } ?? .idle
            phase44Diagnostics.pinnedListFailureCount += 1
            phase44Diagnostics.lastSafeStatus = message
            return
        }
        if case .loading(channelID) = pinnedMessagesState.loadState {
            return
        }
        pinnedMessagesState.loadState = .loading(channelID)
        phase44Diagnostics.pinnedListRequestCount += 1
        let started = Date()
        do {
            let messages = try await apiClient.searchMessages(
                channelID: channelID,
                request: ChannelMessageSearchRequest(pinned: true, limit: 50, sort: .latest, includeUsers: true)
            )
            let loadedIDs = Set(selectedTimelineMessages.map(\.message.id))
            for message in messages {
                mergePhase43MessageIdentity(message)
            }
            let items = messages.map { pinnedMessageDisplayItem(from: $0, loadedIDs: loadedIDs) }
            pinnedMessagesState.loadState = .loaded(channelID, items)
            pinnedMessagesState.lastUpdatedAt = Date()
            phase44Diagnostics.pinnedListSuccessCount += 1
            phase44Diagnostics.lastSafeStatus = items.isEmpty ? "Pinned list empty" : "Pinned list loaded"
            recordPhase44Duration("pinnedList", startedAt: started)
        } catch {
            let message = "Pinned messages failed: \(error.userFacingMessage)"
            pinnedMessagesState.loadState = .failed(channelID, message)
            phase44Diagnostics.pinnedListFailureCount += 1
            phase44Diagnostics.lastSafeStatus = message
            recordPhase44Duration("pinnedList", startedAt: started)
        }
    }

    private func pinnedMessageDisplayItem(from message: Message, loadedIDs: Set<MessageID>) -> PinnedMessageDisplayItem {
        let display = resolvedUserDisplay(for: message)
        let authorName = Phase44SafeSummary.safeDisplayName(message.masquerade?.name) ?? Phase44SafeSummary.safeDisplayName(display.displayName) ?? "Someone"
        return PinnedMessageDisplayItem(
            channelID: message.channelID,
            messageID: message.id,
            authorID: message.authorID,
            authorDisplayName: authorName,
            summary: Phase44SafeSummary.messageSummary(for: message),
            createdAt: message.createdAt,
            isPinned: true,
            isLoaded: loadedIDs.contains(message.id),
            canUnpin: true,
            status: loadedIDs.contains(message.id) ? "Loaded" : "Outside loaded range"
        )
    }

    public func openPinnedMessage(_ item: PinnedMessageDisplayItem) async {
        phase44Diagnostics.pinnedMessageJumpCount += 1
        let result = await navigateToMessage(
            MessageNavigationRequest(channelID: item.channelID, messageID: item.messageID, source: .pinnedMessage)
        )
        if !result.isSuccess {
            phase44Diagnostics.pinnedMessageUnavailableCount += 1
        }
    }

    public func unpinPinnedMessage(_ item: PinnedMessageDisplayItem) async {
        guard !pinnedMessagesState.inFlightActionMessageIDs.contains(item.messageID) else { return }
        pinnedMessagesState.inFlightActionMessageIDs.insert(item.messageID)
        defer {
            pinnedMessagesState.inFlightActionMessageIDs.remove(item.messageID)
        }
        do {
            try await messageActionHandler.unpinMessage(channelID: item.channelID, messageID: item.messageID)
            messageController.applyPinState(channelID: item.channelID, messageID: item.messageID, isPinned: false)
            updatePinnedMessagesLocalState(messageID: item.messageID, isPinned: false)
            messageActionStatus = "Message unpinned"
            phase44Diagnostics.unpinActionSuccessCount += 1
        } catch {
            messageActionStatus = "Unpin failed: \(error.userFacingMessage)"
            phase44Diagnostics.unpinActionFailureCount += 1
        }
    }

    private func updatePinnedMessagesLocalState(messageID: MessageID, isPinned: Bool) {
        guard case let .loaded(channelID, items) = pinnedMessagesState.loadState else { return }
        if isPinned {
            pinnedMessagesState.loadState = .loaded(channelID, items)
        } else {
            pinnedMessagesState.loadState = .loaded(channelID, items.filter { $0.messageID != messageID })
        }
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
            recordPhase44SearchBucket(remote: false, count: results.count)
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
                        sort: query.mode == .pinned ? .latest : .relevance,
                        includeUsers: true
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
                recordPhase44SearchBucket(remote: query.mode != .loadedOnly, count: results.count)
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
        focusTargetMessage(channelID: result.channelID, messageID: result.messageID, source: navigationSource(for: result), duration: 2)
    }

    public func selectSearchResult(_ result: ChannelSearchResult) {
        selectedSearchResultID = result.messageID
        refreshSearchHighlightState()
        let isLoadedNow = selectedTimelineMessages.contains { $0.message.id == result.messageID }
        searchNavigationStatus = isLoadedNow ? nil : "Result outside loaded range."
        if isLoadedNow {
            Task { [weak self] in
                await self?.navigateToMessage(
                    MessageNavigationRequest(channelID: result.channelID, messageID: result.messageID, source: self?.navigationSource(for: result) ?? .loadedSearch)
                )
            }
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
        Task { [weak self] in
            guard let self else { return }
            let navigationResult = await self.navigateToMessage(
                MessageNavigationRequest(channelID: result.channelID, messageID: result.messageID, source: self.navigationSource(for: result))
            )
            self.searchNavigationStatus = navigationResult.isSuccess ? "Jumped to search result" : "Result unavailable."
            self.lastTimelineActionResult = navigationResult.isSuccess ? "Jumped to search result" : "Search result unavailable"
        }
    }

    public func loadAroundSelectedSearchResult() async {
        guard let result = selectedSearchResult else { return }
        await loadAroundSearchResult(result)
    }

    public func loadAroundSearchResult(_ result: ChannelSearchResult) async {
        guard result.channelID == selectedConversationChannelID else { return }
        let navigationResult = await navigateToMessage(
            MessageNavigationRequest(channelID: result.channelID, messageID: result.messageID, source: navigationSource(for: result))
        )
        switch navigationResult {
        case .loaded, .loadedAfterContextFetch, .deduped:
            searchNavigationStatus = "Loaded around result"
            lastTimelineActionResult = "Loaded around search result"
            markSearchResultLoaded(result.messageID)
            refreshSearchHighlightState()
        case .channelOnly:
            searchNavigationStatus = "Opened channel; target was not returned."
            lastTimelineActionResult = "Search result degraded to channel"
        case .queued:
            searchNavigationStatus = "Navigation queued."
        case .unavailable, .failed:
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
                    sort: remoteSearchPinnedOnly ? .latest : .relevance,
                    includeUsers: true
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
            recordPhase44SearchBucket(remote: true, count: messages.count)
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

    private func navigationSource(for result: ChannelSearchResult) -> MessageNavigationSource {
        switch result.mode {
        case .loadedOnly:
            return .loadedSearch
        case .liveChannel:
            return .remoteSearch
        case .pinned:
            return .pinnedMessage
        }
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

    private func applySnapshotUpdate(_ update: RealtimeSnapshotUpdate) {
        guard !update.changes.isEmpty else { return }
        let oldSnapshot = self.snapshot
        reconcileHydratedMemberOverlay(with: update)
        let mergedSnapshot = snapshotWithHydratedMemberOverlay(update.snapshot)
        let refreshesShell = snapshotChangesAffectShell(update.changes, snapshot: mergedSnapshot)
        mergePhase43IdentityChanges(update.changes, snapshot: mergedSnapshot, previous: oldSnapshot)
        updateMemberSourceDiagnostics(changes: update.changes, current: mergedSnapshot)
        self.snapshot = mergedSnapshot
        if refreshesShell {
            phase51ShellDataRevision &+= 1
            schedulePhase51ShellPresentationRefresh(reason: "realtime shell change")
        }
        applyPhase46ModerationChanges(update.changes)
        if update.changes.isFullReplacement {
            messageController.hydrate(from: mergedSnapshot)
            seenNotificationMessageIDsByChannelID = Self.messageIDMap(mergedSnapshot)
        } else if !update.changes.messageChannelIDs.isEmpty {
            messageController.hydrate(channelIDs: update.changes.messageChannelIDs, from: mergedSnapshot)
        }
        for (channelID, deletedMessageIDs) in update.changes.deletedMessageIDsByChannelID {
            for messageID in deletedMessageIDs {
                messageController.removeMessage(channelID: channelID, messageID: messageID)
            }
        }
        processNotificationChanges(update.changes, snapshot: mergedSnapshot)
        previousSnapshot = mergedSnapshot
        restoreOrValidateSelection()
        let selectedChannelID = selectedConversationChannelID
        if update.changes.isFullReplacement
            || update.changes.channelIDs.contains(selectedChannelID ?? "") {
            acknowledgeSelectedChannel()
            scheduleSelectedChannelLoad()
            reconcileTimelineSelection()
        } else if update.changes.messageChannelIDs.contains(selectedChannelID ?? "") {
            acknowledgeSelectedChannel()
            reconcileTimelineSelection()
        }
        if update.changes.isFullReplacement
            || update.changes.typingChannelIDs.contains(selectedConversationChannelID ?? "") {
            refreshTypingIndicatorState()
        }
        if update.changes.affectsShellPresentation || !update.changes.unreadChannelIDs.isEmpty {
            updateDockBadge()
            updateNotificationDiagnostics()
            refreshDMDiagnosticsSnapshot()
        }
        replayQueuedNotificationRoutesIfReady()
        if update.changes.affectsShellPresentation,
           effectiveRuntimeMode == .liveManual,
           effectiveSessionState == .connected {
            loadVisibleIdentityImagesForCurrentSelection()
        }
    }

    private func snapshotChangesAffectShell(
        _ changes: RealtimeSnapshotChangeSet,
        snapshot: RealtimeSnapshot
    ) -> Bool {
        if changes.isFullReplacement
            || !changes.serverIDs.isEmpty
            || !changes.channelIDs.isEmpty
            || !changes.unreadChannelIDs.isEmpty {
            return true
        }
        if !changes.messageChannelIDs.isEmpty {
            let dmChannelIDs = Set(snapshot.channelsByID.values.lazy.filter(DMChannelClassifier.isDirectMessageLike).map(\.id))
            if !changes.messageChannelIDs.isDisjoint(with: dmChannelIDs) {
                return true
            }
        }
        guard !changes.userIDs.isEmpty else { return false }
        var shellUserIDs = Set(currentUser?.relations.map(\.id) ?? [])
        if let currentUserID {
            shellUserIDs.insert(currentUserID)
        }
        for channel in snapshot.channelsByID.values where DMChannelClassifier.isDirectMessageLike(channel) {
            shellUserIDs.formUnion(channel.recipients)
        }
        return !changes.userIDs.isDisjoint(with: shellUserIDs)
    }

    func replaceSnapshotForTesting(
        _ replacement: RealtimeSnapshot,
        changes: RealtimeSnapshotChangeSet = RealtimeSnapshotChangeSet(isFullReplacement: true)
    ) {
        applySnapshotUpdate(
            RealtimeSnapshotUpdate(
                snapshot: replacement,
                changes: changes
            )
        )
    }

    func mutateSnapshotForTesting(_ mutation: (inout RealtimeSnapshot) -> Void) {
        var replacement = snapshot
        mutation(&replacement)
        replaceSnapshotForTesting(replacement)
    }

    private func reconcileHydratedMemberOverlay(with update: RealtimeSnapshotUpdate) {
        guard !restHydratedMembersByServerID.isEmpty || !restHydratedUsersByServerID.isEmpty else { return }
        let incomingUsers: [UserID: User]
        if update.changes.isFullReplacement {
            incomingUsers = update.snapshot.usersByID
        } else {
            incomingUsers = update.changes.userIDs.reduce(into: [:]) { result, userID in
                result[userID] = update.snapshot.usersByID[userID]
            }
        }
        for (userID, user) in incomingUsers {
            for serverID in Array(restHydratedUsersByServerID.keys) where restHydratedUsersByServerID[serverID]?[userID] != nil {
                // Gateway updates are authoritative for live presence/status and replace the
                // stored REST copy so a later sparse gateway snapshot cannot regress them.
                restHydratedUsersByServerID[serverID]?[userID] = user
            }
        }
        for key in update.changes.memberKeys where restHydratedMembersByServerID[key.serverID] != nil {
            if let member = update.snapshot.membersByServerAndUserID[key] {
                restHydratedMembersByServerID[key.serverID]?[key] = member
            }
            if let user = update.snapshot.usersByID[key.userID] {
                restHydratedUsersByServerID[key.serverID, default: [:]][key.userID] = user
            }
        }
        for key in update.changes.removedMemberKeys where restHydratedMembersByServerID[key.serverID] != nil {
            restHydratedMembersByServerID[key.serverID]?[key] = nil
            restHydratedUsersByServerID[key.serverID]?[key.userID] = nil
        }
    }

    private func clearMemberHydrationOverlay() {
        memberHydrationTasks.values.forEach { $0.cancel() }
        memberHydrationTasks.removeAll()
        memberHydrationGenerations.removeAll()
        hydratedMemberServerIDs.removeAll()
        restHydratedMembersByServerID.removeAll()
        restHydratedUsersByServerID.removeAll()
        lastMemberHydrationRequestedAt.removeAll()
        memberHydrationLoadingServerIDs.removeAll()
        memberHydrationErrorsByServerID.removeAll()
        memberListGroupCacheKey = nil
        memberListGroupCache.removeAll()
        memberListLastGroupingServerID = nil
        memberListGroupsRevision &+= 1
    }

    private func mergePhase43IdentityChanges(
        _ changes: RealtimeSnapshotChangeSet,
        snapshot: RealtimeSnapshot,
        previous: RealtimeSnapshot
    ) {
        if changes.isFullReplacement {
            mergePhase43SnapshotIdentities(snapshot, source: .readyUser)
            preserveRemovedRealtimeMemberIdentities(previous: previous, current: snapshot)
            return
        }
        for userID in changes.userIDs {
            if let user = snapshot.usersByID[userID] {
                mergePhase43User(user, source: .realtimeUserUpdate)
            }
        }
        for key in changes.memberKeys {
            if let member = snapshot.membersByServerAndUserID[key] {
                mergePhase43Member(member, user: snapshot.usersByID[key.userID], source: .realtimeMemberUpdate)
            }
        }
        for key in changes.removedMemberKeys {
            if let member = previous.membersByServerAndUserID[key] {
                mergePhase43Member(member, user: previous.usersByID[key.userID], source: .realtimeMemberUpdate)
            }
            let before = phase43IdentitySnapshots.snapshot(for: key.userID)
            if phase43IdentitySnapshots.markMemberRemoved(
                userID: key.userID,
                serverID: key.serverID,
                now: phase43Now()
            ) {
                phase43MemberRemovalIdentityPreservationCount += 1
                phase43IdentityGeneration = phase43IdentitySnapshots.generation
                updatePhase68MemberIdentityRevisions(
                    before: before,
                    after: phase43IdentitySnapshots.snapshot(for: key.userID),
                    including: [key.serverID]
                )
            } else {
                phase68TraceDiagnostics.identityNoOpMergeCount += 1
            }
        }
    }

    private func applyPhase46ModerationChanges(_ changes: RealtimeSnapshotChangeSet) {
        guard changes.affectsModeration else { return }
        if changes.isFullReplacement || !changes.serverIDs.isEmpty {
            phase46ModerationVersions.serverVersion &+= 1
            phase46ModerationVersions.roleVersion &+= 1
            phase46ModerationVersions.permissionVersion &+= 1
        }
        if changes.isFullReplacement || !changes.channelIDs.isEmpty {
            phase46ModerationVersions.channelVersion &+= 1
            phase46ModerationVersions.permissionVersion &+= 1
        }
        if changes.isFullReplacement || !changes.memberKeys.isEmpty || !changes.removedMemberKeys.isEmpty {
            phase46ModerationVersions.memberVersion &+= 1
        }
        invalidateCapabilityCache()
    }

    private func snapshotWithHydratedMemberOverlay(_ incoming: RealtimeSnapshot) -> RealtimeSnapshot {
        guard !restHydratedMembersByServerID.isEmpty || !restHydratedUsersByServerID.isEmpty else { return incoming }
        var copy = incoming
        for (serverID, hydratedMembers) in restHydratedMembersByServerID {
            copy.membersByServerAndUserID = copy.membersByServerAndUserID.filter { $0.key.serverID != serverID }
            for (key, member) in hydratedMembers {
                copy.membersByServerAndUserID[key] = member
            }
        }
        for hydratedUsers in restHydratedUsersByServerID.values {
            for (userID, user) in hydratedUsers where copy.usersByID[userID] == nil {
                // A user present in the incoming gateway snapshot is always fresher. REST
                // copies only fill the sparse identities Ready/realtime did not include.
                copy.usersByID[userID] = user
            }
        }
        return copy
    }

    private func updateMemberSourceDiagnostics(
        changes: RealtimeSnapshotChangeSet,
        current: RealtimeSnapshot
    ) {
        guard changes.isFullReplacement
            || !changes.memberKeys.isEmpty
            || !changes.removedMemberKeys.isEmpty
        else { return }
        if let selectedServerID = selection.serverID {
            memberHydrationDiagnostics.missingUserCount = missingUserCount(serverID: selectedServerID)
        }
        if memberHydrationDiagnostics.source != .restHydrated {
            memberHydrationDiagnostics.source = changes.isFullReplacement ? .readyOnly : .realtimeUpdate
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

    private func processNotificationChanges(
        _ changes: RealtimeSnapshotChangeSet,
        snapshot: RealtimeSnapshot
    ) {
        guard !changes.isFullReplacement else { return }
        for (channelID, deletedIDs) in changes.deletedMessageIDsByChannelID {
            seenNotificationMessageIDsByChannelID[channelID]?.subtract(deletedIDs)
        }
        guard !changes.insertedMessages.isEmpty else { return }
        guard effectiveRuntimeMode == .liveManual,
              sessionCoordinator?.hydrationStatus.readyReceived == true
        else {
            for message in changes.insertedMessages {
                seenNotificationMessageIDsByChannelID[message.channelID, default: []].insert(message.id)
            }
            return
        }
        let context = NotificationClassificationContext(
            runtimeMode: effectiveRuntimeMode,
            currentUserID: currentUserID,
            activeChannelID: selectedConversationChannelID,
            isActiveChannelVisible: isActiveChannelVisibleForNotifications,
            preferences: notificationPreferences,
            snapshot: snapshot
        )
        for message in changes.insertedMessages {
            let inserted = seenNotificationMessageIDsByChannelID[message.channelID, default: []].insert(message.id)
            if inserted.inserted {
                handleNotificationClassification(NotificationClassifier.classify(message: message, context: context))
            }
        }
    }

    private func handleNotificationClassification(_ classification: NotificationClassification) {
        var diagnostics = notificationDiagnostics
        switch classification {
        case let .suppress(reason):
            diagnostics.suppressedCount += 1
            diagnostics.lastSuppressionReason = reason
            notificationDiagnostics = diagnostics
            phase44Diagnostics.muteSuppressionDecisionCounts[reason.rawValue, default: 0] += 1
        case let .deliver(event):
            guard !deliveredNotificationIDs.contains(event.id) else { return }
            deliveredNotificationIDs.insert(event.id)
            phase44Diagnostics.muteSuppressionDecisionCounts["delivered", default: 0] += 1
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
        phase44Diagnostics.notificationRouteQueuedCount += 1
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
            phase44Diagnostics.notificationRouteReplayedCount += 1
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
        if value == 0,
           effectiveRuntimeMode == .liveManual,
           sessionCoordinator?.hydrationStatus.readyReceived != true,
           let lastRequested = lastRequestedDockBadgeValue, lastRequested > 0 {
            // Unread state is transiently empty before hydration completes; keep the current badge instead of flashing it away.
            return
        }
        guard value != lastRequestedDockBadgeValue else { return }
        lastRequestedDockBadgeValue = value
        dockBadgeApplyTask = Task { [dockBadgeManager, previousApply = dockBadgeApplyTask] in
            await previousApply?.value
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
        guard let channelID = selectedConversationChannelID else {
            selectedChannelLoadTask?.cancel()
            selectedChannelLoadTask = nil
            selectedChannelLoadTaskChannelID = nil
            return
        }
        guard selectedChannelLoadTaskChannelID != channelID else { return }
        selectedChannelLoadTask?.cancel()
        selectedChannelLoadTaskChannelID = channelID
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
            let outcome = await self.messageController.loadInitialIfNeeded(channelID: channelID, snapshotMessages: snapshotMessages)
            if self.selectedChannelLoadTaskChannelID == channelID {
                self.selectedChannelLoadTask = nil
                self.selectedChannelLoadTaskChannelID = nil
            }
            if isDMRoute {
                let result = self.safeLoadResultDescription(for: channelID, outcome: outcome)
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
            if self.selectedConversationChannelID == channelID,
               (self.timelineViewport.channelID != channelID || self.timelineViewport.pendingScrollIntent == nil) {
                self.updateViewportForSelectedChannel()
            }
        }
    }

    private func safeLoadResultDescription(
        for channelID: ChannelID,
        outcome: ChannelMessageLoadOutcome? = nil
    ) -> String {
        if let outcome {
            switch outcome {
            case let .loaded(messageCount):
                return "loaded \(messageCount)"
            case let .alreadyLoaded(messageCount):
                return "cached \(messageCount)"
            case .deduplicated:
                return "load already in progress"
            case .cancelled:
                return "load cancelled"
            case let .failed(_, cachedMessageCount):
                return "failed, cached \(cachedMessageCount)"
            }
        }
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
        acknowledgeChannel(channelID)
    }

    /// Phase 58: shared by `acknowledgeSelectedChannel()` and `markSelectedServerRead()`, which
    /// acks every selectable channel in the server rather than just the selected one.
    private func acknowledgeChannel(_ channelID: ChannelID) {
        guard snapshot.channelsByID[channelID] != nil else {
            lastAckResult = "Skipped: selected channel missing"
            return
        }
        phase44Diagnostics.ackRequestedCount += 1
        if effectiveRuntimeMode == .liveManual {
            scheduleLiveAckIfNeeded(channelID: channelID)
            return
        }
        clearLocalUnreadState(channelID: channelID, source: "mock")
    }

    /// Phase 58: verified `CHAT_JUMP_END` (Escape) behavior -- mark the channel read, jump to the
    /// newest loaded message, and focus the composer (Docs/Research.md Phase 58 Notes).
    public func markSelectedChannelReadAndFocusComposer() {
        guard selectedConversationChannelID != nil else { return }
        if let newest = selectedTimelineMessages.last {
            timelineSelection = TimelineSelection(channelID: newest.message.channelID, messageID: newest.message.id, source: .scrollJump)
            timelineViewport = viewportReducer.jumpNewest(timelineViewport, newestMessageID: newest.message.id)
        }
        acknowledgeSelectedChannel()
        focusComposer()
    }

    /// Phase 58: verified `CHAT_MARK_SERVER_AS_READ` (Shift-Escape) -- acks every selectable
    /// channel in the selected server.
    public func markSelectedServerRead() {
        guard let serverID = selection.serverID else { return }
        for channel in navigationHelper.visibleSelectableChannels(in: serverID, snapshot: snapshot) {
            acknowledgeChannel(channel.id)
        }
    }

    private func clearLocalUnreadState(channelID: ChannelID, source: String) {
        let unread = snapshot.unreadsByChannelID[channelID]
        let currentMessages = messageController.state(for: channelID).timelineMessages
        let firstUnread = localReadStates[channelID]?.firstUnreadMessageID ?? unread?.lastMessageID
        let mentionCount = source == "mock" ? (localReadStates[channelID]?.mentionCount ?? unread?.mentions.count ?? 0) : 0
        let newest = timelineViewport.isAtNewest
            ? (timelineViewport.visibleRange?.lastVisibleMessageID ?? currentMessages.last?.message.id ?? unread?.lastMessageID)
            : (timelineViewport.visibleRange?.lastVisibleMessageID ?? localReadStates[channelID]?.lastReadMessageID)
        localReadStates[channelID] = LocalReadState(
            channelID: channelID,
            firstUnreadMessageID: firstUnread,
            lastReadMessageID: newest,
            unreadCount: 0,
            mentionCount: mentionCount
        )
        messageController.moveUnreadMarker(channelID: channelID, messageID: firstUnread)
        messageController.markRead(channelID: channelID, lastReadMessageID: newest)
        locallyClearedUnreadChannelIDs.insert(channelID)
        phase44Diagnostics.unreadLocalClearSources[source, default: 0] += 1
        updateDockBadge()
        updateNotificationDiagnostics()
        refreshDMDiagnosticsSnapshot()
    }

    private func scheduleLiveAckIfNeeded(channelID: ChannelID) {
        let decision = readAckDecision(channelID: channelID)
        lastAckResult = decision.diagnostic
        guard case let .send(messageID) = decision else {
            if decision.diagnostic.localizedCaseInsensitiveContains("duplicate") {
                phase44Diagnostics.ackDedupedCount += 1
            }
            return
        }
        if pendingAckMessageIDsByChannelID[channelID] == messageID {
            lastAckResult = "Deduped: pending"
            phase44Diagnostics.ackDedupedCount += 1
            return
        }
        lastAckTargetMessageID = messageID
        lastAckResult = "Scheduled"
        pendingAckMessageIDsByChannelID[channelID] = messageID
        ackTasksByChannelID[channelID]?.cancel()
        ackTasksByChannelID[channelID] = Task { [weak self, sender = channelAckSender] in
            let delay = await MainActor.run { self?.timelineTuning.ackDebounceMilliseconds ?? TimelineTuningConfiguration.defaults.ackDebounceMilliseconds }
            try? await Task.sleep(for: .milliseconds(delay))
            guard !Task.isCancelled else { return }
            do {
                try await sender.ackChannel(channelID: channelID, messageID: messageID)
                await MainActor.run {
                    self?.lastAckedMessageByChannelID[channelID] = messageID
                    self?.pendingAckMessageIDsByChannelID[channelID] = nil
                    self?.ackTasksByChannelID[channelID] = nil
                    self?.lastAckResult = "Sent"
                    self?.phase44Diagnostics.ackSentCount += 1
                    self?.recordTimelineCalibrationObservation(kind: .afterAck)
                    self?.clearLocalUnreadState(channelID: channelID, source: "liveAckSuccess")
                }
            } catch {
                await MainActor.run {
                    self?.pendingAckMessageIDsByChannelID[channelID] = nil
                    self?.ackTasksByChannelID[channelID] = nil
                    self?.lastAckResult = "Failed: \(error.userFacingMessage)"
                    self?.phase44Diagnostics.ackFailureCount += 1
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
        guard pendingAckMessageIDsByChannelID[channelID] != messageID else { return .skip("duplicate pending") }
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
                case let .loaded(message):
                    self.mergePhase43MessageIdentity(message)
                    self.phase44Diagnostics.replyPreviewResolvedLoaded += 1
                    self.failedReferenceFetchMessageIDs.remove(messageID)
                default:
                    self.phase44Diagnostics.replyPreviewUnavailable += 1
                    self.failedReferenceFetchMessageIDs.insert(messageID)
                }
                self.referenceFetchTasks[messageID] = nil
                self.messageController.markReferenceFetchFinished(channelID: channelID, messageID: messageID)
            }
        }
    }

    private func refreshTypingIndicatorState(now: Date = Date()) {
        let channelID = selectedConversationChannelID
        let typingUserIDs = channelID.flatMap { snapshot.typingUsersByChannelID[$0] } ?? []
        typingIndicatorState.replace(channelID: channelID, typingUserIDs: typingUserIDs, currentUserID: currentUserID, now: now)
        phase44Diagnostics.typingActiveUsersBuckets[Phase44SafeSummary.bucket(for: typingIndicatorState.entriesByUserID.count), default: 0] += 1
        scheduleTypingCleanupIfNeeded()
    }

    private func clearTypingIndicatorState(channelID: ChannelID? = nil) {
        typingCleanupTask?.cancel()
        typingIndicatorState.clear(channelID: channelID)
    }

    private func scheduleTypingCleanupIfNeeded() {
        typingCleanupTask?.cancel()
        guard !typingIndicatorState.entriesByUserID.isEmpty else { return }
        let channelID = typingIndicatorState.channelID
        typingCleanupTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            await MainActor.run {
                guard let self, self.typingIndicatorState.channelID == channelID else { return }
                let removed = self.typingIndicatorState.removeStale()
                if removed > 0 {
                    self.phase44Diagnostics.typingStaleCleanupCount += removed
                }
                self.scheduleTypingCleanupIfNeeded()
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
            if activeTypingChannelID != channelID {
                typingEndTask?.cancel()
                typingEndTask = nil
                typingEndDeadline = nil
            }
            activeTypingChannelID = channelID
            lastTypingBeginAt[channelID] = now
            Task { [handler = messageActionHandler] in
                try? await handler.beginTyping(channelID: channelID)
            }
        }

        typingEndDeadline = now.addingTimeInterval(3)
        phase63ComposerDiagnostics.typingDeadlineResetCount += 1
        startTypingEndWorkerIfNeeded(channelID: channelID)
    }

    private func startTypingEndWorkerIfNeeded(channelID: ChannelID) {
        guard typingEndTask == nil else { return }
        typingEndTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.activeTypingChannelID == channelID, let deadline = self.typingEndDeadline else {
                    break
                }
                let delay = max(0, deadline.timeIntervalSinceNow)
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { break }
                guard let currentDeadline = self.typingEndDeadline else { break }
                if currentDeadline.timeIntervalSinceNow > 0 {
                    continue
                }
                guard self.activeTypingChannelID == channelID else { break }
                self.typingEndDeadline = nil
                self.activeTypingChannelID = nil
                self.typingEndTask = nil
                Task { [handler = self.messageActionHandler] in
                    try? await handler.endTyping(channelID: channelID)
                }
                return
            }
            self?.typingEndTask = nil
        }
    }

    private func endTypingForActiveChannel() {
        typingEndTask?.cancel()
        typingEndTask = nil
        typingEndDeadline = nil
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
        case .openQuickSwitcher, .closeTransientUI, .refresh, .openAccountSettings, .openConnectionSettings, .openAppearanceSettings, .openNotificationSettings, .toggleMemberPanel, .jumpToHome, .jumpToFriends, .jumpToAddFriend, .jumpToDiscover, .openJoinInvite, .openCreateServer, .openDiscoverInBrowser, .focusTimeline, .resetTimelineTuningDefault:
            return true
        case .pasteAttachment:
            return selectedConversationChannelID != nil
        case .openNewDirectMessage, .openNewGroup:
            return canRefreshDMs
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
            } == true
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
        case .markSelectedChannelRead:
            return selectedConversationChannelID != nil
        case .markSelectedServerRead:
            return selection.serverID != nil
        }
    }

    public func disabledReason(for command: AppCommand) -> String? {
        guard !canPerform(command) else { return nil }
        switch command {
        case .focusComposer:
            return "Select a channel before focusing the composer."
        case .pasteAttachment:
            return "Select a channel before pasting an attachment."
        case .openNewDirectMessage:
            return "Connect before starting a direct message."
        case .openNewGroup:
            return "Connect before creating a group."
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
            return "Selected result is already loaded."
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
        case .markSelectedChannelRead:
            return "Select a channel before marking it read."
        case .markSelectedServerRead:
            return "Select a server before marking it read."
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
        case .openAccountSettings:
            showAccountSessions()
        case .openConnectionSettings:
            showConnectionSettings()
        case .openAppearanceSettings:
            showAppearanceSettings()
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
        case .openNewDirectMessage:
            openNewDirectMessage()
        case .openNewGroup:
            openNewGroup()
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
            selectedServerSettingsTab = .moderation
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
            openPinnedMessages()
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
            } else if isPinnedMessagesPresented {
                closePinnedMessages()
            } else if inlineEditState != nil {
                cancelInlineEdit()
            } else if searchHighlightState != nil {
                clearSearchHighlights()
            } else {
                requestFocus(nil)
            }
        case .markSelectedChannelRead:
            markSelectedChannelReadAndFocusComposer()
        case .markSelectedServerRead:
            markSelectedServerRead()
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        .environment(\.stoatLiquidGlassTransparency, viewModel.liquidGlassTransparency)
        .sheet(isPresented: $viewModel.isQuickSwitcherPresented) {
            QuickSwitcherView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.isChannelSearchPresented) {
            ChannelSearchPanel(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.isPinnedMessagesPresented) {
            PinnedMessagesPanel(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.isCredentialSetupPresented) {
            AccountConnectionSettingsView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.isPresentingNewDirectMessage) {
            NewDirectMessagePicker(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.isPresentingCustomStatusEditor) {
            CustomStatusEditorView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.isPresentingNewGroup) {
            CreateGroupChannelView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.isPresentingAddGroupMembers) {
            AddGroupMembersView(viewModel: viewModel)
        }
        .confirmationDialog(
            "Remove from Group",
            isPresented: Binding(
                get: { viewModel.pendingGroupMemberRemoval != nil },
                set: { if !$0 { viewModel.cancelRemoveGroupMember() } }
            ),
            presenting: viewModel.pendingGroupMemberRemoval
        ) { pending in
            Button("Remove \(pending.displayName)", role: .destructive) {
                Task { await viewModel.confirmRemoveGroupMember() }
            }
            Button("Cancel", role: .cancel) {
                viewModel.cancelRemoveGroupMember()
            }
        } message: { pending in
            Text("\(pending.displayName) will no longer see this group or its messages.")
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
        .sheet(isPresented: Binding(
            get: { viewModel.pendingModerationConfirmation != nil },
            set: { if !$0 { viewModel.pendingModerationConfirmation = nil } }
        )) {
            ModerationConfirmationSheet(viewModel: viewModel)
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
        .overlay(alignment: .top) {
            if let notice = viewModel.transientNotice {
                HStack(spacing: StoatSpacing.small) {
                    Image(systemName: notice.severity.systemImage)
                        .foregroundStyle(notice.severity == .error ? Color.red : Color.orange)
                        .accessibilityHidden(true)
                    Text(notice.message)
                        .font(.callout)
                        .lineLimit(3)
                    Button {
                        viewModel.dismissTransientNotice()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss notice")
                }
                .padding(.horizontal, StoatSpacing.medium)
                .padding(.vertical, StoatSpacing.small)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: StoatRadius.control, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: StoatRadius.control, style: .continuous)
                        .strokeBorder(
                            (notice.severity == .error ? Color.red : Color.orange).opacity(0.28),
                            lineWidth: 1
                        )
                }
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                .padding(.top, StoatSpacing.small)
                .padding(.horizontal, StoatSpacing.large)
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.22),
            value: viewModel.transientNotice?.id
        )
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
                StoatToolbarTitle(viewModel.title)
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

private struct ModerationConfirmationSheet: View {
    @Bindable var viewModel: MainShellViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: StoatSpacing.large) {
            if let pending = viewModel.pendingModerationConfirmation {
                HStack(alignment: .top, spacing: StoatSpacing.medium) {
                    Image(systemName: pending.action.systemImage)
                        .font(.title2)
                        .foregroundStyle(pending.action == .unban || pending.action == .removeTimeout ? Color.primary : Color.red)
                    VStack(alignment: .leading, spacing: StoatSpacing.xxSmall) {
                        Text(pending.action.title)
                            .font(.title3.weight(.semibold))
                        Text(pending.displayName)
                            .font(.headline)
                        Text("User \(UserDisplayResolver.shortenedID(pending.targetUserID)) in \(pending.serverName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                Text(consequence(for: pending.action))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if pending.action.requiresReason {
                    VStack(alignment: .leading, spacing: StoatSpacing.xSmall) {
                        Text("Reason")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField("Optional ban reason", text: Binding(
                            get: { viewModel.pendingModerationConfirmation?.reason ?? "" },
                            set: { newValue in
                                if var pending = viewModel.pendingModerationConfirmation {
                                    pending.reason = newValue
                                    viewModel.pendingModerationConfirmation = pending
                                }
                            }
                        ), axis: .vertical)
                        .lineLimit(2...4)
                    }
                }

                if pending.action == .timeout {
                    VStack(alignment: .leading, spacing: StoatSpacing.small) {
                        Picker("Duration", selection: Binding(
                            get: { viewModel.pendingModerationConfirmation?.timeoutPreset ?? .oneHour },
                            set: { preset in
                                if var pending = viewModel.pendingModerationConfirmation {
                                    pending.timeoutPreset = preset
                                    viewModel.pendingModerationConfirmation = pending
                                }
                            }
                        )) {
                            ForEach(ModerationTimeoutPreset.allCases) { preset in
                                Text(preset.title).tag(preset)
                            }
                        }
                        .pickerStyle(.segmented)

                        if pending.timeoutPreset == .custom {
                            DatePicker(
                                "Until",
                                selection: Binding(
                                    get: { viewModel.pendingModerationConfirmation?.customTimeoutUntil ?? Date().addingTimeInterval(60 * 60) },
                                    set: { date in
                                        if var pending = viewModel.pendingModerationConfirmation {
                                            pending.customTimeoutUntil = date
                                            viewModel.pendingModerationConfirmation = pending
                                        }
                                    }
                                ),
                                in: Date().addingTimeInterval(60)...,
                                displayedComponents: [.date, .hourAndMinute]
                            )
                        }
                    }
                }

                moderationStateMessage

                HStack {
                    Button("Cancel") {
                        viewModel.pendingModerationConfirmation = nil
                    }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isLoading)

                    Spacer()

                    Button(role: destructiveRole(for: pending.action)) {
                        Task { await viewModel.confirmPendingModerationAction() }
                    } label: {
                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label(confirmTitle(for: pending.action), systemImage: pending.action.systemImage)
                        }
                    }
                    .buttonStyle(GlassButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(isLoading)
                }
            } else {
                EmptyStateView(title: "No action pending", message: "Choose a moderation action first.", systemImage: "shield")
            }
        }
        .padding(StoatSpacing.xLarge)
        .frame(width: 480, alignment: .topLeading)
    }

    @ViewBuilder private var moderationStateMessage: some View {
        switch viewModel.moderationActionState {
        case .idle:
            Text("Liquid Bagel will send this request only after confirmation.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .loading:
            ProgressView("Applying moderation action")
        case let .failed(message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
        case let .loaded(message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var isLoading: Bool {
        if case .loading = viewModel.moderationActionState { return true }
        return false
    }

    private func destructiveRole(for action: ModerationAction) -> ButtonRole? {
        switch action {
        case .kick, .ban, .timeout:
            .destructive
        case .unban, .removeTimeout:
            nil
        }
    }

    private func confirmTitle(for action: ModerationAction) -> String {
        switch action {
        case .kick: "Kick Member"
        case .ban: "Ban User"
        case .unban: "Unban User"
        case .timeout: "Apply Timeout"
        case .removeTimeout: "Remove Timeout"
        }
    }

    private func consequence(for action: ModerationAction) -> String {
        switch action {
        case .kick:
            "The member is removed from this server. Existing messages and cached identity stay intact."
        case .ban:
            "The user is banned from this server. Existing timeline messages are not deleted."
        case .unban:
            "The user is removed from the ban list. They are not added back to the member list."
        case .timeout:
            "The member is muted until the selected time. This uses the verified member timeout field."
        case .removeTimeout:
            "The member timeout is cleared using the verified remove Timeout field."
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
        if let data = preview.data {
            DecodedDataImage(data: data, pixelSize: 1600)
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
        if let data = item.draft?.previewData {
            DecodedDataImage(data: data, pixelSize: 88)
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
        let phase51 = viewModel.phase51PerformanceDiagnostics
        let phase59Reactions = viewModel.phase59ReactionDiagnostics
        let phase60 = viewModel.phase60Diagnostics
        let phase63Composer = viewModel.phase63ComposerDiagnostics
        let presentation = viewModel.timelinePresentationDiagnostics
        let roleSort = viewModel.memberRoleSortDiagnostics
        let dmConversation = viewModel.dmDiagnostics
        let moderation = viewModel.moderationDiagnostics
        let phase68 = viewModel.phase68TraceDiagnostics
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
            LabeledContent("Phase 43 identities", value: "known \(identity.phase43.knownIdentitySnapshotsCount), historical \(identity.phase43.historicalOnlySnapshotsCount), unresolved \(identity.phase43.unresolvedVisibleUserIDsCount)")
            LabeledContent("Phase 43 system events", value: "clickable \(identity.phase43.systemEventClickableParticipantCount), fallback \(identity.phase43.systemEventNonclickableFallbackCount), profile opens \(identity.phase43.profileOpensFromSystemEventsCount)")
            LabeledContent("Phase 43 hydration", value: "queued \(identity.phase43.identityHydrationQueuedCount), in-flight \(identity.phase43.identityHydrationInFlightCount), success/fail \(identity.phase43.identityHydrationSuccessCount)/\(identity.phase43.identityHydrationFailureCount), dedupe \(identity.phase43.identityHydrationDedupeHits), cooldown \(identity.phase43.identityHydrationCooldownSkips)")
            LabeledContent("Phase 43 preservation", value: "avatar \(identity.phase43.avatarMetadataPreservedAfterMemberRemovalCount), removals \(identity.phase43.memberRemovalIdentityPreservationCount), current edits \(identity.phase43.currentUserEditSnapshotMergeCount)")
            LabeledContent("Phase 68/69 identity", value: "no-op merges \(phase68.identityNoOpMergeCount), member invalidations \(phase68.memberListRelevantInvalidationCount), selected publications \(phase68.selectedMemberListPublicationCount)")
            LabeledContent("Phase 68 emoji index", value: "builds \(phase68.emojiIndexBuildCount), cache hits \(phase68.emojiIndexCacheHitCount)")
            LabeledContent("Phase 68 diagnostics", value: "requests \(phase68.visibleIdentityDiagnosticsRequestCount), coalesced \(phase68.visibleIdentityDiagnosticsCoalescedCount), builds \(phase68.visibleIdentityDiagnosticsBuildCount), stale \(phase68.visibleIdentityDiagnosticsStaleResultCount)")
            LabeledContent("Freeze markers", value: freeze.lastMainThreadMarker ?? "-")
            LabeledContent("Freeze counts", value: "timeline \(freeze.timelineRenderPassCount), grouping \(freeze.memberGroupingCount), grouping cache \(freeze.memberGroupingCacheHitCount), visible \(freeze.visibleRangeUpdateCount), capability cache \(freeze.capabilityCacheUpdateCount)")
            LabeledContent("Phase 51 presentations", value: "shell \(phase51.shellBuildCount), timeline \(phase51.timelineBuildCount), cache \(phase51.timelineCacheHitCount), settings \(phase51.serverSettingsBuildCount), cancelled \(phase51.serverSettingsCancellationCount)")
            LabeledContent("Phase 59 shell", value: "requests \(phase51.shellRequestCount), skips \(phase51.shellCacheHitCount), coalesced \(phase51.shellCoalescedCount), discarded \(phase51.shellDiscardedCount), relationship users \(phase51.shellRelationshipCandidateCount)")
            LabeledContent("Phase 59 reactions", value: "attempts \(phase59Reactions.attemptCount), optimistic \(phase59Reactions.optimisticMutationCount), success \(phase59Reactions.successCount), rollback \(phase59Reactions.rollbackCount), deduped \(phase59Reactions.deduplicatedCount), unavailable \(phase59Reactions.unavailableCount)")
            LabeledContent("Phase 60 viewport", value: "events \(phase60.visibilityEventCount), flushes \(phase60.coalescedViewportFlushCount)")
            LabeledContent("Phase 60 rows", value: "requests \(phase60.rowRequestCount), dedupes \(phase60.rowDedupeCount), completed \(phase60.rowCompletionCount), stale \(phase60.staleRowDiscardCount), skeletons \(phase60.activeSkeletonCount), max queue \(phase60.maximumQueueDepth)")
            LabeledContent("Phase 63 composer", value: "native \(phase63Composer.nativeEditEventCount), accepted \(phase63Composer.acceptedDraftMutationCount), duplicate \(phase63Composer.duplicateDraftMutationCount), triggers \(phase63Composer.inlineTriggerPublicationCount), suppressed \(phase63Composer.inlineTriggerSuppressionCount), typing resets \(phase63Composer.typingDeadlineResetCount)")
            LabeledContent("Phase 63 edit baseline", value: "groups \(phase63Composer.timelineGroupingBuildCountAtLastEdit), row requests \(phase63Composer.timelineRowRequestCountAtLastEdit), viewport flushes \(phase63Composer.viewportFlushCountAtLastEdit)")
            LabeledContent("Phase 63 visibility leases", value: "scheduled \(phase63Composer.visibilityLeaseScheduleCount), cancelled \(phase63Composer.visibilityLeaseCancellationCount), expired \(phase63Composer.visibilityLeaseExpirationCount)")
            LabeledContent("Timeline presentation", value: "groups \(presentation.groupingBuildCount), rows \(presentation.rowBuildCount), visible \(presentation.visibleMessageCount)/\(presentation.visibleGroupCount), cancelled \(presentation.cancellationCount), stale \(presentation.staleResultDiscardCount)")
            LabeledContent("Realtime coalescing", value: "\(viewModel.sessionCoordinator?.coalescedRealtimeUpdateCount ?? 0) pending updates merged")
            LabeledContent("Phase 51 diagnostics", value: "published \(phase51.diagnosticsPublishCount), throttled \(phase51.diagnosticsThrottleCount), budget violations \(phase51.mainThreadBudgetViolationCount)")
            LabeledContent("Markdown cache", value: "parsed \(freeze.markdownParseCount), hits \(freeze.markdownCacheHitCount)")
            LabeledContent("Image queue", value: "active \(freeze.imageActiveCount), queued \(freeze.imageQueuedCount), completed \(freeze.imageCompletedCount), failed \(freeze.imageFailedCount), safe \(freeze.mediaSafeModeEnabled ? "yes" : "no")")
            LabeledContent("Image churn", value: "visible \(freeze.visibleImageResourceCount), evicted \(freeze.imagePresentationEvictionCount), reloaded \(freeze.imageReloadAfterEvictionCount), enqueued \(freeze.imageQueueEnqueueCount), timeline invalidations \(freeze.timelineMediaInvalidationCount)")
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
            LabeledContent("Phase 42 moderation", value: "\(moderation.lastActionCategory), \(moderation.requestResultCategory), route \(moderation.routeCategory)")
            LabeledContent("Moderation target", value: "\(moderation.targetCategory), permission \(moderation.permissionResultCategory), error \(moderation.safeErrorCategory)")
            LabeledContent("Moderation lists", value: "bans \(moderation.bansKnownCount)/\(moderation.bansRenderedCount)/\(moderation.bansPendingCount), timeouts \(moderation.timeoutsKnownCount)/\(moderation.timeoutsRenderedCount)/\(moderation.timeoutsPendingCount)")
            let moderationCache = viewModel.moderationCacheDiagnostics
            LabeledContent("Moderation cache", value: "base \(moderationCache.moderationBaseContextCacheHits)/\(moderationCache.moderationBaseContextCacheMisses), permission \(moderationCache.permissionResolutionCacheHits)/\(moderationCache.permissionResolutionCacheMisses), menu \(moderationCache.memberMenuStateCacheHits)/\(moderationCache.memberMenuStateCacheMisses), lookup \(moderationCache.moderationContextLookupHits)/\(moderationCache.moderationContextLookupMisses)")
            let phase46 = viewModel.phase46FreezePreventionDiagnostics
            LabeledContent("Phase 46 prewarm", value: "\(phase46.lastTrigger.rawValue), \(phase46.lastResult.rawValue), attempts \(phase46.lifecyclePrewarmAttempts), prepared \(phase46.lastPreparedMemberCount)")
            LabeledContent("Parity Matrix", value: "\(parity.count(.done)) done, \(parity.count(.partial)) partial, \(parity.count(.broken)) broken, \(parity.count(.blockedByUnverifiedAPI)) blocked, \(parity.count(.deferred)) deferred, \(parity.count(.outOfScope)) out of scope")
            if let dmParity = parity.items.first(where: { $0.section == "Core chat" && $0.name == "DMs" }) {
                LabeledContent("DM parity", value: "\(dmParity.status.rawValue): \(dmParity.recommendedNextAction)")
            }
            GroupBox("Copy diagnostics") {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 190), spacing: StoatSpacing.small, alignment: .topLeading)],
                    alignment: .leading,
                    spacing: StoatSpacing.small
                ) {
                    ForEach(DeveloperDiagnosticsCopyAction.allCases) { action in
                        Button {
                            performDeveloperDiagnosticsCopyAction(action)
                        } label: {
                            Label(action.title, systemImage: action.systemImage)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel(action.title)
                        .help(action.title)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("Member maintenance") {
                Button {
                    Task { await viewModel.refreshSelectedServerMembers() }
                } label: {
                    Label("Refresh Members", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Refresh Members")
                .help("Refresh members for the selected server")
                .disabled(!viewModel.canRefreshSelectedServerMembers)
            }
            Text("Diagnostics are redacted and omit tokens, raw response bodies, message content, and local file paths.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func performDeveloperDiagnosticsCopyAction(_ action: DeveloperDiagnosticsCopyAction) {
        switch action {
        case .timeline:
            viewModel.copyRedactedTimelineDiagnostics()
        case .dmTrace:
            viewModel.copyRedactedDMTrace()
        case .dm:
            viewModel.copyRedactedDMDiagnostics()
        case .parity:
            viewModel.copyRedactedParityDiagnostics()
        case .notifications:
            viewModel.copyRedactedNotificationDiagnostics()
        case .identity:
            viewModel.copyVisibleIdentityDiagnostics()
        case .moderation:
            viewModel.copyRedactedModerationDiagnostics()
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

enum DeveloperDiagnosticsCopyAction: String, CaseIterable, Identifiable {
    case timeline
    case dmTrace
    case dm
    case parity
    case notifications
    case identity
    case moderation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .timeline: "Copy Timeline"
        case .dmTrace: "Copy DM Trace"
        case .dm: "Copy DM Diagnostics"
        case .parity: "Copy Parity"
        case .notifications: "Copy Notifications"
        case .identity: "Copy Identity"
        case .moderation: "Copy Moderation"
        }
    }

    var systemImage: String {
        switch self {
        case .timeline: "text.line.first.and.arrowtriangle.forward"
        case .dmTrace: "point.topleft.down.to.point.bottomright.curvepath"
        case .dm: "bubble.left.and.bubble.right"
        case .parity: "checklist"
        case .notifications: "bell"
        case .identity: "person.text.rectangle"
        case .moderation: "shield"
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

public struct ServerRailView: View {
    private let viewModel: MainShellViewModel
    @State private var retainedCurrentUserAvatarData: Data?

    public init(viewModel: MainShellViewModel) {
        self.viewModel = viewModel
        _retainedCurrentUserAvatarData = State(initialValue: nil)
    }

    public var body: some View {
        VStack(spacing: StoatSpacing.small) {
            ServerRailItem(title: "Home", systemImage: "house.fill", isSelected: viewModel.selection.space == .home) {
                viewModel.selectHome()
            }
            if let user = viewModel.currentUserForPresentation {
                currentUserRailItem(user)
            }
            Divider().padding(.horizontal, StoatSpacing.medium)
            ScrollView {
                LazyVStack(spacing: StoatSpacing.small) {
                    ForEach(viewModel.servers) { server in
                        let presentation = viewModel.serverRailPresentation(for: server.id)
                        ServerRailItem(
                            title: server.name,
                            isSelected: viewModel.selection.serverID == server.id,
                            unreadCount: presentation?.unreadCount ?? 0,
                            mentionCount: presentation?.mentionCount ?? 0,
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
        let currentAvatarData = viewModel.imageData(for: display.avatarFile, kind: .userAvatar)
        return Button {
            viewModel.showUserProfile(user.id, source: .currentUser)
        } label: {
            ZStack(alignment: .topTrailing) {
                AvatarView(
                    title: display.displayName,
                    size: StoatSize.serverIcon,
                    isOnline: user.online,
                    presence: user.status?.presence,
                    imageData: currentAvatarData ?? retainedCurrentUserAvatarData
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
        .onAppear {
            if let currentAvatarData {
                retainedCurrentUserAvatarData = currentAvatarData
            }
            viewModel.currentUserRailAvatarBecameVisible(display.avatarFile)
        }
        .onChange(of: display.avatarFile) { _, avatarFile in
            if avatarFile == nil {
                retainedCurrentUserAvatarData = nil
            }
            viewModel.currentUserRailAvatarBecameVisible(avatarFile)
        }
        .onChange(of: currentAvatarData) { _, data in
            if let data {
                retainedCurrentUserAvatarData = data
            }
        }
        .onDisappear {
            viewModel.currentUserRailAvatarBecameHidden()
        }
        .help("Profile and status")
        .contextMenu {
            statusMenuButton(.online)
            statusMenuButton(.idle)
            statusMenuButton(.focus)
            statusMenuButton(.busy)
            statusMenuButton(.invisible)
            Divider()
            Button {
                viewModel.openCustomStatusEditor()
            } label: {
                Label(user.status?.text == nil ? "Set Custom Status..." : "Edit Custom Status...", systemImage: "text.bubble")
            }
            if user.status?.text != nil {
                Button {
                    Task { await viewModel.clearCustomStatus() }
                } label: {
                    Label("Clear Custom Status", systemImage: "xmark.circle")
                }
            }
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
                if let data = viewModel.imageData(for: banner, kind: .serverBanner) {
                    DecodedDataImage(data: data, pixelSize: 1200)
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
        // The timeline owns the flexible region directly. Toolbar and composer consume safe area
        // instead of joining every live-resize stack negotiation. Never add layoutPriority here:
        // an ideal-height proposal measures the entire loaded LazyVStack (the Phase 64 freeze).
        MessageTimelineView(viewModel: viewModel)
            .safeAreaInset(edge: .top, spacing: 0) {
                chatToolbar
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let channelID = viewModel.selectedConversationChannelID {
                    SelectedChannelComposerView(viewModel: viewModel, channelID: channelID)
                }
            }
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil) { providers in
                loadDroppedFileURLs(from: providers)
                return true
            }
    }

    private var chatToolbar: some View {
        GlassToolbar {
            HStack(spacing: StoatSpacing.medium) {
                Label(viewModel.selectedConversationChannel?.displayName ?? "No channel", systemImage: "number")
                    .font(.headline)
                if let topic = viewModel.selectedConversationChannel?.description {
                    Text(topic).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                GlassIconButton("Pinned in this channel", systemImage: "pin") {
                    viewModel.openPinnedMessages()
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

/// Keeps draft-sized invalidations below the chat container. In particular, changing the native
/// text view must not re-evaluate the sibling LazyVStack that owns the loaded timeline.
private struct SelectedChannelComposerView: View {
    private let viewModel: MainShellViewModel
    private let channelID: ChannelID

    init(viewModel: MainShellViewModel, channelID: ChannelID) {
        self.viewModel = viewModel
        self.channelID = channelID
    }

    var body: some View {
        if let channel = viewModel.snapshot.channelsByID[channelID] {
            let sendReadiness = viewModel.composerReadiness(for: channelID)
            let inputReadiness = viewModel.composerInputReadiness(for: channelID)
            let draftState = viewModel.composerDraftState(for: channelID)
            let attachmentPresentation = viewModel.composerAttachmentPresentation(for: channelID)
            let emojiSections = viewModel.composerEmojiSections
            GlassComposer(
                text: Binding(
                    get: { viewModel.draft(for: channelID) },
                    set: { viewModel.updateDraft($0, for: channelID) }
                ),
                shouldMentionReplyAuthor: Binding(
                    get: { viewModel.composerDraftState(for: channelID).shouldMentionReplyAuthor },
                    set: { viewModel.updateReplyMentionPreference($0, for: channelID) }
                ),
                placeholder: inputReadiness.isEnabled ? viewModel.composerPlaceholder(for: channel) : inputReadiness.reason,
                isEnabled: inputReadiness.isEnabled,
                canSend: sendReadiness.canSend,
                disabledReason: sendReadiness.canSend ? nil : sendReadiness.reason,
                isSending: viewModel.messageController.sendingChannelIDs.contains(channelID),
                canAttach: viewModel.canUploadFiles(in: channel),
                attachments: attachmentPresentation.chips,
                attachmentSummary: attachmentPresentation.summary,
                replyAuthor: draftState.replyContext?.authorDisplayName,
                replyPreview: draftState.replyContext?.contentPreview,
                focusRequestID: viewModel.composerFocusRequestID,
                onCancelReply: { viewModel.cancelReply(for: channelID) },
                onAttach: { viewModel.openAttachmentPicker(for: channelID) },
                onUploadAttachment: { attachmentID in
                    Task { await viewModel.retryAttachmentUpload(attachmentID, in: channelID) }
                },
                onRemoveAttachment: { attachmentID in
                    viewModel.removeAttachment(attachmentID, from: channelID)
                },
                onPreviewAttachment: { attachmentID in
                    Task { await viewModel.previewComposerAttachment(attachmentID, in: channelID) }
                },
                onDropFileURLs: { viewModel.reviewDroppedAttachmentURLs($0, to: channelID) },
                emojiItems: emojiSections.flatMap(\.items).map(\.insertionText),
                emojiSections: emojiSections,
                onInsertEmoji: { emoji, utf16Offset in
                    viewModel.insertEmoji(emoji, at: utf16Offset, in: channelID)
                },
                customEmojiImageData: { viewModel.composerCustomEmojiImageData(for: $0) },
                onRequestCustomEmojiImage: { viewModel.requestComposerCustomEmojiImage($0) },
                onPasteImageData: { viewModel.addPastedImageDataFromClipboard($0, to: channelID) },
                onPasteFileURLs: { viewModel.addAttachmentURLsFromClipboard($0, to: channelID) },
                onPasteDiagnostic: { viewModel.recordComposerPasteDiagnostic($0) },
                onSend: { Task { await viewModel.sendDraft(for: channelID) } },
                onFocus: { viewModel.focusComposer() },
                mentionAutocompleteCandidates: viewModel.composerAutocompleteCandidates,
                highlightedMentionCandidateID: viewModel.composerAutocompleteHighlightedID,
                cursorRequest: viewModel.composerCursorRequest,
                onInlineTriggerChange: { viewModel.composerInlineTriggerChanged($0, for: channelID) },
                onNativeEdit: { viewModel.noteNativeComposerEdit() },
                onInlineTriggerSuppressed: { viewModel.noteSuppressedComposerInlineTrigger() },
                onNavigateMentionAutocomplete: { viewModel.navigateComposerMentionAutocomplete($0) },
                onSelectHighlightedMentionCandidate: {
                    viewModel.selectHighlightedComposerMentionCandidate(for: channelID)
                },
                onCancelMentionAutocomplete: { viewModel.clearComposerAutocomplete() },
                onSelectMentionCandidate: { viewModel.selectComposerAutocompleteCandidate($0, for: channelID) },
                onRequestAutocompleteEmojiImage: { viewModel.requestComposerAutocompleteEmojiImage($0) }
            )
            .padding([.horizontal, .bottom], StoatSpacing.large)
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
                LazyVStack(alignment: .leading, spacing: 0) {
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
        .task(id: viewModel.selectedTimelinePresentationToken) {
            await viewModel.prepareSelectedTimelineRows()
        }
        .task(id: viewModel.selectedTimelineGroupingToken) {
            await viewModel.prepareSelectedTimelineGrouping()
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
        // Rows are identified by `renderIdentity` (String); scrolling to the raw `MessageID`
        // silently matches nothing.
        let resolvedTarget = TimelineScrollTargetResolver.resolve(
            target: target,
            renderItems: viewModel.selectedTimelineRenderItems
        )
        let scroll = { proxy.scrollTo(resolvedTarget, anchor: anchor) }
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
        let renderItems = viewModel.selectedTimelineRenderItems
        if renderItems.isEmpty, !viewModel.selectedTimelineMessages.isEmpty {
            HStack(spacing: StoatSpacing.small) {
                ProgressView()
                    .controlSize(.small)
                Text("Preparing messages…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Preparing loaded messages")
        } else {
            ForEach(renderItems, id: \.renderIdentity) { item in
                TimelineRenderItemView(item: item, viewModel: viewModel)
                    // Skip re-evaluating unchanged rows when the parent timeline re-renders;
                    // rows still invalidate individually through the observable state they read.
                    .equatable()
                    .padding(
                        .top,
                        item.startsGroup
                            ? (viewModel.messageDensity == .compact ? StoatSpacing.small : StoatSpacing.medium)
                            : 0
                    )
            }
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
        if let text = viewModel.typingIndicatorText(for: viewModel.selectedConversationChannelID) {
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, StoatSpacing.small)
        }
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

private struct Phase43SystemEventRow: View {
    let presentation: SystemEventPresentation
    let onOpenParticipant: (SystemEventParticipant) -> Void

    var body: some View {
        HStack(spacing: StoatSpacing.small) {
            Rectangle()
                .fill(Color.secondary.opacity(0.35))
                .frame(height: 1)
            HStack(spacing: 2) {
                ForEach(Array(presentation.pieces.enumerated()), id: \.offset) { _, piece in
                    switch piece {
                    case let .text(value):
                        Text(value)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    case let .participant(participant):
                        Button {
                            onOpenParticipant(participant)
                        } label: {
                            Text(participant.display.displayName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(roleForeground(participant.display.roleColor))
                                .underline()
                        }
                        .buttonStyle(.plain)
                        .help("Open Profile")
                        .accessibilityLabel(participant.accessibilityLabel)
                    }
                }
            }
            .lineLimit(nil)
            .multilineTextAlignment(.center)
            Rectangle()
                .fill(Color.secondary.opacity(0.35))
                .frame(height: 1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, StoatSpacing.xSmall)
        .accessibilityLabel(presentation.plainText)
    }

    private func roleForeground(_ roleColor: ResolvedRoleColor?) -> AnyShapeStyle {
        guard let roleColor else { return AnyShapeStyle(.secondary) }
        return roleColor.value.foregroundStyle
    }
}

public struct TimelineRenderItemView: View, @MainActor Equatable {
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    // `renderIdentity` keeps this state through optimistic-send reconciliation. Retaining the
    // last decoded bytes prevents a momentary cache/read-state gap from replacing a visible
    // local avatar with initials while the confirmed row is prepared.
    @State private var retainedAuthorAvatarData: Data?
    private let item: TimelineRenderItem
    private let viewModel: MainShellViewModel

    public init(item: TimelineRenderItem, viewModel: MainShellViewModel) {
        self.item = item
        self.viewModel = viewModel
    }

    // Rows that read changed observable state still invalidate individually; this only lets
    // SwiftUI skip rows whose inputs are unchanged when the whole ForEach re-renders. The item
    // comparison hits the boxed payload's identity fast path for reused instances.
    public static func == (lhs: TimelineRenderItemView, rhs: TimelineRenderItemView) -> Bool {
        lhs.item == rhs.item && lhs.viewModel === rhs.viewModel
    }

    public var body: some View {
        let timelineMessage = item.timelineMessage
        let rowState = viewModel.timelineRowPresentationState(for: timelineMessage.message.id)
        let rowPresentation = rowState?.presentation ?? viewModel.pendingRowFallbackPresentation(for: timelineMessage)
        let currentAuthorAvatarData = viewModel.imageData(for: rowPresentation?.authorDisplay.avatarFile, kind: .userAvatar)
        let authorAvatarData = currentAuthorAvatarData ?? retainedAuthorAvatarData
        VStack(alignment: .leading, spacing: StoatSpacing.xSmall) {
            if viewModel.inlineEditState?.messageID == timelineMessage.message.id {
                InlineMessageEditor(viewModel: viewModel)
                    .padding(.leading, item.showsHeader ? 0 : StoatSize.avatar + StoatSpacing.medium)
            } else if rowPresentation == nil {
                TimelineSkeletonRow(showsAvatar: item.showsHeader)
            } else if timelineMessage.message.system != nil {
                systemEventRow(timelineMessage, presentation: rowPresentation)
            } else {
                MessageRow(
                    message: timelineMessage.message,
                    author: viewModel.snapshot.usersByID[item.authorID],
                    authorDisplayNameOverride: rowPresentation?.authorDisplay.displayName,
                    authorDisplayColor: roleColor(for: timelineMessage.message),
                    showsHeader: item.showsHeader,
                    statusText: accessibilityStatus(for: timelineMessage),
                    isSelected: viewModel.timelineSelection.messageID == timelineMessage.message.id,
                    isFocused: viewModel.timelineSelection.focus.messageID == timelineMessage.message.id && viewModel.timelineSelection.focus.mode != .none,
                    isSearchHighlighted: viewModel.isSearchHighlighted(timelineMessage.message.id),
                    isCurrentSearchResult: viewModel.isCurrentSearchResult(timelineMessage.message.id),
                    isTargetHighlighted: viewModel.isTargetMessageHighlighted(timelineMessage.message.id, channelID: timelineMessage.message.channelID),
                    isCompactDensity: viewModel.messageDensity == .compact,
                    searchAccessibilityStatus: viewModel.searchHighlightStatus(for: timelineMessage.message.id),
                    replyPreviewItem: viewModel.replyPreviewItem(for: timelineMessage.message),
                    attachmentItems: viewModel.hydratedAttachmentItems(rowPresentation?.attachmentItems ?? []),
                    customEmojiItems: rowPresentation?.customEmojiItems ?? [],
                    referenceItems: rowPresentation?.referenceItems ?? [:],
                    preparedMarkdownContent: rowPresentation?.preparedMarkdownContent,
                    embedItems: viewModel.hydratedEmbedItems(rowPresentation?.embedItems ?? []),
                    authorAvatarData: authorAvatarData,
                    actionItems: rowActionItems(for: timelineMessage, presentation: rowPresentation),
                    reactionItems: rowReactionItems(for: timelineMessage, presentation: rowPresentation),
                    mentionsCurrentUser: rowPresentation?.mentionsCurrentUser ?? false,
                    onMessageAction: { actionID in
                        select(timelineMessage, source: .contextMenu)
                        viewModel.performMessageAction(actionID, on: timelineMessage)
                    },
                    onToggleReaction: { emoji in
                        select(timelineMessage)
                        Task { await viewModel.toggleReaction(emoji, on: timelineMessage) }
                    },
                    onPreviewAttachment: { value in Task { await viewModel.previewAttachment(value) } },
                    onDownloadAttachment: { value in Task { await viewModel.downloadAttachment(value) } },
                    onOpenAttachment: { value in Task { await viewModel.openAttachmentExternally(value) } },
                    onRetryAttachment: { value in Task { await viewModel.retryAttachmentPreview(value) } },
                    onPreviewEmbedMedia: { value in Task { await viewModel.previewEmbedMedia(value) } },
                    onDownloadEmbedMedia: { value in Task { await viewModel.downloadEmbedMedia(value) } },
                    onOpenEmbedMedia: { value in Task { await viewModel.openEmbedMediaExternally(value) } },
                    onRetryEmbedMedia: { value in Task { await viewModel.retryEmbedMediaPreview(value) } },
                    onOpenAuthorProfile: {
                        guard let display = rowPresentation?.authorDisplay else { return }
                        viewModel.showUserProfile(display.userID, source: .messageName, serverID: display.serverContextID)
                    },
                    onOpenReplyPreview: {
                        Task { await viewModel.openReplyPreview(for: timelineMessage.message) }
                    },
                    onOpenMention: { mentionedUserID in
                        viewModel.showUserProfile(
                            mentionedUserID,
                            source: .mention,
                            serverID: rowPresentation?.authorDisplay.serverContextID
                        )
                    }
                )
            }
            statusView(for: timelineMessage)
        }
        .id(item.renderIdentity)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onAppear {
            if let currentAuthorAvatarData {
                retainedAuthorAvatarData = currentAuthorAvatarData
            }
            viewModel.updateTimelineVisibility(
                messageID: timelineMessage.message.id,
                channelID: timelineMessage.message.channelID,
                isVisible: true
            )
            viewModel.timelineSkeletonVisibilityChanged(
                messageID: timelineMessage.message.id,
                isVisible: true
            )
            if timelineMessage.message.system != nil {
                viewModel.noteVisibleSystemEvent(timelineMessage.message)
            } else {
                let display = viewModel.resolvedUserDisplay(for: timelineMessage.message)
                viewModel.noteVisibleIdentity(
                    userID: display.userID,
                    user: timelineMessage.message.user,
                    member: timelineMessage.message.member,
                    serverID: display.serverContextID,
                    source: .visibleMessage
                )
                viewModel.loadInlineImagePreviews(for: timelineMessage.message)
                viewModel.loadModeledEmbedMediaPreviews(for: timelineMessage.message)
                if item.showsHeader {
                    viewModel.timelineAvatarBecameVisible(
                        display.avatarFile,
                        consumerID: timelineAvatarConsumerID(for: item)
                    )
                }
                viewModel.loadCustomEmojiImages(for: timelineMessage.message)
                viewModel.prepareReplyPreview(for: timelineMessage.message)
            }
        }
        .onChange(of: currentAuthorAvatarData) { newValue in
            if let newValue {
                retainedAuthorAvatarData = newValue
            }
        }
        .onDisappear {
            viewModel.updateTimelineVisibility(
                messageID: timelineMessage.message.id,
                channelID: timelineMessage.message.channelID,
                isVisible: false
            )
            viewModel.timelineSkeletonVisibilityChanged(
                messageID: timelineMessage.message.id,
                isVisible: false
            )
            if item.showsHeader {
                viewModel.timelineAvatarBecameHidden(
                    consumerID: timelineAvatarConsumerID(for: item)
                )
            }
        }
        .onTapGesture { select(timelineMessage) }
        .contextMenu {
            ForEach(rowPresentation?.actionItems ?? []) { action in
                Button(role: buttonRole(for: action)) {
                    select(timelineMessage, source: .contextMenu)
                    viewModel.performMessageAction(action.id, on: timelineMessage)
                } label: {
                    Label(action.title, systemImage: action.systemImage)
                }
                .disabled(!action.availability.isAvailable)
            }
        }
    }

    private func select(_ timelineMessage: TimelineMessage, source: MessageFocusSource = .mouse) {
        viewModel.timelineSelection = TimelineSelection(channelID: timelineMessage.message.channelID, messageID: timelineMessage.message.id, source: source)
        viewModel.requestFocus(.timeline)
    }

    private func timelineAvatarConsumerID(for item: TimelineRenderItem) -> String {
        "timeline-avatar-\(item.timelineMessage.message.channelID.rawValue)-\(item.renderIdentity)"
    }

    @ViewBuilder private func systemEventRow(
        _ timelineMessage: TimelineMessage,
        presentation: TimelineRowPresentation?
    ) -> some View {
        Phase43SystemEventRow(
            presentation: presentation?.systemEventPresentation
                ?? SystemEventPresentation.text("System event"),
            onOpenParticipant: { participant in
                viewModel.showUserProfile(
                    participant.userID,
                    source: .systemEventParticipant,
                    serverID: viewModel.snapshot.channelsByID[timelineMessage.message.channelID]?.serverID
                )
            }
        )
        .id(item.renderIdentity)
    }

    private func rowActionItems(
        for timelineMessage: TimelineMessage,
        presentation: TimelineRowPresentation?
    ) -> [MessageRowActionItem] {
        (presentation?.actionItems ?? []).map { item in
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

    private func rowReactionItems(
        for timelineMessage: TimelineMessage,
        presentation: TimelineRowPresentation?
    ) -> [MessageReactionDisplayItem] {
        // Reactions are tiny to derive and must reflect the optimistic controller state
        // immediately, without waiting for the detached full-row presentation rebuild.
        viewModel.currentReactionItems(for: timelineMessage.message)
    }

    private func buttonRole(for item: MessageActionItem) -> ButtonRole? {
        item.role == .destructive ? .destructive : nil
    }

    private func roleColor(for message: Message) -> RoleColorValue? {
        guard colorSchemeContrast != .increased,
              let roleColor = viewModel.roleColor(for: message)
        else { return nil }
        return roleColor.value
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
        let resolvedGroups = serverMemberGroups
        VStack(alignment: .leading, spacing: StoatSpacing.large) {
            HStack {
                Text(panelTitle)
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
                    .help(String("Refresh Members"))
                    .accessibilityLabel("Refresh members")
                }
                if case let .groupDMParticipants(channelID) = context {
                    Button {
                        viewModel.openAddGroupMembers(for: channelID)
                    } label: {
                        Image(systemName: "person.badge.plus")
                    }
                    .buttonStyle(.borderless)
                    .help(String("Add Members"))
                    .accessibilityLabel("Add members to this group")
                }
                Text("\(panelCount(groups: resolvedGroups))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            panelContent(groups: resolvedGroups)
            Spacer()
        }
        .padding(StoatSpacing.large)
        .background(.thinMaterial)
        .task(id: context) {
            viewModel.hydrateMembersForVisibleContextIfNeeded()
        }
        .task(id: viewModel.memberListPresentationToken) {
            if case let .serverMembers(serverID, _) = context {
                await viewModel.prepareMemberListGroups(for: serverID)
            }
        }
        .task(id: viewModel.memberPanelModerationPrewarmToken) {
            await viewModel.memberPanelBecameVisibleForModerationPrewarm()
        }
        .onChange(of: context) { _, _ in
            viewModel.clearMemberAvatarVisibility()
        }
        .onDisappear {
            viewModel.clearMemberAvatarVisibility()
        }
    }

    private var serverMemberGroups: [MemberListGroup] {
        guard case let .serverMembers(serverID, _) = context else { return [] }
        _ = viewModel.memberListGroupsRevision
        return viewModel.cachedMemberListGroups(for: serverID)
    }

    private func panelCount(groups: [MemberListGroup]) -> Int {
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

    private var panelTitle: String {
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

    @ViewBuilder private func panelContent(groups: [MemberListGroup]) -> some View {
        switch context {
        case let .directMessageParticipants(channelID), let .groupDMParticipants(channelID):
            if let channel = viewModel.snapshot.channelsByID[channelID] {
                dmParticipants(channel)
            } else {
                EmptyStateView(title: "No participants", message: "Participant data is not present in the current snapshot.", systemImage: "person")
                    .frame(maxWidth: .infinity)
            }
        case .serverMembers:
            serverMembersPanel(groups: groups)
        case .hidden, .homeSummary, .friendsSummary, .discoverSummary:
            EmptyView()
        }
    }

    @ViewBuilder private func serverMembersPanel(groups: [MemberListGroup]) -> some View {
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
            // Phase 46: moderation cache prewarm is lifecycle-driven; never trigger it from SwiftUI body/view builders.
            // Member rows are nested in `Section` (not a plain VStack) so they remain direct
            // lazy children of the LazyVStack; a plain VStack would force SwiftUI to realize
            // every row in a group at once, which froze the app on servers with thousands of
            // offline members in a single "Offline" group.
            ScrollView {
                LazyVStack(alignment: .leading, spacing: StoatSpacing.xSmall) {
                    ForEach(groups) { group in
                        let limited = MemberPanelRowLimiter.visibleItems(for: group)
                        Section {
                            ForEach(limited.items) { item in
                                memberListRow(item)
                                    .onAppear {
                                        viewModel.noteVisibleIdentity(userID: item.userID, user: item.user, member: item.member, serverID: item.member?.id.serverID, source: .visibleMember)
                                        viewModel.memberAvatarBecameVisible(item.avatar, consumerID: memberAvatarConsumerID(item))
                                    }
                                    .onDisappear {
                                        viewModel.memberAvatarBecameHidden(consumerID: memberAvatarConsumerID(item))
                                    }
                            }
                            if limited.remainder > 0 {
                                Text("and \(limited.remainder) more offline members")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, StoatSpacing.xxSmall)
                            }
                        } header: {
                            Text(group.title.uppercased())
                                .font(StoatTypography.section)
                                .foregroundStyle(.secondary)
                                .padding(.top, StoatSpacing.medium)
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
        let isRemovableGroup = channel.kind == .group && channel.ownerID == viewModel.currentUserID
        if items.isEmpty {
            EmptyStateView(title: "No participants", message: "Participant data is not present in the current snapshot.", systemImage: "person")
                .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: StoatSpacing.xSmall) {
                    ForEach(items) { item in
                        memberListRow(item, groupRemoval: isRemovableGroup && item.userID != viewModel.currentUserID ? (channelID: channel.id, displayName: item.displayName) : nil)
                            .onAppear {
                                viewModel.noteVisibleIdentity(userID: item.userID, user: item.user, member: item.member, serverID: item.member?.id.serverID, source: .visibleMember)
                                viewModel.memberAvatarBecameVisible(item.avatar, consumerID: memberAvatarConsumerID(item))
                            }
                            .onDisappear {
                                viewModel.memberAvatarBecameHidden(consumerID: memberAvatarConsumerID(item))
                            }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func memberListRow(_ item: MemberListItem, groupRemoval: (channelID: ChannelID, displayName: String)? = nil) -> some View {
        // SwiftUI can build context menus while flushing the view graph; moderation
        // disabled states must come from cached row state, not permission/channel scans.
        let moderationState = item.member == nil ? nil : viewModel.cachedMemberModerationMenuState(for: item)
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
            if let groupRemoval {
                Divider()
                Button(role: .destructive) {
                    viewModel.requestRemoveGroupMember(item.userID, from: groupRemoval.channelID, displayName: groupRemoval.displayName)
                } label: {
                    Label("Remove from Group", systemImage: "person.badge.minus")
                }
            }
            if let member = item.member, let moderationState {
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
                .disabled(moderationState[.timeout].isDisabled)
                .help(moderationState[.timeout].disabledReasonText ?? "Timeout")
                Button {
                    viewModel.requestMemberAction(.clearTimeout, for: member)
                } label: {
                    Label("Clear Timeout", systemImage: "clock.arrow.circlepath")
                }
                .disabled(moderationState[.removeTimeout].isDisabled)
                .help(moderationState[.removeTimeout].disabledReasonText ?? "Clear Timeout")
                Button(role: .destructive) {
                    viewModel.requestMemberAction(.kick, for: member)
                } label: {
                    Label("Kick", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .disabled(moderationState[.kick].isDisabled)
                .help(moderationState[.kick].disabledReasonText ?? "Kick")
                Button(role: .destructive) {
                    viewModel.requestMemberAction(.ban, for: member)
                } label: {
                    Label("Ban", systemImage: "hand.raised.fill")
                }
                .disabled(moderationState[.ban].isDisabled)
                .help(moderationState[.ban].disabledReasonText ?? "Ban")
            }
        }
    }

    private func memberAvatarConsumerID(_ item: MemberListItem) -> String {
        let contextID = item.member?.id.serverID.rawValue
            ?? viewModel.selectedConversationChannelID?.rawValue
            ?? "home"
        return "member-panel-avatar-\(contextID)-\(item.userID.rawValue)"
    }

    private func roleForeground(_ color: ResolvedRoleColor?) -> AnyShapeStyle {
        guard colorSchemeContrast != .increased, let color else { return AnyShapeStyle(.primary) }
        return color.value.foregroundStyle
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

struct ProfileBioDisclosurePolicy {
    /// Tolerance for sub-pixel rounding between the measured content height and the collapsed
    /// clamp. Anything measuring within the epsilon of the clamp is treated as fitting -- and,
    /// because the tri-state below only clamps confirmed overflow, it then renders unclipped.
    static let overflowEpsilon: CGFloat = 0.5

    static func isOverflowing(measuredHeight: CGFloat, collapsedHeight: CGFloat) -> Bool {
        measuredHeight > collapsedHeight + overflowEpsilon
    }

    static func contentWidth(cardWidth: CGFloat, horizontalPadding: CGFloat) -> CGFloat {
        max(1, cardWidth - (horizontalPadding * 2))
    }
}

/// Tri-state bio disclosure. The invariant that fixes the Phase 62 inconsistency: the collapsed
/// clamp is applied only while measuring or after *confirmed* overflow, so "last line clipped
/// but no See More button" is structurally unreachable -- content that fits (including content
/// within the rounding epsilon of the clamp) always renders unclipped.
struct ProfileBioDisclosureState: Equatable {
    enum Classification: Equatable {
        /// No accepted measurement yet: keep the clamp on (avoids a tall flash) but show no button.
        case measuring
        /// Confirmed to fit: no clamp, no button.
        case fits
        /// Confirmed overflow: clamp while collapsed, show the button.
        case overflows
    }

    var contentKey: String
    var preparedContentKey: String?
    var preparedGeneration: Int? = nil
    var classification: Classification = .measuring
    var isExpanded = false

    mutating func reset(contentKey: String) {
        self = ProfileBioDisclosureState(contentKey: contentKey)
    }

    mutating func acceptPrepared(contentKey: String, generation: Int = 0) {
        guard self.contentKey == contentKey else { return }
        preparedContentKey = contentKey
        preparedGeneration = generation
        // Deliberately retain the current classification: the prepared subtree re-measures and
        // reclassifies immediately, and resetting here made the button vanish for a frame on
        // every loading -> prepared swap (the Phase 62 flicker).
    }

    mutating func acceptMeasurement(_ height: CGFloat, contentKey: String, generation: Int = 0, collapsedHeight: CGFloat) {
        guard self.contentKey == contentKey,
              preparedContentKey == contentKey,
              preparedGeneration == generation
        else { return }
        classification = ProfileBioDisclosurePolicy.isOverflowing(
            measuredHeight: max(0, height),
            collapsedHeight: collapsedHeight
        ) ? .overflows : .fits
    }

    var showsDisclosure: Bool {
        preparedContentKey == contentKey && classification == .overflows
    }

    /// Whether the collapsed-height clamp is currently applied to the content.
    var appliesClamp: Bool {
        switch classification {
        case .measuring: return true
        case .fits: return false
        case .overflows: return !isExpanded
        }
    }
}

private struct ProfileBioContentView: View {
    let content: String
    let contentKey: String
    let width: CGFloat
    let collapsedHeight: CGFloat
    let fadeHeight: CGFloat
    @State private var preparedContent: PreparedMarkdownContent?
    @State private var preparationGeneration = 0
    @State private var acceptedPreparedGeneration: Int?
    @State private var disclosure: ProfileBioDisclosureState

    init(content: String, contentKey: String, width: CGFloat, collapsedHeight: CGFloat, fadeHeight: CGFloat) {
        self.content = content
        self.contentKey = contentKey
        self.width = width
        self.collapsedHeight = collapsedHeight
        self.fadeHeight = fadeHeight
        _preparedContent = State(initialValue: nil)
        let measurementKey = Self.measurementKey(contentKey: contentKey, width: width)
        _disclosure = State(initialValue: ProfileBioDisclosureState(contentKey: measurementKey))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: StoatSpacing.xSmall) {
            Group {
                if let preparedContent {
                    MarkdownMessageContent(prepared: preparedContent)
                } else {
                    Text(content)
                        .font(StoatTypography.messageBody)
                        .textSelection(.enabled)
                }
            }
            .id(preparedContent == nil ? "bio-loading-\(contentKey)" : "bio-prepared-\(contentKey)")
            .frame(width: width, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxHeight: disclosure.appliesClamp ? collapsedHeight : nil, alignment: .top)
            .clipped()
            .mask(alignment: .top) { collapseMask }
            .background(alignment: .topLeading) {
                preparedMeasurementView
            }

            if disclosure.showsDisclosure {
                Button(disclosure.isExpanded ? "Show Less" : "See More") {
                    disclosure.isExpanded.toggle()
                }
                .buttonStyle(.link)
                .accessibilityHint(disclosure.isExpanded ? "Collapse the profile biography" : "Show the full profile biography")
            }
        }
        .task(id: measurementKey) {
            preparedContent = nil
            acceptedPreparedGeneration = nil
            preparationGeneration &+= 1
            let generation = preparationGeneration
            disclosure.reset(contentKey: measurementKey)
            let content = content
            let prepared = await Task.detached(priority: .userInitiated) {
                MarkdownContentPreparer.prepare(content)
            }.value
            guard !Task.isCancelled, prepared.source == content, disclosure.contentKey == measurementKey else { return }
            preparedContent = prepared
            acceptedPreparedGeneration = generation
            disclosure.acceptPrepared(contentKey: measurementKey, generation: generation)
        }
    }

    private var measurementKey: String {
        Self.measurementKey(contentKey: contentKey, width: width)
    }

    private static func measurementKey(contentKey: String, width: CGFloat) -> String {
        "\(contentKey)|width:\(width.rounded(.toNearestOrAwayFromZero))"
    }

    @ViewBuilder private var preparedMeasurementView: some View {
        if let preparedContent, let generation = acceptedPreparedGeneration {
            MarkdownMessageContent(prepared: preparedContent)
                .frame(width: width, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .hidden()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    disclosure.acceptMeasurement(
                        height,
                        contentKey: measurementKey,
                        generation: generation,
                        collapsedHeight: collapsedHeight
                    )
                }
        }
    }

    /// While collapsed over confirmed overflow, fade the final line height out instead of hard
    /// clipping -- block markdown (headings, code, spacing) rarely lands the clamp exactly on a
    /// line boundary, and the fade reads as intentional truncation above the See More button.
    @ViewBuilder private var collapseMask: some View {
        if disclosure.appliesClamp && disclosure.classification == .overflows {
            VStack(spacing: 0) {
                Rectangle()
                LinearGradient(
                    colors: [.black, .black.opacity(0.12)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: fadeHeight)
            }
        } else {
            Rectangle()
        }
    }
}

private struct UserProfileCardView: View {
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Bindable var viewModel: MainShellViewModel
    let user: User
    private let cardWidth: CGFloat = 480
    private let cardHeight: CGFloat = 560
    /// Collapse after this many rendered body-text lines; the point value derives from live
    /// line metrics (Phase 63) instead of the old hard-coded 132pt.
    private static let collapsedBioLineLimit = 8
    private var collapsedBioHeight: CGFloat {
        ProfileBioMetrics.collapsedHeight(
            lineLimit: Self.collapsedBioLineLimit,
            lineHeight: ProfileBioMetrics.messageBodyLineHeight
        )
    }

    private var contentWidth: CGFloat {
        ProfileBioDisclosurePolicy.contentWidth(cardWidth: cardWidth, horizontalPadding: StoatSpacing.large)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    profileBackground
                    AvatarView(title: context.display.displayName, size: 72, isOnline: user.online, presence: user.status?.presence, imageData: viewModel.imageData(for: avatarFile, kind: .userAvatar))
                        .padding(.leading, StoatSpacing.large)
                        .offset(y: 28)
                }
                VStack(alignment: .leading, spacing: StoatSpacing.medium) {
                    header
                    actionGrid
                    Picker("Profile section", selection: $viewModel.profileSelectedTab) {
                        ForEach(ProfileCardTab.allCases, id: \.self) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    tabContent
                }
                .frame(width: contentWidth, alignment: .leading)
                .padding(.top, 36)
                .padding([.horizontal, .bottom], StoatSpacing.large)
            }
        }
        .frame(width: cardWidth, height: cardHeight, alignment: .topLeading)
        .background(.regularMaterial)
        .onAppear {
            viewModel.loadImageResource(for: avatarFile, kind: .userAvatar)
            if let background = viewModel.userProfilesByID[user.id]?.background {
                viewModel.loadImageResource(for: background, kind: .profileBackground)
            }
        }
        .onChange(of: viewModel.userProfilesByID[user.id]?.background) { _, background in
            viewModel.loadImageResource(for: background, kind: .profileBackground)
        }
        .task(id: viewModel.memberPanelModerationPrewarmToken) {
            await viewModel.profilePopoverBecameVisibleForModerationPrewarm()
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

    @ViewBuilder private var actionGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 118), spacing: StoatSpacing.small)],
            alignment: .leading,
            spacing: StoatSpacing.small
        ) {
            profileActions
            if viewModel.isDeveloperControlsEnabled {
                Button("Copy ID") {
                    Task { await viewModel.messageCopier.copy(user.id.rawValue) }
                }
                .buttonStyle(GlassButtonStyle())
            }
        }
        .fixedSize(horizontal: false, vertical: true)
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
                profileBioContent(content)
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
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 96), spacing: StoatSpacing.xSmall)],
            alignment: .leading,
            spacing: StoatSpacing.xSmall
        ) {
            ForEach(context.roles) { role in
                let roleColor = ResolvedRoleColor(rawValue: role.colour, highContrast: colorSchemeContrast == .increased, sourceRoleID: role.id)
                Text(role.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, StoatSpacing.small)
                    .padding(.vertical, StoatSpacing.xxSmall)
                    .foregroundStyle(roleForeground(roleColor))
                    // Gradient text over a solid primary-stop wash: a 12% gradient background
                    // reads as mud, so chips keep a flat tint.
                    .background(roleSolidColor(roleColor).opacity(0.12), in: RoundedRectangle(cornerRadius: StoatRadius.control, style: .continuous))
                    .help(role.name)
            }
        }
    }

    @ViewBuilder private func profileBioContent(_ content: String) -> some View {
        ProfileBioContentView(
            content: content,
            contentKey: "\(user.id.rawValue)|\(content)",
            width: contentWidth,
            collapsedHeight: collapsedBioHeight,
            fadeHeight: ProfileBioMetrics.messageBodyLineHeight
        )
        .id("\(user.id.rawValue)|\(content)")
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
        moderationProfileMenu
    }

    private var messageProfileButton: some View {
        Button("Message") { Task { await viewModel.openDirectMessage(with: user.id, source: .profilePopover) } }
            .buttonStyle(GlassButtonStyle())
    }

    @ViewBuilder private var moderationProfileMenu: some View {
        if context.serverID != nil {
            let member = profileServerMember
            let moderationState = viewModel.cachedMemberModerationMenuState(targetUserID: user.id, member: member)
            Menu {
                ForEach(profileModerationActions, id: \.self) { action in
                    Button(action.title, role: action == .kick || action == .ban ? .destructive : nil) {
                        viewModel.requestModerationAction(action, targetUserID: user.id, member: member)
                    }
                    .disabled(moderationState[action].isDisabled)
                    .help(moderationState[action].disabledReasonText ?? action.title)
                }
            } label: {
                Label("Moderate", systemImage: "shield")
            }
            .buttonStyle(GlassButtonStyle())
        }
    }

    private var profileServerMember: ServerMember? {
        guard let serverID = context.serverID else { return nil }
        return viewModel.snapshot.membersByServerAndUserID[ServerMemberKey(serverID: serverID, userID: user.id)]
    }

    private var profileModerationActions: [ModerationAction] {
        guard let member = profileServerMember else { return [.ban] }
        if let timeout = member.timeout, timeout > Date() {
            return [.kick, .ban, .removeTimeout]
        }
        return [.kick, .ban, .timeout]
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
            DecodedDataImage(data: data, pixelSize: 780)
                    .scaledToFill()
                    .frame(height: 96)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .accessibilityLabel("Profile banner")
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

    private func roleForeground(_ color: ResolvedRoleColor?) -> AnyShapeStyle {
        guard colorSchemeContrast != .increased, let color else { return AnyShapeStyle(.secondary) }
        return color.value.foregroundStyle
    }

    private func roleSolidColor(_ color: ResolvedRoleColor?) -> Color {
        guard colorSchemeContrast != .increased, let color else { return .secondary }
        return Color(red: color.red, green: color.green, blue: color.blue)
    }

    private var displayNameForeground: AnyShapeStyle {
        guard colorSchemeContrast != .increased,
              let color = context.display.roleColor
        else { return AnyShapeStyle(.primary) }
        return color.value.foregroundStyle
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

public struct NewDirectMessagePicker: View {
    @Bindable private var viewModel: MainShellViewModel

    public init(viewModel: MainShellViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: StoatSpacing.medium) {
            HStack {
                Text("New Direct Message")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    viewModel.openNewGroup()
                } label: {
                    Label("New Group", systemImage: "person.3")
                }
                .accessibilityLabel("Create a new group")
                Button("Close") { viewModel.isPresentingNewDirectMessage = false }
                    .keyboardShortcut(.cancelAction)
            }
            TextField("Search friends", text: $viewModel.newDirectMessageSearch)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search friends to message")
            let candidates = viewModel.newDirectMessageCandidates
            if candidates.isEmpty {
                Text(viewModel.newDirectMessageSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Add friends to start a direct message."
                    : "No friends match that search.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, StoatSpacing.medium)
            } else {
                ScrollView {
                    LazyVStack(spacing: StoatSpacing.xSmall) {
                        ForEach(candidates) { item in
                            Button {
                                Task { await viewModel.startDirectMessage(with: item.user.id) }
                            } label: {
                                MemberRow(
                                    user: item.user,
                                    imageData: viewModel.imageData(for: item.user.avatar, kind: .userAvatar)
                                )
                            }
                            .buttonStyle(.plain)
                            .onAppear { viewModel.loadImageResource(for: item.user.avatar, kind: .userAvatar) }
                        }
                    }
                }
            }
        }
        .padding(StoatSpacing.large)
        .frame(width: 460, height: 420, alignment: .topLeading)
    }
}

public struct CreateGroupChannelView: View {
    @Bindable private var viewModel: MainShellViewModel

    public init(viewModel: MainShellViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: StoatSpacing.medium) {
            HStack {
                Text("New Group")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Close") { viewModel.isPresentingNewGroup = false }
                    .keyboardShortcut(.cancelAction)
            }
            TextField("Group name", text: $viewModel.groupCreateName)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Group name")
            TextField("Search friends to add", text: $viewModel.groupCreateSearch)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search friends to add to the group")
            let candidates = viewModel.newGroupCandidates
            if candidates.isEmpty {
                Text(viewModel.groupCreateSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Add friends to include them in a group."
                    : "No friends match that search.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, StoatSpacing.medium)
            } else {
                ScrollView {
                    LazyVStack(spacing: StoatSpacing.xSmall) {
                        ForEach(candidates) { item in
                            Button {
                                viewModel.toggleNewGroupCandidate(item.user.id)
                            } label: {
                                HStack {
                                    Image(systemName: viewModel.groupCreateSelectedUserIDs.contains(item.user.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(viewModel.groupCreateSelectedUserIDs.contains(item.user.id) ? Color.accentColor : Color.secondary)
                                    MemberRow(
                                        user: item.user,
                                        imageData: viewModel.imageData(for: item.user.avatar, kind: .userAvatar)
                                    )
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(item.user.displayName ?? item.user.username), \(viewModel.groupCreateSelectedUserIDs.contains(item.user.id) ? "selected" : "not selected")")
                            .onAppear { viewModel.loadImageResource(for: item.user.avatar, kind: .userAvatar) }
                        }
                    }
                }
            }
            if case let .failed(message) = viewModel.groupCreateState {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                Text("\(viewModel.groupCreateSelectedUserIDs.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await viewModel.createGroupFromDraft() }
                } label: {
                    Label("Create Group", systemImage: "person.3")
                }
                .buttonStyle(GlassButtonStyle())
                .disabled(isCreating)
            }
        }
        .padding(StoatSpacing.large)
        .frame(width: 460, height: 480, alignment: .topLeading)
    }

    private var isCreating: Bool {
        if case .creating = viewModel.groupCreateState { return true }
        return false
    }
}

public struct AddGroupMembersView: View {
    @Bindable private var viewModel: MainShellViewModel

    public init(viewModel: MainShellViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: StoatSpacing.medium) {
            HStack {
                Text("Add Members")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Close") { viewModel.isPresentingAddGroupMembers = false }
                    .keyboardShortcut(.cancelAction)
            }
            TextField("Search friends to add", text: $viewModel.addGroupMembersSearch)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search friends to add to the group")
            let candidates = viewModel.addGroupMembersChannelID.map { viewModel.addGroupMemberCandidates(for: $0) } ?? []
            if candidates.isEmpty {
                Text(viewModel.addGroupMembersSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "All your friends are already in this group, or you have no friends to add yet."
                    : "No friends match that search.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, StoatSpacing.medium)
            } else {
                ScrollView {
                    LazyVStack(spacing: StoatSpacing.xSmall) {
                        ForEach(candidates) { item in
                            Button {
                                viewModel.toggleAddGroupMemberCandidate(item.user.id)
                            } label: {
                                HStack {
                                    Image(systemName: viewModel.addGroupMembersSelectedUserIDs.contains(item.user.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(viewModel.addGroupMembersSelectedUserIDs.contains(item.user.id) ? Color.accentColor : Color.secondary)
                                    MemberRow(
                                        user: item.user,
                                        imageData: viewModel.imageData(for: item.user.avatar, kind: .userAvatar)
                                    )
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(item.user.displayName ?? item.user.username), \(viewModel.addGroupMembersSelectedUserIDs.contains(item.user.id) ? "selected" : "not selected")")
                            .onAppear { viewModel.loadImageResource(for: item.user.avatar, kind: .userAvatar) }
                        }
                    }
                }
            }
            if case let .failed(message) = viewModel.groupMembershipActionState {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                Text("\(viewModel.addGroupMembersSelectedUserIDs.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await viewModel.addSelectedGroupMembers() }
                } label: {
                    Label("Add to Group", systemImage: "person.badge.plus")
                }
                .buttonStyle(GlassButtonStyle())
                .disabled(isWorking || viewModel.addGroupMembersSelectedUserIDs.isEmpty)
            }
        }
        .padding(StoatSpacing.large)
        .frame(width: 460, height: 480, alignment: .topLeading)
    }

    private var isWorking: Bool {
        if case .working = viewModel.groupMembershipActionState { return true }
        return false
    }
}

public struct CustomStatusEditorView: View {
    @Bindable private var viewModel: MainShellViewModel

    public init(viewModel: MainShellViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: StoatSpacing.medium) {
            HStack {
                Text("Custom Status")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Close") { viewModel.isPresentingCustomStatusEditor = false }
                    .keyboardShortcut(.cancelAction)
            }
            TextField("What's happening?", text: $viewModel.customStatusDraft)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Custom status text")
                .onSubmit {
                    Task { await viewModel.submitCustomStatusDraft() }
                }
            HStack {
                Text("\(viewModel.customStatusDraft.trimmingCharacters(in: .whitespacesAndNewlines).count)/\(MainShellViewModel.customStatusTextLimit)")
                    .font(.caption)
                    .foregroundStyle(isOverLimit ? .red : .secondary)
                    .accessibilityLabel("Status length \(viewModel.customStatusDraft.count) of \(MainShellViewModel.customStatusTextLimit)")
                Spacer()
                Button("Clear") {
                    Task { await viewModel.clearCustomStatus() }
                }
                .disabled(currentStatusText == nil && viewModel.customStatusDraft.isEmpty)
                Button {
                    Task { await viewModel.submitCustomStatusDraft() }
                } label: {
                    Label("Save", systemImage: "checkmark.circle")
                }
                .buttonStyle(GlassButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(isOverLimit)
            }
        }
        .padding(StoatSpacing.large)
        .frame(width: 420, alignment: .topLeading)
    }

    private var isOverLimit: Bool {
        viewModel.customStatusDraft.trimmingCharacters(in: .whitespacesAndNewlines).count > MainShellViewModel.customStatusTextLimit
    }

    private var currentStatusText: String? {
        viewModel.currentUserForPresentation?.status?.text
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

                switch viewModel.serverSettingsPresentationState {
                case .idle:
                    EmptyStateView(title: "No server selected", message: "Select a server to review settings.", systemImage: "server.rack")
                case .loading:
                    ProgressView("Loading server details")
                case let .failed(message):
                    EmptyStateView(title: "Server settings unavailable", message: message, systemImage: "exclamationmark.triangle")
                case let .loaded(presentation):
                    settings(presentation)
                }
            }
            .padding(StoatSpacing.xLarge)
        }
        .frame(width: 680)
        .frame(minHeight: 620)
        .accessibilityLabel("Server settings")
        .confirmationDialog(
            "Delete server emoji?",
            isPresented: Binding(
                get: { viewModel.pendingServerEmojiDeletion != nil },
                set: { if !$0 { viewModel.pendingServerEmojiDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Emoji", role: .destructive) {
                Task { await viewModel.confirmDeleteServerEmoji() }
            }
            Button("Cancel", role: .cancel) {
                viewModel.pendingServerEmojiDeletion = nil
            }
        } message: {
            Text("This removes the emoji from the server and cannot be undone.")
        }
    }

    private func settings(_ presentation: ServerSettingsPresentationSnapshot) -> some View {
        let details = presentation.details
        return VStack(alignment: .leading, spacing: StoatSpacing.large) {
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
            case .emojis:
                emojis(presentation)
            case .roles:
                roles(presentation)
            case .permissions:
                permissions(presentation)
            case .members:
                members(presentation)
            case .moderation:
                moderation(presentation)
            case .danger:
                EmptyStateView(title: "Server deletion deferred", message: "Danger Zone is intentionally disabled in Phase 25.", systemImage: "lock.shield")
            }
        }
    }

    private func emojis(_ presentation: ServerSettingsPresentationSnapshot) -> some View {
        VStack(alignment: .leading, spacing: StoatSpacing.large) {
            GlassPanel {
                VStack(alignment: .leading, spacing: StoatSpacing.medium) {
                    Text("Create Server Emoji")
                        .font(.headline)
                    TextField("Emoji name", text: $viewModel.serverEmojiName)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Emoji name")
                    HStack {
                        Button {
                            viewModel.chooseServerEmojiDraft()
                        } label: {
                            Label("Choose Image", systemImage: "face.smiling")
                        }
                        Text(viewModel.serverEmojiDraft?.filename ?? "No image selected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Button {
                            Task { await viewModel.createServerEmoji() }
                        } label: {
                            Label("Create", systemImage: "plus")
                        }
                        .buttonStyle(GlassButtonStyle())
                        .disabled(
                            viewModel.serverEmojiDraft == nil
                                || EmojiCreateDraft(
                                    name: viewModel.serverEmojiName,
                                    serverID: presentation.details.server.id
                                ).validated == nil
                                || presentation.emojiManagementDisabledReason != nil
                        )
                    }
                    stateMessage(
                        viewModel.serverEmojiManagementState,
                        loading: "Updating server emoji",
                        success: "Server emoji updated"
                    )
                }
            }

            GlassPanel {
                VStack(alignment: .leading, spacing: StoatSpacing.medium) {
                    HStack {
                        Text("Server Emoji")
                            .font(.headline)
                        Spacer()
                        Text("\(presentation.emojiItems.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Button {
                            Task { await viewModel.refreshServerEmojis() }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    if presentation.emojiItems.isEmpty {
                        EmptyStateView(
                            title: "No server emoji",
                            message: "Create one above or refresh the verified server emoji route.",
                            systemImage: "face.smiling"
                        )
                    } else {
                        LazyVStack(alignment: .leading, spacing: StoatSpacing.small) {
                            ForEach(presentation.emojiItems) { item in
                                HStack(spacing: StoatSpacing.medium) {
                                    AvatarView(
                                        title: item.name,
                                        size: 32,
                                        imageData: viewModel.imageData(for: item.file, kind: .customEmoji)
                                    )
                                    VStack(alignment: .leading, spacing: StoatSpacing.xxSmall) {
                                        Text(":\(item.name):")
                                            .font(.body.monospaced())
                                        if item.animated {
                                            Text("Animated")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Button(role: .destructive) {
                                        viewModel.requestDeleteServerEmoji(item.id)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    .disabled(presentation.emojiManagementDisabledReason != nil)
                                }
                                .padding(StoatSpacing.small)
                                .background(
                                    Color.primary.opacity(0.04),
                                    in: RoundedRectangle(
                                        cornerRadius: StoatRadius.small,
                                        style: .continuous
                                    )
                                )
                                .onAppear {
                                    viewModel.loadImageResource(for: item.file, kind: .customEmoji)
                                }
                            }
                        }
                    }
                }
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
        let cats = viewModel.categoryEditorForm?.categories ?? []
        let canManage = viewModel.channelManagementDisabledReason() == nil
        return VStack(alignment: .leading, spacing: StoatSpacing.medium) {
            GlassPanel {
                VStack(alignment: .leading, spacing: StoatSpacing.medium) {
                    Text("Categories")
                        .font(.headline)
                    HStack {
                        TextField("New category", text: $newCategoryTitle)
                        Button { viewModel.createCategoryDraft(title: newCategoryTitle); newCategoryTitle = "" } label: { Label("Add", systemImage: "plus") }
                            .disabled(newCategoryTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !canManage)
                    }
                    ForEach(Array(zip(cats.indices, cats)), id: \.1.id) { index, category in
                        VStack(alignment: .leading, spacing: StoatSpacing.xSmall) {
                            HStack {
                                VStack(spacing: 0) {
                                    Button {
                                        viewModel.categoryEditorForm?.moveCategories(fromOffsets: IndexSet(integer: index), toOffset: index - 1)
                                    } label: { Image(systemName: "chevron.up") }
                                    .disabled(index == 0 || !canManage)
                                    .accessibilityLabel("Move category up")
                                    Button {
                                        viewModel.categoryEditorForm?.moveCategories(fromOffsets: IndexSet(integer: index), toOffset: index + 2)
                                    } label: { Image(systemName: "chevron.down") }
                                    .disabled(index == cats.count - 1 || !canManage)
                                    .accessibilityLabel("Move category down")
                                }
                                .buttonStyle(.borderless)
                                TextField("Category title", text: Binding(
                                    get: { viewModel.categoryEditorForm?.categories.first(where: { $0.id == category.id })?.title ?? category.title },
                                    set: { viewModel.categoryEditorForm?.renameCategory(id: category.id, title: $0) }
                                ))
                                Text("\(category.channels.count)")
                                    .foregroundStyle(.secondary)
                                Button(role: .destructive) { viewModel.categoryEditorForm?.deleteCategory(id: category.id) } label: { Image(systemName: "trash") }
                                    .accessibilityHint("Deletes this category draft; channels become uncategorized after Apply")
                            }
                            ForEach(Array(zip(category.channels.indices, category.channels)), id: \.1) { chIdx, channelID in
                                if let channel = details.channels.first(where: { $0.id == channelID }) {
                                    HStack {
                                        Button {
                                            viewModel.categoryEditorForm?.moveChannels(inCategory: category.id, fromOffsets: IndexSet(integer: chIdx), toOffset: chIdx - 1)
                                        } label: { Image(systemName: "chevron.up") }
                                        .disabled(chIdx == 0 || !canManage)
                                        .accessibilityLabel("Move channel up within category")
                                        Button {
                                            viewModel.categoryEditorForm?.moveChannels(inCategory: category.id, fromOffsets: IndexSet(integer: chIdx), toOffset: chIdx + 2)
                                        } label: { Image(systemName: "chevron.down") }
                                        .disabled(chIdx == category.channels.count - 1 || !canManage)
                                        .accessibilityLabel("Move channel down within category")
                                        Text(channel.displayName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.borderless)
                                    .padding(.leading, StoatSpacing.medium)
                                }
                            }
                        }
                    }
                    if !details.channels.isEmpty {
                        Divider()
                        Text("Assign channels to categories")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                    }
                    stateMessage(viewModel.categoryEditorState, loading: "Applying categories", success: "Categories updated")
                    HStack {
                        Spacer()
                        Button { Task { await viewModel.applyCategoryChanges() } } label: { Label("Apply Categories", systemImage: "checkmark") }
                            .buttonStyle(GlassButtonStyle())
                            .disabled(!canManage)
                    }
                }
            }
        }
    }

    private func roles(_ presentation: ServerSettingsPresentationSnapshot) -> some View {
        return VStack(alignment: .leading, spacing: StoatSpacing.medium) {
            GlassPanel {
                VStack(alignment: .leading, spacing: StoatSpacing.medium) {
                    HStack {
                        Text("Roles")
                            .font(.headline)
                        Spacer()
                        Button { viewModel.openCreateRole() } label: { Label("Create Role", systemImage: "plus") }
                            .disabled(viewModel.roleManagementDisabledReason() != nil)
                    }
                    ForEach(presentation.orderedRoles) { role in
                        HStack {
                            Circle()
                                .fill(roleSwatchStyle(role.colour))
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

    private func permissions(_ presentation: ServerSettingsPresentationSnapshot) -> some View {
        let details = presentation.details
        return VStack(alignment: .leading, spacing: StoatSpacing.medium) {
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
                    ForEach(presentation.orderedRoles) { role in
                        HStack {
                            Text(role.name)
                            Spacer()
                            Button { viewModel.openPermissionEditor(scope: .serverRole(serverID: details.server.id, roleID: role.id)) } label: { Label("Edit", systemImage: "pencil") }
                                .disabled(viewModel.permissionEditingDisabledReason() != nil || !Phase25PermissionResolver.isRoleEditable(role, currentMember: viewModel.selectedServerMember, server: details.server, currentUserID: viewModel.currentUserID))
                        }
                    }
                    ForEach(presentation.textChannels) { channel in
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
                permissionEditor(draft, groups: presentation.permissionGroups)
            }
        }
    }

    private func permissionEditor(_ draft: PermissionEditDraft, groups: [String]) -> some View {
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
                ForEach(groups, id: \.self) { group in
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

    private func members(_ presentation: ServerSettingsPresentationSnapshot) -> some View {
        let details = presentation.details
        return VStack(alignment: .leading, spacing: StoatSpacing.medium) {
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
                            ForEach(presentation.memberItems) { item in
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
                                    viewModel.imageResourceBecameVisible(
                                        item.member.avatar ?? item.user?.avatar,
                                        kind: .userAvatar,
                                        consumerID: "server-settings-avatar-\(item.member.id.serverID.rawValue)-\(item.member.id.userID.rawValue)"
                                    )
                                }
                                .onDisappear {
                                    viewModel.imageResourceBecameHidden(
                                        consumerID: "server-settings-avatar-\(item.member.id.serverID.rawValue)-\(item.member.id.userID.rawValue)"
                                    )
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

            EmptyView()
        }
    }

    private func moderation(_ presentation: ServerSettingsPresentationSnapshot) -> some View {
        let details = presentation.details
        return VStack(alignment: .leading, spacing: StoatSpacing.medium) {
            GlassPanel {
                VStack(alignment: .leading, spacing: StoatSpacing.medium) {
                    HStack {
                        Label("Moderation", systemImage: "shield.lefthalf.filled")
                            .font(.headline)
                        Spacer()
                        Button {
                            Task { await viewModel.hydrateServerMembers(serverID: details.server.id, force: true, reason: "moderation dashboard refresh") }
                        } label: {
                            Label("Refresh Members", systemImage: "person.2")
                        }
                        Button {
                            Task { await viewModel.refreshBanList() }
                        } label: {
                            Label("Refresh Bans", systemImage: "arrow.clockwise")
                        }
                        .disabled(!viewModel.serverManagementCapabilities().isConnectedForLiveActions)
                        Button {
                            viewModel.copyRedactedModerationDiagnostics()
                        } label: {
                            Label("Copy Safe Diagnostics", systemImage: "doc.on.doc")
                        }
                    }
                    if moderationPermissionSummary(in: details) != nil {
                        Text(moderationPermissionSummary(in: details) ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    stateMessage(viewModel.moderationActionState, loading: "Applying moderation action", success: "Moderation action completed")
                }
            }

            moderationMembers(presentation)
            moderationBans()
            moderationTimeouts(presentation)
        }
        .task(id: viewModel.memberPanelModerationPrewarmToken) {
            await viewModel.serverSettingsModerationBecameVisibleForPrewarm()
        }
    }

    private func moderationMembers(_ presentation: ServerSettingsPresentationSnapshot) -> some View {
        return GlassPanel {
            VStack(alignment: .leading, spacing: StoatSpacing.medium) {
                HStack {
                    Text("Members")
                        .font(.headline)
                    Spacer()
                    Text("\(presentation.memberItems.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                TextField("Search members", text: $viewModel.memberSearchText)
                    .textFieldStyle(.roundedBorder)
                let items = presentation.memberItems
                if items.isEmpty {
                    EmptyStateView(title: "No members", message: "Refresh this server's members to moderate member-scoped actions.", systemImage: "person.2")
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: StoatSpacing.small) {
                            ForEach(items) { item in
                                moderationMemberRow(item)
                            }
                        }
                    }
                    .frame(minHeight: 150, maxHeight: 280)
                }
            }
        }
    }

    private func moderationMemberRow(_ item: MemberManagementItem) -> some View {
        let moderationState = viewModel.cachedMemberModerationMenuState(targetUserID: item.member.id.userID, member: item.member)
        let display = viewModel.resolvedUserDisplay(for: item.user, member: item.member, fallbackID: item.member.id.userID, serverID: item.member.id.serverID)
        return HStack(spacing: StoatSpacing.medium) {
            AvatarView(title: display.displayName, size: 32, isOnline: item.user?.online == true, presence: item.user?.status?.presence, imageData: viewModel.imageData(for: display.avatarFile, kind: .userAvatar))
            VStack(alignment: .leading, spacing: StoatSpacing.xxSmall) {
                Text(display.displayName)
                    .lineLimit(1)
                Text(memberSubtitle(for: item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let timeoutSummary = item.timeoutSummary {
                    Text(timeoutSummary)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            Button {
                viewModel.openMemberDetail(item.member)
            } label: {
                Label("Details", systemImage: "person.text.rectangle")
            }
            moderationActionButton(.kick, targetUserID: item.member.id.userID, member: item.member, state: moderationState)
            moderationActionButton(.ban, targetUserID: item.member.id.userID, member: item.member, state: moderationState)
            if item.timeoutSummary == nil {
                moderationActionButton(.timeout, targetUserID: item.member.id.userID, member: item.member, state: moderationState)
            } else {
                moderationActionButton(.removeTimeout, targetUserID: item.member.id.userID, member: item.member, state: moderationState)
            }
        }
        .padding(StoatSpacing.small)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: StoatRadius.small, style: .continuous))
        .onAppear {
            viewModel.noteVisibleIdentity(userID: item.member.id.userID, user: item.user, member: item.member, serverID: item.member.id.serverID, source: .visibleMember)
            viewModel.loadImageResource(for: display.avatarFile, kind: .userAvatar)
        }
        .contextMenu {
            Button("Open Profile") {
                viewModel.showUserProfile(item.member.id.userID, source: .memberRow, serverID: item.member.id.serverID)
            }
            Divider()
            ForEach([ModerationAction.kick, .ban, .timeout, .removeTimeout], id: \.self) { action in
                Button(action.title, role: action == .kick || action == .ban ? .destructive : nil) {
                    viewModel.requestModerationAction(action, targetUserID: item.member.id.userID, member: item.member)
                }
                .disabled(moderationState[action].isDisabled)
                .help(moderationState[action].disabledReasonText ?? action.title)
            }
        }
    }

    private func moderationActionButton(_ action: ModerationAction, targetUserID: UserID, member: ServerMember? = nil, allowNonMemberBan: Bool = false, state: MemberModerationMenuState? = nil) -> some View {
        let state = state ?? viewModel.cachedMemberModerationMenuState(targetUserID: targetUserID, member: member, allowNonMemberBan: allowNonMemberBan)
        let actionState = state[action]
        return Button(role: action == .kick || action == .ban ? .destructive : nil) {
            viewModel.requestModerationAction(action, targetUserID: targetUserID, member: member, allowNonMemberBan: allowNonMemberBan)
        } label: {
            Image(systemName: action.systemImage)
                .help(actionState.disabledReasonText ?? action.title)
        }
        .disabled(actionState.isDisabled)
        .accessibilityLabel(action.title)
        .accessibilityHint(actionState.disabledReasonText ?? "Requires confirmation")
    }

    @ViewBuilder private func moderationBans() -> some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: StoatSpacing.medium) {
                HStack {
                    Text("Bans")
                        .font(.headline)
                    Spacer()
                    Button {
                        Task { await viewModel.refreshBanList() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(!viewModel.serverManagementCapabilities().isConnectedForLiveActions)
                }
                TextField("Search bans", text: $viewModel.moderationBanSearchText)
                    .textFieldStyle(.roundedBorder)
                switch viewModel.banListState {
                case .idle:
                    EmptyStateView(title: "Ban list not loaded", message: "Refresh bans when you need the current server list.", systemImage: "hand.raised")
                case .loading:
                    ProgressView("Loading bans")
                case let .failed(message):
                    VStack(alignment: .leading, spacing: StoatSpacing.small) {
                        EmptyStateView(title: "Bans unavailable", message: message, systemImage: "exclamationmark.triangle")
                        HStack {
                            Button {
                                Task { await viewModel.refreshBanList() }
                            } label: {
                                Label("Retry", systemImage: "arrow.clockwise")
                            }
                            Button {
                                viewModel.copyRedactedModerationDiagnostics()
                            } label: {
                                Label("Copy Safe Diagnostics", systemImage: "doc.on.doc")
                            }
                        }
                    }
                case let .loaded(result):
                    let bans = filteredBans(result)
                    if bans.isEmpty {
                        EmptyStateView(title: "No bans", message: "No bans match the current filter.", systemImage: "hand.raised.slash")
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: StoatSpacing.small) {
                                ForEach(bans) { ban in
                                    moderationBanRow(ban, result: result)
                                }
                            }
                        }
                        .frame(minHeight: 120, maxHeight: 260)
                    }
                }
            }
        }
    }

    private func moderationBanRow(_ ban: ServerBan, result: BanListResult) -> some View {
        let user = bannedUser(for: ban, in: result)
        let display = bannedResolvedDisplay(ban, result: result)
        let moderationState = viewModel.cachedMemberModerationMenuState(targetUserID: ban.id.userID)
        return HStack(spacing: StoatSpacing.medium) {
            AvatarView(title: display.displayName, size: 28, isOnline: false, presence: nil, imageData: viewModel.imageData(for: display.avatarFile, kind: .userAvatar))
            VStack(alignment: .leading, spacing: StoatSpacing.xxSmall) {
                Text(display.displayName)
                    .lineLimit(1)
                Text(display.subtitle ?? "Banned user")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let reason = ban.reason, !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Button {
                viewModel.showUserProfile(ban.id.userID, source: .memberRow, serverID: ban.id.serverID)
            } label: {
                Label("Profile", systemImage: "person.crop.circle")
            }
            moderationActionButton(.unban, targetUserID: ban.id.userID, state: moderationState)
        }
        .padding(StoatSpacing.small)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: StoatRadius.small, style: .continuous))
        .onAppear {
            viewModel.noteVisibleIdentity(userID: ban.id.userID, user: user.map { User(id: $0.id, username: $0.username, discriminator: $0.discriminator ?? "0000", avatar: $0.avatar) }, serverID: ban.id.serverID, source: .banList)
            viewModel.loadImageResource(for: display.avatarFile, kind: .userAvatar)
        }
    }

    private func moderationTimeouts(_ presentation: ServerSettingsPresentationSnapshot) -> some View {
        let details = presentation.details
        return GlassPanel {
            VStack(alignment: .leading, spacing: StoatSpacing.medium) {
                HStack {
                    Text("Timeouts")
                        .font(.headline)
                    Spacer()
                    Button {
                        Task { await viewModel.hydrateServerMembers(serverID: details.server.id, force: true, reason: "moderation timeout refresh") }
                    } label: {
                        Label("Refresh Members", systemImage: "arrow.clockwise")
                    }
                }
                TextField("Search timeouts", text: $viewModel.moderationTimeoutSearchText)
                    .textFieldStyle(.roundedBorder)
                let items = presentation.timeoutItems
                if items.isEmpty {
                    EmptyStateView(title: "No active timeouts", message: "Active timeouts appear from refreshed member state.", systemImage: "clock")
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: StoatSpacing.small) {
                            ForEach(items) { item in
                                let moderationState = viewModel.cachedMemberModerationMenuState(targetUserID: item.member.id.userID, member: item.member)
                                let display = viewModel.resolvedUserDisplay(for: item.user, member: item.member, fallbackID: item.member.id.userID, serverID: item.member.id.serverID)
                                HStack(spacing: StoatSpacing.medium) {
                                    AvatarView(title: display.displayName, size: 28, isOnline: item.user?.online == true, presence: item.user?.status?.presence, imageData: viewModel.imageData(for: display.avatarFile, kind: .userAvatar))
                                    VStack(alignment: .leading, spacing: StoatSpacing.xxSmall) {
                                        Text(display.displayName)
                                        Text(item.timeoutSummary ?? "Timed out")
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                    }
                                    Spacer()
                                    moderationActionButton(.removeTimeout, targetUserID: item.member.id.userID, member: item.member, state: moderationState)
                                }
                                .padding(StoatSpacing.small)
                                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: StoatRadius.small, style: .continuous))
                            }
                        }
                    }
                    .frame(minHeight: 110, maxHeight: 220)
                }
            }
        }
    }

    private func memberDetail(_ member: ServerMember, details: ServerSettingsDetails) -> some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: StoatSpacing.medium) {
                let user = viewModel.snapshot.usersByID[member.id.userID]
                let moderationState = viewModel.cachedMemberModerationMenuState(targetUserID: member.id.userID, member: member)
                let display = viewModel.resolvedUserDisplay(for: user, member: member, fallbackID: member.id.userID, serverID: member.id.serverID)
                HStack {
                    Text(display.displayName)
                        .font(.headline)
                    Spacer()
                    Button("Close") { viewModel.closeMemberDetail() }
                }
                Text(display.subtitle ?? "Unknown member")
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
                        .disabled(moderationState[.kick].isDisabled)
                    Button(role: .destructive) { viewModel.requestMemberAction(.ban, for: member) } label: { Label("Ban", systemImage: "hand.raised.fill") }
                        .disabled(moderationState[.ban].isDisabled)
                }

                HStack {
                    Stepper(value: $viewModel.memberTimeoutHours, in: 1...168, step: 1) {
                        Text("Timeout \(Int(viewModel.memberTimeoutHours))h")
                    }
                    Button { viewModel.requestMemberAction(.timeout, for: member) } label: { Label("Apply Timeout", systemImage: "clock.badge.exclamationmark") }
                        .disabled(moderationState[.timeout].isDisabled)
                    Button { viewModel.requestMemberAction(.clearTimeout, for: member) } label: { Label("Clear Timeout", systemImage: "clock.arrow.circlepath") }
                        .disabled(moderationState[.removeTimeout].isDisabled)
                }

                if let draft = viewModel.memberRoleDraft {
                    roleAssignment(draft, details: details)
                }
                if let pending = viewModel.pendingMemberModerationAction {
                    Divider()
                    Text("Confirm \(pending.action.rawValue)")
                        .font(.headline)
                    Text("This action affects \(viewModel.resolvedUserDisplay(for: user, member: pending.member, fallbackID: pending.member.id.userID, serverID: pending.member.id.serverID).displayName).")
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
                            Text(banDisplayName(ban, result: result))
                            Spacer()
                            Button("Unban") { Task { await viewModel.unban(userID: ban.id.userID) } }
                        }
                    }
                }
            }
        }
    }

    private func moderationPermissionSummary(in details: ServerSettingsDetails) -> String? {
        if viewModel.currentUserID == details.server.ownerID {
            return "Server owner actions are still confirmed before sending."
        }
        let permissions = details.permissionPreview.effectivePermissions
        let moderationPermissions: Permissions = [.kickMembers, .banMembers, .timeoutMembers]
        if permissions.intersection(moderationPermissions).isEmpty {
            return "Moderation actions are disabled because this account has no kick, ban, or timeout permission here."
        }
        if !details.permissionPreview.warnings.isEmpty {
            return "Some actions are disabled until member and role hierarchy data is hydrated."
        }
        return nil
    }

    private func memberSubtitle(for item: MemberManagementItem) -> String {
        let roleLine = item.roles.map(\.name).joined(separator: ", ")
        return "\(item.username) · \(roleLine.isEmpty ? "No roles" : roleLine)"
    }

    private func filteredBans(_ result: BanListResult) -> [ServerBan] {
        let query = viewModel.moderationBanSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return result.bans }
        return result.bans.filter { ban in
            banDisplayName(ban, result: result).localizedCaseInsensitiveContains(query)
                || UserDisplayResolver.shortenedID(ban.id.userID).localizedCaseInsensitiveContains(query)
                || (ban.reason?.localizedCaseInsensitiveContains(query) == true)
                || (viewModel.isDeveloperControlsEnabled && ban.id.userID.rawValue.localizedCaseInsensitiveContains(query))
        }
    }

    private func bannedUser(for ban: ServerBan, in result: BanListResult) -> BannedUser? {
        result.users.first { $0.id == ban.id.userID }
    }

    private func banDisplayName(_ ban: ServerBan, result: BanListResult) -> String {
        bannedResolvedDisplay(ban, result: result).displayName
    }

    private func bannedResolvedDisplay(_ ban: ServerBan, result: BanListResult) -> ResolvedUserDisplay {
        if let user = result.users.first(where: { $0.id == ban.id.userID }) {
            return viewModel.resolvedUserDisplay(for: User(id: user.id, username: user.username, discriminator: user.discriminator ?? "0000", avatar: user.avatar), fallbackID: user.id, serverID: ban.id.serverID)
        }
        return viewModel.resolvedUserDisplay(for: viewModel.snapshot.usersByID[ban.id.userID], fallbackID: ban.id.userID, serverID: ban.id.serverID)
    }

    private func filteredTimeoutItems(_ details: ServerSettingsDetails) -> [MemberManagementItem] {
        let query = viewModel.moderationTimeoutSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let items = details.members
            .map { member in
                let user = viewModel.snapshot.usersByID[member.id.userID]
                let display = viewModel.resolvedUserDisplay(for: user, member: member, fallbackID: member.id.userID, serverID: member.id.serverID)
                return MemberManagementItem(member: member, user: user, display: display, server: details.server)
            }
            .filter { $0.timeoutSummary != nil }
        guard !query.isEmpty else { return items }
        return items.filter { item in
            item.displayName.localizedCaseInsensitiveContains(query)
                || item.username.localizedCaseInsensitiveContains(query)
                || item.roles.contains { $0.name.localizedCaseInsensitiveContains(query) }
                || (viewModel.isDeveloperControlsEnabled && item.member.id.userID.rawValue.localizedCaseInsensitiveContains(query))
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

    private func roleSwatchStyle(_ colour: String?) -> AnyShapeStyle {
        guard let colour, let value = CSSRoleColorParser.parse(colour) else {
            return AnyShapeStyle(Color.secondary)
        }
        return value.foregroundStyle
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
                if viewModel.selectedChannel?.kind == .textChannel {
                    Picker("Slowmode", selection: Binding(
                        get: { viewModel.channelEditForm?.slowmodeSeconds ?? 0 },
                        set: { viewModel.channelEditForm?.slowmodeSeconds = $0 }
                    )) {
                        Text("Off").tag(UInt64(0))
                        Text("5 seconds").tag(UInt64(5))
                        Text("10 seconds").tag(UInt64(10))
                        Text("30 seconds").tag(UInt64(30))
                        Text("1 minute").tag(UInt64(60))
                        Text("5 minutes").tag(UInt64(300))
                        Text("10 minutes").tag(UInt64(600))
                        Text("30 minutes").tag(UInt64(1_800))
                        Text("1 hour").tag(UInt64(3_600))
                        Text("2 hours").tag(UInt64(7_200))
                        Text("6 hours").tag(UInt64(21_600))
                    }
                    .accessibilityLabel("Channel slowmode")
                    .accessibilityHint("Limits how often non-exempt members can send messages")
                }

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

public struct PinnedMessagesPanel: View {
    @Bindable private var viewModel: MainShellViewModel

    public init(viewModel: MainShellViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: StoatSpacing.medium) {
            HStack {
                Text("Pinned messages")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await viewModel.refreshPinnedMessages() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh pinned messages")
                Button("Done") { viewModel.closePinnedMessages() }
            }
            pinnedStatus
            pinnedContent
        }
        .padding(StoatSpacing.large)
        .frame(minWidth: 560, minHeight: 420, alignment: .topLeading)
        .onAppear {
            if viewModel.pinnedMessagesState.loadState.items.isEmpty {
                Task { await viewModel.refreshPinnedMessages() }
            }
        }
    }

    @ViewBuilder private var pinnedStatus: some View {
        switch viewModel.pinnedMessagesState.loadState {
        case .idle:
            Text("Pinned messages load only when this sheet is opened or refreshed.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .loading:
            Text("Loading pinned messages...")
                .font(.caption)
                .foregroundStyle(.secondary)
        case let .loaded(_, items):
            Text(items.isEmpty ? "No pinned messages in this channel." : "\(items.count) pinned message(s).")
                .font(.caption)
                .foregroundStyle(.secondary)
        case let .failed(_, message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder private var pinnedContent: some View {
        switch viewModel.pinnedMessagesState.loadState {
        case .idle:
            ContentUnavailableView("Pinned messages", systemImage: "pin", description: Text("Open or refresh pinned messages for the selected channel."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loading:
            LoadingStateView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(_, message):
            ErrorStateView(message)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .loaded(_, items):
            if items.isEmpty {
                ContentUnavailableView("No pinned messages", systemImage: "pin.slash", description: Text("Pinned-message list uses selected-channel search and is not global."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: StoatSpacing.xSmall) {
                        ForEach(items) { item in
                            pinnedRow(item)
                        }
                    }
                }
            }
        }
    }

    private func pinnedRow(_ item: PinnedMessageDisplayItem) -> some View {
        let isBusy = viewModel.pinnedMessagesState.inFlightActionMessageIDs.contains(item.messageID)
        return HStack(alignment: .top, spacing: StoatSpacing.small) {
            Button {
                Task { await viewModel.openPinnedMessage(item) }
            } label: {
                HStack(alignment: .top, spacing: StoatSpacing.small) {
                    Image(systemName: item.isLoaded ? "pin.fill" : "arrow.down.message")
                        .frame(width: 20)
                        .foregroundStyle(item.isLoaded ? .primary : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(item.authorDisplayName)
                                .font(.caption.weight(.semibold))
                            if let createdAt = item.createdAt {
                                Text(createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(item.status ?? (item.isLoaded ? "Loaded" : "Outside range"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(item.summary)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                    }
                }
                .padding(StoatSpacing.small)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: StoatRadius.small, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Pinned message by \(item.authorDisplayName), \(item.summary)")
            Button {
                Task { await viewModel.unpinPinnedMessage(item) }
            } label: {
                Image(systemName: "pin.slash")
            }
            .buttonStyle(.borderless)
            .disabled(isBusy || !item.canUnpin)
            .help("Unpin message")
            .accessibilityLabel("Unpin pinned message")
        }
        .onAppear {
            viewModel.noteVisibleIdentity(userID: item.authorID, source: .visibleSearchResult)
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
                        Text(result.authorDisplayName ?? viewModel.resolvedUserDisplay(for: viewModel.snapshot.usersByID[result.authorID], fallbackID: result.authorID).displayName)
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
        .onAppear {
            viewModel.noteVisibleIdentity(userID: result.authorID, source: .visibleSearchResult)
        }
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
    model.liquidGlassTransparency = reduceGlass ? 0.35 : 1.0
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
    model.liquidGlassTransparency = reduceGlass ? 0.35 : 1.0
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
