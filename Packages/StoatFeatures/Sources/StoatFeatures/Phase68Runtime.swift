import Foundation
import StoatModels
import StoatRealtime
import StoatUI

public struct Phase68TraceDiagnostics: Hashable, Sendable {
    public var identityNoOpMergeCount: Int
    public var memberListRelevantInvalidationCount: Int
    public var selectedMemberListPublicationCount: Int
    public var emojiIndexBuildCount: Int
    public var emojiIndexCacheHitCount: Int
    public var visibleIdentityDiagnosticsRequestCount: Int
    public var visibleIdentityDiagnosticsCoalescedCount: Int
    public var visibleIdentityDiagnosticsBuildCount: Int
    public var visibleIdentityDiagnosticsStaleResultCount: Int

    public init(
        identityNoOpMergeCount: Int = 0,
        memberListRelevantInvalidationCount: Int = 0,
        selectedMemberListPublicationCount: Int = 0,
        emojiIndexBuildCount: Int = 0,
        emojiIndexCacheHitCount: Int = 0,
        visibleIdentityDiagnosticsRequestCount: Int = 0,
        visibleIdentityDiagnosticsCoalescedCount: Int = 0,
        visibleIdentityDiagnosticsBuildCount: Int = 0,
        visibleIdentityDiagnosticsStaleResultCount: Int = 0
    ) {
        self.identityNoOpMergeCount = identityNoOpMergeCount
        self.memberListRelevantInvalidationCount = memberListRelevantInvalidationCount
        self.selectedMemberListPublicationCount = selectedMemberListPublicationCount
        self.emojiIndexBuildCount = emojiIndexBuildCount
        self.emojiIndexCacheHitCount = emojiIndexCacheHitCount
        self.visibleIdentityDiagnosticsRequestCount = visibleIdentityDiagnosticsRequestCount
        self.visibleIdentityDiagnosticsCoalescedCount = visibleIdentityDiagnosticsCoalescedCount
        self.visibleIdentityDiagnosticsBuildCount = visibleIdentityDiagnosticsBuildCount
        self.visibleIdentityDiagnosticsStaleResultCount = visibleIdentityDiagnosticsStaleResultCount
    }
}

struct Phase68MemberIdentityPresentationSignature: Hashable, Sendable {
    var username: String?
    var displayName: String?
    var avatarFile: File?
    var isBot: Bool
    var nickname: String?
    var serverAvatarFile: File?
    var isCurrentMember: Bool?

    init(snapshot: Phase43IdentitySnapshot?, serverID: ServerID) {
        let overlay = snapshot?.serverOverlays[serverID]
        username = snapshot?.username
        displayName = snapshot?.displayName
        avatarFile = snapshot?.avatarFile
        isBot = snapshot?.isBot == true
        nickname = overlay?.nickname
        serverAvatarFile = overlay?.avatarFile
        isCurrentMember = overlay?.isCurrentMember
    }
}

public struct Phase68CustomEmojiIndex: Hashable, Sendable {
    public private(set) var sortedItems: [CustomEmojiDisplayItem]
    private var itemsByID: [EmojiID: CustomEmojiDisplayItem]
    private var itemsByShortcode: [String: [CustomEmojiDisplayItem]]

    public init(emojisByID: [EmojiID: Emoji]) {
        let items = emojisByID.values
            .map(CustomEmojiDisplayItem.init(emoji:))
            .sorted {
                let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
                if comparison != .orderedSame { return comparison == .orderedAscending }
                return $0.id.rawValue < $1.id.rawValue
            }
        sortedItems = items
        itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        itemsByShortcode = Dictionary(grouping: items, by: { Self.normalizedShortcode($0.shortcode) })
    }

    public func item(for rawValue: String, serverID: ServerID?) -> CustomEmojiDisplayItem? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let item = itemsByID[EmojiID(rawValue: trimmed)], isAllowed(item, serverID: serverID) {
            return item
        }
        let key = Self.normalizedShortcode(trimmed)
        guard let candidates = itemsByShortcode[key] else { return nil }
        if let serverID, let current = candidates.first(where: { $0.serverID == serverID }) {
            return current
        }
        if serverID != nil {
            return candidates.first(where: { $0.serverID == nil })
        }
        return candidates.first
    }

    public func items(in content: String?, serverID: ServerID?) -> [CustomEmojiDisplayItem] {
        var seen: Set<EmojiID> = []
        return matches(in: content, serverID: serverID).compactMap { match in
            seen.insert(match.item.id).inserted ? match.item : nil
        }
    }

    public func matches(in content: String?, serverID: ServerID?) -> [Phase68CustomEmojiContentMatch] {
        guard let content, content.contains(":") else { return [] }
        var result: [Phase68CustomEmojiContentMatch] = []
        var seenTokens: Set<String> = []

        // Match the Markdown renderer's fenced-code behavior: tokens inside a fenced block
        // remain literal and therefore must not create invisible image work.
        var activeFence: Character?
        for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
            if let fence = Self.fenceMarker(in: trimmed) {
                if activeFence == nil {
                    activeFence = fence
                } else if activeFence == fence {
                    activeFence = nil
                }
                continue
            }
            guard activeFence == nil else { continue }
            Self.appendMatches(in: line, serverID: serverID, index: self, seenTokens: &seenTokens, result: &result)
        }
        return result
    }

    private static func appendMatches(
        in content: Substring,
        serverID: ServerID?,
        index: Phase68CustomEmojiIndex,
        seenTokens: inout Set<String>,
        result: inout [Phase68CustomEmojiContentMatch]
    ) {
        var remaining = content
        while let start = remaining.firstIndex(of: ":"),
              let end = remaining[remaining.index(after: start)...].firstIndex(of: ":") {
            let token = String(remaining[start...end])
            if let item = index.contentItem(for: token, serverID: serverID), seenTokens.insert(token).inserted {
                result.append(Phase68CustomEmojiContentMatch(token: token, item: item))
            }
            remaining = remaining[remaining.index(after: end)...]
        }
    }

    private func contentItem(for token: String, serverID: ServerID?) -> CustomEmojiDisplayItem? {
        let rawValue = token.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        if rawValue.count == 26, let item = itemsByID[EmojiID(rawValue: rawValue)] {
            // Official Stoat content tokens are globally unambiguous emoji IDs. The official
            // parser recognizes 26-character IDs and the picker exposes emoji from every known
            // server, so ID-backed content must not be restricted to the selected server.
            return item
        }

        // Liquid Bagel historically emitted name-only shortcodes. Keep those messages readable,
        // but retain server scoping because names are not globally unique.
        let key = Self.normalizedShortcode(token)
        guard let candidates = itemsByShortcode[key] else { return nil }
        if let serverID {
            return candidates.first(where: { $0.serverID == serverID })
                ?? candidates.first(where: { $0.serverID == nil })
        }
        return candidates.first
    }

    private static func fenceMarker(in line: Substring) -> Character? {
        guard line.count >= 3, let first = line.first, first == "`" || first == "~" else { return nil }
        guard line.prefix(3).allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    private func isAllowed(_ item: CustomEmojiDisplayItem, serverID: ServerID?) -> Bool {
        guard let serverID else { return true }
        return item.serverID == nil || item.serverID == serverID
    }

    private static func normalizedShortcode(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: ":").union(.whitespacesAndNewlines)).lowercased()
    }
}

public struct Phase68CustomEmojiContentMatch: Hashable, Sendable {
    public var token: String
    public var item: CustomEmojiDisplayItem

    public init(token: String, item: CustomEmojiDisplayItem) {
        self.token = token
        self.item = item
    }
}

struct Phase68VisibleIdentityDiagnosticsInput: Sendable {
    var snapshot: RealtimeSnapshot
    var identitySnapshots: Phase43IdentitySnapshotStore
    var timelineMessages: [TimelineMessage]
    var memberGroups: [MemberListGroup]
    var selectedChannelID: ChannelID?
    var selectedServerID: ServerID?
    var currentUser: User?
    var failedAvatarCount: Int
    var profileFetchMergeCount: Int
    var memberWrapperUserMergeCount: Int
    var hydrationQueuedCount: Int
    var hydrationInFlightCount: Int
    var hydrationSuccessCount: Int
    var hydrationFailureCount: Int
    var hydrationDedupeHits: Int
    var hydrationCooldownSkips: Int
    var avatarMetadataPreservedCount: Int
    var profileSystemEventOpenCount: Int
    var currentUserEditMergeCount: Int
    var memberRemovalPreservationCount: Int
}

enum Phase68VisibleIdentityDiagnosticsPreparer {
    static func prepare(_ input: Phase68VisibleIdentityDiagnosticsInput) -> VisibleIdentityDiagnostics {
        let timelineDisplays = input.timelineMessages.map { timelineMessage in
            resolvedDisplay(for: timelineMessage.message, input: input)
        }
        let memberDisplays = input.memberGroups.flatMap(\.items).map { item in
            let serverID = item.member?.id.serverID
            return input.identitySnapshots.resolvedDisplay(
                userID: item.userID,
                user: item.user,
                member: item.member,
                server: serverID.flatMap { input.snapshot.serversByID[$0] }
            )
        }
        let visibleDisplays = timelineDisplays + memberDisplays

        var missingUserIDs: Set<UserID> = []
        var systemEventPresentations: [SystemEventPresentation] = []
        for timelineMessage in input.timelineMessages {
            let message = timelineMessage.message
            if message.system != nil {
                let presentation = systemEventPresentation(for: message, input: input)
                systemEventPresentations.append(presentation)
                if let target = Phase27SystemEventPresenter.profileTarget(for: message),
                   resolvedDisplay(userID: target, serverID: input.snapshot.channelsByID[message.channelID]?.serverID, input: input).isFallback {
                    missingUserIDs.insert(target)
                }
            } else if resolvedDisplay(for: message, input: input).isFallback {
                missingUserIDs.insert(message.authorID)
            }
        }

        if let channelID = input.selectedChannelID,
           let channel = input.snapshot.channelsByID[channelID],
           DMChannelClassifier.isDirectMessageLike(channel) {
            for userID in channel.recipients where resolvedDisplay(userID: userID, serverID: nil, input: input).isFallback {
                missingUserIDs.insert(userID)
            }
        }
        if let serverID = input.selectedServerID {
            for member in input.snapshot.membersByServerAndUserID.values where member.id.serverID == serverID {
                if resolvedDisplay(userID: member.id.userID, serverID: serverID, input: input).isFallback {
                    missingUserIDs.insert(member.id.userID)
                }
            }
        }

        let clickableCount = systemEventPresentations.reduce(0) { $0 + $1.clickableParticipantCount }
        let fallbackCount = systemEventPresentations.reduce(0) { $0 + $1.fallbackCount }
        let phase43 = Phase43IdentityDiagnostics(
            knownIdentitySnapshotsCount: input.identitySnapshots.knownCount,
            historicalOnlySnapshotsCount: input.identitySnapshots.historicalOnlyCount,
            unresolvedVisibleUserIDsCount: missingUserIDs.count,
            systemEventClickableParticipantCount: clickableCount,
            systemEventNonclickableFallbackCount: fallbackCount,
            identityHydrationQueuedCount: input.hydrationQueuedCount,
            identityHydrationInFlightCount: input.hydrationInFlightCount,
            identityHydrationSuccessCount: input.hydrationSuccessCount,
            identityHydrationFailureCount: input.hydrationFailureCount,
            identityHydrationDedupeHits: input.hydrationDedupeHits,
            identityHydrationCooldownSkips: input.hydrationCooldownSkips,
            avatarMetadataPreservedAfterMemberRemovalCount: input.avatarMetadataPreservedCount,
            avatarLoadFailureCount: input.failedAvatarCount,
            profileOpensFromSystemEventsCount: input.profileSystemEventOpenCount,
            currentUserEditSnapshotMergeCount: input.currentUserEditMergeCount,
            memberRemovalIdentityPreservationCount: input.memberRemovalPreservationCount
        )
        return VisibleIdentityDiagnostics(
            unresolvedVisibleUserCount: missingUserIDs.count,
            shortenedVisibleIDCount: visibleDisplays.filter(\.isFallback).count,
            avatarFailureCacheCount: input.failedAvatarCount,
            profileFetchMergeCount: input.profileFetchMergeCount,
            memberWrapperUserMergeCount: input.memberWrapperUserMergeCount,
            phase43: phase43
        )
    }

    private static func resolvedDisplay(for message: Message, input: Phase68VisibleIdentityDiagnosticsInput) -> ResolvedUserDisplay {
        let serverID = input.snapshot.channelsByID[message.channelID]?.serverID
        let server = serverID.flatMap { input.snapshot.serversByID[$0] }
        return input.identitySnapshots.resolvedDisplay(
            userID: message.authorID,
            user: message.user ?? input.snapshot.usersByID[message.authorID] ?? (message.authorID == input.currentUser?.id ? input.currentUser : nil),
            member: message.member ?? serverID.flatMap {
                input.snapshot.membersByServerAndUserID[ServerMemberKey(serverID: $0, userID: message.authorID)]
            },
            server: server
        )
    }

    private static func resolvedDisplay(userID: UserID, serverID: ServerID?, input: Phase68VisibleIdentityDiagnosticsInput) -> ResolvedUserDisplay {
        input.identitySnapshots.resolvedDisplay(
            userID: userID,
            user: input.snapshot.usersByID[userID] ?? (userID == input.currentUser?.id ? input.currentUser : nil),
            member: serverID.flatMap {
                input.snapshot.membersByServerAndUserID[ServerMemberKey(serverID: $0, userID: userID)]
            },
            server: serverID.flatMap { input.snapshot.serversByID[$0] }
        )
    }

    private static func systemEventPresentation(for message: Message, input: Phase68VisibleIdentityDiagnosticsInput) -> SystemEventPresentation {
        let serverID = input.snapshot.channelsByID[message.channelID]?.serverID
        return Phase27SystemEventPresenter.presentation(for: message) { userID, role in
            let display = resolvedDisplay(userID: userID, serverID: serverID, input: input)
            guard !display.isFallback else { return nil }
            let member = serverID.flatMap {
                input.snapshot.membersByServerAndUserID[ServerMemberKey(serverID: $0, userID: userID)]
            }
            let user = input.snapshot.usersByID[userID]
            return SystemEventParticipant(
                userID: userID,
                role: role,
                display: display,
                confidence: member != nil || user != nil ? .high : .medium
            )
        }
    }
}
