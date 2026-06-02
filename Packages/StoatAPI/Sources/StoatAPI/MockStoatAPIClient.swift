import Foundation
import StoatModels

public actor MockStoatAPIClient: StoatAPIClient {
    private var currentUser: User
    private var users: [UserID: User]
    private var servers: [Server]
    private var channels: [Channel]
    private var messagesByChannel: [ChannelID: [Message]]
    private var invites: [InviteID: Invite]

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

    public func fetchUserProfile(userID: UserID) async throws -> UserProfile {
        guard let user = users[userID] else {
            throw StoatAPIError.notFound
        }
        return UserProfile(content: "Mock profile for \(user.displayName ?? user.username).")
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
        return servers[index]
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
