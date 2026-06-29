import Foundation
import StoatAPI
import StoatModels
import StoatRealtime
import StoatUI

public enum Phase52FileIO {
    public static func read(_ url: URL) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped { url.stopAccessingSecurityScopedResource() }
            }
            return try Data(contentsOf: url, options: [.mappedIfSafe])
        }.value
    }

    public static func writeTemporaryAttachment(data: Data, filename: String) async throws -> URL {
        try await Task.detached(priority: .utility) {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("LiquidBagelAttachmentPreviews", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(
                UUID().uuidString + "-" + AttachmentDisplayFormatting.safeFilename(filename)
            )
            try data.write(to: url, options: [.atomic])
            return url
        }.value
    }
}

public struct Phase52FreezeDiagnostics: Hashable, Sendable {
    public var snapshotInstallCount: Int
    public var memberHydrationCommitCount: Int
    public var identityBatchCommitCount: Int
    public var lastMemberPreparationMilliseconds: Int?
    public var mainThreadBudgetViolationCount: Int

    public init(
        snapshotInstallCount: Int = 0,
        memberHydrationCommitCount: Int = 0,
        identityBatchCommitCount: Int = 0,
        lastMemberPreparationMilliseconds: Int? = nil,
        mainThreadBudgetViolationCount: Int = 0
    ) {
        self.snapshotInstallCount = snapshotInstallCount
        self.memberHydrationCommitCount = memberHydrationCommitCount
        self.identityBatchCommitCount = identityBatchCommitCount
        self.lastMemberPreparationMilliseconds = lastMemberPreparationMilliseconds
        self.mainThreadBudgetViolationCount = mainThreadBudgetViolationCount
    }
}

public struct Phase52MemberHydrationPreparation: Sendable {
    public var snapshot: RealtimeSnapshot
    public var identitySnapshots: Phase43IdentitySnapshotStore
    public var returnedMembersByKey: [ServerMemberKey: ServerMember]
    public var previousMemberCount: Int
    public var missingUserCount: Int
    public var invalidatedAvatarKeys: Set<ImageCacheKey>

    public init(
        snapshot: RealtimeSnapshot,
        identitySnapshots: Phase43IdentitySnapshotStore,
        returnedMembersByKey: [ServerMemberKey: ServerMember],
        previousMemberCount: Int,
        missingUserCount: Int,
        invalidatedAvatarKeys: Set<ImageCacheKey>
    ) {
        self.snapshot = snapshot
        self.identitySnapshots = identitySnapshots
        self.returnedMembersByKey = returnedMembersByKey
        self.previousMemberCount = previousMemberCount
        self.missingUserCount = missingUserCount
        self.invalidatedAvatarKeys = invalidatedAvatarKeys
    }
}

public enum Phase52MemberHydrationPreparer {
    public static func prepare(
        serverID: ServerID,
        response: ServerMembersResponse,
        snapshot: RealtimeSnapshot,
        identitySnapshots: Phase43IdentitySnapshotStore,
        now: Date = Date()
    ) throws -> Phase52MemberHydrationPreparation {
        try Task.checkCancellation()
        var nextSnapshot = snapshot
        var returnedByKey: [ServerMemberKey: ServerMember] = [:]
        returnedByKey.reserveCapacity(response.members.count)
        for (index, member) in response.members.enumerated() {
            returnedByKey[ServerMemberKey(member.id)] = member
            if index.isMultiple(of: 128) {
                try Task.checkCancellation()
            }
        }

        let previousMembers = snapshot.membersByServerAndUserID.filter { $0.key.serverID == serverID }
        var mergedMembers = snapshot.membersByServerAndUserID.filter { $0.key.serverID != serverID }
        mergedMembers.reserveCapacity(snapshot.membersByServerAndUserID.count + returnedByKey.count)
        for (key, member) in previousMembers where returnedByKey[key] == nil {
            mergedMembers[key] = member
        }
        for (key, member) in returnedByKey {
            mergedMembers[key] = member
        }
        nextSnapshot.membersByServerAndUserID = mergedMembers

        var invalidatedAvatarKeys: Set<ImageCacheKey> = []
        for (index, user) in response.users.enumerated() {
            let previousAvatar = identitySnapshots.snapshot(for: user.id)?.avatarFile
            if previousAvatar?.id != user.avatar?.id {
                if let previousAvatar {
                    invalidatedAvatarKeys.insert(ImageCacheKey(id: previousAvatar.id.rawValue, kind: .userAvatar))
                }
                if let avatar = user.avatar {
                    invalidatedAvatarKeys.insert(ImageCacheKey(id: avatar.id.rawValue, kind: .userAvatar))
                }
            }
            nextSnapshot.usersByID[user.id] = user
            if index.isMultiple(of: 128) {
                try Task.checkCancellation()
            }
        }

        var nextIdentities = identitySnapshots
        for (index, user) in response.users.enumerated() {
            _ = nextIdentities.merge(user: user, source: .memberRESTUser, now: now)
            if index.isMultiple(of: 128) {
                try Task.checkCancellation()
            }
        }
        for (index, member) in returnedByKey.values.enumerated() {
            let previousAvatar = identitySnapshots.snapshot(for: member.id.userID)?.avatarFile
            if let avatar = member.avatar, previousAvatar?.id != avatar.id {
                if let previousAvatar {
                    invalidatedAvatarKeys.insert(ImageCacheKey(id: previousAvatar.id.rawValue, kind: .userAvatar))
                }
                invalidatedAvatarKeys.insert(ImageCacheKey(id: avatar.id.rawValue, kind: .userAvatar))
            }
            _ = nextIdentities.merge(member: member, user: nil, source: .readyMember, now: now)
            if index.isMultiple(of: 128) {
                try Task.checkCancellation()
            }
        }

        let missingUsers = mergedMembers.values.reduce(into: 0) { count, member in
            if member.id.serverID == serverID, nextSnapshot.usersByID[member.id.userID] == nil {
                count += 1
            }
        }
        try Task.checkCancellation()
        return Phase52MemberHydrationPreparation(
            snapshot: nextSnapshot,
            identitySnapshots: nextIdentities,
            returnedMembersByKey: returnedByKey,
            previousMemberCount: previousMembers.count,
            missingUserCount: missingUsers,
            invalidatedAvatarKeys: invalidatedAvatarKeys
        )
    }
}

public struct Phase52MemberListPreparation: Sendable {
    public var groups: [MemberListGroup]
    public var roleDiagnostics: RoleSortDiagnostics
    public var knownMemberCount: Int
    public var knownUserCount: Int
    public var missingUserCount: Int
    public var missingAvatarCount: Int
    public var durationMilliseconds: Int

    public init(
        groups: [MemberListGroup],
        roleDiagnostics: RoleSortDiagnostics,
        knownMemberCount: Int,
        knownUserCount: Int,
        missingUserCount: Int,
        missingAvatarCount: Int,
        durationMilliseconds: Int
    ) {
        self.groups = groups
        self.roleDiagnostics = roleDiagnostics
        self.knownMemberCount = knownMemberCount
        self.knownUserCount = knownUserCount
        self.missingUserCount = missingUserCount
        self.missingAvatarCount = missingAvatarCount
        self.durationMilliseconds = durationMilliseconds
    }
}

public enum Phase52MemberListPreparer {
    public static func prepare(
        server: Server,
        snapshot: RealtimeSnapshot,
        identitySnapshots: Phase43IdentitySnapshotStore,
        query: String
    ) throws -> Phase52MemberListPreparation {
        let started = ContinuousClock.now
        try Task.checkCancellation()
        let result = MemberListDeriver.result(server: server, snapshot: snapshot, query: query)
        let groups = try result.groups.enumerated().map { groupIndex, group in
            if groupIndex.isMultiple(of: 8) {
                try Task.checkCancellation()
            }
            return MemberListGroup(
                id: group.id,
                title: group.title,
                items: group.items.map { item in
                    let display = identitySnapshots.resolvedDisplay(
                        userID: item.userID,
                        user: item.user,
                        member: item.member,
                        server: server
                    )
                    return MemberListItem(
                        userID: item.userID,
                        user: item.user,
                        member: item.member,
                        display: display,
                        server: server
                    )
                }
            )
        }
        let serverMembers = snapshot.membersByServerAndUserID.values.filter {
            $0.id.serverID == server.id
        }
        let missingUsers = serverMembers.reduce(into: 0) { count, member in
            if snapshot.usersByID[member.id.userID] == nil {
                count += 1
            }
        }
        let missingAvatars = groups.reduce(into: 0) { count, group in
            count += group.items.reduce(into: 0) { itemCount, item in
                if item.avatar == nil {
                    itemCount += 1
                }
            }
        }
        let duration = started.duration(to: .now)
        let milliseconds = Int(duration.components.seconds * 1_000)
            + Int(duration.components.attoseconds / 1_000_000_000_000_000)
        return Phase52MemberListPreparation(
            groups: groups,
            roleDiagnostics: result.diagnostics,
            knownMemberCount: serverMembers.count,
            knownUserCount: snapshot.usersByID.count,
            missingUserCount: missingUsers,
            missingAvatarCount: missingAvatars,
            durationMilliseconds: milliseconds
        )
    }
}

public enum Phase52TimelineInteractionPreparer {
    public static func actionItems(
        for timelineMessage: TimelineMessage,
        currentUserID: UserID?,
        channel: Channel?,
        permissions: Permissions?,
        isRuntimeSendCapable: Bool,
        developerControlsEnabled: Bool
    ) -> [MessageActionItem] {
        let message = timelineMessage.message
        let isConfirmed = timelineMessage.status == .confirmed
        let canReact = message.system == nil
            && channel != nil
            && isRuntimeSendCapable
            && (permissions?.contains(.react) ?? true)
        let canEdit = isConfirmed
            && message.system == nil
            && message.content?.isEmpty == false
            && currentUserID == message.authorID
            && isRuntimeSendCapable
        let canDelete: Bool
        switch timelineMessage.status {
        case .failed:
            canDelete = true
        case .pending, .retrying, .deleting:
            canDelete = false
        case .confirmed:
            canDelete = message.system == nil
                && isRuntimeSendCapable
                && (
                    currentUserID == message.authorID
                        || permissions?.contains(.manageMessages) == true
                )
        }
        let canPin = isConfirmed
            && message.system == nil
            && channel != nil
            && isRuntimeSendCapable
            && (permissions?.contains(.manageMessages) ?? true)
        let canReply = isConfirmed
            && message.system == nil
            && channel != nil
            && isRuntimeSendCapable
        let context = MessageActionContext(
            timelineMessage: timelineMessage,
            currentUserID: currentUserID,
            canReply: canReply,
            canEdit: canEdit,
            canDelete: canDelete,
            canReact: canReact,
            canPin: canPin,
            developerControlsEnabled: developerControlsEnabled
        )
        let items = Phase17MessageActions.actionItems(for: context)
        guard message.system != nil else { return items }
        return items.filter { item in
            item.kind == .copyText || item.kind == .copyMessageID
        }
    }

    public static func systemEventPresentation(
        for message: Message,
        snapshot: RealtimeSnapshot,
        identitySnapshots: Phase43IdentitySnapshotStore
    ) -> SystemEventPresentation? {
        guard message.system != nil else { return nil }
        let serverID = snapshot.channelsByID[message.channelID]?.serverID
        let server = serverID.flatMap { snapshot.serversByID[$0] }
        return Phase27SystemEventPresenter.presentation(for: message) { userID, role in
            let member = serverID.flatMap {
                snapshot.membersByServerAndUserID[ServerMemberKey(serverID: $0, userID: userID)]
            }
            let user = snapshot.usersByID[userID]
            let display = identitySnapshots.resolvedDisplay(
                userID: userID,
                user: user,
                member: member,
                server: server
            )
            guard !display.isFallback else { return nil }
            let confidence: SystemEventParticipantConfidence = member != nil || user != nil ? .high : .medium
            return SystemEventParticipant(
                userID: userID,
                role: role,
                display: display,
                confidence: confidence
            )
        }
    }
}

public struct Phase52TimelineAssetContext: Sendable {
    private var snapshot: RealtimeSnapshot
    private var customEmojiByShortcode: [String: [CustomEmojiDisplayItem]]
    private var imageDataByKey: [ImageCacheKey: Data]
    private var attachmentStates: [String: AttachmentPreviewState]
    private var loadedAttachments: [String: RemoteAttachmentData]
    private var localAttachmentIDs: Set<String>

    public init(
        snapshot: RealtimeSnapshot,
        imageDataByKey: [ImageCacheKey: Data],
        attachmentStates: [String: AttachmentPreviewState],
        loadedAttachments: [String: RemoteAttachmentData],
        localAttachmentIDs: Set<String>
    ) {
        self.snapshot = snapshot
        self.imageDataByKey = imageDataByKey
        self.attachmentStates = attachmentStates
        self.loadedAttachments = loadedAttachments
        self.localAttachmentIDs = localAttachmentIDs
        self.customEmojiByShortcode = Dictionary(
            grouping: snapshot.emojisByID.values.map(CustomEmojiDisplayItem.init(emoji:)),
            by: { $0.shortcode.lowercased() }
        )
    }

    public func inlineCustomEmojiItems(for message: Message) -> [MessageInlineCustomEmojiItem] {
        guard let content = message.content, content.contains(":") else { return [] }
        let serverID = snapshot.channelsByID[message.channelID]?.serverID
        var seen: Set<String> = []
        var result: [MessageInlineCustomEmojiItem] = []
        var remaining = content[...]
        while let start = remaining.firstIndex(of: ":"),
              let end = remaining[remaining.index(after: start)...].firstIndex(of: ":") {
            let raw = String(remaining[start...end])
            let key = raw.lowercased()
            if seen.insert(key).inserted,
               let candidates = customEmojiByShortcode[key],
               let item = candidates.first(where: { serverID == nil || $0.serverID == nil || $0.serverID == serverID }) {
                result.append(
                    MessageInlineCustomEmojiItem(
                        shortcode: item.shortcode,
                        name: item.name,
                        imageData: imageDataByKey[ImageCacheKey(id: item.file.id.rawValue, kind: .customEmoji)]
                    )
                )
            }
            remaining = remaining[remaining.index(after: end)...]
        }
        return result
    }

    public func attachmentItems(for message: Message) -> [AttachmentDisplayItem] {
        (message.attachments ?? []).map { file in
            let id = "file-\(file.id.rawValue)"
            var item = AttachmentDisplayItem(
                file: file,
                previewState: attachmentStates[id] ?? .notLoaded
            )
            if let loaded = loadedAttachments[id] {
                item.previewState = .readyRemote
                item.previewData = loaded.data
            }
            if localAttachmentIDs.contains(id) {
                item.previewState = .readyLocal
            }
            return item
        }
    }

    public func embedItems(for message: Message) -> [MessageEmbedDisplayItem] {
        (message.embeds ?? []).enumerated().map { index, embed in
            let mediaItem = embed.media.map { file -> AttachmentDisplayItem in
                let id = "file-\(file.id.rawValue)"
                let imageKey = ImageCacheKey(id: file.id.rawValue, kind: .attachmentPreview)
                var item = AttachmentDisplayItem(
                    file: file,
                    previewState: attachmentStates[id] ?? .notLoaded
                )
                if let loaded = loadedAttachments[id] {
                    item.previewState = .readyRemote
                    item.previewData = loaded.data
                } else if let data = imageDataByKey[imageKey] {
                    item.previewState = .readyRemote
                    item.previewData = data
                }
                if localAttachmentIDs.contains(id) {
                    item.previewState = .readyLocal
                }
                return item
            }
            return MessageEmbedDisplayItem(
                id: "embed-\(message.id.rawValue)-\(index)",
                embed: embed,
                mediaItem: mediaItem,
                mediaPreviewData: mediaItem?.previewData
            )
        }
    }

    public func reactionItems(for message: Message, currentUserID: UserID?) -> [MessageReactionDisplayItem] {
        Phase17MessageActions.reactionSummaries(for: message, currentUserID: currentUserID).map { summary in
            if let emoji = snapshot.emojisByID.values.first(where: {
                $0.id.rawValue == summary.emoji || $0.name == summary.emoji
            }) {
                let displayItem = CustomEmojiDisplayItem(emoji: emoji)
                return MessageReactionDisplayItem(
                    emoji: summary.emoji,
                    count: summary.count,
                    hasCurrentUserReacted: summary.hasCurrentUserReacted,
                    customEmojiName: emoji.name,
                    customEmojiImageData: imageDataByKey[
                        ImageCacheKey(id: displayItem.file.id.rawValue, kind: .customEmoji)
                    ]
                )
            }
            return MessageReactionDisplayItem(
                emoji: summary.emoji,
                count: summary.count,
                hasCurrentUserReacted: summary.hasCurrentUserReacted
            )
        }
    }
}
