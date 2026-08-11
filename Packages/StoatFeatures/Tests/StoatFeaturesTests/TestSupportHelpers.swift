//  Split from StoatFeaturesTests.swift (Phase 74). Behavior unchanged.
//  `private` widened to internal so the split test files can share these.

import StoatModels
import StoatAPI
import StoatPersistence
import StoatRealtime
import StoatUI
import Observation
import SwiftUI
import XCTest
@testable import StoatFeatures

func makeTemporaryAttachment(name: String, contents: Data) throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LiquidBagelPhase15Tests", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent(UUID().uuidString + "-" + name)
    try contents.write(to: url)
    return url
}

final class LockedInvocationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int { lock.withLock { count } }

    func increment() {
        lock.withLock { count += 1 }
    }
}

final class TestStreamHub<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]

    func stream() -> AsyncStream<Element> {
        AsyncStream { continuation in
            let id = UUID()
            lock.lock()
            continuations[id] = continuation
            lock.unlock()
            continuation.onTermination = { [weak self] _ in
                self?.lock.lock()
                self?.continuations.removeValue(forKey: id)
                self?.lock.unlock()
            }
        }
    }

    func yield(_ value: Element) {
        lock.lock()
        let continuations = Array(continuations.values)
        lock.unlock()
        continuations.forEach { $0.yield(value) }
    }
}

final class MutableSnapshotSource: ShellSnapshotSource, @unchecked Sendable {
    private let lock = NSLock()
    private let hub = TestStreamHub<RealtimeSnapshotUpdate>()
    private var snapshot: RealtimeSnapshot

    init(snapshot: RealtimeSnapshot) {
        self.snapshot = snapshot
    }

    var updates: AsyncStream<RealtimeSnapshotUpdate> {
        hub.stream()
    }

    func currentSnapshot() async -> RealtimeSnapshot {
        lock.withLock { snapshot }
    }

    func yield(_ snapshot: RealtimeSnapshot) {
        lock.withLock {
            self.snapshot = snapshot
        }
        hub.yield(
            RealtimeSnapshotUpdate(
                snapshot: snapshot,
                changes: RealtimeSnapshotChangeSet(isFullReplacement: true)
            )
        )
    }
}

final class Phase55TestClock: @unchecked Sendable {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}

actor Phase68DiagnosticsBuildGate {
    private(set) var invocationCount = 0
    private var firstBuildContinuation: CheckedContinuation<Void, Never>?

    func prepare(_ input: Phase68VisibleIdentityDiagnosticsInput) async -> VisibleIdentityDiagnostics {
        _ = input
        invocationCount += 1
        let invocation = invocationCount
        if invocation == 1 {
            await withCheckedContinuation { continuation in
                firstBuildContinuation = continuation
            }
        }
        return VisibleIdentityDiagnostics(unresolvedVisibleUserCount: invocation)
    }

    func releaseFirstBuild() {
        firstBuildContinuation?.resume()
        firstBuildContinuation = nil
    }
}

actor SlowImageResourceLoader: ImageResourceLoading {
    private let delayNanoseconds: UInt64
    private(set) var calls: [ImageResourceRequest] = []

    init(delayNanoseconds: UInt64) {
        self.delayNanoseconds = delayNanoseconds
    }

    func loadImage(_ request: ImageResourceRequest) async throws -> ImageResourceResult {
        calls.append(request)
        try await Task.sleep(nanoseconds: delayNanoseconds)
        return ImageResourceResult(request: request, contentType: "image/png", data: Data("image".utf8))
    }
}

actor RecordingRealtimeClient: StoatRealtimeClient {
    nonisolated var connectionState: AsyncStream<RealtimeConnectionState> { stateHub.stream() }
    nonisolated var events: AsyncStream<StoatGatewayEvent> { eventHub.stream() }
    nonisolated var diagnosticsStream: AsyncStream<RealtimeDiagnostics> { diagnosticsHub.stream() }

    private let stateHub = TestStreamHub<RealtimeConnectionState>()
    private let eventHub = TestStreamHub<StoatGatewayEvent>()
    private let diagnosticsHub = TestStreamHub<RealtimeDiagnostics>()
    private let statesOnConnect: [RealtimeConnectionState]
    private let eventsOnConnect: [StoatGatewayEvent]

    private(set) var connectCallCount = 0
    private(set) var disconnectCallCount = 0
    private(set) var sentEvents: [ClientGatewayEvent] = []
    private(set) var connectedEnvironments: [StoatAPIEnvironment] = []
    private(set) var connectedCredentials: [StoatAuthCredential] = []

    init(statesOnConnect: [RealtimeConnectionState] = [], eventsOnConnect: [StoatGatewayEvent] = []) {
        self.statesOnConnect = statesOnConnect
        self.eventsOnConnect = eventsOnConnect
    }

    func connect(credential: StoatAuthCredential, environment: StoatAPIEnvironment, readyFields: Set<ReadyField>) async throws {
        connectCallCount += 1
        connectedEnvironments.append(environment)
        connectedCredentials.append(credential)
        for state in statesOnConnect {
            stateHub.yield(state)
        }
        for event in eventsOnConnect {
            eventHub.yield(event)
        }
    }

    func disconnect() async {
        disconnectCallCount += 1
        stateHub.yield(.disconnected(reason: .requested))
    }

    func send(_ event: ClientGatewayEvent) async throws {
        sentEvents.append(event)
    }
}

actor RecordingAPIClient: StoatAPIClient {
    private(set) var fetchCurrentUserCallCount = 0
    private(set) var editUserCallCount = 0
    private(set) var fetchMessagesCallCount = 0
    private(set) var fetchMessageCallCount = 0
    private(set) var searchedMessages: [(ChannelID, ChannelMessageSearchRequest)] = []
    private(set) var pinnedMessages: [(ChannelID, MessageID)] = []
    private(set) var unpinnedMessages: [(ChannelID, MessageID)] = []
    private(set) var fetchServerMembersCallCount = 0
    private(set) var fetchedServerMemberIDs: [ServerID] = []
    private(set) var fetchUserProfileCallCount = 0
    private(set) var fetchDirectMessagesCallCount = 0
    private(set) var openDirectMessageCallCount = 0
    private(set) var openedDirectMessageUserIDs: [UserID] = []
    private(set) var sentDrafts: [(ChannelID, MessageDraft)] = []
    private(set) var editedMessages: [(ChannelID, MessageID, MessageEditDraft)] = []
    private(set) var deletedMessages: [(ChannelID, MessageID)] = []
    private(set) var addedReactions: [(ChannelID, MessageID, String)] = []
    private(set) var removedReactions: [(ChannelID, MessageID, String)] = []
    private(set) var editedUserDrafts: [(UserID, UserEditDraft)] = []
    private(set) var uploadedFiles: [RecordedUpload] = []
    private(set) var createdGroupDrafts: [GroupChannelCreateDraft] = []
    private(set) var fetchedSettingsKeys: [[String]] = []
    private(set) var setSettingsPayloads: [(values: [String: String], timestamp: Int64)] = []
    private(set) var addedGroupRecipients: [(ChannelID, UserID)] = []
    private(set) var removedGroupRecipients: [(ChannelID, UserID)] = []

    private let currentUser: User
    private var messagesByChannel: [ChannelID: [Message]]
    private var membersByServer: [ServerID: [ServerMember]]
    private var usersByServer: [ServerID: [User]]
    private var directMessages: [Channel]
    private var openDirectMessagesByUserID: [UserID: Channel]
    private var editedUsersByID: [UserID: User] = [:]
    private var profilesByUserID: [UserID: UserProfile]
    private let fetchError: (any Error & Sendable)?
    private let fetchMessagesDelayNanoseconds: UInt64
    private let directMessagesFetchError: (any Error & Sendable)?
    private let openDirectMessageError: (any Error & Sendable)?
    private let openDirectMessageDelayNanoseconds: UInt64
    private let memberFetchError: (any Error & Sendable)?
    private let memberFetchDelayNanoseconds: UInt64
    private let editUserError: (any Error & Sendable)?
    private let uploadError: (any Error & Sendable)?
    private let uploadedFileIDsByTag: [UploadTag: FileID]
    private let createGroupError: (any Error & Sendable)?
    private var syncedSettings: [String: SyncedSettingValue]
    private let settingsSyncError: (any Error & Sendable)?
    private let addGroupRecipientError: (any Error & Sendable)?
    private let removeGroupRecipientError: (any Error & Sendable)?

    init(
        currentUser: User = User(id: TestShellData.currentUserID, username: "liquidbagel"),
        messagesByChannel: [ChannelID: [Message]] = [:],
        membersByServer: [ServerID: [ServerMember]] = [:],
        usersByServer: [ServerID: [User]] = [:],
        directMessages: [Channel] = [],
        openDirectMessagesByUserID: [UserID: Channel] = [:],
        profilesByUserID: [UserID: UserProfile] = [:],
        fetchError: (any Error & Sendable)? = nil,
        fetchMessagesDelayNanoseconds: UInt64 = 0,
        directMessagesFetchError: (any Error & Sendable)? = nil,
        openDirectMessageError: (any Error & Sendable)? = nil,
        openDirectMessageDelayNanoseconds: UInt64 = 0,
        memberFetchError: (any Error & Sendable)? = nil,
        memberFetchDelayNanoseconds: UInt64 = 0,
        editUserError: (any Error & Sendable)? = nil,
        uploadError: (any Error & Sendable)? = nil,
        uploadedFileIDsByTag: [UploadTag: FileID] = [:],
        createGroupError: (any Error & Sendable)? = nil,
        syncedSettings: [String: SyncedSettingValue] = [:],
        settingsSyncError: (any Error & Sendable)? = nil,
        addGroupRecipientError: (any Error & Sendable)? = nil,
        removeGroupRecipientError: (any Error & Sendable)? = nil
    ) {
        self.currentUser = currentUser
        self.messagesByChannel = messagesByChannel
        self.membersByServer = membersByServer
        self.usersByServer = usersByServer
        self.directMessages = directMessages
        self.openDirectMessagesByUserID = openDirectMessagesByUserID
        self.profilesByUserID = profilesByUserID
        self.fetchError = fetchError
        self.fetchMessagesDelayNanoseconds = fetchMessagesDelayNanoseconds
        self.directMessagesFetchError = directMessagesFetchError
        self.openDirectMessageError = openDirectMessageError
        self.openDirectMessageDelayNanoseconds = openDirectMessageDelayNanoseconds
        self.memberFetchError = memberFetchError
        self.memberFetchDelayNanoseconds = memberFetchDelayNanoseconds
        self.editUserError = editUserError
        self.uploadError = uploadError
        self.uploadedFileIDsByTag = uploadedFileIDsByTag
        self.createGroupError = createGroupError
        self.syncedSettings = syncedSettings
        self.settingsSyncError = settingsSyncError
        self.addGroupRecipientError = addGroupRecipientError
        self.removeGroupRecipientError = removeGroupRecipientError
    }

    func overrideSyncedSetting(key: String, value: SyncedSettingValue) {
        syncedSettings[key] = value
    }

    func fetchSyncedSettings(keys: [String]) async throws -> [String: SyncedSettingValue] {
        fetchedSettingsKeys.append(keys)
        if let settingsSyncError {
            throw settingsSyncError
        }
        return syncedSettings.filter { keys.contains($0.key) }
    }

    func setSyncedSettings(_ values: [String: String], timestamp: Int64) async throws {
        setSettingsPayloads.append((values: values, timestamp: timestamp))
        if let settingsSyncError {
            throw settingsSyncError
        }
        for (key, value) in values {
            syncedSettings[key] = SyncedSettingValue(timestamp: timestamp, rawValue: value)
        }
    }

    func fetchRootConfiguration() async throws -> StoatConfig {
        throw StoatAPIError.unimplementedEndpoint("test")
    }

    func fetchCurrentUser() async throws -> User {
        fetchCurrentUserCallCount += 1
        return currentUser
    }

    func createGroupChannel(draft: GroupChannelCreateDraft) async throws -> Channel {
        createdGroupDrafts.append(draft)
        if let createGroupError {
            throw createGroupError
        }
        var recipients = [currentUser.id]
        recipients.append(contentsOf: draft.users.filter { $0 != currentUser.id })
        return Channel(
            id: ChannelID(rawValue: "recorded-group-\(createdGroupDrafts.count)"),
            kind: .group,
            name: draft.trimmedName,
            ownerID: currentUser.id,
            active: true,
            recipients: recipients
        )
    }

    func addGroupRecipient(channelID: ChannelID, userID: UserID) async throws {
        addedGroupRecipients.append((channelID, userID))
        if let addGroupRecipientError {
            throw addGroupRecipientError
        }
    }

    func removeGroupRecipient(channelID: ChannelID, userID: UserID) async throws {
        removedGroupRecipients.append((channelID, userID))
        if let removeGroupRecipientError {
            throw removeGroupRecipientError
        }
    }

    func editUser(userID: UserID, draft: UserEditDraft) async throws -> User {
        editUserCallCount += 1
        editedUserDrafts.append((userID, draft))
        if let editUserError {
            throw editUserError
        }
        var user = editedUsersByID[userID] ?? (userID == currentUser.id ? currentUser : User(id: userID, username: UserDisplayResolver.shortenedID(userID)))
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
                filename: "recorded-avatar.png",
                metadata: .file,
                contentType: "image/png",
                size: 12,
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
            var profile = profilesByUserID[userID] ?? UserProfile()
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
                    filename: "recorded-background.png",
                    metadata: .file,
                    contentType: "image/png",
                    size: 24,
                    userID: userID
                )
            }
            profilesByUserID[userID] = profile
        }
        editedUsersByID[userID] = user
        return user
    }

    func fetchUserProfile(userID: UserID) async throws -> UserProfile {
        fetchUserProfileCallCount += 1
        return profilesByUserID[userID] ?? UserProfile(content: "Profile for \(userID.rawValue)")
    }

    func fetchDirectMessages() async throws -> [Channel] {
        fetchDirectMessagesCallCount += 1
        if let directMessagesFetchError {
            throw directMessagesFetchError
        }
        return directMessages
    }

    func openDirectMessage(userID: UserID) async throws -> Channel {
        openDirectMessageCallCount += 1
        openedDirectMessageUserIDs.append(userID)
        if openDirectMessageDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: openDirectMessageDelayNanoseconds)
        }
        if let openDirectMessageError {
            throw openDirectMessageError
        }
        if let channel = openDirectMessagesByUserID[userID] {
            return channel
        }
        let channel = Channel(id: ChannelID(rawValue: "recorded-dm-\(userID.rawValue)"), kind: userID == currentUser.id ? .savedMessages : .directMessage, userID: userID == currentUser.id ? currentUser.id : nil, active: true, recipients: [currentUser.id, userID])
        openDirectMessagesByUserID[userID] = channel
        return channel
    }

    func fetchServers() async throws -> [Server] {
        []
    }

    func fetchChannels() async throws -> [Channel] {
        []
    }

    func fetchChannel(id: ChannelID) async throws -> Channel {
        throw StoatAPIError.notFound
    }

    func fetchMessage(channelID: ChannelID, messageID: MessageID) async throws -> Message {
        fetchMessageCallCount += 1
        guard let message = messagesByChannel[channelID]?.first(where: { $0.id == messageID }) else {
            throw StoatAPIError.notFound
        }
        return message
    }

    func fetchMessages(channelID: ChannelID, options: MessageFetchOptions) async throws -> [Message] {
        fetchMessagesCallCount += 1
        if fetchMessagesDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: fetchMessagesDelayNanoseconds)
        }
        if let fetchError {
            throw fetchError
        }
        var messages = messagesByChannel[channelID] ?? []
        messages.sort { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
        if let nearby = options.nearby,
           let index = messages.firstIndex(where: { $0.id == nearby }) {
            let limit = max(1, options.limit ?? 50)
            let half = max(1, limit / 2)
            let lower = max(messages.startIndex, index - half)
            let upper = min(messages.endIndex, index + half + 1)
            messages = Array(messages[lower..<upper])
        } else {
            if let before = options.before, let index = messages.firstIndex(where: { $0.id == before }) {
                messages = Array(messages[..<index])
            }
            if let after = options.after, let index = messages.firstIndex(where: { $0.id == after }) {
                messages = Array(messages[messages.index(after: index)...])
            }
            if let limit = options.limit, messages.count > limit {
                messages = Array(messages.prefix(limit))
            }
        }
        return messages
    }

    func fetchMessages(channelID: ChannelID, before: MessageID?, after: MessageID?, limit: Int?) async throws -> [Message] {
        fetchMessagesCallCount += 1
        if fetchMessagesDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: fetchMessagesDelayNanoseconds)
        }
        if let fetchError {
            throw fetchError
        }
        var messages = messagesByChannel[channelID] ?? []
        messages.sort { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
        if let before, let index = messages.firstIndex(where: { $0.id == before }) {
            messages = Array(messages[..<index])
        }
        if let after, let index = messages.firstIndex(where: { $0.id == after }) {
            messages = Array(messages[messages.index(after: index)...])
        }
        if let limit, messages.count > limit {
            messages = Array(messages.prefix(limit))
        }
        return messages
    }

    func searchMessages(channelID: ChannelID, request: ChannelMessageSearchRequest) async throws -> [Message] {
        searchedMessages.append((channelID, request))
        var messages = messagesByChannel[channelID] ?? []
        if request.pinned == true {
            messages = messages.filter { $0.isPinned }
        }
        if let query = request.query?.lowercased(), !query.isEmpty {
            messages = messages.filter { ($0.content ?? "").lowercased().contains(query) }
        }
        messages.sort { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        if let limit = request.limit, messages.count > limit {
            messages = Array(messages.prefix(limit))
        }
        return messages
    }

    func fetchServerMembers(serverID: ServerID) async throws -> ServerMembersResponse {
        fetchServerMembersCallCount += 1
        fetchedServerMemberIDs.append(serverID)
        if memberFetchDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: memberFetchDelayNanoseconds)
        }
        if let memberFetchError {
            throw memberFetchError
        }
        return ServerMembersResponse(members: membersByServer[serverID] ?? [], users: usersByServer[serverID] ?? [])
    }

    func sendMessage(channelID: ChannelID, draft: MessageDraft) async throws -> Message {
        sentDrafts.append((channelID, draft))
        let message = Message(id: "01J00000100000000000000001", channelID: channelID, authorID: currentUser.id, content: draft.content, nonce: draft.nonce)
        messagesByChannel[channelID, default: []].append(message)
        return message
    }

    func editMessage(channelID: ChannelID, messageID: MessageID, draft: MessageEditDraft) async throws -> Message {
        editedMessages.append((channelID, messageID, draft))
        return Message(id: messageID, channelID: channelID, authorID: currentUser.id, content: draft.content, editedAt: Date())
    }

    func deleteMessage(channelID: ChannelID, messageID: MessageID) async throws {
        deletedMessages.append((channelID, messageID))
    }

    func addReaction(channelID: ChannelID, messageID: MessageID, emoji: String) async throws {
        addedReactions.append((channelID, messageID, emoji))
    }

    func removeReaction(channelID: ChannelID, messageID: MessageID, emoji: String, removeAll: Bool) async throws {
        removedReactions.append((channelID, messageID, emoji))
    }

    func pinMessage(channelID: ChannelID, messageID: MessageID) async throws {
        pinnedMessages.append((channelID, messageID))
    }

    func unpinMessage(channelID: ChannelID, messageID: MessageID) async throws {
        unpinnedMessages.append((channelID, messageID))
    }

    func uploadFile(data: Data, filename: String, mimeType: String, tag: UploadTag) async throws -> UploadedFile {
        uploadedFiles.append(RecordedUpload(data: data, filename: filename, mimeType: mimeType, tag: tag))
        if let uploadError {
            throw uploadError
        }
        let fallbackID = FileID(rawValue: "\(tag.rawAPIValue)-file-\(uploadedFiles.count)")
        return UploadedFile(id: uploadedFileIDsByTag[tag] ?? fallbackID)
    }
}

struct RecordedUpload: Sendable, Hashable {
    var data: Data
    var filename: String
    var mimeType: String
    var tag: UploadTag
}

struct RecordedAttachmentSend: Sendable {
    var channelID: ChannelID
    var content: String
    var nonce: String?
    var replies: [MessageReply]?
    var attachments: [FileID]?
}

actor RecordingAttachmentMessageActionHandler: MessageActionHandling {
    private(set) var sent: [RecordedAttachmentSend] = []
    var sendError: (any Error & Sendable)?

    func sentSnapshot() -> [RecordedAttachmentSend] {
        sent
    }

    func setSendError(_ error: (any Error & Sendable)?) {
        sendError = error
    }

    func sendMessage(channelID: ChannelID, content: String, nonce: String?, replies: [MessageReply]?, attachments: [FileID]?) async throws -> Message {
        if let sendError {
            throw sendError
        }
        sent.append(RecordedAttachmentSend(channelID: channelID, content: content, nonce: nonce, replies: replies, attachments: attachments))
        let files = attachments?.map {
            File(id: $0, tag: "attachments", filename: "\($0.rawValue).txt", contentType: "text/plain", size: 1)
        }
        return Message(id: "01J00000100000000000009999", channelID: channelID, authorID: TestShellData.currentUserID, content: content, nonce: nonce, attachments: files, replies: replies?.map(\.id))
    }

    func editMessage(channelID: ChannelID, messageID: MessageID, content: String) async throws -> Message {
        Message(id: messageID, channelID: channelID, authorID: TestShellData.currentUserID, content: content)
    }

    func deleteMessage(channelID: ChannelID, messageID: MessageID) async throws {}
    func addReaction(channelID: ChannelID, messageID: MessageID, emoji: String) async throws {}
    func removeReaction(channelID: ChannelID, messageID: MessageID, emoji: String) async throws {}
    func pinMessage(channelID: ChannelID, messageID: MessageID) async throws {}
    func unpinMessage(channelID: ChannelID, messageID: MessageID) async throws {}
    func beginTyping(channelID: ChannelID) async throws {}
    func endTyping(channelID: ChannelID) async throws {}
}

actor DelayedMessageActionHandler: MessageActionHandling {
    let delay: Duration

    init(delay: Duration) {
        self.delay = delay
    }

    func sendMessage(channelID: ChannelID, content: String, nonce: String?, replies: [MessageReply]?, attachments: [FileID]?) async throws -> Message {
        try await Task.sleep(for: delay)
        return Message(
            id: "01J00000100000000000030000",
            channelID: channelID,
            authorID: TestShellData.currentUserID,
            content: content,
            nonce: nonce,
            replies: replies?.map(\.id)
        )
    }

    func editMessage(channelID: ChannelID, messageID: MessageID, content: String) async throws -> Message {
        Message(id: messageID, channelID: channelID, authorID: TestShellData.currentUserID, content: content)
    }

    func deleteMessage(channelID: ChannelID, messageID: MessageID) async throws {}
    func addReaction(channelID: ChannelID, messageID: MessageID, emoji: String) async throws {}
    func removeReaction(channelID: ChannelID, messageID: MessageID, emoji: String) async throws {}
    func pinMessage(channelID: ChannelID, messageID: MessageID) async throws {}
    func unpinMessage(channelID: ChannelID, messageID: MessageID) async throws {}
    func beginTyping(channelID: ChannelID) async throws {}
    func endTyping(channelID: ChannelID) async throws {}
}

actor Phase59ReactionHandler: MessageActionHandling {
    let delay: Duration
    let error: (any Error & Sendable)?
    private(set) var addCallCount = 0
    private(set) var removeCallCount = 0

    init(delay: Duration, error: (any Error & Sendable)? = nil) {
        self.delay = delay
        self.error = error
    }

    func sendMessage(channelID: ChannelID, content: String, nonce: String?, replies: [MessageReply]?, attachments: [FileID]?) async throws -> Message {
        Message(id: "phase59-send", channelID: channelID, authorID: TestShellData.currentUserID, content: content)
    }

    func editMessage(channelID: ChannelID, messageID: MessageID, content: String) async throws -> Message {
        Message(id: messageID, channelID: channelID, authorID: TestShellData.currentUserID, content: content)
    }

    func deleteMessage(channelID: ChannelID, messageID: MessageID) async throws {}

    func addReaction(channelID: ChannelID, messageID: MessageID, emoji: String) async throws {
        addCallCount += 1
        try await Task.sleep(for: delay)
        if let error { throw error }
    }

    func removeReaction(channelID: ChannelID, messageID: MessageID, emoji: String) async throws {
        removeCallCount += 1
        try await Task.sleep(for: delay)
        if let error { throw error }
    }

    func pinMessage(channelID: ChannelID, messageID: MessageID) async throws {}
    func unpinMessage(channelID: ChannelID, messageID: MessageID) async throws {}
    func beginTyping(channelID: ChannelID) async throws {}
    func endTyping(channelID: ChannelID) async throws {}
}

final class SequencedMediaURLProtocol: URLProtocol, @unchecked Sendable {
    enum Stub {
        case response(status: Int, headers: [String: String], data: Data)
        case failure(URLError)
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var stubs: [Stub] = []
    nonisolated(unsafe) private static var recordedRequestCount = 0

    static var requestCount: Int {
        lock.withLock { recordedRequestCount }
    }

    static func configure(_ stubs: [Stub]) {
        lock.withLock {
            self.stubs = stubs
            recordedRequestCount = 0
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let stub: Stub? = Self.lock.withLock {
            Self.recordedRequestCount += 1
            return Self.stubs.isEmpty ? nil : Self.stubs.removeFirst()
        }
        guard let stub else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        switch stub {
        case let .failure(error):
            client?.urlProtocol(self, didFailWithError: error)
        case let .response(status, headers, data):
            guard let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            ) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

actor ImageAttachmentMessageActionHandler: MessageActionHandling {
    func sendMessage(channelID: ChannelID, content: String, nonce: String?, replies: [MessageReply]?, attachments: [FileID]?) async throws -> Message {
        let files = attachments?.map {
            File(id: $0, tag: "attachments", filename: "\($0.rawValue).png", metadata: .image(width: 1, height: 1, thumbhash: nil, animated: false), contentType: "image/png", size: 8)
        }
        return Message(id: "01J00000100000000000020000", channelID: channelID, authorID: TestShellData.currentUserID, content: content, nonce: nonce, attachments: files, replies: replies?.map(\.id))
    }

    func editMessage(channelID: ChannelID, messageID: MessageID, content: String) async throws -> Message {
        Message(id: messageID, channelID: channelID, authorID: TestShellData.currentUserID, content: content)
    }

    func deleteMessage(channelID: ChannelID, messageID: MessageID) async throws {}
    func addReaction(channelID: ChannelID, messageID: MessageID, emoji: String) async throws {}
    func removeReaction(channelID: ChannelID, messageID: MessageID, emoji: String) async throws {}
    func pinMessage(channelID: ChannelID, messageID: MessageID) async throws {}
    func unpinMessage(channelID: ChannelID, messageID: MessageID) async throws {}
    func beginTyping(channelID: ChannelID) async throws {}
    func endTyping(channelID: ChannelID) async throws {}
}

struct StubSessionValidator: SessionValidating {
    var user: User
    var error: (any Error & Sendable)?

    init(
        user: User = User(id: TestShellData.currentUserID, username: "liquidbagel"),
        error: (any Error & Sendable)? = nil
    ) {
        self.user = user
        self.error = error
    }

    func validate(credential: StoatAuthCredential, environment: StoatAPIEnvironment) async throws -> ValidatedSession {
        if let error {
            throw error
        }
        return ValidatedSession(credential: credential, currentUser: user, environment: environment)
    }
}

actor RecordingSessionValidator: SessionValidating {
    private var errors: [any Error & Sendable]
    private let user: User
    private(set) var validateCallCount = 0

    init(
        user: User = User(id: TestShellData.currentUserID, username: "liquidbagel"),
        errors: [any Error & Sendable] = []
    ) {
        self.user = user
        self.errors = errors
    }

    func validate(credential: StoatAuthCredential, environment: StoatAPIEnvironment) async throws -> ValidatedSession {
        validateCallCount += 1
        if !errors.isEmpty {
            throw errors.removeFirst()
        }
        return ValidatedSession(credential: credential, currentUser: user, environment: environment)
    }
}
