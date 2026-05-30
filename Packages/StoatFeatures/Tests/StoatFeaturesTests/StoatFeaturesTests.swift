import StoatModels
import StoatAPI
import StoatPersistence
import StoatRealtime
import XCTest
@testable import StoatFeatures

final class StoatFeaturesTests: XCTestCase {
    func testPhaseThreeStatusUsesOfficialEnvironment() {
        XCTAssertEqual(PhaseThreeStatus.current.environment.apiBaseURL.host(), "api.stoat.chat")
        XCTAssertTrue(PhaseThreeStatus.current.readyFields.contains(.servers))
    }

    @MainActor
    func testRootViewCanBeConstructed() {
        _ = LiquidBagelRootView()
    }

    @MainActor
    func testInitialSelectionDefaultsToHome() {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot)
        XCTAssertEqual(model.selection.space, .home)
        XCTAssertNil(model.selection.serverID)
        XCTAssertNil(model.selection.channelID)
    }

    @MainActor
    func testSelectingServerUpdatesSelectionAndAutoSelectsFirstTextChannel() {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot)
        let server = model.servers.first { $0.name == "Bagel Lab" }!

        model.selectServer(server.id)

        XCTAssertEqual(model.selection.space, .server(server.id))
        XCTAssertEqual(model.selection.serverID, server.id)
        XCTAssertEqual(model.selectedChannel?.kind, .textChannel)
        XCTAssertEqual(model.selectedChannel?.displayName, "general")
    }

    @MainActor
    func testSelectingChannelUpdatesChannelAndServerRoute() {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot)
        let channel = model.snapshot.channelsByID.values.first { $0.displayName == "macos-native" }!

        model.selectChannel(channel.id)

        XCTAssertEqual(model.selection.serverID, channel.serverID)
        XCTAssertEqual(model.selection.channelID, channel.id)
        XCTAssertEqual(model.selection.space, .server(channel.serverID!))
    }

    @MainActor
    func testHomeAndDiscoverClearServerChannelSelection() {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot)
        model.selectServer(model.servers[0].id)

        model.selectHome()
        XCTAssertEqual(model.selection.space, .home)
        XCTAssertNil(model.selection.serverID)
        XCTAssertNil(model.selection.channelID)

        model.selectDiscover()
        XCTAssertEqual(model.selection.space, .discover)
        XCTAssertNil(model.selection.serverID)
        XCTAssertNil(model.selection.channelID)
    }

    @MainActor
    func testToggleMemberPanel() {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot)
        XCTAssertTrue(model.selection.isMemberPanelVisible)
        model.toggleMemberPanel()
        XCTAssertFalse(model.selection.isMemberPanelVisible)
    }

    @MainActor
    func testInvalidSelectedChannelFallsBackSafely() {
        let server = MockShellData.snapshot.serversByID.values.first { $0.name == "Bagel Lab" }!
        let model = MainShellViewModel(
            selection: ShellSelection(space: .server(server.id), serverID: server.id, channelID: "missing"),
            snapshot: MockShellData.snapshot
        )

        XCTAssertEqual(model.selectedChannel?.displayName, "general")
    }

    @MainActor
    func testServerIndexSelectionHandlesValidAndOutOfRangeIndexes() {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot)

        model.selectServer(atOneBasedIndex: 1)
        XCTAssertEqual(model.selection.serverID, model.servers[0].id)

        let selected = model.selection.serverID
        model.selectServer(atOneBasedIndex: 99)
        XCTAssertEqual(model.selection.serverID, selected)
    }

    func testMessageGroupingEmptyInputReturnsEmpty() {
        XCTAssertEqual(MessageGrouping.group([]), [])
    }

    func testMessageGroupingSameAuthorCloseTimeGroupsTogether() {
        let messages = [
            message(id: ulid(milliseconds: 1_000), author: "a", channel: "c"),
            message(id: ulid(milliseconds: 1_000 + 60_000), author: "a", channel: "c")
        ]

        XCTAssertEqual(MessageGrouping.group(messages).map(\.messages.count), [2])
    }

    func testMessageGroupingSameAuthorFarTimeSplits() {
        let messages = [
            message(id: ulid(milliseconds: 1_000), author: "a", channel: "c"),
            message(id: ulid(milliseconds: 1_000 + 10 * 60_000), author: "a", channel: "c")
        ]

        XCTAssertEqual(MessageGrouping.group(messages).map(\.messages.count), [1, 1])
    }

    func testMessageGroupingDifferentAuthorSplits() {
        let messages = [
            message(id: ulid(milliseconds: 1_000), author: "a", channel: "c"),
            message(id: ulid(milliseconds: 2_000), author: "b", channel: "c")
        ]

        XCTAssertEqual(MessageGrouping.group(messages).count, 2)
    }

    func testMessageGroupingDifferentChannelSplits() {
        let messages = [
            message(id: ulid(milliseconds: 1_000), author: "a", channel: "c1"),
            message(id: ulid(milliseconds: 2_000), author: "a", channel: "c2")
        ]

        XCTAssertEqual(MessageGrouping.group(messages).count, 2)
    }

    func testMessageGroupingSystemMessagesSplit() {
        let messages = [
            message(id: ulid(milliseconds: 1_000), author: "a", channel: "c"),
            message(id: ulid(milliseconds: 2_000), author: "a", channel: "c", system: SystemMessage(kind: .text, content: "joined"))
        ]

        XCTAssertEqual(MessageGrouping.group(messages).count, 2)
    }

    func testMessageGroupingRepliesSplitButEditedMessagesDoNot() {
        let messages = [
            message(id: ulid(milliseconds: 1_000), author: "a", channel: "c", edited: true),
            message(id: ulid(milliseconds: 2_000), author: "a", channel: "c"),
            message(id: ulid(milliseconds: 3_000), author: "a", channel: "c", replies: ["reply"])
        ]

        XCTAssertEqual(MessageGrouping.group(messages).map(\.messages.count), [2, 1])
    }

    @MainActor
    func testSessionStartsInMockModeAndDoesNotAutoConnect() async throws {
        let realtime = RecordingRealtimeClient()
        let session = AppSessionCoordinator(
            tokenStore: InMemoryTokenStore(),
            apiClientFactory: { _, _ in RecordingAPIClient() },
            realtimeClientFactory: { realtime }
        )

        XCTAssertEqual(session.mode, .mock)
        XCTAssertEqual(session.sessionState, .mock)
        await session.startMockSession()

        let connectCallCount = await realtime.connectCallCount
        XCTAssertEqual(connectCallCount, 0)
        XCTAssertEqual(session.snapshot, MockShellData.snapshot)
    }

    @MainActor
    func testMissingCredentialProducesSignedOutStateWithoutConnecting() async throws {
        let realtime = RecordingRealtimeClient()
        let session = AppSessionCoordinator(
            tokenStore: InMemoryTokenStore(),
            apiClientFactory: { _, _ in RecordingAPIClient() },
            realtimeClientFactory: { realtime }
        )

        await session.connectLiveManually()

        XCTAssertEqual(session.mode, .liveManual)
        XCTAssertEqual(session.sessionState, .signedOut)
        let connectCallCount = await realtime.connectCallCount
        XCTAssertEqual(connectCallCount, 0)
    }

    @MainActor
    func testManualConnectAndDisconnectUseRealtimeClientMock() async throws {
        let store = InMemoryTokenStore(credential: .sessionToken("token"))
        let realtime = RecordingRealtimeClient(statesOnConnect: [.connecting, .ready])
        let api = RecordingAPIClient()
        let session = AppSessionCoordinator(
            tokenStore: store,
            apiClientFactory: { _, _ in api },
            realtimeClientFactory: { realtime }
        )

        await session.connectLiveManually()
        try await Task.sleep(for: .milliseconds(30))

        let connectCallCount = await realtime.connectCallCount
        XCTAssertEqual(connectCallCount, 1)
        XCTAssertEqual(session.sessionState, .connected)

        await session.disconnectLive()

        let disconnectCallCount = await realtime.disconnectCallCount
        XCTAssertEqual(disconnectCallCount, 1)
        XCTAssertEqual(session.sessionState, .readyToConnect)
    }

    @MainActor
    func testInvalidSessionSurfacesFailedState() async throws {
        let store = InMemoryTokenStore(credential: .sessionToken("token"))
        let realtime = RecordingRealtimeClient(statesOnConnect: [.failed(.authenticationFailed(.invalidSession))])
        let session = AppSessionCoordinator(
            tokenStore: store,
            apiClientFactory: { _, _ in RecordingAPIClient() },
            realtimeClientFactory: { realtime }
        )

        await session.connectLiveManually()
        try await Task.sleep(for: .milliseconds(30))

        if case let .failed(message) = session.sessionState {
            XCTAssertFalse(message.isEmpty)
        } else {
            XCTFail("Expected failed session state")
        }
    }

    @MainActor
    func testManualTokenImportSavesOnlyAfterValidationSucceeds() async throws {
        let store = InMemoryTokenStore()
        let validator = StubSessionValidator(user: User(id: "user-validated", username: "validated"))
        let session = AppSessionCoordinator(
            tokenStore: store,
            sessionValidator: validator,
            apiClientFactory: { _, _ in RecordingAPIClient() }
        )

        await session.validateImportedToken("secret-token", localLabel: "Main Stoat")
        XCTAssertEqual(session.sessionState, .validatedReady)
        let beforeSaveCredential = try await store.loadCredential(scope: .production)
        XCTAssertNil(beforeSaveCredential)

        await session.savePendingValidatedSession()

        let afterSaveCredential = try await store.loadCredential(scope: .production)
        XCTAssertEqual(afterSaveCredential?.token, "secret-token")
        XCTAssertEqual(session.sessionState, .readyToConnect)
    }

    @MainActor
    func testFailedValidationDoesNotSaveToken() async throws {
        let store = InMemoryTokenStore()
        let validator = StubSessionValidator(error: SessionValidationError.invalidOrExpired)
        let session = AppSessionCoordinator(
            tokenStore: store,
            sessionValidator: validator,
            apiClientFactory: { _, _ in RecordingAPIClient() }
        )

        await session.validateImportedToken("bad-token")

        let savedCredential = try await store.loadCredential(scope: .production)
        XCTAssertNil(savedCredential)
        if case .invalidSession = session.sessionState {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected invalid session state")
        }
    }

    @MainActor
    func testValidateSavedSessionDoesNotAutoConnect() async throws {
        let store = InMemoryTokenStore(credential: .sessionToken("token"))
        let realtime = RecordingRealtimeClient(statesOnConnect: [.ready])
        let session = AppSessionCoordinator(
            tokenStore: store,
            sessionValidator: StubSessionValidator(user: User(id: "saved-user", username: "saved")),
            apiClientFactory: { _, _ in RecordingAPIClient() },
            realtimeClientFactory: { realtime }
        )

        await session.validateSavedSession()

        XCTAssertEqual(session.sessionState, .readyToConnect)
        XCTAssertEqual(session.currentUser?.id, "saved-user")
        let connectCallCount = await realtime.connectCallCount
        XCTAssertEqual(connectCallCount, 0)
    }

    @MainActor
    func testStartupLoadsPreferencesButStaysMock() async throws {
        let custom = try EnvironmentProfile.custom(
            name: "Local",
            environment: StoatAPIEnvironment(apiBaseURL: URL(string: "http://localhost:14702")!, eventsURL: URL(string: "ws://localhost:14703")!)
        )
        let preferences = try AppPreferences.defaults.upserting(profile: custom).withSelectedEnvironmentID(custom.id)
        let session = AppSessionCoordinator(
            tokenStore: InMemoryTokenStore(),
            preferencesStore: InMemoryAppPreferencesStore(preferences: preferences),
            apiClientFactory: { _, _ in RecordingAPIClient() }
        )

        await session.startMockSession()

        XCTAssertEqual(session.mode, .mock)
        XCTAssertEqual(session.environment, custom.environment)
        XCTAssertEqual(session.preferences.lastSelectedEnvironmentID, custom.id)
    }

    @MainActor
    func testStartupSavedCredentialBecomesReadyWithoutConnecting() async throws {
        let custom = try EnvironmentProfile.custom(
            name: "Local",
            environment: StoatAPIEnvironment(apiBaseURL: URL(string: "http://localhost:14702")!, eventsURL: URL(string: "ws://localhost:14703")!)
        )
        let preferences = try AppPreferences.defaults.upserting(profile: custom).withSelectedEnvironmentID(custom.id)
        let store = InMemoryTokenStore()
        try await store.saveCredential(.sessionToken("custom-token"), scope: CredentialScope(environmentID: custom.id))
        let realtime = RecordingRealtimeClient(statesOnConnect: [.ready])
        let session = AppSessionCoordinator(
            tokenStore: store,
            preferencesStore: InMemoryAppPreferencesStore(preferences: preferences),
            apiClientFactory: { _, _ in RecordingAPIClient() },
            realtimeClientFactory: { realtime }
        )

        await session.startMockSession()

        XCTAssertEqual(session.mode, .mock)
        XCTAssertEqual(session.sessionState, .readyToConnect)
        XCTAssertTrue(session.hasSavedCredential)
        let connectCallCount = await realtime.connectCallCount
        XCTAssertEqual(connectCallCount, 0)
    }

    @MainActor
    func testEnvironmentSwitchingUsesScopedCredentialAvailabilityAndPersistsSelection() async throws {
        let custom = try EnvironmentProfile.custom(
            name: "Local",
            environment: StoatAPIEnvironment(apiBaseURL: URL(string: "http://localhost:14702")!, eventsURL: URL(string: "ws://localhost:14703")!)
        )
        let preferences = try AppPreferences.defaults.upserting(profile: custom)
        let preferencesStore = InMemoryAppPreferencesStore(preferences: preferences)
        let tokenStore = InMemoryTokenStore()
        try await tokenStore.saveCredential(.sessionToken("custom-token"), scope: CredentialScope(environmentID: custom.id))
        let session = AppSessionCoordinator(
            tokenStore: tokenStore,
            preferencesStore: preferencesStore,
            apiClientFactory: { _, _ in RecordingAPIClient() }
        )

        await session.startMockSession()
        await session.selectEnvironmentProfile(id: custom.id)

        XCTAssertEqual(session.preferences.lastSelectedEnvironmentID, custom.id)
        XCTAssertTrue(session.hasSavedCredential)

        await session.selectEnvironmentProfile(id: "production")
        XCTAssertFalse(session.hasSavedCredential)
        let saved = try await preferencesStore.loadPreferences()
        XCTAssertEqual(saved.lastSelectedEnvironmentID, "production")
    }

    @MainActor
    func testPreferenceSaveFailureSurfacesWithoutCrashing() async {
        let session = AppSessionCoordinator(
            preferencesStore: InMemoryAppPreferencesStore(saveError: MessageActionError.unavailable("save failed")),
            apiClientFactory: { _, _ in RecordingAPIClient() }
        )

        await session.updatePreferences { preferences in
            preferences.memberPanelVisible = false
        }

        XCTAssertTrue(session.preferenceErrorMessage?.contains("save failed") == true)
    }

    @MainActor
    func testForgetSessionDisconnectsAndClearsScopedCredential() async throws {
        let store = InMemoryTokenStore(credential: .sessionToken("token"))
        let realtime = RecordingRealtimeClient(statesOnConnect: [.ready])
        let session = AppSessionCoordinator(
            tokenStore: store,
            sessionValidator: StubSessionValidator(),
            apiClientFactory: { _, _ in RecordingAPIClient() },
            realtimeClientFactory: { realtime }
        )

        await session.connectLiveManually()
        await session.forgetLocalSession()

        let savedCredential = try await store.loadCredential(scope: .production)
        XCTAssertNil(savedCredential)
        XCTAssertEqual(session.sessionState, .signedOut)
        let disconnectCallCount = await realtime.disconnectCallCount
        XCTAssertGreaterThanOrEqual(disconnectCallCount, 1)
    }

    @MainActor
    func testResetToMockPreservesSavedCredential() async throws {
        let store = InMemoryTokenStore(credential: .sessionToken("token"))
        let session = AppSessionCoordinator(
            tokenStore: store,
            sessionValidator: StubSessionValidator(),
            apiClientFactory: { _, _ in RecordingAPIClient() }
        )

        await session.resetToMock()

        XCTAssertEqual(session.mode, .mock)
        let savedCredential = try await store.loadCredential(scope: .production)
        XCTAssertEqual(savedCredential?.token, "token")
    }

    @MainActor
    func testLiveVerificationStateCanRecordHarnessChecks() {
        let session = AppSessionCoordinator()

        session.markSelectedChannelMessageFetchSucceeded(channelID: "channel", isAvailable: true)
        session.markLastMessageActionResult("Send action attempted.")

        XCTAssertTrue(session.verificationState.selectedChannelAvailable)
        XCTAssertTrue(session.verificationState.messageFetchSucceeded)
        XCTAssertEqual(session.verificationState.lastMessageActionResult, "Send action attempted.")
    }

    @MainActor
    func testAccountSessionViewModelLoadsRenamesAndRevokesSessions() async throws {
        let currentID: SessionID = "01J00000000000000000000001"
        let otherID: SessionID = "01J00000010000000000000001"
        let manager = MockSessionManager(sessions: [
            SessionInfo(id: currentID, name: "Mac"),
            SessionInfo(id: otherID, name: "Phone")
        ])
        let model = AccountSessionViewModel(
            currentUser: User(id: "user", username: "test"),
            currentSessionID: currentID,
            sessionManager: manager,
            credentialProvider: { .userSession(token: "secret", sessionID: currentID) }
        )

        await model.refreshSessions()
        XCTAssertEqual(model.sessionsState.sessions.count, 2)
        XCTAssertTrue(model.sessionsState.sessions.first { $0.id == currentID }?.isCurrent == true)

        await model.renameSession(id: otherID, friendlyName: "Tablet")
        let renamed = await manager.renamedSessions
        XCTAssertEqual(renamed.first?.1, "Tablet")

        await model.revokeSession(id: otherID)
        let revoked = await manager.revokedSessionIDs
        XCTAssertEqual(revoked, [otherID])
    }

    @MainActor
    func testAccountSessionViewModelStatesAndValidation() async {
        let empty = AccountSessionViewModel(
            sessionManager: MockSessionManager(),
            credentialProvider: { .sessionToken("secret") }
        )

        await empty.refreshSessions()
        XCTAssertEqual(empty.sessionsState, .empty)

        await empty.renameSession(id: "session", friendlyName: "   ")
        XCTAssertTrue(empty.errorMessage?.contains("cannot be blank") == true)

        let failing = AccountSessionViewModel(
            sessionManager: MockSessionManager(error: MessageActionError.unavailable("api failed")),
            credentialProvider: { .sessionToken("secret") }
        )
        await failing.refreshSessions()
        if case let .failed(message) = failing.sessionsState {
            XCTAssertTrue(message.contains("api failed"))
        } else {
            XCTFail("Expected failed session state")
        }
    }

    @MainActor
    func testRevokeAllOtherSessionsUsesRevokeSelfFalse() async {
        let manager = MockSessionManager(sessions: [
            SessionInfo(id: "01J00000000000000000000001", name: "Mac"),
            SessionInfo(id: "01J00000010000000000000001", name: "Phone")
        ])
        let model = AccountSessionViewModel(
            currentSessionID: "01J00000000000000000000001",
            sessionManager: manager,
            credentialProvider: { .userSession(token: "secret", sessionID: "01J00000000000000000000001") }
        )

        await model.refreshSessions()
        await model.revokeAllOtherSessions()

        let arguments = await manager.revokeAllArguments
        XCTAssertEqual(arguments, [false])
    }

    @MainActor
    func testConnectionSettingsViewModelSavesSelectedEnvironmentAndValidationErrors() async throws {
        let store = InMemoryAppPreferencesStore()
        let model = ConnectionSettingsViewModel(preferencesStore: store)

        await model.addEnvironment(name: "Local", apiURL: "http://localhost:14702", eventsURL: "ws://localhost:14703")
        let selected = try XCTUnwrap(model.selectedEnvironmentID)
        let saved = try await store.loadPreferences()

        XCTAssertEqual(saved.lastSelectedEnvironmentID, selected)

        await model.addEnvironment(name: "Bad", apiURL: "http://example.com", eventsURL: "wss://events.example.com")
        XCTAssertNotNil(model.errorMessage)
    }

    func testPhase6UIHelpersAreSafe() {
        let id: SessionID = "01J00000000000000000000001"

        XCTAssertEqual(Phase6UIHelpers.shortenedSessionID(id), "01J000...0001")
        XCTAssertEqual(Phase6UIHelpers.credentialPresenceLabel(hasCredential: true), "Credential saved for this environment")
        XCTAssertFalse(Phase6UIHelpers.credentialPresenceLabel(hasCredential: true).localizedCaseInsensitiveContains("secret"))
        XCTAssertFalse(Phase6UIHelpers.safeDiagnostics("X-Session-Token: secret").contains("secret"))
    }

    func testMockSnapshotSourceEmitsInitialSnapshot() async {
        var iterator = MockShellSnapshotSource(snapshot: MockShellData.snapshot).snapshots.makeAsyncIterator()
        let snapshot = await iterator.next()

        XCTAssertEqual(snapshot, MockShellData.snapshot)
    }

    @MainActor
    func testViewModelObservesSnapshotAndKeepsValidSelection() async throws {
        let source = MutableSnapshotSource(snapshot: MockShellData.snapshot)
        let model = MainShellViewModel(snapshot: MockShellData.snapshot, snapshotSource: source)
        let server = model.servers.first { $0.name == "Bagel Lab" }!
        model.selectServer(server.id)
        let selected = try XCTUnwrap(model.selection.channelID)

        source.yield(MockShellData.snapshot)
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(model.selection.channelID, selected)
    }

    @MainActor
    func testDeletedSelectedChannelFallsBackSafely() async throws {
        let source = MutableSnapshotSource(snapshot: MockShellData.snapshot)
        let model = MainShellViewModel(snapshot: MockShellData.snapshot, snapshotSource: source)
        let server = model.servers.first { $0.name == "Bagel Lab" }!
        model.selectServer(server.id)
        let deleted = try XCTUnwrap(model.selection.channelID)
        var snapshot = MockShellData.snapshot
        snapshot.channelsByID.removeValue(forKey: deleted)
        snapshot.serversByID[server.id]?.channelIDs.removeAll { $0 == deleted }

        source.yield(snapshot)
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertNotEqual(model.selection.channelID, deleted)
        XCTAssertNotNil(model.selection.channelID)
    }

    @MainActor
    func testDeletedSelectedServerFallsBackHome() async throws {
        let source = MutableSnapshotSource(snapshot: MockShellData.snapshot)
        let model = MainShellViewModel(snapshot: MockShellData.snapshot, snapshotSource: source)
        let server = model.servers.first { $0.name == "Bagel Lab" }!
        model.selectServer(server.id)
        var snapshot = MockShellData.snapshot
        snapshot.serversByID.removeValue(forKey: server.id)

        source.yield(snapshot)
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(model.selection.space, .home)
    }

    @MainActor
    func testMessageLoadingUsesSnapshotInMockModeAndDoesNotCallAPI() async {
        let api = RecordingAPIClient()
        let controller = ChannelMessageController(runtimeMode: .mock, apiClient: api)
        let channelID = MockShellData.snapshot.messagesByChannelID.keys.first!

        await controller.loadInitialMessages(channelID: channelID, snapshotMessages: MockShellData.snapshot.messagesByChannelID[channelID] ?? [])

        XCTAssertTrue(controller.state(for: channelID).hasMessages)
        let fetchMessagesCallCount = await api.fetchMessagesCallCount
        XCTAssertEqual(fetchMessagesCallCount, 0)
    }

    @MainActor
    func testLiveMessageLoadingFetchesPaginatesDedupesAndSorts() async {
        let channelID: ChannelID = "channel"
        let older = message(id: ulid(milliseconds: 1_000), author: "a", channel: channelID)
        let newer = message(id: ulid(milliseconds: 2_000), author: "a", channel: channelID)
        let api = RecordingAPIClient(messagesByChannel: [channelID: [older, newer, newer]])
        let controller = ChannelMessageController(runtimeMode: .liveManual, apiClient: api, currentUserID: "a", pageSize: 2)

        await controller.loadInitialMessages(channelID: channelID, snapshotMessages: [])

        XCTAssertEqual(controller.state(for: channelID).timelineMessages.map(\.message.id), [older.id, newer.id])
        let firstFetchMessagesCallCount = await api.fetchMessagesCallCount
        XCTAssertEqual(firstFetchMessagesCallCount, 1)

        await controller.loadOlderMessages(channelID: channelID)
        let secondFetchMessagesCallCount = await api.fetchMessagesCallCount
        XCTAssertEqual(secondFetchMessagesCallCount, 2)
    }

    @MainActor
    func testFailedLiveLoadKeepsCachedMessages() async {
        let channelID: ChannelID = "channel"
        let cached = message(id: ulid(milliseconds: 1_000), author: "a", channel: channelID)
        let api = RecordingAPIClient(messagesByChannel: [channelID: [cached]], fetchError: MessageActionError.unavailable("boom"))
        let controller = ChannelMessageController(runtimeMode: .liveManual, apiClient: api, currentUserID: "a")

        await controller.loadInitialMessages(channelID: channelID, snapshotMessages: [cached])

        if case let .failed(message, cachedMessages) = controller.state(for: channelID) {
            XCTAssertTrue(message.contains("boom"))
            XCTAssertEqual(cachedMessages.map(\.message.id), [cached.id])
        } else {
            XCTFail("Expected failed state")
        }
    }

    @MainActor
    func testComposerDraftsSendSuccessAndEchoDedupe() async {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot)
        let server = model.servers.first { $0.name == "Bagel Lab" }!
        model.selectServer(server.id)
        let channelID = model.selection.channelID!
        model.updateDraft("hello", for: channelID)

        await model.sendDraft(for: channelID)
        let sent = model.selectedTimelineMessages.filter { $0.message.content == "hello" }

        XCTAssertEqual(model.draft(for: channelID), "")
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?.status, .confirmed)

        model.messageController.hydrate(from: RealtimeSnapshot(messagesByChannelID: [channelID: sent.map(\.message)]))
        XCTAssertEqual(model.selectedTimelineMessages.filter { $0.message.content == "hello" }.count, 1)
    }

    @MainActor
    func testFailedSendMarksTimelineMessageFailed() async {
        let handler = MockMessageActionHandler(sendError: MessageActionError.unavailable("send failed"))
        let model = MainShellViewModel(snapshot: MockShellData.snapshot, messageActionHandler: handler)
        let server = model.servers.first { $0.name == "Bagel Lab" }!
        model.selectServer(server.id)
        let channelID = model.selection.channelID!
        model.updateDraft("hello", for: channelID)

        await model.sendDraft(for: channelID)

        XCTAssertTrue(model.selectedTimelineMessages.contains { if case .failed = $0.status { true } else { false } })
    }

    @MainActor
    func testDraftsArePerChannelAndEmptyDraftCannotSend() async {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot)
        let channels = model.channels(for: model.servers.first { $0.name == "Bagel Lab" }!.id).filter { $0.kind == .textChannel }

        model.updateDraft("one", for: channels[0].id)
        model.updateDraft("two", for: channels[1].id)

        XCTAssertEqual(model.draft(for: channels[0].id), "one")
        XCTAssertEqual(model.draft(for: channels[1].id), "two")
        XCTAssertFalse(model.composerReadiness(for: channels[0].id).canSend == false)

        model.updateDraft("   ", for: channels[0].id)
        XCTAssertFalse(model.composerReadiness(for: channels[0].id).canSend)
    }

    @MainActor
    func testEditDeleteAndReactionActionsCallHandler() async {
        let handler = MockMessageActionHandler()
        let model = MainShellViewModel(snapshot: MockShellData.snapshot, messageActionHandler: handler)
        let server = model.servers.first { $0.name == "Bagel Lab" }!
        model.selectServer(server.id)
        let ownMessage = model.selectedTimelineMessages.first { $0.message.authorID == MockShellData.currentUserID }!

        model.beginEditing(ownMessage)
        model.editingDraft?.content = "edited"
        await model.saveEditingDraft()
        model.requestDelete(ownMessage)
        await model.confirmPendingDelete()
        await model.toggleReaction("👍", on: ownMessage)

        let editedCount = await handler.editedMessages.count
        let deletedCount = await handler.deletedMessages.count
        let reactionCount = await handler.addedReactions.count
        XCTAssertEqual(editedCount, 1)
        XCTAssertEqual(deletedCount, 1)
        XCTAssertEqual(reactionCount, 1)
    }

    @MainActor
    func testTypingBeginDoesNotSpamAndChannelSwitchEndsTyping() async throws {
        let handler = MockMessageActionHandler()
        let model = MainShellViewModel(snapshot: MockShellData.snapshot, messageActionHandler: handler)
        let server = model.servers.first { $0.name == "Bagel Lab" }!
        model.selectServer(server.id)
        let channelID = model.selection.channelID!

        model.updateDraft("h", for: channelID)
        model.updateDraft("he", for: channelID)
        try await Task.sleep(for: .milliseconds(30))
        model.selectHome()
        try await Task.sleep(for: .milliseconds(30))

        let events = await handler.typingEvents
        XCTAssertEqual(events.filter { if case .beginTyping = $0 { true } else { false } }.count, 1)
        XCTAssertEqual(events.filter { if case .endTyping = $0 { true } else { false } }.count, 1)
    }

    @MainActor
    func testCurrentUserExcludedFromTypingDisplayAndUnreadClearsOnSelection() {
        var snapshot = MockShellData.snapshot
        let server = snapshot.serversByID.values.first { $0.name == "Bagel Lab" }!
        let channelID = server.channelIDs[1]
        snapshot.typingUsersByChannelID[channelID, default: []].insert(MockShellData.currentUserID)
        let model = MainShellViewModel(snapshot: snapshot)

        model.selectChannel(channelID)

        XCTAssertFalse(model.typingUsers(for: channelID).contains { $0.id == MockShellData.currentUserID })
        XCTAssertNil(model.unread(for: channelID)?.lastMessageID)
    }

    func testSelectionRestorerRestoresPersistedServerAndChannel() throws {
        let snapshot = MockShellData.snapshot
        let server = try XCTUnwrap(snapshot.serversByID.values.first { $0.name == "Bagel Lab" })
        let channel = try XCTUnwrap(snapshot.channelsByID.values.first { $0.displayName == "macos-native" })
        let preferences = AppPreferences(lastSelectedServerID: server.id, lastSelectedChannelID: channel.id)

        let result = ShellSelectionRestorer().restore(
            preferredSelection: nil,
            preferences: preferences,
            snapshot: snapshot,
            mode: .liveManual
        )

        XCTAssertEqual(result.selection.serverID, server.id)
        XCTAssertEqual(result.selection.channelID, channel.id)
        XCTAssertTrue(result.selectedServerAvailable)
        XCTAssertTrue(result.selectedChannelAvailable)
    }

    func testSelectionRestorerFallsBackToFirstTextChannelWhenChannelMissing() throws {
        let snapshot = MockShellData.snapshot
        let server = try XCTUnwrap(snapshot.serversByID.values.first { $0.name == "Bagel Lab" })
        let preferences = AppPreferences(lastSelectedServerID: server.id, lastSelectedChannelID: "missing")

        let result = ShellSelectionRestorer().restore(
            preferredSelection: nil,
            preferences: preferences,
            snapshot: snapshot,
            mode: .liveManual
        )

        XCTAssertEqual(result.selection.serverID, server.id)
        XCTAssertEqual(result.selection.channelID, server.channelIDs.first)
        XCTAssertTrue(result.selectedServerAvailable)
        XCTAssertFalse(result.selectedChannelAvailable)
    }

    func testSelectionRestorerFallsBackToFirstAvailableServerWhenServerMissing() {
        let preferences = AppPreferences(lastSelectedServerID: "missing-server", lastSelectedChannelID: "missing-channel")

        let result = ShellSelectionRestorer().restore(
            preferredSelection: nil,
            preferences: preferences,
            snapshot: MockShellData.snapshot,
            mode: .liveManual
        )

        XCTAssertEqual(result.selection.space, .server(result.selection.serverID!))
        XCTAssertNotNil(result.selection.channelID)
        XCTAssertFalse(result.selectedServerAvailable)
        XCTAssertFalse(result.selectedChannelAvailable)
    }

    func testSelectionRestorerHandlesNoServersAndNoTextChannels() {
        let empty = ShellSelectionRestorer().restore(
            preferredSelection: nil,
            preferences: .defaults,
            snapshot: RealtimeSnapshot(),
            mode: .liveManual
        )

        XCTAssertEqual(empty.selection.space, .home)
        XCTAssertEqual(empty.message, "No servers available")

        let owner: UserID = "owner"
        let serverID: ServerID = "server"
        let voice: ChannelID = "voice"
        let snapshot = RealtimeSnapshot(
            serversByID: [serverID: Server(id: serverID, ownerID: owner, name: "Voice", channelIDs: [voice])],
            channelsByID: [voice: Channel(id: voice, kind: .voiceChannel, serverID: serverID, name: "voice")]
        )
        let noText = ShellSelectionRestorer().restore(
            preferredSelection: nil,
            preferences: .defaults,
            snapshot: snapshot,
            mode: .liveManual
        )

        XCTAssertEqual(noText.selection.serverID, serverID)
        XCTAssertNil(noText.selection.channelID)
        XCTAssertEqual(noText.message, "No text channels available")
    }

    func testSelectionRestorerPreservesHomeWithoutPersistedSelection() {
        let result = ShellSelectionRestorer().restore(
            preferredSelection: ShellSelection(space: .home),
            preferences: .defaults,
            snapshot: MockShellData.snapshot,
            mode: .liveManual
        )

        XCTAssertEqual(result.selection.space, .home)
        XCTAssertNil(result.selection.channelID)
    }

    @MainActor
    func testReadyEventUpdatesHydrationStatus() async throws {
        let store = InMemoryTokenStore(credential: .sessionToken("token"))
        let ready = StoatGatewayEvent.ready(ReadyPayload(
            users: Array(MockShellData.snapshot.usersByID.values),
            servers: Array(MockShellData.snapshot.serversByID.values),
            channels: Array(MockShellData.snapshot.channelsByID.values),
            members: MockShellData.snapshot.membersByServerAndUserID.values.map { $0 },
            channelUnreads: Array(MockShellData.snapshot.unreadsByChannelID.values)
        ))
        let realtime = RecordingRealtimeClient(statesOnConnect: [.connecting, .authenticated, .ready], eventsOnConnect: [ready])
        let session = AppSessionCoordinator(
            tokenStore: store,
            sessionValidator: StubSessionValidator(),
            apiClientFactory: { _, _ in RecordingAPIClient() },
            realtimeClientFactory: { realtime }
        )

        await session.connectLiveManually()
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertTrue(session.hydrationStatus.readyReceived)
        XCTAssertEqual(session.hydrationStatus.serverCount, MockShellData.snapshot.serversByID.count)
        XCTAssertEqual(session.hydrationStatus.channelCount, MockShellData.snapshot.channelsByID.count)
        XCTAssertNil(session.hydrationStatus.warning)
    }

    @MainActor
    func testManualReconnectDisconnectsExistingClientFirstAndUsesSelectedEnvironment() async throws {
        let custom = try EnvironmentProfile.custom(
            name: "Local",
            environment: StoatAPIEnvironment(apiBaseURL: URL(string: "http://localhost:14702")!, eventsURL: URL(string: "ws://localhost:14703")!)
        )
        let preferences = try AppPreferences.defaults.upserting(profile: custom).withSelectedEnvironmentID(custom.id)
        let tokenStore = InMemoryTokenStore()
        try await tokenStore.saveCredential(.sessionToken("custom-token"), scope: CredentialScope(environmentID: custom.id))
        let realtime = RecordingRealtimeClient(statesOnConnect: [.ready])
        let session = AppSessionCoordinator(
            tokenStore: tokenStore,
            preferencesStore: InMemoryAppPreferencesStore(preferences: preferences),
            sessionValidator: StubSessionValidator(),
            apiClientFactory: { _, _ in RecordingAPIClient() },
            realtimeClientFactory: { realtime }
        )

        await session.startMockSession()
        await session.connectLiveManually()
        await session.reconnectLiveManually()

        let connectCallCount = await realtime.connectCallCount
        let disconnectCallCount = await realtime.disconnectCallCount
        let environments = await realtime.connectedEnvironments
        XCTAssertEqual(connectCallCount, 2)
        XCTAssertGreaterThanOrEqual(disconnectCallCount, 1)
        XCTAssertEqual(environments.last, custom.environment)
    }

    @MainActor
    func testRefreshBehaviorByRuntimeState() async throws {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot)
        model.refreshCurrentContext()
        XCTAssertEqual(model.placeholderStatus, "Mock data refreshed")

        let live = MainShellViewModel(runtimeMode: .liveManual, sessionState: .readyToConnect, currentUser: nil)
        live.refreshCurrentContext()
        XCTAssertEqual(live.placeholderStatus, "Reconnect to refresh live state")
    }

    func testPhase7UIHelpersAreSafe() {
        let hydration = LiveHydrationStatus(readyReceived: true, serverCount: 1, channelCount: 2)

        XCTAssertEqual(Phase6UIHelpers.hydrationLabel(hydration), "Ready hydrated 1 servers and 2 channels")
        XCTAssertFalse(Phase6UIHelpers.connectionHealthText(state: .failed(.unknown("token=secret")), diagnostics: nil, hydration: hydration).contains("secret"))
        XCTAssertFalse(Phase6UIHelpers.safeDiagnostics("token: secret").contains("secret"))
    }

    @MainActor
    func testCommandRouterOpensQuickSwitcherAndFocusesComposer() {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot)
        XCTAssertTrue(model.canPerform(.openQuickSwitcher))

        model.perform(.openQuickSwitcher)
        XCTAssertTrue(model.isQuickSwitcherPresented)
        XCTAssertEqual(model.focusTarget, .quickSwitcher)

        model.selectServer(model.servers[0].id)
        model.perform(.focusComposer)
        XCTAssertEqual(model.focusTarget, .composer)
        XCTAssertEqual(model.composerFocusRequestID, 1)
    }

    @MainActor
    func testCommandRouterUnavailableCommandsNoOpSafely() {
        let model = MainShellViewModel(snapshot: RealtimeSnapshot())

        XCTAssertFalse(model.canPerform(.selectServer(index: 1)))
        model.perform(.selectServer(index: 1))
        XCTAssertTrue(model.placeholderStatus?.contains("server") == true)
    }

    @MainActor
    func testCommandRouterRefreshAndMemberPanelPreference() async throws {
        let store = InMemoryAppPreferencesStore()
        let session = AppSessionCoordinator(
            preferencesStore: store,
            apiClientFactory: { _, _ in RecordingAPIClient() }
        )
        await session.startMockSession()
        let model = MainShellViewModel(snapshot: MockShellData.snapshot, sessionCoordinator: session)
        model.syncFromSessionCoordinator()

        model.perform(.refresh)
        XCTAssertEqual(model.placeholderStatus, "Mock data refreshed")

        model.perform(.toggleMemberPanel)
        try await Task.sleep(for: .milliseconds(30))
        let saved = try await store.loadPreferences()
        XCTAssertFalse(saved.memberPanelVisible)
    }

    @MainActor
    func testQuickSwitcherIndexesFiltersAndActivatesLocalResults() {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot)
        model.perform(.openQuickSwitcher)

        XCTAssertTrue(model.quickSwitcherViewModel.results.contains { $0.title == "Bagel Lab" })
        XCTAssertTrue(model.quickSwitcherViewModel.results.contains { $0.title.contains("macos-native") })
        XCTAssertTrue(model.quickSwitcherViewModel.results.contains { $0.title == "Reconnect" })

        model.quickSwitcherViewModel.query = "macos"
        let result = model.quickSwitcherViewModel.results.first { $0.title.contains("macos-native") }
        XCTAssertNotNil(result)
        if let result, let command = model.quickSwitcherViewModel.command(for: result) {
            model.perform(command)
        }

        XCTAssertEqual(model.selectedChannel?.displayName, "macos-native")
        XCTAssertFalse(model.quickSwitcherViewModel.results.contains { $0.accessibilityLabel.localizedCaseInsensitiveContains("token") })
    }

    @MainActor
    func testQuickSwitcherEmptySnapshotStillShowsRoutesAndCommands() {
        let model = MainShellViewModel(snapshot: RealtimeSnapshot())
        model.perform(.openQuickSwitcher)
        let titles = model.quickSwitcherViewModel.results.map(\.title)

        XCTAssertTrue(titles.contains("Home"))
        XCTAssertTrue(titles.contains("Refresh"))
    }

    @MainActor
    func testNavigationHelpersMoveServersChannelsAndUnreadChannels() {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot)
        let lab = model.servers.first { $0.name == "Bagel Lab" }!
        model.selectServer(lab.id)
        XCTAssertEqual(model.selectedChannel?.displayName, "general")

        model.perform(.selectNextChannel)
        XCTAssertEqual(model.selectedChannel?.displayName, "api-research")

        model.perform(.selectNextUnreadChannel)
        XCTAssertEqual(model.selectedChannel?.displayName, "macos-native")

        model.perform(.selectPreviousChannel)
        XCTAssertEqual(model.selectedChannel?.displayName, "api-research")
    }

    @MainActor
    func testNavigationPausesWhileComposerFocused() {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot)
        model.selectServer(model.servers[0].id)
        model.requestFocus(.composer)

        XCTAssertFalse(model.canPerform(.selectNextChannel))
        model.perform(.selectNextChannel)
        XCTAssertTrue(model.placeholderStatus?.contains("typing") == true)
    }

    @MainActor
    func testTimelineSelectionMovesFallsBackAndCopiesContentOnly() async {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot)
        model.selectServer(model.servers[0].id)

        model.perform(.selectNextMessage)
        let firstID = model.timelineSelection.messageID
        XCTAssertNotNil(firstID)
        model.perform(.selectNextMessage)
        XCTAssertNotEqual(model.timelineSelection.messageID, firstID)

        let selected = model.selectedTimelineMessage!
        XCTAssertEqual(MainShellViewModel.copyableContent(for: selected.message), selected.message.content)

        model.messageController.removeMessage(channelID: selected.message.channelID, messageID: selected.message.id)
        model.reconcileTimelineSelection()
        XCTAssertNotEqual(model.timelineSelection.messageID, selected.message.id)

        model.selectChannel(model.channels(for: model.selection.serverID).last!.id)
        XCTAssertNil(model.timelineSelection.messageID)
    }

    func testPhase9HistoryReducerReconcilesOptimisticEchoFailureDiscardPinReactionAndCap() {
        let channelID: ChannelID = "channel"
        let userID: UserID = "user"
        let reducer = ChannelMessageHistoryReducer(messageCapPerChannel: 3)
        var history = ChannelMessageHistory(channelID: channelID)
        let first = message(id: ulid(milliseconds: 1_000), author: userID, channel: channelID)
        let second = message(id: ulid(milliseconds: 2_000), author: userID, channel: channelID)

        history = reducer.reduce(history, event: .initialLoadSucceeded(messages: [second, first], hasMoreBefore: true, loadedAt: Date()))
        XCTAssertEqual(history.messages.map(\.message.id), [first.id, second.id])
        XCTAssertTrue(history.hasMoreBefore)

        let pending = TimelineMessage(message: Message(id: "pending-nonce", channelID: channelID, authorID: userID, content: "local", nonce: "nonce"), status: .pending)
        history = reducer.reduce(history, event: .optimisticSendCreated(pending))
        XCTAssertEqual(history.messages.filter { $0.message.nonce == "nonce" }.count, 1)

        let confirmed = Message(id: MessageID(rawValue: ulid(milliseconds: 3_000)), channelID: channelID, authorID: userID, content: "local", nonce: "nonce")
        history = reducer.reduce(history, event: .sendConfirmed(message: confirmed, nonce: "nonce"))
        XCTAssertFalse(history.messages.contains { $0.message.id.rawValue.hasPrefix("pending-") })
        XCTAssertEqual(history.messages.filter { $0.message.nonce == "nonce" }.count, 1)

        history = reducer.reduce(history, event: .reactionChanged(messageID: confirmed.id, emoji: "👍", userID: userID, isAdding: true))
        XCTAssertEqual(history.messages.first { $0.message.id == confirmed.id }?.message.reactions["👍"], [userID])

        history = reducer.reduce(history, event: .messagePinned(confirmed.id))
        XCTAssertEqual(history.messages.first { $0.message.id == confirmed.id }?.message.pinned, true)
        history = reducer.reduce(history, event: .messageUnpinned(confirmed.id))
        XCTAssertEqual(history.messages.first { $0.message.id == confirmed.id }?.message.pinned, false)

        history = reducer.reduce(history, event: .sendFailed(nonce: "missing", error: "failed"))
        let failed = TimelineMessage(message: Message(id: "pending-failed", channelID: channelID, authorID: userID, content: "oops", nonce: "failed"), status: .pending)
        history = reducer.reduce(history, event: .optimisticSendCreated(failed))
        history = reducer.reduce(history, event: .sendFailed(nonce: "failed", error: "failed"))
        XCTAssertTrue(history.messages.contains { if case .failed = $0.status { true } else { false } })
        history = reducer.reduce(history, event: .discardLocalMessage(failed.message.id))
        XCTAssertFalse(history.messages.contains { $0.message.id == failed.message.id })

        let fourth = message(id: ulid(milliseconds: 4_000), author: userID, channel: channelID)
        history = reducer.reduce(history, event: .realtimeMessageReceived(fourth))
        XCTAssertLessThanOrEqual(history.messages.count, 3)
        XCTAssertTrue(history.messages.contains { $0.message.id == fourth.id })
    }

    @MainActor
    func testPhase9InlineEditStateSavesAndPreservesComposerDraft() async {
        let handler = MockMessageActionHandler()
        let model = MainShellViewModel(snapshot: MockShellData.snapshot, messageActionHandler: handler)
        model.selectServer(model.servers[0].id)
        let channelID = model.selection.channelID!
        let ownMessage = model.selectedTimelineMessages.first { $0.message.authorID == MockShellData.currentUserID }!

        model.updateDraft("composer survives", for: channelID)
        model.beginEditing(ownMessage)
        XCTAssertEqual(model.inlineEditState?.draftContent, ownMessage.message.content)
        XCTAssertFalse(model.inlineEditState?.canSave ?? true)

        model.updateInlineEditDraft("edited inline")
        XCTAssertTrue(model.inlineEditState?.canSave == true)
        await model.saveEditingDraft()

        let edited = await handler.editedMessages
        XCTAssertEqual(edited.count, 1)
        XCTAssertNil(model.inlineEditState)
        XCTAssertEqual(model.draft(for: channelID), "composer survives")
    }

    @MainActor
    func testPhase9DeleteDiscardAndSelectionFallback() async {
        let handler = MockMessageActionHandler()
        let model = MainShellViewModel(snapshot: MockShellData.snapshot, messageActionHandler: handler)
        model.selectServer(model.servers[0].id)
        let ownMessage = model.selectedTimelineMessages.first { $0.message.authorID == MockShellData.currentUserID }!
        model.timelineSelection = TimelineSelection(channelID: ownMessage.message.channelID, messageID: ownMessage.message.id)

        model.requestDelete(ownMessage)
        XCTAssertNotNil(model.pendingDeletion)
        await model.confirmPendingDelete()
        XCTAssertFalse(model.selectedTimelineMessages.contains { $0.message.id == ownMessage.message.id })
        XCTAssertNotEqual(model.timelineSelection.messageID, ownMessage.message.id)
        let deletedCount = await handler.deletedMessages.count
        XCTAssertEqual(deletedCount, 1)
    }

    @MainActor
    func testPhase9FailedMessageDiscardDoesNotCallAPIAndCommandsPauseWhileEditing() async {
        let handler = MockMessageActionHandler(sendError: MessageActionError.unavailable("send failed"))
        let model = MainShellViewModel(snapshot: MockShellData.snapshot, messageActionHandler: handler)
        model.selectServer(model.servers[0].id)
        let channelID = model.selection.channelID!
        model.updateDraft("hello", for: channelID)

        await model.sendDraft(for: channelID)
        let failed = model.selectedTimelineMessages.first { if case .failed = $0.status { true } else { false } }!
        model.timelineSelection = TimelineSelection(channelID: channelID, messageID: failed.message.id)

        model.perform(.discardSelectedFailedMessage)
        XCTAssertFalse(model.selectedTimelineMessages.contains { $0.message.id == failed.message.id })
        let deletedCount = await handler.deletedMessages.count
        XCTAssertEqual(deletedCount, 0)

        model.beginEditing(model.selectedTimelineMessages.first { $0.message.authorID == MockShellData.currentUserID }!)
        XCTAssertFalse(model.canPerform(.copySelectedMessage))
    }

    @MainActor
    func testPhase9PinReactionAndJumpCommandsRouteThroughSelection() async throws {
        let handler = MockMessageActionHandler()
        var snapshot = MockShellData.snapshot
        let channelID = try XCTUnwrap(snapshot.channelsByID.values.first { $0.displayName == "general" }?.id)
        snapshot.channelsByID[channelID]?.permissions = [.viewChannel, .readMessageHistory, .sendMessage, .react, .manageMessages]
        let model = MainShellViewModel(snapshot: snapshot, messageActionHandler: handler)
        model.selectChannel(channelID)
        let message = try XCTUnwrap(model.selectedTimelineMessages.first { $0.status == .confirmed })
        model.timelineSelection = TimelineSelection(channelID: channelID, messageID: message.message.id)

        model.perform(.pinOrUnpinSelectedMessage)
        try await Task.sleep(for: .milliseconds(30))
        let pinnedCount = await handler.pinnedMessages.count
        XCTAssertEqual(pinnedCount, 1)
        XCTAssertEqual(model.selectedTimelineMessage?.message.pinned, true)

        model.perform(.reactToSelectedMessage("✅"))
        try await Task.sleep(for: .milliseconds(30))
        let reactionCount = await handler.addedReactions.count
        XCTAssertEqual(reactionCount, 1)
        XCTAssertEqual(model.selectedTimelineMessage?.message.reactions["✅"], [MockShellData.currentUserID])

        model.jumpToNewestMessage()
        XCTAssertEqual(model.timelineSelection.messageID, model.selectedTimelineMessages.last?.message.id)
    }

    @MainActor
    func testPhase9LocalUnreadStatePreservesMentionAndJumpsFirstUnread() throws {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot)
        let channel = try XCTUnwrap(model.snapshot.channelsByID.values.first { $0.displayName == "macos-native" })

        model.selectChannel(channel.id)

        XCTAssertEqual(model.localReadStates[channel.id]?.unreadCount, 0)
        XCTAssertEqual(model.localReadStates[channel.id]?.mentionCount, 1)
        XCTAssertNotNil(model.firstUnreadMessageID(for: channel.id))
        model.perform(.jumpToFirstUnreadMessage)
        XCTAssertEqual(model.timelineSelection.messageID, model.firstUnreadMessageID(for: channel.id))
    }

    func testPhase10ViewportReducerCreatesDeterministicScrollIntents() {
        let channelID: ChannelID = "channel"
        let first = TimelineMessage(message: message(id: ulid(milliseconds: 1_000), author: "user", channel: channelID))
        let second = TimelineMessage(message: message(id: ulid(milliseconds: 2_000), author: "user", channel: channelID))
        let reducer = TimelineViewportReducer()

        var state = reducer.channelSelected(channelID: channelID, messages: [first, second], firstUnreadMessageID: first.message.id)
        XCTAssertEqual(state.pendingScrollIntent, .message(first.message.id, anchor: .bottom, reason: .channelSelected))

        state = reducer.jumpNewest(state, newestMessageID: second.message.id)
        XCTAssertEqual(state.pendingScrollIntent, .newest(reason: .jumpCommand))
        XCTAssertTrue(state.isAtNewest)

        state.isAtNewest = false
        state = reducer.newMessage(state, newestMessageID: "new-message", isActiveChannel: true)
        XCTAssertNil(state.pendingScrollIntent == .message("new-message", anchor: .bottom, reason: .newMessage) ? state.pendingScrollIntent : nil)
        XCTAssertTrue(state.hasNewerMessagesIndicator)

        state = reducer.preserveAfterPrepend(state, previousOldestID: first.message.id)
        XCTAssertEqual(state.pendingScrollIntent, .preservePositionAfterPrepend(previousOldestID: first.message.id))
    }

    @MainActor
    func testPhase10ReplyContextComposerAndSendPayload() async throws {
        let handler = MockMessageActionHandler()
        let model = MainShellViewModel(snapshot: MockShellData.snapshot, messageActionHandler: handler)
        model.selectServer(model.servers[0].id)
        let channelID = try XCTUnwrap(model.selection.channelID)
        let target = try XCTUnwrap(model.selectedTimelineMessages.first { $0.status == .confirmed })

        model.beginReply(to: target)
        XCTAssertEqual(model.replyContext(for: channelID)?.messageID, target.message.id)
        XCTAssertEqual(model.timelineSelection.focus.mode, .replying)
        XCTAssertTrue(model.composerDraftState(for: channelID).shouldMentionReplyAuthor)

        model.updateReplyMentionPreference(false, for: channelID)
        model.updateDraft("reply body", for: channelID)
        await model.sendDraft(for: channelID)

        let sent = await handler.sentMessages
        XCTAssertEqual(sent.last?.replies, [target.message.id])
        XCTAssertNil(model.replyContext(for: channelID))
    }

    @MainActor
    func testPhase10CancelReplyPreservesDraftAndCommandsGateWhileTyping() throws {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot)
        model.selectServer(model.servers[0].id)
        let channelID = try XCTUnwrap(model.selection.channelID)
        let target = try XCTUnwrap(model.selectedTimelineMessages.first { $0.status == .confirmed })

        model.updateDraft("keep me", for: channelID)
        model.beginReply(to: target)
        XCTAssertTrue(model.canPerform(.cancelReply))
        model.cancelReply(for: channelID)

        XCTAssertEqual(model.draft(for: channelID), "keep me")
        XCTAssertNil(model.replyContext(for: channelID))
        model.timelineSelection = TimelineSelection(channelID: channelID, messageID: target.message.id)
        model.focusComposer()
        XCTAssertFalse(model.canPerform(.replyToSelectedMessage))
    }

    @MainActor
    func testPhase10LiveAckDebouncesAndClearsMentionAfterSuccess() async throws {
        let channelID = try XCTUnwrap(MockShellData.snapshot.channelsByID.values.first { $0.displayName == "macos-native" }?.id)
        let sender = RecordingChannelAckSender()
        let model = MainShellViewModel(
            snapshot: MockShellData.snapshot,
            runtimeMode: .liveManual,
            sessionState: .connected,
            channelAckSender: sender
        )

        model.selectChannel(channelID)
        model.updateTimelineAtNewest(true)
        try await Task.sleep(for: .milliseconds(1700))

        let acks = await sender.acks
        XCTAssertEqual(acks.last?.0, channelID)
        XCTAssertEqual(acks.last?.1, model.selectedTimelineMessages.last?.message.id)
        XCTAssertEqual(model.localReadStates[channelID]?.mentionCount, 0)
    }

    @MainActor
    func testPhase10MissingFirstUnreadIsRecoverableStatus() throws {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot)
        let channel = try XCTUnwrap(model.snapshot.channelsByID.values.first { $0.displayName == "macos-native" })
        model.selectChannel(channel.id)
        model.localReadStates[channel.id] = LocalReadState(channelID: channel.id, firstUnreadMessageID: "missing", unreadCount: 1, mentionCount: 1)

        model.jumpToFirstUnreadMessage()

        XCTAssertEqual(model.placeholderStatus, "Unread message is not loaded.")
    }

    func testPhase11VisibleRangeDrivesAtNewestDeterministically() {
        let channelID: ChannelID = "channel"
        let messages = [
            TimelineMessage(message: message(id: ulid(milliseconds: 1_000), author: "a", channel: channelID)),
            TimelineMessage(message: message(id: ulid(milliseconds: 2_000), author: "a", channel: channelID)),
            TimelineMessage(message: message(id: ulid(milliseconds: 3_000), author: "a", channel: channelID)),
            TimelineMessage(message: message(id: ulid(milliseconds: 4_000), author: "a", channel: channelID)),
            TimelineMessage(message: message(id: ulid(milliseconds: 5_000), author: "a", channel: channelID))
        ]
        let reducer = TimelineViewportReducer()
        var state = reducer.channelSelected(channelID: channelID, messages: messages, firstUnreadMessageID: nil)

        state = reducer.visibleRangeChanged(
            state,
            channelID: channelID,
            visibleMessageIDs: [messages[0].message.id, messages[1].message.id],
            loadedMessageIDs: messages.map(\.message.id)
        )
        XCTAssertEqual(state.visibleRange?.firstVisibleMessageID, messages[0].message.id)
        XCTAssertEqual(state.visibleRange?.lastVisibleMessageID, messages[1].message.id)
        XCTAssertFalse(state.isAtNewest)

        let unchanged = reducer.visibleRangeChanged(
            state,
            channelID: channelID,
            visibleMessageIDs: [messages[1].message.id, messages[0].message.id],
            loadedMessageIDs: messages.map(\.message.id)
        )
        XCTAssertEqual(unchanged.visibleRange, state.visibleRange)

        state = reducer.visibleRangeChanged(
            state,
            channelID: channelID,
            visibleMessageIDs: [messages[2].message.id],
            loadedMessageIDs: messages.map(\.message.id)
        )
        XCTAssertTrue(state.isAtNewest)
    }

    func testPhase11HistoryTracksBoundariesAndUnreadRecovery() {
        let channelID: ChannelID = "channel"
        let reducer = ChannelMessageHistoryReducer(messageCapPerChannel: 10)
        let messages = [
            message(id: ulid(milliseconds: 1_000), author: "a", channel: channelID),
            message(id: ulid(milliseconds: 2_000), author: "a", channel: channelID)
        ]

        var history = reducer.reduce(
            ChannelMessageHistory(channelID: channelID),
            event: .initialLoadSucceeded(messages: messages, hasMoreBefore: true, loadedAt: Date())
        )

        XCTAssertEqual(history.loadedRange.oldestLoadedMessageID, messages.first?.id)
        XCTAssertEqual(history.loadedRange.newestLoadedMessageID, messages.last?.id)
        XCTAssertTrue(history.loadedRange.hasMoreBefore)

        history = reducer.reduce(history, event: .unreadMarkerMoved("missing"))
        XCTAssertEqual(history.firstUnreadMessageID, "missing")
        XCTAssertEqual(history.unreadRecoveryState, .targetUnloaded("missing"))

        history = reducer.reduce(history, event: .olderLoadFailed("Could not load older messages"))
        XCTAssertEqual(history.loadedRange.lastPaginationError, "Could not load older messages")
    }

    @MainActor
    func testPhase11FailedSendPreservesRetryMetadataAndPreventsDoubleRetry() async throws {
        let handler = MockMessageActionHandler(sendError: MessageActionError.unavailable("offline"))
        let model = MainShellViewModel(snapshot: MockShellData.snapshot, messageActionHandler: handler)
        model.selectServer(model.servers[0].id)
        let channelID = try XCTUnwrap(model.selection.channelID)
        let target = try XCTUnwrap(model.selectedTimelineMessages.first)

        model.beginReply(to: target)
        model.updateReplyMentionPreference(false, for: channelID)
        model.updateDraft("retry me", for: channelID)
        await model.sendDraft(for: channelID)

        let failed = try XCTUnwrap(model.selectedTimelineMessages.first { $0.status.failedMetadata != nil })
        let metadata = try XCTUnwrap(failed.status.failedMetadata)
        XCTAssertEqual(metadata.originalContent, "retry me")
        XCTAssertEqual(metadata.replyContext?.messageID, target.message.id)
        XCTAssertFalse(metadata.mentionReply)
        XCTAssertEqual(metadata.attemptCount, 1)

        async let first: Bool = model.messageController.retrySend(failed, handler: handler)
        async let second: Bool = model.messageController.retrySend(failed, handler: handler)
        let results = await [first, second]
        XCTAssertEqual(results.filter { $0 }.count, 0)
        let retried = try XCTUnwrap(model.selectedTimelineMessages.first { $0.message.id == failed.message.id })
        XCTAssertEqual(retried.status.failedMetadata?.attemptCount, 2)
    }

    @MainActor
    func testPhase11ReferenceResolverCachesVisibleReplyFallbacks() async throws {
        let channelID: ChannelID = "channel"
        let original = message(id: ulid(milliseconds: 1_000), author: "a", channel: channelID)
        let reply = message(id: ulid(milliseconds: 2_000), author: "b", channel: channelID, replies: [original.id])
        let channel = Channel(id: channelID, kind: .textChannel, name: "general")
        let snapshot = RealtimeSnapshot(
            usersByID: [:],
            channelsByID: [channelID: channel],
            messagesByChannelID: [channelID: [reply]]
        )
        let resolver = InMemoryMessageReferenceResolver(messagesByChannelID: [channelID: [original]])
        let model = MainShellViewModel(
            selection: ShellSelection(space: .server("server"), serverID: "server", channelID: channelID),
            snapshot: snapshot,
            messageReferenceResolver: resolver
        )

        XCTAssertEqual(model.resolvedReplyPreview(for: reply), "Loading original message...")
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(model.resolvedReplyPreview(for: reply), "a: hello")

        let diagnostics = model.timelineDiagnostics()
        XCTAssertEqual(diagnostics.pendingReferenceFetchCount, 0)
    }

    @MainActor
    func testPhase11TimelineDiagnosticsStayTokenFree() throws {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot)
        model.selectServer(model.servers[0].id)
        let channelID = try XCTUnwrap(model.selection.channelID)
        let first = try XCTUnwrap(model.selectedTimelineMessages.first?.message.id)
        let last = try XCTUnwrap(model.selectedTimelineMessages.last?.message.id)

        model.updateTimelineVisibility(messageID: first, channelID: channelID, isVisible: true)
        model.updateTimelineVisibility(messageID: last, channelID: channelID, isVisible: true)

        let diagnostics = model.timelineDiagnostics()
        XCTAssertEqual(diagnostics.channelID, channelID)
        XCTAssertEqual(diagnostics.loadedMessageCount, model.selectedTimelineMessages.count)
        XCTAssertEqual(diagnostics.firstVisibleMessageID, first)
        XCTAssertEqual(diagnostics.lastVisibleMessageID, last)
        XCTAssertFalse(String(describing: diagnostics).localizedCaseInsensitiveContains("token="))
    }

    @MainActor
    func testPhase12TuningValidationAndAtNewestThreshold() throws {
        let tuning = TimelineTuningConfiguration(
            nearNewestMessageThreshold: -3,
            visibleRangeUpdateDebounceMilliseconds: -1,
            loadToUnreadMaxAttempts: 99,
            referenceFetchMaxAttempts: 12,
            referenceFetchCooldownSeconds: -1,
            ackDebounceMilliseconds: 99_999
        ).validated()

        XCTAssertEqual(tuning.nearNewestMessageThreshold, 0)
        XCTAssertEqual(tuning.visibleRangeUpdateDebounceMilliseconds, 0)
        XCTAssertEqual(tuning.loadToUnreadMaxAttempts, 20)
        XCTAssertEqual(tuning.referenceFetchMaxAttempts, 5)
        XCTAssertEqual(tuning.referenceFetchCooldownSeconds, 0)
        XCTAssertEqual(tuning.ackDebounceMilliseconds, 10_000)

        let ids: [MessageID] = ["1", "2", "3", "4"]
        XCTAssertFalse(TimelineViewportReducer.isNewestVisibleOrNearVisible(visibleMessageIDs: ["2"], loadedMessageIDs: ids, trailingThreshold: 0))
        XCTAssertTrue(TimelineViewportReducer.isNewestVisibleOrNearVisible(visibleMessageIDs: ["2"], loadedMessageIDs: ids, trailingThreshold: 2))
    }

    @MainActor
    func testPhase12VisibleRangeValidationWarnings() throws {
        let channelID: ChannelID = "channel"
        let loaded: [MessageID] = ["1", "2", "3"]
        let validator = TimelineVisibleRangeValidator()

        let valid = validator.warnings(
            channelID: channelID,
            loadedMessageIDs: loaded,
            visibleRange: TimelineVisibleRange(channelID: channelID, firstVisibleMessageID: "2", lastVisibleMessageID: "3", visibleMessageIDs: ["2", "3"]),
            atNewest: true,
            nearNewestMessageThreshold: 0
        )
        XCTAssertTrue(valid.isEmpty)

        let warnings = validator.warnings(
            channelID: channelID,
            loadedMessageIDs: loaded,
            visibleRange: TimelineVisibleRange(channelID: "other", firstVisibleMessageID: "2", lastVisibleMessageID: "1", visibleMessageIDs: ["2", "missing", "1"]),
            atNewest: true,
            nearNewestMessageThreshold: 0
        )
        XCTAssertTrue(warnings.contains { $0.message.contains("channel") })
        XCTAssertTrue(warnings.contains { $0.message.contains("not loaded") })
        XCTAssertTrue(warnings.contains { $0.message.contains("First visible") })
        XCTAssertTrue(warnings.contains { $0.message.contains("at newest") })
    }

    @MainActor
    func testPhase12FindInLoadedMessagesIsLocalAndCreatesJumpIntent() throws {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot)
        model.selectServer(model.servers[0].id)
        let channelID = try XCTUnwrap(model.selection.channelID)
        let message = message(id: "01J00000000000000000000001", author: "a", channel: channelID)
        let finder = LoadedMessageFinder()
        var searchable = message
        searchable.content = "Phase 12 find in loaded messages"
        let found = finder.find(query: "Phase 12", messages: [TimelineMessage(message: searchable)])
        let result = try XCTUnwrap(found.first)
        model.jumpToLoadedFindResult(result)

        XCTAssertEqual(model.timelineViewport.selectedMessageID, result.messageID)
        XCTAssertNotNil(model.timelineViewport.pendingScrollIntent)
    }

    @MainActor
    func testPhase12DiagnosticsCopyRedactsTokenLikeStrings() throws {
        let diagnostics = TimelineDiagnostics(
            lastAckResult: "token=secret-token-value",
            lastTimelineActionResult: "X-Session-Token: abcdefghijklmnopqrstuvwxyz"
        )

        let copied = TimelineCopyFormatter.diagnostics(diagnostics)
        XCTAssertFalse(copied.contains("secret-token-value"))
        XCTAssertFalse(copied.contains("abcdefghijklmnopqrstuvwxyz"))
        XCTAssertTrue(copied.contains("<redacted>"))
    }

    private func message(
        id: String,
        author: UserID,
        channel: ChannelID,
        system: SystemMessage? = nil,
        edited: Bool = false,
        replies: [MessageID]? = nil
    ) -> Message {
        Message(
            id: MessageID(rawValue: id),
            channelID: channel,
            authorID: author,
            content: system == nil ? "hello" : nil,
            system: system,
            editedAt: edited ? Date() : nil,
            replies: replies
        )
    }

    private func ulid(milliseconds: UInt64) -> String {
        let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
        var value = milliseconds
        var chars = Array(repeating: alphabet[0], count: 10)
        for index in stride(from: 9, through: 0, by: -1) {
            chars[index] = alphabet[Int(value % 32)]
            value /= 32
        }
        return String(chars) + "0000000000000000"
    }
}

private final class TestStreamHub<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]

    func stream() -> AsyncStream<Element> {
        AsyncStream { continuation in
            let id = UUID()
            lock.lock()
            continuations[id] = continuation
            lock.unlock()
            continuation.onTermination = { [weak self] _ in
                self?.lock.lock()
                self?.continuations.removeValue(forKey: id)
                self?.lock.unlock()
            }
        }
    }

    func yield(_ value: Element) {
        lock.lock()
        let continuations = Array(continuations.values)
        lock.unlock()
        continuations.forEach { $0.yield(value) }
    }
}

private final class MutableSnapshotSource: ShellSnapshotSource, @unchecked Sendable {
    private let lock = NSLock()
    private let hub = TestStreamHub<RealtimeSnapshot>()
    private var snapshot: RealtimeSnapshot

    init(snapshot: RealtimeSnapshot) {
        self.snapshot = snapshot
    }

    var snapshots: AsyncStream<RealtimeSnapshot> {
        hub.stream()
    }

    func currentSnapshot() async -> RealtimeSnapshot {
        lock.withLock { snapshot }
    }

    func yield(_ snapshot: RealtimeSnapshot) {
        lock.withLock {
            self.snapshot = snapshot
        }
        hub.yield(snapshot)
    }
}

private actor RecordingRealtimeClient: StoatRealtimeClient {
    nonisolated var connectionState: AsyncStream<RealtimeConnectionState> { stateHub.stream() }
    nonisolated var events: AsyncStream<StoatGatewayEvent> { eventHub.stream() }
    nonisolated var diagnosticsStream: AsyncStream<RealtimeDiagnostics> { diagnosticsHub.stream() }

    private let stateHub = TestStreamHub<RealtimeConnectionState>()
    private let eventHub = TestStreamHub<StoatGatewayEvent>()
    private let diagnosticsHub = TestStreamHub<RealtimeDiagnostics>()
    private let statesOnConnect: [RealtimeConnectionState]
    private let eventsOnConnect: [StoatGatewayEvent]

    private(set) var connectCallCount = 0
    private(set) var disconnectCallCount = 0
    private(set) var sentEvents: [ClientGatewayEvent] = []
    private(set) var connectedEnvironments: [StoatAPIEnvironment] = []
    private(set) var connectedCredentials: [StoatAuthCredential] = []

    init(statesOnConnect: [RealtimeConnectionState] = [], eventsOnConnect: [StoatGatewayEvent] = []) {
        self.statesOnConnect = statesOnConnect
        self.eventsOnConnect = eventsOnConnect
    }

    func connect(credential: StoatAuthCredential, environment: StoatAPIEnvironment, readyFields: Set<ReadyField>) async throws {
        connectCallCount += 1
        connectedEnvironments.append(environment)
        connectedCredentials.append(credential)
        for state in statesOnConnect {
            stateHub.yield(state)
        }
        for event in eventsOnConnect {
            eventHub.yield(event)
        }
    }

    func disconnect() async {
        disconnectCallCount += 1
        stateHub.yield(.disconnected(reason: .requested))
    }

    func send(_ event: ClientGatewayEvent) async throws {
        sentEvents.append(event)
    }
}

private actor RecordingAPIClient: StoatAPIClient {
    private(set) var fetchMessagesCallCount = 0
    private(set) var sentDrafts: [(ChannelID, MessageDraft)] = []
    private(set) var editedMessages: [(ChannelID, MessageID, MessageEditDraft)] = []
    private(set) var deletedMessages: [(ChannelID, MessageID)] = []
    private(set) var addedReactions: [(ChannelID, MessageID, String)] = []
    private(set) var removedReactions: [(ChannelID, MessageID, String)] = []

    private let currentUser: User
    private var messagesByChannel: [ChannelID: [Message]]
    private let fetchError: (any Error & Sendable)?

    init(
        currentUser: User = User(id: MockShellData.currentUserID, username: "liquidbagel"),
        messagesByChannel: [ChannelID: [Message]] = [:],
        fetchError: (any Error & Sendable)? = nil
    ) {
        self.currentUser = currentUser
        self.messagesByChannel = messagesByChannel
        self.fetchError = fetchError
    }

    func fetchRootConfiguration() async throws -> StoatConfig {
        throw StoatAPIError.unimplementedEndpoint("test")
    }

    func fetchCurrentUser() async throws -> User {
        currentUser
    }

    func fetchServers() async throws -> [Server] {
        []
    }

    func fetchChannels() async throws -> [Channel] {
        []
    }

    func fetchChannel(id: ChannelID) async throws -> Channel {
        throw StoatAPIError.notFound
    }

    func fetchMessages(channelID: ChannelID, before: MessageID?, after: MessageID?, limit: Int?) async throws -> [Message] {
        fetchMessagesCallCount += 1
        if let fetchError {
            throw fetchError
        }
        var messages = messagesByChannel[channelID] ?? []
        messages.sort { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
        if let before, let index = messages.firstIndex(where: { $0.id == before }) {
            messages = Array(messages[..<index])
        }
        if let after, let index = messages.firstIndex(where: { $0.id == after }) {
            messages = Array(messages[messages.index(after: index)...])
        }
        if let limit, messages.count > limit {
            messages = Array(messages.prefix(limit))
        }
        return messages
    }

    func sendMessage(channelID: ChannelID, draft: MessageDraft) async throws -> Message {
        sentDrafts.append((channelID, draft))
        let message = Message(id: "01J00000100000000000000001", channelID: channelID, authorID: currentUser.id, content: draft.content, nonce: draft.nonce)
        messagesByChannel[channelID, default: []].append(message)
        return message
    }

    func editMessage(channelID: ChannelID, messageID: MessageID, draft: MessageEditDraft) async throws -> Message {
        editedMessages.append((channelID, messageID, draft))
        return Message(id: messageID, channelID: channelID, authorID: currentUser.id, content: draft.content, editedAt: Date())
    }

    func deleteMessage(channelID: ChannelID, messageID: MessageID) async throws {
        deletedMessages.append((channelID, messageID))
    }

    func addReaction(channelID: ChannelID, messageID: MessageID, emoji: String) async throws {
        addedReactions.append((channelID, messageID, emoji))
    }

    func removeReaction(channelID: ChannelID, messageID: MessageID, emoji: String, removeAll: Bool) async throws {
        removedReactions.append((channelID, messageID, emoji))
    }

    func pinMessage(channelID: ChannelID, messageID: MessageID) async throws {}

    func unpinMessage(channelID: ChannelID, messageID: MessageID) async throws {}

    func uploadFile(data: Data, filename: String, mimeType: String, tag: UploadTag) async throws -> UploadedFile {
        UploadedFile(id: "file")
    }
}

private struct StubSessionValidator: SessionValidating {
    var user: User
    var error: (any Error & Sendable)?

    init(
        user: User = User(id: MockShellData.currentUserID, username: "liquidbagel"),
        error: (any Error & Sendable)? = nil
    ) {
        self.user = user
        self.error = error
    }

    func validate(credential: StoatAuthCredential, environment: StoatAPIEnvironment) async throws -> ValidatedSession {
        if let error {
            throw error
        }
        return ValidatedSession(credential: credential, currentUser: user, environment: environment)
    }
}
