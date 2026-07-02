import Foundation
import StoatModels
import StoatPersistence
import StoatRealtime
import SwiftUI

public enum AppCommand: Hashable, Sendable {
    case openQuickSwitcher
    case focusComposer
    case pasteAttachment
    case refresh
    case reconnect
    case disconnect
    case resetToMock
    case openAccountSettings
    case openConnectionSettings
    case openAppearanceSettings
    case openNotificationSettings
    case toggleMemberPanel
    case toggleDeveloperControls
    case selectServer(index: Int)
    case selectChannel(ChannelID)
    case selectNextServer
    case selectPreviousServer
    case selectNextChannel
    case selectPreviousChannel
    case selectNextUnreadChannel
    case selectPreviousUnreadChannel
    case jumpToHome
    case jumpToFriends
    case jumpToAddFriend
    case openNewDirectMessage
    case openNewGroup
    case jumpToDiscover
    case openJoinInvite
    case openCreateServer
    case openInviteManagement
    case createInviteForCurrentChannel
    case openDiscoverInBrowser
    case openServerOverview
    case openServerAppearance
    case openCategoryEditor
    case openRoles
    case openPermissions
    case openMembers
    case openPermissionEditor
    case openBanList
    case createRole
    case createCategory
    case openCreateChannel
    case openChannelSettings
    case deleteSelectedChannel
    case selectNextMessage
    case selectPreviousMessage
    case jumpToNewestMessage
    case jumpToFirstUnreadMessage
    case openChannelSearch
    case openLoadedMessageFind
    case openLiveChannelSearch
    case openPinnedChannelSearch
    case selectNextSearchResult
    case selectPreviousSearchResult
    case jumpToSelectedSearchResult
    case loadAroundSelectedSearchResult
    case clearSearchHighlights
    case applyTimelineCalibrationRecommendation
    case resetTimelineTuningDefault
    case importCalibrationNotes
    case copyTimelineCalibration
    case startTimelineCalibration
    case addTimelineCalibrationCheckpoint
    case copyTimelineDiagnostics
    case replyToSelectedMessage
    case cancelReply
    case focusTimeline
    case copySelectedMessage
    case copySelectedMessageID
    case editSelectedMessage
    case deleteSelectedMessage
    case reactToSelectedMessage(String)
    case retrySelectedMessage
    case discardSelectedFailedMessage
    case editAndRetrySelectedFailedMessage
    case pinOrUnpinSelectedMessage
    case closeTransientUI
}

@MainActor
public protocol AppCommandHandling {
    func canPerform(_ command: AppCommand) -> Bool
    func disabledReason(for command: AppCommand) -> String?
    func perform(_ command: AppCommand)
}

private struct AppCommandHandlerFocusedValueKey: FocusedValueKey {
    typealias Value = any AppCommandHandling
}

public extension FocusedValues {
    var appCommandHandler: (any AppCommandHandling)? {
        get { self[AppCommandHandlerFocusedValueKey.self] }
        set { self[AppCommandHandlerFocusedValueKey.self] = newValue }
    }
}

public enum ShellFocusTarget: Hashable, Sendable {
    case serverRail
    case channelList
    case timeline
    case inlineEdit
    case composer
    case quickSwitcher
    case memberPanel
}

public enum QuickSwitcherResultKind: Hashable, Sendable {
    case server(ServerID)
    case channel(ChannelID)
    case directMessage(ChannelID)
    case command(AppCommand)
    case route(ShellRoute)
}

public struct QuickSwitcherResult: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var subtitle: String?
    public var kind: QuickSwitcherResultKind
    public var badgeText: String?
    public var accessibilityLabel: String
    public var disabledReason: String?

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        kind: QuickSwitcherResultKind,
        badgeText: String? = nil,
        accessibilityLabel: String? = nil,
        disabledReason: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
        self.badgeText = badgeText
        self.accessibilityLabel = accessibilityLabel ?? [title, subtitle, badgeText, disabledReason].compactMap { $0 }.joined(separator: ", ")
        self.disabledReason = disabledReason
    }

    public var isEnabled: Bool { disabledReason == nil }
}

public struct ShellNavigationHelper: Sendable {
    public init() {}

    public func orderedServers(in snapshot: RealtimeSnapshot) -> [Server] {
        snapshot.serversByID.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func visibleSelectableChannels(in serverID: ServerID?, snapshot: RealtimeSnapshot) -> [Channel] {
        guard let serverID else { return [] }
        let channels = snapshot.channelsByID.values.filter { $0.serverID == serverID && isSelectable($0) }
        if let orderedIDs = snapshot.serversByID[serverID]?.channelIDs, !orderedIDs.isEmpty {
            return orderedIDs.compactMap { id in channels.first { $0.id == id } }
        }
        return channels.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    public func server(atOneBasedIndex index: Int, snapshot: RealtimeSnapshot) -> Server? {
        let servers = orderedServers(in: snapshot)
        let zeroBased = index - 1
        guard servers.indices.contains(zeroBased) else { return nil }
        return servers[zeroBased]
    }

    public func adjacentServer(from selected: ServerID?, direction: Int, snapshot: RealtimeSnapshot) -> Server? {
        adjacent(in: orderedServers(in: snapshot), selectedID: selected, direction: direction)
    }

    public func adjacentChannel(from selected: ChannelID?, serverID: ServerID?, direction: Int, snapshot: RealtimeSnapshot) -> Channel? {
        adjacent(in: visibleSelectableChannels(in: serverID, snapshot: snapshot), selectedID: selected, direction: direction)
    }

    public func adjacentUnreadChannel(from selected: ChannelID?, serverID: ServerID?, direction: Int, snapshot: RealtimeSnapshot, unreadProvider: (ChannelID) -> ChannelUnread?) -> Channel? {
        let unreadChannels = visibleSelectableChannels(in: serverID, snapshot: snapshot).filter { channel in
            let unread = unreadProvider(channel.id)
            return unread?.lastMessageID != nil || unread?.mentions.isEmpty == false
        }
        return adjacent(in: unreadChannels, selectedID: selected, direction: direction)
    }

    public func isSelectable(_ channel: Channel) -> Bool {
        channel.kind == .textChannel || channel.kind == .group || channel.kind == .savedMessages || channel.kind == .directMessage
    }

    private func adjacent<T: Identifiable>(in items: [T], selectedID: T.ID?, direction: Int) -> T? where T.ID: Equatable {
        guard !items.isEmpty else { return nil }
        guard let selectedID, let current = items.firstIndex(where: { $0.id == selectedID }) else {
            return direction >= 0 ? items.first : items.last
        }
        let next = current + (direction >= 0 ? 1 : -1)
        guard items.indices.contains(next) else { return nil }
        return items[next]
    }
}

@MainActor
@Observable
public final class QuickSwitcherViewModel {
    public var query: String = "" {
        didSet { scheduleFilteredResults() }
    }
    public var selectedIndex: Int = 0
    public private(set) var results: [QuickSwitcherResult] = []

    @ObservationIgnored private var snapshot: RealtimeSnapshot
    @ObservationIgnored private var selection: ShellSelection
    @ObservationIgnored private var indexedResultsCache: [QuickSwitcherResult] = []
    @ObservationIgnored private var normalizedSearchTextByID: [String: String] = [:]
    @ObservationIgnored private let navigation = ShellNavigationHelper()
    @ObservationIgnored private let canPerform: (AppCommand) -> Bool
    @ObservationIgnored private let disabledReason: (AppCommand) -> String?
    @ObservationIgnored private var indexTask: Task<Void, Never>?
    @ObservationIgnored private var filterTask: Task<Void, Never>?
    @ObservationIgnored private var indexGeneration = 0
    @ObservationIgnored private var filterGeneration = 0

    public init(
        snapshot: RealtimeSnapshot,
        selection: ShellSelection = ShellSelection(),
        canPerform: @escaping (AppCommand) -> Bool = { _ in true },
        disabledReason: @escaping (AppCommand) -> String? = { _ in nil }
    ) {
        self.snapshot = snapshot
        self.selection = selection
        self.canPerform = canPerform
        self.disabledReason = disabledReason
        rebuildIndex()
        rebuildFilteredResults()
    }

    deinit {
        indexTask?.cancel()
        filterTask?.cancel()
    }

    public var selectedResult: QuickSwitcherResult? {
        let current = results
        guard current.indices.contains(selectedIndex) else { return current.first }
        return current[selectedIndex]
    }

    public func update(snapshot: RealtimeSnapshot, selection: ShellSelection) {
        self.snapshot = snapshot
        self.selection = selection
        scheduleRebuildIndex()
    }

    public func moveSelection(_ delta: Int) {
        let count = results.count
        guard count > 0 else {
            selectedIndex = 0
            return
        }
        selectedIndex = min(max(selectedIndex + delta, 0), count - 1)
    }

    public func command(for result: QuickSwitcherResult) -> AppCommand? {
        guard result.isEnabled else { return nil }
        switch result.kind {
        case let .server(id):
            guard let index = navigation.orderedServers(in: snapshot).firstIndex(where: { $0.id == id }) else { return nil }
            return .selectServer(index: index + 1)
        case let .channel(id), let .directMessage(id):
            return .selectChannel(id)
        case let .command(command):
            return command
        case .route(.home):
            return .jumpToHome
        case .route(.friends):
            return .jumpToFriends
        case .route(.discover):
            return .jumpToDiscover
        case let .route(.server(serverID, channelID)):
            if let channelID { return .selectChannel(channelID) }
            guard let index = navigation.orderedServers(in: snapshot).firstIndex(where: { $0.id == serverID }) else { return nil }
            return .selectServer(index: index + 1)
        case let .route(.directMessage(channelID)):
            guard let channelID else { return nil }
            return .selectChannel(channelID)
        }
    }

    nonisolated private static func indexedEntityResults(
        snapshot: RealtimeSnapshot,
        selection: ShellSelection
    ) -> [QuickSwitcherResult] {
        var output: [QuickSwitcherResult] = [
            QuickSwitcherResult(id: "route-home", title: "Home", subtitle: "Open home", kind: .route(.home), badgeText: "Route"),
            QuickSwitcherResult(id: "route-friends", title: "Friends", subtitle: "Open friends", kind: .route(.friends), badgeText: "Route"),
            QuickSwitcherResult(id: "route-discover", title: "Discover", subtitle: "Open server discovery placeholder", kind: .route(.discover), badgeText: "Route")
        ]

        let navigation = ShellNavigationHelper()
        for server in navigation.orderedServers(in: snapshot) {
            output.append(QuickSwitcherResult(
                id: "server-\(server.id.rawValue)",
                title: server.name,
                subtitle: "Server",
                kind: .server(server.id),
                badgeText: selection.serverID == server.id ? "Selected" : nil
            ))
        }

        let serversByID = snapshot.serversByID
        for channel in snapshot.channelsByID.values.sorted(by: Self.channelSort) where navigation.isSelectable(channel) {
            let serverName = channel.serverID.flatMap { serversByID[$0]?.name }
            let isDM = DMChannelClassifier.isDirectMessageLike(channel)
            output.append(QuickSwitcherResult(
                id: "\(isDM ? "dm" : "channel")-\(channel.id.rawValue)",
                title: isDM ? channel.displayName : "# \(channel.displayName)",
                subtitle: isDM ? "Direct message" : [serverName, "Channel"].compactMap { $0 }.joined(separator: " · "),
                kind: isDM ? .directMessage(channel.id) : .channel(channel.id),
                badgeText: selection.channelID == channel.id || selection.dmChannelID == channel.id ? "Selected" : nil
            ))
        }

        return output
    }

    private func rebuildIndex() {
        indexedResultsCache = Self.indexedEntityResults(snapshot: snapshot, selection: selection) + commandResults()
        normalizedSearchTextByID = Dictionary(
            uniqueKeysWithValues: indexedResultsCache.map { result in
                let text = [result.title, result.subtitle, result.badgeText]
                    .compactMap { $0 }
                    .joined(separator: " ")
                    .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                return (result.id, text)
            }
        )
    }

    private func scheduleRebuildIndex() {
        indexGeneration &+= 1
        let generation = indexGeneration
        indexTask?.cancel()
        let snapshot = snapshot
        let selection = selection
        let commands = commandResults()
        indexTask = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated) {
                let indexed = Self.indexedEntityResults(snapshot: snapshot, selection: selection) + commands
                let normalized = Dictionary(
                    uniqueKeysWithValues: indexed.map { result in
                        let text = [result.title, result.subtitle, result.badgeText]
                            .compactMap { $0 }
                            .joined(separator: " ")
                            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                        return (result.id, text)
                    }
                )
                return (indexed, normalized)
            }
            let prepared = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard !Task.isCancelled, let self, generation == self.indexGeneration else { return }
            self.indexedResultsCache = prepared.0
            self.normalizedSearchTextByID = prepared.1
            self.scheduleFilteredResults()
            self.indexTask = nil
        }
    }

    private func scheduleFilteredResults() {
        filterGeneration &+= 1
        let generation = filterGeneration
        filterTask?.cancel()
        let needle = normalizedQuery
        if needle.isEmpty || indexedResultsCache.count <= 500 {
            rebuildFilteredResults()
            return
        }
        let indexed = indexedResultsCache
        let normalized = normalizedSearchTextByID
        filterTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(35))
            } catch {
                return
            }
            let worker = Task.detached(priority: .userInitiated) {
                Array(indexed.lazy.filter {
                    normalized[$0.id]?.contains(needle) == true
                }.prefix(50))
            }
            let filtered = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard !Task.isCancelled, let self, generation == self.filterGeneration else { return }
            self.results = filtered
            self.selectedIndex = filtered.isEmpty ? 0 : min(self.selectedIndex, filtered.count - 1)
            self.filterTask = nil
        }
    }

    private func rebuildFilteredResults() {
        let needle = normalizedQuery
        if needle.isEmpty {
            results = Array(indexedResultsCache.prefix(16))
        } else {
            results = Array(indexedResultsCache.lazy.filter {
                self.normalizedSearchTextByID[$0.id]?.contains(needle) == true
            }.prefix(50))
        }
        selectedIndex = results.isEmpty ? 0 : min(selectedIndex, results.count - 1)
    }

    private var normalizedQuery: String {
        query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private func commandResults() -> [QuickSwitcherResult] {
        [
            commandResult(.focusComposer, title: "Focus Composer", subtitle: "Move keyboard focus to the message composer"),
            commandResult(.pasteAttachment, title: "Paste Attachment", subtitle: "Review image or file attachments from the clipboard"),
            commandResult(.focusTimeline, title: "Focus Timeline", subtitle: "Move keyboard focus to the message timeline"),
            commandResult(.refresh, title: "Refresh", subtitle: "Refresh the current runtime context"),
            commandResult(.reconnect, title: "Reconnect", subtitle: "Retry the live realtime session"),
            commandResult(.disconnect, title: "Disconnect", subtitle: "Disconnect the live realtime session"),
            commandResult(.jumpToFriends, title: "Open Friends", subtitle: "Open the friends and requests view"),
            commandResult(.jumpToAddFriend, title: "Add Friend", subtitle: "Open the add friend view"),
            commandResult(.jumpToDiscover, title: "Open Discover", subtitle: "Open server discovery and invite tools"),
            commandResult(.openJoinInvite, title: "Join Invite", subtitle: "Paste and preview an invite code or link"),
            commandResult(.openCreateServer, title: "Create Server", subtitle: "Create a new server after live connection"),
            commandResult(.openInviteManagement, title: "Manage Invites", subtitle: "Create, copy, or revoke invites for the selected server"),
            commandResult(.createInviteForCurrentChannel, title: "Create Invite", subtitle: "Create and copy an invite for the selected channel"),
            commandResult(.openDiscoverInBrowser, title: "Open Discover in Browser", subtitle: "Open the web-backed Discover surface"),
            commandResult(.openServerOverview, title: "Server Settings", subtitle: "Review selected server settings and management actions"),
            commandResult(.openServerAppearance, title: "Server Appearance", subtitle: "Edit selected server icon and banner"),
            commandResult(.openCategoryEditor, title: "Category Editor", subtitle: "Create, rename, delete, and move channels between categories"),
            commandResult(.openRoles, title: "Roles", subtitle: "Review and manage selected server roles"),
            commandResult(.openPermissions, title: "Permissions", subtitle: "Preview effective permissions for the selected server"),
            commandResult(.openMembers, title: "Members", subtitle: "Manage selected server members and roles"),
            commandResult(.openPermissionEditor, title: "Permission Editor", subtitle: "Edit selected server default permissions after confirmation"),
            commandResult(.openBanList, title: "Ban List", subtitle: "Fetch selected server bans after live connection"),
            commandResult(.createRole, title: "Create Role", subtitle: "Create a role in the selected server"),
            commandResult(.createCategory, title: "Create Category", subtitle: "Create a draft category in the selected server"),
            commandResult(.openCreateChannel, title: "Create Channel", subtitle: "Create a text channel in the selected server"),
            commandResult(.openChannelSettings, title: "Channel Settings", subtitle: "Edit the selected text channel"),
            commandResult(.deleteSelectedChannel, title: "Delete Channel", subtitle: "Delete the selected text channel after confirmation"),
            commandResult(.openChannelSearch, title: "Search This Channel", subtitle: "Open selected-channel search"),
            commandResult(.openLoadedMessageFind, title: "Find in Loaded Messages", subtitle: "Search loaded messages only"),
            commandResult(.openLiveChannelSearch, title: "Live Search Selected Channel", subtitle: "Search this channel after live connection"),
            commandResult(.openPinnedChannelSearch, title: "Pinned in This Channel", subtitle: "Search pinned messages in the selected channel"),
            commandResult(.jumpToSelectedSearchResult, title: "Jump to Search Result", subtitle: "Jump to the selected search result"),
            commandResult(.loadAroundSelectedSearchResult, title: "Load Around Search Result", subtitle: "Fetch messages around the selected result"),
            commandResult(.clearSearchHighlights, title: "Clear Search Highlights", subtitle: "Clear selected-channel search highlights"),
            commandResult(.replyToSelectedMessage, title: "Reply to Message", subtitle: "Reply to the focused message"),
            commandResult(.cancelReply, title: "Cancel Reply", subtitle: "Clear the active reply context"),
            commandResult(.startTimelineCalibration, title: "Start Timeline Calibration", subtitle: "Begin a manual calibration run"),
            commandResult(.addTimelineCalibrationCheckpoint, title: "Add Calibration Checkpoint", subtitle: "Record current timeline diagnostics"),
            commandResult(.importCalibrationNotes, title: "Import Calibration Notes", subtitle: "Redact and import pasted calibration notes"),
            commandResult(.applyTimelineCalibrationRecommendation, title: "Apply Calibration Recommendation", subtitle: "Apply the visible timeline tuning recommendation"),
            commandResult(.resetTimelineTuningDefault, title: "Reset Timeline Tuning", subtitle: "Restore conservative timeline tuning defaults"),
            commandResult(.copyTimelineCalibration, title: "Copy Calibration Summary", subtitle: "Copy redacted timeline calibration output"),
            commandResult(.copyTimelineDiagnostics, title: "Copy Timeline Diagnostics", subtitle: "Copy redacted timeline diagnostics"),
            commandResult(.toggleMemberPanel, title: "Toggle Member Panel", subtitle: "Show or hide the member panel"),
            commandResult(.openAccountSettings, title: "Account Settings", subtitle: "Open Account & Connection settings"),
            commandResult(.openConnectionSettings, title: "Connection Settings", subtitle: "Open connection settings"),
            commandResult(.openAppearanceSettings, title: "Appearance Settings", subtitle: "Adjust Liquid Glass and message density"),
            commandResult(.openNotificationSettings, title: "Notification Settings", subtitle: "Open notification settings")
        ]
    }

    private func commandResult(_ command: AppCommand, title: String, subtitle: String) -> QuickSwitcherResult {
        let reason = canPerform(command) ? nil : disabledReason(command) ?? "Unavailable"
        return QuickSwitcherResult(
            id: "command-\(title)",
            title: title,
            subtitle: subtitle,
            kind: .command(command),
            badgeText: "Command",
            disabledReason: reason
        )
    }

    nonisolated private static func channelSort(_ lhs: Channel, _ rhs: Channel) -> Bool {
        let leftServer = lhs.serverID?.rawValue ?? ""
        let rightServer = rhs.serverID?.rawValue ?? ""
        if leftServer != rightServer { return leftServer < rightServer }
        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }
}
