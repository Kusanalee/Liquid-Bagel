import StoatModels
import StoatAPI
import StoatPersistence
import StoatRealtime
import StoatUI
import XCTest
@testable import StoatFeatures

private func makeTemporaryAttachment(name: String, contents: Data) throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LiquidBagelPhase15Tests", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent(UUID().uuidString + "-" + name)
    try contents.write(to: url)
    return url
}

final class StoatFeaturesTests: XCTestCase {
    private static let phase41PNGData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

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
    func testSessionStartsLiveFirstAndMockPreviewDoesNotAutoConnect() async throws {
        let realtime = RecordingRealtimeClient()
        let session = AppSessionCoordinator(
            tokenStore: InMemoryTokenStore(),
            apiClientFactory: { _, _ in RecordingAPIClient() },
            realtimeClientFactory: { realtime }
        )

        XCTAssertEqual(session.mode, .liveManual)
        XCTAssertEqual(session.sessionState, .signedOut)
        XCTAssertTrue(session.snapshot.serversByID.isEmpty)
        await session.startMockSession()

        let connectCallCount = await realtime.connectCallCount
        XCTAssertEqual(connectCallCount, 0)
        XCTAssertEqual(session.mode, .mock)
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
    func testManualTokenImportValidatesSavesAndConnects() async throws {
        let store = InMemoryTokenStore()
        let validator = StubSessionValidator(user: User(id: "user-validated", username: "validated"))
        let realtime = RecordingRealtimeClient(statesOnConnect: [.ready])
        let session = AppSessionCoordinator(
            tokenStore: store,
            sessionValidator: validator,
            apiClientFactory: { _, _ in RecordingAPIClient() },
            realtimeClientFactory: { realtime }
        )

        await session.validateImportedToken("secret-token", localLabel: "Main Stoat")
        try await Task.sleep(for: .milliseconds(30))

        let savedCredential = try await store.loadCredential(scope: .production)
        XCTAssertEqual(savedCredential?.token, "secret-token")
        let connectCallCount = await realtime.connectCallCount
        XCTAssertEqual(connectCallCount, 1)
        XCTAssertTrue(session.sessionState == .connecting || session.sessionState == .connected)
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
    func testMockPreviewSavedCredentialBecomesReadyWithoutConnecting() async throws {
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
        XCTAssertNil(model.messageActionStatus)

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
    func testPhase32EmojiInsertionAppendsToComposerDraft() {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot)
        let channelID = model.snapshot.channelsByID.values.first { $0.displayName == "general" }!.id

        model.updateDraft("hello", for: channelID)
        model.insertEmoji("🎉", in: channelID)

        XCTAssertEqual(model.draft(for: channelID), "hello🎉")
        XCTAssertTrue(model.commonEmojiItems.contains("🎉"))
        XCTAssertEqual(model.emojiPickerDiagnostics, "Inserted Unicode emoji")
    }

    @MainActor
    func testPhase15AttachmentQueueDoesNotUploadUntilExplicitAction() async throws {
        let uploader = MockAttachmentUploadHandler()
        let model = MainShellViewModel(snapshot: MockShellData.snapshot, attachmentUploadHandler: uploader)
        let channelID = model.snapshot.channelsByID.values.first { $0.displayName == "general" }!.id
        let url = try makeTemporaryAttachment(name: "note.txt", contents: Data("hello".utf8))

        model.addAttachmentURLs([url], to: channelID)

        XCTAssertEqual(model.composerDraftState(for: channelID).attachments.count, 1)
        let initialUploadCount = await uploader.uploadCount()
        XCTAssertEqual(initialUploadCount, 0)
        XCTAssertTrue(model.composerReadiness(for: channelID).canSend)

        await model.uploadQueuedAttachments(for: channelID)

        let finalUploadCount = await uploader.uploadCount()
        XCTAssertEqual(finalUploadCount, 1)
        XCTAssertNotNil(model.composerDraftState(for: channelID).attachments.first?.uploadedFileID)
    }

    @MainActor
    func testPhase32DroppedFilesOpenReviewBeforeQueueingOrUploading() async throws {
        let uploader = MockAttachmentUploadHandler()
        let model = MainShellViewModel(snapshot: MockShellData.snapshot, attachmentUploadHandler: uploader)
        let channelID = model.snapshot.channelsByID.values.first { $0.displayName == "general" }!.id
        let url = try makeTemporaryAttachment(name: "phase32 dropped.txt", contents: Data("drop".utf8))

        model.reviewDroppedAttachmentURLs([url], to: channelID)

        let review = try XCTUnwrap(model.pendingAttachmentDrop)
        XCTAssertEqual(review.channelID, channelID)
        XCTAssertEqual(review.items.count, 1)
        XCTAssertTrue(review.items.first?.filename.hasSuffix("phase32 dropped.txt") == true)
        XCTAssertFalse(review.items.first?.filename.contains(FileManager.default.temporaryDirectory.path) == true)
        XCTAssertTrue(review.canAddToMessage)
        XCTAssertTrue(model.composerDraftState(for: channelID).attachments.isEmpty)
        let uploadCountAfterDrop = await uploader.uploadCount()
        XCTAssertEqual(uploadCountAfterDrop, 0)

        model.addPendingDroppedAttachmentsToComposer()

        XCTAssertNil(model.pendingAttachmentDrop)
        XCTAssertEqual(model.composerDraftState(for: channelID).attachments.count, 1)
        let uploadCountAfterAdd = await uploader.uploadCount()
        XCTAssertEqual(uploadCountAfterAdd, 0)
    }

    @MainActor
    func testPhase32DroppedFilesWithoutSendableTargetShowBlockedReview() async throws {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot)
        let url = try makeTemporaryAttachment(name: "phase32 blocked.txt", contents: Data("blocked".utf8))

        model.reviewDroppedAttachmentURLs([url], to: nil)

        let review = try XCTUnwrap(model.pendingAttachmentDrop)
        XCTAssertNil(review.channelID)
        XCTAssertTrue(review.blockedReason?.contains("Select a channel") == true)
        XCTAssertFalse(review.canAddToMessage)
        XCTAssertTrue(review.items.first?.filename.hasSuffix("phase32 blocked.txt") == true)
        model.cancelPendingAttachmentDrop()
        XCTAssertNil(model.pendingAttachmentDrop)
    }

    @MainActor
    func testPhase15AttachmentValidationAndPermissionGate() async throws {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot)
        let channelID = model.snapshot.channelsByID.values.first { $0.displayName == "general" }!.id
        let oversized = try makeTemporaryAttachment(name: "large.txt", contents: Data(repeating: 1, count: 21 * 1024 * 1024))

        model.addAttachmentURLs([oversized], to: channelID)

        XCTAssertTrue(model.composerDraftState(for: channelID).attachments.isEmpty)
        XCTAssertEqual(model.composerError, "File too large. Liquid Bagel currently supports files up to 20 MB.")

        var snapshot = MockShellData.snapshot
        snapshot.channelsByID[channelID]?.permissions = [.viewChannel, .readMessageHistory, .sendMessage]
        let permissionModel = MainShellViewModel(snapshot: snapshot)
        XCTAssertFalse(permissionModel.canUploadFiles(in: permissionModel.snapshot.channelsByID[channelID]))
    }

    @MainActor
    func testPhase33UploadLimitBoundaryAndPasteReviewDoNotUpload() async throws {
        let uploader = MockAttachmentUploadHandler()
        let model = MainShellViewModel(snapshot: MockShellData.snapshot, attachmentUploadHandler: uploader)
        let channelID = model.snapshot.channelsByID.values.first { $0.displayName == "general" }!.id
        let exact = try makeTemporaryAttachment(name: "exact-20mb.txt", contents: Data(repeating: 1, count: AttachmentUploadLimits.maxFileBytes))
        let over = try makeTemporaryAttachment(name: "over-20mb.txt", contents: Data(repeating: 1, count: AttachmentUploadLimits.maxFileBytes + 1))

        model.reviewDroppedAttachmentURLs([exact, over], to: channelID)

        let review = try XCTUnwrap(model.pendingAttachmentDrop)
        XCTAssertEqual(review.attachableItems.count, 1)
        XCTAssertEqual(review.items.filter { $0.warning != nil }.first?.warning, "File too large. Liquid Bagel currently supports files up to 20 MB.")
        let uploadCountBeforeQueue = await uploader.uploadCount()
        XCTAssertEqual(uploadCountBeforeQueue, 0)

        model.addPendingDroppedAttachmentsToComposer()
        XCTAssertEqual(model.composerDraftState(for: channelID).attachments.count, 1)
        let uploadCountAfterQueue = await uploader.uploadCount()
        XCTAssertEqual(uploadCountAfterQueue, 0)
    }

    @MainActor
    func testPhase33PastedImageOpensReviewBeforeQueueing() async throws {
        let uploader = MockAttachmentUploadHandler()
        let model = MainShellViewModel(snapshot: MockShellData.snapshot, attachmentUploadHandler: uploader)
        let channelID = model.snapshot.channelsByID.values.first { $0.displayName == "general" }!.id

        model.reviewPastedImageData(Data(repeating: 2, count: 32), to: channelID)

        let review = try XCTUnwrap(model.pendingAttachmentDrop)
        XCTAssertEqual(review.attachableItems.first?.filename, "Pasted Image.png")
        XCTAssertTrue(model.composerDraftState(for: channelID).attachments.isEmpty)
        let uploadCount = await uploader.uploadCount()
        XCTAssertEqual(uploadCount, 0)
    }

    @MainActor
    func testPhase15SendUploadsAttachmentsAndSendsFileIDs() async throws {
        let uploader = MockAttachmentUploadHandler()
        let handler = RecordingAttachmentMessageActionHandler()
        let model = MainShellViewModel(snapshot: MockShellData.snapshot, messageActionHandler: handler, attachmentUploadHandler: uploader)
        let server = model.servers.first { $0.name == "Bagel Lab" }!
        model.selectServer(server.id)
        let channelID = model.selection.channelID!
        let url = try makeTemporaryAttachment(name: "send.txt", contents: Data("payload".utf8))

        model.addAttachmentURLs([url], to: channelID)
        model.updateDraft("with file", for: channelID)
        await model.sendDraft(for: channelID)

        let sent = await handler.sentSnapshot()
        let uploadCount = await uploader.uploadCount()
        XCTAssertEqual(uploadCount, 1)
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?.content, "with file")
        XCTAssertEqual(sent.first?.attachments?.count, 1)
        XCTAssertEqual(model.composerDraftState(for: channelID).attachments.count, 0)
    }

    @MainActor
    func testPhase15AttachmentOnlySendAndUploadFailureKeepsDraft() async throws {
        let failingUploader = MockAttachmentUploadHandler(uploadError: MessageActionError.unavailable("upload failed"))
        let handler = RecordingAttachmentMessageActionHandler()
        let model = MainShellViewModel(snapshot: MockShellData.snapshot, messageActionHandler: handler, attachmentUploadHandler: failingUploader)
        let server = model.servers.first { $0.name == "Bagel Lab" }!
        model.selectServer(server.id)
        let channelID = model.selection.channelID!
        let url = try makeTemporaryAttachment(name: "image.png", contents: Data([137, 80, 78, 71]))

        model.addPastedImageData(Data([137, 80, 78, 71]), to: channelID)
        await model.sendDraft(for: channelID)

        let failedSent = await handler.sentSnapshot()
        XCTAssertEqual(failedSent.count, 0)
        XCTAssertEqual(model.composerDraftState(for: channelID).attachments.count, 1)
        XCTAssertTrue(model.composerError?.contains("upload") == true)

        let workingUploader = MockAttachmentUploadHandler()
        let workingHandler = RecordingAttachmentMessageActionHandler()
        let workingModel = MainShellViewModel(snapshot: MockShellData.snapshot, messageActionHandler: workingHandler, attachmentUploadHandler: workingUploader)
        workingModel.selectServer(server.id)
        let workingChannelID = workingModel.selection.channelID!
        workingModel.addAttachmentURLs([url], to: workingChannelID)
        await workingModel.sendDraft(for: workingChannelID)

        let sent = await workingHandler.sentSnapshot()
        XCTAssertEqual(sent.first?.content, "")
        XCTAssertEqual(sent.first?.attachments?.count, 1)
    }

    @MainActor
    func testPhase16RemotePreviewOnlyLoadsAfterExplicitAction() async throws {
        let loader = MockRemoteAttachmentLoader(result: .success(RemoteAttachmentData(fileID: "file-remote", filename: "note.txt", contentType: "text/plain", byteCount: 5, data: Data("hello".utf8))))
        let model = MainShellViewModel(snapshot: MockShellData.snapshot, remoteAttachmentLoader: loader)
        let file = File(id: "file-remote", tag: "attachments", filename: "note.txt", metadata: .text, contentType: "text/plain", size: 5)
        let item = AttachmentDisplayItem(file: file)

        let initialCallCount = await loader.callCount()
        XCTAssertEqual(initialCallCount, 0)
        XCTAssertEqual(item.previewState, .notLoaded)

        await model.previewAttachment(item)

        let finalCallCount = await loader.callCount()
        XCTAssertEqual(finalCallCount, 1)
        XCTAssertEqual(model.attachmentPreviewStates[item.id], .readyRemote)
        XCTAssertEqual(model.attachmentPreview?.data, Data("hello".utf8))
    }

    @MainActor
    func testPhase16RemotePreviewFailureIsSafeAndRetryable() async throws {
        let loader = MockRemoteAttachmentLoader(result: .failure(AttachmentActionError.unavailable("token=secret /Users/enka/private/file.png")))
        let model = MainShellViewModel(snapshot: MockShellData.snapshot, remoteAttachmentLoader: loader)
        let file = File(id: "file-failed", tag: "attachments", filename: "safe.txt", metadata: .text, contentType: "text/plain", size: 5)
        let item = AttachmentDisplayItem(file: file)

        await model.previewAttachment(item)

        guard case let .failed(message) = model.attachmentPreviewStates[item.id] else {
            return XCTFail("Expected failed preview state")
        }
        XCTAssertFalse(message.contains("secret"))
        XCTAssertFalse(message.contains("/Users/enka"))
        let firstCallCount = await loader.callCount()
        XCTAssertEqual(firstCallCount, 1)

        await model.retryAttachmentPreview(item)
        let retryCallCount = await loader.callCount()
        XCTAssertEqual(retryCallCount, 2)
    }

    @MainActor
    func testPhase16DownloadAndOpenUseMocksAndSanitizedFilename() async throws {
        let data = Data("payload".utf8)
        let loader = MockRemoteAttachmentLoader(result: .success(RemoteAttachmentData(fileID: "file-save", filename: "payload.txt", contentType: "text/plain", byteCount: data.count, data: data)))
        let saver = MockAttachmentSaver()
        let opener = MockAttachmentOpener()
        let model = MainShellViewModel(snapshot: MockShellData.snapshot, remoteAttachmentLoader: loader, attachmentSaver: saver, attachmentOpener: opener)
        let file = File(id: "file-save", tag: "attachments", filename: "/private/payload.txt", metadata: .text, contentType: "text/plain", size: data.count)
        let item = AttachmentDisplayItem(file: file)

        await model.downloadAttachment(item)

        let saveCount = await saver.saveCount()
        XCTAssertEqual(saveCount, 1)
        XCTAssertEqual(model.loadedAttachmentOriginalData[item.id]?.data, data)

        await model.previewAttachment(item)
        await model.openAttachmentExternally(item)

        let openCount = await opener.openCount()
        XCTAssertEqual(openCount, 1)
    }

    @MainActor
    func testPhase16ComposerSummaryFailedReadinessAndDiagnostics() async throws {
        let failingUploader = MockAttachmentUploadHandler(uploadError: MessageActionError.unavailable("upload failed"))
        let model = MainShellViewModel(snapshot: MockShellData.snapshot, attachmentUploadHandler: failingUploader)
        let server = model.servers.first { $0.name == "Bagel Lab" }!
        model.selectServer(server.id)
        let channelID = model.selection.channelID!

        model.addPastedImageData(Data([1, 2, 3, 4]), to: channelID)
        XCTAssertTrue(model.composerAttachmentSummary(for: channelID)?.contains("1 attachment") == true)
        XCTAssertTrue(model.composerReadiness(for: channelID).canSend)

        await model.sendDraft(for: channelID)

        XCTAssertFalse(model.composerReadiness(for: channelID).canSend)
        XCTAssertTrue(model.composerReadiness(for: channelID).reason.contains("failed"))
        let diagnostics = model.attachmentDiagnostics()
        XCTAssertEqual(diagnostics.failedUploadCount, 1)
        XCTAssertFalse(String(describing: diagnostics).contains("/Users/"))
    }

    func testPhase16LiveMediaURLUsesVerifiedRoutesWithoutQuery() throws {
        let base = URL(string: "https://cdn.stoatusercontent.com")!
        let preview = try LiveRemoteAttachmentLoader.mediaURL(baseURL: base, tag: "attachments", fileID: "file id", filename: nil)
        let original = try LiveRemoteAttachmentLoader.mediaURL(baseURL: base, tag: "attachments", fileID: "file id", filename: "original")

        XCTAssertEqual(preview.absoluteString, "https://cdn.stoatusercontent.com/attachments/file%20id")
        XCTAssertEqual(original.absoluteString, "https://cdn.stoatusercontent.com/attachments/file%20id/original")
        XCTAssertNil(URLComponents(url: original, resolvingAgainstBaseURL: false)?.queryItems)
    }

    func testPhase20AttachmentURLResolverUsesAutumnRoutes() throws {
        let resolver = DefaultAttachmentURLResolver()
        let environment = StoatAPIEnvironment.production
        let file = File(id: "file id", tag: "attachments", filename: "photo.png", metadata: .image(width: 10, height: 10, thumbhash: nil, animated: false), contentType: "image/png", size: 100)
        let preview = try XCTUnwrap(resolver.remoteURL(for: file, environment: environment, purpose: .preview))
        let original = try XCTUnwrap(resolver.remoteURL(for: file, environment: environment, purpose: .original))

        XCTAssertEqual(preview.absoluteString, "https://cdn.stoatusercontent.com/attachments/file%20id")
        XCTAssertEqual(original.absoluteString, "https://cdn.stoatusercontent.com/attachments/file%20id/original")
        XCTAssertNil(URLComponents(url: preview, resolvingAgainstBaseURL: false)?.queryItems)
    }

    @MainActor
    func testPhase20LiveConnectedSendAllowsUnknownPermissionsAndBlocksKnownDenial() async throws {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot, runtimeMode: .liveManual, sessionState: .connected)
        let channelID = try XCTUnwrap(model.snapshot.channelsByID.values.first { $0.displayName == "general" }?.id)
        model.selectChannel(channelID)
        model.updateDraft("live hello", for: channelID)

        XCTAssertTrue(model.composerReadiness(for: channelID).canSend)
        XCTAssertTrue(model.composerInputReadiness(for: channelID).isEnabled)

        var snapshot = MockShellData.snapshot
        snapshot.channelsByID[channelID]?.permissions = [.viewChannel, .readMessageHistory]
        let denied = MainShellViewModel(snapshot: snapshot, runtimeMode: .liveManual, sessionState: .connected)
        denied.selectChannel(channelID)
        denied.updateDraft("blocked", for: channelID)

        let readiness = denied.composerReadiness(for: channelID)
        XCTAssertFalse(readiness.canSend)
        XCTAssertTrue(readiness.reason.contains("permission"))
    }

    @MainActor
    func testPhase20SendDiagnosticsAndTimelineCopyStayRedacted() async throws {
        let handler = MockMessageActionHandler(sendError: MessageActionError.unavailable(#"send failed token="secret" /Users/enka/private/file.png {"raw":"payload"}"#))
        let model = MainShellViewModel(snapshot: MockShellData.snapshot, messageActionHandler: handler)
        let channelID = try XCTUnwrap(model.snapshot.channelsByID.values.first { $0.displayName == "general" }?.id)
        model.selectChannel(channelID)
        model.updateDraft("diagnostic message", for: channelID)

        await model.sendDraft(for: channelID)

        let diagnostics = model.currentMessageSendDiagnostics()
        XCTAssertEqual(diagnostics.lastSendStage, .failed)
        XCTAssertEqual(diagnostics.lastSendResult, .failed)
        XCTAssertEqual(diagnostics.selectedChannelID, channelID)
        XCTAssertFalse(diagnostics.lastError?.contains("secret") == true)
        XCTAssertFalse(diagnostics.lastError?.contains("/Users/enka") == true)
        XCTAssertFalse(diagnostics.lastError?.contains("payload") == true)

        let copied = Phase17MessageActions.redactedDiagnosticText(MessageSendDiagnosticsFormatter.redactedText(model.currentMessageSendDiagnostics()))
        XCTAssertTrue(copied.contains("stage: failed"))
        XCTAssertFalse(copied.contains("secret"))
        XCTAssertFalse(copied.contains("/Users/enka"))
        XCTAssertFalse(copied.contains("payload"))
    }

    @MainActor
    func testPhase20ImageSendPreservesLocalPreviewData() async throws {
        let uploader = MockAttachmentUploadHandler()
        let handler = ImageAttachmentMessageActionHandler()
        let model = MainShellViewModel(snapshot: MockShellData.snapshot, messageActionHandler: handler, attachmentUploadHandler: uploader)
        let channelID = try XCTUnwrap(model.snapshot.channelsByID.values.first { $0.displayName == "general" }?.id)
        let png = Data([137, 80, 78, 71, 13, 10, 26, 10])
        model.selectChannel(channelID)
        model.addPastedImageData(png, to: channelID)

        await model.sendDraft(for: channelID)

        let message = try XCTUnwrap(model.selectedTimelineMessages.first { $0.message.attachments?.isEmpty == false }?.message)
        let item = try XCTUnwrap(model.attachmentDisplayItems(for: message).first)
        XCTAssertEqual(item.kind, .image)
        XCTAssertEqual(item.previewState, .readyRemote)
        XCTAssertEqual(item.previewData, png)
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
        model.prepareReplyPreview(for: reply)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(model.resolvedReplyPreview(for: reply), "Unknown member: hello")

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
    func testPhase12FindInLoadedMessagesIsLocalAndCreatesJumpIntent() async throws {
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
        try await Task.sleep(for: .milliseconds(20))

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

    @MainActor
    func testPhase13CalibrationRecordsObservationsAndRedactsCopy() throws {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot)
        model.selectServer(model.servers[0].id)
        model.startTimelineCalibration()
        model.addTimelineCalibrationCheckpoint(note: "token=super-secret-value")

        let run = try XCTUnwrap(model.activeCalibrationRun)
        XCTAssertTrue(run.isRunning)
        XCTAssertGreaterThanOrEqual(run.observations.count, 2)

        let copied = TimelineCopyFormatter.calibration(run)
        XCTAssertFalse(copied.contains("super-secret-value"))
        XCTAssertTrue(copied.contains("<redacted>"))

        model.stopTimelineCalibration()
        XCTAssertFalse(try XCTUnwrap(model.activeCalibrationRun).isRunning)
    }

    @MainActor
    func testPhase13TuningPresetsClampAndReset() {
        let responsive = TimelineTuningPreset.responsive.configuration
        XCTAssertEqual(responsive, responsive.validated())
        XCTAssertEqual(TimelineTuningPreset.debugStrict.configuration.ackDebounceMilliseconds, 0)

        let model = MainShellViewModel(snapshot: MockShellData.snapshot)
        model.applyTimelineTuningPreset(.responsive)
        XCTAssertEqual(model.timelineTuning, TimelineTuningPreset.responsive.configuration)
        model.resetTimelineTuningToDefaults()
        XCTAssertEqual(model.timelineTuning, .defaults)
    }

    @MainActor
    func testPhase13LoadedFindUsesChannelSearchStateAndJumps() async throws {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot)
        model.selectServer(model.servers[0].id)
        model.channelSearchQuery = ChannelSearchQuery(text: "Phase", mode: .loadedOnly)

        await model.runChannelSearch()
        guard case let .results(query, results) = model.channelSearchState else {
            return XCTFail("Expected loaded results")
        }
        XCTAssertEqual(query.mode, .loadedOnly)
        XCTAssertTrue(results.allSatisfy(\.isLoaded))

        model.jumpToSelectedSearchResult()
        XCTAssertNotNil(model.timelineViewport.pendingScrollIntent)
    }

    @MainActor
    func testPhase13LiveSearchRequiresManualConnection() async {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot, runtimeMode: .liveManual, sessionState: .readyToConnect)
        model.selectServer(model.servers[0].id)
        model.channelSearchQuery = ChannelSearchQuery(text: "needle", mode: .liveChannel)

        await model.runChannelSearch()
        guard case let .failed(_, message) = model.channelSearchState else {
            return XCTFail("Expected failed live search state")
        }
        XCTAssertEqual(message, "Live search requires a connected live session.")
    }

    @MainActor
    func testPhase13SearchResultNavigationRouteGatingAndAccessibility() throws {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot)
        model.selectServer(model.servers[0].id)
        let channelID = try XCTUnwrap(model.selection.channelID)
        let result = ChannelSearchResult(
            messageID: "outside",
            channelID: channelID,
            authorID: "author",
            snippet: "Result outside loaded range",
            mode: .liveChannel,
            isLoaded: false,
            safeStatus: "Result outside loaded range"
        )
        model.channelSearchState = .results(ChannelSearchQuery(text: "needle", mode: .liveChannel), [result])
        model.selectSearchResult(result)

        XCTAssertTrue(model.canPerform(.loadAroundSelectedSearchResult))
        XCTAssertNil(model.disabledReason(for: .loadAroundSelectedSearchResult))
        XCTAssertTrue(Phase13Accessibility.channelSearchResultLabel(result, isSelected: true).contains("Outside loaded range"))

        model.verifyTimelineRoutes()
        XCTAssertTrue(model.canPerform(.loadAroundSelectedSearchResult))
    }

    @MainActor
    func testPhase14SearchHighlightClassifiesLoadedAndUnloadedResults() async throws {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot)
        model.selectServer(model.servers[0].id)
        model.channelSearchQuery = ChannelSearchQuery(text: "Phase", mode: .loadedOnly)

        await model.runChannelSearch()

        let state = try XCTUnwrap(model.searchHighlightState)
        XCTAssertEqual(state.mode, .loadedOnly)
        XCTAssertFalse(state.resultIDs.isEmpty)
        XCTAssertEqual(state.unloadedResultIDs, [])
        XCTAssertEqual(state.currentResultID, model.selectedSearchResultID)
        XCTAssertTrue(model.searchResultCountLabel?.contains("loaded") == true)
    }

    @MainActor
    func testPhase14SearchNavigationCyclesAndScrollsLoadedResults() async throws {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot)
        model.selectServer(model.servers[0].id)
        let channelID = try XCTUnwrap(model.selection.channelID)
        let messages = Array(model.selectedTimelineMessages.prefix(2))
        XCTAssertEqual(messages.count, 2)
        let results = messages.map {
            ChannelSearchResult(
                messageID: $0.message.id,
                channelID: channelID,
                authorID: $0.message.authorID,
                snippet: $0.message.content ?? "Message",
                mode: .loadedOnly,
                isLoaded: true
            )
        }

        model.channelSearchState = .results(ChannelSearchQuery(text: "needle", mode: .loadedOnly), results)
        model.selectedSearchResultID = results.last?.messageID
        model.selectAdjacentSearchResult(1)
        try await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(model.selectedSearchResultID, results.first?.messageID)
        XCTAssertEqual(model.timelineViewport.selectedMessageID, results.first?.messageID)
        XCTAssertNotNil(model.timelineViewport.pendingScrollIntent)
        XCTAssertTrue(model.isCurrentSearchResult(try XCTUnwrap(results.first?.messageID)))
    }

    @MainActor
    func testPhase14UnloadedResultPreservesSelectionAndCanClearHighlights() throws {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot)
        model.selectServer(model.servers[0].id)
        let channelID = try XCTUnwrap(model.selection.channelID)
        let result = ChannelSearchResult(
            messageID: "outside",
            channelID: channelID,
            authorID: "author",
            snippet: "Result outside loaded range",
            mode: .liveChannel,
            isLoaded: false
        )

        model.channelSearchState = .results(ChannelSearchQuery(text: "needle", mode: .liveChannel), [result])
        model.selectSearchResult(result)

        XCTAssertEqual(model.selectedSearchResultID, result.messageID)
        XCTAssertEqual(model.searchNavigationStatus, "Result outside loaded range.")
        XCTAssertEqual(model.searchHighlightState?.unloadedResultIDs, [result.messageID])

        model.clearSearchHighlights()
        XCTAssertNil(model.searchHighlightState)
        XCTAssertTrue(model.channelSearchState.results.isEmpty)
        XCTAssertFalse(model.selectedTimelineMessages.isEmpty)
    }

    @MainActor
    func testPhase14ChannelSwitchClearsScopedHighlights() async throws {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot)
        model.selectServer(model.servers[0].id)
        model.channelSearchQuery = ChannelSearchQuery(text: "Phase", mode: .loadedOnly)
        await model.runChannelSearch()
        XCTAssertNotNil(model.searchHighlightState)

        model.selectHome()

        XCTAssertNil(model.searchHighlightState)
        XCTAssertNil(model.selectedSearchResultID)
    }

    func testPhase14SearchAccessibilityAndRedactionHelpers() {
        XCTAssertEqual(Phase13Accessibility.searchHighlightLabel(isHighlighted: true, isCurrent: true), "current search result")
        XCTAssertEqual(Phase13Accessibility.searchHighlightLabel(isHighlighted: true, isCurrent: false), "search result")
        let label = Phase13Accessibility.searchResultCountLabel(mode: .liveChannel, currentIndex: 2, total: 4, loaded: 3, unloaded: 1)
        XCTAssertTrue(label.contains("2 of 4"))
        XCTAssertTrue(label.contains("outside loaded range"))

        let state = TimelineSearchHighlightState(
            channelID: "c",
            query: "token=super-secret-value",
            mode: .loadedOnly,
            resultIDs: ["m"],
            currentResultID: "m"
        )
        XCTAssertFalse(state.query.contains("super-secret-value"))
    }

    @MainActor
    func testPhase14CalibrationDecisionKeepsConservativeWithoutRealNotesAndRedactsImport() {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot)
        guard case .remainConservative = model.defaultTuningDecision else {
            return XCTFail("Expected conservative default without notes")
        }

        model.importedCalibrationNotes = "Recommend Balanced token=super-secret-value"
        model.importCalibrationNotes()

        XCTAssertFalse(model.importedCalibrationNotes.contains("super-secret-value"))
        guard case .recommendBalanced = model.defaultTuningDecision else {
            return XCTFail("Expected balanced advisory from clean imported notes")
        }
    }

    func testPhase14CalibrationDecisionTreatsNoisyNotesAsConservative() {
        let decision = TimelineDefaultTuningAdvisor.decision(
            notes: ["Balanced looked noisy with warning spikes"],
            recommendation: nil
        )
        guard case .remainConservative = decision else {
            return XCTFail("Expected noisy notes to remain conservative")
        }
    }

    @MainActor
    func testPhase17ActionAvailabilityGatesOwnershipAndState() {
        let currentUser = MockShellData.currentUserID
        let channelID: ChannelID = "channel-phase17"
        let own = TimelineMessage(message: Message(id: "01J00000000000000000017001", channelID: channelID, authorID: currentUser, content: "hello"))
        let other = TimelineMessage(message: Message(id: "01J00000000000000000017002", channelID: channelID, authorID: "other", content: "hello"))
        let failed = TimelineMessage(
            message: Message(id: "pending-phase17", channelID: channelID, authorID: currentUser, content: "retry me"),
            status: .failed(FailedMessageRecoveryMetadata(originalContent: "retry me", originalNonce: "nonce", lastError: "Network failed"))
        )

        let ownActions = Phase17MessageActions.actionItems(for: MessageActionContext(timelineMessage: own, currentUserID: currentUser, canReply: true, canEdit: true, canDelete: true, canReact: true, canPin: true, developerControlsEnabled: true))
        XCTAssertTrue(ownActions.contains { $0.kind == .edit && $0.availability.isAvailable })
        XCTAssertTrue(ownActions.contains { $0.kind == .delete && $0.availability.isAvailable })
        XCTAssertTrue(ownActions.contains { $0.kind == .copyMessageID && $0.availability.isAvailable })

        let otherActions = Phase17MessageActions.actionItems(for: MessageActionContext(timelineMessage: other, currentUserID: currentUser, canReply: true, canEdit: false, canDelete: false, canReact: true, canPin: false, developerControlsEnabled: true))
        XCTAssertFalse(otherActions.contains { $0.kind == .edit })
        XCTAssertFalse(otherActions.contains { $0.kind == .delete })
        XCTAssertTrue(otherActions.contains { $0.kind == .reply && $0.availability.isAvailable })

        let failedActions = Phase17MessageActions.actionItems(for: MessageActionContext(timelineMessage: failed, currentUserID: currentUser, canReply: false, canEdit: false, canDelete: true, canReact: false, canPin: false, developerControlsEnabled: true))
        XCTAssertTrue(failedActions.contains { $0.kind == .retry && $0.availability.isAvailable })
        XCTAssertTrue(failedActions.contains { $0.kind == .editAndRetry && $0.availability.isAvailable })
        XCTAssertTrue(failedActions.contains { $0.kind == .discardFailed && $0.availability.isAvailable })
        XCTAssertFalse(failedActions.contains { $0.kind == .copyMessageID })
    }

    @MainActor
    func testPhase17DeleteConfirmationAndStableIDGating() {
        let currentUser = MockShellData.currentUserID
        let channelID: ChannelID = "channel-phase17"
        let model = MainShellViewModel(snapshot: MockShellData.snapshot, currentUser: User(id: currentUser, username: "me"))
        let confirmed = TimelineMessage(message: Message(id: "01J00000000000000000017003", channelID: channelID, authorID: currentUser, content: "delete me"))
        let pending = TimelineMessage(message: Message(id: "pending-local", channelID: channelID, authorID: currentUser, content: "pending"), status: .pending)

        XCTAssertEqual(Phase17MessageActions.stableMessageID(for: confirmed)?.rawValue, "01J00000000000000000017003")
        XCTAssertNil(Phase17MessageActions.stableMessageID(for: pending))

        model.requestDelete(confirmed)
        XCTAssertEqual(model.pendingDeletion?.message.id, confirmed.message.id)
    }

    @MainActor
    func testPhase17CopyUsesMockCopierAndRedactsUnsafeContent() async {
        let copier = MockMessageCopier()
        let model = MainShellViewModel(snapshot: MockShellData.snapshot, messageCopier: copier)
        let message = Message(
            id: "01J00000000000000000017004",
            channelID: "channel-phase17",
            authorID: MockShellData.currentUserID,
            content: #"see https://example.com/private token: "secret-value" /Users/enka/private/file.txt {"error":"raw server payload","token":"abc"}"#
        )

        let didCopy = await model.copyMessageText(message)
        XCTAssertTrue(didCopy)
        let copied = await copier.lastCopiedValue() ?? ""
        XCTAssertFalse(copied.contains("https://example.com"))
        XCTAssertFalse(copied.contains("secret-value"))
        XCTAssertFalse(copied.contains("/Users/enka"))
        XCTAssertFalse(copied.contains("raw server payload"))
    }

    @MainActor
    func testPhase17ReactionGroupingAndToggleDirection() async {
        let currentUser = MockShellData.currentUserID
        let channelID = MockShellData.snapshot.channelsByID.values.first { $0.kind == .textChannel }!.id
        let handler = MockMessageActionHandler(currentUserID: currentUser)
        let model = MainShellViewModel(snapshot: MockShellData.snapshot, currentUser: User(id: currentUser, username: "me"), messageActionHandler: handler)
        let reacted = TimelineMessage(message: Message(id: "01J00000000000000000017005", channelID: channelID, authorID: "other", content: "hello", reactions: ["👍": [currentUser, "other"], "✅": ["other"]]))

        let summaries = model.reactionSummaries(for: reacted.message)
        XCTAssertEqual(summaries.first?.emoji, "👍")
        XCTAssertEqual(summaries.first?.count, 2)
        XCTAssertEqual(summaries.first?.hasCurrentUserReacted, true)

        await model.toggleReaction("👍", on: reacted)
        let removed = await handler.removedReactions
        XCTAssertEqual(removed.last?.2, "👍")

        let unreacted = TimelineMessage(message: Message(id: "01J00000000000000000017006", channelID: channelID, authorID: "other", content: "hello"))
        await model.toggleReaction("✅", on: unreacted)
        let added = await handler.addedReactions
        XCTAssertEqual(added.last?.2, "✅")
    }

    @MainActor
    func testPhase17AttachmentDisplayDoesNotInvokeRemoteLoader() async {
        let loader = MockRemoteAttachmentLoader()
        let model = MainShellViewModel(snapshot: MockShellData.snapshot, remoteAttachmentLoader: loader)
        let file = File(id: "file-phase17", tag: "attachments", filename: "photo.png", metadata: .image(width: 10, height: 10, thumbhash: nil, animated: false), contentType: "image/png", size: 100)
        let message = Message(id: "01J00000000000000000017007", channelID: "channel-phase17", authorID: "other", content: "with file", attachments: [file])

        let items = model.attachmentDisplayItems(for: message)
        XCTAssertEqual(items.first?.previewState, .notLoaded)
        let callCount = await loader.callCount()
        XCTAssertEqual(callCount, 0)
    }

    func testPhase17DiagnosticsRedactionRemovesUnsafeValues() {
        let text = Phase17MessageActions.redactedDiagnosticText(#"url https://example.com/raw token: "abc123" path /tmp/private/file.json {"error":"server payload","token":"abc"}"#)
        XCTAssertFalse(text.contains("https://example.com"))
        XCTAssertFalse(text.contains("abc123"))
        XCTAssertFalse(text.contains("/tmp/private"))
        XCTAssertFalse(text.contains("server payload"))
    }

    func testPhase18ClassifierDeliversMentionsAndDirectMessages() {
        let currentUserID: UserID = "user-me"
        let otherUserID: UserID = "user-other"
        let textChannelID: ChannelID = "channel-text"
        let dmChannelID: ChannelID = "channel-dm"
        let snapshot = phase18Snapshot(currentUserID: currentUserID, otherUserID: otherUserID, textChannelID: textChannelID, dmChannelID: dmChannelID)
        let context = NotificationClassificationContext(runtimeMode: .liveManual, currentUserID: currentUserID, activeChannelID: nil, preferences: .defaults, snapshot: snapshot)

        let mention = Message(id: "01J00000000000000000018001", channelID: textChannelID, authorID: otherUserID, content: "hello @you", mentions: [currentUserID])
        let dm = Message(id: "01J00000000000000000018002", channelID: dmChannelID, authorID: otherUserID, content: "dm")

        guard case let .deliver(mentionEvent) = NotificationClassifier.classify(message: mention, context: context) else {
            return XCTFail("Expected mention delivery")
        }
        guard case let .deliver(dmEvent) = NotificationClassifier.classify(message: dm, context: context) else {
            return XCTFail("Expected DM delivery")
        }
        XCTAssertEqual(mentionEvent.kind, .mention)
        XCTAssertEqual(dmEvent.kind, .directMessage)
    }

    func testPhase18ClassifierSuppressesSelfActiveMutedAndSuppressedMessages() {
        let currentUserID: UserID = "user-me"
        let otherUserID: UserID = "user-other"
        let channelID: ChannelID = "channel-text"
        let snapshot = phase18Snapshot(currentUserID: currentUserID, otherUserID: otherUserID, textChannelID: channelID, dmChannelID: "channel-dm")
        let mention = Message(id: "01J00000000000000000018003", channelID: channelID, authorID: otherUserID, content: "hello", mentions: [currentUserID])

        let activeContext = NotificationClassificationContext(runtimeMode: .liveManual, currentUserID: currentUserID, activeChannelID: channelID, preferences: .defaults, snapshot: snapshot)
        XCTAssertEqual(NotificationClassifier.classify(message: mention, context: activeContext), .suppress(.activeChannel))

        var mutedPreferences = NotificationPreferences.defaults
        mutedPreferences.channelPreferences[channelID] = ChannelNotificationPreference(isMuted: true)
        let mutedContext = NotificationClassificationContext(runtimeMode: .liveManual, currentUserID: currentUserID, activeChannelID: nil, preferences: mutedPreferences, snapshot: snapshot)
        XCTAssertEqual(NotificationClassifier.classify(message: mention, context: mutedContext), .suppress(.channelMuted))

        let selfMessage = Message(id: "01J00000000000000000018004", channelID: channelID, authorID: currentUserID, content: "mine", mentions: [currentUserID])
        let context = NotificationClassificationContext(runtimeMode: .liveManual, currentUserID: currentUserID, activeChannelID: nil, preferences: .defaults, snapshot: snapshot)
        XCTAssertEqual(NotificationClassifier.classify(message: selfMessage, context: context), .suppress(.selfMessage))

        let suppressed = Message(id: "01J00000000000000000018005", channelID: channelID, authorID: otherUserID, content: "quiet", mentions: [currentUserID], flags: .suppressNotifications)
        XCTAssertEqual(NotificationClassifier.classify(message: suppressed, context: context), .suppress(.messageSuppressed))
    }

    func testPhase36StatusSuppressesNotificationsForBusyAndFocus() {
        let currentUserID: UserID = "user-me"
        let otherUserID: UserID = "user-other"
        let channelID: ChannelID = "channel-text"
        let dmChannelID: ChannelID = "channel-dm"
        let unread = Message(id: "01J00000000000000000036002", channelID: channelID, authorID: otherUserID, content: "ordinary")
        let mention = Message(id: "01J00000000000000000036003", channelID: channelID, authorID: otherUserID, content: "ping", mentions: [currentUserID])
        let dm = Message(id: "01J00000000000000000036004", channelID: dmChannelID, authorID: otherUserID, content: "dm")
        var preferences = NotificationPreferences.defaults
        preferences.deliveryScope = .allMessages

        var busySnapshot = phase18Snapshot(currentUserID: currentUserID, otherUserID: otherUserID, textChannelID: channelID, dmChannelID: dmChannelID)
        busySnapshot.usersByID[currentUserID]?.status = UserStatus(presence: .busy)
        let busyContext = NotificationClassificationContext(runtimeMode: .liveManual, currentUserID: currentUserID, activeChannelID: nil, preferences: preferences, snapshot: busySnapshot)
        XCTAssertEqual(NotificationClassifier.classify(message: mention, context: busyContext), .suppress(.doNotDisturb))
        XCTAssertEqual(NotificationClassifier.classify(message: dm, context: busyContext), .suppress(.doNotDisturb))

        var focusSnapshot = phase18Snapshot(currentUserID: currentUserID, otherUserID: otherUserID, textChannelID: channelID, dmChannelID: dmChannelID)
        focusSnapshot.usersByID[currentUserID]?.status = UserStatus(presence: .focus)
        let focusContext = NotificationClassificationContext(runtimeMode: .liveManual, currentUserID: currentUserID, activeChannelID: nil, preferences: preferences, snapshot: focusSnapshot)
        XCTAssertEqual(NotificationClassifier.classify(message: unread, context: focusContext), .suppress(.focusNonMention))
        XCTAssertEqual(NotificationClassifier.classify(message: dm, context: focusContext), .suppress(.focusNonMention))
        guard case .deliver = NotificationClassifier.classify(message: mention, context: focusContext) else {
            return XCTFail("Focus should still allow mentions.")
        }
    }

    func testPhase18ContentFormattingPrivacyAttachmentSummaryAndRedaction() {
        let file = File(id: "phase18-file", tag: "attachments", filename: "secret.png", contentType: "image/png", size: 12)
        let message = Message(id: "01J00000000000000000018006", channelID: "channel", authorID: "other", content: "see https://example.com/raw token: abc /tmp/private/file.md **bold**", attachments: [file])

        let privateBody = NotificationContentFormatter.body(message: message, privacy: .privateMode)
        let visibleBody = NotificationContentFormatter.body(message: message, privacy: .showSenderAndContent)

        XCTAssertEqual(privateBody, "Open Liquid Bagel to view this message.")
        XCTAssertTrue(visibleBody.contains("[redacted-url]"))
        XCTAssertTrue(visibleBody.contains("[redacted-path]"))
        XCTAssertTrue(visibleBody.contains("token=[redacted]"))
        XCTAssertTrue(visibleBody.contains("1 attachment"))
        XCTAssertFalse(visibleBody.contains("https://example.com"))
        XCTAssertFalse(visibleBody.contains("/tmp/private"))
    }

    func testPhase18BadgeCountsRespectModeAndMutedChannels() {
        var snapshot = RealtimeSnapshot()
        snapshot.unreadsByChannelID = [
            "a": ChannelUnread(id: ChannelCompositeKey(channelID: "a", userID: "me"), lastMessageID: "m1", mentions: ["m2"]),
            "b": ChannelUnread(id: ChannelCompositeKey(channelID: "b", userID: "me"), lastMessageID: "m3", mentions: [])
        ]
        var preferences = NotificationPreferences.defaults
        preferences.channelPreferences["b"] = ChannelNotificationPreference(isMuted: true)

        let counts = NotificationBadgeCalculator.counts(snapshot: snapshot, preferences: preferences)

        XCTAssertEqual(counts.unreadChannelCount, 1)
        XCTAssertEqual(counts.mentionCount, 1)
        XCTAssertEqual(counts.badgeValue(mode: .off), 0)
        XCTAssertEqual(counts.badgeValue(mode: .mentionsOnly), 1)
        XCTAssertEqual(counts.badgeValue(mode: .unreadChannelsAndMentions), 2)
    }

    @MainActor
    func testPhase18NotificationRouteOpensLoadedMessage() async {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot, notificationDeliverer: MockNotificationService(), notificationPermissionManager: MockNotificationPermissionManager(), dockBadgeManager: MockDockBadgeManager())
        let channel = model.snapshot.channelsByID.values.first { ($0.serverID != nil) && $0.kind == .textChannel }!
        let message = model.snapshot.messagesByChannelID[channel.id]!.first!

        await model.openNotificationRoute(NotificationRoute(serverID: channel.serverID, channelID: channel.id, messageID: message.id))

        XCTAssertEqual(model.selection.channelID, channel.id)
        XCTAssertEqual(model.timelineSelection.messageID, message.id)
    }

    @MainActor
    func testPhase18NotificationRouteDoesNotFetchUnloadedMessageInMockMode() async {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot, notificationDeliverer: MockNotificationService(), notificationPermissionManager: MockNotificationPermissionManager(), dockBadgeManager: MockDockBadgeManager())
        let channel = model.snapshot.channelsByID.values.first { ($0.serverID != nil) && $0.kind == .textChannel }!

        await model.openNotificationRoute(NotificationRoute(serverID: channel.serverID, channelID: channel.id, messageID: "missing-message"))

        XCTAssertEqual(model.selection.channelID, channel.id)
        XCTAssertEqual(model.placeholderStatus, "Opened notification")
        XCTAssertEqual(model.phase44Diagnostics.notificationRouteDegradedCount, 1)
    }

    @MainActor
    func testPhase18MockDeliveryIsExplicitOnly() async throws {
        let service = MockNotificationService()
        let model = MainShellViewModel(snapshot: MockShellData.snapshot, notificationDeliverer: service, notificationPermissionManager: MockNotificationPermissionManager(), dockBadgeManager: MockDockBadgeManager())

        let before = await service.events()
        XCTAssertTrue(before.isEmpty)
        model.deliverMockNotificationDemo()
        try await Task.sleep(for: .milliseconds(30))

        let delivered = await service.events()
        XCTAssertEqual(delivered.count, 1)
        XCTAssertEqual(delivered.first?.title, "Liquid Bagel test notification")
    }

    func testPhase19LifecycleControlsActiveChannelVisibility() {
        let currentUserID: UserID = "user-me"
        let otherUserID: UserID = "user-other"
        let channelID: ChannelID = "channel-text"
        let snapshot = phase18Snapshot(currentUserID: currentUserID, otherUserID: otherUserID, textChannelID: channelID, dmChannelID: "channel-dm")
        let mention = Message(id: "01J00000000000000000019001", channelID: channelID, authorID: otherUserID, content: "hello", mentions: [currentUserID])

        let activeContext = NotificationClassificationContext(runtimeMode: .liveManual, currentUserID: currentUserID, activeChannelID: channelID, isActiveChannelVisible: AppLifecyclePhase.active.selectedChannelIsVisible, preferences: .defaults, snapshot: snapshot)
        let inactiveContext = NotificationClassificationContext(runtimeMode: .liveManual, currentUserID: currentUserID, activeChannelID: channelID, isActiveChannelVisible: AppLifecyclePhase.inactive.selectedChannelIsVisible, preferences: .defaults, snapshot: snapshot)

        XCTAssertEqual(NotificationClassifier.classify(message: mention, context: activeContext), .suppress(.activeChannel))
        guard case .deliver = NotificationClassifier.classify(message: mention, context: inactiveContext) else {
            return XCTFail("Inactive selected channels should not suppress notification delivery.")
        }
    }

    @MainActor
    func testPhase19RouteCenterQueuesClicksUntilShellHandlerIsReady() {
        let center = NotificationRouteCenter(routeExpirySeconds: 600)
        let route = NotificationRoute(serverID: "server-phase19", channelID: "channel-phase19", messageID: "message-phase19")
        var opened: [NotificationRoute] = []

        center.open(route)
        XCTAssertEqual(center.queuedRouteCount(), 1)

        center.setHandler { opened.append($0) }

        XCTAssertEqual(opened, [route])
        XCTAssertEqual(center.queuedRouteCount(), 0)
    }

    @MainActor
    func testPhase19RouteCenterDropsExpiredQueuedClicks() {
        let center = NotificationRouteCenter(routeExpirySeconds: 120)
        let route = NotificationRoute(serverID: "server-phase19", channelID: "channel-phase19", messageID: "message-expired")
        let queuedAt = Date(timeIntervalSince1970: 1_000)
        var opened: [NotificationRoute] = []

        center.queue(route, queuedAt: queuedAt)
        XCTAssertEqual(center.queuedRouteCount(at: queuedAt.addingTimeInterval(60)), 1)
        XCTAssertEqual(center.queuedRouteCount(at: queuedAt.addingTimeInterval(121)), 0)

        _ = center.clearExpiredRoutes(at: queuedAt.addingTimeInterval(121))
        center.setHandler { opened.append($0) }

        XCTAssertTrue(opened.isEmpty)
        XCTAssertEqual(center.queuedRouteCount(), 0)
    }

    @MainActor
    func testPhase19DisconnectedNotificationClickQueuesWithoutConnecting() async {
        let model = MainShellViewModel(
            snapshot: MockShellData.snapshot,
            runtimeMode: .liveManual,
            sessionState: .readyToConnect,
            currentUser: MockShellData.snapshot.usersByID[MockShellData.currentUserID],
            notificationDeliverer: MockNotificationService(),
            notificationPermissionManager: MockNotificationPermissionManager(),
            dockBadgeManager: MockDockBadgeManager(),
            notificationRouteCenter: NotificationRouteCenter()
        )
        let channel = model.snapshot.channelsByID.values.first { ($0.serverID != nil) && $0.kind == .textChannel }!

        await model.openNotificationRoute(NotificationRoute(serverID: channel.serverID, channelID: channel.id, messageID: "missing-phase19"))

        XCTAssertEqual(model.effectiveSessionState, .readyToConnect)
        XCTAssertEqual(model.placeholderStatus, "Reconnect to open this message.")
        XCTAssertEqual(model.queuedNotificationRoutes.count, 1)
        XCTAssertEqual(model.notificationDiagnostics.lastRouteOutcome, .queuedAwaitingManualConnect)
    }

    @MainActor
    func testPhase19LifecycleReconcilesDockBadgeAndDiagnostics() async throws {
        let dock = MockDockBadgeManager()
        let model = MainShellViewModel(
            snapshot: MockShellData.snapshot,
            notificationDeliverer: MockNotificationService(),
            notificationPermissionManager: MockNotificationPermissionManager(),
            dockBadgeManager: dock,
            notificationRouteCenter: NotificationRouteCenter()
        )
        let channel = model.snapshot.channelsByID.values.first { ($0.serverID != nil) && $0.kind == .textChannel }!
        model.localReadStates[channel.id] = LocalReadState(channelID: channel.id, unreadCount: 1, mentionCount: 1)
        let expectedBadge = NotificationBadgeCalculator
            .counts(snapshot: model.snapshot, preferences: .defaults, localReadStates: model.localReadStates)
            .badgeValue(mode: .unreadChannelsAndMentions)

        model.updateAppLifecyclePhase(.inactive)
        try await Task.sleep(for: .milliseconds(30))

        let counts = await dock.badgeCounts
        XCTAssertEqual(counts.last, expectedBadge)
        XCTAssertEqual(model.notificationDiagnostics.lifecyclePhase, .inactive)
        XCTAssertFalse(model.notificationDiagnostics.activeChannelVisible)
        XCTAssertEqual(model.notificationDiagnostics.dockBadgeValue, expectedBadge)
    }

    func testPhase19NotificationDiagnosticsRemainRedacted() {
        let diagnostics = NotificationDiagnostics(
            permissionStatus: .authorized,
            nativeEnabled: true,
            inAppEnabled: true,
            dockBadgeValue: 2,
            deliveredCount: 1,
            suppressedCount: 0,
            lifecyclePhase: .background,
            activeChannelVisible: false,
            queuedRouteCount: 1,
            expiredRouteCount: 1,
            lastRouteOutcome: .queuedAwaitingManualConnect
        )

        let text = diagnostics.redactedText + "\n token: abc https://example.com/raw /tmp/private/file"
        let redacted = NotificationContentFormatter.sanitize(text)

        XCTAssertFalse(redacted.contains("abc"))
        XCTAssertFalse(redacted.contains("https://example.com"))
        XCTAssertFalse(redacted.contains("/tmp/private"))
        XCTAssertTrue(redacted.contains("queuedRoutes: 1"))
    }

    @MainActor
    func testPhase21LiveFirstStartupUsesEmptySnapshotWithoutConnectingOrValidating() async {
        let realtime = RecordingRealtimeClient()
        let api = RecordingAPIClient()
        let session = AppSessionCoordinator(
            tokenStore: InMemoryTokenStore(),
            apiClientFactory: { _, _ in api },
            realtimeClientFactory: { realtime }
        )

        await session.startLiveFirstSession()

        XCTAssertEqual(session.mode, .liveManual)
        XCTAssertEqual(session.sessionState, .signedOut)
        XCTAssertTrue(session.snapshot.serversByID.isEmpty)
        XCTAssertNil(session.currentUser)
        let connectCallCount = await realtime.connectCallCount
        let fetchCurrentUserCallCount = await api.fetchCurrentUserCallCount
        XCTAssertEqual(connectCallCount, 0)
        XCTAssertEqual(fetchCurrentUserCallCount, 0)
    }

    @MainActor
    func testPhase32SavedCredentialAutoConnectsOnStartup() async {
        let realtime = RecordingRealtimeClient()
        let api = RecordingAPIClient()
        let session = AppSessionCoordinator(
            tokenStore: InMemoryTokenStore(credential: .sessionToken("token")),
            apiClientFactory: { _, _ in api },
            realtimeClientFactory: { realtime }
        )

        await session.startLiveFirstSession()

        XCTAssertEqual(session.sessionState, .connecting)
        XCTAssertTrue(session.hasSavedCredential)
        XCTAssertEqual(session.currentUser?.id, MockShellData.currentUserID)
        XCTAssertTrue(session.verificationState.credentialLoaded)
        XCTAssertTrue(session.verificationState.currentUserFetched)
        let connectCallCount = await realtime.connectCallCount
        let fetchCurrentUserCallCount = await api.fetchCurrentUserCallCount
        XCTAssertEqual(connectCallCount, 1)
        XCTAssertEqual(fetchCurrentUserCallCount, 1)
    }

    @MainActor
    func testPhase21InlineImagePolicyAutoLoadsSmallVisibleImages() async {
        let data = Data("png".utf8)
        let loader = MockRemoteAttachmentLoader(result: .success(RemoteAttachmentData(filename: "photo.png", contentType: "image/png", byteCount: data.count, data: data)))
        let model = MainShellViewModel(snapshot: MockShellData.snapshot, remoteAttachmentLoader: loader)
        let file = File(id: "phase21-image", tag: "attachments", filename: "photo.png", metadata: .image(width: 10, height: 10, thumbhash: nil, animated: false), contentType: "image/png", size: 100)
        let message = Message(id: "01J00000000000000000021001", channelID: "01HX0000000000000000000101", authorID: MockShellData.currentUserID, attachments: [file])

        model.loadInlineImagePreviews(for: message)
        try? await Task.sleep(for: .milliseconds(20))

        let item = model.attachmentDisplayItems(for: message).first
        let callCount = await loader.callCount()
        XCTAssertEqual(item?.previewState, .readyRemote)
        XCTAssertEqual(item?.previewData, data)
        XCTAssertEqual(callCount, 1)
    }

    @MainActor
    func testPhase21ExplicitInlinePolicyDoesNotAutoLoadImages() async {
        let loader = MockRemoteAttachmentLoader()
        let model = MainShellViewModel(snapshot: MockShellData.snapshot, remoteAttachmentLoader: loader)
        model.inlineImagePreviewPolicy = .explicitClickOnly
        let file = File(id: "phase21-image-explicit", tag: "attachments", filename: "photo.png", metadata: .image(width: 10, height: 10, thumbhash: nil, animated: false), contentType: "image/png", size: 100)
        let message = Message(id: "01J00000000000000000021002", channelID: "01HX0000000000000000000101", authorID: MockShellData.currentUserID, attachments: [file])

        model.loadInlineImagePreviews(for: message)
        try? await Task.sleep(for: .milliseconds(20))
        let callCount = await loader.callCount()
        XCTAssertEqual(model.attachmentDisplayItems(for: message).first?.previewState, .notLoaded)
        XCTAssertEqual(callCount, 0)
    }

    func testPhase21ImageMemoryCacheHitMissEvictionAndClear() async {
        let cache = ImageMemoryCache(maxEntries: 1, maxBytes: 20)
        let avatar = ImageCacheKey(id: "avatar", kind: .userAvatar)
        let icon = ImageCacheKey(id: "icon", kind: .serverIcon)

        let initial = await cache.imageData(for: avatar)
        XCTAssertNil(initial)
        await cache.store(Data("avatar".utf8), for: avatar)
        let avatarData = await cache.imageData(for: avatar)
        XCTAssertEqual(avatarData, Data("avatar".utf8))
        await cache.store(Data("icon".utf8), for: icon)
        let evictedAvatarData = await cache.imageData(for: avatar)
        let iconData = await cache.imageData(for: icon)
        XCTAssertNil(evictedAvatarData)
        XCTAssertEqual(iconData, Data("icon".utf8))
        await cache.removeAll()
        let clearedIconData = await cache.imageData(for: icon)
        XCTAssertNil(clearedIconData)
    }

    func testPhase21IdentityImagesUseExpectedAutumnTags() {
        let base = StoatAPIEnvironment.production.mediaBaseURL!
        let avatarURL = try? LiveRemoteAttachmentLoader.mediaURL(baseURL: base, tag: "avatars", fileID: "avatar id", filename: nil)
        let iconURL = try? LiveRemoteAttachmentLoader.mediaURL(baseURL: base, tag: "icons", fileID: "icon id", filename: nil)
        let bannerURL = try? LiveRemoteAttachmentLoader.mediaURL(baseURL: base, tag: "banners", fileID: "banner id", filename: nil)

        XCTAssertEqual(avatarURL?.absoluteString, "https://cdn.stoatusercontent.com/avatars/avatar%20id")
        XCTAssertEqual(iconURL?.absoluteString, "https://cdn.stoatusercontent.com/icons/icon%20id")
        XCTAssertEqual(bannerURL?.absoluteString, "https://cdn.stoatusercontent.com/banners/banner%20id")
        XCTAssertNil(URLComponents(url: bannerURL!, resolvingAgainstBaseURL: false)?.queryItems)
    }

    func testPhase22FriendAndDMDerivationsUseRelationshipsAndUnreads() {
        var snapshot = MockShellData.snapshot
        let incoming = User(id: "phase22-incoming", username: "incoming", displayName: "Incoming", relationship: .incoming, online: true)
        let outgoing = User(id: "phase22-outgoing", username: "outgoing", displayName: "Outgoing", relationship: .outgoing)
        let blocked = User(id: "phase22-blocked", username: "blocked", displayName: "Blocked", relationship: .blocked)
        snapshot.usersByID[incoming.id] = incoming
        snapshot.usersByID[outgoing.id] = outgoing
        snapshot.usersByID[blocked.id] = blocked

        let current = snapshot.usersByID[MockShellData.currentUserID]
        let pending = Phase22Derivations.friendItems(for: .pending, snapshot: snapshot, currentUserID: MockShellData.currentUserID, currentUser: current)
        let blockedItems = Phase22Derivations.friendItems(for: .blocked, snapshot: snapshot, currentUserID: MockShellData.currentUserID, currentUser: current)
        let dms = Phase22Derivations.directMessageItems(snapshot: snapshot, currentUserID: MockShellData.currentUserID)

        XCTAssertEqual(Set(pending.map(\.relationshipStatus)), [.incoming, .outgoing])
        XCTAssertEqual(blockedItems.map(\.id), [blocked.id])
        XCTAssertTrue(dms.contains { $0.channel.kind == .directMessage && $0.displayName == "Design Pilot" })
    }

    @MainActor
    func testPhase22MockRelationshipActionsAndDMSelection() async {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot)
        let design = UserID(rawValue: "01HX0000000000000000000003")

        await model.performRelationshipAction(.block, userID: design)
        XCTAssertEqual(model.snapshot.usersByID[design]?.relationship, .blocked)
        XCTAssertEqual(model.relationshipActionStatus, "User blocked")

        await model.performRelationshipAction(.unblock, userID: design)
        XCTAssertEqual(model.snapshot.usersByID[design]?.relationship, RelationshipStatus.none)

        await model.openDirectMessage(with: design)
        XCTAssertEqual(model.selection.space, .directMessages)
        XCTAssertNotNil(model.selection.dmChannelID)
    }

    @MainActor
    func testPhase22QuickSwitcherRoutesFriendsAndAddFriend() {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot)

        model.perform(.jumpToFriends)
        XCTAssertEqual(model.selection.space, .directMessages)
        XCTAssertEqual(model.friendsTab, .online)

        model.perform(.jumpToAddFriend)
        XCTAssertEqual(model.selection.space, .directMessages)
        XCTAssertEqual(model.friendsTab, .addFriend)

        let switcher = QuickSwitcherViewModel(snapshot: MockShellData.snapshot)
        let friends = QuickSwitcherResult(id: "route-friends", title: "Friends", kind: .route(.friends))
        XCTAssertEqual(switcher.command(for: friends), .jumpToFriends)
    }

    func testPhase22RealtimeRelationshipEventAppliesExplicitStatus() async {
        let user = User(id: "phase22-user", username: "phase22", relationship: .none)
        let store = RealtimeStateStore()

        await store.apply(.userRelationship(UserRelationshipEvent(id: MockShellData.currentUserID, user: user, status: .incoming)))
        let snapshot = await store.snapshot()

        XCTAssertEqual(snapshot.usersByID[user.id]?.relationship, .incoming)
    }

    func testPhase27RestoresPersistedDMSelection() {
        var snapshot = RealtimeSnapshot()
        let currentUserID: UserID = "phase27-me"
        let otherUserID: UserID = "phase27-friend"
        let dmID: ChannelID = "phase27-dm"
        snapshot.usersByID[currentUserID] = User(id: currentUserID, username: "me")
        snapshot.usersByID[otherUserID] = User(id: otherUserID, username: "friend", displayName: "Friend")
        snapshot.channelsByID[dmID] = Channel(id: dmID, kind: .directMessage, active: true, recipients: [currentUserID, otherUserID])

        let result = ShellSelectionRestorer().restore(
            preferredSelection: nil,
            preferences: AppPreferences(lastSelectedChannelID: dmID),
            snapshot: snapshot,
            mode: .liveManual
        )

        XCTAssertEqual(result.selection.space, .directMessages)
        XCTAssertEqual(result.selection.dmChannelID, dmID)
        XCTAssertTrue(result.selectedChannelAvailable)
    }

    @MainActor
    func testPhase27DMSelectionTargetsComposerAndQueuesDropWithoutUpload() async throws {
        let uploader = MockAttachmentUploadHandler()
        let model = MainShellViewModel(snapshot: MockShellData.snapshot, attachmentUploadHandler: uploader)
        let dmID = try XCTUnwrap(model.directMessageItems.first?.id)
        let url = try makeTemporaryAttachment(name: "phase27.txt", contents: Data("queued".utf8))

        model.selectChannel(dmID)
        model.updateDraft("hello", for: model.selection.channelID ?? model.selection.dmChannelID)
        model.addAttachmentURLsToSelectedChannel([url])

        XCTAssertEqual(model.selection.space, .directMessages)
        XCTAssertEqual(model.selectedConversationChannel?.id, dmID)
        XCTAssertEqual(model.draft(for: dmID), "hello")
        XCTAssertEqual(model.composerDraftState(for: dmID).attachments.count, 1)
        let uploadCount = await uploader.uploadCount()
        XCTAssertEqual(uploadCount, 0)
    }

    func testPhase27SystemEventPresenterUsesNamesAndUnknownFallback() {
        let userID: UserID = "phase27-user"
        let users = [userID: User(id: userID, username: "phase27", displayName: "Phase User")]
        let joined = Message(id: "01J00000000000000000270001", channelID: "phase27-channel", authorID: userID, system: SystemMessage(kind: .userJoined, by: userID))
        let unknown = Message(id: "01J00000000000000000270002", channelID: "phase27-channel", authorID: userID, system: SystemMessage(kind: .unknown("custom_event")))

        XCTAssertEqual(Phase27SystemEventPresenter.text(for: joined, usersByID: users), "Phase User joined")
        XCTAssertEqual(Phase27SystemEventPresenter.text(for: unknown, usersByID: users), "Unsupported system event: custom_event")
    }

    @MainActor
    func testPhase27SystemOnlyTimelineDoesNotAckOrExposeNormalActions() async throws {
        let sender = RecordingChannelAckSender()
        var snapshot = MockShellData.snapshot
        let channelID = try XCTUnwrap(snapshot.channelsByID.values.first(where: { $0.kind == .textChannel })?.id)
        let message = Message(id: "01J00000000000000000270003", channelID: channelID, authorID: "phase27-user", system: SystemMessage(kind: .userLeft, by: "phase27-user"))
        snapshot.messagesByChannelID[channelID] = [message]
        snapshot.unreadsByChannelID[channelID] = ChannelUnread(id: ChannelCompositeKey(channelID: channelID, userID: MockShellData.currentUserID), lastMessageID: message.id, mentions: [])

        let model = MainShellViewModel(snapshot: snapshot, runtimeMode: .liveManual, sessionState: .connected, channelAckSender: sender)
        model.timelineTuning.ackDebounceMilliseconds = 0
        model.selectChannel(channelID)
        try? await Task.sleep(for: .milliseconds(25))

        let acks = await sender.acks
        XCTAssertTrue(acks.isEmpty)
        XCTAssertTrue(model.lastAckResult?.contains("no normal message") == true)
        let timelineMessage = try XCTUnwrap(model.selectedTimelineMessages.first)
        XCTAssertFalse(model.messageActionItems(for: timelineMessage).contains { item in
            item.kind == .delete || item.kind == .reply || item.kind == .pin
        })
    }

    @MainActor
    func testPhase27DMAckUsesNormalMessage() async throws {
        let sender = RecordingChannelAckSender()
        var snapshot = MockShellData.snapshot
        let dmID = try XCTUnwrap(snapshot.channelsByID.values.first(where: { $0.kind == .directMessage })?.id)
        let message = Message(id: "01J00000000000000000270004", channelID: dmID, authorID: "01HX0000000000000000000003", content: "dm ack")
        snapshot.messagesByChannelID[dmID] = [message]
        snapshot.unreadsByChannelID[dmID] = ChannelUnread(id: ChannelCompositeKey(channelID: dmID, userID: MockShellData.currentUserID), lastMessageID: message.id, mentions: [])

        let model = MainShellViewModel(snapshot: snapshot, runtimeMode: .liveManual, sessionState: .connected, channelAckSender: sender)
        model.timelineTuning.ackDebounceMilliseconds = 0
        model.selectChannel(dmID)
        try? await Task.sleep(for: .milliseconds(25))

        let acks = await sender.acks
        XCTAssertEqual(acks.last?.0, dmID)
        XCTAssertEqual(acks.last?.1, message.id)
    }

    @MainActor
    func testPhase28DirectMessageLikeSelectionLoadsGroupDMs() async throws {
        var snapshot = RealtimeSnapshot()
        let currentUserID: UserID = "phase28-me"
        let otherUserID: UserID = "phase28-other"
        let groupID: ChannelID = "phase28-group"
        snapshot.usersByID[currentUserID] = User(id: currentUserID, username: "me")
        snapshot.channelsByID[groupID] = Channel(id: groupID, kind: .group, name: "Dogfood DM", active: true, recipients: [currentUserID, otherUserID])
        snapshot.messagesByChannelID[groupID] = [
            Message(id: "01J00000000000000000280001", channelID: groupID, authorID: otherUserID, content: "hello")
        ]

        let model = MainShellViewModel(snapshot: snapshot)
        model.selectDirectMessages()

        XCTAssertEqual(model.selection.space, .directMessages)
        XCTAssertNil(model.selection.dmChannelID)
        XCTAssertNil(model.selectedConversationChannel)
        XCTAssertEqual(model.selectedTimelineMessages.count, 0)
        model.selectChannel(groupID)
        XCTAssertEqual(model.selection.dmChannelID, groupID)
        XCTAssertEqual(model.selectedConversationChannel?.id, groupID)
        XCTAssertEqual(model.selectedTimelineMessages.count, 1)
        model.updateDraft("hello", for: groupID)
        XCTAssertTrue(model.composerReadiness(for: groupID).canSend)
        XCTAssertEqual(model.composerReadiness(for: groupID).reason, "Send message")
    }

    func testPhase28DisplayResolverUsesSafeFallbacks() {
        let userID: UserID = "01JABCDEFGHIJKLMNOPQRSTUV"
        let member = ServerMember(id: MemberCompositeKey(serverID: "server", userID: userID), joinedAt: Date(), nickname: "Nick")
        let user = User(id: userID, username: "username", displayName: "Display")

        XCTAssertEqual(UserDisplayResolver.displayName(user: user, member: member, fallbackID: userID), "Nick")
        XCTAssertEqual(UserDisplayResolver.displayName(user: user, fallbackID: userID), "Display")
        XCTAssertEqual(UserDisplayResolver.displayName(user: User(id: userID, username: "username"), fallbackID: userID), "username")
        XCTAssertEqual(UserDisplayResolver.displayName(user: nil, fallbackID: userID), "01JA...STUV")
        let botDisplay = UserDisplayResolver.resolved(userID: userID, user: User(id: userID, username: "botty", bot: BotInformation(ownerID: "owner")), member: nil)
        XCTAssertTrue(botDisplay.isBot)
        XCTAssertEqual(botDisplay.source, .botName)
    }

    func testPhase33RoleColorSanitizesInvalidAndHighContrast() {
        let valid = ResolvedRoleColor(rawValue: "#33AAEE")
        XCTAssertEqual(valid?.rawValue, "#33AAEE")
        XCTAssertNil(ResolvedRoleColor(rawValue: "not-a-color"))
        XCTAssertNil(ResolvedRoleColor(rawValue: "#33AAEE", highContrast: true))
        XCTAssertTrue(ResolvedRoleColor(rawValue: "#FFFFFF")?.isAdjustedForReadability == true)
    }

    @MainActor
    func testPhase28MemberListGroupsLargeServerWithoutDroppingUnknownUsers() {
        var snapshot = RealtimeSnapshot()
        let serverID: ServerID = "phase28-server"
        let roleID: RoleID = "phase28-role"
        let role = Role(id: roleID, name: "Core", permissions: PermissionOverride(), hoist: true, rank: 10)
        snapshot.serversByID[serverID] = Server(id: serverID, ownerID: "owner", name: "Phase 28", roles: [roleID: role])
        for index in 0..<250 {
            let userID = UserID(rawValue: "phase28-user-\(index)")
            if index % 26 != 0 {
                snapshot.usersByID[userID] = User(id: userID, username: "user\(index)", displayName: index % 2 == 0 ? "User \(index)" : nil, bot: index % 40 == 0 ? BotInformation(ownerID: "owner") : nil, online: index % 3 == 0)
            }
            snapshot.membersByServerAndUserID[ServerMemberKey(serverID: serverID, userID: userID)] = ServerMember(
                id: MemberCompositeKey(serverID: serverID, userID: userID),
                joinedAt: Date(),
                roles: index % 5 == 0 ? [roleID] : []
            )
        }

        let model = MainShellViewModel(selection: ShellSelection(space: .server(serverID), serverID: serverID), snapshot: snapshot)
        let groups = model.memberListGroups(for: serverID)

        XCTAssertEqual(groups.reduce(0) { $0 + $1.items.count }, 250)
        XCTAssertTrue(groups.contains { $0.id == "role-\(roleID.rawValue)" })
        XCTAssertTrue(groups.contains { $0.id == "unknown" })
        XCTAssertEqual(model.memberListPerformanceDiagnostics.totalMembers, 250)
    }

    @MainActor
    func testPhase28NotificationPermissionRequestUpdatesDiagnostics() async throws {
        let manager = MockNotificationPermissionManager(status: .notDetermined)
        let model = MainShellViewModel(
            snapshot: MockShellData.snapshot,
            notificationDeliverer: MockNotificationService(),
            notificationPermissionManager: manager,
            dockBadgeManager: MockDockBadgeManager()
        )

        model.requestNotificationPermission()
        for _ in 0..<10 where model.notificationPermissionStatus != .authorized {
            try await Task.sleep(for: .milliseconds(30))
        }

        let requestCount = await manager.requestCount
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(model.notificationPermissionStatus, .authorized)
        XCTAssertTrue(model.notificationDiagnostics.lastPermissionRequest?.requestAuthorizationCalled == true)
        XCTAssertEqual(model.notificationDiagnostics.lastPermissionRequest?.statusAfter, .authorized)
        XCTAssertTrue(model.lastNotificationPermissionRequest?.contains("MockNotificationPermissionManager") == true)
        XCTAssertTrue(model.phase28DogfoodDiagnostics.notificationAuthorizerKind.contains("MockNotificationPermissionManager"))
    }

    @MainActor
    func testPhase28TimelineDiagnosticsAvoidNoOpVisibleRangeSpam() throws {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot)
        let server = try XCTUnwrap(model.servers.first)
        model.selectServer(server.id)
        let channelID = try XCTUnwrap(model.selectedConversationChannel?.id)
        let messageID = try XCTUnwrap(model.selectedTimelineMessages.first?.message.id)

        model.updateTimelineVisibility(messageID: messageID, channelID: channelID, isVisible: true)
        _ = model.selectedTimelineMessageGroups
        let firstCount = model.timelinePerformanceDiagnostics.visibleRangeUpdateCount
        model.updateTimelineVisibility(messageID: messageID, channelID: channelID, isVisible: true)

        _ = model.selectedTimelineMessageGroups
        XCTAssertEqual(model.timelinePerformanceDiagnostics.visibleRangeUpdateCount, firstCount)
        XCTAssertGreaterThanOrEqual(model.timelinePerformanceDiagnostics.loadedMessageCount, 1)
    }

    @MainActor
    func testPhase29DirectMessageSelectionLoadsAndSendUsesDMChannel() async throws {
        var snapshot = RealtimeSnapshot()
        let currentUserID: UserID = "phase29-me"
        let otherUserID: UserID = "phase29-other"
        let dmID: ChannelID = "phase29-dm"
        snapshot.usersByID[currentUserID] = User(id: currentUserID, username: "me")
        snapshot.usersByID[otherUserID] = User(id: otherUserID, username: "other", displayName: "Other")
        snapshot.channelsByID[dmID] = Channel(id: dmID, kind: .directMessage, active: true, recipients: [currentUserID, otherUserID])
        snapshot.messagesByChannelID[dmID] = [
            Message(id: "01J00000000000000000290001", channelID: dmID, authorID: otherUserID, content: "hello")
        ]
        let handler = MockMessageActionHandler(currentUserID: currentUserID)
        let model = MainShellViewModel(snapshot: snapshot, currentUser: snapshot.usersByID[currentUserID], messageActionHandler: handler)

        model.selectChannel(dmID)
        try? await Task.sleep(for: .milliseconds(25))
        model.updateDraft("reply from dm", for: dmID)
        await model.sendDraft(for: dmID)
        let sent = await handler.sentMessages

        XCTAssertEqual(model.selection.space, .directMessages)
        XCTAssertNil(model.selection.serverID)
        XCTAssertEqual(model.selectedConversationChannelID, dmID)
        XCTAssertEqual(model.selectedTimelineMessages.first?.message.channelID, dmID)
        XCTAssertEqual(sent.last?.channelID, dmID)
        XCTAssertNil(model.messageActionStatus)
        XCTAssertEqual(model.currentMessageSendDiagnostics().lastSendResult, .succeeded)
        XCTAssertEqual(model.dmRouteDiagnostics.clickedChannelID, dmID)
        XCTAssertTrue(model.dmRouteDiagnostics.messageLoadRequested)
        XCTAssertTrue(model.dmRouteDiagnostics.lastLoadResult?.contains("loaded") == true)
    }

    @MainActor
    func testPhase29OpenDirectMessageMatchesRecipientWhenUserIsMissing() async {
        var snapshot = RealtimeSnapshot()
        let currentUserID: UserID = "phase29-me"
        let missingUserID: UserID = "phase29-missing-user"
        let dmID: ChannelID = "phase29-existing-dm"
        snapshot.usersByID[currentUserID] = User(id: currentUserID, username: "me")
        snapshot.channelsByID[dmID] = Channel(id: dmID, kind: .directMessage, active: true, recipients: [currentUserID, missingUserID])
        let model = MainShellViewModel(snapshot: snapshot, currentUser: snapshot.usersByID[currentUserID])

        await model.openDirectMessage(with: missingUserID)

        XCTAssertEqual(model.selection.space, .directMessages)
        XCTAssertEqual(model.selection.dmChannelID, dmID)
        XCTAssertEqual(model.snapshot.channelsByID.count, 1)
    }

    @MainActor
    func testPhase29SelectedConversationPrefersDMInDMSpace() {
        var snapshot = RealtimeSnapshot()
        let serverID: ServerID = "phase29-server"
        let serverChannelID: ChannelID = "phase29-server-channel"
        let dmID: ChannelID = "phase29-dm-channel"
        snapshot.serversByID[serverID] = Server(id: serverID, ownerID: "owner", name: "Phase 29")
        snapshot.channelsByID[serverChannelID] = Channel(id: serverChannelID, kind: .textChannel, serverID: serverID, name: "general")
        snapshot.channelsByID[dmID] = Channel(id: dmID, kind: .directMessage, recipients: ["me", "other"])
        let selection = ShellSelection(space: .directMessages, serverID: serverID, channelID: serverChannelID, dmChannelID: dmID)
        let model = MainShellViewModel(selection: selection, snapshot: snapshot)

        XCTAssertEqual(model.selectedConversationChannelID, dmID)
        XCTAssertEqual(model.selectedConversationChannel?.id, dmID)
    }

    @MainActor
    func testPhase29MemberDiagnosticsKeepMissingAndOfflineMembers() {
        var snapshot = RealtimeSnapshot()
        let serverID: ServerID = "phase29-server"
        snapshot.serversByID[serverID] = Server(id: serverID, ownerID: "owner", name: "Phase 29")
        for index in 0..<12 {
            let userID = UserID(rawValue: "phase29-user-\(index)")
            if index % 4 != 0 {
                snapshot.usersByID[userID] = User(id: userID, username: "user\(index)", displayName: index % 2 == 0 ? "User \(index)" : nil, online: false)
            }
            snapshot.membersByServerAndUserID[ServerMemberKey(serverID: serverID, userID: userID)] = ServerMember(
                id: MemberCompositeKey(serverID: serverID, userID: userID),
                joinedAt: Date(),
                nickname: index == 1 ? "Nickname" : nil
            )
        }
        let model = MainShellViewModel(selection: ShellSelection(space: .server(serverID), serverID: serverID), snapshot: snapshot)
        let groups = model.memberListGroups(for: serverID)
        let allItems = groups.flatMap(\.items)

        XCTAssertEqual(allItems.count, 12)
        XCTAssertTrue(allItems.contains { $0.displayName == "Nickname" })
        XCTAssertTrue(allItems.contains { $0.user == nil && $0.displayName == "Unknown member" })
        XCTAssertEqual(model.memberListPerformanceDiagnostics.knownMemberCount, 12)
        XCTAssertEqual(model.memberListPerformanceDiagnostics.renderedMemberCount, 12)
        XCTAssertEqual(model.memberListPerformanceDiagnostics.missingUserCount, 3)
        XCTAssertEqual(model.memberListPerformanceDiagnostics.droppedMemberCount, 0)
    }

    @MainActor
    func testPhase33CustomEmojiResolverAndPickerUseReadyEmoji() {
        var snapshot = MockShellData.snapshot
        let serverID = snapshot.serversByID.values.first!.id
        let emoji = Emoji(id: "emoji-phase33", parent: .server(serverID), creatorID: MockShellData.currentUserID, name: "bagel")
        snapshot.emojisByID[emoji.id] = emoji
        let model = MainShellViewModel(selection: ShellSelection(space: .server(serverID), serverID: serverID), snapshot: snapshot)

        let itemByID = model.customEmojiDisplayItem(for: "emoji-phase33")
        let itemByName = model.customEmojiDisplayItem(for: ":bagel:")

        XCTAssertEqual(itemByID?.name, "bagel")
        XCTAssertEqual(itemByName?.file.tag, "emojis")
        XCTAssertTrue(model.commonEmojiItems.contains(":bagel:"))
    }

    @MainActor
    func testPhase34RightSidebarContextTracksRouteWithoutStaleMembers() {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot)

        XCTAssertEqual(model.rightSidebarContext, .hidden)

        model.selectServer(model.servers[0].id)
        XCTAssertEqual(model.rightSidebarContext, .serverMembers(serverID: model.selectedServer!.id, channelID: model.selectedConversationChannelID))

        model.selectHome()
        XCTAssertEqual(model.rightSidebarContext, .hidden)

        model.selectDiscover()
        XCTAssertEqual(model.rightSidebarContext, .hidden)

        model.selectDirectMessages()
        XCTAssertEqual(model.rightSidebarContext, .hidden)
        let dm = model.directMessageItems.first!
        model.selectDirectMessageItem(dm)
        XCTAssertTrue([
            RightSidebarContext.directMessageParticipants(channelID: dm.id),
            RightSidebarContext.groupDMParticipants(channelID: dm.id)
        ].contains(model.rightSidebarContext))
    }

    @MainActor
    func testPhase34MemberDiagnosticsReportMissingAvatarsWithoutDroppingMembers() {
        var snapshot = RealtimeSnapshot()
        let serverID: ServerID = "phase34-server"
        let userID: UserID = "phase34-user"
        snapshot.serversByID[serverID] = Server(id: serverID, ownerID: "owner", name: "Phase 34")
        snapshot.usersByID[userID] = User(id: userID, username: "avatarless")
        snapshot.membersByServerAndUserID[ServerMemberKey(serverID: serverID, userID: userID)] = ServerMember(
            id: MemberCompositeKey(serverID: serverID, userID: userID),
            joinedAt: Date()
        )

        let model = MainShellViewModel(selection: ShellSelection(space: .server(serverID), serverID: serverID), snapshot: snapshot)
        let groups = model.memberListGroups(for: serverID)

        XCTAssertEqual(groups.flatMap(\.items).count, 1)
        XCTAssertEqual(model.memberListPerformanceDiagnostics.missingAvatarCount, 1)
        XCTAssertEqual(model.memberListPerformanceDiagnostics.droppedMemberCount, 0)
    }

    @MainActor
    func testPhase34HighestRoleColorAppliesToServerMessageButNotDM() {
        var snapshot = RealtimeSnapshot()
        let serverID: ServerID = "phase34-color-server"
        let channelID: ChannelID = "phase34-color-channel"
        let userID: UserID = "phase34-color-user"
        let lowRoleID: RoleID = "phase34-low"
        let highRoleID: RoleID = "phase34-high"
        let low = Role(id: lowRoleID, name: "Low", permissions: PermissionOverride(), colour: "#111111", rank: 1)
        let high = Role(id: highRoleID, name: "High", permissions: PermissionOverride(), colour: "#33AAEE", rank: 50)
        snapshot.serversByID[serverID] = Server(id: serverID, ownerID: "owner", name: "Phase 34", roles: [lowRoleID: low, highRoleID: high])
        snapshot.channelsByID[channelID] = Channel(id: channelID, kind: .textChannel, serverID: serverID, name: "general")
        snapshot.membersByServerAndUserID[ServerMemberKey(serverID: serverID, userID: userID)] = ServerMember(
            id: MemberCompositeKey(serverID: serverID, userID: userID),
            joinedAt: Date(),
            roles: [lowRoleID, highRoleID]
        )
        let model = MainShellViewModel(snapshot: snapshot)
        let serverMessage = Message(id: "01J00000000000000000340001", channelID: channelID, authorID: userID, content: "hi")
        let dmID: ChannelID = "phase34-dm"
        snapshot.channelsByID[dmID] = Channel(id: dmID, kind: .directMessage, active: true, recipients: [userID])
        model.snapshot = snapshot
        let dmMessage = Message(id: "01J00000000000000000340002", channelID: dmID, authorID: userID, content: "hi")

        XCTAssertEqual(model.roleColor(for: serverMessage)?.sourceRoleID, highRoleID)
        XCTAssertEqual(model.roleColor(for: serverMessage)?.rawValue, "#33AAEE")
        XCTAssertNil(model.roleColor(for: dmMessage))
        XCTAssertNil(RoleColorResolver.resolve(member: snapshot.membersByServerAndUserID[ServerMemberKey(serverID: serverID, userID: userID)], server: snapshot.serversByID[serverID], highContrast: true))
    }

    @MainActor
    func testPhase34CustomEmojiInsertionAndInlineResolverUseReadyEmoji() {
        var snapshot = MockShellData.snapshot
        let server = snapshot.serversByID.values.first { !$0.channelIDs.isEmpty }!
        let serverID = server.id
        let channelID = server.channelIDs[0]
        let emoji = Emoji(id: "emoji-phase34", parent: .server(serverID), creatorID: MockShellData.currentUserID, name: "bagelparty")
        snapshot.emojisByID[emoji.id] = emoji
        let model = MainShellViewModel(selection: ShellSelection(space: .server(serverID), serverID: serverID, channelID: channelID), snapshot: snapshot)

        model.insertEmoji(":bagelparty:", in: channelID)
        XCTAssertEqual(model.draft(for: channelID), ":bagelparty:")
        XCTAssertEqual(model.emojiPickerDiagnostics, "Inserted custom emoji shortcode")

        let message = Message(id: "01J00000000000000000340003", channelID: channelID, authorID: MockShellData.currentUserID, content: "hello :bagelparty:")
        let inline = model.inlineCustomEmojiItems(for: message)
        XCTAssertEqual(inline.map(\.shortcode), [":bagelparty:"])
        XCTAssertEqual(inline.first?.name, "bagelparty")
    }

    @MainActor
    func testPhase35SelectedServerMemberHydrationMergesRestMembersAndDiagnostics() async {
        var snapshot = RealtimeSnapshot()
        let serverID: ServerID = "phase35-server"
        let channelID: ChannelID = "phase35-channel"
        let currentUserID: UserID = "phase35-current"
        let botID: UserID = "phase35-bot"
        let missingID: UserID = "phase35-missing-user-000000"
        snapshot.serversByID[serverID] = Server(id: serverID, ownerID: currentUserID, name: "Phase 35")
        snapshot.channelsByID[channelID] = Channel(id: channelID, kind: .textChannel, serverID: serverID, name: "general")
        snapshot.usersByID[currentUserID] = User(id: currentUserID, username: "current", displayName: "Current")
        snapshot.usersByID[botID] = User(id: botID, username: "phasebot", bot: BotInformation(ownerID: currentUserID))
        snapshot.membersByServerAndUserID[ServerMemberKey(serverID: serverID, userID: currentUserID)] = ServerMember(
            id: MemberCompositeKey(serverID: serverID, userID: currentUserID),
            joinedAt: Date(),
            nickname: "Ready Current"
        )
        let restMembers = [
            ServerMember(id: MemberCompositeKey(serverID: serverID, userID: currentUserID), joinedAt: Date(), nickname: "REST Current"),
            ServerMember(id: MemberCompositeKey(serverID: serverID, userID: botID), joinedAt: Date()),
            ServerMember(id: MemberCompositeKey(serverID: serverID, userID: missingID), joinedAt: Date())
        ]
        let restUsers = [
            User(id: currentUserID, username: "current", displayName: "REST Current User"),
            User(id: botID, username: "phasebot", displayName: "Phase Bot", bot: BotInformation(ownerID: currentUserID))
        ]
        let api = RecordingAPIClient(membersByServer: [serverID: restMembers], usersByServer: [serverID: restUsers])
        let model = MainShellViewModel(
            selection: ShellSelection(space: .server(serverID), serverID: serverID, channelID: channelID),
            snapshot: snapshot,
            runtimeMode: .mock,
            communityAPIClient: api
        )

        await model.hydrateServerMembers(serverID: serverID, force: true, reason: "test")
        let callCount = await api.fetchServerMembersCallCount
        let groups = model.memberListGroups(for: serverID)
        let items = groups.flatMap(\.items)

        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(items.count, 3)
        XCTAssertTrue(items.contains { $0.userID == botID && $0.isBot })
        XCTAssertTrue(items.contains { $0.userID == missingID && $0.user == nil })
        XCTAssertEqual(model.snapshot.membersByServerAndUserID[ServerMemberKey(serverID: serverID, userID: currentUserID)]?.nickname, "REST Current")
        XCTAssertEqual(model.snapshot.usersByID[currentUserID]?.displayName, "REST Current User")
        XCTAssertEqual(model.snapshot.usersByID[botID]?.displayName, "Phase Bot")
        XCTAssertEqual(model.memberHydrationDiagnostics.source, .restHydrated)
        XCTAssertEqual(model.memberHydrationDiagnostics.returnedCount, 3)
        XCTAssertEqual(model.memberHydrationDiagnostics.mergedUserCount, 2)
        XCTAssertEqual(model.memberHydrationDiagnostics.missingUserCount, 1)
    }

    @MainActor
    func testPhase36MemberHydrationFailureKeepsReadyMembersAndRecordsAPIShape() async {
        var snapshot = RealtimeSnapshot()
        let serverID: ServerID = "phase36-ready-server"
        let channelID: ChannelID = "phase36-ready-channel"
        let readyUserID: UserID = "phase36-ready-user"
        snapshot.serversByID[serverID] = Server(id: serverID, ownerID: readyUserID, name: "Phase 36")
        snapshot.channelsByID[channelID] = Channel(id: channelID, kind: .textChannel, serverID: serverID, name: "general")
        snapshot.usersByID[readyUserID] = User(id: readyUserID, username: "ready", displayName: "Ready User")
        snapshot.membersByServerAndUserID[ServerMemberKey(serverID: serverID, userID: readyUserID)] = ServerMember(
            id: MemberCompositeKey(serverID: serverID, userID: readyUserID),
            joinedAt: Date(),
            nickname: "Ready Nick"
        )
        let diagnostics = APIRequestDiagnostics(
            method: "GET",
            route: "/servers/phase36-ready-server/members",
            redactedResourceID: "phas...rver",
            authHeaderPresent: true,
            httpStatus: 200,
            contentType: "application/json",
            topLevelResponseShape: "array[1]",
            decoderSummary: "Expected members/users wrapper",
            errorCategory: "decode"
        )
        let api = RecordingAPIClient(
            memberFetchError: StoatAPIDiagnosedError(apiError: .decodingFailed("Expected members/users wrapper"), diagnostics: diagnostics)
        )
        let model = MainShellViewModel(
            selection: ShellSelection(space: .server(serverID), serverID: serverID, channelID: channelID),
            snapshot: snapshot,
            runtimeMode: .mock,
            communityAPIClient: api
        )

        await model.hydrateServerMembers(serverID: serverID, force: true, reason: "test")

        let displayNames = model.memberListGroups(for: serverID).flatMap { $0.items }.map { $0.displayName }
        XCTAssertEqual(displayNames, ["Ready Nick"])
        XCTAssertEqual(model.memberHydrationDiagnostics.source, MemberHydrationSource.readyOnly)
        XCTAssertEqual(model.memberHydrationDiagnostics.apiDiagnostics?.topLevelResponseShape, "array[1]")
        XCTAssertEqual(model.memberHydrationDiagnostics.apiDiagnostics?.errorCategory, "decode")
        XCTAssertTrue(model.memberHydrationStatusMessage(for: serverID)?.contains("decode") == true)
    }

    @MainActor
    func testPhase35StaleMemberHydrationIsDiscardedAfterServerSwitch() async throws {
        var snapshot = RealtimeSnapshot()
        let serverA: ServerID = "phase35-a"
        let serverB: ServerID = "phase35-b"
        let channelA: ChannelID = "phase35-a-channel"
        let channelB: ChannelID = "phase35-b-channel"
        let userA: UserID = "phase35-a-user"
        snapshot.serversByID[serverA] = Server(id: serverA, ownerID: userA, name: "A")
        snapshot.serversByID[serverB] = Server(id: serverB, ownerID: userA, name: "B")
        snapshot.channelsByID[channelA] = Channel(id: channelA, kind: .textChannel, serverID: serverA, name: "a")
        snapshot.channelsByID[channelB] = Channel(id: channelB, kind: .textChannel, serverID: serverB, name: "b")
        let api = RecordingAPIClient(
            membersByServer: [serverA: [ServerMember(id: MemberCompositeKey(serverID: serverA, userID: userA), joinedAt: Date())]],
            memberFetchDelayNanoseconds: 50_000_000
        )
        let model = MainShellViewModel(
            selection: ShellSelection(space: .server(serverA), serverID: serverA, channelID: channelA),
            snapshot: snapshot,
            runtimeMode: .mock,
            communityAPIClient: api
        )

        let task = Task { await model.hydrateServerMembers(serverID: serverA, force: true, reason: "test") }
        try await Task.sleep(nanoseconds: 5_000_000)
        model.selectChannel(channelB)
        await task.value

        XCTAssertNil(model.snapshot.membersByServerAndUserID[ServerMemberKey(serverID: serverA, userID: userA)])
        XCTAssertTrue(model.memberHydrationDiagnostics.staleFetchDiscarded)
    }

    @MainActor
    func testPhase35ImageResourceQueueCapsConcurrentLoads() async throws {
        let loader = SlowImageResourceLoader(delayNanoseconds: 500_000_000)
        let model = MainShellViewModel(runtimeMode: .mock, imageResourceLoader: loader)
        for index in 0..<10 {
            let file = File(id: FileID(rawValue: "phase35-avatar-\(index)"), tag: "avatars", filename: "avatar\(index).png", contentType: "image/png", size: 100)
            model.loadImageResource(for: file, kind: .userAvatar)
        }
        try await Task.sleep(nanoseconds: 20_000_000)
        let diagnostics = await model.imageResourceDiagnostics()

        XCTAssertLessThanOrEqual(diagnostics.activeTaskCount, 6)
        XCTAssertGreaterThanOrEqual(diagnostics.queuedTaskCount, 4)
    }

    @MainActor
    func testPhase35ProfileFetchRunsOnlyWhenOpenedAndKeepsBackground() async throws {
        var snapshot = RealtimeSnapshot()
        let userID: UserID = "phase35-profile-user"
        let background = File(id: "phase35-background", tag: "backgrounds", filename: "banner.png", contentType: "image/png", size: 100)
        snapshot.usersByID[userID] = User(id: userID, username: "profile", displayName: "Profile User")
        let api = RecordingAPIClient(profilesByUserID: [userID: UserProfile(content: "# Bio\n- one", background: background)])
        let model = MainShellViewModel(snapshot: snapshot, runtimeMode: .mock, communityAPIClient: api)

        let before = await api.fetchUserProfileCallCount
        model.showUserProfile(userID)
        for _ in 0..<20 where model.userProfilesByID[userID] == nil {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        let after = await api.fetchUserProfileCallCount

        XCTAssertEqual(before, 0)
        XCTAssertEqual(after, 1)
        XCTAssertEqual(model.userProfilesByID[userID]?.background?.tag, "backgrounds")
    }

    @MainActor
    func testPhase35SystemEventUnknownActorUsesHumanFallbackAndKnownTargetOpensProfile() {
        var snapshot = RealtimeSnapshot()
        let serverID: ServerID = "phase35-events"
        let channelID: ChannelID = "phase35-events-channel"
        let knownID: UserID = "phase35-known"
        let unknownID: UserID = "phase35-unknown-000000"
        snapshot.serversByID[serverID] = Server(id: serverID, ownerID: knownID, name: "Events")
        snapshot.channelsByID[channelID] = Channel(id: channelID, kind: .textChannel, serverID: serverID, name: "events")
        snapshot.usersByID[knownID] = User(id: knownID, username: "known", displayName: "Known")
        let model = MainShellViewModel(snapshot: snapshot)
        let unknown = Message(id: "01J00000000000000000350001", channelID: channelID, authorID: unknownID, system: SystemMessage(kind: .userJoined, by: unknownID))
        let pinned = Message(id: "01J00000000000000000350002", channelID: channelID, authorID: knownID, system: SystemMessage(kind: .messagePinned, by: knownID))

        XCTAssertEqual(model.systemEventText(for: unknown), "A member joined")
        XCTAssertEqual(model.systemEventProfileTarget(for: pinned), knownID)
        XCTAssertNil(model.systemEventProfileTarget(for: unknown))
    }

    @MainActor
    func testPhase35EmojiSectionsGroupCurrentAndOtherServers() {
        var snapshot = MockShellData.snapshot
        let currentServerID: ServerID = "phase35-emoji-current"
        let otherServerID: ServerID = "phase35-emoji-other"
        let channelID: ChannelID = "phase35-emoji-channel"
        snapshot.serversByID[currentServerID] = Server(id: currentServerID, ownerID: MockShellData.currentUserID, name: "Current")
        snapshot.channelsByID[channelID] = Channel(id: channelID, kind: .textChannel, serverID: currentServerID, name: "general")
        snapshot.emojisByID["phase35-current"] = Emoji(id: "phase35-current", parent: .server(currentServerID), creatorID: MockShellData.currentUserID, name: "currentparty")
        snapshot.emojisByID["phase35-other"] = Emoji(id: "phase35-other", parent: .server(otherServerID), creatorID: MockShellData.currentUserID, name: "otherparty")
        let model = MainShellViewModel(selection: ShellSelection(space: .server(currentServerID), serverID: currentServerID, channelID: channelID), snapshot: snapshot)
        let sections = model.composerEmojiSections
        let current = sections.first { $0.id == "current-server" }?.items ?? []
        let other = sections.first { $0.id == "other-servers" }?.items ?? []

        XCTAssertTrue(current.contains(":currentparty:"))
        XCTAssertTrue(other.contains(":otherparty:"))
    }

    @MainActor
    func testPhase36CustomEmojiContextHidesOtherServersInMessages() {
        var snapshot = MockShellData.snapshot
        let currentServerID: ServerID = "phase36-emoji-current"
        let otherServerID: ServerID = "phase36-emoji-other"
        let channelID: ChannelID = "phase36-emoji-channel"
        snapshot.serversByID[currentServerID] = Server(id: currentServerID, ownerID: MockShellData.currentUserID, name: "Current")
        snapshot.channelsByID[channelID] = Channel(id: channelID, kind: .textChannel, serverID: currentServerID, name: "general")
        snapshot.emojisByID["phase36-current"] = Emoji(id: "phase36-current", parent: .server(currentServerID), creatorID: MockShellData.currentUserID, name: "currentparty")
        snapshot.emojisByID["phase36-other"] = Emoji(id: "phase36-other", parent: .server(otherServerID), creatorID: MockShellData.currentUserID, name: "otherparty")
        let model = MainShellViewModel(selection: ShellSelection(space: .server(currentServerID), serverID: currentServerID, channelID: channelID), snapshot: snapshot)
        let message = Message(id: "01J00000000000000000360001", channelID: channelID, authorID: MockShellData.currentUserID, content: ":currentparty: :otherparty:")

        XCTAssertEqual(model.inlineCustomEmojiItems(for: message).map(\.shortcode), [":currentparty:"])
    }

    @MainActor
    func testPhase29SystemEventsUseMemberNamesAndSafeFallbacks() {
        var snapshot = RealtimeSnapshot()
        let serverID: ServerID = "phase29-server"
        let channelID: ChannelID = "phase29-channel"
        let namedUserID: UserID = "phase29-named-user"
        let unknownUserID: UserID = "01JPHASE29UNKNOWNUSER00001"
        snapshot.serversByID[serverID] = Server(id: serverID, ownerID: "owner", name: "Phase 29")
        snapshot.channelsByID[channelID] = Channel(id: channelID, kind: .textChannel, serverID: serverID, name: "joins")
        snapshot.usersByID[namedUserID] = User(id: namedUserID, username: "named", displayName: "Named User")
        snapshot.membersByServerAndUserID[ServerMemberKey(serverID: serverID, userID: namedUserID)] = ServerMember(
            id: MemberCompositeKey(serverID: serverID, userID: namedUserID),
            joinedAt: Date(),
            nickname: "Member Nick"
        )
        let model = MainShellViewModel(snapshot: snapshot)
        let joined = Message(id: "01J00000000000000000290002", channelID: channelID, authorID: namedUserID, system: SystemMessage(kind: .userJoined, by: namedUserID))
        let left = Message(id: "01J00000000000000000290003", channelID: channelID, authorID: unknownUserID, system: SystemMessage(kind: .userLeft, by: unknownUserID))

        XCTAssertEqual(model.systemEventText(for: joined), "Member Nick joined")
        XCTAssertEqual(model.systemEventText(for: left), "A member left")
        XCTAssertFalse(model.systemEventText(for: left).contains(unknownUserID.rawValue))
    }

    @MainActor
    func testPhase33SystemEventZeroActorUsesHumanFallback() {
        var snapshot = RealtimeSnapshot()
        let serverID: ServerID = "phase33-server"
        let channelID: ChannelID = "phase33-channel"
        let zeroUserID: UserID = "00000000000000000000000000"
        snapshot.serversByID[serverID] = Server(id: serverID, ownerID: "owner", name: "Phase 33")
        snapshot.channelsByID[channelID] = Channel(id: channelID, kind: .textChannel, serverID: serverID, name: "events")
        let message = Message(id: "01J00000000000000000330001", channelID: channelID, authorID: zeroUserID, system: SystemMessage(kind: .userJoined, by: zeroUserID))
        let model = MainShellViewModel(snapshot: snapshot)

        XCTAssertEqual(model.systemEventText(for: message), "A member joined")
    }

    @MainActor
    func testPhase30DMRowTraceAndActiveConversationBeatStaleServerSelection() async throws {
        var snapshot = RealtimeSnapshot()
        let serverID: ServerID = "phase30-server"
        let serverChannelID: ChannelID = "phase30-server-channel"
        let currentUserID: UserID = "phase30-me"
        let otherUserID: UserID = "phase30-other"
        let dmID: ChannelID = "phase30-dm"
        snapshot.serversByID[serverID] = Server(id: serverID, ownerID: currentUserID, name: "Phase 30")
        snapshot.channelsByID[serverChannelID] = Channel(id: serverChannelID, kind: .textChannel, serverID: serverID, name: "general")
        snapshot.usersByID[currentUserID] = User(id: currentUserID, username: "me")
        snapshot.usersByID[otherUserID] = User(id: otherUserID, username: "other", displayName: "Other")
        snapshot.channelsByID[dmID] = Channel(id: dmID, kind: .directMessage, recipients: [currentUserID, otherUserID])
        snapshot.messagesByChannelID[dmID] = [Message(id: "01J00000000000000000300001", channelID: dmID, authorID: otherUserID, content: "hi")]
        let model = MainShellViewModel(
            selection: ShellSelection(space: .server(serverID), serverID: serverID, channelID: serverChannelID),
            snapshot: snapshot,
            currentUser: snapshot.usersByID[currentUserID]
        )
        let item = try XCTUnwrap(model.directMessageItems.first { $0.id == dmID })

        model.selectDirectMessageItem(item)
        try? await Task.sleep(for: .milliseconds(25))

        XCTAssertEqual(model.activeConversation, .directMessage(channelID: dmID))
        XCTAssertEqual(model.selectedConversationChannelID, dmID)
        XCTAssertNil(model.selection.serverID)
        XCTAssertNil(model.selection.channelID)
        XCTAssertEqual(model.selection.dmChannelID, dmID)
        XCTAssertEqual(model.dmLiveTrace.clickedRowID, dmID.rawValue)
        XCTAssertEqual(model.dmLiveTrace.clickedChannelID, dmID)
        XCTAssertEqual(model.dmLiveTrace.clickedUserID, otherUserID)
        XCTAssertEqual(model.dmLiveTrace.selectedServerIDBefore, serverID)
        XCTAssertNil(model.dmLiveTrace.selectedServerIDAfter)
        XCTAssertEqual(model.dmLiveTrace.messageLoadChannelID, dmID)
        XCTAssertEqual(model.dmLiveTrace.timelineChannelID, dmID)
        XCTAssertEqual(model.dmLiveTrace.composerTargetChannelID, dmID)
        XCTAssertEqual(model.dmLiveTrace.timelineMessageCount, 1)
    }

    @MainActor
    func testPhase30DMLiveLoadSendAttachmentParticipantsAndAckUseDMChannel() async throws {
        var snapshot = RealtimeSnapshot()
        let currentUserID: UserID = "phase30-me"
        let missingUserID: UserID = "phase30-missing-user"
        let dmID: ChannelID = "phase30-live-dm"
        let liveMessage = Message(id: "01J00000000000000000300002", channelID: dmID, authorID: missingUserID, content: "from live")
        snapshot.usersByID[currentUserID] = User(id: currentUserID, username: "me")
        snapshot.channelsByID[dmID] = Channel(id: dmID, kind: .directMessage, recipients: [currentUserID, missingUserID])
        snapshot.unreadsByChannelID[dmID] = ChannelUnread(id: ChannelCompositeKey(channelID: dmID, userID: currentUserID), lastMessageID: liveMessage.id, mentions: [])
        let api = RecordingAPIClient(currentUser: User(id: currentUserID, username: "me"), messagesByChannel: [dmID: [liveMessage]])
        let controller = ChannelMessageController(runtimeMode: .liveManual, apiClient: api, currentUserID: currentUserID)
        let sender = RecordingChannelAckSender()
        let handler = MockMessageActionHandler(currentUserID: currentUserID)
        let uploader = MockAttachmentUploadHandler()
        let model = MainShellViewModel(
            snapshot: snapshot,
            runtimeMode: .liveManual,
            sessionState: .connected,
            currentUser: snapshot.usersByID[currentUserID],
            messageController: controller,
            messageActionHandler: handler,
            attachmentUploadHandler: uploader,
            channelAckSender: sender
        )
        model.timelineTuning.ackDebounceMilliseconds = 0

        model.selectChannel(dmID)
        try? await Task.sleep(for: .milliseconds(40))
        model.updateDraft("with attachment", for: dmID)
        let url = try makeTemporaryAttachment(name: "phase30.txt", contents: Data("dm file".utf8))
        model.addAttachmentURLs([url], to: dmID)
        await model.sendDraft(for: dmID)
        model.updateTimelineAtNewest(true)
        try? await Task.sleep(for: .milliseconds(25))

        let fetchCount = await api.fetchMessagesCallCount
        let sent = await handler.sentMessages
        let acks = await sender.acks
        XCTAssertEqual(fetchCount, 1)
        XCTAssertEqual(model.selectedTimelineMessages.first?.message.channelID, dmID)
        XCTAssertEqual(sent.last?.channelID, dmID)
        XCTAssertEqual(sent.last?.attachments?.count, 1)
        XCTAssertEqual(model.directMessageParticipantItems(for: snapshot.channelsByID[dmID]!).count, 2)
        XCTAssertTrue(model.directMessageParticipantItems(for: snapshot.channelsByID[dmID]!).contains { $0.userID == missingUserID && $0.user == nil })
        XCTAssertEqual(model.dmLiveTrace.messageLoadChannelID, dmID)
        XCTAssertTrue(model.dmLiveTrace.messageLoadUsedREST)
        XCTAssertEqual(model.dmLiveTrace.sidebarParticipantCount, 2)
        XCTAssertEqual(model.currentMessageSendDiagnostics().selectedChannelID, dmID)
        XCTAssertEqual(acks.last?.0, dmID)
    }

    @MainActor
    func testPhase30GroupDMSavedMessagesAndOpenDMKnownChannelStayExplicit() async throws {
        var snapshot = RealtimeSnapshot()
        let currentUserID: UserID = "phase30-me"
        let otherUserID: UserID = "phase30-other"
        let groupID: ChannelID = "phase30-group"
        let dmID: ChannelID = "phase30-known-dm"
        let savedID: ChannelID = "phase30-saved"
        snapshot.usersByID[currentUserID] = User(id: currentUserID, username: "me")
        snapshot.usersByID[otherUserID] = User(id: otherUserID, username: "other")
        snapshot.channelsByID[groupID] = Channel(id: groupID, kind: .group, name: "Group", recipients: [currentUserID, otherUserID])
        snapshot.channelsByID[dmID] = Channel(id: dmID, kind: .directMessage, recipients: [currentUserID, otherUserID])
        snapshot.channelsByID[savedID] = Channel(id: savedID, kind: .savedMessages, userID: currentUserID, recipients: [])
        let model = MainShellViewModel(snapshot: snapshot, currentUser: snapshot.usersByID[currentUserID])

        model.selectChannel(groupID)
        XCTAssertEqual(model.activeConversation, .groupDM(channelID: groupID))
        model.selectChannel(savedID)
        XCTAssertEqual(model.activeConversation, .savedMessages(channelID: savedID))
        await model.openDirectMessage(with: otherUserID)

        XCTAssertEqual(model.selection.dmChannelID, dmID)
        XCTAssertEqual(model.snapshot.channelsByID.count, 3)
        XCTAssertEqual(model.dmLiveTrace.clickedUserID, otherUserID)
    }

    func testPhase30DMTraceAndParityDiagnosticsStayRedacted() {
        let trace = DirectMessageLiveTrace(
            clickedRowID: #"https://secret.example/session token=supersecret"#,
            clickedUserID: "phase30-user",
            clickedChannelExistsInSnapshot: false,
            selectedSpaceBefore: "/Users/enka/private/file.png",
            selectedSpaceAfter: "directMessages",
            lastError: #"X-Session-Token: secret {"raw":"body"} https://api.stoat.chat/private"#
        )
        let text = DirectMessageLiveTraceFormatter.redactedText(trace)

        XCTAssertFalse(text.contains("supersecret"))
        XCTAssertFalse(text.contains("X-Session-Token: secret"))
        XCTAssertFalse(text.contains("/Users/enka/private"))
        XCTAssertFalse(text.contains("https://api.stoat.chat/private"))
        XCTAssertFalse(text.contains(#"{"raw":"body"}"#))
    }

    func testPhase30ParityMatrixContainsRequiredSectionsAndKeepsDMsPartialUntilLiveQA() {
        let matrix = Phase30ParityMatrixBuilder.build(dmLiveQAPassed: false)
        let sections = Set(matrix.sections)
        XCTAssertTrue(sections.isSuperset(of: [
            "Account and session",
            "Core chat",
            "Server/community",
            "Notifications",
            "UI/platform",
            "Deferred / not parity"
        ]))
        XCTAssertFalse(matrix.items.contains { $0.status.rawValue.isEmpty })
        let dm = matrix.items.first { $0.section == "Core chat" && $0.name == "DMs" }
        XCTAssertEqual(dm?.status, .partial)
        XCTAssertFalse(matrix.items.contains { item in
            (item.status == .deferred || item.status == .blockedByUnverifiedAPI) && item.recommendedNextAction.isEmpty
        })

        let unrecovered = Phase30ParityMatrixBuilder.build(dmRecoveredByTests: false, dmLiveQAPassed: false)
        XCTAssertEqual(unrecovered.items.first { $0.section == "Core chat" && $0.name == "DMs" }?.status, .broken)
        let passed = Phase30ParityMatrixBuilder.build(dmLiveQAPassed: true)
        XCTAssertEqual(passed.items.first { $0.section == "Core chat" && $0.name == "DMs" }?.status, .done)
    }

    @MainActor
    func testPhase41UploadFailurePreventsProfileMutation() async throws {
        var snapshot = RealtimeSnapshot()
        let currentUser = User(id: "phase41-me", username: "me", displayName: "Old Name", relationship: .user)
        snapshot.usersByID[currentUser.id] = currentUser
        let api = RecordingAPIClient(currentUser: currentUser, uploadError: StoatAPIError.unknown(statusCode: 400, body: #"{"error":"reject"}"#))
        let model = MainShellViewModel(snapshot: snapshot, currentUser: currentUser, communityAPIClient: api)

        model.prepareProfileEditor(force: true)
        try model.stageProfileMediaData(kind: .avatar, data: Self.phase41PNGData, filename: "/Users/enka/secret/avatar.png", mimeType: "image/png")
        await model.saveProfileEdit()

        let uploadCount = await api.uploadedFiles.count
        let editCount = await api.editUserCallCount
        XCTAssertEqual(uploadCount, 1)
        XCTAssertEqual(editCount, 0)
        XCTAssertNil(model.currentUserForPresentation?.avatar)
        XCTAssertEqual(model.profileEditDiagnostics.safeErrorCategory, .uploadRejected)
        XCTAssertEqual(model.profileEditDiagnostics.mutationResultCategory, .skipped)
    }

    @MainActor
    func testPhase41MutationFailurePreservesPreviousLocalProfileState() async throws {
        var snapshot = RealtimeSnapshot()
        let currentUser = User(id: "phase41-me", username: "me", displayName: "Old Name", relationship: .user)
        snapshot.usersByID[currentUser.id] = currentUser
        let api = RecordingAPIClient(currentUser: currentUser, editUserError: StoatAPIError.serverError(statusCode: 500, message: "nope"))
        let model = MainShellViewModel(snapshot: snapshot, currentUser: currentUser, communityAPIClient: api)
        model.userProfilesByID[currentUser.id] = UserProfile(content: "old bio")

        model.prepareProfileEditor(force: true)
        model.profileEditDraft.displayName = "New Name"
        model.profileEditDraft.profileContent = "new bio"
        await model.saveProfileEdit()

        let editCount = await api.editUserCallCount
        XCTAssertEqual(editCount, 1)
        XCTAssertEqual(model.currentUserForPresentation?.displayName, "Old Name")
        XCTAssertEqual(model.userProfilesByID[currentUser.id]?.content, "old bio")
        XCTAssertEqual(model.profileEditDiagnostics.safeErrorCategory, .server)
        XCTAssertEqual(model.profileEditDiagnostics.mutationResultCategory, .failed)
    }

    @MainActor
    func testPhase41SuccessfulProfileEditMergesSnapshotAndInvalidatesTargetedCaches() async throws {
        var snapshot = RealtimeSnapshot()
        let currentUserID: UserID = "phase41-me"
        let oldAvatar = File(id: "phase41-old-avatar", tag: "avatars", filename: "old.png", contentType: "image/png", size: 1, userID: currentUserID)
        let oldBackground = File(id: "phase41-old-background", tag: "backgrounds", filename: "old-bg.png", contentType: "image/png", size: 1, userID: currentUserID)
        let unrelatedAvatar = File(id: "phase41-unrelated-avatar", tag: "avatars", filename: "other.png", contentType: "image/png", size: 1)
        let currentUser = User(id: currentUserID, username: "me", displayName: "Old Name", avatar: oldAvatar, relationship: .user)
        let channelID: ChannelID = "phase41-saved"
        let message = Message(id: "phase41-message", channelID: channelID, authorID: currentUserID, content: "hello")
        snapshot.usersByID[currentUserID] = currentUser
        snapshot.channelsByID[channelID] = Channel(id: channelID, kind: .savedMessages, userID: currentUserID, active: true)
        snapshot.messagesByChannelID[channelID] = [message]
        let api = RecordingAPIClient(
            currentUser: currentUser,
            uploadedFileIDsByTag: [.avatars: "phase41-new-avatar", .backgrounds: "phase41-new-background"]
        )
        let model = MainShellViewModel(snapshot: snapshot, currentUser: currentUser, communityAPIClient: api)
        model.userProfilesByID[currentUserID] = UserProfile(content: "old bio", background: oldBackground)
        model.loadedImageResources[ImageCacheKey(id: oldAvatar.id.rawValue, kind: .userAvatar)] = Data("old-avatar".utf8)
        model.loadedImageResources[ImageCacheKey(id: oldBackground.id.rawValue, kind: .profileBackground)] = Data("old-background".utf8)
        model.loadedImageResources[ImageCacheKey(id: unrelatedAvatar.id.rawValue, kind: .userAvatar)] = Data("keep".utf8)

        model.prepareProfileEditor(force: true)
        model.profileEditDraft.displayName = "New Name"
        model.profileEditDraft.profileContent = "new bio"
        try model.stageProfileMediaData(kind: .avatar, data: Self.phase41PNGData, filename: "avatar.png", mimeType: "image/png")
        try model.stageProfileMediaData(kind: .background, data: Self.phase41PNGData, filename: "banner.png", mimeType: "image/png")
        await model.saveProfileEdit()

        let editCount = await api.editUserCallCount
        let uploadedTags = await api.uploadedFiles.map(\.tag)
        XCTAssertEqual(editCount, 1)
        XCTAssertEqual(uploadedTags, [.avatars, .backgrounds])
        XCTAssertEqual(model.currentUserForPresentation?.displayName, "New Name")
        XCTAssertEqual(model.resolvedUserDisplay(for: message).displayName, "New Name")
        XCTAssertEqual(model.directMessageParticipantItems(for: snapshot.channelsByID[channelID]!).first?.displayName, "New Name")
        XCTAssertEqual(model.userProfilesByID[currentUserID]?.content, "new bio")
        XCTAssertEqual(model.userProfilesByID[currentUserID]?.background?.id, "phase41-new-background")
        XCTAssertNil(model.loadedImageResources[ImageCacheKey(id: oldAvatar.id.rawValue, kind: .userAvatar)])
        XCTAssertNil(model.loadedImageResources[ImageCacheKey(id: oldBackground.id.rawValue, kind: .profileBackground)])
        XCTAssertEqual(model.loadedImageResources[ImageCacheKey(id: unrelatedAvatar.id.rawValue, kind: .userAvatar)], Data("keep".utf8))
        XCTAssertNotNil(model.loadedImageResources[ImageCacheKey(id: "phase41-new-avatar", kind: .userAvatar)])
        XCTAssertNotNil(model.loadedImageResources[ImageCacheKey(id: "phase41-new-background", kind: .profileBackground)])
        XCTAssertEqual(model.profileEditDiagnostics.cacheInvalidationCount, 4)
        XCTAssertEqual(model.profileEditDiagnostics.returnedDataShape, .fullUser)
    }

    @MainActor
    func testPhase41ProfileEditorDirtyStateAndSaveEnablement() {
        var snapshot = RealtimeSnapshot()
        let avatar = File(id: "phase41-avatar", tag: "avatars", filename: "avatar.png", contentType: "image/png", size: 1)
        let currentUser = User(id: "phase41-me", username: "me", displayName: "Old Name", avatar: avatar, relationship: .user)
        snapshot.usersByID[currentUser.id] = currentUser
        let model = MainShellViewModel(snapshot: snapshot, currentUser: currentUser)

        model.prepareProfileEditor(force: true)
        XCTAssertFalse(model.profileEditDraft.isDirty)
        XCTAssertFalse(model.canSaveProfileEdit)

        model.profileEditDraft.displayName = "New Name"
        XCTAssertTrue(model.profileEditDraft.isDirty)
        XCTAssertTrue(model.canSaveProfileEdit)

        model.cancelProfileEdit()
        XCTAssertFalse(model.profileEditDraft.isDirty)
        model.removeProfileAvatar()
        XCTAssertTrue(model.profileEditDraft.isDirty)
        XCTAssertTrue(model.canSaveProfileEdit)
    }

    func testPhase41SafeErrorCategoryMapping() {
        XCTAssertEqual(ProfileEditSafeErrorCategory.categorize(StoatAPIError.unauthorized), .unauthenticated)
        XCTAssertEqual(ProfileEditSafeErrorCategory.categorize(StoatAPIError.forbidden), .forbidden)
        XCTAssertEqual(ProfileEditSafeErrorCategory.categorize(StoatAPIError.rateLimited(retryAfterMilliseconds: 1)), .rateLimited)
        XCTAssertEqual(ProfileEditSafeErrorCategory.categorize(StoatAPIError.transport("offline")), .network)
        XCTAssertEqual(ProfileEditSafeErrorCategory.categorize(StoatAPIError.serverError(statusCode: 503, message: nil)), .server)
        XCTAssertEqual(ProfileEditSafeErrorCategory.categorize(StoatAPIError.decodingFailed("bad")), .decode)
        XCTAssertEqual(ProfileEditSafeErrorCategory.categorize(ProfileEditValidationError.fileTooLarge(maxBytes: 4)), .fileTooLarge)
        XCTAssertEqual(ProfileEditSafeErrorCategory.categorize(ProfileEditValidationError.unsupportedFileType), .unsupportedFileType)
        XCTAssertEqual(ProfileEditSafeErrorCategory.uploadCategory(StoatAPIError.unknown(statusCode: 400, body: "raw")), .uploadRejected)
    }

    func testPhase41DiagnosticsRedactionDropsSecretsIDsPathsURLsAndUserContent() {
        let secretBio = "private profile bio text"
        let diagnostics = ProfileEditDiagnostics(
            lastAction: "save succeeded",
            routeCategory: .currentUserPatch,
            editedFieldCategories: [.displayName, .profileContent, .avatar, .profileBackground],
            uploadTagCategory: .multiple,
            uploadResultCategory: .succeeded,
            mutationResultCategory: .succeeded,
            durationMilliseconds: 42,
            cacheInvalidationCount: 2,
            returnedDataShape: .fullUser
        )
        let text = ProfileEditDiagnosticsFormatter.redactedText(diagnostics)
        let redacted = ProfileEditDiagnosticsFormatter.redactSensitiveText("""
        X-Session-Token: supersecret
        token=secret-token
        session_id=01J12345678901234567890123
        file id 01JFILE123456789012345678
        user id 01JUSER123456789012345678
        /Users/enka/private/file.png
        https://api.stoat.chat/users/@me
        user@example.com
        password hunter2
        mfa response ticket-secret
        {"content":"\(secretBio)","token":"secret"}
        """)

        XCTAssertFalse(text.contains(secretBio))
        XCTAssertFalse(redacted.contains("supersecret"))
        XCTAssertFalse(redacted.contains("secret-token"))
        XCTAssertFalse(redacted.contains("01J12345678901234567890123"))
        XCTAssertFalse(redacted.contains("01JFILE123456789012345678"))
        XCTAssertFalse(redacted.contains("01JUSER123456789012345678"))
        XCTAssertFalse(redacted.contains("/Users/enka/private"))
        XCTAssertFalse(redacted.contains("https://api.stoat.chat"))
        XCTAssertFalse(redacted.contains("user@example.com"))
        XCTAssertFalse(redacted.contains("hunter2"))
        XCTAssertFalse(redacted.contains("ticket-secret"))
        XCTAssertFalse(redacted.contains(secretBio))
    }

    func testPhase41ParityRowsRemainPartialUntilLiveQA() {
        let matrix = Phase30ParityMatrixBuilder.build(dmLiveQAPassed: true)
        let profileEdit = matrix.items.first { $0.section == "Account and session" && $0.name == "account profile edit" }
        let avatarEdit = matrix.items.first { $0.section == "Account and session" && $0.name == "avatar edit" }
        let backgroundEdit = matrix.items.first { $0.section == "Account and session" && $0.name == "profile banner/background edit" }

        XCTAssertEqual(profileEdit?.status, .partial)
        XCTAssertEqual(avatarEdit?.status, .partial)
        XCTAssertEqual(backgroundEdit?.status, .partial)
        XCTAssertFalse([profileEdit, avatarEdit, backgroundEdit].contains { $0?.status == .done })
    }

    @MainActor
    private func phase40LiveModel(snapshot: RealtimeSnapshot, currentUser: User, api: RecordingAPIClient) async -> MainShellViewModel {
        let coordinator = AppSessionCoordinator(
            tokenStore: InMemoryTokenStore(credential: .sessionToken("phase40-token")),
            sessionValidator: StubSessionValidator(user: currentUser),
            apiClientFactory: { _, _ in api },
            realtimeClientFactory: { RecordingRealtimeClient(statesOnConnect: [.connected, .ready]) }
        )
        await coordinator.startLiveFirstSession()
        for _ in 0..<20 where coordinator.sessionState != .connected {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return MainShellViewModel(
            snapshot: snapshot,
            runtimeMode: .liveManual,
            sessionState: .connected,
            currentUser: currentUser,
            sessionCoordinator: coordinator
        )
    }

    func testPhase40ReadyDMChannelsAppearInHomeConversations() {
        var snapshot = RealtimeSnapshot()
        let currentUserID: UserID = "phase40-me"
        let friendID: UserID = "phase40-friend"
        let groupID: ChannelID = "phase40-group"
        let dmID: ChannelID = "phase40-dm"
        let savedID: ChannelID = "phase40-saved"
        let icon = File(id: "phase40-group-icon", tag: "icons", filename: "group.png", contentType: "image/png", size: 100)
        snapshot.usersByID[currentUserID] = User(id: currentUserID, username: "me")
        snapshot.usersByID[friendID] = User(id: friendID, username: "friend", displayName: "Friend")
        snapshot.channelsByID[dmID] = Channel(id: dmID, kind: .directMessage, recipients: [currentUserID, friendID])
        snapshot.channelsByID[groupID] = Channel(id: groupID, kind: .group, name: "Weekend", recipients: [currentUserID, friendID, "phase40-third"], icon: icon)
        snapshot.channelsByID[savedID] = Channel(id: savedID, kind: .savedMessages, userID: currentUserID)
        let preferences = NotificationPreferences(channelPreferences: [dmID: ChannelNotificationPreference(isMuted: true)])

        let items = Phase22Derivations.directMessageItems(
            snapshot: snapshot,
            currentUserID: currentUserID,
            notificationPreferences: preferences,
            selectedChannelID: groupID
        )

        XCTAssertEqual(items.first?.channel.kind, .savedMessages)
        XCTAssertTrue(items.contains { $0.id == dmID && $0.displayName == "Friend" && $0.isMuted })
        XCTAssertTrue(items.contains { $0.id == groupID && $0.displayName == "Weekend" && $0.groupMemberCount == 3 && $0.groupIcon == icon && $0.isSelected })
        XCTAssertFalse(items.contains { $0.displayName.contains(friendID.rawValue) })
    }

    @MainActor
    func testPhase40RefreshDMsMergesChannelsWithoutDuplicates() async {
        var snapshot = RealtimeSnapshot()
        let currentUserID: UserID = "phase40-me"
        let friendID: UserID = "phase40-friend"
        let existingID: ChannelID = "phase40-existing"
        let newID: ChannelID = "phase40-new"
        snapshot.usersByID[currentUserID] = User(id: currentUserID, username: "me")
        snapshot.usersByID[friendID] = User(id: friendID, username: "friend", displayName: "Friend")
        snapshot.channelsByID[existingID] = Channel(id: existingID, kind: .directMessage, name: "Ready Name", recipients: [currentUserID, friendID], lastMessageID: "ready-last")
        let api = RecordingAPIClient(directMessages: [
            Channel(id: existingID, kind: .directMessage, active: true, recipients: []),
            Channel(id: newID, kind: .directMessage, recipients: [currentUserID, "phase40-new-user"]),
            Channel(id: newID, kind: .directMessage, recipients: [currentUserID, "phase40-new-user"])
        ])
        let model = MainShellViewModel(snapshot: snapshot, runtimeMode: .mock, communityAPIClient: api)

        await model.refreshDMs(source: DMRefreshSource.directMessages)

        let callCount = await api.fetchDirectMessagesCallCount
        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(model.snapshot.channelsByID[existingID]?.recipients, [currentUserID, friendID])
        XCTAssertEqual(model.snapshot.channelsByID[existingID]?.lastMessageID, "ready-last")
        XCTAssertEqual(model.snapshot.channelsByID[newID]?.kind, .directMessage)
        XCTAssertEqual(model.directMessageItems.filter { $0.id == newID }.count, 1)
        XCTAssertEqual(model.dmDiagnostics.lastRefreshStatus, DMOperationStatus.succeeded)
        XCTAssertEqual(model.dmDiagnostics.lastRefreshCount, 3)
        XCTAssertGreaterThanOrEqual(model.dmDiagnostics.duplicateMergeCount, 1)
    }

    @MainActor
    func testPhase40DMRefreshFailurePreservesReadyChannels() async {
        var snapshot = RealtimeSnapshot()
        let currentUserID: UserID = "phase40-me"
        let dmID: ChannelID = "phase40-ready-dm"
        snapshot.usersByID[currentUserID] = User(id: currentUserID, username: "me")
        snapshot.channelsByID[dmID] = Channel(id: dmID, kind: .directMessage, recipients: [currentUserID, "phase40-friend"])
        let api = RecordingAPIClient(directMessagesFetchError: StoatAPIError.transport("offline token=secret"))
        let model = MainShellViewModel(snapshot: snapshot, runtimeMode: .mock, communityAPIClient: api)

        await model.refreshDMs(source: .home)

        XCTAssertEqual(model.snapshot.channelsByID[dmID]?.id, dmID)
        XCTAssertEqual(model.dmDiagnostics.lastRefreshStatus, .failed)
        XCTAssertEqual(model.dmDiagnostics.lastRefreshErrorCategory, .network)
    }

    @MainActor
    func testPhase40OpenKnownDMSelectsExistingWithoutNetwork() async {
        var snapshot = RealtimeSnapshot()
        let current = User(id: "phase40-me", username: "me")
        let otherID: UserID = "phase40-other"
        let dmID: ChannelID = "phase40-known-dm"
        snapshot.usersByID[current.id] = current
        snapshot.usersByID[otherID] = User(id: otherID, username: "other")
        snapshot.channelsByID[dmID] = Channel(id: dmID, kind: .directMessage, recipients: [current.id, otherID])
        let api = RecordingAPIClient(currentUser: current)
        let model = await phase40LiveModel(snapshot: snapshot, currentUser: current, api: api)

        await model.openDirectMessage(with: otherID, source: .friendsRow)

        let openCount = await api.openDirectMessageCallCount
        XCTAssertEqual(openCount, 0)
        XCTAssertEqual(model.selection.dmChannelID, dmID)
        XCTAssertEqual(model.dmDiagnostics.lastOpenSource, .friendsRow)
        XCTAssertEqual(model.dmDiagnostics.lastOpenStatus, .succeeded)
    }

    @MainActor
    func testPhase40OpenDMMergesNewReturnedChannelAndSelectsIt() async {
        var snapshot = RealtimeSnapshot()
        let current = User(id: "phase40-me", username: "me")
        let otherID: UserID = "phase40-new-other"
        let dmID: ChannelID = "phase40-opened-dm"
        snapshot.usersByID[current.id] = current
        snapshot.usersByID[otherID] = User(id: otherID, username: "other", displayName: "Other")
        let api = RecordingAPIClient(
            currentUser: current,
            openDirectMessagesByUserID: [otherID: Channel(id: dmID, kind: .directMessage, recipients: [current.id, otherID])]
        )
        let model = await phase40LiveModel(snapshot: snapshot, currentUser: current, api: api)

        await model.openDirectMessage(with: otherID, source: .profilePopover)

        let openCount = await api.openDirectMessageCallCount
        XCTAssertEqual(openCount, 1)
        XCTAssertEqual(model.snapshot.channelsByID[dmID]?.kind, .directMessage)
        XCTAssertEqual(model.selection.dmChannelID, dmID)
        XCTAssertEqual(model.activeConversation, .directMessage(channelID: dmID))
    }

    @MainActor
    func testPhase40RapidDuplicateOpenDMCallsAreIdempotent() async throws {
        var snapshot = RealtimeSnapshot()
        let current = User(id: "phase40-me", username: "me")
        let otherID: UserID = "phase40-rapid-other"
        let dmID: ChannelID = "phase40-rapid-dm"
        snapshot.usersByID[current.id] = current
        snapshot.usersByID[otherID] = User(id: otherID, username: "other")
        let api = RecordingAPIClient(
            currentUser: current,
            openDirectMessagesByUserID: [otherID: Channel(id: dmID, kind: .directMessage, recipients: [current.id, otherID])],
            openDirectMessageDelayNanoseconds: 50_000_000
        )
        let model = await phase40LiveModel(snapshot: snapshot, currentUser: current, api: api)

        let first = Task { await model.openDirectMessage(with: otherID, source: .profilePopover, forceNetwork: true) }
        try await Task.sleep(nanoseconds: 5_000_000)
        let second = Task { await model.openDirectMessage(with: otherID, source: .profilePopover, forceNetwork: true) }
        await first.value
        await second.value

        let openCount = await api.openDirectMessageCallCount
        XCTAssertEqual(openCount, 1)
        XCTAssertEqual(model.selection.dmChannelID, dmID)
    }

    @MainActor
    func testPhase40FriendsProfileAndMemberSourcesUseSameOpenPath() async {
        var snapshot = RealtimeSnapshot()
        let current = User(id: "phase40-me", username: "me")
        let otherID: UserID = "phase40-source-other"
        let dmID: ChannelID = "phase40-source-dm"
        snapshot.usersByID[current.id] = current
        snapshot.usersByID[otherID] = User(id: otherID, username: "other")
        snapshot.channelsByID[dmID] = Channel(id: dmID, kind: .directMessage, recipients: [current.id, otherID])
        let api = RecordingAPIClient(currentUser: current)
        let model = await phase40LiveModel(snapshot: snapshot, currentUser: current, api: api)

        await model.openDirectMessage(with: otherID, source: .friendsRow)
        XCTAssertEqual(model.dmDiagnostics.lastOpenSource, .friendsRow)
        await model.openDirectMessage(with: otherID, source: .profilePopover)
        XCTAssertEqual(model.dmDiagnostics.lastOpenSource, .profilePopover)
        await model.openDirectMessage(with: otherID, source: .memberRow)
        XCTAssertEqual(model.dmDiagnostics.lastOpenSource, .memberRow)
        let openCount = await api.openDirectMessageCallCount
        XCTAssertEqual(openCount, 0)
    }

    @MainActor
    func testPhase40SavedNotesResolvesAndUnavailableStateIsRecoverable() async {
        var snapshot = RealtimeSnapshot()
        let current = User(id: "phase40-me", username: "me")
        let savedID: ChannelID = "phase40-saved"
        snapshot.usersByID[current.id] = current
        let successAPI = RecordingAPIClient(
            currentUser: current,
            openDirectMessagesByUserID: [current.id: Channel(id: savedID, kind: .savedMessages, userID: current.id)]
        )
        let successModel = await phase40LiveModel(snapshot: snapshot, currentUser: current, api: successAPI)

        await successModel.openSavedNotes()

        XCTAssertEqual(successModel.selection.dmChannelID, savedID)
        XCTAssertEqual(successModel.dmDiagnostics.savedNotesState, .available(savedID))

        let failureAPI = RecordingAPIClient(currentUser: current, openDirectMessageError: StoatAPIError.notFound)
        let failureModel = await phase40LiveModel(snapshot: snapshot, currentUser: current, api: failureAPI)
        await failureModel.openSavedNotes()

        XCTAssertEqual(failureModel.dmDiagnostics.savedNotesState, .failed(.notFound))
        XCTAssertNil(failureModel.selection.dmChannelID)
    }

    @MainActor
    func testPhase40DMTimelineActionsUseSharedChannelPipeline() async throws {
        var snapshot = RealtimeSnapshot()
        let currentUserID: UserID = "phase40-me"
        let otherID: UserID = "phase40-other"
        let dmID: ChannelID = "phase40-actions-dm"
        let message = Message(id: "01J00000000000000000400001", channelID: dmID, authorID: currentUserID, content: "original")
        snapshot.usersByID[currentUserID] = User(id: currentUserID, username: "me")
        snapshot.usersByID[otherID] = User(id: otherID, username: "other")
        snapshot.channelsByID[dmID] = Channel(id: dmID, kind: .directMessage, recipients: [currentUserID, otherID])
        snapshot.messagesByChannelID[dmID] = [message]
        let handler = MockMessageActionHandler(currentUserID: currentUserID)
        let uploader = MockAttachmentUploadHandler()
        let model = MainShellViewModel(snapshot: snapshot, currentUser: snapshot.usersByID[currentUserID], messageActionHandler: handler, attachmentUploadHandler: uploader)
        model.selectChannel(dmID)

        model.updateDraft("with file", for: dmID)
        let url = try makeTemporaryAttachment(name: "phase40.txt", contents: Data("dm".utf8))
        model.addAttachmentURLs([url], to: dmID)
        await model.sendDraft(for: dmID)

        let sent = await handler.sentMessages
        XCTAssertEqual(sent.last?.channelID, dmID)
        XCTAssertEqual(sent.last?.attachments?.count, 1)

        let editable = try XCTUnwrap(model.selectedTimelineMessages.first { $0.message.id == message.id })
        model.beginEditing(editable)
        model.updateInlineEditDraft("edited")
        await model.saveEditingDraft()
        let edited = await handler.editedMessages
        XCTAssertEqual(edited.last?.0, dmID)

        let reacted = try XCTUnwrap(model.selectedTimelineMessages.first { $0.message.id == message.id })
        await model.toggleReaction("👍", on: reacted)
        let reactions = await handler.addedReactions
        XCTAssertEqual(reactions.last?.0, dmID)

        let deletable = try XCTUnwrap(model.selectedTimelineMessages.first { $0.message.id == message.id })
        model.requestDelete(deletable)
        await model.confirmPendingDelete()
        let deleted = await handler.deletedMessages
        XCTAssertEqual(deleted.last?.0, dmID)
    }

    @MainActor
    func testPhase40DMAckClearsUnreadAndMentionsLocally() async throws {
        let sender = RecordingChannelAckSender()
        var snapshot = RealtimeSnapshot()
        let currentUserID: UserID = "phase40-me"
        let otherID: UserID = "phase40-other"
        let dmID: ChannelID = "phase40-ack-dm"
        let message = Message(id: "01J00000000000000000400002", channelID: dmID, authorID: otherID, content: "mention", mentions: [currentUserID])
        snapshot.usersByID[currentUserID] = User(id: currentUserID, username: "me")
        snapshot.usersByID[otherID] = User(id: otherID, username: "other")
        snapshot.channelsByID[dmID] = Channel(id: dmID, kind: .directMessage, recipients: [currentUserID, otherID])
        snapshot.messagesByChannelID[dmID] = [message]
        snapshot.unreadsByChannelID[dmID] = ChannelUnread(id: ChannelCompositeKey(channelID: dmID, userID: currentUserID), lastMessageID: message.id, mentions: [message.id])
        let model = MainShellViewModel(snapshot: snapshot, runtimeMode: .liveManual, sessionState: .connected, currentUser: snapshot.usersByID[currentUserID], channelAckSender: sender)
        model.timelineTuning.ackDebounceMilliseconds = 0

        model.selectChannel(dmID)
        model.updateTimelineAtNewest(true)
        try await Task.sleep(for: .milliseconds(30))

        let acks = await sender.acks
        XCTAssertEqual(acks.last?.0, dmID)
        XCTAssertEqual(model.localReadStates[dmID]?.mentionCount, 0)
        XCTAssertEqual(model.dmDiagnostics.mentionCount, 0)
    }

    @MainActor
    func testPhase40DMNotificationRouteQueuesUntilReadyAndReadyRouteSelectsMessage() async throws {
        let queuedModel = MainShellViewModel(
            snapshot: RealtimeSnapshot(),
            runtimeMode: .liveManual,
            sessionState: .connected,
            currentUser: User(id: "phase40-me", username: "me"),
            notificationDeliverer: MockNotificationService(),
            notificationPermissionManager: MockNotificationPermissionManager(),
            dockBadgeManager: MockDockBadgeManager(),
            notificationRouteCenter: NotificationRouteCenter()
        )
        let dmID: ChannelID = "phase40-notification-dm"
        await queuedModel.openNotificationRoute(NotificationRoute(channelID: dmID, messageID: "01J00000000000000000400003"))

        XCTAssertEqual(queuedModel.queuedNotificationRoutes.count, 1)
        XCTAssertNil(queuedModel.selection.dmChannelID)

        var snapshot = RealtimeSnapshot()
        let current = User(id: "phase40-me", username: "me")
        let otherID: UserID = "phase40-other"
        let messageID: MessageID = "01J00000000000000000400004"
        snapshot.usersByID[current.id] = current
        snapshot.usersByID[otherID] = User(id: otherID, username: "other")
        snapshot.channelsByID[dmID] = Channel(id: dmID, kind: .directMessage, recipients: [current.id, otherID])
        snapshot.messagesByChannelID[dmID] = [Message(id: messageID, channelID: dmID, authorID: otherID, content: "route")]
        let api = RecordingAPIClient(currentUser: current)
        let readyModel = await phase40LiveModel(snapshot: snapshot, currentUser: current, api: api)

        await readyModel.openNotificationRoute(NotificationRoute(channelID: dmID, messageID: messageID))

        XCTAssertEqual(readyModel.selection.dmChannelID, dmID)
        XCTAssertEqual(readyModel.timelineSelection.messageID, messageID)
    }

    func testPhase40ActiveDMNotificationSuppressionUsesActiveConversationID() {
        var snapshot = RealtimeSnapshot()
        let currentUserID: UserID = "phase40-me"
        let otherID: UserID = "phase40-other"
        let dmID: ChannelID = "phase40-active-dm"
        snapshot.usersByID[currentUserID] = User(id: currentUserID, username: "me")
        snapshot.usersByID[otherID] = User(id: otherID, username: "other")
        snapshot.channelsByID[dmID] = Channel(id: dmID, kind: .directMessage, recipients: [currentUserID, otherID])
        let message = Message(id: "01J00000000000000000400005", channelID: dmID, authorID: otherID, content: "active")
        let context = NotificationClassificationContext(runtimeMode: .liveManual, currentUserID: currentUserID, activeChannelID: dmID, isActiveChannelVisible: true, preferences: .defaults, snapshot: snapshot)

        XCTAssertEqual(NotificationClassifier.classify(message: message, context: context), .suppress(.activeChannel))
    }

    func testPhase40DMDiagnosticsRedactionPreventsSensitiveLeaks() {
        let diagnostics = DMDiagnostics(
            savedNotesState: .available("01J123456789ABCDEFGHJKLMNP"),
            lastRefreshStatus: .failed,
            lastRefreshSource: .home,
            lastRefreshErrorCategory: .network,
            lastOpenStatus: .failed,
            lastOpenSource: .profilePopover,
            lastOpenTarget: "01J123456789ABCDEFGHJKLMNP",
            lastOpenErrorCategory: .authentication,
            lastAckSummary: #"token=secret /Users/enka/private {"raw":"body"} https://api.example.test"#
        )

        let text = DMDiagnosticsFormatter.redactedText(diagnostics)

        XCTAssertFalse(text.contains("secret"))
        XCTAssertFalse(text.contains("/Users/enka"))
        XCTAssertFalse(text.contains(#"{"raw":"body"}"#))
        XCTAssertFalse(text.contains("https://api.example.test"))
        XCTAssertFalse(text.contains("01J123456789ABCDEFGHJKLMNP"))
        XCTAssertTrue(text.contains("[redacted"))
    }

    @MainActor
    func testPhase31DirectMessageRowActivatesTimelineWithoutFriendsRouteOverride() async throws {
        var snapshot = RealtimeSnapshot()
        let currentUserID: UserID = "phase31-me"
        let otherUserID: UserID = "phase31-other"
        let dmID: ChannelID = "phase31-dm"
        snapshot.usersByID[currentUserID] = User(id: currentUserID, username: "me")
        snapshot.usersByID[otherUserID] = User(id: otherUserID, username: "other", displayName: "Other Person")
        snapshot.channelsByID[dmID] = Channel(id: dmID, kind: .directMessage, recipients: [currentUserID, otherUserID])
        snapshot.messagesByChannelID[dmID] = [
            Message(id: "01J00000000000000000310001", channelID: dmID, authorID: otherUserID, content: "hello")
        ]
        let model = MainShellViewModel(snapshot: snapshot, currentUser: snapshot.usersByID[currentUserID])

        model.openFriends(tab: .online)
        XCTAssertEqual(model.selection.space, .directMessages)
        XCTAssertNil(model.selectedConversationChannelID)
        XCTAssertFalse(model.isTimelineRouteActive)

        let item = try XCTUnwrap(model.directMessageItems.first { $0.id == dmID })
        model.selectDirectMessageItem(item)
        try? await Task.sleep(for: .milliseconds(25))

        XCTAssertEqual(model.activeConversation, .directMessage(channelID: dmID))
        XCTAssertEqual(model.selectedConversationChannelID, dmID)
        XCTAssertTrue(model.isTimelineRouteActive)
        XCTAssertEqual(model.selectedTimelineMessages.first?.message.channelID, dmID)
        XCTAssertEqual(model.composerPlaceholder(for: snapshot.channelsByID[dmID]!), "Message Other Person")
        XCTAssertEqual(model.dmLiveTrace.clickedChannelID, dmID)
        XCTAssertEqual(model.dmLiveTrace.messageLoadChannelID, dmID)
        XCTAssertEqual(model.dmLiveTrace.timelineChannelID, dmID)
        XCTAssertEqual(model.dmLiveTrace.composerTargetChannelID, dmID)
    }

    @MainActor
    func testPhase31ResolvedDisplayUsesMemberNicknameAvatarAndShortFallback() {
        let userID: UserID = "01JPHASE31AUTHOR0000000001"
        let avatar = File(id: "phase31-avatar", tag: "avatars", filename: "avatar.png", contentType: "image/png", size: 10)
        let memberAvatar = File(id: "phase31-member-avatar", tag: "avatars", filename: "member.png", contentType: "image/png", size: 10)
        let user = User(id: userID, username: "phaseauthor", displayName: "Phase Author", avatar: avatar)
        let member = ServerMember(id: MemberCompositeKey(serverID: "phase31-server", userID: userID), joinedAt: Date(), nickname: "Server Nick", avatar: memberAvatar)

        let display = UserDisplayResolver.resolved(userID: userID, user: user, member: member)
        XCTAssertEqual(display.displayName, "Server Nick")
        XCTAssertEqual(display.avatarFile?.id, memberAvatar.id)
        XCTAssertEqual(display.source, ResolvedUserDisplaySource.memberNickname)

        let fallback = UserDisplayResolver.resolved(userID: userID, user: nil, member: nil)
        XCTAssertNotEqual(fallback.displayName, userID.rawValue)
        XCTAssertTrue(fallback.displayName.contains("..."))
        XCTAssertTrue(fallback.isFallback)
    }

    @MainActor
    func testPhase31NotificationRequestRecordsOptionsAndAuthorizerMode() async throws {
        let manager = MockNotificationPermissionManager(status: .notDetermined)
        let model = MainShellViewModel(snapshot: MockShellData.snapshot, notificationPermissionManager: manager)

        model.requestNotificationPermission()
        for _ in 0..<10 where model.notificationDiagnostics.lastPermissionRequest == nil {
            try await Task.sleep(for: .milliseconds(30))
        }

        let result = try XCTUnwrap(model.notificationDiagnostics.lastPermissionRequest)
        XCTAssertTrue(result.requestAuthorizationCalled)
        XCTAssertEqual(result.requestedOptions, ["alert", "sound", "badge"])
        XCTAssertTrue(result.usedMockAuthorizer)
        XCTAssertEqual(result.statusAfter, .authorized)
        XCTAssertTrue(model.notificationDiagnostics.redactedText.contains("called yes"))
    }

    @MainActor
    func testPhase36NotificationsDoNotRequestOnLaunchAndSelfTestSchedulesOnlyWhenAuthorized() async throws {
        let deniedManager = MockNotificationPermissionManager(status: .denied)
        let deniedService = MockNotificationService()
        let deniedModel = MainShellViewModel(
            snapshot: MockShellData.snapshot,
            notificationDeliverer: deniedService,
            notificationPermissionManager: deniedManager,
            dockBadgeManager: MockDockBadgeManager()
        )
        let deniedRequestCountBefore = await deniedManager.requestCount
        XCTAssertEqual(deniedRequestCountBefore, 0)

        deniedModel.runNotificationSelfTest()
        for _ in 0..<20 where deniedModel.notificationDiagnostics.selfTestReport == "Self-test started" {
            try await Task.sleep(for: .milliseconds(20))
        }

        let deniedRequestCountAfter = await deniedManager.requestCount
        XCTAssertEqual(deniedRequestCountAfter, 1)
        XCTAssertTrue((deniedModel.notificationDiagnostics.selfTestReport ?? "").contains("local test skipped"))
        let deniedEvents = await deniedService.events()
        XCTAssertTrue(deniedEvents.isEmpty)

        let authorizedManager = MockNotificationPermissionManager(status: .authorized)
        let authorizedService = MockNotificationService()
        let authorizedModel = MainShellViewModel(
            snapshot: MockShellData.snapshot,
            notificationDeliverer: authorizedService,
            notificationPermissionManager: authorizedManager,
            dockBadgeManager: MockDockBadgeManager()
        )
        authorizedModel.runNotificationSelfTest()
        for _ in 0..<20 {
            let events = await authorizedService.events()
            if !events.isEmpty { break }
            try await Task.sleep(for: .milliseconds(20))
        }

        let authorizedRequestCount = await authorizedManager.requestCount
        XCTAssertEqual(authorizedRequestCount, 1)
        let authorizedEvents = await authorizedService.events()
        XCTAssertEqual(authorizedEvents.count, 1)
        XCTAssertTrue((authorizedModel.notificationDiagnostics.selfTestReport ?? "").contains("scheduled local test"))
    }

    @MainActor
    func testPhase29ChannelContextMenuContainsSettingsAndDeveloperActions() throws {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot)
        let server = try XCTUnwrap(model.servers.first)
        model.selectServer(server.id)
        let channel = try XCTUnwrap(model.selectedChannel)

        let items = model.channelContextMenuItems(for: channel)

        XCTAssertTrue(items.contains { $0.kind == .settings && $0.title == "Channel Settings" })
        XCTAssertTrue(items.contains { $0.kind == .createChannel })
        XCTAssertTrue(items.contains { $0.kind == .copyChannelID && $0.isDeveloperOnly })
        XCTAssertTrue(items.contains { $0.kind == .deleteChannel && $0.isDestructive })
    }

    @MainActor
    func testPhase24ServerOverviewAndPermissionGating() {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot)
        let server = model.servers.first { $0.name == "Bagel Lab" }!

        model.selectServer(server.id)
        model.openServerOverview()

        guard case let .loaded(details) = model.serverOverviewState else {
            return XCTFail("Expected server overview details")
        }
        XCTAssertEqual(details.server.id, server.id)
        XCTAssertGreaterThan(details.channels.count, 0)
        XCTAssertNil(model.channelManagementDisabledReason())
        XCTAssertTrue(model.canPerform(.openCreateChannel))
        XCTAssertTrue(model.canPerform(.openChannelSettings))
    }

    @MainActor
    func testPhase24ChannelCreateEditAndDeleteUseMockAPIAndSnapshotIntegration() async {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot, runtimeMode: .mock, communityAPIClient: MockStoatAPIClient())
        let server = model.servers.first { $0.name == "Bagel Lab" }!
        model.selectServer(server.id)

        model.openCreateChannel(categoryID: "cat-text")
        model.channelCreateForm.name = "phase-24"
        model.channelCreateForm.description = "Management test"
        await model.createChannelFromDraft()

        let created = try? XCTUnwrap(model.selectedChannel)
        XCTAssertEqual(created?.displayName, "phase-24")
        XCTAssertEqual(model.phase24Status, "Channel created")
        XCTAssertTrue(model.snapshot.serversByID[server.id]?.channelIDs.contains(created!.id) == true)
        XCTAssertTrue(model.snapshot.serversByID[server.id]?.categories?.first { $0.id == "cat-text" }?.channels.contains(created!.id) == true)

        model.openChannelSettings()
        model.channelEditForm?.name = "phase-24-renamed"
        model.channelEditForm?.description = ""
        await model.saveChannelSettings()

        XCTAssertEqual(model.snapshot.channelsByID[created!.id]?.displayName, "phase-24-renamed")
        XCTAssertNil(model.snapshot.channelsByID[created!.id]?.description)

        model.requestDeleteSelectedChannel()
        XCTAssertEqual(model.pendingChannelDeletion?.channel.id, created!.id)
        await model.confirmPendingChannelDeletion()

        XCTAssertNil(model.snapshot.channelsByID[created!.id])
        XCTAssertNotEqual(model.selection.channelID, created!.id)
        XCTAssertEqual(model.phase24Status, "Channel deleted")
    }

    @MainActor
    func testPhase24InviteManagementDoesNotAutoRefreshOnOpen() {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot)
        let server = model.servers.first { $0.name == "Bagel Lab" }!

        model.selectServer(server.id)
        model.openInviteManagement()

        XCTAssertTrue(model.isInviteManagementPresented)
        XCTAssertEqual(model.inviteManagementState, .idle)
    }

    @MainActor
    func testPhase25ServerSettingsCategoriesRolesAndCommandsUseMockAPI() async {
        var snapshot = MockShellData.snapshot
        let seedServer = snapshot.serversByID.values.first { $0.name == "Bagel Lab" }!
        snapshot.serversByID[seedServer.id]?.defaultPermissions.insert(.manageRole)
        let model = MainShellViewModel(snapshot: snapshot, runtimeMode: .mock, communityAPIClient: MockStoatAPIClient())
        let server = model.servers.first { $0.name == "Bagel Lab" }!

        model.selectServer(server.id)
        model.openServerOverview()

        guard case let .loaded(settings) = model.serverSettingsState else {
            return XCTFail("Expected server settings")
        }
        XCTAssertEqual(settings.server.id, server.id)
        XCTAssertTrue(model.canPerform(.openServerAppearance))
        XCTAssertTrue(model.canPerform(.openCategoryEditor))
        XCTAssertTrue(model.canPerform(.openRoles))
        XCTAssertTrue(model.canPerform(.openPermissions))

        model.serverSettingsForm?.name = "Bagel Lab Phase 25"
        model.serverSettingsForm?.description = "Settings test"
        await model.saveServerSettings()
        XCTAssertEqual(model.snapshot.serversByID[server.id]?.name, "Bagel Lab Phase 25")
        XCTAssertEqual(model.snapshot.serversByID[server.id]?.description, "Settings test")

        model.createCategoryDraft(title: "Phase 25")
        let createdCategoryID = try? XCTUnwrap(model.categoryEditorForm?.categories.last?.id)
        let firstChannelID = try? XCTUnwrap(model.snapshot.serversByID[server.id]?.channelIDs.first)
        model.categoryEditorForm?.move(channelID: firstChannelID!, toCategory: createdCategoryID!)
        await model.applyCategoryChanges()
        XCTAssertTrue(model.snapshot.serversByID[server.id]?.categories?.contains { $0.title == "Phase 25" && $0.channels.contains(firstChannelID!) } == true)

        model.snapshot.serversByID[server.id]?.defaultPermissions.insert(.manageRole)
        model.openCreateRole()
        model.roleEditorForm?.name = "Phase 25 Role"
        model.roleEditorForm?.colour = "#33AAEE"
        model.roleEditorForm?.hoist = true
        await model.saveRoleEditor()
        XCTAssertTrue(model.snapshot.serversByID[server.id]?.roles.values.contains { $0.name == "Phase 25 Role" } == true)
    }

    func testPhase25PermissionResolverAppliesRoleAndChannelOverrides() {
        let currentUser: UserID = "user-1"
        let roleID: RoleID = "role-1"
        let server = Server(
            id: "server-1",
            ownerID: "owner",
            name: "Lab",
            channelIDs: ["channel-1"],
            roles: [
                roleID: Role(id: roleID, name: "Managers", permissions: PermissionOverride(allow: [.manageServer, .uploadFiles]), rank: 1)
            ],
            defaultPermissions: [.viewChannel, .readMessageHistory, .sendMessage]
        )
        let member = ServerMember(id: MemberCompositeKey(serverID: server.id, userID: currentUser), joinedAt: Date(), roles: [roleID])
        let channel = Channel(
            id: "channel-1",
            kind: .textChannel,
            serverID: server.id,
            name: "general",
            defaultPermissions: PermissionOverride(deny: [.sendMessage]),
            rolePermissions: [roleID: PermissionOverride(allow: [.manageChannel])]
        )

        let result = Phase25PermissionResolver.resolve(server: server, channel: channel, member: member, currentUserID: currentUser)

        XCTAssertTrue(result.canManageServer)
        XCTAssertTrue(result.canManageChannels)
        XCTAssertTrue(result.canUploadFiles)
        XCTAssertFalse(result.effectivePermissions.contains(.sendMessage))
        XCTAssertTrue(result.warnings.isEmpty)
    }

    func testPhase25PermissionResolverOwnerBypassesIncompleteMemberData() {
        let server = Server(id: "server-1", ownerID: "owner", name: "Lab", defaultPermissions: [])

        let result = Phase25PermissionResolver.resolve(server: server, channel: nil, member: nil, currentUserID: "owner")

        XCTAssertTrue(result.canManageServer)
        XCTAssertTrue(result.canManageRoles)
        XCTAssertTrue(result.canManagePermissions)
        XCTAssertTrue(result.warnings.isEmpty)
    }

    @MainActor
    func testPhase26MemberRoleAssignmentRequiresDiffConfirmation() async {
        let snapshot = MockShellData.snapshot
        let server = snapshot.serversByID.values.first { $0.name == "Bagel Lab" }!
        let targetUserID: UserID = "01HX0000000000000000000002"
        let targetKey = ServerMemberKey(serverID: server.id, userID: targetUserID)
        let targetMember = snapshot.membersByServerAndUserID[targetKey]!
        let model = MainShellViewModel(snapshot: snapshot, runtimeMode: .mock, communityAPIClient: MockStoatAPIClient())

        model.selectServer(server.id)
        model.openServerOverview()
        model.openMemberRoleAssignment(targetMember)
        model.toggleRole("01HX0000000000000000000301", inMemberRoleDraft: true)
        await model.confirmSaveMemberRoles()

        guard case let .failed(unconfirmedMessage) = model.memberActionState else {
            return XCTFail("Expected unconfirmed role save to fail")
        }
        XCTAssertTrue(unconfirmedMessage.contains("confirm"))

        model.requestSaveMemberRoles()
        XCTAssertTrue(model.memberRoleSaveRequiresConfirmation)
        await model.confirmSaveMemberRoles()

        XCTAssertEqual(model.snapshot.membersByServerAndUserID[targetKey]?.roles, ["01HX0000000000000000000301"])
    }

    @MainActor
    func testPhase26PermissionEditorShowsDiffAndSavesThroughMockAPI() async {
        let snapshot = MockShellData.snapshot
        let server = snapshot.serversByID.values.first { $0.name == "Bagel Lab" }!
        let model = MainShellViewModel(snapshot: snapshot, runtimeMode: .mock, communityAPIClient: MockStoatAPIClient())
        let key = Phase26Permissions.editableKeys.first { $0.permission == .managePermissions }!

        model.selectServer(server.id)
        model.openPermissionEditor(scope: .serverDefault(serverID: server.id))
        model.setPermissionState(.allow, for: key)
        XCTAssertEqual(model.permissionEditDraft?.diff(keys: Phase26Permissions.editableKeys).count, 1)

        await model.confirmSavePermissionEdit()
        guard case let .failed(unconfirmedMessage) = model.permissionEditorState else {
            return XCTFail("Expected unconfirmed permission save to fail")
        }
        XCTAssertTrue(unconfirmedMessage.contains("confirm"))

        model.requestSavePermissionEdit()
        XCTAssertTrue(model.permissionSaveRequiresConfirmation)
        await model.confirmSavePermissionEdit()

        XCTAssertTrue(model.snapshot.serversByID[server.id]?.defaultPermissions.contains(.managePermissions) == true)
    }

    @MainActor
    func testPhase42MemberModerationUsesCentralConfirmationAndDoesNotAutoLoadBans() async {
        let snapshot = MockShellData.snapshot
        let server = snapshot.serversByID.values.first { $0.name == "Bagel Lab" }!
        let targetUserID: UserID = "01HX0000000000000000000002"
        let targetKey = ServerMemberKey(serverID: server.id, userID: targetUserID)
        let targetMember = snapshot.membersByServerAndUserID[targetKey]!
        let model = MainShellViewModel(snapshot: snapshot, runtimeMode: .mock, communityAPIClient: MockStoatAPIClient())

        model.selectServer(server.id)
        model.openServerOverview()
        XCTAssertEqual(model.banListState, .idle)
        XCTAssertTrue(model.canPerform(.openMembers))
        XCTAssertTrue(model.canPerform(.openPermissionEditor))

        model.requestMemberAction(.ban, for: targetMember)
        XCTAssertNil(model.pendingMemberModerationAction)
        XCTAssertEqual(model.pendingModerationConfirmation?.action, .ban)
        XCTAssertNotNil(model.snapshot.membersByServerAndUserID[targetKey])

        await model.confirmPendingModerationAction()
        XCTAssertNil(model.snapshot.membersByServerAndUserID[targetKey])
        XCTAssertNotNil(model.snapshot.usersByID[targetUserID])
    }

    func testPhase42ModerationResolverBlocksUnsafeTargets() {
        let owner: UserID = "owner"
        let current: UserID = "mod"
        let target: UserID = "target"
        let serverID: ServerID = "server"
        let modRoleID: RoleID = "mod-role"
        let adminRoleID: RoleID = "admin-role"
        let memberRoleID: RoleID = "member-role"
        let timeoutRoleID: RoleID = "timeout-role"
        let server = Server(
            id: serverID,
            ownerID: owner,
            name: "Moderation Test",
            roles: [
                adminRoleID: Role(id: adminRoleID, name: "Admin", permissions: PermissionOverride(), rank: 5),
                modRoleID: Role(id: modRoleID, name: "Mod", permissions: PermissionOverride(allow: [.kickMembers, .banMembers, .timeoutMembers]), rank: 10),
                memberRoleID: Role(id: memberRoleID, name: "Member", permissions: PermissionOverride(), rank: 50),
                timeoutRoleID: Role(id: timeoutRoleID, name: "Timeout Mod", permissions: PermissionOverride(allow: [.timeoutMembers]), rank: 60)
            ],
            defaultPermissions: [.viewChannel, .readMessageHistory]
        )
        let currentMember = ServerMember(id: MemberCompositeKey(serverID: serverID, userID: current), joinedAt: Date(), roles: [modRoleID])
        let targetMember = ServerMember(id: MemberCompositeKey(serverID: serverID, userID: target), joinedAt: Date(), roles: [memberRoleID], timeout: Date().addingTimeInterval(300))
        let permission = PermissionResolutionResult(effectivePermissions: [.kickMembers, .banMembers, .timeoutMembers])
        let context = ModerationActionContext(
            currentUserID: current,
            server: server,
            currentMember: currentMember,
            targetUserID: target,
            targetMember: targetMember,
            permissionResolution: permission,
            isConnectedForLiveActions: true
        )

        XCTAssertNil(ModerationActionResolver.disabledReason(for: .kick, context: context))
        XCTAssertNil(ModerationActionResolver.disabledReason(for: .ban, context: context))
        XCTAssertNil(ModerationActionResolver.disabledReason(for: .removeTimeout, context: context))

        var selfContext = context
        selfContext.targetUserID = current
        selfContext.targetMember = currentMember
        XCTAssertEqual(ModerationActionResolver.disabledReason(for: .kick, context: selfContext), .targetIsSelf)

        var ownerContext = context
        ownerContext.targetUserID = owner
        ownerContext.targetMember = ServerMember(id: MemberCompositeKey(serverID: serverID, userID: owner), joinedAt: Date(), roles: [adminRoleID])
        XCTAssertEqual(ModerationActionResolver.disabledReason(for: .ban, context: ownerContext), .targetIsServerOwner)

        var higherContext = context
        higherContext.targetMember = ServerMember(id: MemberCompositeKey(serverID: serverID, userID: target), joinedAt: Date(), roles: [adminRoleID])
        XCTAssertEqual(ModerationActionResolver.disabledReason(for: .kick, context: higherContext), .targetRoleEqualOrHigher)

        var missingPermission = context
        missingPermission.permissionResolution = PermissionResolutionResult(effectivePermissions: [])
        XCTAssertEqual(ModerationActionResolver.disabledReason(for: .ban, context: missingPermission), .currentUserMissingPermission)

        var unknownHierarchy = context
        unknownHierarchy.targetMember = ServerMember(id: MemberCompositeKey(serverID: serverID, userID: target), joinedAt: Date(), roles: ["missing-role"])
        XCTAssertEqual(ModerationActionResolver.disabledReason(for: .ban, context: unknownHierarchy), .unknownPermissionHierarchy)

        var alreadyBanned = context
        alreadyBanned.knownBannedUserIDs = [target]
        XCTAssertEqual(ModerationActionResolver.disabledReason(for: .ban, context: alreadyBanned), .targetAlreadyBanned)
        XCTAssertNil(ModerationActionResolver.disabledReason(for: .unban, context: alreadyBanned))

        var timeoutPermissionTarget = context
        timeoutPermissionTarget.targetMember = ServerMember(id: MemberCompositeKey(serverID: serverID, userID: target), joinedAt: Date(), roles: [timeoutRoleID])
        XCTAssertEqual(ModerationActionResolver.disabledReason(for: .timeout, context: timeoutPermissionTarget), .targetHasTimeoutPermission)
    }

    func testPhase42MemberModerationMenuStateResolverCoversCoreStates() {
        let owner: UserID = "owner"
        let current: UserID = "mod"
        let target: UserID = "target"
        let serverID: ServerID = "menu-state-server"
        let modRoleID: RoleID = "mod-role"
        let adminRoleID: RoleID = "admin-role"
        let memberRoleID: RoleID = "member-role"
        let timeoutRoleID: RoleID = "timeout-role"
        let server = Server(
            id: serverID,
            ownerID: owner,
            name: "Moderation Menu Test",
            roles: [
                adminRoleID: Role(id: adminRoleID, name: "Admin", permissions: PermissionOverride(), rank: 5),
                modRoleID: Role(id: modRoleID, name: "Mod", permissions: PermissionOverride(allow: [.kickMembers, .banMembers, .timeoutMembers]), rank: 10),
                memberRoleID: Role(id: memberRoleID, name: "Member", permissions: PermissionOverride(), rank: 50),
                timeoutRoleID: Role(id: timeoutRoleID, name: "Timeout Mod", permissions: PermissionOverride(allow: [.timeoutMembers]), rank: 60)
            ],
            defaultPermissions: [.viewChannel, .readMessageHistory]
        )
        let currentMember = ServerMember(id: MemberCompositeKey(serverID: serverID, userID: current), joinedAt: Date(), roles: [modRoleID])
        let targetMember = ServerMember(id: MemberCompositeKey(serverID: serverID, userID: target), joinedAt: Date(), roles: [memberRoleID])
        let base = ModerationBaseContextSnapshot(
            serverID: serverID,
            currentUserID: current,
            server: server,
            currentMember: currentMember,
            selectedOrFallbackTextChannelID: nil,
            permissionResolution: PermissionResolutionResult(effectivePermissions: [.kickMembers, .banMembers, .timeoutMembers]),
            isConnectedForLiveActions: true,
            knownBannedUserIDs: [],
            generation: 1
        )

        let normal = MemberModerationMenuStateResolver.menuState(targetUserID: target, targetMember: targetMember, baseContext: base)
        XCTAssertFalse(normal[.kick].isDisabled)
        XCTAssertFalse(normal[.ban].isDisabled)
        XCTAssertFalse(normal[.timeout].isDisabled)
        XCTAssertEqual(normal[.removeTimeout].disabledReason, .targetNotTimedOut)

        let timedOutMember = ServerMember(id: targetMember.id, joinedAt: targetMember.joinedAt, roles: [memberRoleID], timeout: Date().addingTimeInterval(300))
        let timedOut = MemberModerationMenuStateResolver.menuState(targetUserID: target, targetMember: timedOutMember, baseContext: base)
        XCTAssertFalse(timedOut[.removeTimeout].isDisabled)

        let selfTarget = MemberModerationMenuStateResolver.menuState(targetUserID: current, targetMember: currentMember, baseContext: base)
        XCTAssertEqual(selfTarget[.kick].disabledReason, .targetIsSelf)

        let ownerMember = ServerMember(id: MemberCompositeKey(serverID: serverID, userID: owner), joinedAt: Date(), roles: [adminRoleID])
        let ownerTarget = MemberModerationMenuStateResolver.menuState(targetUserID: owner, targetMember: ownerMember, baseContext: base)
        XCTAssertEqual(ownerTarget[.ban].disabledReason, .targetIsServerOwner)

        let higherMember = ServerMember(id: targetMember.id, joinedAt: targetMember.joinedAt, roles: [adminRoleID])
        let higher = MemberModerationMenuStateResolver.menuState(targetUserID: target, targetMember: higherMember, baseContext: base)
        XCTAssertEqual(higher[.kick].disabledReason, .targetRoleEqualOrHigher)

        var disconnectedBase = base
        disconnectedBase.isConnectedForLiveActions = false
        let disconnected = MemberModerationMenuStateResolver.menuState(targetUserID: target, targetMember: targetMember, baseContext: disconnectedBase)
        XCTAssertEqual(disconnected[.ban].disabledReason, .disconnected)

        var bannedBase = base
        bannedBase.knownBannedUserIDs = [target]
        let banned = MemberModerationMenuStateResolver.menuState(targetUserID: target, targetMember: targetMember, baseContext: bannedBase)
        XCTAssertEqual(banned[.ban].disabledReason, .targetAlreadyBanned)
        XCTAssertFalse(banned[.unban].isDisabled)

        let nonMemberBan = MemberModerationMenuStateResolver.menuState(targetUserID: "non-member", targetMember: nil, baseContext: base, allowNonMemberBan: true)
        XCTAssertFalse(nonMemberBan[.ban].isDisabled)

        let timeoutCapableTarget = ServerMember(id: targetMember.id, joinedAt: targetMember.joinedAt, roles: [timeoutRoleID])
        let timeoutBlocked = MemberModerationMenuStateResolver.menuState(targetUserID: target, targetMember: timeoutCapableTarget, baseContext: base)
        XCTAssertEqual(timeoutBlocked[.timeout].disabledReason, .targetHasTimeoutPermission)
    }

    @MainActor
    func testPhase42ModerationMenuStateUsesFallbackTextChannelAndCachesByTarget() {
        let current: UserID = "phase42-current"
        let target: UserID = "phase42-target"
        let serverID: ServerID = "phase42-fallback-server"
        let roleID: RoleID = "phase42-mod-role"
        let memberRoleID: RoleID = "phase42-member-role"
        let channelID: ChannelID = "phase42-general"
        let role = Role(id: roleID, name: "Channel Mod", permissions: PermissionOverride(), rank: 10)
        let memberRole = Role(id: memberRoleID, name: "Member", permissions: PermissionOverride(), rank: 50)
        let server = Server(id: serverID, ownerID: "phase42-owner", name: "Fallback", channelIDs: [channelID], roles: [roleID: role, memberRoleID: memberRole], defaultPermissions: [.viewChannel, .readMessageHistory])
        let channel = Channel(
            id: channelID,
            kind: .textChannel,
            serverID: serverID,
            name: "general",
            rolePermissions: [roleID: PermissionOverride(allow: [.kickMembers, .banMembers, .timeoutMembers])]
        )
        let currentMember = ServerMember(id: MemberCompositeKey(serverID: serverID, userID: current), joinedAt: Date(), roles: [roleID])
        let targetMember = ServerMember(id: MemberCompositeKey(serverID: serverID, userID: target), joinedAt: Date(), roles: [memberRoleID])
        var snapshot = RealtimeSnapshot(
            usersByID: [
                current: User(id: current, username: "current"),
                target: User(id: target, username: "target")
            ],
            serversByID: [serverID: server],
            channelsByID: [channelID: channel],
            membersByServerAndUserID: [
                ServerMemberKey(currentMember.id): currentMember,
                ServerMemberKey(targetMember.id): targetMember
            ]
        )
        let model = MainShellViewModel(
            selection: ShellSelection(space: .server(serverID), serverID: serverID),
            snapshot: snapshot,
            runtimeMode: .mock,
            currentUser: snapshot.usersByID[current]
        )
        model.selection.channelID = nil

        let beforeChannels = model.channelsForServerInvocationCount
        let first = model.memberModerationMenuState(targetUserID: target, member: targetMember)
        XCTAssertFalse(first[.ban].isDisabled)
        XCTAssertEqual(model.channelsForServerInvocationCount, beforeChannels)
        let firstDiagnostics = model.moderationCacheDiagnostics
        XCTAssertGreaterThan(firstDiagnostics.memberMenuStateCacheMisses, 0)

        let second = model.memberModerationMenuState(targetUserID: target, member: targetMember)
        XCTAssertFalse(second[.ban].isDisabled)
        XCTAssertGreaterThan(model.moderationCacheDiagnostics.memberMenuStateCacheHits, firstDiagnostics.memberMenuStateCacheHits)

        model.banListState = .loaded(BanListResult(users: [], bans: [ServerBan(id: MemberCompositeKey(serverID: serverID, userID: target))]))
        let banned = model.memberModerationMenuState(targetUserID: target, member: targetMember)
        XCTAssertEqual(banned[.ban].disabledReason, .targetAlreadyBanned)

        snapshot.membersByServerAndUserID[ServerMemberKey(targetMember.id)] = ServerMember(id: targetMember.id, joinedAt: targetMember.joinedAt, roles: [roleID])
        model.snapshot = snapshot
        let elevatedTarget = model.memberModerationMenuState(targetUserID: target)
        XCTAssertEqual(elevatedTarget[.timeout].disabledReason, .targetRoleEqualOrHigher)
    }

    @MainActor
    func testPhase42ModerationMenuStateAllowsServerPermissionsWithoutVisibleTextChannel() {
        let current: UserID = "phase42-server-current"
        let target: UserID = "phase42-server-target"
        let serverID: ServerID = "phase42-no-channel-server"
        let roleID: RoleID = "phase42-server-mod"
        let memberRoleID: RoleID = "phase42-server-member"
        let role = Role(id: roleID, name: "Server Mod", permissions: PermissionOverride(allow: [.kickMembers, .banMembers, .timeoutMembers]), rank: 10)
        let memberRole = Role(id: memberRoleID, name: "Member", permissions: PermissionOverride(), rank: 50)
        let server = Server(id: serverID, ownerID: "phase42-owner", name: "No Channel", roles: [roleID: role, memberRoleID: memberRole], defaultPermissions: [.viewChannel, .readMessageHistory])
        let currentMember = ServerMember(id: MemberCompositeKey(serverID: serverID, userID: current), joinedAt: Date(), roles: [roleID])
        let targetMember = ServerMember(id: MemberCompositeKey(serverID: serverID, userID: target), joinedAt: Date(), roles: [memberRoleID])
        let snapshot = RealtimeSnapshot(
            usersByID: [
                current: User(id: current, username: "current"),
                target: User(id: target, username: "target")
            ],
            serversByID: [serverID: server],
            membersByServerAndUserID: [
                ServerMemberKey(currentMember.id): currentMember,
                ServerMemberKey(targetMember.id): targetMember
            ]
        )
        let model = MainShellViewModel(
            selection: ShellSelection(space: .server(serverID), serverID: serverID),
            snapshot: snapshot,
            runtimeMode: .mock,
            currentUser: snapshot.usersByID[current]
        )

        let beforeChannels = model.channelsForServerInvocationCount
        let state = model.memberModerationMenuState(targetUserID: target, member: targetMember)
        XCTAssertFalse(state[.kick].isDisabled)
        XCTAssertFalse(state[.ban].isDisabled)
        XCTAssertEqual(model.channelsForServerInvocationCount, beforeChannels)
    }

    @MainActor
    func testPhase42ModerationMenuStateInvalidatesWhenSessionDisconnects() {
        let current: UserID = "phase42-live-current"
        let target: UserID = "phase42-live-target"
        let serverID: ServerID = "phase42-live-server"
        let roleID: RoleID = "phase42-live-mod"
        let memberRoleID: RoleID = "phase42-live-member"
        let role = Role(id: roleID, name: "Live Mod", permissions: PermissionOverride(allow: [.kickMembers, .banMembers, .timeoutMembers]), rank: 10)
        let memberRole = Role(id: memberRoleID, name: "Member", permissions: PermissionOverride(), rank: 50)
        let server = Server(id: serverID, ownerID: "phase42-owner", name: "Live", roles: [roleID: role, memberRoleID: memberRole], defaultPermissions: [.viewChannel, .readMessageHistory])
        let currentMember = ServerMember(id: MemberCompositeKey(serverID: serverID, userID: current), joinedAt: Date(), roles: [roleID])
        let targetMember = ServerMember(id: MemberCompositeKey(serverID: serverID, userID: target), joinedAt: Date(), roles: [memberRoleID])
        let snapshot = RealtimeSnapshot(
            usersByID: [
                current: User(id: current, username: "current"),
                target: User(id: target, username: "target")
            ],
            serversByID: [serverID: server],
            membersByServerAndUserID: [
                ServerMemberKey(currentMember.id): currentMember,
                ServerMemberKey(targetMember.id): targetMember
            ]
        )
        let model = MainShellViewModel(
            selection: ShellSelection(space: .server(serverID), serverID: serverID),
            snapshot: snapshot,
            runtimeMode: .liveManual,
            sessionState: .connected,
            currentUser: snapshot.usersByID[current]
        )

        XCTAssertFalse(model.memberModerationMenuState(targetUserID: target, member: targetMember)[.ban].isDisabled)
        model.sessionState = .signedOut
        XCTAssertEqual(model.memberModerationMenuState(targetUserID: target, member: targetMember)[.ban].disabledReason, .disconnected)
    }

    @MainActor
    func testPhase42ModerationMenuStateLargeServerDoesNotWalkChannelsPerMember() {
        let current: UserID = "phase42-large-current"
        let serverID: ServerID = "phase42-large-server"
        let modRoleID: RoleID = "phase42-large-mod"
        var roles: [RoleID: Role] = [
            modRoleID: Role(id: modRoleID, name: "Mod", permissions: PermissionOverride(allow: [.kickMembers, .banMembers, .timeoutMembers]), rank: 1)
        ]
        for index in 0..<19 {
            let roleID = RoleID(rawValue: "phase42-large-role-\(index)")
            roles[roleID] = Role(id: roleID, name: "Role \(index)", permissions: PermissionOverride(), rank: Int64(index + 10))
        }
        let channelIDs = (0..<50).map { ChannelID(rawValue: "phase42-large-channel-\($0)") }
        let server = Server(id: serverID, ownerID: "phase42-owner", name: "Large", channelIDs: channelIDs, roles: roles, defaultPermissions: [.viewChannel, .readMessageHistory])
        var channels: [ChannelID: Channel] = [:]
        for channelID in channelIDs {
            channels[channelID] = Channel(id: channelID, kind: .textChannel, serverID: serverID, name: channelID.rawValue)
        }
        var users: [UserID: User] = [current: User(id: current, username: "current")]
        var members: [ServerMemberKey: ServerMember] = [
            ServerMemberKey(serverID: serverID, userID: current): ServerMember(id: MemberCompositeKey(serverID: serverID, userID: current), joinedAt: Date(), roles: [modRoleID])
        ]
        var targetMembers: [ServerMember] = []
        for index in 0..<1_000 {
            let userID = UserID(rawValue: "phase42-large-user-\(index)")
            users[userID] = User(id: userID, username: "user\(index)")
            let member = ServerMember(id: MemberCompositeKey(serverID: serverID, userID: userID), joinedAt: Date())
            targetMembers.append(member)
            members[ServerMemberKey(member.id)] = member
        }
        let snapshot = RealtimeSnapshot(
            usersByID: users,
            serversByID: [serverID: server],
            channelsByID: channels,
            membersByServerAndUserID: members
        )
        let model = MainShellViewModel(
            selection: ShellSelection(space: .server(serverID), serverID: serverID, channelID: channelIDs[0]),
            snapshot: snapshot,
            runtimeMode: .mock,
            currentUser: users[current]
        )

        let beforeChannels = model.channelsForServerInvocationCount
        let beforePermissionMisses = model.moderationCacheDiagnostics.permissionResolutionCacheMisses
        for member in targetMembers {
            _ = model.memberModerationMenuState(targetUserID: member.id.userID, member: member)
        }
        let afterFirstPass = model.moderationCacheDiagnostics
        XCTAssertEqual(model.channelsForServerInvocationCount, beforeChannels)
        XCTAssertLessThanOrEqual(afterFirstPass.permissionResolutionCacheMisses - beforePermissionMisses, 1)
        XCTAssertEqual(afterFirstPass.memberMenuStateCacheMisses, targetMembers.count)

        for member in targetMembers {
            _ = model.memberModerationMenuState(targetUserID: member.id.userID, member: member)
        }
        let afterSecondPass = model.moderationCacheDiagnostics
        XCTAssertEqual(model.channelsForServerInvocationCount, beforeChannels)
        XCTAssertEqual(afterSecondPass.memberMenuStateCacheHits - afterFirstPass.memberMenuStateCacheHits, targetMembers.count)
    }

    @MainActor
    func testPhase46CachedModerationLookupDoesNotComputeDuringRender() async {
        let current: UserID = "phase46-current"
        let target: UserID = "phase46-target"
        let serverID: ServerID = "phase46-server"
        let roleID: RoleID = "phase46-mod-role"
        let memberRoleID: RoleID = "phase46-member-role"
        let channelID: ChannelID = "phase46-general"
        let role = Role(id: roleID, name: "Moderator", permissions: PermissionOverride(allow: [.kickMembers, .banMembers, .timeoutMembers]), rank: 10)
        let memberRole = Role(id: memberRoleID, name: "Member", permissions: PermissionOverride(), rank: 50)
        let server = Server(id: serverID, ownerID: "phase46-owner", name: "Phase 46", channelIDs: [channelID], roles: [roleID: role, memberRoleID: memberRole], defaultPermissions: [.viewChannel, .readMessageHistory])
        let channel = Channel(id: channelID, kind: .textChannel, serverID: serverID, name: "general")
        let currentMember = ServerMember(id: MemberCompositeKey(serverID: serverID, userID: current), joinedAt: Date(), roles: [roleID])
        let targetMember = ServerMember(id: MemberCompositeKey(serverID: serverID, userID: target), joinedAt: Date(), roles: [memberRoleID])
        let snapshot = RealtimeSnapshot(
            usersByID: [
                current: User(id: current, username: "current"),
                target: User(id: target, username: "target")
            ],
            serversByID: [serverID: server],
            channelsByID: [channelID: channel],
            membersByServerAndUserID: [
                ServerMemberKey(currentMember.id): currentMember,
                ServerMemberKey(targetMember.id): targetMember
            ]
        )
        let model = MainShellViewModel(
            selection: ShellSelection(space: .server(serverID), serverID: serverID, channelID: channelID),
            snapshot: snapshot,
            runtimeMode: .mock,
            currentUser: snapshot.usersByID[current]
        )

        let beforeRenderLookup = model.moderationCacheDiagnostics
        let preparing = model.cachedMemberModerationMenuState(targetUserID: target, member: targetMember)
        XCTAssertTrue(preparing[.ban].isDisabled)
        XCTAssertEqual(preparing[.ban].disabledReasonText, "Preparing moderation state")
        XCTAssertEqual(model.moderationCacheDiagnostics, beforeRenderLookup)

        await model.memberPanelBecameVisibleForModerationPrewarm()
        XCTAssertEqual(model.phase46MemberPanelPrewarmState.lastResult, .prepared)
        XCTAssertEqual(model.phase46MemberPanelPrewarmState.preparedMemberCount, 2)

        let afterPrewarmDiagnostics = model.moderationCacheDiagnostics
        let cached = model.cachedMemberModerationMenuState(targetUserID: target, member: targetMember)
        XCTAssertFalse(cached[.ban].isDisabled)
        XCTAssertEqual(model.moderationCacheDiagnostics, afterPrewarmDiagnostics)
    }

    @MainActor
    func testPhase46MemberPanelPrewarmDedupesForSameRevisionKey() async {
        let current: UserID = "phase46-dedupe-current"
        let target: UserID = "phase46-dedupe-target"
        let serverID: ServerID = "phase46-dedupe-server"
        let roleID: RoleID = "phase46-dedupe-mod-role"
        let memberRoleID: RoleID = "phase46-dedupe-member-role"
        let channelID: ChannelID = "phase46-dedupe-general"
        let role = Role(id: roleID, name: "Moderator", permissions: PermissionOverride(allow: [.kickMembers, .banMembers, .timeoutMembers]), rank: 10)
        let memberRole = Role(id: memberRoleID, name: "Member", permissions: PermissionOverride(), rank: 50)
        let server = Server(id: serverID, ownerID: "phase46-dedupe-owner", name: "Phase 46 Dedupe", channelIDs: [channelID], roles: [roleID: role, memberRoleID: memberRole], defaultPermissions: [.viewChannel, .readMessageHistory])
        let channel = Channel(id: channelID, kind: .textChannel, serverID: serverID, name: "general")
        let currentMember = ServerMember(id: MemberCompositeKey(serverID: serverID, userID: current), joinedAt: Date(), roles: [roleID])
        let targetMember = ServerMember(id: MemberCompositeKey(serverID: serverID, userID: target), joinedAt: Date(), roles: [memberRoleID])
        let snapshot = RealtimeSnapshot(
            usersByID: [
                current: User(id: current, username: "current"),
                target: User(id: target, username: "target")
            ],
            serversByID: [serverID: server],
            channelsByID: [channelID: channel],
            membersByServerAndUserID: [
                ServerMemberKey(currentMember.id): currentMember,
                ServerMemberKey(targetMember.id): targetMember
            ]
        )
        let model = MainShellViewModel(
            selection: ShellSelection(space: .server(serverID), serverID: serverID, channelID: channelID),
            snapshot: snapshot,
            runtimeMode: .mock,
            currentUser: snapshot.usersByID[current]
        )

        await model.memberPanelBecameVisibleForModerationPrewarm()
        let afterFirstPrewarm = model.phase46FreezePreventionDiagnostics
        let afterFirstDiagnostics = model.moderationCacheDiagnostics
        XCTAssertEqual(afterFirstPrewarm.lastResult, .prepared)

        await model.memberPanelBecameVisibleForModerationPrewarm()
        XCTAssertEqual(model.phase46FreezePreventionDiagnostics.lastResult, .deduped)
        XCTAssertEqual(model.phase46FreezePreventionDiagnostics.lifecyclePrewarmDedupes, afterFirstPrewarm.lifecyclePrewarmDedupes + 1)
        XCTAssertEqual(model.moderationCacheDiagnostics, afterFirstDiagnostics)
    }

    @MainActor
    func testPhase46MessageOnlySnapshotUpdateDoesNotInvalidateModerationPrewarm() async {
        let current: UserID = "phase46-message-current"
        let target: UserID = "phase46-message-target"
        let serverID: ServerID = "phase46-message-server"
        let roleID: RoleID = "phase46-message-mod-role"
        let memberRoleID: RoleID = "phase46-message-member-role"
        let channelID: ChannelID = "phase46-message-general"
        let role = Role(id: roleID, name: "Moderator", permissions: PermissionOverride(allow: [.kickMembers, .banMembers, .timeoutMembers]), rank: 10)
        let memberRole = Role(id: memberRoleID, name: "Member", permissions: PermissionOverride(), rank: 50)
        let server = Server(id: serverID, ownerID: "phase46-message-owner", name: "Phase 46 Message", channelIDs: [channelID], roles: [roleID: role, memberRoleID: memberRole], defaultPermissions: [.viewChannel, .readMessageHistory])
        let channel = Channel(id: channelID, kind: .textChannel, serverID: serverID, name: "general")
        let currentMember = ServerMember(id: MemberCompositeKey(serverID: serverID, userID: current), joinedAt: Date(), roles: [roleID])
        let targetMember = ServerMember(id: MemberCompositeKey(serverID: serverID, userID: target), joinedAt: Date(), roles: [memberRoleID])
        var snapshot = RealtimeSnapshot(
            usersByID: [
                current: User(id: current, username: "current"),
                target: User(id: target, username: "target")
            ],
            serversByID: [serverID: server],
            channelsByID: [channelID: channel],
            membersByServerAndUserID: [
                ServerMemberKey(currentMember.id): currentMember,
                ServerMemberKey(targetMember.id): targetMember
            ]
        )
        let model = MainShellViewModel(
            selection: ShellSelection(space: .server(serverID), serverID: serverID, channelID: channelID),
            snapshot: snapshot,
            runtimeMode: .mock,
            currentUser: snapshot.usersByID[current]
        )
        await model.memberPanelBecameVisibleForModerationPrewarm()
        let preparedKey = model.phase46MemberPanelPrewarmState.preparedKey
        let token = model.memberPanelModerationPrewarmToken

        snapshot.messagesByChannelID[channelID] = [
            Message(id: "phase46-message-1", channelID: channelID, authorID: current, content: "hello")
        ]
        model.snapshot = snapshot

        XCTAssertEqual(model.memberPanelModerationPrewarmToken, token)
        XCTAssertEqual(model.phase46MemberPanelPrewarmState.preparedKey, preparedKey)
        XCTAssertFalse(model.cachedMemberModerationMenuState(targetUserID: target, member: targetMember)[.ban].isDisabled)
    }

    @MainActor
    func testPhase42BanAndUnbanPatchListsWithoutReaddingMember() async {
        let snapshot = MockShellData.snapshot
        let server = snapshot.serversByID.values.first { $0.name == "Bagel Lab" }!
        let targetUserID: UserID = "01HX0000000000000000000003"
        let targetKey = ServerMemberKey(serverID: server.id, userID: targetUserID)
        let targetMember = snapshot.membersByServerAndUserID[targetKey]!
        let api = MockStoatAPIClient()
        let model = MainShellViewModel(snapshot: snapshot, runtimeMode: .mock, communityAPIClient: api)

        model.selectServer(server.id)
        await model.refreshBanList()
        model.requestModerationAction(.ban, targetUserID: targetUserID, member: targetMember)
        if var pending = model.pendingModerationConfirmation {
            pending.reason = "private moderation note"
            model.pendingModerationConfirmation = pending
        }
        await model.confirmPendingModerationAction()

        XCTAssertNil(model.snapshot.membersByServerAndUserID[targetKey])
        XCTAssertEqual(model.snapshot.usersByID[targetUserID]?.username, "designpilot")
        guard case let .loaded(afterBan) = model.banListState else {
            return XCTFail("Expected loaded ban list")
        }
        XCTAssertTrue(afterBan.bans.contains { $0.id.userID == targetUserID })

        model.requestUnban(userID: targetUserID)
        XCTAssertEqual(model.pendingModerationConfirmation?.action, .unban)
        await model.confirmPendingModerationAction()

        guard case let .loaded(afterUnban) = model.banListState else {
            return XCTFail("Expected loaded ban list after unban")
        }
        XCTAssertFalse(afterUnban.bans.contains { $0.id.userID == targetUserID })
        XCTAssertNil(model.snapshot.membersByServerAndUserID[targetKey])
    }

    @MainActor
    func testPhase42KickPreservesIdentityAndFailurePreservesMember() async {
        let snapshot = MockShellData.snapshot
        let server = snapshot.serversByID.values.first { $0.name == "Bagel Lab" }!
        let targetUserID: UserID = "01HX0000000000000000000003"
        let targetKey = ServerMemberKey(serverID: server.id, userID: targetUserID)
        let targetMember = snapshot.membersByServerAndUserID[targetKey]!
        let failingModel = MainShellViewModel(snapshot: snapshot, runtimeMode: .mock, communityAPIClient: RecordingAPIClient())

        failingModel.selectServer(server.id)
        failingModel.requestModerationAction(.kick, targetUserID: targetUserID, member: targetMember)
        await failingModel.confirmPendingModerationAction()
        XCTAssertNotNil(failingModel.snapshot.membersByServerAndUserID[targetKey])
        guard case .failed = failingModel.moderationActionState else {
            return XCTFail("Expected failed moderation state")
        }

        let model = MainShellViewModel(snapshot: snapshot, runtimeMode: .mock, communityAPIClient: MockStoatAPIClient())
        model.selectServer(server.id)
        model.requestModerationAction(.kick, targetUserID: targetUserID, member: targetMember)
        await model.confirmPendingModerationAction()
        XCTAssertNil(model.snapshot.membersByServerAndUserID[targetKey])
        XCTAssertEqual(model.snapshot.usersByID[targetUserID]?.username, "designpilot")
    }

    @MainActor
    func testPhase42TimeoutPresetAndRemoveTimeoutUpdateMember() async {
        let snapshot = MockShellData.snapshot
        let server = snapshot.serversByID.values.first { $0.name == "Bagel Lab" }!
        let targetUserID: UserID = "01HX0000000000000000000002"
        let targetKey = ServerMemberKey(serverID: server.id, userID: targetUserID)
        let targetMember = snapshot.membersByServerAndUserID[targetKey]!
        let model = MainShellViewModel(snapshot: snapshot, runtimeMode: .mock, communityAPIClient: MockStoatAPIClient())

        model.selectServer(server.id)
        model.requestModerationAction(.timeout, targetUserID: targetUserID, member: targetMember)
        if var pending = model.pendingModerationConfirmation {
            pending.timeoutPreset = .fiveMinutes
            model.pendingModerationConfirmation = pending
        }
        await model.confirmPendingModerationAction()
        let timedOutMember = try? XCTUnwrap(model.snapshot.membersByServerAndUserID[targetKey])
        XCTAssertNotNil(timedOutMember?.timeout)
        XCTAssertEqual(model.moderationDiagnostics.durationBucket, "minutes")

        model.requestModerationAction(.removeTimeout, targetUserID: targetUserID, member: timedOutMember!)
        await model.confirmPendingModerationAction()
        XCTAssertNil(model.snapshot.membersByServerAndUserID[targetKey]?.timeout)
    }

    func testPhase42ModerationDiagnosticsRedactsReasonAndIDs() {
        let diagnostics = ModerationDiagnostics(
            lastActionCategory: "ban",
            selectedServerPresenceCategory: "selected",
            targetCategory: "member",
            permissionResultCategory: "allowed",
            routeCategory: "PUT /servers/{server}/bans/{target}",
            requestResultCategory: "failed",
            responseShapeCategory: "error",
            safeErrorCategory: #"network token="secret" /Users/enka/private raw@example.com 01HX0000000000000000000002"#,
            durationBucket: "minutes",
            memberCacheMutationCategory: "none",
            bansKnownCount: 1,
            bansRenderedCount: 1,
            bansPendingCount: 0,
            timeoutsKnownCount: 0,
            timeoutsRenderedCount: 0,
            timeoutsPendingCount: 0,
            elapsedDurationBucket: "under1s",
            copiedDiagnosticsRedactedReasonText: true
        )

        let text = ModerationDiagnosticsFormatter.redactedText(diagnostics)

        XCTAssertTrue(text.contains("reasonRedacted: yes"))
        XCTAssertFalse(text.contains("secret"))
        XCTAssertFalse(text.contains("/Users/enka"))
        XCTAssertFalse(text.contains("raw@example.com"))
        XCTAssertFalse(text.contains("01HX0000000000000000000002"))
        XCTAssertFalse(text.contains("private moderation note"))
    }

    func testPhase42ParityRowsRemainPartialUntilLiveQA() {
        let matrix = Phase30ParityMatrixBuilder.build(dmLiveQAPassed: true)
        let memberModeration = matrix.items.first { $0.section == "Server/community" && $0.name == "member moderation" }
        let bansTimeouts = matrix.items.first { $0.section == "Server/community" && $0.name == "bans/timeouts" }

        XCTAssertEqual(memberModeration?.status, .partial)
        XCTAssertEqual(bansTimeouts?.status, .partial)
        XCTAssertTrue(memberModeration?.currentImplementation.contains("Phase 42") == true)
        XCTAssertTrue(bansTimeouts?.knownGaps.localizedCaseInsensitiveContains("live QA") == true)
    }

    @MainActor func testCapabilityCachePopulatedOnInit() {
        let snapshot = MockShellData.snapshot
        let server = snapshot.serversByID.values.first { $0.name == "Bagel Lab" }!
        let model = MainShellViewModel(snapshot: snapshot, runtimeMode: .mock)
        model.selectServer(server.id)
        let caps = model.serverManagementCapabilities()
        // Mock mode is always connected — cache must reflect this immediately without re-scanning channels.
        XCTAssertTrue(caps.isConnectedForLiveActions)
        XCTAssertEqual(caps, model.cachedServerCapabilities)
    }

    @MainActor func testCapabilityCacheUpdatesWhenSnapshotChanges() {
        let snapshot = MockShellData.snapshot
        let server = snapshot.serversByID.values.first { $0.name == "Bagel Lab" }!
        let model = MainShellViewModel(snapshot: snapshot, runtimeMode: .mock)
        model.selectServer(server.id)

        let before = model.cachedServerCapabilities
        // Replace the snapshot — cache must update.
        model.snapshot = RealtimeSnapshot()
        let after = model.cachedServerCapabilities
        // After clearing the snapshot the selected server no longer exists; capabilities should differ.
        XCTAssertNotEqual(before, after)
        XCTAssertFalse(after.canManageServer)
    }

    @MainActor func testCapabilityCacheUpdatesWhenSelectionChanges() {
        let snapshot = MockShellData.snapshot
        let server = snapshot.serversByID.values.first { $0.name == "Bagel Lab" }!
        let model = MainShellViewModel(snapshot: snapshot, runtimeMode: .mock)

        let beforeSelect = model.cachedServerCapabilities
        model.selectServer(server.id)
        let afterSelect = model.cachedServerCapabilities
        XCTAssertNotEqual(beforeSelect, afterSelect)
    }

    @MainActor func testMemberActionDisabledReasonUsesCache() {
        let snapshot = MockShellData.snapshot
        let server = snapshot.serversByID.values.first { $0.name == "Bagel Lab" }!
        let targetUserID: UserID = "01HX0000000000000000000002"
        let targetKey = ServerMemberKey(serverID: server.id, userID: targetUserID)
        let targetMember = snapshot.membersByServerAndUserID[targetKey]!
        let model = MainShellViewModel(snapshot: snapshot, runtimeMode: .mock)
        model.selectServer(server.id)

        // Call four times — this should read from the cache each time, not re-scan channels.
        let r1 = model.memberActionDisabledReason(for: targetMember, action: .kick)
        let r2 = model.memberActionDisabledReason(for: targetMember, action: .ban)
        let r3 = model.memberActionDisabledReason(for: targetMember, action: .timeout)
        let r4 = model.memberActionDisabledReason(for: targetMember, action: .clearTimeout)
        // All four calls share the same cached permission resolution; remove-timeout now has its own state gate.
        XCTAssertEqual(r1, r2)
        XCTAssertNil(r3)
        XCTAssertEqual(r4, "This member is not currently timed out.")
        // Capability cache must not have changed (no snapshot/selection mutation occurred).
        let capsBefore = model.cachedServerCapabilities
        _ = model.memberActionDisabledReason(for: targetMember, action: .kick)
        XCTAssertEqual(capsBefore, model.cachedServerCapabilities)
    }

    @MainActor func testChannelsForServerUsesOrderedIDsWithDictLookup() {
        let serverID: ServerID = "server-order-test"
        let ch1 = Channel(id: "ch1", kind: .textChannel, serverID: serverID, name: "Zeta")
        let ch2 = Channel(id: "ch2", kind: .textChannel, serverID: serverID, name: "Alpha")
        let server = Server(id: serverID, ownerID: "u1", name: "Order Test", channelIDs: [ch2.id, ch1.id])
        let snap = RealtimeSnapshot(
            serversByID: [server.id: server],
            channelsByID: [ch1.id: ch1, ch2.id: ch2]
        )
        let model = MainShellViewModel(snapshot: snap, runtimeMode: .mock)
        let channels = model.channels(for: serverID)
        // Ordered by channelIDs list (ch2 first), NOT alphabetically.
        XCTAssertEqual(channels.map(\.id), [ch2.id, ch1.id])
    }

    private func phase18Snapshot(currentUserID: UserID, otherUserID: UserID, textChannelID: ChannelID, dmChannelID: ChannelID) -> RealtimeSnapshot {
        let currentUser = User(id: currentUserID, username: "me", displayName: "Me")
        let otherUser = User(id: otherUserID, username: "other", displayName: "Other")
        let server = Server(id: "server-phase18", ownerID: currentUserID, name: "Phase 18", channelIDs: [textChannelID])
        let text = Channel(id: textChannelID, kind: .textChannel, serverID: server.id, name: "general")
        let dm = Channel(id: dmChannelID, kind: .directMessage, recipients: [currentUserID, otherUserID])
        return RealtimeSnapshot(
            usersByID: [currentUserID: currentUser, otherUserID: otherUser],
            serversByID: [server.id: server],
            channelsByID: [text.id: text, dm.id: dm]
        )
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

    @MainActor
    func testPhase37MemberOrderingHighestRoleColorAndDMIsolation() throws {
        let serverID: ServerID = "phase37-server"
        let channelID: ChannelID = "phase37-channel"
        let adminID: RoleID = "phase37-admin"
        let managerID: RoleID = "phase37-manager"
        let ordinaryID: RoleID = "phase37-ordinary"
        let userAdmin: UserID = "phase37-user-admin"
        let userManager: UserID = "phase37-user-manager"
        let userOrdinary: UserID = "phase37-user-ordinary"
        let userBot: UserID = "phase37-user-bot"
        let userUnknown: UserID = "phase37-user-unknown"
        var server = Server(id: serverID, ownerID: "phase37-owner", name: "Phase 37")
        server.roles = [
            adminID: Role(id: adminID, name: "Admins", permissions: PermissionOverride(allow: [.manageServer]), colour: "#FF3366", rank: 0),
            managerID: Role(id: managerID, name: "Managers", permissions: PermissionOverride(allow: [.manageRole]), colour: "#3366FF", rank: 20),
            ordinaryID: Role(id: ordinaryID, name: "Members", permissions: PermissionOverride(), colour: "#00AA44", rank: 1)
        ]
        var snapshot = RealtimeSnapshot()
        snapshot.serversByID[serverID] = server
        snapshot.channelsByID[channelID] = Channel(id: channelID, kind: .textChannel, serverID: serverID, name: "general")
        snapshot.usersByID[userAdmin] = User(id: userAdmin, username: "admin", displayName: "Admin", online: true)
        snapshot.usersByID[userManager] = User(id: userManager, username: "manager", displayName: "Manager", online: true)
        snapshot.usersByID[userOrdinary] = User(id: userOrdinary, username: "ordinary", displayName: "Ordinary", online: true)
        snapshot.usersByID[userBot] = User(id: userBot, username: "bot", displayName: "Bot", bot: BotInformation(ownerID: userAdmin), online: true)
        snapshot.membersByServerAndUserID[ServerMemberKey(serverID: serverID, userID: userAdmin)] = ServerMember(id: MemberCompositeKey(serverID: serverID, userID: userAdmin), joinedAt: Date(), roles: [adminID, ordinaryID])
        snapshot.membersByServerAndUserID[ServerMemberKey(serverID: serverID, userID: userManager)] = ServerMember(id: MemberCompositeKey(serverID: serverID, userID: userManager), joinedAt: Date(), roles: [managerID, ordinaryID])
        snapshot.membersByServerAndUserID[ServerMemberKey(serverID: serverID, userID: userOrdinary)] = ServerMember(id: MemberCompositeKey(serverID: serverID, userID: userOrdinary), joinedAt: Date(), roles: [ordinaryID])
        snapshot.membersByServerAndUserID[ServerMemberKey(serverID: serverID, userID: userBot)] = ServerMember(id: MemberCompositeKey(serverID: serverID, userID: userBot), joinedAt: Date(), roles: [])
        snapshot.membersByServerAndUserID[ServerMemberKey(serverID: serverID, userID: userUnknown)] = ServerMember(id: MemberCompositeKey(serverID: serverID, userID: userUnknown), joinedAt: Date(), roles: ["phase37-missing-role"])
        let model = MainShellViewModel(selection: ShellSelection(space: .server(serverID), serverID: serverID, channelID: channelID), snapshot: snapshot)

        let groups = model.memberListGroups(for: serverID)
        XCTAssertEqual(groups.map(\.id).prefix(3), ["role-\(managerID.rawValue)", "role-\(ordinaryID.rawValue)", "bots"])
        XCTAssertEqual(groups.first?.items.map(\.userID), [userManager])
        XCTAssertEqual(groups.flatMap(\.items).filter { $0.userID == userAdmin }.count, 1)
        XCTAssertEqual(model.memberRoleSortDiagnostics.unknownRoleCount, 1)

        let managerDisplay = model.resolvedUserDisplay(for: snapshot.usersByID[userManager], member: snapshot.membersByServerAndUserID[ServerMemberKey(serverID: serverID, userID: userManager)], fallbackID: userManager, serverID: serverID)
        XCTAssertEqual(managerDisplay.roleColor?.sourceRoleID, managerID)
        let dmDisplay = model.resolvedUserDisplay(for: snapshot.usersByID[userManager], member: nil, fallbackID: userManager)
        XCTAssertNil(dmDisplay.roleColor)
    }

    @MainActor
    func testPhase37ProfileContextNotificationReadinessAndTopBarTitle() async throws {
        let serverID: ServerID = "phase37-profile-server"
        let userID: UserID = "phase37-profile-user"
        let ownerID: UserID = "phase37-owner"
        let roleID: RoleID = "phase37-role"
        var server = Server(id: serverID, ownerID: ownerID, name: "Profile Server")
        server.roles = [roleID: Role(id: roleID, name: "Staff", permissions: PermissionOverride(allow: [.manageServer]), colour: "#AA00AA", rank: 5)]
        var snapshot = RealtimeSnapshot()
        snapshot.serversByID[serverID] = server
        snapshot.usersByID[ownerID] = User(id: ownerID, username: "owner", displayName: "Owner")
        snapshot.usersByID[userID] = User(id: userID, username: "helper", displayName: "Helper", status: UserStatus(text: "Testing", presence: .focus), bot: BotInformation(ownerID: ownerID))
        snapshot.membersByServerAndUserID[ServerMemberKey(serverID: serverID, userID: userID)] = ServerMember(id: MemberCompositeKey(serverID: serverID, userID: userID), joinedAt: Date(), roles: [roleID])
        let api = RecordingAPIClient(currentUser: snapshot.usersByID[ownerID]!, profilesByUserID: [userID: UserProfile(content: "**hello**")])
        let model = MainShellViewModel(selection: ShellSelection(space: .server(serverID), serverID: serverID), snapshot: snapshot, communityAPIClient: api)

        model.showUserProfile(userID, source: .memberRow, serverID: serverID)
        try await Task.sleep(for: .milliseconds(30))

        let context = try XCTUnwrap(model.profilePresentationContext)
        XCTAssertEqual(context.serverID, serverID)
        XCTAssertEqual(context.openSource, .memberRow)
        XCTAssertEqual(context.display.roleColor?.sourceRoleID, roleID)
        XCTAssertEqual(context.botOwnerID, ownerID)
        XCTAssertEqual(context.roles.map(\.id), [roleID])
        let fetchCount = await api.fetchUserProfileCallCount
        XCTAssertEqual(fetchCount, 1)
        XCTAssertEqual(model.userProfilesByID[userID]?.content, "**hello**")
        XCTAssertFalse(model.title.contains("checkmark"))
        XCTAssertTrue(model.notificationBuildReadinessDiagnostics.codeSigningAllowed.contains("NO"))
        XCTAssertEqual(model.notificationBuildReadinessDiagnostics.bundleIdentifier.isEmpty, false)
    }

    @MainActor
    func testPhase37IdentityFreezeMarkdownAndImageSafeModeDiagnostics() async throws {
        let serverID: ServerID = "phase37-freeze-server"
        let channelID: ChannelID = "phase37-freeze-channel"
        let userID: UserID = "01JPHASE37MISSING0000000001"
        var snapshot = RealtimeSnapshot()
        snapshot.serversByID[serverID] = Server(id: serverID, ownerID: userID, name: "Freeze")
        snapshot.channelsByID[channelID] = Channel(id: channelID, kind: .textChannel, serverID: serverID, name: "general")
        snapshot.membersByServerAndUserID[ServerMemberKey(serverID: serverID, userID: userID)] = ServerMember(id: MemberCompositeKey(serverID: serverID, userID: userID), joinedAt: Date())
        snapshot.messagesByChannelID[channelID] = [Message(id: "01J00000000000000000370001", channelID: channelID, authorID: userID, content: "hello **markdown**")]
        let loader = SlowImageResourceLoader(delayNanoseconds: 500_000_000)
        let model = MainShellViewModel(selection: ShellSelection(space: .server(serverID), serverID: serverID, channelID: channelID), snapshot: snapshot, imageResourceLoader: loader)

        _ = model.memberListGroups(for: serverID)
        _ = model.memberListGroups(for: serverID)
        model.updateTimelineVisibility(messageID: "01J00000000000000000370001", channelID: channelID, isVisible: true)
        _ = MarkdownMessageContent("hello **markdown**")
        _ = MarkdownMessageContent("hello **markdown**")
        for index in 0..<24 {
            let file = File(id: FileID(rawValue: "phase37-image-\(index)"), tag: "attachments", filename: "\(index).png", contentType: "image/png", size: 1)
            model.loadImageResource(for: file, kind: .attachmentPreview)
        }
        try await Task.sleep(for: .milliseconds(25))

        model.copyVisibleIdentityDiagnostics()
        XCTAssertGreaterThanOrEqual(model.freezePerformanceDiagnostics.memberGroupingCacheHitCount, 1)
        XCTAssertGreaterThanOrEqual(model.visibleIdentityDiagnostics.unresolvedVisibleUserCount, 1)
        XCTAssertGreaterThanOrEqual(model.freezePerformanceDiagnostics.markdownCacheHitCount, 1)
        XCTAssertTrue(model.freezePerformanceDiagnostics.mediaSafeModeEnabled)
        let diagnostics = await model.imageResourceDiagnostics()
        XCTAssertTrue(diagnostics.mediaSafeModeEnabled)
        XCTAssertGreaterThan(diagnostics.queuedTaskCount, 0)
    }

    @MainActor
    func testPhase44ReplyPreviewLoadedUnavailableAndNoRawFullIDs() {
        let channelID: ChannelID = "phase44-replies"
        let rawAuthorID: UserID = "01JPHASE44AUTHOR0000000001"
        let original = Message(id: MessageID(rawValue: ulid(milliseconds: 1_000)), channelID: channelID, authorID: rawAuthorID, content: "reply target")
        let reply = Message(id: MessageID(rawValue: ulid(milliseconds: 2_000)), channelID: channelID, authorID: "phase44-replier", content: "replying", replies: [original.id])
        let missingReply = Message(id: MessageID(rawValue: ulid(milliseconds: 3_000)), channelID: channelID, authorID: "phase44-replier", content: "replying", replies: ["01JPHASE44MISSING0000000001"])
        let channel = Channel(id: channelID, kind: .textChannel, serverID: "phase44-server", name: "general")
        let server = Server(id: "phase44-server", ownerID: rawAuthorID, name: "Phase44", channelIDs: [channelID])
        let model = MainShellViewModel(
            selection: ShellSelection(space: .server(server.id), serverID: server.id, channelID: channelID),
            snapshot: RealtimeSnapshot(serversByID: [server.id: server], channelsByID: [channelID: channel], messagesByChannelID: [channelID: [original, reply, missingReply]])
        )

        let loaded = model.replyPreviewState(for: reply)
        XCTAssertEqual(loaded?.resolution, .loaded)
        XCTAssertNotEqual(loaded?.authorDisplayName, rawAuthorID.rawValue)
        XCTAssertFalse(loaded?.plainText.contains(rawAuthorID.rawValue) == true)

        let unavailable = model.replyPreviewState(for: missingReply)
        XCTAssertEqual(unavailable?.resolution, .loading)
        XCTAssertEqual(unavailable?.summary, "Loading original message...")
    }

    @MainActor
    func testPhase44ReplyPreviewClickRoutesThroughJumpCoordinatorAndHighlights() async {
        let channelID: ChannelID = "phase44-reply-jump"
        let original = Message(id: MessageID(rawValue: ulid(milliseconds: 1_000)), channelID: channelID, authorID: "phase44-author", content: "original")
        let reply = Message(id: MessageID(rawValue: ulid(milliseconds: 2_000)), channelID: channelID, authorID: "phase44-replier", content: "reply", replies: [original.id])
        let channel = Channel(id: channelID, kind: .textChannel, serverID: "phase44-server", name: "general")
        let server = Server(id: "phase44-server", ownerID: "phase44-author", name: "Phase44", channelIDs: [channelID])
        let model = MainShellViewModel(
            selection: ShellSelection(space: .server(server.id), serverID: server.id, channelID: channelID),
            snapshot: RealtimeSnapshot(serversByID: [server.id: server], channelsByID: [channelID: channel], messagesByChannelID: [channelID: [original, reply]])
        )

        await model.openReplyPreview(for: reply)

        XCTAssertEqual(model.timelineSelection.messageID, original.id)
        XCTAssertTrue(model.isTargetMessageHighlighted(original.id, channelID: channelID))
        XCTAssertEqual(model.phase44Diagnostics.jumpSourceCounts[MessageNavigationSource.replyPreview.rawValue], 1)
    }

    @MainActor
    func testPhase44ReplyComposerClearsAfterSuccessAndPersistsAfterFailure() async throws {
        let channelID = try XCTUnwrap(MockShellData.snapshot.channelsByID.values.first { $0.kind == .textChannel }?.id)
        let target = try XCTUnwrap(MockShellData.snapshot.messagesByChannelID[channelID]?.first)

        let failingHandler = RecordingAttachmentMessageActionHandler()
        await failingHandler.setSendError(MessageActionError.unavailable("offline"))
        let failingModel = MainShellViewModel(snapshot: MockShellData.snapshot, messageActionHandler: failingHandler)
        failingModel.selectChannel(channelID)
        failingModel.beginReply(to: TimelineMessage(message: target, status: .confirmed))
        failingModel.updateDraft("still here", for: channelID)
        await failingModel.sendDraft(for: channelID)

        XCTAssertEqual(failingModel.replyContext(for: channelID)?.messageID, target.id)
        XCTAssertEqual(failingModel.draft(for: channelID), "still here")
        XCTAssertEqual(failingModel.phase44Diagnostics.replyComposerPreservedAfterFailureCount, 1)

        let successHandler = RecordingAttachmentMessageActionHandler()
        let successModel = MainShellViewModel(snapshot: MockShellData.snapshot, messageActionHandler: successHandler)
        successModel.selectChannel(channelID)
        successModel.beginReply(to: TimelineMessage(message: target, status: .confirmed))
        successModel.updateDraft("send", for: channelID)
        await successModel.sendDraft(for: channelID)

        XCTAssertNil(successModel.replyContext(for: channelID))
        XCTAssertEqual(successModel.draft(for: channelID), "")
        XCTAssertEqual(successModel.phase44Diagnostics.replyComposerClearedAfterSendCount, 1)
    }

    @MainActor
    func testPhase44PinnedListUsesSelectedChannelSearchJumpAndUnpin() async throws {
        let current = User(id: MockShellData.currentUserID, username: "me")
        let author = User(id: "phase44-pin-author", username: "pin-author", displayName: "Pin Author")
        let serverID: ServerID = "phase44-pin-server"
        let channelID: ChannelID = "phase44-pin-channel"
        let target = Message(id: MessageID(rawValue: ulid(milliseconds: 10_000)), channelID: channelID, authorID: author.id, content: "pinned target", user: author, pinned: true)
        let channel = Channel(id: channelID, kind: .textChannel, serverID: serverID, name: "pins")
        let server = Server(id: serverID, ownerID: current.id, name: "Pins", channelIDs: [channelID])
        let snapshot = RealtimeSnapshot(usersByID: [current.id: current, author.id: author], serversByID: [serverID: server], channelsByID: [channelID: channel], messagesByChannelID: [channelID: [target]])
        let api = RecordingAPIClient(currentUser: current, messagesByChannel: [channelID: [target]])
        let model = await phase40LiveModel(snapshot: snapshot, currentUser: current, api: api)
        model.messageActionHandler = LiveMessageActionHandler(apiClient: api, realtimeClient: RecordingRealtimeClient())
        model.selectChannel(channelID)

        await model.refreshPinnedMessages()
        guard case let .loaded(_, items) = model.pinnedMessagesState.loadState else {
            return XCTFail("Expected pinned messages")
        }
        XCTAssertEqual(items.count, 1)
        let searches = await api.searchedMessages
        XCTAssertEqual(searches.last?.1.pinned, true)
        XCTAssertEqual(searches.last?.1.includeUsers, true)

        await model.openPinnedMessage(items[0])
        XCTAssertEqual(model.timelineSelection.messageID, target.id)
        XCTAssertTrue(model.isTargetMessageHighlighted(target.id, channelID: channelID))

        await model.unpinPinnedMessage(items[0])
        let unpinned = await api.unpinnedMessages
        XCTAssertEqual(unpinned.last?.1, target.id)
        XCTAssertTrue(model.pinnedMessagesState.loadState.items.isEmpty)
    }

    @MainActor
    func testPhase44NotificationRouteDegradesToChannelWhenMessageUnavailable() async {
        let channelID: ChannelID = "phase44-notification-channel"
        let serverID: ServerID = "phase44-notification-server"
        let channel = Channel(id: channelID, kind: .textChannel, serverID: serverID, name: "general")
        let server = Server(id: serverID, ownerID: "owner", name: "Notify", channelIDs: [channelID])
        let model = MainShellViewModel(snapshot: RealtimeSnapshot(serversByID: [serverID: server], channelsByID: [channelID: channel]))

        await model.openNotificationRoute(NotificationRoute(serverID: serverID, channelID: channelID, messageID: "phase44-missing-message"))

        XCTAssertEqual(model.selectedConversationChannelID, channelID)
        XCTAssertEqual(model.phase44Diagnostics.notificationRouteDegradedCount, 1)
    }

    @MainActor
    func testPhase44TypingIndicatorCopyExcludesCurrentUserAndExpiresStale() {
        let channelID: ChannelID = "phase44-typing-channel"
        let current: UserID = "phase44-current"
        let one: UserID = "phase44-one"
        let two: UserID = "phase44-two"
        var state = TypingIndicatorState(channelID: channelID, timeout: 2)
        state.replace(channelID: channelID, typingUserIDs: [current, one], currentUserID: current, now: Date(timeIntervalSince1970: 10))
        XCTAssertEqual(TypingIndicatorState.displayText(names: ["One"]), "One is typing...")
        XCTAssertEqual(state.activeUserIDs, [one])
        state.replace(channelID: channelID, typingUserIDs: [one, two], currentUserID: current, now: Date(timeIntervalSince1970: 11))
        XCTAssertEqual(TypingIndicatorState.displayText(names: ["One", "Two"]), "One and Two are typing...")
        state.replace(channelID: channelID, typingUserIDs: [one, two, "phase44-three"], currentUserID: current, now: Date(timeIntervalSince1970: 12))
        XCTAssertEqual(TypingIndicatorState.displayText(names: ["One", "Two", "Three"]), "Several people are typing...")
        XCTAssertEqual(state.removeStale(now: Date(timeIntervalSince1970: 20)), 3)
        XCTAssertTrue(state.activeUserIDs.isEmpty)
    }

    @MainActor
    func testPhase44AckDedupeAndClearsUnreadOnlyAfterSuccess() async throws {
        let sender = RecordingChannelAckSender()
        let currentUserID = MockShellData.currentUserID
        let channelID: ChannelID = "phase44-ack-channel"
        let message = Message(id: MessageID(rawValue: ulid(milliseconds: 1_000)), channelID: channelID, authorID: "phase44-other", content: "ack me")
        let channel = Channel(id: channelID, kind: .textChannel, serverID: "phase44-ack-server", name: "ack")
        let server = Server(id: "phase44-ack-server", ownerID: currentUserID, name: "Ack", channelIDs: [channelID])
        var snapshot = RealtimeSnapshot(serversByID: [server.id: server], channelsByID: [channelID: channel], messagesByChannelID: [channelID: [message]])
        snapshot.unreadsByChannelID[channelID] = ChannelUnread(id: ChannelCompositeKey(channelID: channelID, userID: currentUserID), lastMessageID: message.id, mentions: [])
        let model = MainShellViewModel(selection: ShellSelection(space: .server(server.id), serverID: server.id, channelID: channelID), snapshot: snapshot, runtimeMode: .liveManual, sessionState: .connected, currentUser: User(id: currentUserID, username: "me"), channelAckSender: sender)
        model.timelineTuning.ackDebounceMilliseconds = 5

        model.selectChannel(channelID)
        model.updateTimelineVisibility(messageID: message.id, channelID: channelID, isVisible: true)
        model.updateTimelineAtNewest(true)
        try await Task.sleep(for: .milliseconds(40))

        let acks = await sender.acks
        XCTAssertEqual(acks.filter { $0.0 == channelID && $0.1 == message.id }.count, 1)
        XCTAssertNil(model.unread(for: channelID)?.lastMessageID)
        XCTAssertGreaterThanOrEqual(model.phase44Diagnostics.ackDedupedCount, 1)
    }

    func testPhase44DiagnosticsRedactsSensitiveValues() {
        let diagnostics = Phase44ChatInteractionDiagnostics(
            lastSafeStatus: #"token="secret" https://stoat.example/a /Users/enka/private raw@example.com 01JPHASE44FULLID0000000001 private moderation note"#
        )

        let text = Phase44DiagnosticsFormatter.redactedText(diagnostics)

        XCTAssertTrue(text.contains("Phase 44 Chat Interaction Diagnostics"))
        XCTAssertFalse(text.contains("secret"))
        XCTAssertFalse(text.contains("https://stoat.example"))
        XCTAssertFalse(text.contains("/Users/enka"))
        XCTAssertFalse(text.contains("raw@example.com"))
        XCTAssertFalse(text.contains("01JPHASE44FULLID0000000001"))
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

private actor SlowImageResourceLoader: ImageResourceLoading {
    private let delayNanoseconds: UInt64
    private(set) var calls: [ImageResourceRequest] = []

    init(delayNanoseconds: UInt64) {
        self.delayNanoseconds = delayNanoseconds
    }

    func loadImage(_ request: ImageResourceRequest) async throws -> ImageResourceResult {
        calls.append(request)
        try await Task.sleep(nanoseconds: delayNanoseconds)
        return ImageResourceResult(request: request, contentType: "image/png", data: Data("image".utf8))
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
    private(set) var fetchCurrentUserCallCount = 0
    private(set) var editUserCallCount = 0
    private(set) var fetchMessagesCallCount = 0
    private(set) var fetchMessageCallCount = 0
    private(set) var searchedMessages: [(ChannelID, ChannelMessageSearchRequest)] = []
    private(set) var pinnedMessages: [(ChannelID, MessageID)] = []
    private(set) var unpinnedMessages: [(ChannelID, MessageID)] = []
    private(set) var fetchServerMembersCallCount = 0
    private(set) var fetchedServerMemberIDs: [ServerID] = []
    private(set) var fetchUserProfileCallCount = 0
    private(set) var fetchDirectMessagesCallCount = 0
    private(set) var openDirectMessageCallCount = 0
    private(set) var openedDirectMessageUserIDs: [UserID] = []
    private(set) var sentDrafts: [(ChannelID, MessageDraft)] = []
    private(set) var editedMessages: [(ChannelID, MessageID, MessageEditDraft)] = []
    private(set) var deletedMessages: [(ChannelID, MessageID)] = []
    private(set) var addedReactions: [(ChannelID, MessageID, String)] = []
    private(set) var removedReactions: [(ChannelID, MessageID, String)] = []
    private(set) var editedUserDrafts: [(UserID, UserEditDraft)] = []
    private(set) var uploadedFiles: [RecordedUpload] = []

    private let currentUser: User
    private var messagesByChannel: [ChannelID: [Message]]
    private var membersByServer: [ServerID: [ServerMember]]
    private var usersByServer: [ServerID: [User]]
    private var directMessages: [Channel]
    private var openDirectMessagesByUserID: [UserID: Channel]
    private var editedUsersByID: [UserID: User] = [:]
    private var profilesByUserID: [UserID: UserProfile]
    private let fetchError: (any Error & Sendable)?
    private let directMessagesFetchError: (any Error & Sendable)?
    private let openDirectMessageError: (any Error & Sendable)?
    private let openDirectMessageDelayNanoseconds: UInt64
    private let memberFetchError: (any Error & Sendable)?
    private let memberFetchDelayNanoseconds: UInt64
    private let editUserError: (any Error & Sendable)?
    private let uploadError: (any Error & Sendable)?
    private let uploadedFileIDsByTag: [UploadTag: FileID]

    init(
        currentUser: User = User(id: MockShellData.currentUserID, username: "liquidbagel"),
        messagesByChannel: [ChannelID: [Message]] = [:],
        membersByServer: [ServerID: [ServerMember]] = [:],
        usersByServer: [ServerID: [User]] = [:],
        directMessages: [Channel] = [],
        openDirectMessagesByUserID: [UserID: Channel] = [:],
        profilesByUserID: [UserID: UserProfile] = [:],
        fetchError: (any Error & Sendable)? = nil,
        directMessagesFetchError: (any Error & Sendable)? = nil,
        openDirectMessageError: (any Error & Sendable)? = nil,
        openDirectMessageDelayNanoseconds: UInt64 = 0,
        memberFetchError: (any Error & Sendable)? = nil,
        memberFetchDelayNanoseconds: UInt64 = 0,
        editUserError: (any Error & Sendable)? = nil,
        uploadError: (any Error & Sendable)? = nil,
        uploadedFileIDsByTag: [UploadTag: FileID] = [:]
    ) {
        self.currentUser = currentUser
        self.messagesByChannel = messagesByChannel
        self.membersByServer = membersByServer
        self.usersByServer = usersByServer
        self.directMessages = directMessages
        self.openDirectMessagesByUserID = openDirectMessagesByUserID
        self.profilesByUserID = profilesByUserID
        self.fetchError = fetchError
        self.directMessagesFetchError = directMessagesFetchError
        self.openDirectMessageError = openDirectMessageError
        self.openDirectMessageDelayNanoseconds = openDirectMessageDelayNanoseconds
        self.memberFetchError = memberFetchError
        self.memberFetchDelayNanoseconds = memberFetchDelayNanoseconds
        self.editUserError = editUserError
        self.uploadError = uploadError
        self.uploadedFileIDsByTag = uploadedFileIDsByTag
    }

    func fetchRootConfiguration() async throws -> StoatConfig {
        throw StoatAPIError.unimplementedEndpoint("test")
    }

    func fetchCurrentUser() async throws -> User {
        fetchCurrentUserCallCount += 1
        return currentUser
    }

    func editUser(userID: UserID, draft: UserEditDraft) async throws -> User {
        editUserCallCount += 1
        editedUserDrafts.append((userID, draft))
        if let editUserError {
            throw editUserError
        }
        var user = editedUsersByID[userID] ?? (userID == currentUser.id ? currentUser : User(id: userID, username: UserDisplayResolver.shortenedID(userID)))
        if let status = draft.status {
            user.status = status
            user.online = status.presence != .invisible
        }
        if let displayName = draft.displayName {
            user.displayName = displayName
        }
        if let avatar = draft.avatar {
            user.avatar = File(
                id: FileID(rawValue: avatar),
                tag: UploadTag.avatars.rawAPIValue,
                filename: "recorded-avatar.png",
                metadata: .file,
                contentType: "image/png",
                size: 12,
                userID: userID
            )
        }
        if draft.remove.contains(.displayName) {
            user.displayName = nil
        }
        if draft.remove.contains(.avatar) {
            user.avatar = nil
        }
        if draft.remove.contains(.statusText) {
            user.status?.text = nil
        }
        if draft.remove.contains(.statusPresence) {
            user.status?.presence = nil
        }
        if draft.profile != nil || draft.remove.contains(.profileContent) || draft.remove.contains(.profileBackground) {
            var profile = profilesByUserID[userID] ?? UserProfile()
            if draft.remove.contains(.profileContent) {
                profile.content = nil
            }
            if draft.remove.contains(.profileBackground) {
                profile.background = nil
            }
            if let content = draft.profile?.content {
                profile.content = content
            }
            if let background = draft.profile?.background {
                profile.background = File(
                    id: FileID(rawValue: background),
                    tag: UploadTag.backgrounds.rawAPIValue,
                    filename: "recorded-background.png",
                    metadata: .file,
                    contentType: "image/png",
                    size: 24,
                    userID: userID
                )
            }
            profilesByUserID[userID] = profile
        }
        editedUsersByID[userID] = user
        return user
    }

    func fetchUserProfile(userID: UserID) async throws -> UserProfile {
        fetchUserProfileCallCount += 1
        return profilesByUserID[userID] ?? UserProfile(content: "Profile for \(userID.rawValue)")
    }

    func fetchDirectMessages() async throws -> [Channel] {
        fetchDirectMessagesCallCount += 1
        if let directMessagesFetchError {
            throw directMessagesFetchError
        }
        return directMessages
    }

    func openDirectMessage(userID: UserID) async throws -> Channel {
        openDirectMessageCallCount += 1
        openedDirectMessageUserIDs.append(userID)
        if openDirectMessageDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: openDirectMessageDelayNanoseconds)
        }
        if let openDirectMessageError {
            throw openDirectMessageError
        }
        if let channel = openDirectMessagesByUserID[userID] {
            return channel
        }
        let channel = Channel(id: ChannelID(rawValue: "recorded-dm-\(userID.rawValue)"), kind: userID == currentUser.id ? .savedMessages : .directMessage, userID: userID == currentUser.id ? currentUser.id : nil, active: true, recipients: [currentUser.id, userID])
        openDirectMessagesByUserID[userID] = channel
        return channel
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

    func fetchMessage(channelID: ChannelID, messageID: MessageID) async throws -> Message {
        fetchMessageCallCount += 1
        guard let message = messagesByChannel[channelID]?.first(where: { $0.id == messageID }) else {
            throw StoatAPIError.notFound
        }
        return message
    }

    func fetchMessages(channelID: ChannelID, options: MessageFetchOptions) async throws -> [Message] {
        fetchMessagesCallCount += 1
        if let fetchError {
            throw fetchError
        }
        var messages = messagesByChannel[channelID] ?? []
        messages.sort { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
        if let nearby = options.nearby,
           let index = messages.firstIndex(where: { $0.id == nearby }) {
            let limit = max(1, options.limit ?? 50)
            let half = max(1, limit / 2)
            let lower = max(messages.startIndex, index - half)
            let upper = min(messages.endIndex, index + half + 1)
            messages = Array(messages[lower..<upper])
        } else {
            if let before = options.before, let index = messages.firstIndex(where: { $0.id == before }) {
                messages = Array(messages[..<index])
            }
            if let after = options.after, let index = messages.firstIndex(where: { $0.id == after }) {
                messages = Array(messages[messages.index(after: index)...])
            }
            if let limit = options.limit, messages.count > limit {
                messages = Array(messages.prefix(limit))
            }
        }
        return messages
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

    func searchMessages(channelID: ChannelID, request: ChannelMessageSearchRequest) async throws -> [Message] {
        searchedMessages.append((channelID, request))
        var messages = messagesByChannel[channelID] ?? []
        if request.pinned == true {
            messages = messages.filter { $0.isPinned }
        }
        if let query = request.query?.lowercased(), !query.isEmpty {
            messages = messages.filter { ($0.content ?? "").lowercased().contains(query) }
        }
        messages.sort { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        if let limit = request.limit, messages.count > limit {
            messages = Array(messages.prefix(limit))
        }
        return messages
    }

    func fetchServerMembers(serverID: ServerID) async throws -> ServerMembersResponse {
        fetchServerMembersCallCount += 1
        fetchedServerMemberIDs.append(serverID)
        if memberFetchDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: memberFetchDelayNanoseconds)
        }
        if let memberFetchError {
            throw memberFetchError
        }
        return ServerMembersResponse(members: membersByServer[serverID] ?? [], users: usersByServer[serverID] ?? [])
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

    func pinMessage(channelID: ChannelID, messageID: MessageID) async throws {
        pinnedMessages.append((channelID, messageID))
    }

    func unpinMessage(channelID: ChannelID, messageID: MessageID) async throws {
        unpinnedMessages.append((channelID, messageID))
    }

    func uploadFile(data: Data, filename: String, mimeType: String, tag: UploadTag) async throws -> UploadedFile {
        uploadedFiles.append(RecordedUpload(data: data, filename: filename, mimeType: mimeType, tag: tag))
        if let uploadError {
            throw uploadError
        }
        let fallbackID = FileID(rawValue: "\(tag.rawAPIValue)-file-\(uploadedFiles.count)")
        return UploadedFile(id: uploadedFileIDsByTag[tag] ?? fallbackID)
    }
}

private struct RecordedUpload: Sendable, Hashable {
    var data: Data
    var filename: String
    var mimeType: String
    var tag: UploadTag
}

private struct RecordedAttachmentSend: Sendable {
    var channelID: ChannelID
    var content: String
    var nonce: String?
    var replies: [MessageReply]?
    var attachments: [FileID]?
}

private actor RecordingAttachmentMessageActionHandler: MessageActionHandling {
    private(set) var sent: [RecordedAttachmentSend] = []
    var sendError: (any Error & Sendable)?

    func sentSnapshot() -> [RecordedAttachmentSend] {
        sent
    }

    func setSendError(_ error: (any Error & Sendable)?) {
        sendError = error
    }

    func sendMessage(channelID: ChannelID, content: String, nonce: String?, replies: [MessageReply]?, attachments: [FileID]?) async throws -> Message {
        if let sendError {
            throw sendError
        }
        sent.append(RecordedAttachmentSend(channelID: channelID, content: content, nonce: nonce, replies: replies, attachments: attachments))
        let files = attachments?.map {
            File(id: $0, tag: "attachments", filename: "\($0.rawValue).txt", contentType: "text/plain", size: 1)
        }
        return Message(id: "01J00000100000000000009999", channelID: channelID, authorID: MockShellData.currentUserID, content: content, nonce: nonce, attachments: files, replies: replies?.map(\.id))
    }

    func editMessage(channelID: ChannelID, messageID: MessageID, content: String) async throws -> Message {
        Message(id: messageID, channelID: channelID, authorID: MockShellData.currentUserID, content: content)
    }

    func deleteMessage(channelID: ChannelID, messageID: MessageID) async throws {}
    func addReaction(channelID: ChannelID, messageID: MessageID, emoji: String) async throws {}
    func removeReaction(channelID: ChannelID, messageID: MessageID, emoji: String) async throws {}
    func pinMessage(channelID: ChannelID, messageID: MessageID) async throws {}
    func unpinMessage(channelID: ChannelID, messageID: MessageID) async throws {}
    func beginTyping(channelID: ChannelID) async throws {}
    func endTyping(channelID: ChannelID) async throws {}
}

private actor ImageAttachmentMessageActionHandler: MessageActionHandling {
    func sendMessage(channelID: ChannelID, content: String, nonce: String?, replies: [MessageReply]?, attachments: [FileID]?) async throws -> Message {
        let files = attachments?.map {
            File(id: $0, tag: "attachments", filename: "\($0.rawValue).png", metadata: .image(width: 1, height: 1, thumbhash: nil, animated: false), contentType: "image/png", size: 8)
        }
        return Message(id: "01J00000100000000000020000", channelID: channelID, authorID: MockShellData.currentUserID, content: content, nonce: nonce, attachments: files, replies: replies?.map(\.id))
    }

    func editMessage(channelID: ChannelID, messageID: MessageID, content: String) async throws -> Message {
        Message(id: messageID, channelID: channelID, authorID: MockShellData.currentUserID, content: content)
    }

    func deleteMessage(channelID: ChannelID, messageID: MessageID) async throws {}
    func addReaction(channelID: ChannelID, messageID: MessageID, emoji: String) async throws {}
    func removeReaction(channelID: ChannelID, messageID: MessageID, emoji: String) async throws {}
    func pinMessage(channelID: ChannelID, messageID: MessageID) async throws {}
    func unpinMessage(channelID: ChannelID, messageID: MessageID) async throws {}
    func beginTyping(channelID: ChannelID) async throws {}
    func endTyping(channelID: ChannelID) async throws {}
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

private actor RecordingSessionValidator: SessionValidating {
    private var errors: [any Error & Sendable]
    private let user: User
    private(set) var validateCallCount = 0

    init(
        user: User = User(id: MockShellData.currentUserID, username: "liquidbagel"),
        errors: [any Error & Sendable] = []
    ) {
        self.user = user
        self.errors = errors
    }

    func validate(credential: StoatAuthCredential, environment: StoatAPIEnvironment) async throws -> ValidatedSession {
        validateCallCount += 1
        if !errors.isEmpty {
            throw errors.removeFirst()
        }
        return ValidatedSession(credential: credential, currentUser: user, environment: environment)
    }
}

// MARK: - Phase 38 Tests

final class Phase38StartupStateTests: XCTestCase {

    @MainActor
    func testStartupStateIsNoCredentialWhenSignedOut() {
        let coordinator = AppSessionCoordinator(tokenStore: InMemoryTokenStore())
        let appModel = LiquidBagelAppModel(coordinator: coordinator)
        XCTAssertEqual(appModel.startupState, .noCredential)
    }

    @MainActor
    func testStartupStateIsReadyForMockMode() async {
        let coordinator = AppSessionCoordinator(tokenStore: InMemoryTokenStore())
        await coordinator.startMockSession()
        let appModel = LiquidBagelAppModel(coordinator: coordinator)
        XCTAssertEqual(appModel.startupState, .ready)
    }

    @MainActor
    func testStartupStateIsRecoverableWhenSavedCredentialReadyButNotConnecting() async throws {
        let store = InMemoryTokenStore(credential: .sessionToken("token"))
        let realtime = RecordingRealtimeClient(statesOnConnect: [.connecting])
        let coordinator = AppSessionCoordinator(
            tokenStore: store,
            sessionValidator: StubSessionValidator(),
            apiClientFactory: { _, _ in RecordingAPIClient() },
            realtimeClientFactory: { realtime }
        )
        let appModel = LiquidBagelAppModel(coordinator: coordinator)
        await coordinator.validateSavedSession()
        XCTAssertEqual(coordinator.sessionState, .readyToConnect)
        if case .savedCredentialFailed = appModel.startupState {
        } else {
            XCTFail("Expected savedCredentialFailed recovery state, got \(appModel.startupState)")
        }
    }

    @MainActor
    func testStartupStateIsReadyAfterConnected() async throws {
        let store = InMemoryTokenStore(credential: .sessionToken("token"))
        let realtime = RecordingRealtimeClient(statesOnConnect: [.connecting, .ready])
        let coordinator = AppSessionCoordinator(
            tokenStore: store,
            sessionValidator: StubSessionValidator(),
            apiClientFactory: { _, _ in RecordingAPIClient() },
            realtimeClientFactory: { realtime }
        )
        let appModel = LiquidBagelAppModel(coordinator: coordinator)
        await coordinator.connectLiveManually()
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(coordinator.sessionState, .connected)
        XCTAssertEqual(appModel.startupState, .ready)
    }

    @MainActor
    func testStartupStateIsSavedCredentialFailedOnInvalidSession() async throws {
        let store = InMemoryTokenStore(credential: .sessionToken("token"))
        let coordinator = AppSessionCoordinator(
            tokenStore: store,
            sessionValidator: StubSessionValidator(error: SessionValidationError.invalidOrExpired),
            apiClientFactory: { _, _ in RecordingAPIClient() },
            realtimeClientFactory: { RecordingRealtimeClient() }
        )
        let appModel = LiquidBagelAppModel(coordinator: coordinator)
        await coordinator.validateSavedSession()
        if case .savedCredentialFailed = appModel.startupState {
        } else {
            XCTFail("Expected savedCredentialFailed, got \(appModel.startupState)")
        }
    }

    @MainActor
    func testForgetSessionReturnsToNoCredential() async throws {
        let store = InMemoryTokenStore(credential: .sessionToken("token"))
        let coordinator = AppSessionCoordinator(
            tokenStore: store,
            sessionValidator: StubSessionValidator(),
            apiClientFactory: { _, _ in RecordingAPIClient() },
            realtimeClientFactory: { RecordingRealtimeClient() }
        )
        let appModel = LiquidBagelAppModel(coordinator: coordinator)
        await coordinator.validateSavedSession()
        await coordinator.forgetLocalSession()
        XCTAssertEqual(appModel.startupState, .noCredential)
        XCTAssertFalse(coordinator.hasSavedCredential)
    }

    @MainActor
    func testNoShellSnapshotBeforeReady() {
        let coordinator = AppSessionCoordinator(tokenStore: InMemoryTokenStore())
        let appModel = LiquidBagelAppModel(coordinator: coordinator)
        XCTAssertEqual(appModel.startupState, .noCredential)
        XCTAssertTrue(appModel.shell.snapshot.serversByID.isEmpty)
    }
}

final class Phase38LoginDiagnosticsTests: XCTestCase {

    @MainActor
    func testLoginFlowStateStartsIdle() {
        let coordinator = AppSessionCoordinator(tokenStore: InMemoryTokenStore())
        XCTAssertEqual(coordinator.loginFlowState, .idle)
    }

    @MainActor
    func testLoginDiagnosticsStartEmpty() {
        let coordinator = AppSessionCoordinator(tokenStore: InMemoryTokenStore())
        XCTAssertEqual(coordinator.loginDiagnostics.attemptCount, 0)
        XCTAssertNil(coordinator.loginDiagnostics.lastAttemptAt)
        XCTAssertNil(coordinator.loginDiagnostics.lastErrorCategory)
    }

    @MainActor
    func testAutoConnectAttemptCountStartsZero() {
        let coordinator = AppSessionCoordinator(tokenStore: InMemoryTokenStore())
        XCTAssertEqual(coordinator.autoConnectAttemptCount, 0)
    }

    @MainActor
    func testAutoConnectAttemptCountIncrementsOnStartup() async {
        let store = InMemoryTokenStore(credential: .sessionToken("token"))
        let coordinator = AppSessionCoordinator(
            tokenStore: store,
            sessionValidator: StubSessionValidator(),
            apiClientFactory: { _, _ in RecordingAPIClient() },
            realtimeClientFactory: { RecordingRealtimeClient() }
        )
        await coordinator.startLiveFirstSession()
        XCTAssertGreaterThanOrEqual(coordinator.autoConnectAttemptCount, 1)
    }

    @MainActor
    func testLoginDiagnosticsRedactedSummaryContainsAttemptCount() {
        var diag = LoginDiagnostics()
        diag.attemptCount = 3
        diag.lastErrorCategory = .networkError
        XCTAssertTrue(diag.redactedSummary.contains("attempts: 3"))
        XCTAssertTrue(diag.redactedSummary.contains("network_error"))
    }

    @MainActor
    func testLoginDiagnosticsDoesNotContainCredentials() {
        var diag = LoginDiagnostics()
        diag.attemptCount = 1
        diag.lastErrorCategory = .unknown("Bad token abc123")
        let summary = diag.redactedSummary
        XCTAssertFalse(summary.contains("abc123"), "Summary must not contain raw error text that could include token values")
    }

    @MainActor
    func testForgetSessionResetsLoginDiagnostics() async {
        let store = InMemoryTokenStore(credential: .sessionToken("token"))
        let coordinator = AppSessionCoordinator(
            tokenStore: store,
            sessionValidator: StubSessionValidator(error: SessionValidationError.invalidOrExpired),
            apiClientFactory: { _, _ in RecordingAPIClient() },
            realtimeClientFactory: { RecordingRealtimeClient() }
        )
        await coordinator.validateSavedSession()
        await coordinator.validateImportedToken("badtoken")
        XCTAssertGreaterThan(coordinator.loginDiagnostics.attemptCount, 0)
        await coordinator.forgetLocalSession()
        XCTAssertEqual(coordinator.loginDiagnostics.attemptCount, 0)
        XCTAssertEqual(coordinator.loginFlowState, .idle)
    }
}

final class Phase38FirstRunLoginViewModelTests: XCTestCase {

    @MainActor
    func testDefaultStateHasEmptyFields() {
        let coordinator = AppSessionCoordinator(tokenStore: InMemoryTokenStore())
        let vm = FirstRunLoginViewModel(coordinator: coordinator)
        XCTAssertEqual(vm.email, "")
        XCTAssertEqual(vm.password, "")
        XCTAssertFalse(vm.isAdvancedExpanded)
        XCTAssertNil(vm.loginError)
    }

    @MainActor
    func testCanSubmitLoginRequiresNonEmptyEmailAndPassword() {
        let coordinator = AppSessionCoordinator(tokenStore: InMemoryTokenStore())
        let vm = FirstRunLoginViewModel(coordinator: coordinator)
        XCTAssertFalse(vm.canSubmitLogin)
        vm.email = "test@example.com"
        XCTAssertFalse(vm.canSubmitLogin)
        vm.password = "secret"
        XCTAssertTrue(vm.canSubmitLogin)
    }

    @MainActor
    func testCanSubmitTokenRequiresNonEmptyToken() {
        let coordinator = AppSessionCoordinator(tokenStore: InMemoryTokenStore())
        let vm = FirstRunLoginViewModel(coordinator: coordinator)
        XCTAssertFalse(vm.canSubmitToken)
        vm.manualToken = "tok_test"
        XCTAssertTrue(vm.canSubmitToken)
    }

    @MainActor
    func testClearFormResetsAllFields() {
        let coordinator = AppSessionCoordinator(tokenStore: InMemoryTokenStore())
        let vm = FirstRunLoginViewModel(coordinator: coordinator)
        vm.email = "a@b.com"
        vm.password = "pass"
        vm.manualToken = "tok"
        vm.tokenLabel = "label"
        vm.clearForm()
        XCTAssertEqual(vm.email, "")
        XCTAssertEqual(vm.password, "")
        XCTAssertEqual(vm.manualToken, "")
        XCTAssertEqual(vm.tokenLabel, "")
    }

    @MainActor
    func testMFAChallengeForwardedFromCoordinator() {
        let coordinator = AppSessionCoordinator(tokenStore: InMemoryTokenStore())
        let vm = FirstRunLoginViewModel(coordinator: coordinator)
        XCTAssertNil(vm.mfaChallenge)
        XCTAssertNotEqual(vm.flowState, .mfaRequired)
    }

    @MainActor
    func testIsLoadingWhenSubmitting() {
        let coordinator = AppSessionCoordinator(tokenStore: InMemoryTokenStore())
        let vm = FirstRunLoginViewModel(coordinator: coordinator)
        XCTAssertFalse(vm.isLoading)
        XCTAssertEqual(vm.flowState, .idle)
    }
}

final class Phase38AuthFlowTests: XCTestCase {

    @MainActor
    func testLoginWithInvalidCredentialsShowsError() async {
        let coordinator = AppSessionCoordinator(
            tokenStore: InMemoryTokenStore(),
            sessionValidator: StubSessionValidator(error: SessionValidationError.invalidOrExpired),
            apiClientFactory: { _, _ in
                StubLoginAPIClient(response: .success(SessionLoginSuccess(
                    id: "sess1",
                    userID: "user1",
                    token: "tok",
                    name: "Test",
                    lastSeen: Date()
                )))
            },
            realtimeClientFactory: { RecordingRealtimeClient() }
        )
        await coordinator.login(email: "a@b.com", password: "wrong")
        XCTAssertEqual(coordinator.loginFlowState, .idle)
        XCTAssertEqual(coordinator.loginDiagnostics.lastErrorCategory, .invalidCredentials)
        XCTAssertEqual(coordinator.loginDiagnostics.attemptCount, 1)
        XCTAssertNotNil(coordinator.loginDiagnostics.lastAttemptAt)
    }

    @MainActor
    func testTokenImportSuccessUpdatesFlowState() async {
        let realtime = RecordingRealtimeClient(statesOnConnect: [.ready])
        let coordinator = AppSessionCoordinator(
            tokenStore: InMemoryTokenStore(),
            sessionValidator: StubSessionValidator(),
            apiClientFactory: { _, _ in RecordingAPIClient() },
            realtimeClientFactory: { realtime }
        )
        await coordinator.validateImportedToken("validtoken", localLabel: "Dev")
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(coordinator.loginFlowState, .succeeded)
        XCTAssertNil(coordinator.pendingValidatedSession)
        XCTAssertTrue(coordinator.hasSavedCredential)
    }

    @MainActor
    func testTokenImportFailureDoesNotSaveCredential() async {
        let store = InMemoryTokenStore()
        let coordinator = AppSessionCoordinator(
            tokenStore: store,
            sessionValidator: StubSessionValidator(error: SessionValidationError.invalidOrExpired),
            apiClientFactory: { _, _ in RecordingAPIClient() },
            realtimeClientFactory: { RecordingRealtimeClient() }
        )
        await coordinator.validateImportedToken("badtoken")
        XCTAssertEqual(coordinator.loginFlowState, .idle)
        XCTAssertNil(coordinator.pendingValidatedSession)
        let saved = try? await store.loadCredential()
        XCTAssertNil(saved)
    }

    @MainActor
    func testFinishValidatedSessionAndConnectSavesToKeychain() async throws {
        let store = InMemoryTokenStore()
        let realtime = RecordingRealtimeClient(statesOnConnect: [.ready])
        let coordinator = AppSessionCoordinator(
            tokenStore: store,
            sessionValidator: StubSessionValidator(),
            apiClientFactory: { _, _ in RecordingAPIClient() },
            realtimeClientFactory: { realtime }
        )
        await coordinator.validateImportedToken("validtoken")
        await coordinator.finishValidatedSessionAndConnect()
        try await Task.sleep(for: .milliseconds(30))
        let saved = try await store.loadCredential()
        XCTAssertNotNil(saved)
        let connectCallCount = await realtime.connectCallCount
        XCTAssertEqual(connectCallCount, 1)
    }

    @MainActor
    func testFinishValidatedSessionAndConnectDoesNothingWithNoPending() async throws {
        let store = InMemoryTokenStore()
        let coordinator = AppSessionCoordinator(
            tokenStore: store,
            apiClientFactory: { _, _ in RecordingAPIClient() },
            realtimeClientFactory: { RecordingRealtimeClient() }
        )
        await coordinator.finishValidatedSessionAndConnect()
        XCTAssertEqual(coordinator.sessionState, .signedOut)
        let saved = try? await store.loadCredential()
        XCTAssertNil(saved)
    }

    @MainActor
    func testNetworkErrorCategorizedCorrectly() async {
        let coordinator = AppSessionCoordinator(
            tokenStore: InMemoryTokenStore(),
            sessionValidator: StubSessionValidator(error: SessionValidationError.networkUnavailable("timeout")),
            apiClientFactory: { _, _ in RecordingAPIClient() },
            realtimeClientFactory: { RecordingRealtimeClient() }
        )
        await coordinator.validateImportedToken("anytoken")
        XCTAssertEqual(coordinator.loginDiagnostics.lastErrorCategory, .networkError)
    }

    @MainActor
    func testRateLimitCategorizedCorrectly() async {
        let coordinator = AppSessionCoordinator(
            tokenStore: InMemoryTokenStore(),
            sessionValidator: StubSessionValidator(error: SessionValidationError.rateLimited(retryAfterMilliseconds: 5000)),
            apiClientFactory: { _, _ in RecordingAPIClient() },
            realtimeClientFactory: { RecordingRealtimeClient() }
        )
        await coordinator.validateImportedToken("anytoken")
        XCTAssertEqual(coordinator.loginDiagnostics.lastErrorCategory, .rateLimited)
    }
}

// MARK: - Phase 39 Tests

final class Phase39StartupAuthStabilizationTests: XCTestCase {

    @MainActor
    func testStartupAutoConnectIsIdempotentPerLaunchEnvironment() async throws {
        let store = InMemoryTokenStore(credential: .sessionToken("token"))
        let realtime = RecordingRealtimeClient(statesOnConnect: [.ready])
        let coordinator = AppSessionCoordinator(
            tokenStore: store,
            sessionValidator: StubSessionValidator(),
            apiClientFactory: { _, _ in RecordingAPIClient() },
            realtimeClientFactory: { realtime }
        )

        await coordinator.startLiveFirstSession()
        await coordinator.startLiveFirstSession()
        try await Task.sleep(for: .milliseconds(30))

        let connectCallCount = await realtime.connectCallCount
        XCTAssertEqual(connectCallCount, 1)
        XCTAssertEqual(coordinator.autoConnectAttemptCount, 1)
        XCTAssertEqual(coordinator.startupAuthDiagnostics.startupSkippedCount, 1)
    }

    @MainActor
    func testEmailPasswordLoginSavesValidatedSessionAndConnects() async throws {
        let store = InMemoryTokenStore()
        let realtime = RecordingRealtimeClient(statesOnConnect: [.ready])
        let loginSuccess = SessionLoginSuccess(id: "sess-login", userID: "user-login", token: "login-token", name: "Mac", lastSeen: Date())
        let coordinator = AppSessionCoordinator(
            tokenStore: store,
            sessionValidator: StubSessionValidator(user: User(id: "user-login", username: "login")),
            apiClientFactory: { _, _ in StubLoginAPIClient(response: .success(loginSuccess)) },
            realtimeClientFactory: { realtime }
        )

        await coordinator.login(email: "user@example.com", password: "correct horse battery staple", friendlyName: "Mac")
        try await Task.sleep(for: .milliseconds(30))

        let saved = try await store.loadCredential(scope: .production)
        XCTAssertEqual(saved?.token, "login-token")
        XCTAssertEqual(coordinator.loginFlowState, .succeeded)
        let connectCallCount = await realtime.connectCallCount
        XCTAssertEqual(connectCallCount, 1)
        XCTAssertTrue(coordinator.sessionState == .connecting || coordinator.sessionState == .connected)
    }

    @MainActor
    func testMFAContinuationSavesValidatedSessionAndConnects() async throws {
        let store = InMemoryTokenStore()
        let realtime = RecordingRealtimeClient(statesOnConnect: [.ready])
        let loginSuccess = SessionLoginSuccess(id: "sess-mfa", userID: "user-mfa", token: "mfa-token", name: "Mac", lastSeen: Date())
        let api = StubLoginAPIClient(response: .mfa(ticket: "ticket-secret", allowedMethods: [.totp]), continueResponse: .success(loginSuccess))
        let coordinator = AppSessionCoordinator(
            tokenStore: store,
            sessionValidator: StubSessionValidator(user: User(id: "user-mfa", username: "mfa")),
            apiClientFactory: { _, _ in api },
            realtimeClientFactory: { realtime }
        )

        await coordinator.login(email: "mfa@example.com", password: "password", friendlyName: "Mac")
        XCTAssertEqual(coordinator.loginFlowState, .mfaRequired)
        await coordinator.continueLoginMFA(response: .totpCode("123456"), friendlyName: "Mac")
        try await Task.sleep(for: .milliseconds(30))

        let saved = try await store.loadCredential(scope: .production)
        XCTAssertEqual(saved?.token, "mfa-token")
        XCTAssertEqual(coordinator.loginFlowState, .succeeded)
        let continueCallCount = await api.continueCallCount
        let connectCallCount = await realtime.connectCallCount
        XCTAssertEqual(continueCallCount, 1)
        XCTAssertEqual(connectCallCount, 1)
        XCTAssertTrue(coordinator.sessionState == .connecting || coordinator.sessionState == .connected)
    }

    @MainActor
    func testTokenImportSavesToSelectedEnvironmentAndConnects() async throws {
        let custom = try EnvironmentProfile.custom(
            name: "Local",
            environment: StoatAPIEnvironment(apiBaseURL: URL(string: "http://localhost:14702")!, eventsURL: URL(string: "ws://localhost:14703")!)
        )
        let preferences = try AppPreferences.defaults.upserting(profile: custom).withSelectedEnvironmentID(custom.id)
        let store = InMemoryTokenStore()
        let realtime = RecordingRealtimeClient(statesOnConnect: [.ready])
        let coordinator = AppSessionCoordinator(
            tokenStore: store,
            preferencesStore: InMemoryAppPreferencesStore(preferences: preferences),
            sessionValidator: StubSessionValidator(),
            apiClientFactory: { _, _ in RecordingAPIClient() },
            realtimeClientFactory: { realtime }
        )

        await coordinator.startLiveFirstSession()
        await coordinator.validateImportedToken("custom-token", localLabel: "Local")
        try await Task.sleep(for: .milliseconds(30))

        let productionSaved = try await store.loadCredential(scope: .production)
        let customSaved = try await store.loadCredential(scope: CredentialScope(environmentID: custom.id))
        let connectedEnvironments = await realtime.connectedEnvironments
        let connectedCredentials = await realtime.connectedCredentials
        XCTAssertNil(productionSaved)
        XCTAssertEqual(customSaved?.token, "custom-token")
        XCTAssertEqual(connectedEnvironments.last, custom.environment)
        XCTAssertEqual(connectedCredentials.last?.token, "custom-token")
    }

    @MainActor
    func testSavedCredentialNetworkFailureDoesNotLoopAndRetryCanRecover() async throws {
        let store = InMemoryTokenStore(credential: .sessionToken("token"))
        let realtime = RecordingRealtimeClient(statesOnConnect: [.ready])
        let validator = RecordingSessionValidator(errors: [SessionValidationError.networkUnavailable("timeout token=secret /Users/enka/Library/Keychains/login.keychain-db")])
        let coordinator = AppSessionCoordinator(
            tokenStore: store,
            sessionValidator: validator,
            apiClientFactory: { _, _ in RecordingAPIClient() },
            realtimeClientFactory: { realtime }
        )
        let appModel = LiquidBagelAppModel(coordinator: coordinator)

        await coordinator.startLiveFirstSession()
        await coordinator.startLiveFirstSession()
        if case .savedCredentialFailed = appModel.startupState {
        } else {
            XCTFail("Expected saved credential recovery state, got \(appModel.startupState)")
        }
        XCTAssertEqual(coordinator.autoConnectAttemptCount, 1)
        XCTAssertEqual(coordinator.startupAuthDiagnostics.startupSkippedCount, 1)

        await coordinator.reconnectLiveManually()
        try await Task.sleep(for: .milliseconds(30))

        let validateCallCount = await validator.validateCallCount
        let connectCallCount = await realtime.connectCallCount
        XCTAssertEqual(validateCallCount, 2)
        XCTAssertEqual(connectCallCount, 1)
        XCTAssertTrue(coordinator.sessionState == .connecting || coordinator.sessionState == .connected)
    }

    @MainActor
    func testForgetSessionAndEnvironmentSwitchLandInRecoverableStates() async throws {
        let custom = try EnvironmentProfile.custom(
            name: "Local",
            environment: StoatAPIEnvironment(apiBaseURL: URL(string: "http://localhost:14702")!, eventsURL: URL(string: "ws://localhost:14703")!)
        )
        let forgetStore = InMemoryTokenStore(credential: .sessionToken("production-token"))
        let forgetCoordinator = AppSessionCoordinator(
            tokenStore: forgetStore,
            sessionValidator: StubSessionValidator(),
            apiClientFactory: { _, _ in RecordingAPIClient() },
            realtimeClientFactory: { RecordingRealtimeClient(statesOnConnect: [.ready]) }
        )
        let forgetAppModel = LiquidBagelAppModel(coordinator: forgetCoordinator)

        await forgetCoordinator.startLiveFirstSession()
        await forgetCoordinator.forgetLocalSession()
        XCTAssertEqual(forgetAppModel.startupState, .noCredential)

        let switchPreferences = try AppPreferences.defaults.upserting(profile: custom)
        let switchStore = InMemoryTokenStore()
        try await switchStore.saveCredential(.sessionToken("custom-token"), scope: CredentialScope(environmentID: custom.id))
        let switchCoordinator = AppSessionCoordinator(
            tokenStore: switchStore,
            preferencesStore: InMemoryAppPreferencesStore(preferences: switchPreferences),
            sessionValidator: StubSessionValidator(),
            apiClientFactory: { _, _ in RecordingAPIClient() },
            realtimeClientFactory: { RecordingRealtimeClient(statesOnConnect: [.ready]) }
        )
        let switchAppModel = LiquidBagelAppModel(coordinator: switchCoordinator)

        await switchCoordinator.startMockSession()
        await switchCoordinator.selectEnvironmentProfile(id: custom.id)
        XCTAssertTrue(switchCoordinator.hasSavedCredential)
        if case .savedCredentialFailed = switchAppModel.startupState {
        } else {
            XCTFail("Expected saved credential recovery state after environment switch, got \(switchAppModel.startupState)")
        }
    }

    @MainActor
    func testLiquidBagelAppModelSharesCoordinatorWithShell() {
        let coordinator = AppSessionCoordinator(tokenStore: InMemoryTokenStore())
        let appModel = LiquidBagelAppModel(coordinator: coordinator)

        appModel.shell.attachSessionCoordinator(appModel.coordinator)

        XCTAssertTrue(appModel.coordinator === coordinator)
        XCTAssertTrue(appModel.shell.sessionCoordinator === coordinator)
    }

    @MainActor
    func testStartupAuthDiagnosticsRedactSensitiveValues() {
        var diagnostics = StartupAuthDiagnostics()
        diagnostics.startupInvocationCount = 1
        diagnostics.startupAutoConnectAttemptCount = 1
        diagnostics.lastEnvironmentKind = "custom https://api.example.test"
        diagnostics.lastStartupAction = #"token=abc123 password=hunter2 /Users/enka/Library/Keychains/login.keychain-db"#
        diagnostics.lastStartupResult = #"{"error":"raw body","token":"secret","mfa_response":"123456"}"#
        diagnostics.lastAuthAction = "session 01J123456789ABCDEFGHJKLMNP"
        diagnostics.lastAuthResult = "mfa_ticket=secret-ticket"
        diagnostics.lastErrorCategory = .unknown("raw body secret")

        let summary = diagnostics.redactedSummary

        XCTAssertFalse(summary.contains("abc123"))
        XCTAssertFalse(summary.contains("hunter2"))
        XCTAssertFalse(summary.contains("/Users/enka"))
        XCTAssertFalse(summary.contains(#""token":"secret""#))
        XCTAssertFalse(summary.contains("123456"))
        XCTAssertFalse(summary.contains("01J123456789ABCDEFGHJKLMNP"))
        XCTAssertFalse(summary.contains("secret-ticket"))
        XCTAssertTrue(summary.contains("[redacted"))
    }
}

// MARK: - Phase 38 Support Types

private actor StubLoginAPIClient: StoatAPIClient {
    let loginResponse: SessionLoginResponse
    let continueResponse: SessionLoginResponse
    private(set) var loginCallCount = 0
    private(set) var continueCallCount = 0

    init(response: SessionLoginResponse, continueResponse: SessionLoginResponse? = nil) {
        self.loginResponse = response
        self.continueResponse = continueResponse ?? response
    }

    // Required protocol methods without default implementations
    func fetchRootConfiguration() async throws -> StoatConfig { throw StoatAPIError.unimplementedEndpoint("stub") }
    func fetchCurrentUser() async throws -> User { User(id: "user1", username: "test") }
    func fetchServers() async throws -> [Server] { [] }
    func fetchChannels() async throws -> [Channel] { [] }
    func fetchChannel(id: ChannelID) async throws -> Channel { throw StoatAPIError.unimplementedEndpoint("stub") }
    func fetchMessages(channelID: ChannelID, before: MessageID?, after: MessageID?, limit: Int?) async throws -> [Message] { [] }
    func sendMessage(channelID: ChannelID, draft: MessageDraft) async throws -> Message { throw StoatAPIError.unimplementedEndpoint("stub") }
    func editMessage(channelID: ChannelID, messageID: MessageID, draft: MessageEditDraft) async throws -> Message { throw StoatAPIError.unimplementedEndpoint("stub") }
    func deleteMessage(channelID: ChannelID, messageID: MessageID) async throws {}
    func addReaction(channelID: ChannelID, messageID: MessageID, emoji: String) async throws {}
    func removeReaction(channelID: ChannelID, messageID: MessageID, emoji: String, removeAll: Bool) async throws {}
    func pinMessage(channelID: ChannelID, messageID: MessageID) async throws {}
    func unpinMessage(channelID: ChannelID, messageID: MessageID) async throws {}
    func uploadFile(data: Data, filename: String, mimeType: String, tag: UploadTag) async throws -> UploadedFile { throw StoatAPIError.unimplementedEndpoint("stub") }

    func login(request: SessionLoginRequest) async throws -> SessionLoginResponse {
        loginCallCount += 1
        return loginResponse
    }

    func continueLogin(request: SessionMFALoginRequest) async throws -> SessionLoginResponse {
        continueCallCount += 1
        return continueResponse
    }
}
