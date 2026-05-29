import Foundation
import Observation
import StoatAPI
import StoatDesignSystem
import StoatModels
import StoatPersistence
import StoatRealtime
import StoatUI
import SwiftUI

public enum AppRuntimeMode: Codable, Hashable, Sendable {
    case mock
    case livePreviewDisabled
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

@MainActor
@Observable
public final class MainShellViewModel {
    public var selection: ShellSelection
    public var snapshot: RealtimeSnapshot
    public var connectionState: RealtimeConnectionState
    public var diagnostics: RealtimeDiagnostics?
    public var runtimeMode: AppRuntimeMode
    public var isQuickSwitcherPresented = false
    public var placeholderStatus: String?
    public var shouldFocusComposer = false

    public init(
        selection: ShellSelection = ShellSelection(),
        snapshot: RealtimeSnapshot = MockShellData.snapshot,
        connectionState: RealtimeConnectionState = .idle,
        diagnostics: RealtimeDiagnostics? = nil,
        runtimeMode: AppRuntimeMode = .mock
    ) {
        self.selection = selection
        self.snapshot = snapshot
        self.connectionState = connectionState
        self.diagnostics = diagnostics
        self.runtimeMode = runtimeMode
        validateSelection()
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
        return snapshot.messagesByChannelID[channelID] ?? []
    }

    public var selectedMessageGroups: [MessageGroup] {
        MessageGrouping.group(selectedMessages)
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
        selection.space = .home
        selection.serverID = nil
        selection.channelID = nil
        selection.dmChannelID = nil
        placeholderStatus = nil
    }

    public func selectDiscover() {
        selection.space = .discover
        selection.serverID = nil
        selection.channelID = nil
        selection.dmChannelID = nil
        placeholderStatus = nil
    }

    public func selectDirectMessages() {
        selection.space = .directMessages
        selection.serverID = nil
        selection.channelID = nil
        selection.dmChannelID = snapshot.channelsByID.values.first { $0.kind == .directMessage }?.id
        placeholderStatus = nil
    }

    public func selectServer(_ id: ServerID) {
        guard snapshot.serversByID[id] != nil else {
            validateSelection()
            return
        }
        selection.space = .server(id)
        selection.serverID = id
        selection.channelID = firstVisibleTextChannel(in: id)?.id
        selection.dmChannelID = nil
        placeholderStatus = nil
    }

    public func selectServer(atOneBasedIndex index: Int) {
        let zeroBased = index - 1
        guard servers.indices.contains(zeroBased) else { return }
        selectServer(servers[zeroBased].id)
    }

    public func selectChannel(_ id: ChannelID) {
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
    }

    public func toggleMemberPanel() {
        selection.isMemberPanelVisible.toggle()
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
        placeholderStatus = "Live refresh/reconnect is deferred until credential-driven realtime wiring."
    }

    public func settingsPlaceholder() {
        placeholderStatus = "Settings remain a placeholder in Phase 3."
    }

    public func validateSelection() {
        switch selection.space {
        case .home, .discover, .directMessages:
            break
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

    private func firstVisibleTextChannel(in serverID: ServerID) -> Channel? {
        channels(for: serverID).first { $0.kind == .textChannel || $0.kind == .group || $0.kind == .savedMessages }
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
    @State private var viewModel: MainShellViewModel

    public init(viewModel: MainShellViewModel = MainShellViewModel(runtimeMode: .mock)) {
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        MainShellView(viewModel: viewModel)
    }
}

public struct MainShellView: View {
    @Bindable private var viewModel: MainShellViewModel
    @State private var draft = ""

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
        .overlay(alignment: .bottom) {
            if let status = viewModel.placeholderStatus {
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
                Button { viewModel.settingsPlaceholder() } label: { Label("Settings", systemImage: "gearshape") }
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
            ChatPlaceholderView(viewModel: viewModel, draft: $draft)
        }
    }

    private var connectionChip: some View {
        Text(connectionText)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, StoatSpacing.small)
            .padding(.vertical, StoatSpacing.xSmall)
            .background(Color.primary.opacity(0.06), in: Capsule())
            .accessibilityLabel("Connection state \(connectionText)")
    }

    private var connectionText: String {
        switch viewModel.connectionState {
        case .idle: "Mock"
        case .ready: "Ready"
        case .connecting, .authenticating, .authenticated, .connected: "Connecting"
        case .reconnecting: "Reconnecting"
        case .disconnected: "Offline"
        case .failed: "Failed"
        }
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
            count + (viewModel.snapshot.unreadsByChannelID[channelID] == nil ? 0 : 1)
        }
    }

    private func mentionCount(for server: Server) -> Int {
        server.channelIDs.reduce(0) { count, channelID in
            count + (viewModel.snapshot.unreadsByChannelID[channelID]?.mentions.count ?? 0)
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
            Text("Mock shell · no live connection")
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
        let unread = viewModel.snapshot.unreadsByChannelID[channel.id]
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
    @Binding private var draft: String

    public init(viewModel: MainShellViewModel, draft: Binding<String>) {
        self.viewModel = viewModel
        self._draft = draft
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
                GlassComposer(text: $draft, placeholder: "Message #\(channel.displayName)") {
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
            LazyVStack(alignment: .leading, spacing: StoatSpacing.medium) {
                if viewModel.selectedChannel == nil {
                    EmptyStateView(title: "Choose a channel", message: "Pick a server channel or DM to preview the Phase 3 timeline.")
                        .frame(maxWidth: .infinity)
                } else if viewModel.selectedMessageGroups.isEmpty {
                    EmptyStateView(title: "Nothing here yet", message: "This mock channel has no messages.")
                        .frame(maxWidth: .infinity)
                } else {
                    unreadSeparator
                    ForEach(viewModel.selectedMessageGroups) { group in
                        MessageGroupView(id: group.id, messages: group.messages, author: viewModel.snapshot.usersByID[group.authorID])
                    }
                }
            }
            .padding(StoatSpacing.xLarge)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var unreadSeparator: some View {
        HStack {
            Rectangle().frame(height: 1).foregroundStyle(Color.red.opacity(0.5))
            Text("Unread preview")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
            Rectangle().frame(height: 1).foregroundStyle(Color.red.opacity(0.5))
        }
        .accessibilityLabel("Unread messages preview separator")
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
                LabeledContent("App phase", value: "Phase 3")
                LabeledContent("Runtime", value: "Mock shell, no live auto-connect")
                LabeledContent("Persistence", value: "Deferred")
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
