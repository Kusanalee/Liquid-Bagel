import Foundation
import StoatModels

public struct ServerMemberKey: Codable, Hashable, Sendable {
    public var serverID: ServerID
    public var userID: UserID

    public init(serverID: ServerID, userID: UserID) {
        self.serverID = serverID
        self.userID = userID
    }

    public init(_ key: MemberCompositeKey) {
        self.serverID = key.serverID
        self.userID = key.userID
    }
}

public struct RealtimeSnapshot: Hashable, Sendable {
    public var usersByID: [UserID: User]
    public var serversByID: [ServerID: Server]
    public var channelsByID: [ChannelID: Channel]
    public var messagesByChannelID: [ChannelID: [Message]]
    public var membersByServerAndUserID: [ServerMemberKey: ServerMember]
    public var emojisByID: [EmojiID: Emoji]
    public var unreadsByChannelID: [ChannelID: ChannelUnread]
    public var typingUsersByChannelID: [ChannelID: Set<UserID>]
    public var userSettings: UserSettings
    public var policyChanges: [PolicyChange]

    public init(
        usersByID: [UserID: User] = [:],
        serversByID: [ServerID: Server] = [:],
        channelsByID: [ChannelID: Channel] = [:],
        messagesByChannelID: [ChannelID: [Message]] = [:],
        membersByServerAndUserID: [ServerMemberKey: ServerMember] = [:],
        emojisByID: [EmojiID: Emoji] = [:],
        unreadsByChannelID: [ChannelID: ChannelUnread] = [:],
        typingUsersByChannelID: [ChannelID: Set<UserID>] = [:],
        userSettings: UserSettings = UserSettings(),
        policyChanges: [PolicyChange] = []
    ) {
        self.usersByID = usersByID
        self.serversByID = serversByID
        self.channelsByID = channelsByID
        self.messagesByChannelID = messagesByChannelID
        self.membersByServerAndUserID = membersByServerAndUserID
        self.emojisByID = emojisByID
        self.unreadsByChannelID = unreadsByChannelID
        self.typingUsersByChannelID = typingUsersByChannelID
        self.userSettings = userSettings
        self.policyChanges = policyChanges
    }
}

public actor RealtimeStateStore {
    public private(set) var currentSnapshot: RealtimeSnapshot
    public let messageCapPerChannel: Int
    private let snapshotHub = StreamHub<RealtimeSnapshot>()

    public nonisolated var snapshots: AsyncStream<RealtimeSnapshot> {
        snapshotHub.stream()
    }

    public init(initialSnapshot: RealtimeSnapshot = RealtimeSnapshot(), messageCapPerChannel: Int = 200) {
        currentSnapshot = initialSnapshot
        self.messageCapPerChannel = messageCapPerChannel
    }

    public func snapshot() -> RealtimeSnapshot {
        currentSnapshot
    }

    public func apply(_ event: StoatGatewayEvent) async {
        switch event {
        case let .bulk(events):
            for event in events {
                await apply(event)
            }
            return
        case let .ready(payload):
            applyReady(payload)
        case let .message(message):
            insert(message)
            if let user = message.user {
                currentSnapshot.usersByID[user.id] = user
            }
            if let member = message.member {
                currentSnapshot.membersByServerAndUserID[ServerMemberKey(member.id)] = member
            }
        case let .messageUpdate(event):
            updateMessage(event)
        case let .messageAppend(event):
            appendMessage(event)
        case let .messageDelete(event):
            currentSnapshot.messagesByChannelID[event.channelID]?.removeAll { $0.id == event.id }
        case let .bulkMessageDelete(event):
            currentSnapshot.messagesByChannelID[event.channelID]?.removeAll { event.ids.contains($0.id) }
        case let .messageReact(event):
            mutateMessage(event.channelID, event.id) { message in
                var users = message.reactions[event.emojiID] ?? []
                users.insert(event.userID)
                message.reactions[event.emojiID] = users
            }
        case let .messageUnreact(event):
            mutateMessage(event.channelID, event.id) { message in
                message.reactions[event.emojiID]?.remove(event.userID)
                if message.reactions[event.emojiID]?.isEmpty == true {
                    message.reactions.removeValue(forKey: event.emojiID)
                }
            }
        case let .messageRemoveReaction(event):
            mutateMessage(event.channelID, event.id) { message in
                message.reactions.removeValue(forKey: event.emojiID)
            }
        case let .channelCreate(channel):
            currentSnapshot.channelsByID[channel.id] = channel
        case let .channelUpdate(event):
            guard var channel = currentSnapshot.channelsByID[event.id] else { break }
            if let name = event.data.name { channel.name = name }
            if let description = event.data.description { channel.description = description }
            if let lastMessageID = event.data.lastMessageID { channel.lastMessageID = lastMessageID }
            for field in event.clear {
                switch field {
                case "Description": channel.description = nil
                default: break
                }
            }
            currentSnapshot.channelsByID[event.id] = channel
        case let .channelDelete(event):
            currentSnapshot.channelsByID.removeValue(forKey: event.id)
            currentSnapshot.messagesByChannelID.removeValue(forKey: event.id)
            currentSnapshot.typingUsersByChannelID.removeValue(forKey: event.id)
        case let .channelGroupJoin(event):
            if var channel = currentSnapshot.channelsByID[event.id], !channel.recipients.contains(event.userID) {
                channel.recipients.append(event.userID)
                currentSnapshot.channelsByID[event.id] = channel
            }
        case let .channelGroupLeave(event):
            if var channel = currentSnapshot.channelsByID[event.id] {
                channel.recipients.removeAll { $0 == event.userID }
                currentSnapshot.channelsByID[event.id] = channel
            }
        case let .channelStartTyping(event):
            currentSnapshot.typingUsersByChannelID[event.id, default: []].insert(event.userID)
        case let .channelStopTyping(event):
            currentSnapshot.typingUsersByChannelID[event.id]?.remove(event.userID)
        case let .channelAck(event):
            currentSnapshot.unreadsByChannelID[event.id] = ChannelUnread(
                id: ChannelCompositeKey(channelID: event.id, userID: event.userID),
                lastMessageID: event.messageID,
                mentions: []
            )
        case let .serverCreate(event):
            currentSnapshot.serversByID[event.server.id] = event.server
            for channel in event.channels {
                currentSnapshot.channelsByID[channel.id] = channel
            }
            for emoji in event.emojis {
                currentSnapshot.emojisByID[emoji.id] = emoji
            }
        case let .serverUpdate(event):
            guard var server = currentSnapshot.serversByID[event.id] else { break }
            if let name = event.data.name { server.name = name }
            if let description = event.data.description { server.description = description }
            for field in event.clear {
                switch field {
                case "Description": server.description = nil
                default: break
                }
            }
            currentSnapshot.serversByID[event.id] = server
        case let .serverDelete(event):
            currentSnapshot.serversByID.removeValue(forKey: event.id)
            currentSnapshot.channelsByID = currentSnapshot.channelsByID.filter { $0.value.serverID != event.id }
            currentSnapshot.membersByServerAndUserID = currentSnapshot.membersByServerAndUserID.filter { $0.key.serverID != event.id }
        case let .serverMemberUpdate(event):
            let key = ServerMemberKey(event.id)
            guard var member = currentSnapshot.membersByServerAndUserID[key] else { break }
            if let nickname = event.data.nickname { member.nickname = nickname }
            if let avatar = event.data.avatar { member.avatar = avatar }
            if let roles = event.data.roles { member.roles = roles }
            if let timeout = event.data.timeout { member.timeout = timeout }
            for field in event.clear {
                switch field {
                case "Nickname": member.nickname = nil
                case "Avatar": member.avatar = nil
                case "Roles": member.roles = []
                case "Timeout": member.timeout = nil
                default: break
                }
            }
            currentSnapshot.membersByServerAndUserID[key] = member
        case let .serverMemberJoin(event):
            if let member = event.member {
                currentSnapshot.membersByServerAndUserID[ServerMemberKey(member.id)] = member
            }
        case let .serverMemberLeave(event):
            currentSnapshot.membersByServerAndUserID.removeValue(forKey: ServerMemberKey(serverID: event.id, userID: event.userID))
        case let .serverRoleUpdate(event):
            guard var server = currentSnapshot.serversByID[event.id] else { break }
            if var role = server.roles[event.roleID], let name = event.data.name {
                role.name = name
                server.roles[event.roleID] = role
            }
            currentSnapshot.serversByID[event.id] = server
        case let .serverRoleDelete(event):
            if var server = currentSnapshot.serversByID[event.id] {
                server.roles.removeValue(forKey: event.roleID)
                currentSnapshot.serversByID[event.id] = server
            }
        case let .userUpdate(event):
            guard var user = currentSnapshot.usersByID[event.id] else { break }
            if let username = event.data.username { user.username = username }
            if let displayName = event.data.displayName { user.displayName = displayName }
            if let status = event.data.status { user.status = status }
            if let relationship = event.data.relationship { user.relationship = relationship }
            if let online = event.data.online { user.online = online }
            if let flags = event.data.flags { user.flags = flags }
            if let badges = event.data.badges { user.badges = badges }
            for field in event.clear {
                switch field {
                case "StatusPresence": user.status?.presence = nil
                case "StatusText": user.status?.text = nil
                case "Avatar": user.avatar = nil
                default: break
                }
            }
            currentSnapshot.usersByID[event.id] = user
        case let .userRelationship(event):
            var user = event.user
            if let status = event.status {
                user.relationship = status
            }
            currentSnapshot.usersByID[user.id] = user
        case let .userPresence(event):
            if var user = currentSnapshot.usersByID[event.id] {
                user.online = event.online
                currentSnapshot.usersByID[event.id] = user
            }
        case let .userSettingsUpdate(event):
            for (key, value) in event.update.values {
                currentSnapshot.userSettings.values[key] = value
            }
        case let .userPlatformWipe(event):
            currentSnapshot.usersByID.removeValue(forKey: event.userID)
            for channelID in currentSnapshot.messagesByChannelID.keys {
                currentSnapshot.messagesByChannelID[channelID]?.removeAll { $0.authorID == event.userID }
            }
            currentSnapshot.typingUsersByChannelID = currentSnapshot.typingUsersByChannelID.mapValues { users in
                var users = users
                users.remove(event.userID)
                return users
            }
        case let .emojiCreate(emoji):
            currentSnapshot.emojisByID[emoji.id] = emoji
        case let .emojiUpdate(event):
            if var emoji = currentSnapshot.emojisByID[event.id], let name = event.data.name {
                emoji.name = name
                currentSnapshot.emojisByID[event.id] = emoji
            }
        case let .emojiDelete(event):
            currentSnapshot.emojisByID.removeValue(forKey: event.id)
        default:
            break
        }
        snapshotHub.yield(currentSnapshot)
    }

    private func applyReady(_ payload: ReadyPayload) {
        if let users = payload.users {
            currentSnapshot.usersByID = keyedByLastValue(users) { $0.id }
        }
        if let servers = payload.servers {
            currentSnapshot.serversByID = keyedByLastValue(servers) { $0.id }
        }
        if let channels = payload.channels {
            currentSnapshot.channelsByID = keyedByLastValue(channels) { $0.id }
        }
        if let members = payload.members {
            currentSnapshot.membersByServerAndUserID = keyedByLastValue(members) { ServerMemberKey($0.id) }
        }
        if let emojis = payload.emojis {
            currentSnapshot.emojisByID = keyedByLastValue(emojis) { $0.id }
        }
        if let unreads = payload.channelUnreads {
            currentSnapshot.unreadsByChannelID = keyedByLastValue(unreads) { $0.id.channelID }
        }
        if let settings = payload.userSettings {
            currentSnapshot.userSettings = settings
        }
        if let policyChanges = payload.policyChanges {
            currentSnapshot.policyChanges = policyChanges
        }
    }

    private func keyedByLastValue<Element, Key: Hashable>(_ values: [Element], key: (Element) -> Key) -> [Key: Element] {
        var result: [Key: Element] = [:]
        for value in values {
            result[key(value)] = value
        }
        return result
    }

    private func insert(_ message: Message) {
        var messages = currentSnapshot.messagesByChannelID[message.channelID, default: []]
        messages.removeAll { $0.id == message.id }
        messages.append(message)
        if messages.count > messageCapPerChannel {
            messages.removeFirst(messages.count - messageCapPerChannel)
        }
        currentSnapshot.messagesByChannelID[message.channelID] = messages
        if var channel = currentSnapshot.channelsByID[message.channelID] {
            channel.lastMessageID = message.id
            currentSnapshot.channelsByID[message.channelID] = channel
        }
    }

    private func updateMessage(_ event: MessageUpdateEvent) {
        mutateMessage(event.channelID, event.id) { message in
            if let content = event.data.content { message.content = content }
            if let editedAt = event.data.editedAt { message.editedAt = editedAt }
            if let embeds = event.data.embeds { message.embeds = embeds }
            if let pinned = event.data.pinned { message.pinned = pinned }
            if let reactions = event.data.reactions { message.reactions = reactions }
            for field in event.clear {
                switch field {
                case "Content": message.content = nil
                case "Embeds": message.embeds = nil
                default: break
                }
            }
        }
    }

    private func appendMessage(_ event: MessageAppendEvent) {
        mutateMessage(event.channelID, event.id) { message in
            if let embeds = event.append.embeds {
                message.embeds = (message.embeds ?? []) + embeds
            }
        }
    }

    private func mutateMessage(_ channelID: ChannelID, _ messageID: MessageID, _ mutation: (inout Message) -> Void) {
        guard var messages = currentSnapshot.messagesByChannelID[channelID],
              let index = messages.firstIndex(where: { $0.id == messageID })
        else {
            return
        }
        mutation(&messages[index])
        currentSnapshot.messagesByChannelID[channelID] = messages
    }
}
