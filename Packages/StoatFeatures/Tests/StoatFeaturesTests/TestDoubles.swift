//  Moved out of the library targets in Phase 73.
//
//  These lived in Sources/, which is why they shipped in the built product and why
//  MainShellViewModel.init constructed them as its defaults. As test-target files they get
//  @testable access and cannot reach production.

import Foundation
import Observation
import SwiftUI
import StoatAPI
import StoatDesignSystem
import StoatModels
import StoatPersistence
import StoatRealtime
import StoatUI
import StoatVoice
@testable import StoatFeatures

public actor StubStoatAPIClient: StoatAPIClient {
    private var currentUser: User
    private var users: [UserID: User]
    private var servers: [Server]
    private var channels: [Channel]
    private var syncedSettings: [String: SyncedSettingValue] = [:]
    private var messagesByChannel: [ChannelID: [Message]]
    private var invites: [InviteID: Invite]
    private var members: [MemberCompositeKey: ServerMember]
    private var bans: [MemberCompositeKey: ServerBan]
    private var profiles: [UserID: UserProfile]
    private var emojis: [EmojiID: Emoji]

    public init() {
        let liquid = User(
            id: "01HX0000000000000000000001",
            username: "liquidbagel",
            discriminator: "0001",
            displayName: "Liquid Bagel",
            status: UserStatus(text: "Kneading native macOS", presence: .online),
            relationship: .user,
            online: true
        )
        let stoat = User(
            id: "01HX0000000000000000000002",
            username: "stoat-system",
            discriminator: "0000",
            displayName: "Stoat System",
            relationship: .friend,
            online: true
        )
        let design = User(
            id: "01HX0000000000000000000003",
            username: "designpilot",
            discriminator: "0420",
            displayName: "Design Pilot",
            relationship: .friend,
            online: false
        )

        let general: ChannelID = "01HX0000000000000000000101"
        let apiResearch: ChannelID = "01HX0000000000000000000102"
        let macNative: ChannelID = "01HX0000000000000000000103"
        let lab: ServerID = "01HX0000000000000000000201"
        let orchard: ServerID = "01HX0000000000000000000202"

        let memberPermissions: Permissions = [
            .viewChannel,
            .readMessageHistory,
            .sendMessage,
            .sendEmbeds,
            .uploadFiles,
            .react
        ]

        let coreRole = Role(
            id: "01HX0000000000000000000301",
            name: "Core Crew",
            permissions: PermissionOverride(allow: memberPermissions)
        )

        self.currentUser = liquid
        self.users = [
            liquid.id: liquid,
            stoat.id: stoat,
            design.id: design
        ]
        self.servers = [
            Server(
                id: lab,
                ownerID: liquid.id,
                name: "Bagel Lab",
                description: "Phase 1 mock workspace",
                channelIDs: [general, apiResearch, macNative],
                categories: [
                    ServerCategory(id: "mock-cat-core", title: "Core", channels: [general, apiResearch]),
                    ServerCategory(id: "mock-cat-native", title: "Native", channels: [macNative])
                ],
                roles: [coreRole.id: coreRole],
                defaultPermissions: memberPermissions.union([.manageChannel, .manageServer, .inviteOthers]),
                discoverable: false
            ),
            Server(
                id: orchard,
                ownerID: design.id,
                name: "Stoat Orchard",
                channelIDs: [],
                defaultPermissions: [.viewChannel, .readMessageHistory]
            )
        ]
        self.channels = [
            Channel(id: general, kind: .textChannel, serverID: lab, name: "general", description: "Mock chat for previews"),
            Channel(id: apiResearch, kind: .textChannel, serverID: lab, name: "api-research"),
            Channel(id: macNative, kind: .textChannel, serverID: lab, name: "macos-native"),
            Channel(id: "01HX0000000000000000000104", kind: .directMessage, active: true, recipients: [liquid.id, design.id])
        ]
        self.invites = [
            "bagel-lab": Invite(id: "bagel-lab", kind: .server, serverID: lab, creatorID: liquid.id, channelID: general)
        ]
        self.members = [
            MemberCompositeKey(serverID: lab, userID: liquid.id): ServerMember(id: MemberCompositeKey(serverID: lab, userID: liquid.id), joinedAt: Date(timeIntervalSince1970: 1_700_000_000), roles: [coreRole.id]),
            MemberCompositeKey(serverID: lab, userID: stoat.id): ServerMember(id: MemberCompositeKey(serverID: lab, userID: stoat.id), joinedAt: Date(timeIntervalSince1970: 1_700_000_100)),
            MemberCompositeKey(serverID: lab, userID: design.id): ServerMember(id: MemberCompositeKey(serverID: lab, userID: design.id), joinedAt: Date(timeIntervalSince1970: 1_700_000_200))
        ]
        self.bans = [:]
        self.profiles = [
            liquid.id: UserProfile(content: "Mock profile for Liquid Bagel."),
            stoat.id: UserProfile(content: "Mock profile for Stoat System."),
            design.id: UserProfile(content: "Mock profile for Design Pilot.")
        ]
        self.emojis = [:]
        self.messagesByChannel = [
            general: [
                Message(
                    id: "01HX0000000000000000000401",
                    channelID: general,
                    authorID: liquid.id,
                    content: "Phase 1 models are wired to mock data. No live credentials required."
                ),
                Message(
                    id: "01HX0000000000000000000402",
                    channelID: general,
                    authorID: stoat.id,
                    content: "The live client will stay quiet until you provide a real token.",
                    reactions: ["🥯": [liquid.id, design.id]]
                )
            ],
            apiResearch: [
                Message(
                    id: "01HX0000000000000000000403",
                    channelID: apiResearch,
                    authorID: design.id,
                    content: "Verified REST routes are in; realtime list hydration waits for Phase 2."
                )
            ],
            macNative: [
                Message(
                    id: "01HX0000000000000000000404",
                    channelID: macNative,
                    authorID: liquid.id,
                    content: "SwiftUI shell, model package, API package. Nice and tidy."
                )
            ]
        ]
    }

    public func fetchRootConfiguration() async throws -> StoatConfig {
        StoatConfig(
            revolt: "0.13.7",
            features: StoatFeatures(
                captcha: CaptchaFeature(enabled: true, key: "mock"),
                email: true,
                inviteOnly: false,
                autumn: FeatureConfiguration(enabled: true, url: "https://cdn.stoatusercontent.com"),
                january: FeatureConfiguration(enabled: true, url: "https://proxy.stoatusercontent.com"),
                livekit: VoiceFeature(enabled: true, nodes: []),
                limits: LimitsConfig(global: GlobalLimits(), newUser: UserLimits(), default: UserLimits()),
                legalLinks: LegalLinks()
            ),
            ws: "wss://events.stoat.chat",
            app: "https://stoat.chat",
            vapid: "mock",
            build: BuildInformation()
        )
    }

    public func fetchCurrentUser() async throws -> User {
        currentUser
    }

    public func fetchUser(userID: UserID) async throws -> User {
        guard let user = users[userID] else {
            throw StoatAPIError.notFound
        }
        return user
    }

    public func editUser(userID: UserID, draft: UserEditDraft) async throws -> User {
        guard var user = users[userID] else {
            throw StoatAPIError.notFound
        }
        if let status = draft.status {
            user.status = status
            user.online = status.presence != .invisible
        }
        if let displayName = draft.displayName {
            user.displayName = displayName
        }
        if let avatar = draft.avatar {
            user.avatar = File(
                id: FileID(rawValue: avatar),
                tag: UploadTag.avatars.rawAPIValue,
                filename: "mock-user-avatar.png",
                metadata: .image(width: 96, height: 96, thumbhash: nil, animated: nil),
                contentType: "image/png",
                size: 1024,
                userID: userID
            )
        }
        if draft.remove.contains(.displayName) {
            user.displayName = nil
        }
        if draft.remove.contains(.avatar) {
            user.avatar = nil
        }
        if draft.remove.contains(.statusText) {
            user.status?.text = nil
        }
        if draft.remove.contains(.statusPresence) {
            user.status?.presence = nil
        }
        if draft.profile != nil || draft.remove.contains(.profileContent) || draft.remove.contains(.profileBackground) {
            var profile = profiles[userID] ?? UserProfile()
            if draft.remove.contains(.profileContent) {
                profile.content = nil
            }
            if draft.remove.contains(.profileBackground) {
                profile.background = nil
            }
            if let content = draft.profile?.content {
                profile.content = content
            }
            if let background = draft.profile?.background {
                profile.background = File(
                    id: FileID(rawValue: background),
                    tag: UploadTag.backgrounds.rawAPIValue,
                    filename: "mock-profile-background.png",
                    metadata: .image(width: 960, height: 320, thumbhash: nil, animated: nil),
                    contentType: "image/png",
                    size: 4096,
                    userID: userID
                )
            }
            profiles[userID] = profile
        }
        users[userID] = user
        if currentUser.id == userID {
            currentUser = user
        }
        return user
    }

    public func fetchUserProfile(userID: UserID) async throws -> UserProfile {
        guard let user = users[userID] else {
            throw StoatAPIError.notFound
        }
        return profiles[userID] ?? UserProfile(content: "Mock profile for \(user.displayName ?? user.username).")
    }

    public func fetchServers() async throws -> [Server] {
        servers
    }

    public func fetchChannels() async throws -> [Channel] {
        channels
    }

    public func fetchDirectMessages() async throws -> [Channel] {
        channels.filter { $0.kind == .directMessage || $0.kind == .group || $0.kind == .savedMessages }
    }

    public func openDirectMessage(userID: UserID) async throws -> Channel {
        if let existing = channels.first(where: { channel in
            (channel.kind == .directMessage || channel.kind == .savedMessages) &&
                (channel.userID == userID || channel.recipients.contains(userID))
        }) {
            return existing
        }
        guard users[userID] != nil || userID == currentUser.id else {
            throw StoatAPIError.notFound
        }
        let channel = Channel(
            id: ChannelID(rawValue: "mock-dm-\(userID.rawValue)"),
            kind: userID == currentUser.id ? .savedMessages : .directMessage,
            userID: userID == currentUser.id ? currentUser.id : nil,
            active: true,
            recipients: userID == currentUser.id ? [] : [currentUser.id, userID]
        )
        channels.append(channel)
        return channel
    }

    public func fetchChannel(id: ChannelID) async throws -> Channel {
        guard let channel = channels.first(where: { $0.id == id }) else {
            throw StoatAPIError.notFound
        }
        return channel
    }

    public func fetchMessage(channelID: ChannelID, messageID: MessageID) async throws -> Message {
        guard let message = messagesByChannel[channelID]?.first(where: { $0.id == messageID }) else {
            throw StoatAPIError.notFound
        }
        return message
    }

    public func fetchMessages(channelID: ChannelID, options: MessageFetchOptions) async throws -> [Message] {
        var messages = messagesByChannel[channelID] ?? []
        if let nearby = options.nearby,
           let index = messages.firstIndex(where: { $0.id == nearby }) {
            let limit = max(1, options.limit ?? messages.count)
            let side = max(0, limit / 2)
            let lower = max(messages.startIndex, index - side)
            let upper = min(messages.endIndex, index + side + 1)
            messages = Array(messages[lower..<upper])
        } else {
            if let before = options.before, let index = messages.firstIndex(where: { $0.id == before }) {
                messages = Array(messages[..<index])
            }
            if let after = options.after, let index = messages.firstIndex(where: { $0.id == after }) {
                messages = Array(messages[messages.index(after: index)...])
            }
            if options.sort == .oldest {
                messages.sort { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
            } else if options.sort == .latest {
                messages.sort { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
            }
        }
        if let limit = options.limit, limit < messages.count {
            messages = Array(messages.prefix(limit))
        }
        return messages
    }

    public func fetchMessages(channelID: ChannelID, before: MessageID?, after: MessageID?, limit: Int?) async throws -> [Message] {
        try await fetchMessages(channelID: channelID, options: MessageFetchOptions(before: before, after: after, limit: limit))
    }

    public func searchMessages(channelID: ChannelID, request: ChannelMessageSearchRequest) async throws -> [Message] {
        var messages = messagesByChannel[channelID] ?? []
        if request.pinned == true {
            messages = messages.filter { $0.pinned == true }
        } else if let query = request.query?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty {
            messages = messages.filter { ($0.content ?? "").localizedCaseInsensitiveContains(query) }
        } else {
            messages = []
        }
        if let before = request.before, let index = messages.firstIndex(where: { $0.id == before }) {
            messages = Array(messages[..<index])
        }
        if let after = request.after, let index = messages.firstIndex(where: { $0.id == after }) {
            messages = Array(messages[messages.index(after: index)...])
        }
        if request.sort == .oldest {
            messages.sort { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
        } else {
            messages.sort { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        }
        if let limit = request.limit, limit < messages.count {
            messages = Array(messages.prefix(limit))
        }
        return messages
    }

    public func sendMessage(channelID: ChannelID, draft: MessageDraft) async throws -> Message {
        let files = draft.attachments?.map {
            File(id: $0, tag: "attachments", filename: "\($0.rawValue)", contentType: "application/octet-stream", size: 0)
        }
        let message = Message(
            id: MessageID(rawValue: "01HX0000000000000000\(String(format: "%06d", Int.random(in: 5000...9999)))"),
            channelID: channelID,
            authorID: currentUser.id,
            content: draft.content,
            nonce: draft.nonce,
            attachments: files,
            replies: draft.replies?.map(\.id),
            interactions: draft.interactions ?? MessageInteractions(),
            masquerade: draft.masquerade,
            flags: draft.flags ?? []
        )
        messagesByChannel[channelID, default: []].append(message)
        return message
    }

    public func editMessage(channelID: ChannelID, messageID: MessageID, draft: MessageEditDraft) async throws -> Message {
        guard var messages = messagesByChannel[channelID],
              let index = messages.firstIndex(where: { $0.id == messageID })
        else {
            throw StoatAPIError.notFound
        }
        messages[index].content = draft.content ?? messages[index].content
        messages[index].editedAt = Date()
        messagesByChannel[channelID] = messages
        return messages[index]
    }

    public func deleteMessage(channelID: ChannelID, messageID: MessageID) async throws {
        messagesByChannel[channelID]?.removeAll { $0.id == messageID }
    }

    public func ackChannel(channelID: ChannelID, messageID: MessageID) async throws {
    }

    public var voiceJoinError: (any Error)?

    public func setVoiceJoinError(_ error: (any Error)?) {
        voiceJoinError = error
    }

    public func joinVoiceChannel(channelID: ChannelID) async throws -> VoiceJoinResponse {
        if let voiceJoinError { throw voiceJoinError }
        return VoiceJoinResponse(token: "stub-token-\(channelID.rawValue)", url: "wss://voice.stub.test")
    }

    public func addReaction(channelID: ChannelID, messageID: MessageID, emoji: String) async throws {
        guard var messages = messagesByChannel[channelID],
              let index = messages.firstIndex(where: { $0.id == messageID })
        else {
            throw StoatAPIError.notFound
        }
        messages[index].reactions[emoji, default: []].insert(currentUser.id)
        messagesByChannel[channelID] = messages
    }

    public func removeReaction(channelID: ChannelID, messageID: MessageID, emoji: String, removeAll: Bool) async throws {
        guard var messages = messagesByChannel[channelID],
              let index = messages.firstIndex(where: { $0.id == messageID })
        else {
            throw StoatAPIError.notFound
        }
        if removeAll {
            messages[index].reactions[emoji] = nil
        } else {
            messages[index].reactions[emoji]?.remove(currentUser.id)
        }
        messagesByChannel[channelID] = messages
    }

    public func pinMessage(channelID: ChannelID, messageID: MessageID) async throws {
        try setPinned(true, channelID: channelID, messageID: messageID)
    }

    public func unpinMessage(channelID: ChannelID, messageID: MessageID) async throws {
        try setPinned(false, channelID: channelID, messageID: messageID)
    }

    public func uploadFile(data: Data, filename: String, mimeType: String, tag: UploadTag) async throws -> UploadedFile {
        UploadedFile(id: FileID(rawValue: "mock-\(tag.rawAPIValue)-\(abs(filename.hashValue))"))
    }

    public func sendFriendRequest(username: String) async throws -> User {
        guard let userID = users.first(where: { _, user in
            "\(user.username)#\(user.discriminator)" == username || user.username == username
        })?.key else {
            throw StoatAPIError.notFound
        }
        return try updateRelationship(userID: userID, status: .outgoing)
    }

    public func acceptFriendRequest(userID: UserID) async throws -> User {
        try updateRelationship(userID: userID, status: .friend)
    }

    public func denyFriendRequest(userID: UserID) async throws -> User {
        try updateRelationship(userID: userID, status: .none)
    }

    public func removeFriend(userID: UserID) async throws -> User {
        try updateRelationship(userID: userID, status: .none)
    }

    public func blockUser(userID: UserID) async throws -> User {
        try updateRelationship(userID: userID, status: .blocked)
    }

    public func unblockUser(userID: UserID) async throws -> User {
        try updateRelationship(userID: userID, status: .none)
    }

    public func fetchInvitePreview(code: InviteCode) async throws -> InvitePreview {
        guard let invite = invites[InviteID(rawValue: code.rawValue)] else {
            throw StoatAPIError.notFound
        }
        switch invite.kind {
        case .server:
            guard let serverID = invite.serverID,
                  let server = servers.first(where: { $0.id == serverID }),
                  let channel = channels.first(where: { $0.id == invite.channelID })
            else {
                throw StoatAPIError.notFound
            }
            return InvitePreview(
                code: code,
                kind: .server,
                serverID: server.id,
                serverName: server.name,
                serverIcon: server.icon,
                serverBanner: server.banner,
                channelID: channel.id,
                channelName: channel.displayName,
                channelDescription: channel.description,
                inviterName: users[invite.creatorID]?.displayName ?? users[invite.creatorID]?.username ?? "Unknown User",
                inviterAvatar: users[invite.creatorID]?.avatar,
                memberCount: 4,
                isAlreadyJoined: true
            )
        case .group:
            guard let channel = channels.first(where: { $0.id == invite.channelID }) else {
                throw StoatAPIError.notFound
            }
            return InvitePreview(
                code: code,
                kind: .group,
                channelID: channel.id,
                channelName: channel.displayName,
                channelDescription: channel.description,
                inviterName: users[invite.creatorID]?.displayName ?? users[invite.creatorID]?.username ?? "Unknown User",
                inviterAvatar: users[invite.creatorID]?.avatar
            )
        case .unknown:
            throw StoatAPIError.unimplementedEndpoint("Unknown invite type.")
        }
    }

    public func joinInvite(code: InviteCode) async throws -> InviteJoinResponse {
        let preview = try await fetchInvitePreview(code: code)
        switch preview.kind {
        case .server:
            guard let serverID = preview.serverID,
                  let server = servers.first(where: { $0.id == serverID })
            else {
                throw StoatAPIError.notFound
            }
            return .server(server: server, channels: channels.filter { $0.serverID == serverID })
        case .group:
            guard let channel = channels.first(where: { $0.id == preview.channelID }) else {
                throw StoatAPIError.notFound
            }
            return .group(channel: channel, users: channel.recipients.compactMap { users[$0] })
        case .unknown:
            throw StoatAPIError.unimplementedEndpoint("Unknown invite type.")
        }
    }

    public func createInvite(channelID: ChannelID) async throws -> Invite {
        guard let channel = channels.first(where: { $0.id == channelID }) else {
            throw StoatAPIError.notFound
        }
        let code = InviteID(rawValue: "mock-\(channelID.rawValue.suffix(6))")
        let invite = Invite(id: code, kind: channel.serverID == nil ? .group : .server, serverID: channel.serverID, creatorID: currentUser.id, channelID: channelID)
        invites[code] = invite
        return invite
    }

    public func fetchServerInvites(serverID: ServerID) async throws -> [Invite] {
        guard servers.contains(where: { $0.id == serverID }) else {
            throw StoatAPIError.notFound
        }
        return invites.values.filter { $0.serverID == serverID }.sorted { $0.id.rawValue < $1.id.rawValue }
    }

    public func deleteInvite(code: InviteCode) async throws {
        guard invites.removeValue(forKey: InviteID(rawValue: code.rawValue)) != nil else {
            throw StoatAPIError.notFound
        }
    }

    public func createServer(draft: ServerCreateDraft) async throws -> ServerCreateResponse {
        guard let validated = draft.validatedForCreate else {
            throw StoatAPIError.invalidEnvironment("Server name must be 1 to 32 characters.")
        }
        let serverID = ServerID(rawValue: "mock-server-\(servers.count + 1)")
        let channelID = ChannelID(rawValue: "mock-channel-\(channels.count + 1)")
        let server = Server(
            id: serverID,
            ownerID: currentUser.id,
            name: validated.name,
            description: validated.description,
            channelIDs: [channelID],
            defaultPermissions: [.viewChannel, .readMessageHistory, .sendMessage, .uploadFiles, .react],
            nsfw: validated.nsfw ?? false
        )
        let channel = Channel(id: channelID, kind: .textChannel, serverID: serverID, name: "general")
        servers.append(server)
        channels.append(channel)
        return ServerCreateResponse(server: server, channels: [channel])
    }

    public func fetchSyncedSettings(keys: [String]) async throws -> [String: SyncedSettingValue] {
        syncedSettings.filter { keys.contains($0.key) }
    }

    public func setSyncedSettings(_ values: [String: String], timestamp: Int64) async throws {
        // The verified backend caps future timestamps at the current server time.
        let capped = min(timestamp, Int64(Date().timeIntervalSince1970 * 1000))
        for (key, value) in values {
            syncedSettings[key] = SyncedSettingValue(timestamp: capped, rawValue: value)
        }
    }

    public func createGroupChannel(draft: GroupChannelCreateDraft) async throws -> Channel {
        guard let validated = draft.validatedForCreate else {
            throw StoatAPIError.invalidEnvironment("Group name must be 1 to 32 characters.")
        }
        let channelID = ChannelID(rawValue: "mock-group-\(channels.count + 1)")
        var recipients = [currentUser.id]
        recipients.append(contentsOf: validated.users.filter { $0 != currentUser.id })
        let channel = Channel(
            id: channelID,
            kind: .group,
            name: validated.name,
            ownerID: currentUser.id,
            description: validated.description,
            active: true,
            recipients: recipients,
            nsfw: validated.nsfw ?? false
        )
        channels.append(channel)
        return channel
    }

    public func addGroupRecipient(channelID: ChannelID, userID: UserID) async throws {
        guard let index = channels.firstIndex(where: { $0.id == channelID }), channels[index].kind == .group else {
            throw StoatAPIError.notFound
        }
        guard users[userID]?.relationship == .friend else {
            throw StoatAPIError.forbidden
        }
        var recipients = channels[index].recipients
        guard !recipients.contains(userID) else {
            throw StoatAPIError.serverError(statusCode: 409, message: "AlreadyInGroup")
        }
        recipients.append(userID)
        channels[index].recipients = recipients
    }

    public func removeGroupRecipient(channelID: ChannelID, userID: UserID) async throws {
        guard let index = channels.firstIndex(where: { $0.id == channelID }), channels[index].kind == .group else {
            throw StoatAPIError.notFound
        }
        guard channels[index].ownerID == currentUser.id else {
            throw StoatAPIError.forbidden
        }
        guard userID != currentUser.id else {
            throw StoatAPIError.serverError(statusCode: 400, message: "CannotRemoveYourself")
        }
        var recipients = channels[index].recipients
        guard let recipientIndex = recipients.firstIndex(of: userID) else {
            throw StoatAPIError.notFound
        }
        recipients.remove(at: recipientIndex)
        channels[index].recipients = recipients
    }

    public func fetchServer(id: ServerID, includeChannels: Bool = false) async throws -> ServerFetchResponse {
        guard let server = servers.first(where: { $0.id == id }) else {
            throw StoatAPIError.notFound
        }
        let serverChannels = includeChannels ? channels.filter { $0.serverID == id } : nil
        return ServerFetchResponse(server: server, channels: serverChannels)
    }

    public func editServer(id: ServerID, draft: ServerEditDraft) async throws -> Server {
        guard let index = servers.firstIndex(where: { $0.id == id }) else {
            throw StoatAPIError.notFound
        }
        if let categories = draft.categories {
            servers[index].categories = categories
        }
        if let name = draft.name {
            servers[index].name = name
        }
        if draft.remove.contains(.description) {
            servers[index].description = nil
        } else if let description = draft.description {
            servers[index].description = description
        }
        if draft.remove.contains(.icon) {
            servers[index].icon = nil
        } else if let icon = draft.icon {
            servers[index].icon = File(id: icon, tag: UploadTag.icons.rawAPIValue, filename: "mock-server-icon.png", metadata: .image(width: 96, height: 96, thumbhash: nil, animated: nil), contentType: "image/png", size: 1024, serverID: id)
        }
        if draft.remove.contains(.banner) {
            servers[index].banner = nil
        } else if let banner = draft.banner {
            servers[index].banner = File(id: banner, tag: UploadTag.banners.rawAPIValue, filename: "mock-server-banner.png", metadata: .image(width: 960, height: 320, thumbhash: nil, animated: nil), contentType: "image/png", size: 4096, serverID: id)
        }
        return servers[index]
    }

    public func createRole(serverID: ServerID, draft: RoleCreateDraft) async throws -> RoleCreateResponse {
        guard let serverIndex = servers.firstIndex(where: { $0.id == serverID }) else {
            throw StoatAPIError.notFound
        }
        guard let validated = draft.validatedForCreate else {
            throw StoatAPIError.invalidEnvironment("Role name must be 1 to 32 characters.")
        }
        let roleID = RoleID(rawValue: "mock-role-\(servers[serverIndex].roles.count + 1)")
        let role = Role(id: roleID, name: validated.name, permissions: PermissionOverride(), rank: Int64(servers[serverIndex].roles.count + 1))
        servers[serverIndex].roles[roleID] = role
        return RoleCreateResponse(id: roleID, role: role)
    }

    public func editRole(serverID: ServerID, roleID: RoleID, draft: RoleEditDraft) async throws -> Role {
        guard let serverIndex = servers.firstIndex(where: { $0.id == serverID }),
              var role = servers[serverIndex].roles[roleID]
        else {
            throw StoatAPIError.notFound
        }
        if let name = draft.name {
            role.name = name
        }
        if draft.remove.contains(.colour) {
            role.colour = nil
        } else if let colour = draft.colour {
            role.colour = colour
        }
        if let hoist = draft.hoist {
            role.hoist = hoist
        }
        servers[serverIndex].roles[roleID] = role
        return role
    }

    public func deleteRole(serverID: ServerID, roleID: RoleID) async throws {
        guard let serverIndex = servers.firstIndex(where: { $0.id == serverID }),
              servers[serverIndex].roles[roleID] != nil
        else {
            throw StoatAPIError.notFound
        }
        servers[serverIndex].roles.removeValue(forKey: roleID)
    }

    public func fetchServerMembers(serverID: ServerID) async throws -> ServerMembersResponse {
        guard servers.contains(where: { $0.id == serverID }) else {
            throw StoatAPIError.notFound
        }
        let sortedMembers = members.values
            .filter { $0.id.serverID == serverID }
            .sorted { $0.id.userID.rawValue < $1.id.userID.rawValue }
        let memberUsers = sortedMembers.compactMap { users[$0.id.userID] }
        return ServerMembersResponse(members: sortedMembers, users: memberUsers)
    }

    public func editMember(serverID: ServerID, userID: UserID, draft: MemberEditDraft) async throws -> ServerMember {
        guard servers.contains(where: { $0.id == serverID }) else {
            throw StoatAPIError.notFound
        }
        let key = MemberCompositeKey(serverID: serverID, userID: userID)
        var member = members[key] ?? ServerMember(id: key, joinedAt: Date(timeIntervalSince1970: 1_700_000_000))
        if draft.remove.contains(.nickname) {
            member.nickname = nil
        } else if let nickname = draft.nickname {
            member.nickname = nickname
        }
        if draft.remove.contains(.avatar) {
            member.avatar = nil
        } else if let avatar = draft.avatar {
            member.avatar = File(id: avatar, tag: UploadTag.avatars.rawAPIValue, filename: "mock-member-avatar.png", metadata: .image(width: 96, height: 96, thumbhash: nil, animated: nil), contentType: "image/png", size: 1024)
        }
        if draft.remove.contains(.roles) {
            member.roles = []
        } else if let roles = draft.roles {
            member.roles = roles
        }
        if draft.remove.contains(.timeout) {
            member.timeout = nil
        } else if let timeout = draft.timeout {
            member.timeout = timeout
        }
        members[key] = member
        return member
    }

    public func kickMember(serverID: ServerID, userID: UserID) async throws {
        let key = MemberCompositeKey(serverID: serverID, userID: userID)
        guard members.removeValue(forKey: key) != nil else {
            throw StoatAPIError.notFound
        }
    }

    public func banMember(serverID: ServerID, userID: UserID, draft: BanCreateDraft) async throws -> ServerBan {
        guard servers.contains(where: { $0.id == serverID }) else {
            throw StoatAPIError.notFound
        }
        let key = MemberCompositeKey(serverID: serverID, userID: userID)
        members.removeValue(forKey: key)
        let ban = ServerBan(id: key, reason: draft.reason)
        bans[key] = ban
        return ban
    }

    public func unbanMember(serverID: ServerID, userID: UserID) async throws {
        let key = MemberCompositeKey(serverID: serverID, userID: userID)
        guard bans.removeValue(forKey: key) != nil else {
            throw StoatAPIError.notFound
        }
    }

    public func fetchServerBans(serverID: ServerID) async throws -> BanListResult {
        guard servers.contains(where: { $0.id == serverID }) else {
            throw StoatAPIError.notFound
        }
        let serverBans = bans.values.filter { $0.id.serverID == serverID }.sorted { $0.id.userID.rawValue < $1.id.userID.rawValue }
        let bannedUsers = serverBans.compactMap { ban -> BannedUser? in
            guard let user = users[ban.id.userID] else { return nil }
            return BannedUser(id: user.id, username: user.username, discriminator: user.discriminator, avatar: user.avatar)
        }
        return BanListResult(users: bannedUsers, bans: serverBans)
    }

    public func setServerRolePermissions(serverID: ServerID, roleID: RoleID, draft: ServerRolePermissionDraft) async throws -> Server {
        guard let serverIndex = servers.firstIndex(where: { $0.id == serverID }),
              var role = servers[serverIndex].roles[roleID]
        else {
            throw StoatAPIError.notFound
        }
        role.permissions = PermissionOverride(allow: draft.permissions.allow, deny: draft.permissions.deny)
        servers[serverIndex].roles[roleID] = role
        return servers[serverIndex]
    }

    public func setServerDefaultPermissions(serverID: ServerID, draft: ServerDefaultPermissionDraft) async throws -> Server {
        guard let serverIndex = servers.firstIndex(where: { $0.id == serverID }) else {
            throw StoatAPIError.notFound
        }
        servers[serverIndex].defaultPermissions = draft.permissions
        return servers[serverIndex]
    }

    public func setChannelRolePermissions(channelID: ChannelID, roleID: RoleID, draft: ServerRolePermissionDraft) async throws -> Channel {
        guard let channelIndex = channels.firstIndex(where: { $0.id == channelID }) else {
            throw StoatAPIError.notFound
        }
        channels[channelIndex].rolePermissions[roleID] = PermissionOverride(allow: draft.permissions.allow, deny: draft.permissions.deny)
        return channels[channelIndex]
    }

    public func setChannelDefaultPermissions(channelID: ChannelID, draft: ChannelDefaultPermissionDraft) async throws -> Channel {
        guard let channelIndex = channels.firstIndex(where: { $0.id == channelID }) else {
            throw StoatAPIError.notFound
        }
        switch draft {
        case let .value(permissions):
            channels[channelIndex].permissions = permissions
        case let .override(override):
            channels[channelIndex].defaultPermissions = PermissionOverride(allow: override.allow, deny: override.deny)
        }
        return channels[channelIndex]
    }

    public func createChannel(serverID: ServerID, draft: ChannelCreateDraft) async throws -> Channel {
        guard let serverIndex = servers.firstIndex(where: { $0.id == serverID }) else {
            throw StoatAPIError.notFound
        }
        guard let validated = draft.validatedForCreate else {
            throw StoatAPIError.invalidEnvironment("Channel name must be 1 to 32 characters.")
        }
        let channelID = ChannelID(rawValue: "mock-channel-\(channels.count + 1)")
        let channel = Channel(
            id: channelID,
            kind: validated.type == .voiceChannel ? .voiceChannel : .textChannel,
            serverID: serverID,
            name: validated.name,
            description: validated.description,
            permissions: [.viewChannel, .readMessageHistory, .sendMessage, .uploadFiles, .react, .manageChannel, .inviteOthers],
            nsfw: validated.nsfw ?? false
        )
        channels.append(channel)
        servers[serverIndex].channelIDs.append(channelID)
        return channel
    }

    public func editChannel(id: ChannelID, draft: ChannelEditDraft) async throws -> Channel {
        guard let index = channels.firstIndex(where: { $0.id == id }) else {
            throw StoatAPIError.notFound
        }
        if let name = draft.name {
            channels[index].name = name
        }
        if draft.remove.contains(.description) {
            channels[index].description = nil
        } else if let description = draft.description {
            channels[index].description = description
        }
        if let nsfw = draft.nsfw {
            channels[index].nsfw = nsfw
        }
        if let slowmode = draft.slowmode {
            channels[index].slowmode = slowmode == 0 ? nil : slowmode
        }
        return channels[index]
    }

    public func deleteChannel(id: ChannelID) async throws {
        guard let channel = channels.first(where: { $0.id == id }) else {
            throw StoatAPIError.notFound
        }
        channels.removeAll { $0.id == id }
        messagesByChannel[id] = nil
        if let serverID = channel.serverID,
           let serverIndex = servers.firstIndex(where: { $0.id == serverID }) {
            servers[serverIndex].channelIDs.removeAll { $0 == id }
            servers[serverIndex].categories = servers[serverIndex].categories?.map { category in
                var category = category
                category.channels.removeAll { $0 == id }
                return category
            }
        }
    }

    public func fetchServerEmojis(serverID: ServerID) async throws -> [Emoji] {
        emojis.values.filter {
            if case let .server(parentServerID) = $0.parent {
                return parentServerID == serverID
            }
            return false
        }
    }

    public func createEmoji(uploadID: FileID, draft: EmojiCreateDraft) async throws -> Emoji {
        guard let validated = draft.validated else {
            throw StoatAPIError.invalidEnvironment("Emoji name must be 1 to 32 characters.")
        }
        let emoji = Emoji(
            id: EmojiID(rawValue: uploadID.rawValue),
            parent: validated.parent,
            creatorID: currentUser.id,
            name: validated.name,
            nsfw: validated.nsfw ?? false
        )
        emojis[emoji.id] = emoji
        return emoji
    }

    public func deleteEmoji(id: EmojiID) async throws {
        guard emojis.removeValue(forKey: id) != nil else {
            throw StoatAPIError.notFound
        }
    }

    private func setPinned(_ pinned: Bool, channelID: ChannelID, messageID: MessageID) throws {
        guard var messages = messagesByChannel[channelID],
              let index = messages.firstIndex(where: { $0.id == messageID })
        else {
            throw StoatAPIError.notFound
        }
        messages[index].pinned = pinned
        messagesByChannel[channelID] = messages
    }

    private func updateRelationship(userID: UserID, status: RelationshipStatus) throws -> User {
        guard var user = users[userID] else {
            throw StoatAPIError.notFound
        }
        user.relationship = status
        users[userID] = user
        currentUser.relations.removeAll { $0.id == userID }
        if status != .none {
            currentUser.relations.append(Relationship(id: userID, status: status))
        }
        return user
    }
}
public enum TestShellData {
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
public actor StubMessageActionHandler: MessageActionHandling {
    public private(set) var sentMessages: [Message] = []
    public private(set) var editedMessages: [(ChannelID, MessageID, String)] = []
    public private(set) var deletedMessages: [(ChannelID, MessageID)] = []
    public private(set) var addedReactions: [(ChannelID, MessageID, String)] = []
    public private(set) var removedReactions: [(ChannelID, MessageID, String)] = []
    public private(set) var pinnedMessages: [(ChannelID, MessageID)] = []
    public private(set) var unpinnedMessages: [(ChannelID, MessageID)] = []
    public private(set) var typingEvents: [ClientGatewayEvent] = []

    private let currentUserID: UserID
    private var nextMessageCounter = 0
    private var sendError: (any Error & Sendable)?

    public init(currentUserID: UserID = TestShellData.currentUserID, sendError: (any Error & Sendable)? = nil) {
        self.currentUserID = currentUserID
        self.sendError = sendError
    }

    public func setSendError(_ error: (any Error & Sendable)?) {
        sendError = error
    }

    public func sendMessage(channelID: ChannelID, content: String, nonce: String?, replies: [MessageReply]? = nil, attachments: [FileID]? = nil) async throws -> Message {
        if let sendError {
            throw sendError
        }
        nextMessageCounter += 1
        let files = attachments?.map {
            File(id: $0, tag: "attachments", filename: "\($0.rawValue)", contentType: "application/octet-stream", size: 0)
        }
        let message = Message(
            id: MessageID(rawValue: Self.mockMessageID(counter: nextMessageCounter)),
            channelID: channelID,
            authorID: currentUserID,
            content: content,
            nonce: nonce,
            attachments: files,
            replies: replies?.map(\.id)
        )
        sentMessages.append(message)
        return message
    }

    public func editMessage(channelID: ChannelID, messageID: MessageID, content: String) async throws -> Message {
        editedMessages.append((channelID, messageID, content))
        return Message(id: messageID, channelID: channelID, authorID: currentUserID, content: content, editedAt: Date())
    }

    public func deleteMessage(channelID: ChannelID, messageID: MessageID) async throws {
        deletedMessages.append((channelID, messageID))
    }

    public func addReaction(channelID: ChannelID, messageID: MessageID, emoji: String) async throws {
        addedReactions.append((channelID, messageID, emoji))
    }

    public func removeReaction(channelID: ChannelID, messageID: MessageID, emoji: String) async throws {
        removedReactions.append((channelID, messageID, emoji))
    }

    public func pinMessage(channelID: ChannelID, messageID: MessageID) async throws {
        pinnedMessages.append((channelID, messageID))
    }

    public func unpinMessage(channelID: ChannelID, messageID: MessageID) async throws {
        unpinnedMessages.append((channelID, messageID))
    }

    public func beginTyping(channelID: ChannelID) async throws {
        typingEvents.append(.beginTyping(channel: channelID))
    }

    public func endTyping(channelID: ChannelID) async throws {
        typingEvents.append(.endTyping(channel: channelID))
    }

    private static func mockMessageID(counter: Int) -> String {
        let timestamp = UInt64(Date().timeIntervalSince1970 * 1000)
        let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
        var value = timestamp
        var prefix = Array(repeating: alphabet[0], count: 10)
        for index in stride(from: 9, through: 0, by: -1) {
            prefix[index] = alphabet[Int(value % 32)]
            value /= 32
        }
        return String(prefix) + String(format: "%016X", counter).suffix(16)
    }
}
public actor StubSessionManager: SessionManaging {
    public private(set) var revokeAllArguments: [Bool] = []
    public private(set) var revokedSessionIDs: [SessionID] = []
    public private(set) var renamedSessions: [(SessionID, String)] = []
    public private(set) var logoutCallCount = 0

    private var sessions: [SessionInfo]
    private let error: (any Error & Sendable)?

    public init(sessions: [SessionInfo] = [], error: (any Error & Sendable)? = nil) {
        self.sessions = sessions
        self.error = error
    }

    public func listSessions(environment: StoatAPIEnvironment, credential: StoatAuthCredential) async throws -> [SessionInfo] {
        if let error { throw error }
        return sessions
    }

    public func renameSession(id: SessionID, friendlyName: String, environment: StoatAPIEnvironment, credential: StoatAuthCredential) async throws -> SessionInfo {
        if let error { throw error }
        let renamed = SessionInfo(id: id, name: friendlyName)
        sessions.removeAll { $0.id == id }
        sessions.append(renamed)
        renamedSessions.append((id, friendlyName))
        return renamed
    }

    public func revokeSession(id: SessionID, environment: StoatAPIEnvironment, credential: StoatAuthCredential) async throws {
        if let error { throw error }
        sessions.removeAll { $0.id == id }
        revokedSessionIDs.append(id)
    }

    public func revokeAllSessions(revokeSelf: Bool, environment: StoatAPIEnvironment, credential: StoatAuthCredential) async throws {
        if let error { throw error }
        revokeAllArguments.append(revokeSelf)
        if revokeSelf {
            sessions.removeAll()
        }
    }

    public func logoutCurrentSession(environment: StoatAPIEnvironment, credential: StoatAuthCredential) async throws {
        if let error { throw error }
        logoutCallCount += 1
    }
}
public actor StubNotificationService: NotificationDelivering {
    public private(set) var deliveredEvents: [NotificationEvent] = []

    public init() {}

    public func deliver(_ event: NotificationEvent) async throws {
        deliveredEvents.append(event)
    }

    public func events() -> [NotificationEvent] {
        deliveredEvents
    }
}
public actor StubNotificationPermissionManager: NotificationPermissionManaging {
    public var currentStatus: NotificationPermissionStatus
    public private(set) var requestCount = 0

    public init(status: NotificationPermissionStatus = .notDetermined) {
        self.currentStatus = status
    }

    public func status() async -> NotificationPermissionStatus {
        currentStatus
    }

    public func requestAuthorization() async -> NotificationPermissionRequestResult {
        let before = currentStatus
        requestCount += 1
        if currentStatus == .notDetermined {
            currentStatus = .authorized
        }
        return NotificationPermissionRequestResult(
            authorizerKind: "StubNotificationPermissionManager",
            statusBefore: before,
            requestAuthorizationCalled: true,
            granted: currentStatus == .authorized,
            statusAfter: currentStatus,
            usedMockAuthorizer: true
        )
    }
}
public actor StubDockBadgeManager: DockBadgeManaging {
    public private(set) var badgeCounts: [Int] = []

    public init() {}

    public func setBadgeCount(_ count: Int) async {
        badgeCounts.append(count)
    }
}
public actor StubMessageCopier: MessageCopying {
    public private(set) var copiedValues: [String] = []

    public init() {}

    public func copy(_ value: String) async {
        copiedValues.append(value)
    }

    public func lastCopiedValue() -> String? {
        copiedValues.last
    }
}
public actor StubAttachmentUploadHandler: AttachmentUploadHandling {
    public private(set) var uploads: [ComposerAttachmentDraft] = []
    private var uploadError: (any Error & Sendable)?

    public init(uploadError: (any Error & Sendable)? = nil) {
        self.uploadError = uploadError
    }

    public func setUploadError(_ error: (any Error & Sendable)?) {
        uploadError = error
    }

    public func uploadCount() -> Int {
        uploads.count
    }

    public func upload(_ attachment: ComposerAttachmentDraft) async throws -> UploadedFile {
        if let uploadError {
            throw uploadError
        }
        uploads.append(attachment)
        return UploadedFile(id: FileID(rawValue: "mock-attachments-\(abs(attachment.filename.hashValue))"))
    }
}
public actor StubImageResourceLoader: ImageResourceLoading {
    public private(set) var calls: [ImageResourceRequest] = []
    private var result: Result<Data, any Error & Sendable>

    public init(result: Result<Data, any Error & Sendable> = .success(Data())) {
        self.result = result
    }

    public func setResult(_ result: Result<Data, any Error & Sendable>) {
        self.result = result
    }

    public func callCount() -> Int {
        calls.count
    }

    public func loadImage(_ request: ImageResourceRequest) async throws -> ImageResourceResult {
        calls.append(request)
        switch result {
        case let .success(data):
            return ImageResourceResult(request: request, contentType: "image/png", data: data)
        case let .failure(error):
            throw error
        }
    }
}
public actor StubRemoteAttachmentLoader: RemoteAttachmentLoading {
    public private(set) var calls: [(String, RemoteAttachmentLoadPurpose)] = []
    private var result: Result<RemoteAttachmentData, any Error & Sendable>

    public init(result: Result<RemoteAttachmentData, any Error & Sendable> = .success(RemoteAttachmentData(filename: "mock.txt", contentType: "text/plain", byteCount: 4, data: Data("mock".utf8)))) {
        self.result = result
    }

    public func setResult(_ result: Result<RemoteAttachmentData, any Error & Sendable>) {
        self.result = result
    }

    public func callCount() -> Int {
        calls.count
    }

    public func load(_ item: AttachmentDisplayItem, purpose: RemoteAttachmentLoadPurpose) async throws -> RemoteAttachmentData {
        calls.append((item.id, purpose))
        switch result {
        case let .success(data):
            return RemoteAttachmentData(fileID: item.fileID ?? data.fileID, filename: item.displayName, contentType: item.contentType ?? data.contentType, byteCount: item.byteCount ?? data.byteCount, data: data.data)
        case let .failure(error):
            throw error
        }
    }
}
public actor StubAttachmentSaver: AttachmentSaving {
    public private(set) var saves: [(String, Int)] = []
    public var error: (any Error & Sendable)?

    public init(error: (any Error & Sendable)? = nil) {
        self.error = error
    }

    public func save(data: Data, suggestedFilename: String) async throws {
        if let error {
            throw error
        }
        saves.append((AttachmentDisplayFormatting.safeFilename(suggestedFilename), data.count))
    }

    public func saveCount() -> Int {
        saves.count
    }
}
public actor StubAttachmentOpener: AttachmentOpening {
    public private(set) var opened: [URL] = []
    public var error: (any Error & Sendable)?

    public init(error: (any Error & Sendable)? = nil) {
        self.error = error
    }

    public func open(_ localFile: URL) async throws {
        if let error {
            throw error
        }
        guard !AttachmentSafety.isExecutableLike(localFile) else {
            throw AttachmentActionError.unsafeToOpen
        }
        opened.append(localFile)
    }

    public func openCount() -> Int {
        opened.count
    }
}

/// Plain class rather than an actor: `MainShellViewModel.joinVoiceChannel` calls `engine.events`
/// synchronously right after `await engine.connect(...)` returns, and wiring the continuation
/// without an actor hop in between means there's no race where an `emit(_:)` from a test lands
/// before the subscriber is registered.
public final class StubVoiceEngine: VoiceEngine, @unchecked Sendable {
    private let lock = NSLock()
    private var eventContinuation: AsyncStream<VoiceEngineEvent>.Continuation?
    private var audioLevelContinuation: AsyncStream<Float>.Continuation?

    public private(set) var connectCallCount = 0
    public private(set) var lastConnectURL: URL?
    public private(set) var lastConnectToken: String?
    public private(set) var disconnectCallCount = 0
    public private(set) var microphoneMutedCalls: [Bool] = []
    public private(set) var audioProcessingCalls: [(echoCancellation: Bool, noiseSuppression: Bool)] = []
    public var connectError: (any Error)?
    public var availableInputDevices: [VoiceAudioDevice]
    public var availableOutputDevices: [VoiceAudioDevice]
    public private(set) var selectedInputDeviceID: String?
    public private(set) var selectedOutputDeviceID: String?

    public init(availableInputDevices: [VoiceAudioDevice] = [], availableOutputDevices: [VoiceAudioDevice] = []) {
        self.availableInputDevices = availableInputDevices
        self.availableOutputDevices = availableOutputDevices
    }

    public var events: AsyncStream<VoiceEngineEvent> {
        AsyncStream { [weak self] continuation in
            self?.lock.lock()
            self?.eventContinuation = continuation
            self?.lock.unlock()
        }
    }

    public var localAudioLevel: AsyncStream<Float> {
        AsyncStream { [weak self] continuation in
            self?.lock.lock()
            self?.audioLevelContinuation = continuation
            self?.lock.unlock()
        }
    }

    public func connect(url: URL, token: String) async throws {
        if let connectError { throw connectError }
        connectCallCount += 1
        lastConnectURL = url
        lastConnectToken = token
    }

    public func disconnect() async {
        disconnectCallCount += 1
        finishContinuations()
    }

    // `NSLock.lock()`/`unlock()` are unavailable when called lexically inside an `async` function
    // body — hence this small synchronous helper, same shape as `LiveKitVoiceEngine`'s `emit`.
    private func finishContinuations() {
        lock.lock()
        eventContinuation?.finish()
        eventContinuation = nil
        audioLevelContinuation?.finish()
        audioLevelContinuation = nil
        lock.unlock()
    }

    public func setMicrophoneMuted(_ muted: Bool) async throws {
        microphoneMutedCalls.append(muted)
    }

    public func setAudioProcessing(echoCancellation: Bool, noiseSuppression: Bool) {
        audioProcessingCalls.append((echoCancellation, noiseSuppression))
    }

    public func selectInputDevice(id: String) { selectedInputDeviceID = id }
    public func selectOutputDevice(id: String) { selectedOutputDeviceID = id }

    /// Test helper: push an event to the active `events` subscriber, if any.
    public func emit(_ event: VoiceEngineEvent) {
        lock.lock()
        let continuation = eventContinuation
        lock.unlock()
        continuation?.yield(event)
    }
}

public actor StubMicrophonePermissionManager: MicrophonePermissionManaging {
    public var currentStatus: MicrophonePermissionStatus
    public private(set) var requestCount = 0

    public init(status: MicrophonePermissionStatus = .notDetermined) {
        self.currentStatus = status
    }

    public func status() async -> MicrophonePermissionStatus {
        currentStatus
    }

    public func requestAuthorization() async -> MicrophonePermissionRequestResult {
        let before = currentStatus
        requestCount += 1
        if currentStatus == .notDetermined {
            currentStatus = .authorized
        }
        return MicrophonePermissionRequestResult(
            statusBefore: before,
            requestAuthorizationCalled: true,
            granted: currentStatus == .authorized,
            statusAfter: currentStatus
        )
    }
}
