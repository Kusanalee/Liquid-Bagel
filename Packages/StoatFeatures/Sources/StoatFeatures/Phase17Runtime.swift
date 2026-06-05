import Foundation
import StoatModels

#if canImport(AppKit)
import AppKit
#endif

public enum MessageActionRole: Hashable, Sendable {
    case standard
    case destructive
}

public enum MessageActionKind: Hashable, Sendable {
    case copyText
    case copyMessageID
    case reply
    case edit
    case delete
    case discardFailed
    case retry
    case editAndRetry
    case pin
    case unpin
    case addReaction(String)
    case removeReaction(String)
}

public enum MessageActionAvailability: Hashable, Sendable {
    case available
    case disabled(String)
    case hidden

    public var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    public var isVisible: Bool {
        if case .hidden = self { return false }
        return true
    }
}

public struct MessageActionItem: Identifiable, Hashable, Sendable {
    public var id: String
    public var kind: MessageActionKind
    public var title: String
    public var systemImage: String
    public var role: MessageActionRole
    public var availability: MessageActionAvailability
    public var isPrimary: Bool

    public init(
        kind: MessageActionKind,
        title: String,
        systemImage: String,
        role: MessageActionRole = .standard,
        availability: MessageActionAvailability = .available,
        isPrimary: Bool = false
    ) {
        self.kind = kind
        self.id = kind.stableID
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.availability = availability
        self.isPrimary = isPrimary
    }
}

public struct MessageActionContext: Hashable, Sendable {
    public var timelineMessage: TimelineMessage
    public var currentUserID: UserID?
    public var canReply: Bool
    public var canEdit: Bool
    public var canDelete: Bool
    public var canReact: Bool
    public var canPin: Bool
    public var developerControlsEnabled: Bool

    public init(
        timelineMessage: TimelineMessage,
        currentUserID: UserID?,
        canReply: Bool,
        canEdit: Bool,
        canDelete: Bool,
        canReact: Bool,
        canPin: Bool,
        developerControlsEnabled: Bool
    ) {
        self.timelineMessage = timelineMessage
        self.currentUserID = currentUserID
        self.canReply = canReply
        self.canEdit = canEdit
        self.canDelete = canDelete
        self.canReact = canReact
        self.canPin = canPin
        self.developerControlsEnabled = developerControlsEnabled
    }
}

public struct ReactionSummary: Identifiable, Hashable, Sendable {
    public var emoji: String
    public var count: Int
    public var hasCurrentUserReacted: Bool

    public var id: String { emoji }

    public init(emoji: String, count: Int, hasCurrentUserReacted: Bool) {
        self.emoji = emoji
        self.count = count
        self.hasCurrentUserReacted = hasCurrentUserReacted
    }
}

public protocol MessageCopying: Sendable {
    func copy(_ value: String) async
}

public struct AppKitMessageCopier: MessageCopying {
    public init() {}

    public func copy(_ value: String) async {
        #if canImport(AppKit)
        await MainActor.run {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
        }
        #endif
    }
}

public actor MockMessageCopier: MessageCopying {
    public private(set) var copiedValues: [String] = []

    public init() {}

    public func copy(_ value: String) async {
        copiedValues.append(value)
    }

    public func lastCopiedValue() -> String? {
        copiedValues.last
    }
}

public struct MessageActionDiagnostics: Hashable, Sendable {
    public var visibleActionCount: Int
    public var availableActionCount: Int
    public var reactionGroupCount: Int
    public var currentUserReactionCount: Int
    public var hasPendingDeleteConfirmation: Bool

    public init(
        visibleActionCount: Int = 0,
        availableActionCount: Int = 0,
        reactionGroupCount: Int = 0,
        currentUserReactionCount: Int = 0,
        hasPendingDeleteConfirmation: Bool = false
    ) {
        self.visibleActionCount = visibleActionCount
        self.availableActionCount = availableActionCount
        self.reactionGroupCount = reactionGroupCount
        self.currentUserReactionCount = currentUserReactionCount
        self.hasPendingDeleteConfirmation = hasPendingDeleteConfirmation
    }
}

public enum Phase17MessageActions {
    public static let quickReactions = ["👍", "❤️", "😂", "🥯", "✅", "👀", "🎉", "🙏"]

    public static func actionItems(for context: MessageActionContext) -> [MessageActionItem] {
        let timelineMessage = context.timelineMessage
        let message = timelineMessage.message
        let hasCopyableText = copyableText(for: message)?.isEmpty == false
        let stableID = stableMessageID(for: timelineMessage) != nil
        let isFailed = timelineMessage.status.failedMetadata != nil
        let isConfirmed = timelineMessage.status == .confirmed

        var items: [MessageActionItem] = []
        items.append(MessageActionItem(
            kind: .copyText,
            title: "Copy Text",
            systemImage: "doc.on.doc",
            availability: hasCopyableText ? .available : .disabled("Message has no copyable text.")
        ))
        items.append(MessageActionItem(
            kind: .copyMessageID,
            title: "Copy Message ID",
            systemImage: "number",
            availability: context.developerControlsEnabled && stableID ? .available : .hidden
        ))
        items.append(MessageActionItem(
            kind: .reply,
            title: "Reply",
            systemImage: "arrowshape.turn.up.left",
            availability: context.canReply ? .available : .hidden,
            isPrimary: context.canReply
        ))
        items.append(MessageActionItem(
            kind: .edit,
            title: "Edit Message",
            systemImage: "pencil",
            availability: context.canEdit ? .available : .hidden
        ))
        if isFailed {
            items.append(MessageActionItem(
                kind: .retry,
                title: "Retry Send",
                systemImage: "arrow.clockwise",
                availability: .available,
                isPrimary: true
            ))
            items.append(MessageActionItem(
                kind: .editAndRetry,
                title: "Edit & Retry",
                systemImage: "pencil.and.outline",
                availability: .available
            ))
            items.append(MessageActionItem(
                kind: .discardFailed,
                title: "Discard Failed Message",
                systemImage: "trash",
                role: .destructive,
                availability: context.canDelete ? .available : .hidden
            ))
        } else {
            items.append(MessageActionItem(
                kind: .delete,
                title: "Delete Message",
                systemImage: "trash",
                role: .destructive,
                availability: context.canDelete && isConfirmed ? .available : .hidden
            ))
        }
        items.append(MessageActionItem(
            kind: message.isPinned ? .unpin : .pin,
            title: message.isPinned ? "Unpin Message" : "Pin Message",
            systemImage: message.isPinned ? "pin.slash" : "pin",
            availability: context.canPin ? .available : .hidden
        ))

        if context.canReact {
            for emoji in quickReactions {
                let hasReacted = currentUserHasReacted(to: message, emoji: emoji, currentUserID: context.currentUserID)
                items.append(MessageActionItem(
                    kind: hasReacted ? .removeReaction(emoji) : .addReaction(emoji),
                    title: hasReacted ? "Remove \(emoji)" : "React \(emoji)",
                    systemImage: hasReacted ? "minus.circle" : "plus.circle",
                    availability: .available
                ))
            }
        }

        return items.filter { $0.availability.isVisible }
    }

    public static func reactionSummaries(for message: Message, currentUserID: UserID?) -> [ReactionSummary] {
        message.reactions
            .filter { !$0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.value.isEmpty }
            .map { emoji, users in
                ReactionSummary(
                    emoji: emoji,
                    count: users.count,
                    hasCurrentUserReacted: currentUserID.map { users.contains($0) } ?? false
                )
            }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count { return lhs.emoji < rhs.emoji }
                return lhs.count > rhs.count
            }
    }

    public static func copyableText(for message: Message) -> String? {
        if let content = message.content?.trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty {
            return content
        }
        if let system = message.system?.content?.trimmingCharacters(in: .whitespacesAndNewlines), !system.isEmpty {
            return system
        }
        return nil
    }

    public static func stableMessageID(for timelineMessage: TimelineMessage) -> MessageID? {
        guard timelineMessage.status == .confirmed else { return nil }
        guard !timelineMessage.message.id.rawValue.hasPrefix("pending-") else { return nil }
        return timelineMessage.message.id
    }

    public static func currentUserHasReacted(to message: Message, emoji: String, currentUserID: UserID?) -> Bool {
        guard let currentUserID else { return false }
        return message.reactions[emoji]?.contains(currentUserID) == true
    }

    public static func diagnostics(
        actions: [MessageActionItem],
        reactions: [ReactionSummary],
        hasPendingDeleteConfirmation: Bool
    ) -> MessageActionDiagnostics {
        MessageActionDiagnostics(
            visibleActionCount: actions.count,
            availableActionCount: actions.filter(\.availability.isAvailable).count,
            reactionGroupCount: reactions.count,
            currentUserReactionCount: reactions.filter(\.hasCurrentUserReacted).count,
            hasPendingDeleteConfirmation: hasPendingDeleteConfirmation
        )
    }

    public static func redactedDiagnosticText(_ value: String) -> String {
        var redacted = value
        redacted = replace(redacted, pattern: #"https?://\S+"#, with: "[redacted-url]")
        redacted = replace(redacted, pattern: #"/(?:Users|tmp|var|private|Volumes)/[^\s,;\)]+"#, with: "[redacted-path]")
        redacted = replace(redacted, pattern: #"(?i)(authorization|token|session|password|secret|auth)[\s:=]+"[^"\s]+"?"#, with: "$1=[redacted]")
        redacted = replace(redacted, pattern: #"\{[^\n]*(token|authorization|session|password|secret|error)[^\n]*\}"#, with: "[redacted-payload]")
        return redacted
    }

    private static func replace(_ value: String, pattern: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return value }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.stringByReplacingMatches(in: value, range: range, withTemplate: replacement)
    }
}

public extension MessageActionKind {
    var stableID: String {
        switch self {
        case .copyText:
            return "copyText"
        case .copyMessageID:
            return "copyMessageID"
        case .reply:
            return "reply"
        case .edit:
            return "edit"
        case .delete:
            return "delete"
        case .discardFailed:
            return "discardFailed"
        case .retry:
            return "retry"
        case .editAndRetry:
            return "editAndRetry"
        case .pin:
            return "pin"
        case .unpin:
            return "unpin"
        case let .addReaction(emoji):
            return "addReaction-\(emoji)"
        case let .removeReaction(emoji):
            return "removeReaction-\(emoji)"
        }
    }
}
