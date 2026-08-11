import Foundation
import StoatAPI
import StoatModels
import StoatPersistence
import StoatRealtime

// Phase 74 -- keeping the offline cache current.
//
// The mapping between `RealtimeSnapshot` and the on-disk DTOs lives here rather than in
// StoatPersistence, which depends only on StoatAPI and StoatModels. That is on purpose: the disk
// format has to version independently of an in-memory type that changes for gateway reasons, and
// this file is exactly where the translation between the two belongs.

public enum SessionCacheMapper {
    /// Member rosters are the single largest thing on disk. Capped per server because a heavy
    /// account with hundreds of servers would otherwise turn a 60 MB cache into a 600 MB one for
    /// a panel that is rarely why anyone opens the app offline.
    public static let maximumMembersPerServer = 2_000
    /// Only the most recently selected servers keep a roster at all.
    public static let maximumCachedMemberServers = 5
    public static let maximumCachedUsers = 5_000

    public static func graph(from snapshot: RealtimeSnapshot) -> CachedServerGraph {
        CachedServerGraph(
            servers: Array(snapshot.serversByID.values),
            channels: Array(snapshot.channelsByID.values),
            emojis: Array(snapshot.emojisByID.values)
        )
    }

    public static func users(from snapshot: RealtimeSnapshot) -> CachedUserDirectory {
        CachedUserDirectory(users: Array(snapshot.usersByID.values.prefix(maximumCachedUsers)))
    }

    public static func unreads(from snapshot: RealtimeSnapshot) -> CachedUnreads {
        CachedUnreads(unreads: Array(snapshot.unreadsByChannelID.values))
    }

    public static func members(from snapshot: RealtimeSnapshot, serverID: ServerID) -> CachedServerMembers {
        let members = snapshot.membersByServerAndUserID
            .filter { $0.key.serverID == serverID }
            .values
            .prefix(maximumMembersPerServer)
        return CachedServerMembers(serverID: serverID, members: Array(members))
    }

    public static func readStates(from states: [ChannelID: LocalReadState], now: Date) -> CachedReadStates {
        CachedReadStates(states: states.values.map {
            CachedLocalReadState(
                channelID: $0.channelID,
                firstUnreadMessageID: $0.firstUnreadMessageID,
                lastReadMessageID: $0.lastReadMessageID,
                unreadCount: $0.unreadCount,
                mentionCount: $0.mentionCount,
                updatedAt: now
            )
        })
    }

    /// Rebuild an in-memory snapshot from what was on disk.
    ///
    /// Messages and typing state are deliberately absent. Messages belong to the channel message
    /// cache, which hydrates per channel on demand; typing state describes a moment that has
    /// definitively passed.
    public static func snapshot(from cache: LoadedSessionCache) -> RealtimeSnapshot {
        var snapshot = RealtimeSnapshot()
        if let graph = cache.graph {
            snapshot.serversByID = Dictionary(graph.servers.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
            snapshot.channelsByID = Dictionary(graph.channels.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
            snapshot.emojisByID = Dictionary(graph.emojis.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        }
        if let users = cache.users {
            snapshot.usersByID = Dictionary(users.users.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        }
        if let currentUser = cache.core?.currentUser {
            snapshot.usersByID[currentUser.id] = currentUser
        }
        if let unreads = cache.unreads {
            snapshot.unreadsByChannelID = Dictionary(
                unreads.unreads.map { ($0.id.channelID, $0) },
                uniquingKeysWith: { _, last in last }
            )
        }
        for (serverID, shard) in cache.membersByServerID {
            for member in shard.members {
                snapshot.membersByServerAndUserID[ServerMemberKey(serverID: serverID, userID: member.id.userID)] = member
            }
        }
        return snapshot
    }

    /// Reconcile read markers restored from disk against fresh server truth.
    ///
    /// Local read state is optimistic: it exists so marking a channel read feels instant before
    /// the ack lands. Restored from disk it is also *stale*, so it may only ever be more
    /// conservative than the server. It must never invent unread badges for channels the server
    /// says are read, and it must never survive being overtaken.
    public static func reconcileReadStates(
        cached: [CachedLocalReadState],
        snapshot: RealtimeSnapshot,
        now: Date,
        maximumAge: TimeInterval = 30 * 24 * 60 * 60
    ) -> [ChannelID: LocalReadState] {
        var result: [ChannelID: LocalReadState] = [:]
        for entry in cached {
            // The channel is gone.
            guard snapshot.channelsByID[entry.channelID] != nil else { continue }
            // Old enough that it is more likely to be wrong than useful.
            guard now.timeIntervalSince(entry.updatedAt) <= maximumAge else { continue }

            if let serverLastRead = snapshot.unreadsByChannelID[entry.channelID]?.lastMessageID {
                // ULIDs sort chronologically, so a lexicographic comparison is a time comparison.
                // If the server has read at least as far as we had, its answer wins.
                guard let localLastRead = entry.lastReadMessageID,
                      localLastRead.rawValue > serverLastRead.rawValue
                else { continue }
            }

            result[entry.channelID] = LocalReadState(
                channelID: entry.channelID,
                firstUnreadMessageID: entry.firstUnreadMessageID,
                lastReadMessageID: entry.lastReadMessageID,
                unreadCount: entry.unreadCount,
                mentionCount: entry.mentionCount
            )
        }
        return result
    }
}

/// Decides which shards a gateway update dirtied, coalesces the churn, and writes.
///
/// The reason this is affordable at all: `RealtimeSnapshotChangeSet` already distinguishes message
/// and typing traffic -- the overwhelming majority of events -- from the structural changes that
/// actually need persisting. Those events dirty nothing.
@MainActor
public final class SessionCacheWriter {
    /// How long the snapshot must stay still before a flush.
    public static let quiesceDelay: Duration = .seconds(5)
    /// Ceiling since the first dirty mark, so a permanently busy account still checkpoints.
    public static let maximumDelay: TimeInterval = 60

    private let store: any SessionSnapshotStoring
    private let environmentID: String
    private let userID: UserID

    private var dirtyShards: Set<SessionCacheShard> = []
    private var firstDirtyAt: Date?
    private var flushTask: Task<Void, Never>?
    private var latestSnapshot: RealtimeSnapshot?
    private var latestReadStates: [ChannelID: LocalReadState] = [:]
    /// Rosters are only kept for servers the user actually visits.
    private var recentlySelectedServerIDs: [ServerID] = []

    public private(set) var writeCount = 0
    public private(set) var skippedUpdateCount = 0

    public init(store: any SessionSnapshotStoring, environmentID: String, userID: UserID) {
        self.store = store
        self.environmentID = environmentID
        self.userID = userID
    }

    deinit {
        flushTask?.cancel()
    }

    public func noteServerSelected(_ serverID: ServerID) {
        recentlySelectedServerIDs.removeAll { $0 == serverID }
        recentlySelectedServerIDs.insert(serverID, at: 0)
        if recentlySelectedServerIDs.count > SessionCacheMapper.maximumCachedMemberServers {
            recentlySelectedServerIDs.removeLast()
        }
    }

    public func note(_ update: RealtimeSnapshotUpdate) {
        latestSnapshot = update.snapshot
        let shards = Self.dirtyShards(for: update.changes, recentServerIDs: recentlySelectedServerIDs)
        guard !shards.isEmpty else {
            skippedUpdateCount += 1
            return
        }
        markDirty(shards)
    }

    public func noteReadStatesChanged(_ states: [ChannelID: LocalReadState]) {
        latestReadStates = states
        markDirty([.readStates])
    }

    /// Which shards an update actually touched.
    ///
    /// `messageChannelIDs`, `insertedMessages`, `deletedMessageIDsByChannelID`, `typingChannelIDs`
    /// and `policyChangesChanged` map to nothing on purpose. Messages live in the channel message
    /// cache, typing describes a moment that has already passed, and policy changes are
    /// server-driven and worthless stale.
    nonisolated static func dirtyShards(
        for changes: RealtimeSnapshotChangeSet,
        recentServerIDs: [ServerID]
    ) -> Set<SessionCacheShard> {
        if changes.isFullReplacement {
            var shards: Set<SessionCacheShard> = [.core, .graph, .users, .unreads]
            for serverID in recentServerIDs { shards.insert(.members(serverID)) }
            return shards
        }

        var shards: Set<SessionCacheShard> = []
        if !changes.serverIDs.isEmpty || !changes.channelIDs.isEmpty || !changes.emojiIDs.isEmpty {
            shards.insert(.graph)
        }
        if !changes.userIDs.isEmpty { shards.insert(.users) }
        if !changes.unreadChannelIDs.isEmpty { shards.insert(.unreads) }
        if changes.userSettingsChanged { shards.insert(.core) }

        // Only rewrite a roster that is already being kept.
        let touchedServerIDs = Set(changes.memberKeys.map(\.serverID))
            .union(changes.removedMemberKeys.map(\.serverID))
        for serverID in touchedServerIDs where recentServerIDs.contains(serverID) {
            shards.insert(.members(serverID))
        }
        return shards
    }

    private func markDirty(_ shards: Set<SessionCacheShard>) {
        dirtyShards.formUnion(shards)
        if firstDirtyAt == nil { firstDirtyAt = Date() }
        scheduleFlush()
    }

    private func scheduleFlush() {
        flushTask?.cancel()
        // The ceiling matters for an account that never goes quiet: without it, a busy server
        // would reset the debounce forever and nothing would ever reach disk.
        let elapsed = firstDirtyAt.map { Date().timeIntervalSince($0) } ?? 0
        let remaining = max(0, Self.maximumDelay - elapsed)
        let delay = min(Self.quiesceDelay, .seconds(remaining))
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }

    /// Write everything dirty right now.
    ///
    /// Called on disconnect, backgrounding, sleep, and termination. The disconnect flush is the
    /// most valuable of those: it captures precisely the snapshot the next offline launch needs.
    public func flush() async {
        flushTask?.cancel()
        flushTask = nil
        let shards = dirtyShards
        dirtyShards.removeAll()
        firstDirtyAt = nil
        guard !shards.isEmpty, let snapshot = latestSnapshot else { return }

        var batch = SessionCacheWriteBatch()
        if shards.contains(.graph) { batch.graph = SessionCacheMapper.graph(from: snapshot) }
        if shards.contains(.users) { batch.users = SessionCacheMapper.users(from: snapshot) }
        if shards.contains(.unreads) { batch.unreads = SessionCacheMapper.unreads(from: snapshot) }
        if shards.contains(.readStates) {
            batch.readStates = SessionCacheMapper.readStates(from: latestReadStates, now: Date())
        }
        for shard in shards {
            if case let .members(serverID) = shard {
                batch.members.append(SessionCacheMapper.members(from: snapshot, serverID: serverID))
            }
        }
        guard !batch.isEmpty else { return }
        writeCount += 1
        await store.write(batch, environmentID: environmentID, userID: userID)
    }

    /// Written separately from the shard batch because it is keyed by environment rather than by
    /// account -- it is what tells the next launch which account directory to look in.
    public func writeIdentity() async {
        await store.writeIdentity(
            CachedSessionIdentity(userID: userID, savedAt: Date()),
            environmentID: environmentID
        )
    }

    public func writeCore(currentUser: User) async {
        await store.write(
            SessionCacheWriteBatch(core: CachedSessionCore(currentUser: currentUser)),
            environmentID: environmentID,
            userID: userID
        )
    }
}
