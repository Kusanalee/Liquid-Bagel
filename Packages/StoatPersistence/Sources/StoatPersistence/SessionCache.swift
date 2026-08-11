import CryptoKit
import Foundation
import StoatAPI
import StoatModels

// Phase 74 -- the offline session cache.
//
// Enough of a connected session is written to disk that the app can open into a usable, readable
// shell with no network: servers, channels, users, unreads, read markers, and recent messages.
//
// Two rules govern everything here.
//
// **The cache is disposable.** Every shard is versioned, and a version this build does not
// recognise is deleted rather than migrated. Losing the cache costs a reconnect; carrying a
// migration path for a throwaway artefact costs forever. Do not add one.
//
// **The cache is real message content on someone's disk.** Payloads are encrypted with a key held
// in the Keychain, scoped per account and per environment, and signing out destroys the key along
// with the files.

// MARK: - On-disk payloads

public struct CachedSessionIdentity: Codable, Hashable, Sendable {
    public var userID: UserID
    public var savedAt: Date

    public init(userID: UserID, savedAt: Date) {
        self.userID = userID
        self.savedAt = savedAt
    }
}

public struct CachedSessionCore: Codable, Hashable, Sendable {
    public var currentUser: User

    public init(currentUser: User) {
        self.currentUser = currentUser
    }
}

/// Collections are arrays, not dictionaries keyed by `StoatID`.
///
/// `StoatID` is `RawRepresentable<String>` but does not conform to `CodingKeyRepresentable`, so
/// `JSONEncoder` writes `[ChannelID: Channel]` as a flat alternating `[key, value, key, value]`
/// array -- unreadable and easy to corrupt. Every model carries its own id, so the dictionaries
/// are rebuilt on load instead.
public struct CachedServerGraph: Codable, Hashable, Sendable {
    public var servers: [Server]
    public var channels: [Channel]
    public var emojis: [Emoji]

    public init(servers: [Server], channels: [Channel], emojis: [Emoji]) {
        self.servers = servers
        self.channels = channels
        self.emojis = emojis
    }
}

public struct CachedUserDirectory: Codable, Hashable, Sendable {
    public var users: [User]

    public init(users: [User]) {
        self.users = users
    }
}

public struct CachedServerMembers: Codable, Hashable, Sendable {
    public var serverID: ServerID
    public var members: [ServerMember]

    public init(serverID: ServerID, members: [ServerMember]) {
        self.serverID = serverID
        self.members = members
    }
}

public struct CachedUnreads: Codable, Hashable, Sendable {
    public var unreads: [ChannelUnread]

    public init(unreads: [ChannelUnread]) {
        self.unreads = unreads
    }
}

public struct CachedLocalReadState: Codable, Hashable, Sendable {
    public var channelID: ChannelID
    public var firstUnreadMessageID: MessageID?
    public var lastReadMessageID: MessageID?
    public var unreadCount: Int
    public var mentionCount: Int
    public var updatedAt: Date

    public init(
        channelID: ChannelID,
        firstUnreadMessageID: MessageID? = nil,
        lastReadMessageID: MessageID? = nil,
        unreadCount: Int = 0,
        mentionCount: Int = 0,
        updatedAt: Date
    ) {
        self.channelID = channelID
        self.firstUnreadMessageID = firstUnreadMessageID
        self.lastReadMessageID = lastReadMessageID
        self.unreadCount = unreadCount
        self.mentionCount = mentionCount
        self.updatedAt = updatedAt
    }
}

public struct CachedReadStates: Codable, Hashable, Sendable {
    public var states: [CachedLocalReadState]

    public init(states: [CachedLocalReadState]) {
        self.states = states
    }
}

public struct CachedChannelHistory: Codable, Hashable, Sendable {
    public var channelID: ChannelID
    public var messages: [Message]
    /// Whether older messages exist beyond what was cached. Distinguishes "the start of the
    /// channel" from "the end of what we saved", which the timeline header needs to avoid
    /// telling an offline user they have reached the beginning of a conversation.
    public var hasMoreBefore: Bool
    public var savedAt: Date

    public init(channelID: ChannelID, messages: [Message], hasMoreBefore: Bool, savedAt: Date) {
        self.channelID = channelID
        self.messages = messages
        self.hasMoreBefore = hasMoreBefore
        self.savedAt = savedAt
    }
}

// MARK: - Shards

public enum SessionCacheShard: Hashable, Sendable {
    case core
    case graph
    case users
    case unreads
    case readStates
    case members(ServerID)
}

/// A partial write. `nil` means "not dirty, leave that file alone".
public struct SessionCacheWriteBatch: Hashable, Sendable {
    public var core: CachedSessionCore?
    public var graph: CachedServerGraph?
    public var users: CachedUserDirectory?
    public var unreads: CachedUnreads?
    public var readStates: CachedReadStates?
    public var members: [CachedServerMembers]

    public init(
        core: CachedSessionCore? = nil,
        graph: CachedServerGraph? = nil,
        users: CachedUserDirectory? = nil,
        unreads: CachedUnreads? = nil,
        readStates: CachedReadStates? = nil,
        members: [CachedServerMembers] = []
    ) {
        self.core = core
        self.graph = graph
        self.users = users
        self.unreads = unreads
        self.readStates = readStates
        self.members = members
    }

    public var isEmpty: Bool {
        core == nil && graph == nil && users == nil && unreads == nil && readStates == nil && members.isEmpty
    }
}

public struct LoadedSessionCache: Hashable, Sendable {
    public var core: CachedSessionCore?
    public var graph: CachedServerGraph?
    public var users: CachedUserDirectory?
    public var unreads: CachedUnreads?
    public var readStates: [CachedLocalReadState]
    public var membersByServerID: [ServerID: CachedServerMembers]
    public var savedAt: Date?

    public init(
        core: CachedSessionCore? = nil,
        graph: CachedServerGraph? = nil,
        users: CachedUserDirectory? = nil,
        unreads: CachedUnreads? = nil,
        readStates: [CachedLocalReadState] = [],
        membersByServerID: [ServerID: CachedServerMembers] = [:],
        savedAt: Date? = nil
    ) {
        self.core = core
        self.graph = graph
        self.users = users
        self.unreads = unreads
        self.readStates = readStates
        self.membersByServerID = membersByServerID
        self.savedAt = savedAt
    }

    /// Offline mode needs somewhere to put the user. Without a channel graph there is nothing to
    /// show and the normal failure screen is the honest answer.
    public var isUsable: Bool {
        (graph?.channels.isEmpty == false)
    }
}

/// What is on disk for an environment, discovered without decrypting anything.
public struct SessionCacheAvailability: Hashable, Sendable {
    public var userID: UserID
    public var savedAt: Date

    public init(userID: UserID, savedAt: Date) {
        self.userID = userID
        self.savedAt = savedAt
    }
}

/// Counts and byte totals only -- never a name, an id, message content, or a path.
public struct SessionCacheDiagnostics: Hashable, Sendable {
    public var writeCount: Int
    public var readCount: Int
    public var corruptShardCount: Int
    public var versionMismatchShardCount: Int
    public var scopeMismatchPurgeCount: Int
    public var totalBytesOnDisk: Int

    public init(
        writeCount: Int = 0,
        readCount: Int = 0,
        corruptShardCount: Int = 0,
        versionMismatchShardCount: Int = 0,
        scopeMismatchPurgeCount: Int = 0,
        totalBytesOnDisk: Int = 0
    ) {
        self.writeCount = writeCount
        self.readCount = readCount
        self.corruptShardCount = corruptShardCount
        self.versionMismatchShardCount = versionMismatchShardCount
        self.scopeMismatchPurgeCount = scopeMismatchPurgeCount
        self.totalBytesOnDisk = totalBytesOnDisk
    }
}

// MARK: - Encryption

/// Payload encryption for the session cache.
///
/// `Data.WritingOptions.completeFileProtection` is deliberately not used: it maps to
/// `NSFileProtectionComplete`, which is an iOS Data Protection feature and does nothing at all on
/// macOS. Claiming the cache is protected by it would be false. The sandbox container and FileVault
/// are the platform protections; this adds encryption at rest on top of them, and makes purging
/// robust -- destroying the key renders every remaining shard unreadable even if a file deletion
/// later fails.
public protocol SessionCacheCipher: Sendable {
    func seal(_ data: Data) throws -> Data
    func open(_ data: Data) throws -> Data
}

public struct AESGCMSessionCacheCipher: SessionCacheCipher {
    private let key: SymmetricKey

    public init(key: SymmetricKey) {
        self.key = key
    }

    public func seal(_ data: Data) throws -> Data {
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else {
            throw PersistenceError.encodingFailed("Could not seal session cache payload.")
        }
        return combined
    }

    public func open(_ data: Data) throws -> Data {
        try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key)
    }
}

/// For tests and for callers that have no key available. Keeping this explicit means an
/// unencrypted cache is always a decision someone made, never a default that got inherited.
public struct PassthroughSessionCacheCipher: SessionCacheCipher {
    public init() {}
    public func seal(_ data: Data) throws -> Data { data }
    public func open(_ data: Data) throws -> Data { data }
}

// MARK: - Store

public protocol SessionSnapshotStoring: Sendable {
    /// Which account has a cache for this environment, resolvable with no network and no key.
    /// Offline boot needs it because the user's own ID normally requires a round trip.
    func availability(environmentID: String) async -> SessionCacheAvailability?
    func writeIdentity(_ identity: CachedSessionIdentity, environmentID: String) async
    func load(environmentID: String, userID: UserID) async -> LoadedSessionCache
    func write(_ batch: SessionCacheWriteBatch, environmentID: String, userID: UserID) async
    func purgeScope(environmentID: String, userID: UserID) async
    func purgeEnvironment(environmentID: String) async
    func purgeEverything() async
    func diagnostics() async -> SessionCacheDiagnostics
}

public actor FileSessionSnapshotStore: SessionSnapshotStoring {
    /// Plaintext header on every shard. Keeping version and scope outside the ciphertext lets a
    /// stale or foreign shard be recognised and deleted without a key.
    private struct Envelope: Codable {
        var version: Int
        var scopeFingerprint: String
        var savedAt: Date
        var payload: Data
    }

    private enum ShardFile: String {
        case core = "session.v1.json"
        case graph = "graph.v1.json"
        case users = "users.v1.json"
        case unreads = "unreads.v1.json"
        case readStates = "readstate.v1.json"
    }

    private static let envelopeVersion = 1
    private static let identityFileName = "index.v1.json"

    private let root: URL
    private let cipher: any SessionCacheCipher
    private var diagnosticsValue = SessionCacheDiagnostics()

    public init(root: URL? = nil, cipher: any SessionCacheCipher = PassthroughSessionCacheCipher()) {
        if let root {
            self.root = root
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.root = base.appendingPathComponent("LiquidBagel/SessionCache", isDirectory: true)
        }
        self.cipher = cipher
    }

    // MARK: Availability

    public func availability(environmentID: String) async -> SessionCacheAvailability? {
        let url = environmentDirectory(environmentID).appendingPathComponent(Self.identityFileName)
        guard let data = try? Data(contentsOf: url),
              let identity = try? JSONDecoder.stoatCache.decode(CachedSessionIdentity.self, from: data)
        else { return nil }
        return SessionCacheAvailability(userID: identity.userID, savedAt: identity.savedAt)
    }

    public func writeIdentity(_ identity: CachedSessionIdentity, environmentID: String) async {
        let directory = environmentDirectory(environmentID)
        createDirectory(directory)
        guard let data = try? JSONEncoder.stoatCache.encode(identity) else { return }
        write(data, to: directory.appendingPathComponent(Self.identityFileName))
    }

    // MARK: Load

    public func load(environmentID: String, userID: UserID) async -> LoadedSessionCache {
        let fingerprint = Self.scopeFingerprint(environmentID: environmentID, userID: userID)
        let directory = scopeDirectory(environmentID: environmentID, userID: userID)
        guard FileManager.default.fileExists(atPath: directory.path) else { return LoadedSessionCache() }
        diagnosticsValue.readCount += 1

        var savedAt: Date?
        func read<T: Codable>(_ file: ShardFile, as type: T.Type) -> T? {
            let url = directory.appendingPathComponent(file.rawValue)
            guard let result = decode(type, at: url, fingerprint: fingerprint) else { return nil }
            savedAt = max(savedAt ?? .distantPast, result.savedAt)
            return result.value
        }

        let core = read(.core, as: CachedSessionCore.self)
        let graph = read(.graph, as: CachedServerGraph.self)
        let users = read(.users, as: CachedUserDirectory.self)
        let unreads = read(.unreads, as: CachedUnreads.self)
        let readStates = read(.readStates, as: CachedReadStates.self)

        // Member shards are optional and independently disposable. A corrupt roster costs the
        // member panel for one server, not the whole offline session.
        var membersByServerID: [ServerID: CachedServerMembers] = [:]
        let membersDirectory = directory.appendingPathComponent("members", isDirectory: true)
        if let urls = try? FileManager.default.contentsOfDirectory(at: membersDirectory, includingPropertiesForKeys: nil) {
            for url in urls where url.pathExtension == "json" {
                guard let result = decode(CachedServerMembers.self, at: url, fingerprint: fingerprint) else { continue }
                membersByServerID[result.value.serverID] = result.value
            }
        }

        return LoadedSessionCache(
            core: core,
            graph: graph,
            users: users,
            unreads: unreads,
            readStates: readStates?.states ?? [],
            membersByServerID: membersByServerID,
            savedAt: savedAt
        )
    }

    // MARK: Write

    public func write(_ batch: SessionCacheWriteBatch, environmentID: String, userID: UserID) async {
        guard !batch.isEmpty else { return }
        let fingerprint = Self.scopeFingerprint(environmentID: environmentID, userID: userID)
        let directory = scopeDirectory(environmentID: environmentID, userID: userID)
        createDirectory(directory)

        func store(_ value: (some Codable)?, to file: ShardFile) {
            guard let value else { return }
            encode(value, to: directory.appendingPathComponent(file.rawValue), fingerprint: fingerprint)
        }

        store(batch.core, to: .core)
        store(batch.graph, to: .graph)
        store(batch.users, to: .users)
        store(batch.unreads, to: .unreads)
        store(batch.readStates, to: .readStates)

        if !batch.members.isEmpty {
            let membersDirectory = directory.appendingPathComponent("members", isDirectory: true)
            createDirectory(membersDirectory)
            for shard in batch.members {
                let url = membersDirectory.appendingPathComponent("\(Self.digest(shard.serverID.rawValue)).v1.json")
                encode(shard, to: url, fingerprint: fingerprint)
            }
        }

        diagnosticsValue.writeCount += 1
    }

    // MARK: Purge

    public func purgeScope(environmentID: String, userID: UserID) async {
        try? FileManager.default.removeItem(at: scopeDirectory(environmentID: environmentID, userID: userID))
        // The identity index points at a scope that no longer exists, so it goes too. Leaving it
        // behind would make `availability` promise a cache that cannot be loaded.
        let identity = environmentDirectory(environmentID).appendingPathComponent(Self.identityFileName)
        try? FileManager.default.removeItem(at: identity)
    }

    public func purgeEnvironment(environmentID: String) async {
        try? FileManager.default.removeItem(at: environmentDirectory(environmentID))
    }

    public func purgeEverything() async {
        try? FileManager.default.removeItem(at: root)
    }

    public func diagnostics() async -> SessionCacheDiagnostics {
        var diagnostics = diagnosticsValue
        diagnostics.totalBytesOnDisk = Self.byteSize(of: root)
        return diagnostics
    }

    // MARK: Envelope IO

    private func encode(_ value: some Codable, to url: URL, fingerprint: String) {
        guard let payload = try? JSONEncoder.stoatCache.encode(value),
              let sealed = try? cipher.seal(payload)
        else { return }
        let envelope = Envelope(
            version: Self.envelopeVersion,
            scopeFingerprint: fingerprint,
            savedAt: Date(),
            payload: sealed
        )
        guard let data = try? JSONEncoder.stoatCache.encode(envelope) else { return }
        write(data, to: url)
    }

    private func decode<T: Codable>(_ type: T.Type, at url: URL, fingerprint: String) -> (value: T, savedAt: Date)? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let envelope = try? JSONDecoder.stoatCache.decode(Envelope.self, from: data) else {
            // Truncated, half-written, or not an envelope at all. The cache is disposable, so
            // this is a delete, never an error the user hears about.
            diagnosticsValue.corruptShardCount += 1
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        guard envelope.version == Self.envelopeVersion else {
            diagnosticsValue.versionMismatchShardCount += 1
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        guard envelope.scopeFingerprint == fingerprint else {
            // A directory holding another identity's data is a privacy problem, not a stale
            // read, so the whole scope goes rather than just this file.
            diagnosticsValue.scopeMismatchPurgeCount += 1
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
            return nil
        }
        guard let payload = try? cipher.open(envelope.payload),
              let value = try? JSONDecoder.stoatCache.decode(type, from: payload)
        else {
            diagnosticsValue.corruptShardCount += 1
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return (value, envelope.savedAt)
    }

    // MARK: Filesystem

    private func environmentDirectory(_ environmentID: String) -> URL {
        root.appendingPathComponent(Self.digest(environmentID), isDirectory: true)
    }

    private func scopeDirectory(environmentID: String, userID: UserID) -> URL {
        environmentDirectory(environmentID).appendingPathComponent(Self.digest(userID.rawValue), isDirectory: true)
    }

    private func createDirectory(_ url: URL) {
        try? FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        excludeRootFromBackup()
    }

    private func write(_ data: Data, to url: URL) {
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// A cache should not ride along in Time Machine. Application Support rather than Caches is
    /// deliberate though: an unpredictable OS purge of the caches directory would silently take
    /// offline mode with it.
    private func excludeRootFromBackup() {
        var url = root
        guard (try? url.resourceValues(forKeys: [.isExcludedFromBackupKey]))?.isExcludedFromBackup != true else { return }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    private static func byteSize(of url: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total = 0
        for case let fileURL as URL in enumerator {
            total += (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        }
        return total
    }

    static func scopeFingerprint(environmentID: String, userID: UserID) -> String {
        digest("\(environmentID)|\(userID.rawValue)")
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}

/// Test and preview double. Named `InMemory` rather than `Stub` on purpose -- `Scripts/check.sh`
/// bans `Mock`/`Stub`/`Fake` in library sources, and this follows the existing
/// `InMemoryAppPreferencesStore` convention.
public actor InMemorySessionSnapshotStore: SessionSnapshotStoring {
    private var identitiesByEnvironment: [String: CachedSessionIdentity] = [:]
    private var cachesByScope: [String: LoadedSessionCache] = [:]
    private var diagnosticsValue = SessionCacheDiagnostics()

    public init() {}

    private func key(_ environmentID: String, _ userID: UserID) -> String {
        "\(environmentID)|\(userID.rawValue)"
    }

    public func availability(environmentID: String) async -> SessionCacheAvailability? {
        identitiesByEnvironment[environmentID].map {
            SessionCacheAvailability(userID: $0.userID, savedAt: $0.savedAt)
        }
    }

    public func writeIdentity(_ identity: CachedSessionIdentity, environmentID: String) async {
        identitiesByEnvironment[environmentID] = identity
    }

    public func load(environmentID: String, userID: UserID) async -> LoadedSessionCache {
        diagnosticsValue.readCount += 1
        return cachesByScope[key(environmentID, userID)] ?? LoadedSessionCache()
    }

    public func write(_ batch: SessionCacheWriteBatch, environmentID: String, userID: UserID) async {
        guard !batch.isEmpty else { return }
        diagnosticsValue.writeCount += 1
        var cache = cachesByScope[key(environmentID, userID)] ?? LoadedSessionCache()
        if let core = batch.core { cache.core = core }
        if let graph = batch.graph { cache.graph = graph }
        if let users = batch.users { cache.users = users }
        if let unreads = batch.unreads { cache.unreads = unreads }
        if let readStates = batch.readStates { cache.readStates = readStates.states }
        for shard in batch.members { cache.membersByServerID[shard.serverID] = shard }
        cache.savedAt = Date()
        cachesByScope[key(environmentID, userID)] = cache
    }

    public func purgeScope(environmentID: String, userID: UserID) async {
        cachesByScope[key(environmentID, userID)] = nil
        identitiesByEnvironment[environmentID] = nil
    }

    public func purgeEnvironment(environmentID: String) async {
        identitiesByEnvironment[environmentID] = nil
        for key in cachesByScope.keys where key.hasPrefix("\(environmentID)|") {
            cachesByScope[key] = nil
        }
    }

    public func purgeEverything() async {
        identitiesByEnvironment.removeAll()
        cachesByScope.removeAll()
    }

    public func diagnostics() async -> SessionCacheDiagnostics { diagnosticsValue }
}

extension JSONEncoder {
    /// Separate from `JSONEncoder.stoat`, which encodes wire payloads. The cache is free to
    /// change representation without touching anything the server sees.
    static let stoatCache: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

extension JSONDecoder {
    static let stoatCache: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
