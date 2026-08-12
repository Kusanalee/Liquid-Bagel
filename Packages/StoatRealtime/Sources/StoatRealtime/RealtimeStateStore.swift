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

public struct RealtimeSnapshotChangeSet: Hashable, Sendable {
    public var isFullReplacement: Bool
    public var userIDs: Set<UserID>
    public var serverIDs: Set<ServerID>
    public var channelIDs: Set<ChannelID>
    public var messageChannelIDs: Set<ChannelID>
    public var insertedMessages: [Message]
    public var deletedMessageIDsByChannelID: [ChannelID: Set<MessageID>]
    public var memberKeys: Set<ServerMemberKey>
    public var removedMemberKeys: Set<ServerMemberKey>
    public var emojiIDs: Set<EmojiID>
    public var unreadChannelIDs: Set<ChannelID>
    public var typingChannelIDs: Set<ChannelID>
    public var userSettingsChanged: Bool
    public var policyChangesChanged: Bool

    public init(
        isFullReplacement: Bool = false,
        userIDs: Set<UserID> = [],
        serverIDs: Set<ServerID> = [],
        channelIDs: Set<ChannelID> = [],
        messageChannelIDs: Set<ChannelID> = [],
        insertedMessages: [Message] = [],
        deletedMessageIDsByChannelID: [ChannelID: Set<MessageID>] = [:],
        memberKeys: Set<ServerMemberKey> = [],
        removedMemberKeys: Set<ServerMemberKey> = [],
        emojiIDs: Set<EmojiID> = [],
        unreadChannelIDs: Set<ChannelID> = [],
        typingChannelIDs: Set<ChannelID> = [],
        userSettingsChanged: Bool = false,
        policyChangesChanged: Bool = false
    ) {
        self.isFullReplacement = isFullReplacement
        self.userIDs = userIDs
        self.serverIDs = serverIDs
        self.channelIDs = channelIDs
        self.messageChannelIDs = messageChannelIDs
        self.insertedMessages = insertedMessages
        self.deletedMessageIDsByChannelID = deletedMessageIDsByChannelID
        self.memberKeys = memberKeys
        self.removedMemberKeys = removedMemberKeys
        self.emojiIDs = emojiIDs
        self.unreadChannelIDs = unreadChannelIDs
        self.typingChannelIDs = typingChannelIDs
        self.userSettingsChanged = userSettingsChanged
        self.policyChangesChanged = policyChangesChanged
    }

    public var affectsShellPresentation: Bool {
        isFullReplacement
            || !userIDs.isEmpty
            || !serverIDs.isEmpty
            || !channelIDs.isEmpty
            || !memberKeys.isEmpty
            || !removedMemberKeys.isEmpty
            || !unreadChannelIDs.isEmpty
    }

    public var affectsModeration: Bool {
        isFullReplacement
            || !serverIDs.isEmpty
            || !channelIDs.isEmpty
            || !memberKeys.isEmpty
            || !removedMemberKeys.isEmpty
    }

    public var isEmpty: Bool {
        !isFullReplacement
            && userIDs.isEmpty
            && serverIDs.isEmpty
            && channelIDs.isEmpty
            && messageChannelIDs.isEmpty
            && insertedMessages.isEmpty
            && deletedMessageIDsByChannelID.isEmpty
            && memberKeys.isEmpty
            && removedMemberKeys.isEmpty
            && emojiIDs.isEmpty
            && unreadChannelIDs.isEmpty
            && typingChannelIDs.isEmpty
            && !userSettingsChanged
            && !policyChangesChanged
    }

    public mutating func formUnion(_ other: RealtimeSnapshotChangeSet) {
        isFullReplacement = isFullReplacement || other.isFullReplacement
        userIDs.formUnion(other.userIDs)
        serverIDs.formUnion(other.serverIDs)
        channelIDs.formUnion(other.channelIDs)
        messageChannelIDs.formUnion(other.messageChannelIDs)
        insertedMessages.append(contentsOf: other.insertedMessages)
        for (channelID, messageIDs) in other.deletedMessageIDsByChannelID {
            deletedMessageIDsByChannelID[channelID, default: []].formUnion(messageIDs)
        }
        memberKeys.formUnion(other.memberKeys)
        removedMemberKeys.formUnion(other.removedMemberKeys)
        emojiIDs.formUnion(other.emojiIDs)
        unreadChannelIDs.formUnion(other.unreadChannelIDs)
        typingChannelIDs.formUnion(other.typingChannelIDs)
        userSettingsChanged = userSettingsChanged || other.userSettingsChanged
        policyChangesChanged = policyChangesChanged || other.policyChangesChanged
    }
}

public struct RealtimeSnapshotUpdate: Hashable, Sendable {
    public var snapshot: RealtimeSnapshot
    public var changes: RealtimeSnapshotChangeSet

    public init(snapshot: RealtimeSnapshot, changes: RealtimeSnapshotChangeSet) {
        self.snapshot = snapshot
        self.changes = changes
    }

    public func coalescing(previous: RealtimeSnapshotUpdate) -> RealtimeSnapshotUpdate {
        var changes = previous.changes
        changes.formUnion(self.changes)
        var seenInsertedMessageIDs: Set<MessageID> = []
        changes.insertedMessages = changes.insertedMessages.filter { message in
            guard snapshot.messagesByChannelID[message.channelID]?.contains(where: { $0.id == message.id }) == true else {
                return false
            }
            return seenInsertedMessageIDs.insert(message.id).inserted
        }
        for (channelID, deletedMessageIDs) in changes.deletedMessageIDsByChannelID {
            let liveMessageIDs = Set((snapshot.messagesByChannelID[channelID] ?? []).map(\.id))
            changes.deletedMessageIDsByChannelID[channelID] = deletedMessageIDs.subtracting(liveMessageIDs)
        }
        changes.deletedMessageIDsByChannelID = changes.deletedMessageIDsByChannelID.filter { !$0.value.isEmpty }
        return RealtimeSnapshotUpdate(snapshot: snapshot, changes: changes)
    }
}

public actor RealtimeStateStore {
    public private(set) var currentSnapshot: RealtimeSnapshot
    public let messageCapPerChannel: Int
    private let snapshotHub = CoalescingStreamHub<RealtimeSnapshotUpdate> { previous, latest in
        latest.coalescing(previous: previous)
    }

    public nonisolated var updates: AsyncStream<RealtimeSnapshotUpdate> {
        snapshotHub.stream()
    }

    public nonisolated var coalescedUpdateCount: Int {
        snapshotHub.coalescedCount
    }

    public init(initialSnapshot: RealtimeSnapshot = RealtimeSnapshot(), messageCapPerChannel: Int = 200) {
        currentSnapshot = initialSnapshot
        self.messageCapPerChannel = messageCapPerChannel
    }

    public func snapshot() -> RealtimeSnapshot {
        currentSnapshot
    }

    @discardableResult
    public func apply(_ event: StoatGatewayEvent) -> RealtimeSnapshotUpdate {
        var changes = RealtimeSnapshotChangeSet()
        apply(event, changes: &changes)
        let update = RealtimeSnapshotUpdate(snapshot: currentSnapshot, changes: changes)
        if !changes.isEmpty {
            snapshotHub.yield(update)
        }
        return update
    }

    private func apply(_ event: StoatGatewayEvent, changes: inout RealtimeSnapshotChangeSet) {
        switch event {
        case let .bulk(events):
            for event in events {
                apply(event, changes: &changes)
            }
            return
        case let .ready(payload):
            applyReady(payload)
            changes.isFullReplacement = true
            changes.userIDs.formUnion(currentSnapshot.usersByID.keys)
            changes.serverIDs.formUnion(currentSnapshot.serversByID.keys)
            changes.channelIDs.formUnion(currentSnapshot.channelsByID.keys)
            changes.memberKeys.formUnion(currentSnapshot.membersByServerAndUserID.keys)
            changes.emojiIDs.formUnion(currentSnapshot.emojisByID.keys)
            changes.unreadChannelIDs.formUnion(currentSnapshot.unreadsByChannelID.keys)
            changes.userSettingsChanged = true
            changes.policyChangesChanged = true
        case let .message(message):
            insert(message)
            changes.messageChannelIDs.insert(message.channelID)
            changes.insertedMessages.append(message)
            if let user = message.user {
                currentSnapshot.usersByID[user.id] = user
                changes.userIDs.insert(user.id)
            }
            if let member = message.member {
                let key = ServerMemberKey(member.id)
                currentSnapshot.membersByServerAndUserID[key] = member
                changes.memberKeys.insert(key)
            }
        case let .messageUpdate(event):
            updateMessage(event)
            changes.messageChannelIDs.insert(event.channelID)
        case let .messageAppend(event):
            appendMessage(event)
            changes.messageChannelIDs.insert(event.channelID)
        case let .messageDelete(event):
            currentSnapshot.messagesByChannelID[event.channelID]?.removeAll { $0.id == event.id }
            changes.messageChannelIDs.insert(event.channelID)
            changes.deletedMessageIDsByChannelID[event.channelID, default: []].insert(event.id)
        case let .bulkMessageDelete(event):
            currentSnapshot.messagesByChannelID[event.channelID]?.removeAll { event.ids.contains($0.id) }
            changes.messageChannelIDs.insert(event.channelID)
            changes.deletedMessageIDsByChannelID[event.channelID, default: []].formUnion(event.ids)
        case let .messageReact(event):
            mutateMessage(event.channelID, event.id) { message in
                var users = message.reactions[event.emojiID] ?? []
                users.insert(event.userID)
                message.reactions[event.emojiID] = users
            }
            changes.messageChannelIDs.insert(event.channelID)
        case let .messageUnreact(event):
            mutateMessage(event.channelID, event.id) { message in
                message.reactions[event.emojiID]?.remove(event.userID)
                if message.reactions[event.emojiID]?.isEmpty == true {
                    message.reactions.removeValue(forKey: event.emojiID)
                }
            }
            changes.messageChannelIDs.insert(event.channelID)
        case let .messageRemoveReaction(event):
            mutateMessage(event.channelID, event.id) { message in
                message.reactions.removeValue(forKey: event.emojiID)
            }
            changes.messageChannelIDs.insert(event.channelID)
        case let .channelCreate(channel):
            currentSnapshot.channelsByID[channel.id] = channel
            changes.channelIDs.insert(channel.id)
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
            changes.channelIDs.insert(event.id)
        case let .channelDelete(event):
            currentSnapshot.channelsByID.removeValue(forKey: event.id)
            currentSnapshot.messagesByChannelID.removeValue(forKey: event.id)
            currentSnapshot.typingUsersByChannelID.removeValue(forKey: event.id)
            changes.channelIDs.insert(event.id)
            changes.messageChannelIDs.insert(event.id)
            changes.typingChannelIDs.insert(event.id)
        case let .channelGroupJoin(event):
            if var channel = currentSnapshot.channelsByID[event.id], !channel.recipients.contains(event.userID) {
                channel.recipients.append(event.userID)
                currentSnapshot.channelsByID[event.id] = channel
            }
            changes.channelIDs.insert(event.id)
        case let .channelGroupLeave(event):
            if var channel = currentSnapshot.channelsByID[event.id] {
                channel.recipients.removeAll { $0 == event.userID }
                currentSnapshot.channelsByID[event.id] = channel
            }
            changes.channelIDs.insert(event.id)
        case let .channelStartTyping(event):
            currentSnapshot.typingUsersByChannelID[event.id, default: []].insert(event.userID)
            changes.typingChannelIDs.insert(event.id)
        case let .channelStopTyping(event):
            currentSnapshot.typingUsersByChannelID[event.id]?.remove(event.userID)
            changes.typingChannelIDs.insert(event.id)
        case let .channelAck(event):
            currentSnapshot.unreadsByChannelID[event.id] = ChannelUnread(
                id: ChannelCompositeKey(channelID: event.id, userID: event.userID),
                lastMessageID: event.messageID,
                mentions: []
            )
            changes.unreadChannelIDs.insert(event.id)
        case let .serverCreate(event):
            currentSnapshot.serversByID[event.server.id] = event.server
            changes.serverIDs.insert(event.server.id)
            for channel in event.channels {
                currentSnapshot.channelsByID[channel.id] = channel
                changes.channelIDs.insert(channel.id)
            }
            for emoji in event.emojis {
                currentSnapshot.emojisByID[emoji.id] = emoji
                changes.emojiIDs.insert(emoji.id)
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
            changes.serverIDs.insert(event.id)
        case let .serverDelete(event):
            let removedChannelIDs = currentSnapshot.channelsByID.values
                .filter { $0.serverID == event.id }
                .map(\.id)
            let removedMemberKeys = currentSnapshot.membersByServerAndUserID.keys
                .filter { $0.serverID == event.id }
            currentSnapshot.serversByID.removeValue(forKey: event.id)
            currentSnapshot.channelsByID = currentSnapshot.channelsByID.filter { $0.value.serverID != event.id }
            currentSnapshot.membersByServerAndUserID = currentSnapshot.membersByServerAndUserID.filter { $0.key.serverID != event.id }
            changes.serverIDs.insert(event.id)
            changes.channelIDs.formUnion(removedChannelIDs)
            changes.removedMemberKeys.formUnion(removedMemberKeys)
        case let .serverMemberUpdate(event):
            let key = ServerMemberKey(event.id)
            guard var member = currentSnapshot.membersByServerAndUserID[key] else { break }
            if let nickname = event.data.nickname { member.nickname = nickname }
            if let avatar = event.data.avatar { member.avatar = avatar }
            if let roles = event.data.roles { member.roles = roles }
            if let timeout = event.data.timeout { member.timeout = timeout }
            if let canPublish = event.data.canPublish { member.canPublish = canPublish }
            if let canReceive = event.data.canReceive { member.canReceive = canReceive }
            if let voiceChannel = event.data.voiceChannel { member.voiceChannel = voiceChannel }
            for field in event.clear {
                switch field {
                case "Nickname": member.nickname = nil
                case "Avatar": member.avatar = nil
                case "Roles": member.roles = []
                case "Timeout": member.timeout = nil
                case "CanPublish": member.canPublish = true
                case "CanReceive": member.canReceive = true
                case "VoiceChannel": member.voiceChannel = nil
                default: break
                }
            }
            currentSnapshot.membersByServerAndUserID[key] = member
            changes.memberKeys.insert(key)
        case let .serverMemberJoin(event):
            if let member = event.member {
                let key = ServerMemberKey(member.id)
                currentSnapshot.membersByServerAndUserID[key] = member
                changes.memberKeys.insert(key)
            }
        case let .serverMemberLeave(event):
            let key = ServerMemberKey(serverID: event.id, userID: event.userID)
            currentSnapshot.membersByServerAndUserID.removeValue(forKey: key)
            changes.removedMemberKeys.insert(key)
        case let .serverRoleUpdate(event):
            guard var server = currentSnapshot.serversByID[event.id] else { break }
            if var role = server.roles[event.roleID], let name = event.data.name {
                role.name = name
                server.roles[event.roleID] = role
            }
            currentSnapshot.serversByID[event.id] = server
            changes.serverIDs.insert(event.id)
        case let .serverRoleDelete(event):
            if var server = currentSnapshot.serversByID[event.id] {
                server.roles.removeValue(forKey: event.roleID)
                currentSnapshot.serversByID[event.id] = server
            }
            changes.serverIDs.insert(event.id)
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
            changes.userIDs.insert(event.id)
        case let .userRelationship(event):
            var user = event.user
            if let status = event.status {
                user.relationship = status
            }
            currentSnapshot.usersByID[user.id] = user
            changes.userIDs.insert(user.id)
        case let .userPresence(event):
            if var user = currentSnapshot.usersByID[event.id] {
                user.online = event.online
                currentSnapshot.usersByID[event.id] = user
            }
            changes.userIDs.insert(event.id)
        case let .userSettingsUpdate(event):
            for (key, value) in event.update.values {
                currentSnapshot.userSettings.values[key] = value
            }
            changes.userSettingsChanged = true
        case let .userPlatformWipe(event):
            currentSnapshot.usersByID.removeValue(forKey: event.userID)
            changes.userIDs.insert(event.userID)
            for channelID in currentSnapshot.messagesByChannelID.keys {
                currentSnapshot.messagesByChannelID[channelID]?.removeAll { $0.authorID == event.userID }
                changes.messageChannelIDs.insert(channelID)
            }
            currentSnapshot.typingUsersByChannelID = currentSnapshot.typingUsersByChannelID.mapValues { users in
                var users = users
                users.remove(event.userID)
                return users
            }
            changes.typingChannelIDs.formUnion(currentSnapshot.typingUsersByChannelID.keys)
        case let .emojiCreate(emoji):
            currentSnapshot.emojisByID[emoji.id] = emoji
            changes.emojiIDs.insert(emoji.id)
        case let .emojiUpdate(event):
            if var emoji = currentSnapshot.emojisByID[event.id], let name = event.data.name {
                emoji.name = name
                currentSnapshot.emojisByID[event.id] = emoji
            }
            changes.emojiIDs.insert(event.id)
        case let .emojiDelete(event):
            currentSnapshot.emojisByID.removeValue(forKey: event.id)
            changes.emojiIDs.insert(event.id)
        default:
            break
        }
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
