import Foundation
import Observation
import StoatAPI
import StoatModels
import StoatPersistence
import StoatRealtime

public enum AppSessionState: Hashable, Sendable {
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

public enum LoginFlowState: Hashable, Sendable {
    case idle
    case submitting
    case mfaRequired
    case succeeded
}

public enum LoginErrorDisplay: Hashable, Sendable {
    case invalidCredentials
    case accountDisabled
    case mfaFailed
    case rateLimited
    case networkError
    case serverError
    case keychainError
    case environmentError
    case unknown(String)

    public var localizedDescription: String {
        switch self {
        case .invalidCredentials: "Invalid email or password."
        case .accountDisabled: "This account is disabled or unavailable."
        case .mfaFailed: "Multi-factor authentication failed."
        case .rateLimited: "Too many attempts. Please wait a moment and try again."
        case .networkError: "Network unavailable. Check your connection and try again."
        case .serverError: "The server is unavailable. Try again later."
        case .keychainError: "Could not save your session. Check Keychain access."
        case .environmentError: "The selected environment is invalid."
        case let .unknown(message): StartupAuthDiagnosticsRedactor.redact(message)
        }
    }
}

public struct LoginDiagnostics: Hashable, Sendable {
    public var lastAttemptAt: Date?
    public var attemptCount: Int
    public var lastErrorCategory: LoginErrorDisplay?

    public init() {
        lastAttemptAt = nil
        attemptCount = 0
        lastErrorCategory = nil
    }

    public var redactedSummary: String {
        var parts: [String] = []
        parts.append("attempts: \(attemptCount)")
        if let lastAttemptAt {
            let formatter = ISO8601DateFormatter()
            parts.append("last: \(formatter.string(from: lastAttemptAt))")
        }
        if let lastErrorCategory {
            parts.append("last error: \(loginErrorCategoryName(lastErrorCategory))")
        }
        return parts.joined(separator: ", ")
    }
}

public struct StartupAuthDiagnostics: Hashable, Sendable {
    public var startupInvocationCount: Int
    public var startupSkippedCount: Int
    public var startupAutoConnectAttemptCount: Int
    public var lastEnvironmentKind: String?
    public var lastStartupAction: String?
    public var lastStartupResult: String?
    public var lastAuthAction: String?
    public var lastAuthResult: String?
    public var lastErrorCategory: LoginErrorDisplay?

    public init() {
        startupInvocationCount = 0
        startupSkippedCount = 0
        startupAutoConnectAttemptCount = 0
        lastEnvironmentKind = nil
        lastStartupAction = nil
        lastStartupResult = nil
        lastAuthAction = nil
        lastAuthResult = nil
        lastErrorCategory = nil
    }

    public var redactedSummary: String {
        var parts = [
            "startup invocations: \(startupInvocationCount)",
            "startup skipped: \(startupSkippedCount)",
            "auto-connect attempts: \(startupAutoConnectAttemptCount)"
        ]
        if let lastEnvironmentKind {
            parts.append("environment: \(StartupAuthDiagnosticsRedactor.redact(lastEnvironmentKind))")
        }
        if let lastStartupAction {
            parts.append("startup action: \(StartupAuthDiagnosticsRedactor.redact(lastStartupAction))")
        }
        if let lastStartupResult {
            parts.append("startup result: \(StartupAuthDiagnosticsRedactor.redact(lastStartupResult))")
        }
        if let lastAuthAction {
            parts.append("auth action: \(StartupAuthDiagnosticsRedactor.redact(lastAuthAction))")
        }
        if let lastAuthResult {
            parts.append("auth result: \(StartupAuthDiagnosticsRedactor.redact(lastAuthResult))")
        }
        if let lastErrorCategory {
            parts.append("last error: \(loginErrorCategoryName(lastErrorCategory))")
        }
        return parts.joined(separator: ", ")
    }
}

enum StartupAuthDiagnosticsRedactor {
    static func redact(_ value: String) -> String {
        var output = value
        let replacements: [(String, String)] = [
            (#"\{[^\n]*(authorization|token|session|password|secret|mfa|ticket|response|error)[^\n]*\}"#, "[redacted-payload]"),
            (#"https?://\S+"#, "[redacted-url]"),
            (#"/(?:Users|tmp|var|private|Volumes|Library|System)/[^\s,;\)]+"#, "[redacted-path]"),
            (#"(?i)(authorization|token|session|password|secret|mfa|mfa_response|mfa_ticket|keychain)[\s:=]+"?[^"\s,;]+"?"#, "$1=[redacted]"),
            (#"\b(?=[A-Za-z0-9_-]*\d)[A-Za-z0-9_-]{24,}\b"#, "[redacted-id]")
        ]
        for (pattern, replacement) in replacements {
            output = output.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        return output
    }
}

private func loginErrorCategoryName(_ error: LoginErrorDisplay) -> String {
    switch error {
    case .invalidCredentials: "invalid_credentials"
    case .accountDisabled: "account_disabled"
    case .mfaFailed: "mfa_failed"
    case .rateLimited: "rate_limited"
    case .networkError: "network_error"
    case .serverError: "server_error"
    case .keychainError: "keychain_error"
    case .environmentError: "environment_error"
    case .unknown: "unknown"
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
    case failed(FailedMessageRecoveryMetadata)
    case retrying(FailedMessageRecoveryMetadata)
    case deleting
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

public enum ChannelMessageLoadOutcome: Equatable, Sendable {
    case loaded(messageCount: Int)
    case alreadyLoaded(messageCount: Int)
    case deduplicated
    case cancelled
    case failed(message: String, cachedMessageCount: Int)
}

public struct ChannelMessageHistory: Hashable, Sendable {
    public var channelID: ChannelID
    public var messages: [TimelineMessage]
    public var hasMoreBefore: Bool
    public var isLoadingInitial: Bool
    public var isLoadingOlder: Bool
    public var lastLoadedAt: Date?
    public var firstUnreadMessageID: MessageID?
    public var newestMessageID: MessageID?
    public var errorMessage: String?
    public var loadedRange: ChannelLoadedMessageRange
    public var unreadRecoveryState: UnreadRecoveryState
    public var pendingReferenceFetchMessageIDs: Set<MessageID>

    public init(
        channelID: ChannelID,
        messages: [TimelineMessage] = [],
        hasMoreBefore: Bool = false,
        isLoadingInitial: Bool = false,
        isLoadingOlder: Bool = false,
        lastLoadedAt: Date? = nil,
        firstUnreadMessageID: MessageID? = nil,
        newestMessageID: MessageID? = nil,
        errorMessage: String? = nil,
        loadedRange: ChannelLoadedMessageRange = ChannelLoadedMessageRange(),
        unreadRecoveryState: UnreadRecoveryState = .none,
        pendingReferenceFetchMessageIDs: Set<MessageID> = []
    ) {
        self.channelID = channelID
        self.messages = messages
        self.hasMoreBefore = hasMoreBefore
        self.isLoadingInitial = isLoadingInitial
        self.isLoadingOlder = isLoadingOlder
        self.lastLoadedAt = lastLoadedAt
        self.firstUnreadMessageID = firstUnreadMessageID
        self.newestMessageID = newestMessageID
        self.errorMessage = errorMessage
        self.loadedRange = loadedRange
        self.unreadRecoveryState = unreadRecoveryState
        self.pendingReferenceFetchMessageIDs = pendingReferenceFetchMessageIDs
    }

    public var state: ChannelMessageState {
        if isLoadingOlder {
            return .loadingOlder(messages: messages)
        }
        if isLoadingInitial && messages.isEmpty {
            return .loading
        }
        if let errorMessage {
            return .failed(errorMessage, cachedMessages: messages)
        }
        if messages.isEmpty {
            return isLoadingInitial ? .loading : .empty
        }
        return .loaded(messages: messages, hasMoreBefore: hasMoreBefore)
    }
}

public struct LocalReadState: Hashable, Sendable {
    public var channelID: ChannelID
    public var firstUnreadMessageID: MessageID?
    public var lastReadMessageID: MessageID?
    public var unreadCount: Int
    public var mentionCount: Int

    public init(
        channelID: ChannelID,
        firstUnreadMessageID: MessageID? = nil,
        lastReadMessageID: MessageID? = nil,
        unreadCount: Int = 0,
        mentionCount: Int = 0
    ) {
        self.channelID = channelID
        self.firstUnreadMessageID = firstUnreadMessageID
        self.lastReadMessageID = lastReadMessageID
        self.unreadCount = unreadCount
        self.mentionCount = mentionCount
    }
}

public struct InlineEditState: Hashable, Sendable {
    public var channelID: ChannelID
    public var messageID: MessageID
    public var originalContent: String
    public var draftContent: String
    public var isSaving: Bool
    public var errorMessage: String?

    public init(
        channelID: ChannelID,
        messageID: MessageID,
        originalContent: String,
        draftContent: String,
        isSaving: Bool = false,
        errorMessage: String? = nil
    ) {
        self.channelID = channelID
        self.messageID = messageID
        self.originalContent = originalContent
        self.draftContent = draftContent
        self.isSaving = isSaving
        self.errorMessage = errorMessage
    }

    public var trimmedDraft: String {
        draftContent.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var canSave: Bool {
        !trimmedDraft.isEmpty && trimmedDraft != originalContent.trimmingCharacters(in: .whitespacesAndNewlines) && !isSaving
    }
}

public enum ChannelMessageHistoryEvent: Hashable, Sendable {
    case initialLoadStarted
    case initialLoadSucceeded(messages: [Message], hasMoreBefore: Bool, loadedAt: Date)
    case initialLoadFailed(String)
    case initialLoadCancelled
    case olderLoadStarted
    case olderLoadSucceeded(messages: [Message], hasMoreBefore: Bool, loadedAt: Date)
    case olderLoadFailed(String)
    case olderLoadCancelled
    case snapshotMerged([Message])
    case optimisticSendCreated(TimelineMessage)
    case sendConfirmed(message: Message, nonce: String?)
    case sendFailed(nonce: String, error: String)
    case retryStarted(messageID: MessageID)
    case retryFailed(messageID: MessageID, error: String)
    case failedRecoveryEdited(messageID: MessageID, content: String)
    case discardLocalMessage(MessageID)
    case realtimeMessageReceived(Message)
    case messageUpdated(Message)
    case messageDeleted(MessageID)
    case reactionChanged(messageID: MessageID, emoji: String, userID: UserID, isAdding: Bool)
    case messagePinned(MessageID)
    case messageUnpinned(MessageID)
    case unreadMarkerMoved(MessageID?)
    case unreadRecoveryChanged(UnreadRecoveryState)
    case channelMarkedRead(lastReadMessageID: MessageID?)
    case referenceFetchStarted(MessageID)
    case referenceFetchFinished(MessageID)
}

public struct ChannelMessageHistoryReducer: Sendable {
    public var messageCapPerChannel: Int

    public init(messageCapPerChannel: Int = 250) {
        self.messageCapPerChannel = messageCapPerChannel
    }

    public func reduce(_ history: ChannelMessageHistory, event: ChannelMessageHistoryEvent) -> ChannelMessageHistory {
        var history = history
        switch event {
        case .initialLoadStarted:
            history.isLoadingInitial = true
            history.errorMessage = nil
            history.loadedRange.lastPaginationError = nil
        case let .initialLoadSucceeded(messages, hasMoreBefore, loadedAt):
            history.messages = merge(current: history.messages, incoming: messages)
            history.hasMoreBefore = hasMoreBefore
            history.loadedRange = Self.loadedRange(for: history.messages, hasMoreBefore: hasMoreBefore, hasMoreAfter: false, error: nil)
            history.isLoadingInitial = false
            history.errorMessage = nil
            history.lastLoadedAt = loadedAt
        case let .initialLoadFailed(message):
            history.isLoadingInitial = false
            history.errorMessage = message
            history.loadedRange.lastPaginationError = message
        case .initialLoadCancelled:
            history.isLoadingInitial = false
        case .olderLoadStarted:
            history.isLoadingOlder = true
            history.errorMessage = nil
            history.loadedRange.lastPaginationError = nil
        case let .olderLoadSucceeded(messages, hasMoreBefore, loadedAt):
            history.messages = merge(current: history.messages, incoming: messages)
            history.hasMoreBefore = hasMoreBefore
            history.loadedRange = Self.loadedRange(for: history.messages, hasMoreBefore: hasMoreBefore, hasMoreAfter: false, error: nil)
            history.isLoadingOlder = false
            history.errorMessage = nil
            history.lastLoadedAt = loadedAt
        case let .olderLoadFailed(message):
            history.isLoadingOlder = false
            history.errorMessage = message
            history.loadedRange.lastPaginationError = message
        case .olderLoadCancelled:
            history.isLoadingOlder = false
        case let .snapshotMerged(messages):
            history.messages = merge(current: history.messages, incoming: messages)
            history.loadedRange = Self.loadedRange(for: history.messages, hasMoreBefore: history.hasMoreBefore, hasMoreAfter: history.loadedRange.hasMoreAfter, error: history.loadedRange.lastPaginationError)
        case let .optimisticSendCreated(timelineMessage):
            history.messages = replacingOrAppending(timelineMessage, in: history.messages)
            history.loadedRange = Self.loadedRange(for: history.messages, hasMoreBefore: history.hasMoreBefore, hasMoreAfter: history.loadedRange.hasMoreAfter, error: history.loadedRange.lastPaginationError)
        case let .sendConfirmed(message, nonce):
            var messages = history.messages
            messages.removeAll { timelineMessage in
                timelineMessage.message.id == message.id || (nonce != nil && timelineMessage.message.nonce == nonce)
            }
            messages.append(TimelineMessage(message: message, status: .confirmed))
            history.messages = sortedCapped(messages)
            history.loadedRange = Self.loadedRange(for: history.messages, hasMoreBefore: history.hasMoreBefore, hasMoreAfter: history.loadedRange.hasMoreAfter, error: history.loadedRange.lastPaginationError)
        case let .sendFailed(nonce, error):
            if let index = history.messages.firstIndex(where: { $0.message.nonce == nonce }) {
                let message = history.messages[index].message
                let replyContext = message.replies?.first.map {
                    ReplyContext(channelID: message.channelID, messageID: $0, authorDisplayName: "Original message", contentPreview: "Original message unavailable")
                }
                history.messages[index].status = .failed(FailedMessageRecoveryMetadata(
                    originalContent: message.content ?? "",
                    originalNonce: nonce,
                    attachmentIDs: message.attachments?.map(\.id) ?? [],
                    attachmentFiles: message.attachments ?? [],
                    replyContext: replyContext,
                    mentionReply: true,
                    lastError: error
                ))
            }
        case let .retryStarted(messageID):
            if let index = history.messages.firstIndex(where: { $0.message.id == messageID }) {
                if case let .failed(metadata) = history.messages[index].status {
                    history.messages[index].status = .retrying(metadata.retrying())
                }
            }
        case let .retryFailed(messageID, error):
            if let index = history.messages.firstIndex(where: { $0.message.id == messageID }) {
                if case let .failed(metadata) = history.messages[index].status {
                    var updated = metadata
                    updated.lastError = error
                    history.messages[index].status = .failed(updated)
                } else if case let .retrying(metadata) = history.messages[index].status {
                    var updated = metadata
                    updated.lastError = error
                    history.messages[index].status = .failed(updated)
                }
            }
        case let .failedRecoveryEdited(messageID, content):
            if let index = history.messages.firstIndex(where: { $0.message.id == messageID }) {
                history.messages[index].message.content = content
                switch history.messages[index].status {
                case let .failed(metadata):
                    history.messages[index].status = .failed(metadata.edited(content: content))
                case let .retrying(metadata):
                    history.messages[index].status = .retrying(metadata.edited(content: content))
                default:
                    break
                }
            }
        case let .discardLocalMessage(messageID):
            history.messages.removeAll { $0.message.id == messageID && $0.status.isLocalOnly }
            history.loadedRange = Self.loadedRange(for: history.messages, hasMoreBefore: history.hasMoreBefore, hasMoreAfter: history.loadedRange.hasMoreAfter, error: history.loadedRange.lastPaginationError)
        case let .realtimeMessageReceived(message):
            history.messages = merge(current: history.messages, incoming: [message])
            history.loadedRange = Self.loadedRange(for: history.messages, hasMoreBefore: history.hasMoreBefore, hasMoreAfter: history.loadedRange.hasMoreAfter, error: history.loadedRange.lastPaginationError)
        case let .messageUpdated(message):
            history.messages = replacingOrAppending(TimelineMessage(message: message, status: .confirmed), in: history.messages)
            history.loadedRange = Self.loadedRange(for: history.messages, hasMoreBefore: history.hasMoreBefore, hasMoreAfter: history.loadedRange.hasMoreAfter, error: history.loadedRange.lastPaginationError)
        case let .messageDeleted(messageID):
            history.messages.removeAll { $0.message.id == messageID }
            if history.firstUnreadMessageID == messageID {
                history.firstUnreadMessageID = history.messages.first?.message.id
            }
            history.loadedRange = Self.loadedRange(for: history.messages, hasMoreBefore: history.hasMoreBefore, hasMoreAfter: history.loadedRange.hasMoreAfter, error: history.loadedRange.lastPaginationError)
        case let .reactionChanged(messageID, emoji, userID, isAdding):
            guard let index = history.messages.firstIndex(where: { $0.message.id == messageID }) else { break }
            if isAdding {
                history.messages[index].message.reactions[emoji, default: []].insert(userID)
            } else {
                history.messages[index].message.reactions[emoji]?.remove(userID)
                if history.messages[index].message.reactions[emoji]?.isEmpty == true {
                    history.messages[index].message.reactions.removeValue(forKey: emoji)
                }
            }
        case let .messagePinned(messageID):
            if let index = history.messages.firstIndex(where: { $0.message.id == messageID }) {
                history.messages[index].message.pinned = true
            }
        case let .messageUnpinned(messageID):
            if let index = history.messages.firstIndex(where: { $0.message.id == messageID }) {
                history.messages[index].message.pinned = false
            }
        case let .unreadMarkerMoved(messageID):
            history.firstUnreadMessageID = messageID
            if let messageID {
                history.unreadRecoveryState = history.messages.contains { $0.message.id == messageID } ? .targetLoaded(messageID) : .targetUnloaded(messageID)
            } else {
                history.unreadRecoveryState = .none
            }
        case let .unreadRecoveryChanged(state):
            history.unreadRecoveryState = state
        case let .channelMarkedRead(lastReadMessageID):
            history.firstUnreadMessageID = nil
            history.unreadRecoveryState = .none
            if let lastReadMessageID {
                history.newestMessageID = lastReadMessageID
            }
        case let .referenceFetchStarted(messageID):
            history.pendingReferenceFetchMessageIDs.insert(messageID)
        case let .referenceFetchFinished(messageID):
            history.pendingReferenceFetchMessageIDs.remove(messageID)
        }
        history.messages = sortedCapped(history.messages)
        history.newestMessageID = history.messages.last?.message.id
        history.loadedRange.oldestLoadedMessageID = history.messages.first?.message.id
        history.loadedRange.newestLoadedMessageID = history.messages.last?.message.id
        return history
    }

    private static func loadedRange(
        for messages: [TimelineMessage],
        hasMoreBefore: Bool,
        hasMoreAfter: Bool,
        error: String?
    ) -> ChannelLoadedMessageRange {
        ChannelLoadedMessageRange(
            oldestLoadedMessageID: messages.first?.message.id,
            newestLoadedMessageID: messages.last?.message.id,
            hasMoreBefore: hasMoreBefore,
            hasMoreAfter: hasMoreAfter,
            lastPaginationError: error
        )
    }

    private func merge(current: [TimelineMessage], incoming messages: [Message]) -> [TimelineMessage] {
        var byID: [MessageID: TimelineMessage] = [:]
        let incomingNonces = Set(messages.compactMap(\.nonce))

        for timelineMessage in current {
            switch timelineMessage.status {
            case .pending, .failed, .retrying:
                if let nonce = timelineMessage.message.nonce, incomingNonces.contains(nonce) {
                    continue
                }
                byID[timelineMessage.message.id] = timelineMessage
            case .confirmed, .deleting:
                byID[timelineMessage.message.id] = timelineMessage
            }
        }

        for message in messages {
            byID[message.id] = TimelineMessage(message: message, status: .confirmed)
        }

        return sortedCapped(Array(byID.values))
    }

    private func replacingOrAppending(_ timelineMessage: TimelineMessage, in messages: [TimelineMessage]) -> [TimelineMessage] {
        var messages = messages
        if let index = messages.firstIndex(where: { $0.message.id == timelineMessage.message.id }) {
            messages[index] = timelineMessage
        } else if let nonce = timelineMessage.message.nonce,
                  let index = messages.firstIndex(where: { $0.message.nonce == nonce }) {
            messages[index] = timelineMessage
        } else {
            messages.append(timelineMessage)
        }
        return sortedCapped(messages)
    }

    private func sortedCapped(_ messages: [TimelineMessage]) -> [TimelineMessage] {
        let sorted = messages.sorted { lhs, rhs in
            if lhs.message.id == rhs.message.id { return false }
            return Self.messageIDChronologicalSort(lhs.message.id, rhs.message.id)
        }
        guard sorted.count > messageCapPerChannel else { return sorted }
        let local = sorted.filter(\.status.isLocalOnly)
        let confirmed = sorted.filter { !$0.status.isLocalOnly }
        let keptConfirmedCount = max(0, messageCapPerChannel - local.count)
        return (Array(confirmed.suffix(keptConfirmedCount)) + local).sorted {
            Self.messageIDChronologicalSort($0.message.id, $1.message.id)
        }
    }

    public static func messageIDChronologicalSort(_ lhs: MessageID, _ rhs: MessageID) -> Bool {
        let lhsDate = Message.dateFromULID(lhs.rawValue) ?? (lhs.rawValue.hasPrefix("pending-") ? .distantFuture : .distantPast)
        let rhsDate = Message.dateFromULID(rhs.rawValue) ?? (rhs.rawValue.hasPrefix("pending-") ? .distantFuture : .distantPast)
        if lhsDate == rhsDate {
            return lhs.rawValue < rhs.rawValue
        }
        return lhsDate < rhsDate
    }
}

public extension TimelineMessageStatus {
    var isLocalOnly: Bool {
        switch self {
        case .pending, .failed, .retrying:
            return true
        case .confirmed, .deleting:
            return false
        }
    }

    var failedMetadata: FailedMessageRecoveryMetadata? {
        switch self {
        case let .failed(metadata), let .retrying(metadata):
            return metadata
        case .confirmed, .pending, .deleting:
            return nil
        }
    }

    var isRetrying: Bool {
        if case .retrying = self { return true }
        return false
    }
}

public protocol ShellSnapshotSource: Sendable {
    var updates: AsyncStream<RealtimeSnapshotUpdate> { get }
    func currentSnapshot() async -> RealtimeSnapshot
}

public struct MockShellSnapshotSource: ShellSnapshotSource {
    private let snapshot: RealtimeSnapshot

    public init(snapshot: RealtimeSnapshot = MockShellData.snapshot) {
        self.snapshot = snapshot
    }

    public var updates: AsyncStream<RealtimeSnapshotUpdate> {
        AsyncStream { continuation in
            continuation.yield(
                RealtimeSnapshotUpdate(
                    snapshot: snapshot,
                    changes: RealtimeSnapshotChangeSet(isFullReplacement: true)
                )
            )
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

    public var updates: AsyncStream<RealtimeSnapshotUpdate> {
        store.updates
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
    func sendMessage(channelID: ChannelID, content: String, nonce: String?, replies: [MessageReply]?, attachments: [FileID]?) async throws -> Message
    func editMessage(channelID: ChannelID, messageID: MessageID, content: String) async throws -> Message
    func deleteMessage(channelID: ChannelID, messageID: MessageID) async throws
    func addReaction(channelID: ChannelID, messageID: MessageID, emoji: String) async throws
    func removeReaction(channelID: ChannelID, messageID: MessageID, emoji: String) async throws
    func pinMessage(channelID: ChannelID, messageID: MessageID) async throws
    func unpinMessage(channelID: ChannelID, messageID: MessageID) async throws
    func beginTyping(channelID: ChannelID) async throws
    func endTyping(channelID: ChannelID) async throws
}

public actor MockMessageActionHandler: MessageActionHandling {
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

    public init(currentUserID: UserID = MockShellData.currentUserID, sendError: (any Error & Sendable)? = nil) {
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

public actor LiveMessageActionHandler: MessageActionHandling {
    private let apiClient: any StoatAPIClient
    private let realtimeClient: any StoatRealtimeClient

    public init(apiClient: any StoatAPIClient, realtimeClient: any StoatRealtimeClient) {
        self.apiClient = apiClient
        self.realtimeClient = realtimeClient
    }

    public func sendMessage(channelID: ChannelID, content: String, nonce: String?, replies: [MessageReply]? = nil, attachments: [FileID]? = nil) async throws -> Message {
        try await apiClient.sendMessage(channelID: channelID, draft: MessageDraft(content: content.isEmpty ? nil : content, nonce: nonce, attachments: attachments, replies: replies))
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

    public func pinMessage(channelID: ChannelID, messageID: MessageID) async throws {
        try await apiClient.pinMessage(channelID: channelID, messageID: messageID)
    }

    public func unpinMessage(channelID: ChannelID, messageID: MessageID) async throws {
        try await apiClient.unpinMessage(channelID: channelID, messageID: messageID)
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

    public func sendMessage(channelID: ChannelID, content: String, nonce: String?, replies: [MessageReply]? = nil, attachments: [FileID]? = nil) async throws -> Message {
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

    public func pinMessage(channelID: ChannelID, messageID: MessageID) async throws {
        throw MessageActionError.unavailable(message)
    }

    public func unpinMessage(channelID: ChannelID, messageID: MessageID) async throws {
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
    public private(set) var historiesByChannelID: [ChannelID: ChannelMessageHistory]
    public private(set) var sendingChannelIDs: Set<ChannelID>
    public private(set) var retryingMessageIDs: Set<MessageID>
    public private(set) var lastErrorByChannelID: [ChannelID: String]

    @ObservationIgnored private var apiClient: (any StoatAPIClient)?
    @ObservationIgnored private var runtimeMode: AppRuntimeMode
    @ObservationIgnored private var currentUserID: UserID?
    @ObservationIgnored private let pageSize: Int
    @ObservationIgnored private let messageCapPerChannel: Int
    @ObservationIgnored private var reducer: ChannelMessageHistoryReducer
    @ObservationIgnored private var initialLoadTokens: [ChannelID: UUID] = [:]
    @ObservationIgnored private var paginationLoadTokens: [ChannelID: UUID] = [:]
    @ObservationIgnored private var initialLoadInFlightChannelIDs: Set<ChannelID> = []
    @ObservationIgnored private var completedInitialLoadChannelIDs: Set<ChannelID> = []
    @ObservationIgnored private var configuredLoadGeneration: Int?
    @ObservationIgnored private var presentationRevisionsByChannelID: [ChannelID: Int] = [:]
    @ObservationIgnored private var messageCache: any ChannelMessageCaching = NoopChannelMessageCache()

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
        self.reducer = ChannelMessageHistoryReducer(messageCapPerChannel: messageCapPerChannel)
        self.statesByChannelID = [:]
        self.historiesByChannelID = [:]
        self.sendingChannelIDs = []
        self.retryingMessageIDs = []
        self.lastErrorByChannelID = [:]
    }

    public func configure(
        runtimeMode: AppRuntimeMode,
        apiClient: (any StoatAPIClient)?,
        currentUserID: UserID?,
        loadGeneration: Int? = nil,
        messageCache: (any ChannelMessageCaching)? = nil
    ) {
        self.messageCache = messageCache ?? NoopChannelMessageCache()
        let identityScopeChanged = self.runtimeMode != runtimeMode
            || self.currentUserID != currentUserID
        let loadScopeChanged = identityScopeChanged
            || (self.apiClient == nil) != (apiClient == nil)
            || configuredLoadGeneration != loadGeneration
        if identityScopeChanged {
            statesByChannelID.removeAll()
            historiesByChannelID.removeAll()
            sendingChannelIDs.removeAll()
            retryingMessageIDs.removeAll()
            lastErrorByChannelID.removeAll()
            presentationRevisionsByChannelID.removeAll()
        }
        if loadScopeChanged {
            initialLoadTokens.removeAll()
            paginationLoadTokens.removeAll()
            initialLoadInFlightChannelIDs.removeAll()
            completedInitialLoadChannelIDs.removeAll()
        }
        self.runtimeMode = runtimeMode
        self.apiClient = apiClient
        self.currentUserID = currentUserID
        configuredLoadGeneration = loadGeneration
    }

    public func reset() {
        Task { [messageCache] in
            await messageCache.removeAll()
        }
        statesByChannelID.removeAll()
        historiesByChannelID.removeAll()
        sendingChannelIDs.removeAll()
        retryingMessageIDs.removeAll()
        lastErrorByChannelID.removeAll()
        initialLoadTokens.removeAll()
        paginationLoadTokens.removeAll()
        initialLoadInFlightChannelIDs.removeAll()
        completedInitialLoadChannelIDs.removeAll()
        configuredLoadGeneration = nil
        presentationRevisionsByChannelID.removeAll()
    }

    public func presentationRevision(for channelID: ChannelID?) -> Int {
        guard let channelID else { return 0 }
        return presentationRevisionsByChannelID[channelID, default: 0]
    }

    public func state(for channelID: ChannelID?) -> ChannelMessageState {
        guard let channelID else { return .idle }
        return historiesByChannelID[channelID]?.state ?? statesByChannelID[channelID] ?? .idle
    }

    public func hydrate(from snapshot: RealtimeSnapshot) {
        for (channelID, messages) in snapshot.messagesByChannelID {
            mergeSnapshotMessages(messages, channelID: channelID)
        }
    }

    public func hydrate(channelIDs: Set<ChannelID>, from snapshot: RealtimeSnapshot) {
        for channelID in channelIDs {
            mergeSnapshotMessages(snapshot.messagesByChannelID[channelID] ?? [], channelID: channelID)
        }
    }

    @discardableResult
    public func loadInitialIfNeeded(channelID: ChannelID, snapshotMessages: [Message]) async -> ChannelMessageLoadOutcome {
        if !snapshotMessages.isEmpty {
            mergeSnapshotMessages(snapshotMessages, channelID: channelID)
        }
        if completedInitialLoadChannelIDs.contains(channelID) {
            return .alreadyLoaded(messageCount: state(for: channelID).timelineMessages.count)
        }
        if initialLoadInFlightChannelIDs.contains(channelID) {
            return .deduplicated
        }
        return await performInitialLoad(channelID: channelID, snapshotMessages: snapshotMessages, force: false)
    }

    @discardableResult
    public func loadInitialMessages(channelID: ChannelID, snapshotMessages: [Message]) async -> ChannelMessageLoadOutcome {
        await performInitialLoad(channelID: channelID, snapshotMessages: snapshotMessages, force: true)
    }

    private func performInitialLoad(
        channelID: ChannelID,
        snapshotMessages: [Message],
        force: Bool
    ) async -> ChannelMessageLoadOutcome {
        if !force, initialLoadInFlightChannelIDs.contains(channelID) {
            return .deduplicated
        }
        let token = UUID()
        initialLoadTokens[channelID] = token
        initialLoadInFlightChannelIDs.insert(channelID)
        lastErrorByChannelID[channelID] = nil
        defer {
            if initialLoadTokens[channelID] == token {
                initialLoadInFlightChannelIDs.remove(channelID)
            }
        }

        if shouldUseLiveAPI, let apiClient {
            mergeSnapshotMessages(snapshotMessages, channelID: channelID)
            if state(for: channelID).timelineMessages.isEmpty {
                let cached = await messageCache.messages(for: channelID)
                guard initialLoadTokens[channelID] == token else { return .cancelled }
                if !cached.isEmpty {
                    mergeSnapshotMessages(cached, channelID: channelID)
                }
            }
            apply(.initialLoadStarted, channelID: channelID)
            var cachedHistory = history(for: channelID)
            cachedHistory.hasMoreBefore = true
            setHistory(cachedHistory)
            do {
                let fetched = try await apiClient.fetchMessages(channelID: channelID, before: nil, after: nil, limit: pageSize)
                guard initialLoadTokens[channelID] == token else { return .cancelled }
                apply(.initialLoadSucceeded(messages: fetched, hasMoreBefore: fetched.count >= pageSize, loadedAt: Date()), channelID: channelID)
                completedInitialLoadChannelIDs.insert(channelID)
                lastErrorByChannelID[channelID] = nil
                return .loaded(messageCount: state(for: channelID).timelineMessages.count)
            } catch {
                guard initialLoadTokens[channelID] == token else { return .cancelled }
                if error is CancellationError || Task.isCancelled {
                    apply(.initialLoadCancelled, channelID: channelID)
                    return .cancelled
                }
                let message = error.userFacingMessage
                apply(.initialLoadFailed(message), channelID: channelID)
                lastErrorByChannelID[channelID] = message
                return .failed(message: message, cachedMessageCount: state(for: channelID).timelineMessages.count)
            }
        }

        apply(.initialLoadSucceeded(messages: snapshotMessages, hasMoreBefore: false, loadedAt: Date()), channelID: channelID)
        completedInitialLoadChannelIDs.insert(channelID)
        lastErrorByChannelID[channelID] = nil
        return .loaded(messageCount: state(for: channelID).timelineMessages.count)
    }

    @discardableResult
    public func loadOlderMessages(channelID: ChannelID) async -> Bool {
        guard shouldUseLiveAPI, let apiClient else { return false }
        let current = state(for: channelID).timelineMessages
        guard let before = current.map(\.message.id).sorted(by: messageIDChronologicalSort).first else { return false }

        let token = UUID()
        paginationLoadTokens[channelID] = token
        apply(.olderLoadStarted, channelID: channelID)

        do {
            let fetched = try await apiClient.fetchMessages(channelID: channelID, before: before, after: nil, limit: pageSize)
            guard paginationLoadTokens[channelID] == token else { return false }
            apply(.olderLoadSucceeded(messages: fetched, hasMoreBefore: fetched.count >= pageSize, loadedAt: Date()), channelID: channelID)
            lastErrorByChannelID[channelID] = nil
            return true
        } catch {
            guard paginationLoadTokens[channelID] == token else { return false }
            if error is CancellationError || Task.isCancelled {
                apply(.olderLoadCancelled, channelID: channelID)
                return false
            }
            apply(.olderLoadFailed(error.userFacingMessage), channelID: channelID)
            lastErrorByChannelID[channelID] = error.userFacingMessage
            return false
        }
    }

    @discardableResult
    public func loadMessagesAround(channelID: ChannelID, targetMessageID: MessageID, limit: Int? = nil) async -> Bool {
        guard shouldUseLiveAPI, let apiClient else { return false }
        let token = UUID()
        paginationLoadTokens[channelID] = token
        apply(.olderLoadStarted, channelID: channelID)

        do {
            let fetched = try await apiClient.fetchMessages(
                channelID: channelID,
                options: MessageFetchOptions(nearby: targetMessageID, limit: limit ?? pageSize)
            )
            guard paginationLoadTokens[channelID] == token else { return false }
            let hasMoreBefore = history(for: channelID).hasMoreBefore
            apply(.olderLoadSucceeded(messages: fetched, hasMoreBefore: hasMoreBefore, loadedAt: Date()), channelID: channelID)
            var updated = history(for: channelID)
            updated.loadedRange.loadedAroundMessageID = targetMessageID
            setHistory(updated)
            lastErrorByChannelID[channelID] = nil
            return true
        } catch {
            guard paginationLoadTokens[channelID] == token else { return false }
            if error is CancellationError || Task.isCancelled {
                apply(.olderLoadCancelled, channelID: channelID)
                return false
            }
            apply(.olderLoadFailed(error.userFacingMessage), channelID: channelID)
            lastErrorByChannelID[channelID] = error.userFacingMessage
            return false
        }
    }

    @discardableResult
    public func loadOlderMessagesToTarget(channelID: ChannelID, targetMessageID: MessageID, maxAttempts: Int = 4) async -> UnreadRecoveryState {
        guard maxAttempts > 0 else {
            let state: UnreadRecoveryState = .failed(targetMessageID, "Could not load older messages.")
            apply(.unreadRecoveryChanged(state), channelID: channelID)
            return state
        }
        for attempt in 1...maxAttempts {
            if state(for: channelID).timelineMessages.contains(where: { $0.message.id == targetMessageID }) {
                let state: UnreadRecoveryState = .targetLoaded(targetMessageID)
                apply(.unreadRecoveryChanged(state), channelID: channelID)
                return state
            }
            apply(.unreadRecoveryChanged(.loadingToTarget(targetMessageID, attempts: attempt)), channelID: channelID)
            let loaded = await loadOlderMessages(channelID: channelID)
            guard loaded else {
                let state: UnreadRecoveryState = .failed(targetMessageID, lastErrorByChannelID[channelID] ?? "Could not load older messages.")
                apply(.unreadRecoveryChanged(state), channelID: channelID)
                return state
            }
            if !history(for: channelID).hasMoreBefore,
               !state(for: channelID).timelineMessages.contains(where: { $0.message.id == targetMessageID }) {
                let state: UnreadRecoveryState = .targetMissing(targetMessageID)
                apply(.unreadRecoveryChanged(state), channelID: channelID)
                return state
            }
        }
        if state(for: channelID).timelineMessages.contains(where: { $0.message.id == targetMessageID }) {
            let state: UnreadRecoveryState = .targetLoaded(targetMessageID)
            apply(.unreadRecoveryChanged(state), channelID: channelID)
            return state
        }
        let state: UnreadRecoveryState = .targetUnloaded(targetMessageID)
        apply(.unreadRecoveryChanged(state), channelID: channelID)
        return state
    }

    @discardableResult
    public func refreshMessages(channelID: ChannelID, snapshotMessages: [Message]) async -> ChannelMessageLoadOutcome {
        await performInitialLoad(channelID: channelID, snapshotMessages: snapshotMessages, force: true)
    }

    public func sendMessage(
        channelID: ChannelID,
        content: String,
        replies: [MessageReply]? = nil,
        attachments: [FileID] = [],
        attachmentFiles: [File] = [],
        handler: any MessageActionHandling
    ) async -> Bool {
        guard let currentUserID else {
            apply(.initialLoadFailed(MessageActionError.missingCurrentUser.userFacingMessage), channelID: channelID)
            return false
        }

        let nonce = UUID().uuidString
        let pending = TimelineMessage(
            message: Message(
                id: MessageID(rawValue: "pending-\(nonce)"),
                channelID: channelID,
                authorID: currentUserID,
                content: content,
                nonce: nonce,
                attachments: attachmentFiles.isEmpty ? nil : attachmentFiles,
                replies: replies?.map(\.id)
            ),
            status: .pending
        )
        apply(.optimisticSendCreated(pending), channelID: channelID)
        sendingChannelIDs.insert(channelID)

        do {
            let confirmed = try await handler.sendMessage(channelID: channelID, content: content, nonce: nonce, replies: replies, attachments: attachments.isEmpty ? nil : attachments)
            sendingChannelIDs.remove(channelID)
            apply(.sendConfirmed(message: confirmed, nonce: nonce), channelID: channelID)
            lastErrorByChannelID[channelID] = nil
            return true
        } catch {
            sendingChannelIDs.remove(channelID)
            apply(.sendFailed(nonce: nonce, error: error.userFacingMessage), channelID: channelID)
            if let failedID = state(for: channelID).timelineMessages.first(where: { $0.message.nonce == nonce })?.message.id,
               let reply = replies?.first,
               let failed = state(for: channelID).timelineMessages.first(where: { $0.message.id == failedID }),
               case let .failed(metadata) = failed.status {
                var updated = metadata
                updated.attachmentIDs = attachments
                updated.attachmentFiles = attachmentFiles
                updated.replyContext = ReplyContext(channelID: channelID, messageID: reply.id, authorDisplayName: "Original message", contentPreview: "Original message unavailable")
                updated.mentionReply = reply.mention
                apply(.failedRecoveryEdited(messageID: failedID, content: updated.originalContent), channelID: channelID)
                setFailedMetadata(updated, messageID: failedID, channelID: channelID)
            } else if let failedID = state(for: channelID).timelineMessages.first(where: { $0.message.nonce == nonce })?.message.id,
                      let failed = state(for: channelID).timelineMessages.first(where: { $0.message.id == failedID }),
                      case var .failed(metadata) = failed.status {
                metadata.attachmentIDs = attachments
                metadata.attachmentFiles = attachmentFiles
                setFailedMetadata(metadata, messageID: failedID, channelID: channelID)
            }
            lastErrorByChannelID[channelID] = error.userFacingMessage
            return false
        }
    }

    public func retrySend(_ timelineMessage: TimelineMessage, handler: any MessageActionHandling) async -> Bool {
        guard let metadata = timelineMessage.status.failedMetadata,
              !retryingMessageIDs.contains(timelineMessage.message.id)
        else {
            return false
        }
        let channelID = timelineMessage.message.channelID
        retryingMessageIDs.insert(timelineMessage.message.id)
        apply(.retryStarted(messageID: timelineMessage.message.id), channelID: channelID)
        let nonce = UUID().uuidString
        let replies = metadata.replyContext.map { [MessageReply(id: $0.messageID, mention: metadata.mentionReply)] }
        do {
            let confirmed = try await handler.sendMessage(channelID: channelID, content: metadata.originalContent, nonce: nonce, replies: replies, attachments: metadata.attachmentIDs.isEmpty ? nil : metadata.attachmentIDs)
            retryingMessageIDs.remove(timelineMessage.message.id)
            apply(.discardLocalMessage(timelineMessage.message.id), channelID: channelID)
            apply(.sendConfirmed(message: confirmed, nonce: nonce), channelID: channelID)
            lastErrorByChannelID[channelID] = nil
            return true
        } catch {
            retryingMessageIDs.remove(timelineMessage.message.id)
            apply(.retryFailed(messageID: timelineMessage.message.id, error: error.userFacingMessage), channelID: channelID)
            lastErrorByChannelID[channelID] = error.userFacingMessage
            return false
        }
    }

    public func markRetryStarted(_ timelineMessage: TimelineMessage) {
        apply(.retryStarted(messageID: timelineMessage.message.id), channelID: timelineMessage.message.channelID)
    }

    public func discardLocalMessage(_ timelineMessage: TimelineMessage) {
        apply(.discardLocalMessage(timelineMessage.message.id), channelID: timelineMessage.message.channelID)
    }

    public func updateFailedRecoveryContent(messageID: MessageID, channelID: ChannelID, content: String) {
        apply(.failedRecoveryEdited(messageID: messageID, content: content), channelID: channelID)
    }

    public func updateUnreadRecovery(channelID: ChannelID, state: UnreadRecoveryState) {
        apply(.unreadRecoveryChanged(state), channelID: channelID)
    }

    public func markReferenceFetchStarted(channelID: ChannelID, messageID: MessageID) {
        apply(.referenceFetchStarted(messageID), channelID: channelID)
    }

    public func markReferenceFetchFinished(channelID: ChannelID, messageID: MessageID) {
        apply(.referenceFetchFinished(messageID), channelID: channelID)
    }

    public func applyEditedMessage(_ message: Message) {
        apply(.messageUpdated(message), channelID: message.channelID)
    }

    public func removeMessage(channelID: ChannelID, messageID: MessageID) {
        apply(.messageDeleted(messageID), channelID: channelID)
    }

    public func applyReaction(channelID: ChannelID, messageID: MessageID, emoji: String, userID: UserID, isAdding: Bool) {
        apply(.reactionChanged(messageID: messageID, emoji: emoji, userID: userID, isAdding: isAdding), channelID: channelID)
    }

    public func applyPinState(channelID: ChannelID, messageID: MessageID, isPinned: Bool) {
        apply(isPinned ? .messagePinned(messageID) : .messageUnpinned(messageID), channelID: channelID)
    }

    public func moveUnreadMarker(channelID: ChannelID, messageID: MessageID?) {
        apply(.unreadMarkerMoved(messageID), channelID: channelID)
    }

    public func markRead(channelID: ChannelID, lastReadMessageID: MessageID?) {
        apply(.channelMarkedRead(lastReadMessageID: lastReadMessageID), channelID: channelID)
    }

    private var shouldUseLiveAPI: Bool {
        runtimeMode == .liveManual && apiClient != nil
    }

    private func history(for channelID: ChannelID) -> ChannelMessageHistory {
        if let history = historiesByChannelID[channelID] {
            return history
        }
        return ChannelMessageHistory(channelID: channelID)
    }

    private func setHistory(_ history: ChannelMessageHistory) {
        historiesByChannelID[history.channelID] = history
        statesByChannelID[history.channelID] = history.state
        presentationRevisionsByChannelID[history.channelID, default: 0] &+= 1
    }

    private func apply(_ event: ChannelMessageHistoryEvent, channelID: ChannelID) {
        let persistMode = persistMode(for: event)
        let confirmedIDsBefore = persistMode == .ifChanged ? confirmedPersistableMessages(for: channelID).map(\.id) : nil
        setHistory(reducer.reduce(history(for: channelID), event: event))
        switch persistMode {
        case .never:
            return
        case .always:
            persistHistory(for: channelID)
        case .ifChanged:
            if confirmedIDsBefore != confirmedPersistableMessages(for: channelID).map(\.id) {
                persistHistory(for: channelID)
            }
        }
    }

    private enum HistoryPersistMode {
        case never
        case always
        case ifChanged
    }

    private func persistMode(for event: ChannelMessageHistoryEvent) -> HistoryPersistMode {
        switch event {
        case .initialLoadSucceeded, .realtimeMessageReceived, .sendConfirmed, .messageUpdated, .messageDeleted, .reactionChanged:
            .always
        case .snapshotMerged:
            .ifChanged
        default:
            .never
        }
    }

    private func confirmedPersistableMessages(for channelID: ChannelID) -> [Message] {
        history(for: channelID).messages.compactMap { timelineMessage in
            switch timelineMessage.status {
            case .confirmed:
                timelineMessage.message
            case .deleting, .pending, .failed, .retrying:
                nil
            }
        }
    }

    private func persistHistory(for channelID: ChannelID) {
        guard shouldUseLiveAPI else { return }
        let messages = confirmedPersistableMessages(for: channelID)
        guard !messages.isEmpty else { return }
        Task { [messageCache] in
            await messageCache.store(messages, for: channelID)
        }
    }

    private func setFailedMetadata(_ metadata: FailedMessageRecoveryMetadata, messageID: MessageID, channelID: ChannelID) {
        var history = history(for: channelID)
        if let index = history.messages.firstIndex(where: { $0.message.id == messageID }) {
            history.messages[index].status = .failed(metadata)
            setHistory(history)
        }
    }

    private func mergeSnapshotMessages(_ messages: [Message], channelID: ChannelID) {
        let hadMessages = !state(for: channelID).timelineMessages.isEmpty
        apply(.snapshotMerged(messages), channelID: channelID)
        if !hadMessages {
            var history = history(for: channelID)
            history.hasMoreBefore = shouldUseLiveAPI
            setHistory(history)
        }
    }

    private func merge(current: [TimelineMessage], incoming messages: [Message]) -> [TimelineMessage] {
        var byID: [MessageID: TimelineMessage] = [:]
        var incomingNonces = Set(messages.compactMap(\.nonce))

        for timelineMessage in current {
            switch timelineMessage.status {
            case .confirmed, .deleting:
                byID[timelineMessage.message.id] = timelineMessage
            case .pending, .failed, .retrying:
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
        let message = messages[index].message
        messages[index].status = .failed(FailedMessageRecoveryMetadata(originalContent: message.content ?? "", originalNonce: nonce, attachmentIDs: message.attachments?.map(\.id) ?? [], attachmentFiles: message.attachments ?? [], lastError: error))
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
    public private(set) var loginFlowState: LoginFlowState
    public private(set) var loginDiagnostics: LoginDiagnostics
    public private(set) var startupAuthDiagnostics: StartupAuthDiagnostics
    public private(set) var autoConnectAttemptCount: Int

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
    @ObservationIgnored private var liveFirstStartupAttemptedEnvironmentIDs: Set<String>

    public var coalescedRealtimeUpdateCount: Int {
        realtimeStore?.coalescedUpdateCount ?? 0
    }

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
        self.mode = .liveManual
        self.sessionState = .signedOut
        self.connectionState = .idle
        self.snapshot = RealtimeSnapshot()
        self.currentUser = nil
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
        self.loginFlowState = .idle
        self.loginDiagnostics = LoginDiagnostics()
        self.startupAuthDiagnostics = StartupAuthDiagnostics()
        self.autoConnectAttemptCount = 0
        self.liveFirstStartupAttemptedEnvironmentIDs = []
        self.snapshotSource = MockShellSnapshotSource(snapshot: RealtimeSnapshot())
        self.messageActionHandler = UnavailableMessageActionHandler(message: "Set up a session before sending messages.")
    }

    deinit {
        eventTask?.cancel()
        connectionTask?.cancel()
        diagnosticsTask?.cancel()
    }

    public func startMockSession() async {
        await startMockSession(loadStoredPreferences: true)
    }

    public func startLiveFirstSession() async {
        startupAuthDiagnostics.startupInvocationCount += 1
        await loadPreferences()
        startupAuthDiagnostics.lastEnvironmentKind = startupDiagnosticEnvironmentKind(environment)
        let environmentID = environment.stableID
        guard !liveFirstStartupAttemptedEnvironmentIDs.contains(environmentID) else {
            startupAuthDiagnostics.startupSkippedCount += 1
            startupAuthDiagnostics.lastStartupAction = "startup_auto_connect"
            startupAuthDiagnostics.lastStartupResult = "already_attempted_for_environment"
            return
        }
        liveFirstStartupAttemptedEnvironmentIDs.insert(environmentID)
        await disconnectActiveRealtime()
        mode = .liveManual
        connectionState = .idle
        diagnostics = nil
        lastErrorMessage = nil
        validatedSession = nil
        pendingValidatedSession = nil
        mfaChallenge = nil
        currentUser = nil
        apiClient = nil
        messageActionHandler = UnavailableMessageActionHandler(message: "Set up a session before sending messages.")
        verificationState = LiveVerificationState()
        installLiveSafeSnapshot()
        await refreshCredentialAvailability()
        if case .keychainFailed = sessionState {
            startupAuthDiagnostics.lastStartupAction = "startup_auto_connect"
            startupAuthDiagnostics.lastStartupResult = "keychain_failed"
            startupAuthDiagnostics.lastErrorCategory = .keychainError
            return
        }
        guard hasSavedCredential else {
            sessionState = .signedOut
            startupAuthDiagnostics.lastStartupAction = "startup_auto_connect"
            startupAuthDiagnostics.lastStartupResult = "no_saved_credential"
            return
        }
        autoConnectAttemptCount += 1
        startupAuthDiagnostics.startupAutoConnectAttemptCount = autoConnectAttemptCount
        startupAuthDiagnostics.lastStartupAction = "startup_auto_connect"
        startupAuthDiagnostics.lastStartupResult = "attempting"
        await connectLive(source: .startupAuto)
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
            let message = StartupAuthDiagnosticsRedactor.redact("Could not load preferences: \(error.userFacingMessage)")
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
            let message = StartupAuthDiagnosticsRedactor.redact("Could not save preferences: \(error.userFacingMessage)")
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
            let message = StartupAuthDiagnosticsRedactor.redact("Could not update preferences: \(error.userFacingMessage)")
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
            let message = StartupAuthDiagnosticsRedactor.redact("Could not read saved credential: \(error.userFacingMessage)")
            lastErrorMessage = message
            sessionState = .keychainFailed(message)
            startupAuthDiagnostics.lastErrorCategory = .keychainError
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
            let message = StartupAuthDiagnosticsRedactor.redact("Custom environment is invalid: \(error.userFacingMessage)")
            sessionState = .validationFailed(message)
            lastErrorMessage = message
            startupAuthDiagnostics.lastErrorCategory = .environmentError
        }
    }

    public func selectEnvironmentProfile(id: String) async {
        guard let profile = preferences.environmentProfiles.first(where: { $0.id == id }) else {
            let message = "Environment profile was not found."
            sessionState = .validationFailed(message)
            lastErrorMessage = message
            startupAuthDiagnostics.lastErrorCategory = .environmentError
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
            let message = StartupAuthDiagnosticsRedactor.redact("Could not save environment profile: \(error.userFacingMessage)")
            sessionState = .validationFailed(message)
            lastErrorMessage = message
            startupAuthDiagnostics.lastErrorCategory = .environmentError
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
            let message = StartupAuthDiagnosticsRedactor.redact("Could not delete environment profile: \(error.userFacingMessage)")
            sessionState = .validationFailed(message)
            lastErrorMessage = message
            startupAuthDiagnostics.lastErrorCategory = .environmentError
        }
    }

    public func validateImportedToken(_ token: String, localLabel: String? = nil) async {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        mode = .liveManual
        sessionState = .validatingCredential
        loginFlowState = .submitting
        lastErrorMessage = nil
        pendingValidatedSession = nil
        mfaChallenge = nil
        loginDiagnostics.attemptCount += 1
        loginDiagnostics.lastAttemptAt = Date()
        startupAuthDiagnostics.lastAuthAction = "token_import"
        startupAuthDiagnostics.lastAuthResult = "validating"
        do {
            let session = try await sessionValidator.validate(credential: .sessionToken(trimmed), environment: environment)
            await completeValidatedSessionAndConnect(session, localLabel: localLabel, authAction: "token_import")
        } catch {
            let message = StartupAuthDiagnosticsRedactor.redact(error.userFacingMessage)
            pendingValidatedSession = nil
            currentUser = nil
            sessionState = sessionFailureState(for: error, fallback: message)
            lastErrorMessage = message
            let category = loginErrorCategory(for: error)
            loginDiagnostics.lastErrorCategory = category
            startupAuthDiagnostics.lastErrorCategory = category
            startupAuthDiagnostics.lastAuthResult = "failed_\(loginErrorCategoryName(category))"
            loginFlowState = .idle
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
            startupAuthDiagnostics.lastAuthResult = "saved"
        } catch {
            let message = StartupAuthDiagnosticsRedactor.redact("Could not save credential to Keychain: \(error.userFacingMessage)")
            sessionState = .keychainFailed(message)
            lastErrorMessage = message
            loginDiagnostics.lastErrorCategory = .keychainError
            startupAuthDiagnostics.lastErrorCategory = .keychainError
            startupAuthDiagnostics.lastAuthResult = "failed_keychain_error"
            loginFlowState = .idle
        }
    }

    public func finishValidatedSessionAndConnect() async {
        guard pendingValidatedSession != nil else { return }
        await savePendingValidatedSession()
        guard case .readyToConnect = sessionState else { return }
        loginFlowState = .succeeded
        await connectLive(source: .userInitiated)
    }

    public func validateSavedSession() async {
        mode = .liveManual
        sessionState = .loadingCredential
        lastErrorMessage = nil
        startupAuthDiagnostics.lastAuthAction = "saved_session_validation"
        startupAuthDiagnostics.lastAuthResult = "loading_credential"
        do {
            guard let credential = try await loadCredentialForCurrentEnvironment() else {
                hasSavedCredential = false
                verificationState.credentialLoaded = false
                sessionState = .signedOut
                currentUser = nil
                installLiveSafeSnapshot()
                startupAuthDiagnostics.lastAuthResult = "missing_credential"
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
            startupAuthDiagnostics.lastAuthResult = "validated_ready"
        } catch {
            let message = StartupAuthDiagnosticsRedactor.redact(error.userFacingMessage)
            validatedSession = nil
            currentUser = nil
            sessionState = sessionFailureState(for: error, fallback: message)
            lastErrorMessage = message
            let category = loginErrorCategory(for: error)
            startupAuthDiagnostics.lastErrorCategory = category
            startupAuthDiagnostics.lastAuthResult = "failed_\(loginErrorCategoryName(category))"
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
        loginFlowState = .submitting
        lastErrorMessage = nil
        mfaChallenge = nil
        pendingValidatedSession = nil
        loginDiagnostics.attemptCount += 1
        loginDiagnostics.lastAttemptAt = Date()
        startupAuthDiagnostics.lastAuthAction = "email_password_login"
        startupAuthDiagnostics.lastAuthResult = "submitting"
        let client = apiClientFactory(environment, StaticCredentialProvider(nil))
        do {
            let response = try await client.login(request: SessionLoginRequest(email: email, password: password, friendlyName: friendlyName))
            await handleLoginResponse(response, friendlyName: friendlyName)
        } catch {
            let message = StartupAuthDiagnosticsRedactor.redact("Login failed: \(error.userFacingMessage)")
            sessionState = .validationFailed(message)
            lastErrorMessage = message
            let category = loginErrorCategory(for: error)
            loginDiagnostics.lastErrorCategory = category
            startupAuthDiagnostics.lastErrorCategory = category
            startupAuthDiagnostics.lastAuthResult = "failed_\(loginErrorCategoryName(category))"
            loginFlowState = .idle
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
        loginFlowState = .submitting
        lastErrorMessage = nil
        loginDiagnostics.attemptCount += 1
        loginDiagnostics.lastAttemptAt = Date()
        startupAuthDiagnostics.lastAuthAction = "mfa_continuation"
        startupAuthDiagnostics.lastAuthResult = "submitting"
        let client = apiClientFactory(environment, StaticCredentialProvider(nil))
        do {
            let response = try await client.continueLogin(
                request: SessionMFALoginRequest(mfaTicket: mfaChallenge.ticket, mfaResponse: response, friendlyName: friendlyName)
            )
            await handleLoginResponse(response, friendlyName: friendlyName)
        } catch {
            let message = StartupAuthDiagnosticsRedactor.redact("MFA login failed: \(error.userFacingMessage)")
            sessionState = .validationFailed(message)
            lastErrorMessage = message
            loginDiagnostics.lastErrorCategory = .mfaFailed
            startupAuthDiagnostics.lastErrorCategory = .mfaFailed
            startupAuthDiagnostics.lastAuthResult = "failed_mfa_failed"
            loginFlowState = .mfaRequired
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
                await completeValidatedSessionAndConnect(session, localLabel: friendlyName, authAction: startupAuthDiagnostics.lastAuthAction ?? "login")
            } catch {
                let message = StartupAuthDiagnosticsRedactor.redact("Login succeeded, but validation failed: \(error.userFacingMessage)")
                sessionState = sessionFailureState(for: error, fallback: message)
                lastErrorMessage = message
                let category = loginErrorCategory(for: error)
                loginDiagnostics.lastErrorCategory = category
                startupAuthDiagnostics.lastErrorCategory = category
                startupAuthDiagnostics.lastAuthResult = "failed_\(loginErrorCategoryName(category))"
                loginFlowState = .idle
            }
        case let .mfa(ticket, allowedMethods):
            mfaChallenge = LoginMFAChallenge(ticket: ticket, allowedMethods: allowedMethods)
            sessionState = .validationFailed("Multi-factor authentication is required.")
            lastErrorMessage = nil
            loginFlowState = .mfaRequired
            startupAuthDiagnostics.lastAuthResult = "mfa_required"
        case let .disabled(userID):
            let message = "This account is disabled or unavailable. User ID: \(UserDisplayResolver.shortenedID(userID))"
            sessionState = .validationFailed(message)
            lastErrorMessage = message
            loginDiagnostics.lastErrorCategory = .accountDisabled
            startupAuthDiagnostics.lastErrorCategory = .accountDisabled
            startupAuthDiagnostics.lastAuthResult = "failed_account_disabled"
            loginFlowState = .idle
        }
    }

    private func completeValidatedSessionAndConnect(_ session: ValidatedSession, localLabel: String?, authAction: String) async {
        pendingValidatedSession = session
        currentUser = session.currentUser
        localSessionLabel = localLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        verificationState.currentUserFetched = true
        sessionState = .validatedReady
        startupAuthDiagnostics.lastAuthAction = authAction
        startupAuthDiagnostics.lastAuthResult = "validated"
        await savePendingValidatedSession()
        guard case .readyToConnect = sessionState else { return }
        loginFlowState = .succeeded
        await connectLive(source: .userInitiated)
    }

    public func connectLiveManually() async {
        await connectLive(source: .userInitiated)
    }

    public func reconnectLiveManually() async {
        await connectLive(source: .retry)
    }

    private enum LiveConnectSource: Hashable, Sendable {
        case startupAuto
        case userInitiated
        case retry

        var failurePrefix: String {
            switch self {
            case .startupAuto:
                return "Automatic connection failed"
            case .userInitiated, .retry:
                return "Live connection failed"
            }
        }

        var diagnosticsAction: String {
            switch self {
            case .startupAuto:
                return "startup_auto_connect"
            case .userInitiated:
                return "connect"
            case .retry:
                return "retry_connect"
            }
        }
    }

    private func connectLive(source: LiveConnectSource) async {
        await disconnectActiveRealtime()
        mode = .liveManual
        sessionState = .loadingCredential
        connectionState = .idle
        diagnostics = nil
        lastErrorMessage = nil
        startupAuthDiagnostics.lastAuthAction = source.diagnosticsAction
        startupAuthDiagnostics.lastAuthResult = "loading_credential"

        let credential: StoatAuthCredential
        do {
            guard let loaded = try await loadCredentialForCurrentEnvironment() else {
                hasSavedCredential = false
                sessionState = .signedOut
                installLiveSafeSnapshot()
                startupAuthDiagnostics.lastAuthResult = "missing_credential"
                return
            }
            credential = loaded
            hasSavedCredential = true
            verificationState.credentialLoaded = true
            sessionState = validatedSession == nil ? .validatingCredential : .readyToConnect
        } catch {
            hasSavedCredential = false
            let message = StartupAuthDiagnosticsRedactor.redact("Could not load saved credential: \(error.userFacingMessage)")
            sessionState = .keychainFailed(message)
            startupAuthDiagnostics.lastErrorCategory = .keychainError
            startupAuthDiagnostics.lastAuthResult = "failed_keychain_error"
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
            let validation: ValidatedSession
            if let existing = validatedSession,
               existing.credential == credential,
               existing.environment == environment {
                validation = existing
            } else {
                validation = try await sessionValidator.validate(credential: credential, environment: environment)
            }
            validatedSession = validation
            currentUser = validation.currentUser
            verificationState.currentUserFetched = true
            startupAuthDiagnostics.lastAuthResult = "connecting_realtime"
            try await realtimeClient.connect(credential: credential, environment: environment, readyFields: readyFields)
            startupAuthDiagnostics.lastAuthResult = "realtime_connect_started"
            if source == .startupAuto {
                startupAuthDiagnostics.lastStartupResult = "realtime_connect_started"
            }
        } catch {
            await disconnectActiveRealtime()
            let message = StartupAuthDiagnosticsRedactor.redact("\(source.failurePrefix): \(error.userFacingMessage)")
            sessionState = .connectionFailed(message)
            let category = loginErrorCategory(for: error)
            startupAuthDiagnostics.lastErrorCategory = category
            startupAuthDiagnostics.lastAuthResult = "failed_\(loginErrorCategoryName(category))"
            if source == .startupAuto {
                startupAuthDiagnostics.lastStartupResult = "failed_\(loginErrorCategoryName(category))"
            }
            failLiveSession(message, replaceConnectionState: true)
        }
    }

    public func disconnectLive() async {
        await disconnectActiveRealtime()
        mode = .liveManual
        connectionState = .disconnected(reason: .requested)
        diagnostics = nil
        currentUser = nil
        apiClient = nil
        loginFlowState = .idle
        messageActionHandler = UnavailableMessageActionHandler(message: "Reconnect before sending messages.")
        installLiveSafeSnapshot()
        await refreshCredentialAvailability()
        sessionState = hasSavedCredential ? .readyToConnect : .signedOut
        startupAuthDiagnostics.lastAuthAction = "disconnect"
        startupAuthDiagnostics.lastAuthResult = "disconnected"
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
            loginFlowState = .idle
            loginDiagnostics = LoginDiagnostics()
            startupAuthDiagnostics.lastAuthAction = "forget_session"
            startupAuthDiagnostics.lastAuthResult = "forgot_local_session"
            messageActionHandler = UnavailableMessageActionHandler(message: "Set up a session before sending messages.")
            installLiveSafeSnapshot()
            lastErrorMessage = nil
        } catch {
            let message = StartupAuthDiagnosticsRedactor.redact("Could not delete saved credential: \(error.userFacingMessage)")
            sessionState = .keychainFailed(message)
            lastErrorMessage = message
            loginDiagnostics.lastErrorCategory = .keychainError
            startupAuthDiagnostics.lastErrorCategory = .keychainError
            startupAuthDiagnostics.lastAuthResult = "failed_keychain_error"
        }
    }

    public func revokeCurrentSessionOnServer() async {
        do {
            guard let credential = try await loadCredentialForCurrentEnvironment() else {
                let message = "No saved session is available to revoke."
                sessionState = .signedOut
                lastErrorMessage = message
                startupAuthDiagnostics.lastAuthAction = "revoke_session"
                startupAuthDiagnostics.lastAuthResult = "missing_credential"
                return
            }
            let client = apiClientFactory(environment, StaticCredentialProvider(credential))
            try await client.logoutCurrentSession()
            await forgetLocalSession()
        } catch {
            let message = StartupAuthDiagnosticsRedactor.redact("Server-side session revocation failed: \(error.userFacingMessage)")
            sessionState = .validationFailed(message)
            lastErrorMessage = message
            let category = loginErrorCategory(for: error)
            startupAuthDiagnostics.lastErrorCategory = category
            startupAuthDiagnostics.lastAuthAction = "revoke_session"
            startupAuthDiagnostics.lastAuthResult = "failed_\(loginErrorCategoryName(category))"
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
                let update = await store.apply(event)
                let snapshot = update.snapshot
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

    private func startupDiagnosticEnvironmentKind(_ environment: StoatAPIEnvironment) -> String {
        environment.isProduction ? "production" : "custom"
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

    private func loginErrorCategory(for error: Error) -> LoginErrorDisplay {
        if let validationError = error as? SessionValidationError {
            switch validationError {
            case .invalidOrExpired, .missingCredential, .forbidden:
                return .invalidCredentials
            case .rateLimited:
                return .rateLimited
            case .networkUnavailable:
                return .networkError
            case .serverUnavailable:
                return .serverError
            case .invalidEnvironment:
                return .environmentError
            case .failed:
                return .unknown(validationError.errorDescription ?? "Unknown error")
            }
        }
        return .unknown(error.userFacingMessage)
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
