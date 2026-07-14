import Foundation
import StoatModels
import StoatRealtime

public enum Phase43IdentitySource: String, Codable, Hashable, Sendable, CaseIterable {
    case readyUser
    case readyMember
    case messageUser
    case messageMember
    case memberRESTUser
    case profileFetch
    case relationship
    case banList
    case moderationAction
    case currentUserEdit
    case realtimeUserUpdate
    case realtimeMemberUpdate
    case hydrationFetch
}

public enum Phase43IdentityConfidence: Int, Codable, Hashable, Sendable, Comparable {
    case fallback = 0
    case historical = 20
    case embedded = 40
    case hydrated = 60
    case current = 80

    public static func < (lhs: Phase43IdentityConfidence, rhs: Phase43IdentityConfidence) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum Phase43AvatarCacheTransition: Equatable {
    case preserve
    case replace(previous: File?, next: File)
    case remove(previous: File)

    static func resolve(previous: File?, incoming: File?, source: Phase43IdentitySource) -> Self {
        if let incoming {
            guard previous?.id != incoming.id else { return .preserve }
            return .replace(previous: previous, next: incoming)
        }
        guard let previous,
              source == .realtimeUserUpdate || source == .currentUserEdit else {
            return .preserve
        }
        return .remove(previous: previous)
    }
}

enum Phase43ServerAvatarCacheTransition: Equatable {
    case preserve
    case replace(previous: File?, next: File)
    case remove(previous: File)

    static func resolve(previous: File?, incoming: File?, source: Phase43IdentitySource) -> Self {
        if let incoming {
            guard previous?.id != incoming.id else { return .preserve }
            return .replace(previous: previous, next: incoming)
        }
        guard let previous, source == .realtimeMemberUpdate else {
            return .preserve
        }
        return .remove(previous: previous)
    }
}

public struct Phase43ServerIdentityOverlay: Hashable, Sendable {
    public var serverID: ServerID
    public var nickname: String?
    public var avatarFile: File?
    public var roleIDs: [RoleID]
    public var isCurrentMember: Bool
    public var sourceCategories: Set<Phase43IdentitySource>
    public var generation: Int
    public var lastUpdatedAt: Date

    public init(
        serverID: ServerID,
        nickname: String? = nil,
        avatarFile: File? = nil,
        roleIDs: [RoleID] = [],
        isCurrentMember: Bool = true,
        sourceCategories: Set<Phase43IdentitySource> = [],
        generation: Int = 0,
        lastUpdatedAt: Date = Date()
    ) {
        self.serverID = serverID
        self.nickname = Phase43IdentitySnapshotStore.trimmed(nickname)
        self.avatarFile = avatarFile
        self.roleIDs = roleIDs
        self.isCurrentMember = isCurrentMember
        self.sourceCategories = sourceCategories
        self.generation = generation
        self.lastUpdatedAt = lastUpdatedAt
    }
}

public struct Phase43IdentitySnapshot: Hashable, Sendable, Identifiable {
    public var id: UserID { userID }
    public var userID: UserID
    public var username: String?
    public var displayName: String?
    public var avatarFile: File?
    public var isBot: Bool
    public var botOwnerID: UserID?
    public var profileContentSummary: String?
    public var profileBackgroundFile: File?
    public var sourceCategories: Set<Phase43IdentitySource>
    public var confidence: Phase43IdentityConfidence
    public var generation: Int
    public var lastUpdatedAt: Date
    public var serverOverlays: [ServerID: Phase43ServerIdentityOverlay]

    public init(
        userID: UserID,
        username: String? = nil,
        displayName: String? = nil,
        avatarFile: File? = nil,
        isBot: Bool = false,
        botOwnerID: UserID? = nil,
        profileContentSummary: String? = nil,
        profileBackgroundFile: File? = nil,
        sourceCategories: Set<Phase43IdentitySource> = [],
        confidence: Phase43IdentityConfidence = .fallback,
        generation: Int = 0,
        lastUpdatedAt: Date = Date(),
        serverOverlays: [ServerID: Phase43ServerIdentityOverlay] = [:]
    ) {
        self.userID = userID
        self.username = Phase43IdentitySnapshotStore.trimmed(username)
        self.displayName = Phase43IdentitySnapshotStore.trimmed(displayName)
        self.avatarFile = avatarFile
        self.isBot = isBot
        self.botOwnerID = botOwnerID
        self.profileContentSummary = Phase43IdentitySnapshotStore.summary(profileContentSummary)
        self.profileBackgroundFile = profileBackgroundFile
        self.sourceCategories = sourceCategories
        self.confidence = confidence
        self.generation = generation
        self.lastUpdatedAt = lastUpdatedAt
        self.serverOverlays = serverOverlays
    }

    public var hasReadableIdentity: Bool {
        displayName != nil || username != nil || serverOverlays.values.contains { $0.nickname != nil }
    }

    public var isHistoricalOnly: Bool {
        !serverOverlays.isEmpty && serverOverlays.values.allSatisfy { !$0.isCurrentMember }
    }
}

public struct Phase43HydrationPolicy: Hashable, Sendable {
    public var maxConcurrentFetches: Int
    public var firstFailureCooldown: TimeInterval
    public var repeatedFailureCooldown: TimeInterval
    public var repeatedFailureThreshold: Int
    public var maxBatchEnqueue: Int

    public init(
        maxConcurrentFetches: Int = 3,
        firstFailureCooldown: TimeInterval = 60,
        repeatedFailureCooldown: TimeInterval = 300,
        repeatedFailureThreshold: Int = 3,
        maxBatchEnqueue: Int = 80
    ) {
        self.maxConcurrentFetches = max(1, maxConcurrentFetches)
        self.firstFailureCooldown = firstFailureCooldown
        self.repeatedFailureCooldown = repeatedFailureCooldown
        self.repeatedFailureThreshold = max(1, repeatedFailureThreshold)
        self.maxBatchEnqueue = max(1, maxBatchEnqueue)
    }

    public func cooldownInterval(afterFailureCount count: Int) -> TimeInterval {
        count >= repeatedFailureThreshold ? repeatedFailureCooldown : firstFailureCooldown
    }
}

public enum Phase43IdentityHydrationSource: String, Hashable, Sendable {
    case visibleMessage
    case visibleMember
    case visibleSearchResult
    case systemEvent
    case banList
    case profileOpen
}

public struct Phase43IdentityDiagnostics: Hashable, Sendable {
    public var knownIdentitySnapshotsCount: Int
    public var historicalOnlySnapshotsCount: Int
    public var unresolvedVisibleUserIDsCount: Int
    public var systemEventClickableParticipantCount: Int
    public var systemEventNonclickableFallbackCount: Int
    public var identityHydrationQueuedCount: Int
    public var identityHydrationInFlightCount: Int
    public var identityHydrationSuccessCount: Int
    public var identityHydrationFailureCount: Int
    public var identityHydrationDedupeHits: Int
    public var identityHydrationCooldownSkips: Int
    public var avatarMetadataPreservedAfterMemberRemovalCount: Int
    public var avatarLoadFailureCount: Int
    public var profileOpensFromSystemEventsCount: Int
    public var currentUserEditSnapshotMergeCount: Int
    public var memberRemovalIdentityPreservationCount: Int

    public init(
        knownIdentitySnapshotsCount: Int = 0,
        historicalOnlySnapshotsCount: Int = 0,
        unresolvedVisibleUserIDsCount: Int = 0,
        systemEventClickableParticipantCount: Int = 0,
        systemEventNonclickableFallbackCount: Int = 0,
        identityHydrationQueuedCount: Int = 0,
        identityHydrationInFlightCount: Int = 0,
        identityHydrationSuccessCount: Int = 0,
        identityHydrationFailureCount: Int = 0,
        identityHydrationDedupeHits: Int = 0,
        identityHydrationCooldownSkips: Int = 0,
        avatarMetadataPreservedAfterMemberRemovalCount: Int = 0,
        avatarLoadFailureCount: Int = 0,
        profileOpensFromSystemEventsCount: Int = 0,
        currentUserEditSnapshotMergeCount: Int = 0,
        memberRemovalIdentityPreservationCount: Int = 0
    ) {
        self.knownIdentitySnapshotsCount = knownIdentitySnapshotsCount
        self.historicalOnlySnapshotsCount = historicalOnlySnapshotsCount
        self.unresolvedVisibleUserIDsCount = unresolvedVisibleUserIDsCount
        self.systemEventClickableParticipantCount = systemEventClickableParticipantCount
        self.systemEventNonclickableFallbackCount = systemEventNonclickableFallbackCount
        self.identityHydrationQueuedCount = identityHydrationQueuedCount
        self.identityHydrationInFlightCount = identityHydrationInFlightCount
        self.identityHydrationSuccessCount = identityHydrationSuccessCount
        self.identityHydrationFailureCount = identityHydrationFailureCount
        self.identityHydrationDedupeHits = identityHydrationDedupeHits
        self.identityHydrationCooldownSkips = identityHydrationCooldownSkips
        self.avatarMetadataPreservedAfterMemberRemovalCount = avatarMetadataPreservedAfterMemberRemovalCount
        self.avatarLoadFailureCount = avatarLoadFailureCount
        self.profileOpensFromSystemEventsCount = profileOpensFromSystemEventsCount
        self.currentUserEditSnapshotMergeCount = currentUserEditSnapshotMergeCount
        self.memberRemovalIdentityPreservationCount = memberRemovalIdentityPreservationCount
    }
}

public enum Phase43IdentityDiagnosticsFormatter {
    public static func redactedText(_ diagnostics: Phase43IdentityDiagnostics) -> String {
        let text = """
        Phase 43 identity diagnostics
        knownSnapshots: \(diagnostics.knownIdentitySnapshotsCount)
        historicalOnlySnapshots: \(diagnostics.historicalOnlySnapshotsCount)
        unresolvedVisibleUserIDs: \(diagnostics.unresolvedVisibleUserIDsCount)
        systemEventClickableParticipants: \(diagnostics.systemEventClickableParticipantCount)
        systemEventNonclickableFallbacks: \(diagnostics.systemEventNonclickableFallbackCount)
        identityHydrationQueued: \(diagnostics.identityHydrationQueuedCount)
        identityHydrationInFlight: \(diagnostics.identityHydrationInFlightCount)
        identityHydrationSuccessFailure: \(diagnostics.identityHydrationSuccessCount)/\(diagnostics.identityHydrationFailureCount)
        identityHydrationDedupeHits: \(diagnostics.identityHydrationDedupeHits)
        identityHydrationCooldownSkips: \(diagnostics.identityHydrationCooldownSkips)
        avatarMetadataPreservedAfterMemberRemoval: \(diagnostics.avatarMetadataPreservedAfterMemberRemovalCount)
        avatarLoadFailures: \(diagnostics.avatarLoadFailureCount)
        profileOpensFromSystemEvents: \(diagnostics.profileOpensFromSystemEventsCount)
        currentUserEditSnapshotMerges: \(diagnostics.currentUserEditSnapshotMergeCount)
        memberRemovalIdentityPreservations: \(diagnostics.memberRemovalIdentityPreservationCount)
        """
        return redactSensitiveText(text)
    }

    public static func redactSensitiveText(_ value: String) -> String {
        var output = value
        let patterns = [
            #"\{[^\n]*\}"#,
            #"https?://[^\s,;)"]+"#,
            #"file://[^\s,;)"]+"#,
            #"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#,
            #"(?i)\b(x-session-token|authorization|token|session|session_id|sessionID|password|mfa|ticket|response|reason)\b\s*[:=]\s*["']?[^"',;\s]+"#,
            #"(?i)\b(password|mfa|ticket|response|reason)\b\s+[^,;\n]+"#,
            #"(/Users|/tmp|/var|/private|/Volumes)(/[^\s,;)"]+)+"#,
            #"\b[A-Za-z0-9_-]{20,}\b"#
        ]
        for pattern in patterns {
            output = output.replacingOccurrences(of: pattern, with: "[redacted]", options: .regularExpression)
        }
        output = TimelineCopyFormatter.redactTokenLikeStrings(output)
        output = Phase6UIHelpers.safeDiagnostics(output)
        output = Phase17MessageActions.redactedDiagnosticText(output)
        return output
    }
}

public struct Phase43IdentitySnapshotStore: Hashable, Sendable {
    public private(set) var snapshotsByUserID: [UserID: Phase43IdentitySnapshot]
    public private(set) var generation: Int

    public init(snapshotsByUserID: [UserID: Phase43IdentitySnapshot] = [:], generation: Int = 0) {
        self.snapshotsByUserID = snapshotsByUserID
        self.generation = generation
    }

    public var knownCount: Int { snapshotsByUserID.count }

    public var historicalOnlyCount: Int {
        snapshotsByUserID.values.filter(\.isHistoricalOnly).count
    }

    public func snapshot(for userID: UserID) -> Phase43IdentitySnapshot? {
        snapshotsByUserID[userID]
    }

    public func hasReadableIdentity(for userID: UserID) -> Bool {
        snapshotsByUserID[userID]?.hasReadableIdentity == true
    }

    @discardableResult
    public mutating func merge(user: User, source: Phase43IdentitySource, now: Date = Date()) -> Bool {
        var snapshot = snapshotsByUserID[user.id] ?? Phase43IdentitySnapshot(userID: user.id)
        let before = snapshot
        Self.mergeString(&snapshot.username, user.username)
        Self.mergeString(&snapshot.displayName, user.displayName)
        if let avatar = user.avatar {
            snapshot.avatarFile = avatar
        } else if source == .realtimeUserUpdate || source == .currentUserEdit {
            snapshot.avatarFile = nil
        }
        snapshot.isBot = user.bot != nil
        snapshot.botOwnerID = user.bot?.ownerID
        snapshot.sourceCategories.insert(source)
        snapshot.confidence = max(snapshot.confidence, Self.confidence(for: source))
        guard before != snapshot else { return false }
        markUpdated(&snapshot, now: now)
        snapshotsByUserID[user.id] = snapshot
        return true
    }

    @discardableResult
    public mutating func merge(member: ServerMember, user: User?, source: Phase43IdentitySource, now: Date = Date()) -> Bool {
        let userChanged: Bool
        if let user {
            userChanged = merge(user: user, source: source == .messageMember ? .messageUser : source, now: now)
        } else {
            userChanged = false
        }
        var snapshot = snapshotsByUserID[member.id.userID] ?? Phase43IdentitySnapshot(userID: member.id.userID)
        let before = snapshot
        snapshot.sourceCategories.insert(source)
        snapshot.confidence = max(snapshot.confidence, Self.confidence(for: source))
        var overlay = snapshot.serverOverlays[member.id.serverID] ?? Phase43ServerIdentityOverlay(serverID: member.id.serverID)
        let overlayBefore = overlay
        overlay.nickname = Self.trimmed(member.nickname)
        overlay.avatarFile = member.avatar
        overlay.roleIDs = member.roles
        overlay.isCurrentMember = true
        overlay.sourceCategories.insert(source)
        snapshot.serverOverlays[member.id.serverID] = overlay
        guard before != snapshot else { return userChanged }
        generation &+= 1
        if overlayBefore != overlay {
            overlay.generation = generation
            overlay.lastUpdatedAt = now
            snapshot.serverOverlays[member.id.serverID] = overlay
        }
        snapshot.generation = generation
        snapshot.lastUpdatedAt = now
        snapshotsByUserID[member.id.userID] = snapshot
        return true
    }

    @discardableResult
    public mutating func merge(profile: UserProfile, userID: UserID, now: Date = Date()) -> Bool {
        var snapshot = snapshotsByUserID[userID] ?? Phase43IdentitySnapshot(userID: userID)
        let before = snapshot
        snapshot.profileContentSummary = Self.summary(profile.content)
        snapshot.profileBackgroundFile = profile.background
        snapshot.sourceCategories.insert(.profileFetch)
        snapshot.confidence = max(snapshot.confidence, .hydrated)
        guard before != snapshot else { return false }
        markUpdated(&snapshot, now: now)
        snapshotsByUserID[userID] = snapshot
        return true
    }

    @discardableResult
    public mutating func markMemberRemoved(userID: UserID, serverID: ServerID, now: Date = Date()) -> Bool {
        var snapshot = snapshotsByUserID[userID] ?? Phase43IdentitySnapshot(userID: userID)
        let before = snapshot
        var overlay = snapshot.serverOverlays[serverID] ?? Phase43ServerIdentityOverlay(serverID: serverID)
        let overlayBefore = overlay
        overlay.isCurrentMember = false
        overlay.sourceCategories.insert(.moderationAction)
        snapshot.serverOverlays[serverID] = overlay
        snapshot.sourceCategories.insert(.moderationAction)
        snapshot.confidence = max(snapshot.confidence, .historical)
        guard before != snapshot else { return false }
        generation &+= 1
        if overlayBefore != overlay {
            overlay.generation = generation
            overlay.lastUpdatedAt = now
            snapshot.serverOverlays[serverID] = overlay
        }
        snapshot.generation = generation
        snapshot.lastUpdatedAt = now
        snapshotsByUserID[userID] = snapshot
        return true
    }

    public func resolvedDisplay(
        userID: UserID,
        user: User?,
        member: ServerMember?,
        server: Server?,
        highContrast: Bool = false
    ) -> ResolvedUserDisplay {
        let snapshot = snapshotsByUserID[userID]
        let roleColor = RoleColorResolver.resolve(member: member, server: server, highContrast: highContrast)
        let roleDiagnostics = RoleColorResolver.diagnostics(member: member, server: server, resolved: roleColor, highContrast: highContrast)
        let activeOverlay = server.flatMap { snapshot?.serverOverlays[$0.id] }?.isCurrentMember == true ? server.flatMap { snapshot?.serverOverlays[$0.id] } : nil
        let historicalOverlay = server.flatMap { snapshot?.serverOverlays[$0.id] }
        let avatar = member?.avatar ?? user?.avatar ?? activeOverlay?.avatarFile ?? snapshot?.avatarFile ?? historicalOverlay?.avatarFile
        let username = Self.trimmed(user?.username) ?? snapshot?.username
        let subtitle = username.map { "@\($0)" } ?? "Unknown member"
        if let nickname = Self.trimmed(member?.nickname) ?? activeOverlay?.nickname {
            return ResolvedUserDisplay(userID: userID, displayName: nickname, subtitle: subtitle, avatarFile: avatar, fallbackInitials: UserDisplayResolver.initials(for: nickname), isFallback: false, source: .memberNickname, isBot: user?.bot != nil || snapshot?.isBot == true, roleColor: roleColor, roleColorDiagnostics: roleDiagnostics, serverContextID: server?.id)
        }
        if let displayName = Self.trimmed(user?.displayName) {
            return ResolvedUserDisplay(userID: userID, displayName: displayName, subtitle: subtitle, avatarFile: avatar, fallbackInitials: UserDisplayResolver.initials(for: displayName), isFallback: false, source: .userDisplayName, isBot: user?.bot != nil || snapshot?.isBot == true, roleColor: roleColor, roleColorDiagnostics: roleDiagnostics, serverContextID: server?.id)
        }
        if let username {
            let source: ResolvedUserDisplaySource = (user?.bot != nil || snapshot?.isBot == true) ? .botName : .username
            return ResolvedUserDisplay(userID: userID, displayName: username, subtitle: "@\(username)", avatarFile: avatar, fallbackInitials: UserDisplayResolver.initials(for: username), isFallback: false, source: source, isBot: user?.bot != nil || snapshot?.isBot == true, roleColor: roleColor, roleColorDiagnostics: roleDiagnostics, serverContextID: server?.id)
        }
        if let displayName = snapshot?.displayName {
            return ResolvedUserDisplay(userID: userID, displayName: displayName, subtitle: subtitle, avatarFile: avatar, fallbackInitials: UserDisplayResolver.initials(for: displayName), isFallback: false, source: .userDisplayName, isBot: snapshot?.isBot == true, roleColor: roleColor, roleColorDiagnostics: roleDiagnostics, serverContextID: server?.id)
        }
        if let historical = historicalOverlay?.nickname {
            return ResolvedUserDisplay(userID: userID, displayName: historical, subtitle: subtitle, avatarFile: avatar, fallbackInitials: UserDisplayResolver.initials(for: historical), isFallback: false, source: .memberNickname, isBot: snapshot?.isBot == true, roleColor: roleColor, roleColorDiagnostics: roleDiagnostics, serverContextID: server?.id)
        }
        return ResolvedUserDisplay(userID: userID, displayName: "Unknown member", subtitle: "Unknown member", avatarFile: avatar, fallbackInitials: "?", isFallback: true, source: .unknown, isBot: snapshot?.isBot == true, roleColor: roleColor, roleColorDiagnostics: roleDiagnostics, serverContextID: server?.id)
    }

    private static func confidence(for source: Phase43IdentitySource) -> Phase43IdentityConfidence {
        switch source {
        case .readyUser, .readyMember, .realtimeUserUpdate, .realtimeMemberUpdate, .currentUserEdit:
            return .current
        case .memberRESTUser, .profileFetch, .banList, .moderationAction, .hydrationFetch, .relationship:
            return .hydrated
        case .messageUser, .messageMember:
            return .embedded
        }
    }

    private mutating func markUpdated(_ snapshot: inout Phase43IdentitySnapshot, now: Date) {
        generation &+= 1
        snapshot.generation = generation
        snapshot.lastUpdatedAt = now
    }

    private static func mergeString(_ current: inout String?, _ incoming: String?) {
        guard let incoming = trimmed(incoming) else { return }
        current = incoming
    }

    public static func trimmed(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    public static func summary(_ value: String?) -> String? {
        guard let trimmed = trimmed(value) else { return nil }
        return String(trimmed.prefix(160))
    }
}

public enum SystemEventParticipantConfidence: String, Hashable, Sendable {
    case high
    case medium
    case low
}

public enum SystemEventParticipantRole: String, Hashable, Sendable {
    case actor
    case target
    case affected
}

public struct SystemEventParticipant: Hashable, Sendable, Identifiable {
    public var id: String { "\(role.rawValue)-\(userID.rawValue)" }
    public var userID: UserID
    public var role: SystemEventParticipantRole
    public var display: ResolvedUserDisplay
    public var confidence: SystemEventParticipantConfidence

    public init(userID: UserID, role: SystemEventParticipantRole, display: ResolvedUserDisplay, confidence: SystemEventParticipantConfidence = .high) {
        self.userID = userID
        self.role = role
        self.display = display
        self.confidence = confidence
    }

    public var accessibilityLabel: String {
        "Open profile for \(display.displayName)"
    }
}

public enum SystemEventPresentationPiece: Hashable, Sendable, Identifiable {
    case text(String)
    case participant(SystemEventParticipant)

    public var id: String {
        switch self {
        case let .text(value):
            return "text-\(value)"
        case let .participant(participant):
            return "participant-\(participant.id)"
        }
    }
}

public struct SystemEventPresentation: Hashable, Sendable {
    public var pieces: [SystemEventPresentationPiece]
    public var fallbackCount: Int

    public init(pieces: [SystemEventPresentationPiece] = [], fallbackCount: Int = 0) {
        self.pieces = pieces
        self.fallbackCount = fallbackCount
    }

    public var plainText: String {
        pieces.map { piece in
            switch piece {
            case let .text(value): value
            case let .participant(participant): participant.display.displayName
            }
        }.joined()
    }

    public var clickableParticipantCount: Int {
        pieces.reduce(0) { count, piece in
            if case .participant = piece { return count + 1 }
            return count
        }
    }

    public static func text(_ value: String, fallbackCount: Int = 0) -> SystemEventPresentation {
        SystemEventPresentation(pieces: [.text(value)], fallbackCount: fallbackCount)
    }
}
