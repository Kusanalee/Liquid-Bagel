import Foundation
import StoatModels
import StoatUI

/// Phase 58: state for group DM member add/remove, built on the verified
/// `PUT/DELETE /channels/{target}/recipients/{member}` routes (Docs/Research.md Phase 58 Notes).
public enum GroupMembershipActionState: Hashable, Sendable {
    case idle
    case working
    case failed(String)
}

public struct PendingGroupMemberRemoval: Hashable, Sendable, Identifiable {
    public var id: String { "\(channelID.rawValue)-\(userID.rawValue)" }
    public var channelID: ChannelID
    public var userID: UserID
    public var displayName: String

    public init(channelID: ChannelID, userID: UserID, displayName: String) {
        self.channelID = channelID
        self.userID = userID
        self.displayName = displayName
    }
}

/// Phase 58: candidates for composer `@` autocomplete, sorted once per rebuild and queried by
/// prefix binary search so a run of keystrokes within the same query never re-derives the whole
/// candidate list from server members/DM recipients/friends (see Docs/Research.md Phase 58 Notes
/// on avoiding per-keystroke O(N) scans).
public struct Phase58MentionCandidateIndex: Sendable {
    private struct Entry: Sendable {
        let searchKey: String
        let candidate: ComposerMentionCandidate
    }

    private let entries: [Entry]

    public init(candidates: [ComposerMentionCandidate]) {
        var seen: Set<UserID> = []
        var built: [Entry] = []
        built.reserveCapacity(candidates.count)
        for candidate in candidates where seen.insert(candidate.userID).inserted {
            built.append(Entry(searchKey: candidate.name.lowercased(), candidate: candidate))
        }
        entries = built.sorted { $0.searchKey < $1.searchKey }
    }

    public var isEmpty: Bool { entries.isEmpty }

    public func matches(prefix: String, limit: Int) -> [ComposerMentionCandidate] {
        let query = prefix.lowercased()
        guard !query.isEmpty else {
            return entries.prefix(limit).map(\.candidate)
        }
        var low = 0
        var high = entries.count
        while low < high {
            let mid = (low + high) / 2
            if entries[mid].searchKey < query {
                low = mid + 1
            } else {
                high = mid
            }
        }
        var result: [ComposerMentionCandidate] = []
        var index = low
        while index < entries.count, result.count < limit, entries[index].searchKey.hasPrefix(query) {
            result.append(entries[index].candidate)
            index += 1
        }
        return result
    }
}
