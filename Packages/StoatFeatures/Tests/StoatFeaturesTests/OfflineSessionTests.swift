//  Phase 74 -- offline mode.
//
//  Three things here are load-bearing and would fail quietly rather than loudly:
//
//    1. Message traffic must dirty no session shard, or per-event caching is unaffordable.
//    2. Restoring a cache must not fire notifications for the backlog.
//    3. Promoting a cached session to a live one must not wipe loaded timelines.
//
//  Each has a test that fails if the mechanism protecting it is removed.

import StoatModels
import StoatAPI
import StoatPersistence
import StoatRealtime
import XCTest
@testable import StoatFeatures

extension StoatFeaturesTests {

    // MARK: - Dirty-shard accounting

    func testPhase74MessageAndTypingTrafficDirtiesNoSessionShard() {
        // The load-bearing one. The snapshot mutates on every gateway event and the overwhelming
        // majority of those events are messages and typing. If they dirtied shards, the cache
        // would rewrite the whole server graph on every incoming message.
        var changes = RealtimeSnapshotChangeSet()
        changes.messageChannelIDs = ["channel-1", "channel-2"]
        changes.insertedMessages = [Message(id: "m1", channelID: "channel-1", authorID: "a", content: "hi")]
        changes.typingChannelIDs = ["channel-1"]
        changes.deletedMessageIDsByChannelID = ["channel-1": ["m0"]]
        changes.policyChangesChanged = true

        let shards = SessionCacheWriter.dirtyShards(for: changes, recentServerIDs: ["server-1"])

        XCTAssertTrue(shards.isEmpty, "message traffic must not trigger session cache writes")
    }

    func testPhase74StructuralChangesDirtyOnlyTheirOwnShard() {
        var graphChange = RealtimeSnapshotChangeSet()
        graphChange.channelIDs = ["channel-1"]
        XCTAssertEqual(SessionCacheWriter.dirtyShards(for: graphChange, recentServerIDs: []), [.graph])

        var unreadChange = RealtimeSnapshotChangeSet()
        unreadChange.unreadChannelIDs = ["channel-1"]
        XCTAssertEqual(SessionCacheWriter.dirtyShards(for: unreadChange, recentServerIDs: []), [.unreads])

        var userChange = RealtimeSnapshotChangeSet()
        userChange.userIDs = ["u1"]
        XCTAssertEqual(SessionCacheWriter.dirtyShards(for: userChange, recentServerIDs: []), [.users])
    }

    func testPhase74MemberChangesOnlyDirtyRostersWeActuallyKeep() {
        var changes = RealtimeSnapshotChangeSet()
        changes.memberKeys = [
            ServerMemberKey(serverID: "visited", userID: "u1"),
            ServerMemberKey(serverID: "never-opened", userID: "u2")
        ]

        let shards = SessionCacheWriter.dirtyShards(for: changes, recentServerIDs: ["visited"])

        XCTAssertEqual(shards, [.members("visited")])
    }

    func testPhase74AFullReplacementDirtiesEverything() {
        var changes = RealtimeSnapshotChangeSet()
        changes.isFullReplacement = true

        let shards = SessionCacheWriter.dirtyShards(for: changes, recentServerIDs: ["server-1"])

        XCTAssertTrue(shards.contains(.graph))
        XCTAssertTrue(shards.contains(.users))
        XCTAssertTrue(shards.contains(.unreads))
        XCTAssertTrue(shards.contains(.members("server-1")))
    }

    // MARK: - Mapping

    func testPhase74MapperOmitsMessagesAndTyping() {
        var snapshot = RealtimeSnapshot()
        snapshot.serversByID["s1"] = Server(id: "s1", ownerID: "o", name: "Server", channelIDs: ["c1"])
        snapshot.channelsByID["c1"] = Channel(id: "c1", kind: .textChannel, serverID: "s1", name: "general")
        snapshot.usersByID["u1"] = User(id: "u1", username: "u1")
        snapshot.messagesByChannelID["c1"] = [Message(id: "m1", channelID: "c1", authorID: "u1", content: "secret")]
        snapshot.typingUsersByChannelID["c1"] = ["u1"]

        let restored = SessionCacheMapper.snapshot(from: LoadedSessionCache(
            graph: SessionCacheMapper.graph(from: snapshot),
            users: SessionCacheMapper.users(from: snapshot)
        ))

        XCTAssertEqual(restored.channelsByID.count, 1)
        XCTAssertEqual(restored.usersByID.count, 1)
        // Messages belong to the per-channel message cache; typing describes a moment that has
        // already passed.
        XCTAssertTrue(restored.messagesByChannelID.isEmpty)
        XCTAssertTrue(restored.typingUsersByChannelID.isEmpty)
    }

    // MARK: - Read-state reconciliation

    func testPhase74RestoredReadStateYieldsToNewerServerTruth() {
        var snapshot = RealtimeSnapshot()
        snapshot.channelsByID["c1"] = Channel(id: "c1", kind: .textChannel, serverID: "s1", name: "general")
        // The server has read further than the cached marker did.
        snapshot.unreadsByChannelID["c1"] = ChannelUnread(
            id: ChannelCompositeKey(channelID: "c1", userID: "me"),
            lastMessageID: "01HX0000000000000000000900",
            mentions: []
        )
        let cached = [CachedLocalReadState(
            channelID: "c1",
            lastReadMessageID: "01HX0000000000000000000100",
            unreadCount: 5,
            updatedAt: Date()
        )]

        let result = SessionCacheMapper.reconcileReadStates(cached: cached, snapshot: snapshot, now: Date())

        XCTAssertTrue(result.isEmpty, "stale local state must never resurrect unread badges the server cleared")
    }

    func testPhase74RestoredReadStateSurvivesWhenItIsAheadOfTheServer() {
        var snapshot = RealtimeSnapshot()
        snapshot.channelsByID["c1"] = Channel(id: "c1", kind: .textChannel, serverID: "s1", name: "general")
        snapshot.unreadsByChannelID["c1"] = ChannelUnread(
            id: ChannelCompositeKey(channelID: "c1", userID: "me"),
            lastMessageID: "01HX0000000000000000000100",
            mentions: []
        )
        let cached = [CachedLocalReadState(
            channelID: "c1",
            lastReadMessageID: "01HX0000000000000000000900",
            unreadCount: 0,
            updatedAt: Date()
        )]

        let result = SessionCacheMapper.reconcileReadStates(cached: cached, snapshot: snapshot, now: Date())

        XCTAssertEqual(result["c1"]?.lastReadMessageID, "01HX0000000000000000000900")
    }

    func testPhase74ReadStatesForVanishedChannelsAndAncientEntriesAreDropped() {
        var snapshot = RealtimeSnapshot()
        snapshot.channelsByID["kept"] = Channel(id: "kept", kind: .textChannel, serverID: "s1", name: "general")
        let now = Date()
        let cached = [
            CachedLocalReadState(channelID: "kept", lastReadMessageID: "01HX1", updatedAt: now),
            CachedLocalReadState(channelID: "deleted-channel", lastReadMessageID: "01HX1", updatedAt: now),
            CachedLocalReadState(channelID: "kept", lastReadMessageID: "01HX1", updatedAt: now.addingTimeInterval(-90 * 24 * 60 * 60))
        ]

        let result = SessionCacheMapper.reconcileReadStates(cached: cached, snapshot: snapshot, now: now)

        XCTAssertEqual(Set(result.keys.map(\.rawValue)), ["kept"])
    }

    // MARK: - Startup routing

    @MainActor
    func testPhase74AUsableCacheEntersTheOfflineShellBeforeConnecting() async {
        let store = InMemorySessionSnapshotStore()
        await seedCache(store, userID: "u1")
        let coordinator = AppSessionCoordinator(
            tokenStore: InMemoryTokenStore(credential: .sessionToken("token")),
            sessionValidator: StubSessionValidator(user: User(id: "u1", username: "u1")),
            apiClientFactory: { _, _ in RecordingAPIClient() },
            realtimeClientFactory: { RecordingRealtimeClient(statesOnConnect: []) },
            sessionCache: store
        )
        let appModel = LiquidBagelAppModel(coordinator: coordinator)

        await coordinator.restoreCachedSession()

        XCTAssertTrue(coordinator.isUsingCachedSession)
        XCTAssertEqual(coordinator.snapshot.channelsByID.count, 1)
        guard case .readyOffline = appModel.startupState else {
            return XCTFail("expected the offline shell, got \(appModel.startupState)")
        }
        XCTAssertTrue(appModel.startupState.showsMainShell)
        // Nothing has been validated, so the session is not "connected" and hydration has not
        // happened -- which is what keeps the notification pipeline closed.
        XCTAssertNotEqual(coordinator.sessionState, .connected)
        XCTAssertFalse(coordinator.hydrationStatus.readyReceived)
    }

    @MainActor
    func testPhase74WithoutACacheTheNormalFailureScreenStillAppears() async {
        let coordinator = AppSessionCoordinator(
            tokenStore: InMemoryTokenStore(credential: .sessionToken("token")),
            sessionValidator: StubSessionValidator(user: User(id: "u1", username: "u1")),
            apiClientFactory: { _, _ in RecordingAPIClient() },
            realtimeClientFactory: { RecordingRealtimeClient(statesOnConnect: []) },
            sessionCache: InMemorySessionSnapshotStore()
        )
        let appModel = LiquidBagelAppModel(coordinator: coordinator)

        await coordinator.restoreCachedSession()

        XCTAssertFalse(coordinator.isUsingCachedSession)
        XCTAssertFalse(appModel.startupState.showsMainShell)
    }

    @MainActor
    func testPhase74AnInvalidSessionNeverShowsCachedContent() async {
        // The safety property. A rejected session must not leave the user browsing content they
        // are no longer entitled to read.
        let store = InMemorySessionSnapshotStore()
        await seedCache(store, userID: "u1")
        // A validator that rejects the saved token is how a revoked session actually surfaces.
        let coordinator = AppSessionCoordinator(
            tokenStore: InMemoryTokenStore(credential: .sessionToken("token")),
            sessionValidator: StubSessionValidator(
                user: User(id: "u1", username: "u1"),
                error: SessionValidationError.invalidOrExpired
            ),
            apiClientFactory: { _, _ in RecordingAPIClient() },
            realtimeClientFactory: { RecordingRealtimeClient(statesOnConnect: []) },
            sessionCache: store
        )
        let appModel = LiquidBagelAppModel(coordinator: coordinator)
        await coordinator.restoreCachedSession()
        XCTAssertTrue(appModel.startupState.showsMainShell, "the cache paints before the token is checked")

        await coordinator.validateSavedSession()

        XCTAssertFalse(
            appModel.startupState.showsMainShell,
            "a rejected session must not leave the user browsing content they can no longer read"
        )
    }

    @MainActor
    func testPhase74TheKillSwitchSkipsCacheRestoreEntirely() async {
        let store = InMemorySessionSnapshotStore()
        await seedCache(store, userID: "u1")
        var preferences = AppPreferences.defaults
        preferences.offlineCacheRestoreOnLaunch = false
        let coordinator = AppSessionCoordinator(
            tokenStore: InMemoryTokenStore(credential: .sessionToken("token")),
            preferencesStore: InMemoryAppPreferencesStore(preferences: preferences),
            sessionValidator: StubSessionValidator(user: User(id: "u1", username: "u1")),
            apiClientFactory: { _, _ in RecordingAPIClient() },
            realtimeClientFactory: { RecordingRealtimeClient(statesOnConnect: []) },
            sessionCache: store
        )
        await coordinator.loadPreferences()

        await coordinator.restoreCachedSession()

        XCTAssertFalse(coordinator.isUsingCachedSession)
    }

    // MARK: - Promotion to live

    @MainActor
    func testPhase74PromotionToLivePreservesLoadedTimelines() async throws {
        // The identity-scope trap. `ChannelMessageController.configure` wipes every loaded
        // history when the current user changes, so if `restoreCachedSession` left `currentUser`
        // nil the first successful connect would blank the timeline the user was reading.
        let channelID: ChannelID = "phase74-promote"
        let controller = ChannelMessageController(runtimeMode: .liveManual, apiClient: RecordingAPIClient(), currentUserID: "u1")
        await controller.loadInitialMessages(
            channelID: channelID,
            snapshotMessages: [Message(id: "01HX1", channelID: channelID, authorID: "u1", content: "cached")]
        )
        XCTAssertTrue(controller.state(for: channelID).hasMessages)

        // Same user, now with a live client: a load-scope change, not an identity one.
        controller.configure(runtimeMode: .liveManual, apiClient: RecordingAPIClient(), currentUserID: "u1", loadGeneration: 1)
        XCTAssertTrue(controller.state(for: channelID).hasMessages, "histories must survive going live")

        // A different user is a real identity change and must clear everything.
        controller.configure(runtimeMode: .liveManual, apiClient: RecordingAPIClient(), currentUserID: "someone-else")
        XCTAssertFalse(controller.state(for: channelID).hasMessages)
    }

    @MainActor
    func testPhase74RestoringACacheDeliversNoNotifications() async {
        // The notification trap. Restoring a cache is not new activity. This works because the
        // restore leaves `readyReceived` false and never bumps the connection generation -- both
        // of which are easy to "clean up" without realising what they were holding shut.
        let store = InMemorySessionSnapshotStore()
        await seedCache(store, userID: "u1")
        let coordinator = AppSessionCoordinator(
            tokenStore: InMemoryTokenStore(credential: .sessionToken("token")),
            sessionValidator: StubSessionValidator(user: User(id: "u1", username: "u1")),
            apiClientFactory: { _, _ in RecordingAPIClient() },
            realtimeClientFactory: { RecordingRealtimeClient(statesOnConnect: []) },
            sessionCache: store
        )
        let model = MainShellViewModel(
            snapshot: RealtimeSnapshot(),
            runtimeMode: .liveManual,
            sessionState: .signedOut,
            currentUser: nil,
            messageActionHandler: StubMessageActionHandler(currentUserID: "u1"),
            communityAPIClient: StubStoatAPIClient()
        )
        model.attachSessionCoordinator(coordinator)

        await coordinator.restoreCachedSession()
        model.syncFromSessionCoordinator()
        await model.adoptRestoredSessionCache()

        XCTAssertTrue(model.notificationBanners.isEmpty)
        XCTAssertEqual(model.notificationDiagnostics.deliveredCount, 0)
    }

    // MARK: - Purge

    @MainActor
    func testPhase74SigningOutPurgesTheCache() async {
        let store = InMemorySessionSnapshotStore()
        await seedCache(store, userID: "u1")
        let coordinator = AppSessionCoordinator(
            tokenStore: InMemoryTokenStore(credential: .sessionToken("token")),
            sessionValidator: StubSessionValidator(user: User(id: "u1", username: "u1")),
            apiClientFactory: { _, _ in RecordingAPIClient() },
            realtimeClientFactory: { RecordingRealtimeClient(statesOnConnect: []) },
            sessionCache: store
        )
        await coordinator.restoreCachedSession()
        XCTAssertTrue(coordinator.isUsingCachedSession)

        await coordinator.forgetLocalSession()

        let availability = await store.availability(environmentID: StoatAPIEnvironment.production.stableID)
        XCTAssertNil(availability, "cached message content must not outlive the credential")
        XCTAssertFalse(coordinator.isUsingCachedSession)
        XCTAssertNil(coordinator.sessionCacheAvailability)
    }

}

/// Free function rather than a method: calling an actor from a `@MainActor` test through an
/// instance method would send `self` across the isolation boundary.
private func seedCache(_ store: InMemorySessionSnapshotStore, userID: UserID) async {
    let environmentID = StoatAPIEnvironment.production.stableID
    await store.writeIdentity(CachedSessionIdentity(userID: userID, savedAt: Date()), environmentID: environmentID)
    await store.write(
        SessionCacheWriteBatch(
            core: CachedSessionCore(currentUser: User(id: userID, username: "me")),
            graph: CachedServerGraph(
                servers: [Server(id: "s1", ownerID: "o", name: "Bagel Lab", channelIDs: ["c1"])],
                channels: [Channel(id: "c1", kind: .textChannel, serverID: "s1", name: "general")],
                emojis: []
            )
        ),
        environmentID: environmentID,
        userID: userID
    )
}

// Phase 74 -- connection chrome and write blocking.
extension StoatFeaturesTests {
    @MainActor
    func testPhase74ChromeIsSilentWhenConnected() {
        // The contract: a healthy app says nothing about its connection. The sidebar used to
        // carry a permanent "Connected" line, which is noise and trains people to ignore the one
        // place a real problem would appear.
        let model = MainShellViewModel(
            snapshot: RealtimeSnapshot(),
            runtimeMode: .liveManual,
            sessionState: .connected,
            currentUser: User(id: "u1", username: "u1"),
            messageActionHandler: StubMessageActionHandler(currentUserID: "u1"),
            communityAPIClient: StubStoatAPIClient()
        )

        XCTAssertNil(model.connectionChrome)
        XCTAssertFalse(model.isOffline)
        XCTAssertNil(model.writeBlockReason(.sendMessage))
    }

    @MainActor
    func testPhase74ChromeAppearsOnlyWhenSomethingIsWrong() {
        let model = MainShellViewModel(
            snapshot: RealtimeSnapshot(),
            runtimeMode: .liveManual,
            sessionState: .connected,
            currentUser: User(id: "u1", username: "u1"),
            messageActionHandler: StubMessageActionHandler(currentUserID: "u1"),
            communityAPIClient: StubStoatAPIClient()
        )

        model.sessionState = .connectionFailed("boom")
        let offline = model.connectionChrome
        XCTAssertNotNil(offline)
        XCTAssertEqual(offline?.level, .warning)

        model.sessionState = .invalidSession("expired")
        XCTAssertEqual(model.connectionChrome?.level, .error)

        model.sessionState = .connecting
        XCTAssertEqual(model.connectionChrome?.level, .info)
    }

    @MainActor
    func testPhase74EveryWriteActionIsBlockedWithTheSameShapeOfReason() {
        let model = MainShellViewModel(
            snapshot: RealtimeSnapshot(),
            runtimeMode: .liveManual,
            sessionState: .connectionFailed("boom"),
            currentUser: User(id: "u1", username: "u1"),
            messageActionHandler: StubMessageActionHandler(currentUserID: "u1"),
            communityAPIClient: StubStoatAPIClient()
        )

        let actions: [WriteAction] = [.sendMessage, .attachFile, .react, .edit, .delete, .pin]
        for action in actions {
            let reason = model.writeBlockReason(action)
            XCTAssertNotNil(reason, "\(action) should be blocked offline")
            XCTAssertEqual(reason?.hasPrefix("You're offline."), true, "\(action): \(reason ?? "nil")")
        }
        // Distinct per action, so the composer and a context menu never say the same generic thing.
        XCTAssertEqual(Set(actions.compactMap { model.writeBlockReason($0) }).count, actions.count)
    }

    @MainActor
    func testPhase74OfflineComposerExplainsItselfRatherThanJustGoingDead() {
        var snapshot = RealtimeSnapshot()
        let channelID: ChannelID = "c1"
        snapshot.channelsByID[channelID] = Channel(id: channelID, kind: .textChannel, serverID: "s1", name: "general")
        let model = MainShellViewModel(
            snapshot: snapshot,
            runtimeMode: .liveManual,
            sessionState: .connectionFailed("boom"),
            currentUser: User(id: "u1", username: "u1"),
            messageActionHandler: StubMessageActionHandler(currentUserID: "u1"),
            communityAPIClient: StubStoatAPIClient()
        )
        model.updateDraft("hello", for: channelID)

        let readiness = model.composerReadiness(for: channelID)
        XCTAssertFalse(readiness.canSend)
        XCTAssertEqual(readiness.reason, model.writeBlockReason(.sendMessage))
    }
}

// Phase 74 -- automatic settings sync.
extension StoatFeaturesTests {
    @MainActor
    private func syncedModel(api: RecordingAPIClient) async -> MainShellViewModel {
        let coordinator = AppSessionCoordinator(
            tokenStore: InMemoryTokenStore(credential: .sessionToken("token")),
            // Without this, the coordinator's default preferencesStore reads the real
            // "LiquidBagel.AppPreferences" UserDefaults suite, which other tests in this same
            // process also write to -- causing a spurious diff against the sync baseline that
            // has nothing to do with anything this test did.
            preferencesStore: InMemoryAppPreferencesStore(),
            sessionValidator: StubSessionValidator(user: User(id: "u1", username: "u1")),
            apiClientFactory: { _, _ in api },
            realtimeClientFactory: { RecordingRealtimeClient(statesOnConnect: [.connected, .ready]) }
        )
        let model = MainShellViewModel(
            snapshot: RealtimeSnapshot(),
            runtimeMode: .liveManual,
            sessionState: .signedOut,
            currentUser: nil,
            messageActionHandler: StubMessageActionHandler(currentUserID: "u1"),
            communityAPIClient: StubStoatAPIClient()
        )
        model.attachSessionCoordinator(coordinator)
        await coordinator.startLiveFirstSession()
        for _ in 0..<40 where coordinator.sessionState != .connected {
            try? await Task.sleep(for: .milliseconds(10))
        }
        model.syncFromSessionCoordinator()
        return model
    }

    @MainActor
    func testPhase74ConnectingFetchesCloudPreferencesOnce() async throws {
        let api = RecordingAPIClient()
        let synced = SyncedClientPreferences(messageDensity: .compact)
        await api.overrideSyncedSetting(
            key: MainShellViewModel.cloudPreferencesKey,
            value: SyncedSettingValue(timestamp: 1, rawValue: String(decoding: try JSONEncoder().encode(synced), as: UTF8.self))
        )
        let model = await syncedModel(api: api)
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(model.messageDensity, .compact, "the connect-triggered fetch should have applied the cloud value")
        let fetchedKeys = await api.fetchedSettingsKeys
        XCTAssertEqual(fetchedKeys.count, 1, "connecting must fetch exactly once, not repeatedly")
    }

    @MainActor
    func testPhase74LocalChangesPushAfterQuiescingRatherThanImmediately() async throws {
        let api = RecordingAPIClient()
        let model = await syncedModel(api: api)
        try await Task.sleep(for: .milliseconds(60))
        let baselineFetches = await api.fetchedSettingsKeys.count

        model.messageDensity = .compact
        model.settingsChangedLocally()
        let immediatePushes = await api.setSettingsPayloads.count
        XCTAssertEqual(immediatePushes, 0, "a single change must debounce, not push instantly")

        try await Task.sleep(for: MainShellViewModel.automaticSettingsPushDelay + .milliseconds(300))
        let pushesAfterDebounce = await api.setSettingsPayloads.count
        XCTAssertEqual(pushesAfterDebounce, 1)
        _ = baselineFetches
    }

    @MainActor
    func testPhase74RapidLocalChangesCollapseToOnePush() async throws {
        // A slider drag is a stream of changes, not one. Each should reset the debounce rather
        // than queue a push of its own.
        let api = RecordingAPIClient()
        let model = await syncedModel(api: api)
        try await Task.sleep(for: .milliseconds(60))

        for density: MessageDensityPreference in [.compact, .comfortable, .compact, .comfortable] {
            model.messageDensity = density
            model.settingsChangedLocally()
            try await Task.sleep(for: .milliseconds(200))
        }
        try await Task.sleep(for: MainShellViewModel.automaticSettingsPushDelay + .milliseconds(300))

        let pushes = await api.setSettingsPayloads.count
        XCTAssertEqual(pushes, 1)
    }

    @MainActor
    func testPhase74NoLocalChangeMeansNoPush() async throws {
        let api = RecordingAPIClient()
        let model = await syncedModel(api: api)
        try await Task.sleep(for: MainShellViewModel.automaticSettingsPushDelay + .milliseconds(300))

        let pushes = await api.setSettingsPayloads.count
        XCTAssertEqual(pushes, 0, "connecting must not itself look like a local edit")
        _ = model
    }

    @MainActor
    func testPhase74RemoteUserSettingsUpdateTriggersAFetch() async throws {
        let api = RecordingAPIClient()
        let model = await syncedModel(api: api)
        try await Task.sleep(for: .milliseconds(60))
        let fetchesAfterConnect = await api.fetchedSettingsKeys.count

        var changes = RealtimeSnapshotChangeSet()
        changes.userSettingsChanged = true
        await model.settingsSyncRemoteSettingsChanged()

        let fetchesAfterEvent = await api.fetchedSettingsKeys.count
        XCTAssertGreaterThan(fetchesAfterEvent, fetchesAfterConnect)
    }

    @MainActor
    func testPhase74DisablingAutomaticSyncStopsBothDirections() async throws {
        let api = RecordingAPIClient()
        let coordinator = AppSessionCoordinator(
            tokenStore: InMemoryTokenStore(credential: .sessionToken("token")),
            preferencesStore: InMemoryAppPreferencesStore(
                preferences: AppPreferences(automaticSettingsSyncEnabled: false)
            ),
            sessionValidator: StubSessionValidator(user: User(id: "u1", username: "u1")),
            apiClientFactory: { _, _ in api },
            realtimeClientFactory: { RecordingRealtimeClient(statesOnConnect: [.connected, .ready]) }
        )
        let model = MainShellViewModel(
            snapshot: RealtimeSnapshot(),
            runtimeMode: .liveManual,
            sessionState: .signedOut,
            currentUser: nil,
            messageActionHandler: StubMessageActionHandler(currentUserID: "u1"),
            communityAPIClient: StubStoatAPIClient()
        )
        model.attachSessionCoordinator(coordinator)
        await coordinator.startLiveFirstSession()
        for _ in 0..<40 where coordinator.sessionState != .connected {
            try? await Task.sleep(for: .milliseconds(10))
        }
        model.syncFromSessionCoordinator()
        try await Task.sleep(for: .milliseconds(60))

        model.messageDensity = .compact
        model.settingsChangedLocally()
        try await Task.sleep(for: MainShellViewModel.automaticSettingsPushDelay + .milliseconds(300))

        let fetches = await api.fetchedSettingsKeys.count
        let pushes = await api.setSettingsPayloads.count
        XCTAssertEqual(fetches, 0)
        XCTAssertEqual(pushes, 0)
    }
}
