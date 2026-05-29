import Foundation
import StoatModels

public actor MockStoatAPIClient: StoatAPIClient {
    private var currentUser: User
    private var users: [UserID: User]
    private var servers: [Server]
    private var channels: [Channel]
    private var messagesByChannel: [ChannelID: [Message]]

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
                roles: [coreRole.id: coreRole],
                defaultPermissions: memberPermissions,
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

    public func fetchServers() async throws -> [Server] {
        servers
    }

    public func fetchChannels() async throws -> [Channel] {
        channels
    }

    public func fetchChannel(id: ChannelID) async throws -> Channel {
        guard let channel = channels.first(where: { $0.id == id }) else {
            throw StoatAPIError.notFound
        }
        return channel
    }

    public func fetchMessages(channelID: ChannelID, before: MessageID?, after: MessageID?, limit: Int?) async throws -> [Message] {
        var messages = messagesByChannel[channelID] ?? []
        if let before, let index = messages.firstIndex(where: { $0.id == before }) {
            messages = Array(messages[..<index])
        }
        if let after, let index = messages.firstIndex(where: { $0.id == after }) {
            messages = Array(messages[messages.index(after: index)...])
        }
        if let limit, limit < messages.count {
            messages = Array(messages.prefix(limit))
        }
        return messages
    }

    public func sendMessage(channelID: ChannelID, draft: MessageDraft) async throws -> Message {
        let message = Message(
            id: MessageID(rawValue: "01HX0000000000000000\(String(format: "%06d", Int.random(in: 5000...9999)))"),
            channelID: channelID,
            authorID: currentUser.id,
            content: draft.content,
            nonce: draft.nonce,
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

    private func setPinned(_ pinned: Bool, channelID: ChannelID, messageID: MessageID) throws {
        guard var messages = messagesByChannel[channelID],
              let index = messages.firstIndex(where: { $0.id == messageID })
        else {
            throw StoatAPIError.notFound
        }
        messages[index].pinned = pinned
        messagesByChannel[channelID] = messages
    }
}

