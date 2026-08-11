//  Phase 74 -- the offline session cache.
//
//  Two properties matter more than any individual behaviour here, and both are tested directly:
//  a damaged cache never breaks startup, and a purge actually removes the content.

import CryptoKit
import XCTest
import StoatAPI
import StoatModels
@testable import StoatPersistence

final class SessionCacheTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionCacheTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private let environmentID = "production"
    private let userID: UserID = "01HX0000000000000000000001"

    private func makeStore(cipher: any SessionCacheCipher = PassthroughSessionCacheCipher()) -> FileSessionSnapshotStore {
        FileSessionSnapshotStore(root: root, cipher: cipher)
    }

    private func makeGraph() -> CachedServerGraph {
        CachedServerGraph(
            servers: [Server(id: "server-1", ownerID: "owner", name: "Bagel Lab", channelIDs: ["channel-1"])],
            channels: [Channel(id: "channel-1", kind: .textChannel, serverID: "server-1", name: "general")],
            emojis: []
        )
    }

    // MARK: - Round trip

    func testShardsRoundTripAndRebuildTheirCollections() async {
        let store = makeStore()
        let graph = makeGraph()
        let core = CachedSessionCore(currentUser: User(id: userID, username: "me"))

        await store.write(
            SessionCacheWriteBatch(
                core: core,
                graph: graph,
                users: CachedUserDirectory(users: [User(id: "other", username: "other")]),
                members: [CachedServerMembers(serverID: "server-1", members: [])]
            ),
            environmentID: environmentID,
            userID: userID
        )
        let loaded = await store.load(environmentID: environmentID, userID: userID)

        XCTAssertEqual(loaded.core, core)
        XCTAssertEqual(loaded.graph, graph)
        XCTAssertEqual(loaded.users?.users.count, 1)
        XCTAssertEqual(loaded.membersByServerID.keys.map(\.rawValue), ["server-1"])
        XCTAssertTrue(loaded.isUsable)
        XCTAssertNotNil(loaded.savedAt)
    }

    func testAWriteBatchOnlyTouchesTheShardsItCarries() async throws {
        let store = makeStore()
        await store.write(
            SessionCacheWriteBatch(core: CachedSessionCore(currentUser: User(id: userID, username: "me")), graph: makeGraph()),
            environmentID: environmentID,
            userID: userID
        )
        let graphURL = try scopeDirectory().appendingPathComponent("graph.v1.json")
        let before = try modificationDate(of: graphURL)

        // Sleep past filesystem timestamp granularity so an unchanged mtime is meaningful.
        try await Task.sleep(for: .milliseconds(1_100))
        await store.write(
            SessionCacheWriteBatch(unreads: CachedUnreads(unreads: [])),
            environmentID: environmentID,
            userID: userID
        )

        // Message traffic dirties only `unreads`, so the expensive graph shard must not be
        // rewritten. This is the property that makes per-event caching affordable at all.
        XCTAssertEqual(try modificationDate(of: graphURL), before)
    }

    func testAnEmptyBatchWritesNothing() async {
        let store = makeStore()
        await store.write(SessionCacheWriteBatch(), environmentID: environmentID, userID: userID)

        let diagnostics = await store.diagnostics()
        XCTAssertEqual(diagnostics.writeCount, 0)
    }

    // MARK: - Damage

    func testACorruptShardIsDiscardedRatherThanThrowing() async throws {
        let store = makeStore()
        await store.write(SessionCacheWriteBatch(graph: makeGraph()), environmentID: environmentID, userID: userID)
        let graphURL = try scopeDirectory().appendingPathComponent("graph.v1.json")
        try Data("{ not json".utf8).write(to: graphURL)

        let loaded = await store.load(environmentID: environmentID, userID: userID)

        XCTAssertNil(loaded.graph)
        XCTAssertFalse(loaded.isUsable, "an unusable cache falls back to the normal startup path")
        XCTAssertFalse(FileManager.default.fileExists(atPath: graphURL.path), "the bad file is deleted, not left to fail again")
        let diagnostics = await store.diagnostics()
        XCTAssertEqual(diagnostics.corruptShardCount, 1)
    }

    func testAnUnknownShardVersionIsDiscardedNotMigrated() async throws {
        let store = makeStore()
        await store.write(SessionCacheWriteBatch(graph: makeGraph()), environmentID: environmentID, userID: userID)
        let graphURL = try scopeDirectory().appendingPathComponent("graph.v1.json")

        var envelope = try JSONSerialization.jsonObject(with: Data(contentsOf: graphURL)) as! [String: Any]
        envelope["version"] = 999
        try JSONSerialization.data(withJSONObject: envelope).write(to: graphURL)

        let loaded = await store.load(environmentID: environmentID, userID: userID)

        XCTAssertNil(loaded.graph)
        let diagnostics = await store.diagnostics()
        XCTAssertEqual(diagnostics.versionMismatchShardCount, 1)
    }

    func testAScopeFingerprintMismatchPurgesTheWholeScope() async throws {
        let store = makeStore()
        await store.write(
            SessionCacheWriteBatch(core: CachedSessionCore(currentUser: User(id: userID, username: "me")), graph: makeGraph()),
            environmentID: environmentID,
            userID: userID
        )
        let graphURL = try scopeDirectory().appendingPathComponent("graph.v1.json")
        var envelope = try JSONSerialization.jsonObject(with: Data(contentsOf: graphURL)) as! [String: Any]
        envelope["scopeFingerprint"] = "someone-elses-fingerprint"
        try JSONSerialization.data(withJSONObject: envelope).write(to: graphURL)

        let loaded = await store.load(environmentID: environmentID, userID: userID)

        // A directory holding another identity's content is a privacy failure, not a stale read,
        // so everything in the scope goes -- not just the offending file.
        XCTAssertNil(loaded.graph)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try scopeDirectory().path))
        let diagnostics = await store.diagnostics()
        XCTAssertEqual(diagnostics.scopeMismatchPurgeCount, 1)
    }

    func testPartialDamageStillYieldsAUsableCache() async throws {
        let store = makeStore()
        await store.write(
            SessionCacheWriteBatch(graph: makeGraph(), members: [CachedServerMembers(serverID: "server-1", members: [])]),
            environmentID: environmentID,
            userID: userID
        )
        let membersDirectory = try scopeDirectory().appendingPathComponent("members", isDirectory: true)
        let memberFile = try XCTUnwrap(
            try FileManager.default.contentsOfDirectory(at: membersDirectory, includingPropertiesForKeys: nil).first
        )
        try Data("garbage".utf8).write(to: memberFile)

        let loaded = await store.load(environmentID: environmentID, userID: userID)

        // A corrupt roster costs the member panel for one server, not the offline session.
        XCTAssertNotNil(loaded.graph)
        XCTAssertTrue(loaded.isUsable)
        XCTAssertTrue(loaded.membersByServerID.isEmpty)
    }

    func testLoadingAnAbsentCacheIsEmptyRatherThanAnError() async {
        let store = makeStore()
        let loaded = await store.load(environmentID: environmentID, userID: userID)

        XCTAssertFalse(loaded.isUsable)
        XCTAssertNil(loaded.graph)
    }

    // MARK: - Identity index

    func testTheIdentityIndexResolvesTheUserWithoutNetworkOrKey() async {
        // Offline boot knows the environment from preferences and has a Keychain credential, but
        // not the account's own user ID -- that normally needs a round trip. The index is how the
        // right scope directory is found before anything is decrypted.
        let store = makeStore(cipher: AESGCMSessionCacheCipher(key: SymmetricKey(size: .bits256)))
        await store.writeIdentity(CachedSessionIdentity(userID: userID, savedAt: Date()), environmentID: environmentID)

        let availability = await store.availability(environmentID: environmentID)
        XCTAssertEqual(availability?.userID, userID)
    }

    func testAvailabilityIsNilWhenNothingHasBeenCached() async {
        let store = makeStore()
        let availability = await store.availability(environmentID: environmentID)
        XCTAssertNil(availability)
    }

    // MARK: - Encryption

    func testEncryptedPayloadsAreNotReadableOnDisk() async throws {
        let key = SymmetricKey(size: .bits256)
        let store = makeStore(cipher: AESGCMSessionCacheCipher(key: key))
        await store.write(SessionCacheWriteBatch(graph: makeGraph()), environmentID: environmentID, userID: userID)

        let raw = try Data(contentsOf: try scopeDirectory().appendingPathComponent("graph.v1.json"))
        let text = String(decoding: raw, as: UTF8.self)

        XCTAssertFalse(text.contains("Bagel Lab"), "a channel name must not be recoverable by reading the file")
        XCTAssertFalse(text.contains("general"))
        // The envelope header stays plaintext so a stale or foreign shard can be triaged and
        // deleted without the key.
        XCTAssertTrue(text.contains("scopeFingerprint"))

        let loaded = await store.load(environmentID: environmentID, userID: userID)
        XCTAssertEqual(loaded.graph, makeGraph())
    }

    func testTheWrongKeyReadsAsDamageRatherThanCrashing() async {
        let writer = makeStore(cipher: AESGCMSessionCacheCipher(key: SymmetricKey(size: .bits256)))
        await writer.write(SessionCacheWriteBatch(graph: makeGraph()), environmentID: environmentID, userID: userID)

        let reader = makeStore(cipher: AESGCMSessionCacheCipher(key: SymmetricKey(size: .bits256)))
        let loaded = await reader.load(environmentID: environmentID, userID: userID)

        XCTAssertNil(loaded.graph)
        XCTAssertFalse(loaded.isUsable)
    }

    // MARK: - Purge

    func testPurgingAScopeRemovesEveryFileAndTheIdentityIndex() async throws {
        let store = makeStore()
        await store.writeIdentity(CachedSessionIdentity(userID: userID, savedAt: Date()), environmentID: environmentID)
        await store.write(
            SessionCacheWriteBatch(
                core: CachedSessionCore(currentUser: User(id: userID, username: "me")),
                graph: makeGraph(),
                members: [CachedServerMembers(serverID: "server-1", members: [])]
            ),
            environmentID: environmentID,
            userID: userID
        )

        await store.purgeScope(environmentID: environmentID, userID: userID)

        XCTAssertFalse(FileManager.default.fileExists(atPath: try scopeDirectory().path))
        // Leaving the index behind would make `availability` promise a cache that cannot load.
        let availability = await store.availability(environmentID: environmentID)
        XCTAssertNil(availability)
    }

    func testEnvironmentsAreIsolatedFromEachOther() async {
        let store = makeStore()
        await store.write(SessionCacheWriteBatch(graph: makeGraph()), environmentID: "production", userID: userID)

        let other = await store.load(environmentID: "custom-selfhosted", userID: userID)
        XCTAssertNil(other.graph)
    }

    func testAccountsAreIsolatedWithinAnEnvironment() async {
        let store = makeStore()
        await store.write(SessionCacheWriteBatch(graph: makeGraph()), environmentID: environmentID, userID: userID)

        let other = await store.load(environmentID: environmentID, userID: "01HX0000000000000000000009")
        XCTAssertNil(other.graph)
    }

    // MARK: - Diagnostics

    func testDiagnosticsCarryNoContent() async {
        let store = makeStore()
        await store.write(SessionCacheWriteBatch(graph: makeGraph()), environmentID: environmentID, userID: userID)

        let text = String(describing: await store.diagnostics())

        for secret in ["Bagel Lab", "general", "server-1", userID.rawValue, root.path] {
            XCTAssertFalse(text.contains(secret), "diagnostics leaked \(secret)")
        }
    }

    // MARK: - Helpers

    private func scopeDirectory() throws -> URL {
        func digest(_ value: String) -> String {
            SHA256.hash(data: Data(value.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
        }
        return root
            .appendingPathComponent(digest(environmentID), isDirectory: true)
            .appendingPathComponent(digest(userID.rawValue), isDirectory: true)
    }

    private func modificationDate(of url: URL) throws -> Date {
        try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)
    }
}

final class ChannelMessageCacheTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MessageCacheTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func message(_ index: Int, channel: ChannelID) -> Message {
        Message(id: MessageID(rawValue: String(format: "01HX%020d", index)), channelID: channel, authorID: "author", content: "message \(index)")
    }

    func testHistoryRoundTripsIncludingHasMoreBefore() async {
        let cache = FileChannelMessageCache(scopeIdentifier: "scope", directory: directory)
        let history = CachedChannelHistory(
            channelID: "channel",
            messages: (0..<3).map { message($0, channel: "channel") },
            hasMoreBefore: true,
            savedAt: Date()
        )

        await cache.store(history)
        let loaded = await cache.history(for: "channel")

        XCTAssertEqual(loaded?.messages.count, 3)
        XCTAssertEqual(loaded?.hasMoreBefore, true)
    }

    func testTruncatingToTheCapRecordsThatOlderMessagesExist() async {
        // Even if the caller believed it had the whole channel, dropping the oldest messages to
        // fit the cap creates older history by definition. Getting this wrong would make the
        // offline timeline claim the user had reached the start of a conversation.
        let cache = FileChannelMessageCache(scopeIdentifier: "scope", directory: directory, maxMessagesPerChannel: 5)
        await cache.store(CachedChannelHistory(
            channelID: "channel",
            messages: (0..<20).map { message($0, channel: "channel") },
            hasMoreBefore: false,
            savedAt: Date()
        ))

        let loaded = await cache.history(for: "channel")

        XCTAssertEqual(loaded?.messages.count, 5)
        XCTAssertEqual(loaded?.hasMoreBefore, true)
        XCTAssertEqual(loaded?.messages.first?.content, "message 15", "the newest page is what gets kept")
    }

    func testEvictionHonoursTheFileCountCap() async {
        let cache = FileChannelMessageCache(scopeIdentifier: "scope", directory: directory, maxChannels: 3)
        for index in 0..<6 {
            let channel = ChannelID(rawValue: "channel-\(index)")
            await cache.store(CachedChannelHistory(channelID: channel, messages: [message(index, channel: channel)], hasMoreBefore: false, savedAt: Date()))
        }

        let files = try? FileManager.default.contentsOfDirectory(
            at: directory.appendingPathComponent(scopeDigest("scope"), isDirectory: true),
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(files?.count, 3)
    }

    func testEvictionHonoursTheByteBudget() async {
        // A file-count cap is not a size cap: 200 channels of messages carrying embeds runs well
        // past 100 MB while staying under any plausible file limit.
        let cache = FileChannelMessageCache(
            scopeIdentifier: "scope",
            directory: directory,
            maxChannels: 500,
            maxTotalBytes: 4_000
        )
        for index in 0..<40 {
            let channel = ChannelID(rawValue: "channel-\(index)")
            await cache.store(CachedChannelHistory(
                channelID: channel,
                messages: (0..<5).map { message($0, channel: channel) },
                hasMoreBefore: false,
                savedAt: Date()
            ))
        }

        let scopeDirectory = directory.appendingPathComponent(scopeDigest("scope"), isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: scopeDirectory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        let total = files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) }

        XCTAssertLessThanOrEqual(total, 4_000)
        XCTAssertGreaterThan(files.count, 0, "the budget evicts, it does not empty the cache")
    }

    func testAPageWrittenBeforeHasMoreBeforeExistedReadsAsCompleteHistory() async throws {
        // v1 envelopes have no `hasMoreBefore`. Reading them as "complete" is the conservative
        // choice: it stops the offline timeline advertising older messages it cannot fetch.
        let cache = FileChannelMessageCache(scopeIdentifier: "scope", directory: directory)
        await cache.store(CachedChannelHistory(channelID: "channel", messages: [message(1, channel: "channel")], hasMoreBefore: true, savedAt: Date()))

        let scopeDirectory = directory.appendingPathComponent(scopeDigest("scope"), isDirectory: true)
        let file = try XCTUnwrap(try FileManager.default.contentsOfDirectory(at: scopeDirectory, includingPropertiesForKeys: nil).first)
        var envelope = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        envelope["version"] = 1
        envelope.removeValue(forKey: "hasMoreBefore")
        try JSONSerialization.data(withJSONObject: envelope).write(to: file)

        let loaded = await cache.history(for: "channel")
        XCTAssertEqual(loaded?.messages.count, 1)
        XCTAssertEqual(loaded?.hasMoreBefore, false)
    }

    func testRemoveAllClearsTheScope() async {
        let cache = FileChannelMessageCache(scopeIdentifier: "scope", directory: directory)
        await cache.store(CachedChannelHistory(channelID: "channel", messages: [message(1, channel: "channel")], hasMoreBefore: false, savedAt: Date()))

        await cache.removeAll()

        let loaded = await cache.history(for: "channel")
        XCTAssertNil(loaded)
    }

    private func scopeDigest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}
