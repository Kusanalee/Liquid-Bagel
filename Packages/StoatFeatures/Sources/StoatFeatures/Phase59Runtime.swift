import Foundation
import StoatModels

enum ImageResourceRequestPriority: Int, Comparable, Sendable {
    case visibleTimeline = 0
    case visibleMember = 1
    case shellCritical = 2
    case identity = 3
    case media = 4
    case background = 5

    static func < (lhs: ImageResourceRequestPriority, rhs: ImageResourceRequestPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct PrioritizedImageResourceRequest: Sendable {
    var request: ImageResourceRequest
    var priority: ImageResourceRequestPriority
    var sequence: UInt64
}

struct ReactionMutationKey: Hashable, Sendable {
    var channelID: ChannelID
    var messageID: MessageID
    var emoji: String
}

public struct Phase59ReactionDiagnostics: Hashable, Sendable {
    public var attemptCount: Int
    public var optimisticMutationCount: Int
    public var successCount: Int
    public var rollbackCount: Int
    public var deduplicatedCount: Int
    public var unavailableCount: Int
    public var lastOutcome: String?

    public init(
        attemptCount: Int = 0,
        optimisticMutationCount: Int = 0,
        successCount: Int = 0,
        rollbackCount: Int = 0,
        deduplicatedCount: Int = 0,
        unavailableCount: Int = 0,
        lastOutcome: String? = nil
    ) {
        self.attemptCount = attemptCount
        self.optimisticMutationCount = optimisticMutationCount
        self.successCount = successCount
        self.rollbackCount = rollbackCount
        self.deduplicatedCount = deduplicatedCount
        self.unavailableCount = unavailableCount
        self.lastOutcome = lastOutcome
    }
}
