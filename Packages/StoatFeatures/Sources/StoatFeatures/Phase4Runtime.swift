import Foundation
import Observation
import StoatAPI
import StoatModels
import StoatPersistence
import StoatRealtime

public enum AppSessionState: Equatable, Sendable {
    case mock
    case signedOut
    case loadingCredential
    case savedCredentialUnvalidated
    case validatingCredential
    case validatedReady
    case readyToConnect
    case connecting
    case connected
    case invalidSession(String)
    case validationFailed(String)
    case connectionFailed(String)
    case keychainFailed(String)
    case failed(String)
}

public struct LoginMFAChallenge: Hashable, Sendable {
    public var ticket: String
    public var allowedMethods: [MFAMethod]

    public init(ticket: String, allowedMethods: [MFAMethod]) {
        self.ticket = ticket
        self.allowedMethods = allowedMethods
    }
}

public struct LiveVerificationState: Equatable, Sendable {
    public var credentialLoaded = false
    public var currentUserFetched = false
    public var webSocketConnected = false
    public var authenticated = false
    public var readyReceived = false
    public var usersReceived = false
    public var serversReceived = false
    public var channelsReceived = false
    public var selectedChannelAvailable = false
    public var messageFetchSucceeded = false
    public var lastRealtimeEventAt: Date?
    public var lastPingLatencyMilliseconds: Int?
    public var lastMessageActionResult: String?

    public init() {}
}

public struct LiveHydrationStatus: Hashable, Sendable {
    public var readyReceived: Bool
    public var userCount: Int
    public var serverCount: Int
    public var channelCount: Int
    public var memberCount: Int
    public var unreadCount: Int
    public var selectedServerAvailable: Bool
    public var selectedChannelAvailable: Bool
    public var warning: String?
    public var lastHydratedAt: Date?

    public init(
        readyReceived: Bool = false,
        userCount: Int = 0,
        serverCount: Int = 0,
        channelCount: Int = 0,
        memberCount: Int = 0,
        unreadCount: Int = 0,
        selectedServerAvailable: Bool = false,
        selectedChannelAvailable: Bool = false,
        warning: String? = nil,
        lastHydratedAt: Date? = nil
    ) {
        self.readyReceived = readyReceived
        self.userCount = userCount
        self.serverCount = serverCount
        self.channelCount = channelCount
        self.memberCount = memberCount
        self.unreadCount = unreadCount
        self.selectedServerAvailable = selectedServerAvailable
        self.selectedChannelAvailable = selectedChannelAvailable
        self.warning = warning
        self.lastHydratedAt = lastHydratedAt
    }

    public static let empty = LiveHydrationStatus()
}

public enum TimelineMessageStatus: Hashable, Sendable {
    case confirmed
    case pending
    case failed(String)
}

public struct TimelineMessage: Hashable, Sendable, Identifiable {
    public var message: Message
    public var status: TimelineMessageStatus

    public var id: MessageID { message.id }

    public init(message: Message, status: TimelineMessageStatus = .confirmed) {
        self.message = message
        self.status = status
    }
}

public enum ChannelMessageState: Equatable, Sendable {
    case idle
    case loading
    case loaded(messages: [TimelineMessage], hasMoreBefore: Bool)
    case loadingOlder(messages: [TimelineMessage])
    case empty
    case failed(String, cachedMessages: [TimelineMessage])

    public var timelineMessages: [TimelineMessage] {
        switch self {
        case .idle, .loading, .empty:
            return []
        case let .loaded(messages, _), let .loadingOlder(messages), let .failed(_, messages):
            return messages
        }
    }

    public var hasMessages: Bool {
        !timelineMessages.isEmpty
    }
}

public protocol ShellSnapshotSource: Sendable {
    var snapshots: AsyncStream<RealtimeSnapshot> { get }
    func currentSnapshot() async -> RealtimeSnapshot
}

public struct MockShellSnapshotSource: ShellSnapshotSource {
    private let snapshot: RealtimeSnapshot

    public init(snapshot: RealtimeSnapshot = MockShellData.snapshot) {
        self.snapshot = snapshot
    }

    public var snapshots: AsyncStream<RealtimeSnapshot> {
        AsyncStream { continuation in
            continuation.yield(snapshot)
            continuation.finish()
        }
    }

    public func currentSnapshot() async -> RealtimeSnapshot {
        snapshot
    }
}

public struct RealtimeStoreSnapshotSource: ShellSnapshotSource {
    private let store: RealtimeStateStore

    public init(store: RealtimeStateStore) {
        self.store = store
    }

    public var snapshots: AsyncStream<RealtimeSnapshot> {
        store.snapshots
    }

    public func currentSnapshot() async -> RealtimeSnapshot {
        await store.snapshot()
    }
}

public enum MessageActionError: Error, Equatable, Sendable, LocalizedError {
    case unavailable(String)
    case missingCurrentUser

    public var errorDescription: String? {
        switch self {
        case let .unavailable(message):
            return message
        case .missingCurrentUser:
            return "No current user is available for this message action."
        }
    }
}

public protocol MessageActionHandling: Sendable {
    func sendMessage(channelID: ChannelID, content: String, nonce: String?) async throws -> Message
    func editMessage(channelID: ChannelID, messageID: MessageID, content: String) async throws -> Message
    func deleteMessage(channelID: ChannelID, messageID: MessageID) async throws
    func addReaction(channelID: ChannelID, messageID: MessageID, emoji: String) async throws
    func removeReaction(channelID: ChannelID, messageID: MessageID, emoji: String) async throws
    func beginTyping(channelID: ChannelID) async throws
    func endTyping(channelID: ChannelID) async throws
}

public actor MockMessageActionHandler: MessageActionHandling {
    public private(set) var sentMessages: [Message] = []
    public private(set) var editedMessages: [(ChannelID, MessageID, String)] = []
    public private(set) var deletedMessages: [(ChannelID, MessageID)] = []
    public private(set) var addedReactions: [(ChannelID, MessageID, String)] = []
    public private(set) var removedReactions: [(ChannelID, MessageID, String)] = []
    public private(set) var typingEvents: [ClientGatewayEvent] = []

    private let currentUserID: UserID
    private var nextMessageCounter = 0
    private var sendError: (any Error & Sendable)?

    public init(currentUserID: UserID = MockShellData.currentUserID, sendError: (any Error & Sendable)? = nil) {
        self.currentUserID = currentUserID
        self.sendError = sendError
    }

    public func setSendError(_ error: (any Error & Sendable)?) {
        sendError = error
    }

    public func sendMessage(channelID: ChannelID, content: String, nonce: String?) async throws -> Message {
        if let sendError {
            throw sendError
        }
        nextMessageCounter += 1
        let message = Message(
            id: MessageID(rawValue: Self.mockMessageID(counter: nextMessageCounter)),
            channelID: channelID,
            authorID: currentUserID,
            content: content,
            nonce: nonce
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

public actor LiveMessageActionHandler: MessageActionHandling {
    private let apiClient: any StoatAPIClient
    private let realtimeClient: any StoatRealtimeClient

    public init(apiClient: any StoatAPIClient, realtimeClient: any StoatRealtimeClient) {
        self.apiClient = apiClient
        self.realtimeClient = realtimeClient
    }

    public func sendMessage(channelID: ChannelID, content: String, nonce: String?) async throws -> Message {
        try await apiClient.sendMessage(channelID: channelID, draft: MessageDraft(content: content, nonce: nonce))
    }

    public func editMessage(channelID: ChannelID, messageID: MessageID, content: String) async throws -> Message {
        try await apiClient.editMessage(channelID: channelID, messageID: messageID, draft: MessageEditDraft(content: content))
    }

    public func deleteMessage(channelID: ChannelID, messageID: MessageID) async throws {
        try await apiClient.deleteMessage(channelID: channelID, messageID: messageID)
    }

    public func addReaction(channelID: ChannelID, messageID: MessageID, emoji: String) async throws {
        try await apiClient.addReaction(channelID: channelID, messageID: messageID, emoji: emoji)
    }

    public func removeReaction(channelID: ChannelID, messageID: MessageID, emoji: String) async throws {
        try await apiClient.removeReaction(channelID: channelID, messageID: messageID, emoji: emoji, removeAll: false)
    }

    public func beginTyping(channelID: ChannelID) async throws {
        try await realtimeClient.send(.beginTyping(channel: channelID))
    }

    public func endTyping(channelID: ChannelID) async throws {
        try await realtimeClient.send(.endTyping(channel: channelID))
    }
}

public actor UnavailableMessageActionHandler: MessageActionHandling {
    private let message: String

    public init(message: String = "Message actions are unavailable in the current session.") {
        self.message = message
    }

    public func sendMessage(channelID: ChannelID, content: String, nonce: String?) async throws -> Message {
        throw MessageActionError.unavailable(message)
    }

    public func editMessage(channelID: ChannelID, messageID: MessageID, content: String) async throws -> Message {
        throw MessageActionError.unavailable(message)
    }

    public func deleteMessage(channelID: ChannelID, messageID: MessageID) async throws {
        throw MessageActionError.unavailable(message)
    }

    public func addReaction(channelID: ChannelID, messageID: MessageID, emoji: String) async throws {
        throw MessageActionError.unavailable(message)
    }

    public func removeReaction(channelID: ChannelID, messageID: MessageID, emoji: String) async throws {
        throw MessageActionError.unavailable(message)
    }

    public func beginTyping(channelID: ChannelID) async throws {
        throw MessageActionError.unavailable(message)
    }

    public func endTyping(channelID: ChannelID) async throws {
        throw MessageActionError.unavailable(message)
    }
}

@MainActor
@Observable
public final class ChannelMessageController {
    public private(set) var statesByChannelID: [ChannelID: ChannelMessageState]
    public private(set) var sendingChannelIDs: Set<ChannelID>
    public private(set) var lastErrorByChannelID: [ChannelID: String]

    @ObservationIgnored private var apiClient: (any StoatAPIClient)?
    @ObservationIgnored private var runtimeMode: AppRuntimeMode
    @ObservationIgnored private var currentUserID: UserID?
    @ObservationIgnored private let pageSize: Int
    @ObservationIgnored private let messageCapPerChannel: Int
    @ObservationIgnored private var loadTokens: [ChannelID: UUID] = [:]

    public init(
        runtimeMode: AppRuntimeMode = .mock,
        apiClient: (any StoatAPIClient)? = nil,
        currentUserID: UserID? = MockShellData.currentUserID,
        pageSize: Int = 50,
        messageCapPerChannel: Int = 250
    ) {
        self.runtimeMode = runtimeMode
        self.apiClient = apiClient
        self.currentUserID = currentUserID
        self.pageSize = pageSize
        self.messageCapPerChannel = messageCapPerChannel
        self.statesByChannelID = [:]
        self.sendingChannelIDs = []
        self.lastErrorByChannelID = [:]
    }

    public func configure(runtimeMode: AppRuntimeMode, apiClient: (any StoatAPIClient)?, currentUserID: UserID?) {
        self.runtimeMode = runtimeMode
        self.apiClient = apiClient
        self.currentUserID = currentUserID
    }

    public func reset() {
        statesByChannelID.removeAll()
        sendingChannelIDs.removeAll()
        lastErrorByChannelID.removeAll()
        loadTokens.removeAll()
    }

    public func state(for channelID: ChannelID?) -> ChannelMessageState {
        guard let channelID else { return .idle }
        return statesByChannelID[channelID] ?? .idle
    }

    public func hydrate(from snapshot: RealtimeSnapshot) {
        for (channelID, messages) in snapshot.messagesByChannelID {
            mergeSnapshotMessages(messages, channelID: channelID)
        }
    }

    public func loadInitialIfNeeded(channelID: ChannelID, snapshotMessages: [Message]) async {
        if case .loaded = statesByChannelID[channelID], !snapshotMessages.isEmpty {
            mergeSnapshotMessages(snapshotMessages, channelID: channelID)
            return
        }
        await loadInitialMessages(channelID: channelID, snapshotMessages: snapshotMessages)
    }

    public func loadInitialMessages(channelID: ChannelID, snapshotMessages: [Message]) async {
        let token = UUID()
        loadTokens[channelID] = token

        if shouldUseLiveAPI, let apiClient {
            let cached = merge(current: state(for: channelID).timelineMessages, incoming: snapshotMessages)
            statesByChannelID[channelID] = cached.isEmpty ? .loading : .loaded(messages: cached, hasMoreBefore: true)
            do {
                let fetched = try await apiClient.fetchMessages(channelID: channelID, before: nil, after: nil, limit: pageSize)
                guard loadTokens[channelID] == token else { return }
                let merged = merge(current: cached, incoming: fetched)
                statesByChannelID[channelID] = merged.isEmpty ? .empty : .loaded(messages: merged, hasMoreBefore: fetched.count >= pageSize)
                lastErrorByChannelID[channelID] = nil
            } catch {
                guard loadTokens[channelID] == token else { return }
                statesByChannelID[channelID] = .failed(error.userFacingMessage, cachedMessages: cached)
                lastErrorByChannelID[channelID] = error.userFacingMessage
            }
            return
        }

        let merged = merge(current: state(for: channelID).timelineMessages, incoming: snapshotMessages)
        statesByChannelID[channelID] = merged.isEmpty ? .empty : .loaded(messages: merged, hasMoreBefore: false)
    }

    public func loadOlderMessages(channelID: ChannelID) async {
        guard shouldUseLiveAPI, let apiClient else { return }
        let current = state(for: channelID).timelineMessages
        guard let before = current.map(\.message.id).sorted(by: messageIDChronologicalSort).first else { return }

        let token = UUID()
        loadTokens[channelID] = token
        statesByChannelID[channelID] = .loadingOlder(messages: current)

        do {
            let fetched = try await apiClient.fetchMessages(channelID: channelID, before: before, after: nil, limit: pageSize)
            guard loadTokens[channelID] == token else { return }
            let merged = merge(current: current, incoming: fetched)
            statesByChannelID[channelID] = merged.isEmpty ? .empty : .loaded(messages: merged, hasMoreBefore: fetched.count >= pageSize)
            lastErrorByChannelID[channelID] = nil
        } catch {
            guard loadTokens[channelID] == token else { return }
            statesByChannelID[channelID] = .failed(error.userFacingMessage, cachedMessages: current)
            lastErrorByChannelID[channelID] = error.userFacingMessage
        }
    }

    public func refreshMessages(channelID: ChannelID, snapshotMessages: [Message]) async {
        statesByChannelID[channelID] = .loading
        await loadInitialMessages(channelID: channelID, snapshotMessages: snapshotMessages)
    }

    public func sendMessage(channelID: ChannelID, content: String, handler: any MessageActionHandling) async -> Bool {
        guard let currentUserID else {
            statesByChannelID[channelID] = .failed(MessageActionError.missingCurrentUser.userFacingMessage, cachedMessages: state(for: channelID).timelineMessages)
            return false
        }

        let nonce = UUID().uuidString
        let pending = TimelineMessage(
            message: Message(
                id: MessageID(rawValue: "pending-\(nonce)"),
                channelID: channelID,
                authorID: currentUserID,
                content: content,
                nonce: nonce
            ),
            status: .pending
        )
        replaceOrAppend(pending, channelID: channelID)
        sendingChannelIDs.insert(channelID)

        do {
            let confirmed = try await handler.sendMessage(channelID: channelID, content: content, nonce: nonce)
            sendingChannelIDs.remove(channelID)
            reconcileConfirmedMessage(confirmed, nonce: nonce, channelID: channelID)
            lastErrorByChannelID[channelID] = nil
            return true
        } catch {
            sendingChannelIDs.remove(channelID)
            markPendingFailed(nonce: nonce, channelID: channelID, error: error.userFacingMessage)
            lastErrorByChannelID[channelID] = error.userFacingMessage
            return false
        }
    }

    public func retrySend(_ timelineMessage: TimelineMessage, handler: any MessageActionHandling) async -> Bool {
        guard let content = timelineMessage.message.content else { return false }
        removeMessage(channelID: timelineMessage.message.channelID, messageID: timelineMessage.message.id)
        return await sendMessage(channelID: timelineMessage.message.channelID, content: content, handler: handler)
    }

    public func applyEditedMessage(_ message: Message) {
        replaceOrAppend(TimelineMessage(message: message, status: .confirmed), channelID: message.channelID)
    }

    public func removeMessage(channelID: ChannelID, messageID: MessageID) {
        var messages = state(for: channelID).timelineMessages
        messages.removeAll { $0.message.id == messageID }
        statesByChannelID[channelID] = messages.isEmpty ? .empty : .loaded(messages: messages, hasMoreBefore: false)
    }

    public func applyReaction(channelID: ChannelID, messageID: MessageID, emoji: String, userID: UserID, isAdding: Bool) {
        var messages = state(for: channelID).timelineMessages
        guard let index = messages.firstIndex(where: { $0.message.id == messageID }) else { return }
        if isAdding {
            messages[index].message.reactions[emoji, default: []].insert(userID)
        } else {
            messages[index].message.reactions[emoji]?.remove(userID)
            if messages[index].message.reactions[emoji]?.isEmpty == true {
                messages[index].message.reactions.removeValue(forKey: emoji)
            }
        }
        statesByChannelID[channelID] = .loaded(messages: sortedCapped(messages), hasMoreBefore: false)
    }

    private var shouldUseLiveAPI: Bool {
        runtimeMode == .liveManual && apiClient != nil
    }

    private func mergeSnapshotMessages(_ messages: [Message], channelID: ChannelID) {
        let merged = merge(current: state(for: channelID).timelineMessages, incoming: messages)
        guard !merged.isEmpty else { return }
        let hasMore: Bool
        if case let .loaded(_, existingHasMore) = statesByChannelID[channelID] {
            hasMore = existingHasMore
        } else {
            hasMore = shouldUseLiveAPI
        }
        statesByChannelID[channelID] = .loaded(messages: merged, hasMoreBefore: hasMore)
    }

    private func merge(current: [TimelineMessage], incoming messages: [Message]) -> [TimelineMessage] {
        var byID: [MessageID: TimelineMessage] = [:]
        var incomingNonces = Set(messages.compactMap(\.nonce))

        for timelineMessage in current {
            switch timelineMessage.status {
            case .confirmed:
                byID[timelineMessage.message.id] = timelineMessage
            case .pending, .failed:
                if let nonce = timelineMessage.message.nonce, incomingNonces.contains(nonce) {
                    continue
                }
                byID[timelineMessage.message.id] = timelineMessage
            }
        }

        for message in messages {
            byID[message.id] = TimelineMessage(message: message, status: .confirmed)
            if let nonce = message.nonce {
                incomingNonces.insert(nonce)
            }
        }

        return sortedCapped(Array(byID.values))
    }

    private func replaceOrAppend(_ timelineMessage: TimelineMessage, channelID: ChannelID) {
        var messages = state(for: channelID).timelineMessages
        if let index = messages.firstIndex(where: { $0.message.id == timelineMessage.message.id }) {
            messages[index] = timelineMessage
        } else {
            messages.append(timelineMessage)
        }
        statesByChannelID[channelID] = .loaded(messages: sortedCapped(messages), hasMoreBefore: false)
    }

    private func reconcileConfirmedMessage(_ message: Message, nonce: String, channelID: ChannelID) {
        var messages = state(for: channelID).timelineMessages
        messages.removeAll { timelineMessage in
            timelineMessage.message.id == message.id || timelineMessage.message.nonce == nonce
        }
        messages.append(TimelineMessage(message: message, status: .confirmed))
        statesByChannelID[channelID] = .loaded(messages: sortedCapped(messages), hasMoreBefore: false)
    }

    private func markPendingFailed(nonce: String, channelID: ChannelID, error: String) {
        var messages = state(for: channelID).timelineMessages
        guard let index = messages.firstIndex(where: { $0.message.nonce == nonce }) else { return }
        messages[index].status = .failed(error)
        statesByChannelID[channelID] = .loaded(messages: sortedCapped(messages), hasMoreBefore: false)
    }

    private func sortedCapped(_ messages: [TimelineMessage]) -> [TimelineMessage] {
        let sorted = messages.sorted { lhs, rhs in
            if lhs.message.id == rhs.message.id { return false }
            return messageIDChronologicalSort(lhs.message.id, rhs.message.id)
        }
        guard sorted.count > messageCapPerChannel else { return sorted }
        return Array(sorted.suffix(messageCapPerChannel))
    }

    private func messageIDChronologicalSort(_ lhs: MessageID, _ rhs: MessageID) -> Bool {
        let lhsDate = Message.dateFromULID(lhs.rawValue) ?? .distantFuture
        let rhsDate = Message.dateFromULID(rhs.rawValue) ?? .distantFuture
        if lhsDate == rhsDate {
            return lhs.rawValue < rhs.rawValue
        }
        return lhsDate < rhsDate
    }
}

@MainActor
@Observable
public final class AppSessionCoordinator {
    public private(set) var mode: AppRuntimeMode
    public private(set) var sessionState: AppSessionState
    public private(set) var connectionState: RealtimeConnectionState
    public private(set) var diagnostics: RealtimeDiagnostics?
    public private(set) var currentUser: User?
    public private(set) var validatedSession: ValidatedSession?
    public private(set) var pendingValidatedSession: ValidatedSession?
    public private(set) var mfaChallenge: LoginMFAChallenge?
    public private(set) var snapshot: RealtimeSnapshot
    public private(set) var hasSavedCredential: Bool
    public private(set) var lastErrorMessage: String?
    public private(set) var environment: StoatAPIEnvironment
    public private(set) var preferences: AppPreferences
    public private(set) var preferenceErrorMessage: String?
    public private(set) var localSessionLabel: String?
    public private(set) var verificationState: LiveVerificationState
    public private(set) var hydrationStatus: LiveHydrationStatus
    public private(set) var liveConnectionGeneration: Int

    @ObservationIgnored public private(set) var snapshotSource: any ShellSnapshotSource
    @ObservationIgnored public private(set) var apiClient: (any StoatAPIClient)?
    @ObservationIgnored public private(set) var messageActionHandler: any MessageActionHandling

    @ObservationIgnored private let tokenStore: any TokenStore
    @ObservationIgnored private let preferencesStore: any AppPreferencesStore
    @ObservationIgnored private let readyFields: Set<ReadyField>
    @ObservationIgnored private let mockSnapshot: RealtimeSnapshot
    @ObservationIgnored private let mockCurrentUserID: UserID
    @ObservationIgnored private let sessionValidator: any SessionValidating
    @ObservationIgnored private let apiClientFactory: @Sendable (StoatAPIEnvironment, any CredentialProvider) -> any StoatAPIClient
    @ObservationIgnored private let realtimeClientFactory: @Sendable () -> any StoatRealtimeClient
    @ObservationIgnored private let realtimeStoreFactory: @Sendable () -> RealtimeStateStore
    @ObservationIgnored private var realtimeClient: (any StoatRealtimeClient)?
    @ObservationIgnored private var realtimeStore: RealtimeStateStore?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var connectionTask: Task<Void, Never>?
    @ObservationIgnored private var diagnosticsTask: Task<Void, Never>?

    public init(
        tokenStore: any TokenStore = KeychainTokenStore(),
        preferencesStore: any AppPreferencesStore = UserDefaultsAppPreferencesStore(),
        environment: StoatAPIEnvironment = .production,
        readyFields: Set<ReadyField> = Set([.users, .servers, .channels, .members, .emojis, .userSettings, .channelUnreads, .policyChanges]),
        mockSnapshot: RealtimeSnapshot = MockShellData.snapshot,
        mockCurrentUserID: UserID = MockShellData.currentUserID,
        sessionValidator: (any SessionValidating)? = nil,
        apiClientFactory: @escaping @Sendable (StoatAPIEnvironment, any CredentialProvider) -> any StoatAPIClient = { environment, provider in
            LiveStoatAPIClient(environment: environment, credentialProvider: provider)
        },
        realtimeClientFactory: @escaping @Sendable () -> any StoatRealtimeClient = {
            LiveStoatRealtimeClient()
        },
        realtimeStoreFactory: @escaping @Sendable () -> RealtimeStateStore = {
            RealtimeStateStore()
        }
    ) {
        self.tokenStore = tokenStore
        self.preferencesStore = preferencesStore
        self.environment = environment
        self.readyFields = readyFields
        self.mockSnapshot = mockSnapshot
        self.mockCurrentUserID = mockCurrentUserID
        self.sessionValidator = sessionValidator ?? LiveSessionValidator(apiClientFactory: apiClientFactory)
        self.apiClientFactory = apiClientFactory
        self.realtimeClientFactory = realtimeClientFactory
        self.realtimeStoreFactory = realtimeStoreFactory
        self.mode = .mock
        self.sessionState = .mock
        self.connectionState = .idle
        self.snapshot = mockSnapshot
        self.currentUser = mockSnapshot.usersByID[mockCurrentUserID]
        self.validatedSession = nil
        self.pendingValidatedSession = nil
        self.mfaChallenge = nil
        self.hasSavedCredential = false
        self.lastErrorMessage = nil
        self.environment = environment
        self.preferences = .defaults
        self.preferenceErrorMessage = nil
        self.localSessionLabel = nil
        self.verificationState = LiveVerificationState()
        self.hydrationStatus = .empty
        self.liveConnectionGeneration = 0
        self.snapshotSource = MockShellSnapshotSource(snapshot: mockSnapshot)
        self.messageActionHandler = MockMessageActionHandler(currentUserID: mockCurrentUserID)
    }

    deinit {
        eventTask?.cancel()
        connectionTask?.cancel()
        diagnosticsTask?.cancel()
    }

    public func startMockSession() async {
        await startMockSession(loadStoredPreferences: true)
    }

    private func startMockSession(loadStoredPreferences: Bool) async {
        if loadStoredPreferences {
            await loadPreferences()
        }
        await disconnectActiveRealtime()
        mode = .mock
        sessionState = .mock
        connectionState = .idle
        diagnostics = nil
        lastErrorMessage = nil
        validatedSession = nil
        pendingValidatedSession = nil
        mfaChallenge = nil
        verificationState = LiveVerificationState()
        hydrationStatus = .empty
        snapshot = mockSnapshot
        currentUser = mockSnapshot.usersByID[mockCurrentUserID]
        snapshotSource = MockShellSnapshotSource(snapshot: mockSnapshot)
        apiClient = nil
        messageActionHandler = MockMessageActionHandler(currentUserID: mockCurrentUserID)
        await refreshCredentialAvailability()
        if hasSavedCredential {
            sessionState = .readyToConnect
        }
    }

    public func loadPreferences() async {
        do {
            let loaded = try await preferencesStore.loadPreferences()
            preferences = loaded
            environment = loaded.selectedEnvironment
            preferenceErrorMessage = nil
        } catch {
            preferences = .defaults
            environment = .production
            let message = "Could not load preferences: \(error.userFacingMessage)"
            preferenceErrorMessage = message
            lastErrorMessage = message
        }
    }

    public func savePreferences(_ newPreferences: AppPreferences) async {
        do {
            let validated = try newPreferences.validated()
            preferences = validated
            try await preferencesStore.savePreferences(validated)
            preferenceErrorMessage = nil
        } catch {
            let message = "Could not save preferences: \(error.userFacingMessage)"
            preferenceErrorMessage = message
            lastErrorMessage = message
        }
    }

    public func updatePreferences(_ update: (inout AppPreferences) throws -> Void) async {
        var updated = preferences
        do {
            try update(&updated)
            await savePreferences(updated)
        } catch {
            let message = "Could not update preferences: \(error.userFacingMessage)"
            preferenceErrorMessage = message
            lastErrorMessage = message
        }
    }

    public func refreshCredentialAvailability() async {
        do {
            hasSavedCredential = try await loadCredentialForCurrentEnvironment() != nil
            if mode == .liveManual, sessionState == .signedOut, hasSavedCredential {
                sessionState = .savedCredentialUnvalidated
            }
        } catch {
            hasSavedCredential = false
            let message = "Could not read saved credential: \(error.userFacingMessage)"
            lastErrorMessage = message
            sessionState = .keychainFailed(message)
        }
        verificationState.credentialLoaded = hasSavedCredential
    }

    public func setEnvironment(_ newEnvironment: StoatAPIEnvironment) async {
        do {
            try newEnvironment.validate()
            if !preferences.environmentProfiles.contains(where: { $0.environment == newEnvironment }) {
                let profile = try EnvironmentProfile.custom(name: "Custom Environment", environment: newEnvironment)
                preferences = try preferences.upserting(profile: profile).withSelectedEnvironmentID(profile.id)
            } else if let profile = preferences.environmentProfiles.first(where: { $0.environment == newEnvironment }) {
                preferences = preferences.withSelectedEnvironmentID(profile.id)
            }
            await savePreferences(preferences)
            await disconnectActiveRealtime()
            environment = newEnvironment
            mode = .liveManual
            sessionState = .signedOut
            connectionState = .idle
            diagnostics = nil
            validatedSession = nil
            pendingValidatedSession = nil
            mfaChallenge = nil
            currentUser = nil
            lastErrorMessage = nil
            verificationState = LiveVerificationState()
            hydrationStatus = .empty
            installLiveSafeSnapshot()
            await refreshCredentialAvailability()
        } catch {
            let message = "Custom environment is invalid: \(error.userFacingMessage)"
            sessionState = .validationFailed(message)
            lastErrorMessage = message
        }
    }

    public func selectEnvironmentProfile(id: String) async {
        guard let profile = preferences.environmentProfiles.first(where: { $0.id == id }) else {
            let message = "Environment profile was not found."
            sessionState = .validationFailed(message)
            lastErrorMessage = message
            return
        }
        var updated = preferences.withSelectedEnvironmentID(profile.id)
        updated.preferredLaunchMode = .rememberLastButDoNotConnect
        await savePreferences(updated)
        await setEnvironment(profile.environment)
    }

    public func upsertEnvironmentProfile(_ profile: EnvironmentProfile) async {
        do {
            let updated = try preferences.upserting(profile: profile).withSelectedEnvironmentID(profile.id)
            await savePreferences(updated)
            await setEnvironment(profile.environment)
        } catch {
            let message = "Could not save environment profile: \(error.userFacingMessage)"
            sessionState = .validationFailed(message)
            lastErrorMessage = message
        }
    }

    public func deleteEnvironmentProfile(id: String, forgetCredential: Bool = false) async {
        do {
            let deletingSelected = preferences.lastSelectedEnvironmentID == id || environment.stableID == id
            if forgetCredential {
                try await clearCredential(environmentID: id)
            }
            let updated = try preferences.deletingProfile(id: id)
            await savePreferences(updated)
            if deletingSelected {
                await setEnvironment(.production)
            }
        } catch {
            let message = "Could not delete environment profile: \(error.userFacingMessage)"
            sessionState = .validationFailed(message)
            lastErrorMessage = message
        }
    }

    public func validateImportedToken(_ token: String, localLabel: String? = nil) async {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        mode = .liveManual
        sessionState = .validatingCredential
        lastErrorMessage = nil
        pendingValidatedSession = nil
        mfaChallenge = nil
        do {
            let session = try await sessionValidator.validate(credential: .sessionToken(trimmed), environment: environment)
            pendingValidatedSession = session
            currentUser = session.currentUser
            localSessionLabel = localLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
            verificationState.currentUserFetched = true
            sessionState = .validatedReady
        } catch {
            let message = error.userFacingMessage
            pendingValidatedSession = nil
            currentUser = nil
            sessionState = sessionFailureState(for: error, fallback: message)
            lastErrorMessage = message
        }
    }

    public func savePendingValidatedSession() async {
        guard let pendingValidatedSession else {
            let message = "Validate a session before saving it."
            sessionState = .validationFailed(message)
            lastErrorMessage = message
            return
        }
        do {
            try await saveCredentialForCurrentEnvironment(pendingValidatedSession.credential)
            validatedSession = pendingValidatedSession
            self.pendingValidatedSession = nil
            hasSavedCredential = true
            verificationState.credentialLoaded = true
            verificationState.currentUserFetched = true
            currentUser = pendingValidatedSession.currentUser
            sessionState = .readyToConnect
            lastErrorMessage = nil
        } catch {
            let message = "Could not save credential to Keychain: \(error.userFacingMessage)"
            sessionState = .keychainFailed(message)
            lastErrorMessage = message
        }
    }

    public func validateSavedSession() async {
        mode = .liveManual
        sessionState = .loadingCredential
        lastErrorMessage = nil
        do {
            guard let credential = try await loadCredentialForCurrentEnvironment() else {
                hasSavedCredential = false
                verificationState.credentialLoaded = false
                sessionState = .signedOut
                currentUser = nil
                installLiveSafeSnapshot()
                return
            }
            hasSavedCredential = true
            verificationState.credentialLoaded = true
            sessionState = .validatingCredential
            let session = try await sessionValidator.validate(credential: credential, environment: environment)
            validatedSession = session
            currentUser = session.currentUser
            verificationState.currentUserFetched = true
            sessionState = .readyToConnect
        } catch {
            let message = error.userFacingMessage
            validatedSession = nil
            currentUser = nil
            sessionState = sessionFailureState(for: error, fallback: message)
            lastErrorMessage = message
        }
    }

    public func credentialForCurrentEnvironment() async throws -> StoatAuthCredential? {
        try await loadCredentialForCurrentEnvironment()
    }

    public func credentialExists(environmentID: String) async -> Bool {
        do {
            if let scoped = tokenStore as? any ScopedTokenStore {
                return try await scoped.loadCredential(scope: CredentialScope(environmentID: environmentID)) != nil
            }
            guard environmentID == StoatAPIEnvironment.production.stableID else { return false }
            return try await tokenStore.loadCredential() != nil
        } catch {
            return false
        }
    }

    public func login(email: String, password: String, friendlyName: String = "Liquid Bagel macOS") async {
        mode = .liveManual
        sessionState = .validatingCredential
        lastErrorMessage = nil
        mfaChallenge = nil
        pendingValidatedSession = nil
        let client = apiClientFactory(environment, StaticCredentialProvider(nil))
        do {
            let response = try await client.login(request: SessionLoginRequest(email: email, password: password, friendlyName: friendlyName))
            await handleLoginResponse(response, friendlyName: friendlyName)
        } catch {
            let message = "Login failed: \(error.userFacingMessage)"
            sessionState = .validationFailed(message)
            lastErrorMessage = message
        }
    }

    public func continueLoginMFA(response: MFAResponse, friendlyName: String = "Liquid Bagel macOS") async {
        guard let mfaChallenge else {
            let message = "No MFA challenge is waiting."
            sessionState = .validationFailed(message)
            lastErrorMessage = message
            return
        }
        sessionState = .validatingCredential
        lastErrorMessage = nil
        let client = apiClientFactory(environment, StaticCredentialProvider(nil))
        do {
            let response = try await client.continueLogin(
                request: SessionMFALoginRequest(mfaTicket: mfaChallenge.ticket, mfaResponse: response, friendlyName: friendlyName)
            )
            await handleLoginResponse(response, friendlyName: friendlyName)
        } catch {
            let message = "MFA login failed: \(error.userFacingMessage)"
            sessionState = .validationFailed(message)
            lastErrorMessage = message
        }
    }

    private func handleLoginResponse(_ response: SessionLoginResponse, friendlyName: String) async {
        switch response {
        case let .success(success):
            localSessionLabel = friendlyName
            mfaChallenge = nil
            let credential = success.credential
            do {
                let session = try await sessionValidator.validate(credential: credential, environment: environment)
                pendingValidatedSession = session
                currentUser = session.currentUser
                verificationState.currentUserFetched = true
                sessionState = .validatedReady
            } catch {
                let message = "Login succeeded, but validation failed: \(error.userFacingMessage)"
                sessionState = sessionFailureState(for: error, fallback: message)
                lastErrorMessage = message
            }
        case let .mfa(ticket, allowedMethods):
            mfaChallenge = LoginMFAChallenge(ticket: ticket, allowedMethods: allowedMethods)
            sessionState = .validationFailed("Multi-factor authentication is required.")
            lastErrorMessage = nil
        case let .disabled(userID):
            let message = "This account is disabled or unavailable. User ID: \(userID.rawValue)"
            sessionState = .validationFailed(message)
            lastErrorMessage = message
        }
    }

    public func connectLiveManually() async {
        await disconnectActiveRealtime()
        mode = .liveManual
        sessionState = .loadingCredential
        connectionState = .idle
        diagnostics = nil
        lastErrorMessage = nil

        let credential: StoatAuthCredential
        do {
            guard let loaded = try await loadCredentialForCurrentEnvironment() else {
                hasSavedCredential = false
                sessionState = .signedOut
                installLiveSafeSnapshot()
                return
            }
            credential = loaded
            hasSavedCredential = true
            verificationState.credentialLoaded = true
            sessionState = validatedSession == nil ? .validatingCredential : .readyToConnect
        } catch {
            hasSavedCredential = false
            let message = "Could not load saved credential: \(error.userFacingMessage)"
            sessionState = .keychainFailed(message)
            failLiveSession(message)
            return
        }

        sessionState = .connecting
        liveConnectionGeneration += 1
        let provider = StaticCredentialProvider(credential)
        let apiClient = apiClientFactory(environment, provider)
        let realtimeClient = realtimeClientFactory()
        let store = realtimeStoreFactory()
        self.apiClient = apiClient
        self.realtimeClient = realtimeClient
        self.realtimeStore = store
        self.snapshotSource = RealtimeStoreSnapshotSource(store: store)
        self.messageActionHandler = LiveMessageActionHandler(apiClient: apiClient, realtimeClient: realtimeClient)
        self.snapshot = await store.snapshot()

        startObservingRealtime(realtimeClient: realtimeClient, store: store)

        do {
            let validation = try await sessionValidator.validate(credential: credential, environment: environment)
            validatedSession = validation
            currentUser = validation.currentUser
            verificationState.currentUserFetched = true
            try await realtimeClient.connect(credential: credential, environment: environment, readyFields: readyFields)
        } catch {
            await disconnectActiveRealtime()
            let message = "Live connection failed: \(error.userFacingMessage)"
            sessionState = .connectionFailed(message)
            failLiveSession(message, replaceConnectionState: true)
        }
    }

    public func reconnectLiveManually() async {
        await connectLiveManually()
    }

    public func disconnectLive() async {
        await disconnectActiveRealtime()
        mode = .liveManual
        connectionState = .disconnected(reason: .requested)
        diagnostics = nil
        currentUser = nil
        apiClient = nil
        messageActionHandler = UnavailableMessageActionHandler(message: "Connect Live Manual before sending messages.")
        installLiveSafeSnapshot()
        await refreshCredentialAvailability()
        sessionState = hasSavedCredential ? .readyToConnect : .signedOut
    }

    public func forgetLocalSession() async {
        await disconnectActiveRealtime()
        do {
            try await clearCredentialForCurrentEnvironment()
            mode = .liveManual
            sessionState = .signedOut
            connectionState = .disconnected(reason: .requested)
            diagnostics = nil
            currentUser = nil
            validatedSession = nil
            pendingValidatedSession = nil
            mfaChallenge = nil
            hasSavedCredential = false
            verificationState = LiveVerificationState()
            hydrationStatus = .empty
            apiClient = nil
            messageActionHandler = UnavailableMessageActionHandler(message: "Set up a session before sending messages.")
            installLiveSafeSnapshot()
            lastErrorMessage = nil
        } catch {
            let message = "Could not delete saved credential: \(error.userFacingMessage)"
            sessionState = .keychainFailed(message)
            lastErrorMessage = message
        }
    }

    public func revokeCurrentSessionOnServer() async {
        do {
            guard let credential = try await loadCredentialForCurrentEnvironment() else {
                let message = "No saved session is available to revoke."
                sessionState = .signedOut
                lastErrorMessage = message
                return
            }
            let client = apiClientFactory(environment, StaticCredentialProvider(credential))
            try await client.logoutCurrentSession()
            await forgetLocalSession()
        } catch {
            let message = "Server-side session revocation failed: \(error.userFacingMessage)"
            sessionState = .validationFailed(message)
            lastErrorMessage = message
        }
    }

    public func markSelectedChannelMessageFetchSucceeded(channelID: ChannelID, isAvailable: Bool) {
        verificationState.selectedChannelAvailable = isAvailable
        verificationState.messageFetchSucceeded = true
    }

    public func markLastMessageActionResult(_ result: String) {
        verificationState.lastMessageActionResult = result
    }

    public func resetToMock() async {
        await startMockSession(loadStoredPreferences: false)
    }

    private func startObservingRealtime(realtimeClient: any StoatRealtimeClient, store: RealtimeStateStore) {
        eventTask?.cancel()
        connectionTask?.cancel()
        diagnosticsTask?.cancel()

        eventTask = Task { [weak self] in
            for await event in realtimeClient.events {
                await store.apply(event)
                let snapshot = await store.snapshot()
                await MainActor.run {
                    self?.snapshot = snapshot
                    self?.applyVerificationState(event: event, snapshot: snapshot)
                }
            }
        }

        connectionTask = Task { [weak self] in
            for await state in realtimeClient.connectionState {
                await MainActor.run {
                    self?.connectionState = state
                    self?.applySessionState(for: state)
                }
            }
        }

        diagnosticsTask = Task { [weak self] in
            for await diagnostics in realtimeClient.diagnosticsStream {
                await MainActor.run {
                    self?.diagnostics = diagnostics
                    self?.verificationState.lastRealtimeEventAt = diagnostics.lastReceivedEventAt
                    self?.verificationState.lastPingLatencyMilliseconds = diagnostics.lastLatencyMilliseconds
                }
            }
        }
    }

    private func applyVerificationState(event: StoatGatewayEvent, snapshot: RealtimeSnapshot) {
        verificationState.lastRealtimeEventAt = diagnostics?.lastReceivedEventAt ?? Date()
        switch event {
        case .authenticated:
            verificationState.authenticated = true
        case .ready:
            verificationState.readyReceived = true
            updateHydrationStatus(snapshot: snapshot, readyReceived: true)
        default:
            if verificationState.readyReceived {
                updateHydrationStatus(snapshot: snapshot, readyReceived: true)
            }
            break
        }
        verificationState.usersReceived = !snapshot.usersByID.isEmpty
        verificationState.serversReceived = !snapshot.serversByID.isEmpty
        verificationState.channelsReceived = !snapshot.channelsByID.isEmpty
    }

    private func applySessionState(for state: RealtimeConnectionState) {
        switch state {
        case .ready:
            sessionState = .connected
            lastErrorMessage = nil
            verificationState.readyReceived = true
            verificationState.webSocketConnected = true
            verificationState.authenticated = true
            updateHydrationStatus(snapshot: snapshot, readyReceived: true)
        case .connecting, .connected, .authenticating, .authenticated, .reconnecting:
            sessionState = .connecting
            verificationState.webSocketConnected = true
            if case .authenticated = state {
                verificationState.authenticated = true
            }
        case let .failed(error):
            failLiveSession(error.userFacingMessage, replaceConnectionState: false)
        case .disconnected:
            if mode == .liveManual {
                sessionState = hasSavedCredential ? .readyToConnect : .signedOut
            }
        case .idle:
            break
        }
    }

    private func failLiveSession(_ message: String, replaceConnectionState: Bool = true) {
        if case .connectionFailed = sessionState {
            // Preserve the more specific state set by the caller.
        } else if case .keychainFailed = sessionState {
            // Preserve the more specific state set by the caller.
        } else {
            sessionState = .failed(message)
        }
        if replaceConnectionState {
            connectionState = .failed(.unknown(message))
        }
        lastErrorMessage = message
        messageActionHandler = UnavailableMessageActionHandler(message: message)
    }

    private func installLiveSafeSnapshot() {
        snapshot = RealtimeSnapshot()
        snapshotSource = MockShellSnapshotSource(snapshot: snapshot)
        hydrationStatus = .empty
    }

    public func updateHydrationSelectionAvailability(serverAvailable: Bool, channelAvailable: Bool, warning: String?) {
        hydrationStatus.selectedServerAvailable = serverAvailable
        hydrationStatus.selectedChannelAvailable = channelAvailable
        hydrationStatus.warning = warning ?? hydrationStatus.warning
    }

    private func updateHydrationStatus(snapshot: RealtimeSnapshot, readyReceived: Bool) {
        let textChannelCount = snapshot.channelsByID.values.filter { channel in
            channel.kind == .textChannel || channel.kind == .group || channel.kind == .savedMessages
        }.count
        let warning: String?
        if !readyReceived {
            warning = "Waiting for realtime data"
        } else if snapshot.serversByID.isEmpty {
            warning = "No servers available"
        } else if textChannelCount == 0 {
            warning = "No text channels available"
        } else {
            warning = nil
        }
        hydrationStatus = LiveHydrationStatus(
            readyReceived: readyReceived,
            userCount: snapshot.usersByID.count,
            serverCount: snapshot.serversByID.count,
            channelCount: snapshot.channelsByID.count,
            memberCount: snapshot.membersByServerAndUserID.count,
            unreadCount: snapshot.unreadsByChannelID.count,
            selectedServerAvailable: hydrationStatus.selectedServerAvailable,
            selectedChannelAvailable: hydrationStatus.selectedChannelAvailable,
            warning: warning,
            lastHydratedAt: readyReceived ? Date() : hydrationStatus.lastHydratedAt
        )
    }

    private var currentCredentialScope: CredentialScope {
        CredentialScope(environmentID: environment.stableID)
    }

    private func loadCredentialForCurrentEnvironment() async throws -> StoatAuthCredential? {
        if let scoped = tokenStore as? any ScopedTokenStore {
            return try await scoped.loadCredential(scope: currentCredentialScope)
        }
        return try await tokenStore.loadCredential()
    }

    private func saveCredentialForCurrentEnvironment(_ credential: StoatAuthCredential) async throws {
        if let scoped = tokenStore as? any ScopedTokenStore {
            try await scoped.saveCredential(credential, scope: currentCredentialScope)
        } else {
            try await tokenStore.saveCredential(credential)
        }
    }

    private func clearCredentialForCurrentEnvironment() async throws {
        try await clearCredential(environmentID: environment.stableID)
    }

    public func clearCredential(environmentID: String) async throws {
        if let scoped = tokenStore as? any ScopedTokenStore {
            try await scoped.clearCredential(scope: CredentialScope(environmentID: environmentID))
        } else {
            try await tokenStore.clearCredential()
        }
    }

    private func sessionFailureState(for error: Error, fallback: String) -> AppSessionState {
        if let validationError = error as? SessionValidationError {
            switch validationError {
            case .invalidOrExpired:
                return .invalidSession(fallback)
            case .forbidden, .missingCredential, .rateLimited, .networkUnavailable, .serverUnavailable, .invalidEnvironment, .failed:
                return .validationFailed(fallback)
            }
        }
        return .validationFailed(fallback)
    }

    private func disconnectActiveRealtime() async {
        eventTask?.cancel()
        connectionTask?.cancel()
        diagnosticsTask?.cancel()
        eventTask = nil
        connectionTask = nil
        diagnosticsTask = nil
        if let realtimeClient {
            await realtimeClient.disconnect()
        }
        realtimeClient = nil
        realtimeStore = nil
    }
}

extension Error {
    var userFacingMessage: String {
        if let localized = self as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return localizedDescription
    }
}
