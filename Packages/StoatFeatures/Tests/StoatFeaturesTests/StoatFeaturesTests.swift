import StoatModels
import StoatAPI
import StoatPersistence
import StoatRealtime
import StoatUI
import Observation
import SwiftUI
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
        var iterator = MockShellSnapshotSource(snapshot: MockShellData.snapshot).updates.makeAsyncIterator()
        let update = await iterator.next()

        XCTAssertEqual(update?.snapshot, MockShellData.snapshot)
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
    func testInitialHistoryLoadSurvivesRealtimeMessageAndDeduplicatesConcurrentRequest() async {
        let channelID: ChannelID = "history-interleave-channel"
        let historical = message(id: ulid(milliseconds: 1_000), author: "a", channel: channelID)
        let realtime = message(id: ulid(milliseconds: 2_000), author: "b", channel: channelID)
        let api = RecordingAPIClient(
            messagesByChannel: [channelID: [historical]],
            fetchMessagesDelayNanoseconds: 40_000_000
        )
        let controller = ChannelMessageController(
            runtimeMode: .liveManual,
            apiClient: api,
            currentUserID: "a"
        )

        async let initial = controller.loadInitialIfNeeded(channelID: channelID, snapshotMessages: [])
        try? await Task.sleep(for: .milliseconds(10))
        controller.hydrate(from: RealtimeSnapshot(messagesByChannelID: [channelID: [realtime]]))
        let duplicate = await controller.loadInitialIfNeeded(channelID: channelID, snapshotMessages: [realtime])
        let outcome = await initial

        XCTAssertEqual(outcome, .loaded(messageCount: 2))
        XCTAssertEqual(duplicate, .deduplicated)
        XCTAssertEqual(
            controller.state(for: channelID).timelineMessages.map(\.message.id),
            [historical.id, realtime.id]
        )
        let fetchCount = await api.fetchMessagesCallCount
        XCTAssertEqual(fetchCount, 1)
    }

    @MainActor
    func testCancelledInitialHistoryLoadLeavesRecoverableNonErrorState() async {
        let channelID: ChannelID = "history-cancel-channel"
        let api = RecordingAPIClient(fetchMessagesDelayNanoseconds: 100_000_000)
        let controller = ChannelMessageController(
            runtimeMode: .liveManual,
            apiClient: api,
            currentUserID: "history-cancel-user"
        )

        let task = Task {
            await controller.loadInitialIfNeeded(channelID: channelID, snapshotMessages: [])
        }
        try? await Task.sleep(for: .milliseconds(10))
        task.cancel()
        let outcome = await task.value

        XCTAssertEqual(outcome, .cancelled)
        XCTAssertEqual(controller.state(for: channelID), .empty)
        XCTAssertNil(controller.lastErrorByChannelID[channelID])
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
    func testPhase56OptimisticAndConfirmedSendGroupsPaintWithoutPreparationPass() async throws {
        let handler = DelayedMessageActionHandler(delay: .milliseconds(80))
        let model = MainShellViewModel(snapshot: MockShellData.snapshot, messageActionHandler: handler)
        let server = try XCTUnwrap(model.servers.first { $0.name == "Bagel Lab" })
        model.selectServer(server.id)
        let channelID = try XCTUnwrap(model.selection.channelID)
        model.updateDraft("paint immediately", for: channelID)
        let tokenBeforeSend = model.selectedTimelineGroupingToken

        let sendTask = Task { await model.sendDraft(for: channelID) }
        try await Task.sleep(for: .milliseconds(10))

        let optimistic = model.selectedTimelineMessageGroups
            .flatMap(\.messages)
            .first { $0.message.content == "paint immediately" }
        XCTAssertEqual(optimistic?.status, .pending)
        XCTAssertNotEqual(model.selectedTimelineGroupingToken, tokenBeforeSend)

        await sendTask.value
        let confirmed = model.selectedTimelineMessageGroups
            .flatMap(\.messages)
            .first { $0.message.content == "paint immediately" }
        XCTAssertEqual(confirmed?.status, .confirmed)
    }

    @MainActor
    func testPhase61LocalSendPreservesWarmAvatarIdentityAcrossReconciliation() async throws {
        var snapshot = MockShellData.snapshot
        let server = try XCTUnwrap(snapshot.serversByID.values.first { $0.name == "Bagel Lab" })
        let channelID = try XCTUnwrap(snapshot.channelsByID.values.first { $0.displayName == "general" }?.id)
        let userAvatar = File(id: "phase61-user-avatar", tag: "avatars", filename: "user.png", contentType: "image/png", size: 8)
        let memberAvatar = File(id: "phase61-member-avatar", tag: "avatars", filename: "member.png", contentType: "image/png", size: 8)
        snapshot.usersByID[MockShellData.currentUserID]?.avatar = userAvatar
        snapshot.membersByServerAndUserID[ServerMemberKey(serverID: server.id, userID: MockShellData.currentUserID)]?.avatar = memberAvatar

        let handler = DelayedMessageActionHandler(delay: .milliseconds(80))
        let model = MainShellViewModel(snapshot: snapshot, messageActionHandler: handler)
        model.selectServer(server.id)
        model.updateDraft("avatar continuity", for: channelID)

        let sendTask = Task { await model.sendDraft(for: channelID) }
        try await Task.sleep(for: .milliseconds(10))

        let pending = try XCTUnwrap(model.selectedTimelineMessages.first { $0.message.content == "avatar continuity" })
        XCTAssertEqual(pending.status, .pending)
        XCTAssertEqual(pending.message.user?.avatar?.id, userAvatar.id)
        XCTAssertEqual(pending.message.member?.avatar?.id, memberAvatar.id)
        XCTAssertEqual(model.pendingRowFallbackPresentation(for: pending)?.authorDisplay.avatarFile?.id, memberAvatar.id)

        await sendTask.value

        let confirmed = try XCTUnwrap(model.selectedTimelineMessages.first { $0.message.content == "avatar continuity" })
        XCTAssertEqual(confirmed.status, .confirmed)
        XCTAssertEqual(confirmed.message.user?.avatar?.id, userAvatar.id)
        XCTAssertEqual(confirmed.message.member?.avatar?.id, memberAvatar.id)
        XCTAssertEqual(model.pendingRowFallbackPresentation(for: confirmed)?.authorDisplay.avatarFile?.id, memberAvatar.id)
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
    func testPhase61PastedImageQueuesComposerAttachmentWithoutUploading() async throws {
        let uploader = MockAttachmentUploadHandler()
        let model = MainShellViewModel(snapshot: MockShellData.snapshot, attachmentUploadHandler: uploader)
        let channelID = model.snapshot.channelsByID.values.first { $0.displayName == "general" }!.id

        model.addPastedImageData(Data(repeating: 2, count: 32), to: channelID)

        XCTAssertNil(model.pendingAttachmentDrop)
        let attachment = try XCTUnwrap(model.composerDraftState(for: channelID).attachments.first)
        XCTAssertEqual(attachment.filename, "Pasted Image.png")
        XCTAssertEqual(attachment.kind, .image)
        XCTAssertEqual(attachment.previewData, Data(repeating: 2, count: 32))
        let uploadCount = await uploader.uploadCount()
        XCTAssertEqual(uploadCount, 0)
    }

    @MainActor
    func testPhase61PastedImageCanSendAttachmentOnly() async throws {
        let uploader = MockAttachmentUploadHandler()
        let handler = RecordingAttachmentMessageActionHandler()
        let model = MainShellViewModel(snapshot: MockShellData.snapshot, messageActionHandler: handler, attachmentUploadHandler: uploader)
        let server = model.servers.first { $0.name == "Bagel Lab" }!
        model.selectServer(server.id)
        let channelID = model.selection.channelID!

        model.addPastedImageData(Data([137, 80, 78, 71]), to: channelID)
        await model.sendDraft(for: channelID)

        let uploadCount = await uploader.uploadCount()
        let sent = await handler.sentSnapshot()
        XCTAssertEqual(uploadCount, 1)
        XCTAssertEqual(sent.first?.content, "")
        XCTAssertEqual(sent.first?.attachments?.count, 1)
        XCTAssertTrue(model.composerDraftState(for: channelID).attachments.isEmpty)
    }

    @MainActor
    func testPhase61PastedFileURLsQueueComposerAttachmentsWithoutReviewOrUpload() async throws {
        let uploader = MockAttachmentUploadHandler()
        let model = MainShellViewModel(snapshot: MockShellData.snapshot, attachmentUploadHandler: uploader)
        let channelID = model.snapshot.channelsByID.values.first { $0.displayName == "general" }!.id
        let url = try makeTemporaryAttachment(name: "pasted-file.txt", contents: Data("paste".utf8))

        model.addAttachmentURLs([url], to: channelID)

        XCTAssertNil(model.pendingAttachmentDrop)
        XCTAssertTrue(model.composerDraftState(for: channelID).attachments.first?.filename.hasSuffix("pasted-file.txt") == true)
        let uploadCount = await uploader.uploadCount()
        XCTAssertEqual(uploadCount, 0)
    }

    @MainActor
    func testPhase61InvalidPastedImageAndMissingChannelStayOutOfComposer() {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot)
        let channelID = model.snapshot.channelsByID.values.first { $0.displayName == "general" }!.id

        model.addPastedImageData(Data(repeating: 1, count: AttachmentUploadLimits.maxFileBytes + 1), to: channelID)

        XCTAssertTrue(model.composerDraftState(for: channelID).attachments.isEmpty)
        XCTAssertEqual(model.composerError, "File too large. Liquid Bagel currently supports files up to 20 MB.")

        model.addPastedImageData(Data(repeating: 2, count: 32), to: nil)

        XCTAssertTrue(model.composerDraftState(for: nil).attachments.isEmpty)
        XCTAssertEqual(model.composerError, "Select a channel or DM before attaching files.")
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

        model.perform(.openAppearanceSettings)
        XCTAssertEqual(model.selectedSettingsTab, .appearance)
        XCTAssertTrue(model.isCredentialSetupPresented)
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
    func testAppearancePreferencesSyncFromSessionCoordinator() async throws {
        var preferences = AppPreferences.defaults
        preferences.messageDensity = .compact
        preferences.liquidGlassTransparency = 0.55
        let session = AppSessionCoordinator(
            preferencesStore: InMemoryAppPreferencesStore(preferences: preferences),
            apiClientFactory: { _, _ in RecordingAPIClient() }
        )
        await session.startMockSession()
        let model = MainShellViewModel(snapshot: MockShellData.snapshot, sessionCoordinator: session)

        model.syncFromSessionCoordinator()

        XCTAssertEqual(model.messageDensity, .compact)
        XCTAssertEqual(model.liquidGlassTransparency, 0.55)
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

        model.quickSwitcherViewModel.query = "appearance"
        XCTAssertTrue(model.quickSwitcherViewModel.results.contains { $0.title == "Appearance Settings" })
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

    @MainActor
    func testPhase58MarkChannelReadCommandRoutes() throws {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot)
        let channel = try XCTUnwrap(model.snapshot.channelsByID.values.first { $0.displayName == "macos-native" })
        model.selectChannel(channel.id)
        let mentionCountBefore = model.localReadStates[channel.id]?.mentionCount ?? 0
        XCTAssertGreaterThan(mentionCountBefore, 0)

        XCTAssertTrue(model.canPerform(.markSelectedChannelRead))
        model.perform(.markSelectedChannelRead)

        // Mock-source acks clear unreadCount but intentionally preserve mentionCount (matching
        // Phase 9's testPhase9LocalUnreadStatePreservesMentionAndJumpsFirstUnread convention) --
        // only a real live ack round-trip clears mentions.
        XCTAssertEqual(model.localReadStates[channel.id]?.unreadCount, 0)
        XCTAssertEqual(model.localReadStates[channel.id]?.mentionCount, mentionCountBefore)
        XCTAssertEqual(model.focusTarget, .composer)
        if let newest = model.selectedTimelineMessages.last {
            XCTAssertEqual(model.timelineSelection.messageID, newest.message.id)
        }
    }

    @MainActor
    func testPhase58MarkServerReadCommandActsOnEveryChannel() throws {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot)
        let channel = try XCTUnwrap(model.snapshot.channelsByID.values.first { $0.displayName == "macos-native" })
        guard let serverID = channel.serverID else {
            XCTFail("Expected a server channel")
            return
        }
        model.selectChannel(channel.id)
        XCTAssertGreaterThan(model.localReadStates[channel.id]?.mentionCount ?? 0, 0)
        model.selection = ShellSelection(space: .server(serverID), serverID: serverID)

        XCTAssertTrue(model.canPerform(.markSelectedServerRead))
        model.perform(.markSelectedServerRead)

        XCTAssertEqual(model.localReadStates[channel.id]?.unreadCount, 0)
    }

    @MainActor
    func testPhase58MarkChannelAndServerReadDisabledWithoutSelection() {
        let model = MainShellViewModel(snapshot: RealtimeSnapshot())
        XCTAssertFalse(model.canPerform(.markSelectedChannelRead))
        XCTAssertFalse(model.canPerform(.markSelectedServerRead))
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

    @MainActor
    func testPhase55DockBadgeUpdatesAreDedupedAcrossLifecycleChurn() async throws {
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
        model.updateAppLifecyclePhase(.inactive)
        model.updateAppLifecyclePhase(.background)
        try await Task.sleep(for: .milliseconds(30))

        let counts = await dock.badgeCounts
        XCTAssertEqual(counts.last, expectedBadge)
        XCTAssertEqual(counts.filter { $0 == expectedBadge }.count, 1)
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
    func testPhase56TimelineRowCacheDoesNotPinPreviewDataAndHydratesLiveState() async throws {
        let serverID: ServerID = "phase56-media-server"
        let channelID: ChannelID = "phase56-media-channel"
        var snapshot = RealtimeSnapshot()
        snapshot.serversByID[serverID] = Server(id: serverID, ownerID: "phase56-owner", name: "Phase56 Media", channelIDs: [channelID])
        snapshot.channelsByID[channelID] = Channel(id: channelID, kind: .textChannel, serverID: serverID, name: "media")
        let file = File(id: "phase56-image", tag: "attachments", filename: "photo.png", metadata: .image(width: 10, height: 10, thumbhash: nil, animated: false), contentType: "image/png", size: 100)
        let message = Message(id: "01J00000000000000000560001", channelID: channelID, authorID: "phase56-author", content: "look", attachments: [file])
        snapshot.messagesByChannelID[channelID] = [message]
        let data = Data("png-bytes".utf8)
        let loader = MockImageResourceLoader(result: .success(data))
        let model = MainShellViewModel(selection: ShellSelection(space: .server(serverID), serverID: serverID, channelID: channelID), snapshot: snapshot, imageResourceLoader: loader)

        await model.prepareSelectedTimelinePresentation()
        let cachedBefore = model.timelineRowPresentation(for: message.id)
        XCTAssertNil(cachedBefore?.attachmentItems.first?.previewData, "row cache must not pin preview data")
        let hydratedBefore = model.hydratedAttachmentItems(cachedBefore?.attachmentItems ?? [])
        XCTAssertEqual(hydratedBefore.first?.previewState, .notLoaded)

        model.loadImageResource(for: file, kind: .attachmentPreview)
        for _ in 0..<40 {
            if model.imageData(for: file, kind: .attachmentPreview) != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }

        let cachedAfter = model.timelineRowPresentation(for: message.id)
        XCTAssertNil(cachedAfter?.attachmentItems.first?.previewData, "row cache must still not pin preview data after a load completes")
        let hydratedAfter = model.hydratedAttachmentItems(cachedAfter?.attachmentItems ?? [])
        XCTAssertEqual(hydratedAfter.first?.previewData, data)
        XCTAssertEqual(hydratedAfter.first?.previewState, .readyRemote)
    }

    @MainActor
    func testPhase56TimelineMediaInvalidationCoalescesIntoOneRebuild() async throws {
        let serverID: ServerID = "phase56-coalesce-server"
        let channelID: ChannelID = "phase56-coalesce-channel"
        var snapshot = RealtimeSnapshot()
        snapshot.serversByID[serverID] = Server(id: serverID, ownerID: "phase56-owner", name: "Phase56 Coalesce", channelIDs: [channelID])
        snapshot.channelsByID[channelID] = Channel(id: channelID, kind: .textChannel, serverID: serverID, name: "media")
        let files = (0..<3).map { index in
            File(id: FileID(rawValue: "phase56-coalesce-\(index)"), tag: "attachments", filename: "\(index).png", metadata: .image(width: 10, height: 10, thumbhash: nil, animated: false), contentType: "image/png", size: 100)
        }
        let message = Message(id: "01J00000000000000000560002", channelID: channelID, authorID: "phase56-author", content: "look", attachments: files)
        snapshot.messagesByChannelID[channelID] = [message]
        let loader = MockImageResourceLoader(result: .success(Data("png-bytes".utf8)))
        let model = MainShellViewModel(selection: ShellSelection(space: .server(serverID), serverID: serverID, channelID: channelID), snapshot: snapshot, imageResourceLoader: loader)

        await model.prepareSelectedTimelinePresentation()
        let rowBuildCountBeforeLoads = model.timelinePresentationDiagnostics.rowBuildCount

        for file in files {
            model.loadImageResource(for: file, kind: .attachmentPreview)
        }
        for _ in 0..<40 {
            if files.allSatisfy({ model.imageData(for: $0, kind: .attachmentPreview) != nil }) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        // Give the coalesced Task.yield()-based rebuild a chance to run and settle.
        for _ in 0..<10 {
            await model.prepareSelectedTimelinePresentation()
            try await Task.sleep(for: .milliseconds(10))
        }

        let rowBuildCountAfterLoads = model.timelinePresentationDiagnostics.rowBuildCount
        XCTAssertLessThanOrEqual(
            rowBuildCountAfterLoads - rowBuildCountBeforeLoads,
            2,
            "three near-simultaneous image loads should coalesce into at most one extra row rebuild, not one per image"
        )
        let hydrated = model.hydratedAttachmentItems(model.timelineRowPresentation(for: message.id)?.attachmentItems ?? [])
        XCTAssertTrue(hydrated.allSatisfy { $0.previewState == .readyRemote })
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
    func testPhase55MemberListHoistedSectionsRankOrderAndOfflineAtBottom() {
        var snapshot = RealtimeSnapshot()
        let serverID: ServerID = "phase55-members-server"
        let hoistedTopID: RoleID = "phase55-hoisted-top"
        let hoistedLowID: RoleID = "phase55-hoisted-low"
        let plainRoleID: RoleID = "phase55-plain-role"
        snapshot.serversByID[serverID] = Server(id: serverID, ownerID: "phase55-owner", name: "Phase 55", roles: [
            hoistedTopID: Role(id: hoistedTopID, name: "Admins", permissions: PermissionOverride(), hoist: true, rank: 1),
            hoistedLowID: Role(id: hoistedLowID, name: "Regulars", permissions: PermissionOverride(), hoist: true, rank: 20),
            plainRoleID: Role(id: plainRoleID, name: "Cosmetic", permissions: PermissionOverride(), hoist: false, rank: 0)
        ])

        func addMember(_ id: String, roles memberRoles: [RoleID] = [], online: Bool) {
            let userID = UserID(rawValue: id)
            snapshot.usersByID[userID] = User(id: userID, username: id, online: online)
            snapshot.membersByServerAndUserID[ServerMemberKey(serverID: serverID, userID: userID)] = ServerMember(
                id: MemberCompositeKey(serverID: serverID, userID: userID),
                joinedAt: Date(),
                roles: memberRoles
            )
        }

        addMember("phase55-owner", online: true)
        addMember("phase55-admin", roles: [hoistedLowID, hoistedTopID], online: true)
        addMember("phase55-regular", roles: [hoistedLowID, plainRoleID], online: true)
        addMember("phase55-cosmetic-only", roles: [plainRoleID], online: true)
        addMember("phase55-nobody", online: true)
        addMember("phase55-sleepy-admin", roles: [hoistedTopID], online: false)
        addMember("phase55-sleepy", online: false)

        let result = MemberListDeriver.result(server: snapshot.serversByID[serverID], snapshot: snapshot)

        XCTAssertEqual(result.groups.map(\.id), [
            "owner",
            "role-\(hoistedTopID.rawValue)",
            "role-\(hoistedLowID.rawValue)",
            "online",
            "offline"
        ])
        XCTAssertEqual(result.groups.first { $0.id == "role-\(hoistedTopID.rawValue)" }?.items.map(\.userID), ["phase55-admin"])
        XCTAssertEqual(result.groups.first { $0.id == "role-\(hoistedLowID.rawValue)" }?.items.map(\.userID), ["phase55-regular"])
        XCTAssertEqual(result.groups.first { $0.id == "online" }?.items.map(\.userID), ["phase55-cosmetic-only", "phase55-nobody"])
        XCTAssertEqual(result.groups.first { $0.id == "offline" }?.items.map(\.userID), ["phase55-sleepy", "phase55-sleepy-admin"])
    }

    func testPhase56MemberPanelRowLimiterCapsOnlyOfflineGroup() {
        let items = (0..<2000).map { index in
            MemberListItem(userID: UserID(rawValue: "phase56-user-\(index)"), user: nil, member: nil)
        }
        let offlineGroup = MemberListGroup(id: "offline", title: "Offline - 2000", items: items)
        let limitedOffline = MemberPanelRowLimiter.visibleItems(for: offlineGroup)
        XCTAssertEqual(limitedOffline.items.count, 200)
        XCTAssertEqual(limitedOffline.remainder, 1800)

        let onlineGroup = MemberListGroup(id: "online", title: "Online - 2000", items: items)
        let limitedOnline = MemberPanelRowLimiter.visibleItems(for: onlineGroup)
        XCTAssertEqual(limitedOnline.items.count, 2000)
        XCTAssertEqual(limitedOnline.remainder, 0)

        let smallOffline = MemberListGroup(id: "offline", title: "Offline - 5", items: Array(items.prefix(5)))
        let limitedSmallOffline = MemberPanelRowLimiter.visibleItems(for: smallOffline)
        XCTAssertEqual(limitedSmallOffline.items.count, 5)
        XCTAssertEqual(limitedSmallOffline.remainder, 0)
    }

    @MainActor
    func testPhase57LargeMemberAvatarLoadingIsVisibilityDrivenInsteadOfBulkPrequeued() async throws {
        let serverID: ServerID = "phase56-prequeue-server"
        let hoistedRoleID: RoleID = "phase56-prequeue-role"
        var snapshot = RealtimeSnapshot()
        snapshot.serversByID[serverID] = Server(id: serverID, ownerID: "phase56-prequeue-owner", name: "Phase56 PreQueue", roles: [
            hoistedRoleID: Role(id: hoistedRoleID, name: "Staff", permissions: PermissionOverride(), hoist: true, rank: 1)
        ])
        snapshot.usersByID["phase56-prequeue-owner"] = User(id: "phase56-prequeue-owner", username: "owner", online: true)
        snapshot.membersByServerAndUserID[ServerMemberKey(serverID: serverID, userID: "phase56-prequeue-owner")] = ServerMember(id: MemberCompositeKey(serverID: serverID, userID: "phase56-prequeue-owner"), joinedAt: Date())
        // A couple of small hoisted-role groups that would previously exhaust a "first 4
        // groups" cap before reaching the much larger Online fallback group below.
        for index in 0..<2 {
            let userID = UserID(rawValue: "phase56-staff-\(index)")
            snapshot.usersByID[userID] = User(id: userID, username: "staff\(index)", online: true)
            snapshot.membersByServerAndUserID[ServerMemberKey(serverID: serverID, userID: userID)] = ServerMember(id: MemberCompositeKey(serverID: serverID, userID: userID), joinedAt: Date(), roles: [hoistedRoleID])
        }
        for index in 0..<60 {
            let userID = UserID(rawValue: "phase56-online-\(index)")
            let file = File(id: FileID(rawValue: "phase56-online-avatar-\(index)"), tag: "avatars", filename: "a\(index).png", contentType: "image/png", size: 10)
            snapshot.usersByID[userID] = User(id: userID, username: "online\(index)", avatar: file, online: true)
            snapshot.membersByServerAndUserID[ServerMemberKey(serverID: serverID, userID: userID)] = ServerMember(id: MemberCompositeKey(serverID: serverID, userID: userID), joinedAt: Date())
        }
        let loader = MockImageResourceLoader(result: .success(Data("avatar".utf8)))
        let model = MainShellViewModel(selection: ShellSelection(space: .server(serverID), serverID: serverID), snapshot: snapshot, imageResourceLoader: loader)
        await model.prepareMemberListGroups(for: serverID)

        model.reloadVisibleImages()
        try await Task.sleep(for: .milliseconds(20))
        var calls = await loader.calls
        XCTAssertFalse(calls.contains(where: { $0.id == "phase56-online-avatar-30" }), "large member lists must not bulk-prequeue offscreen avatars")

        let visibleAvatar = snapshot.usersByID["phase56-online-30"]?.avatar
        model.imageResourceBecameVisible(visibleAvatar, kind: .userAvatar, consumerID: "member-panel-avatar-phase56-online-30")
        for _ in 0..<40 {
            calls = await loader.calls
            if calls.contains(where: { $0.id == "phase56-online-avatar-30" }) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(calls.contains(where: { $0.id == "phase56-online-avatar-30" }))
        let diagnostics = await model.imageResourceDiagnostics()
        XCTAssertEqual(diagnostics.visibleResourceCount, 1)
    }

    @MainActor
    func testPhase56MessageOnlySnapshotChangeDoesNotForceMemberListRederivation() async throws {
        let serverID: ServerID = "phase56-fp-server"
        let channelID: ChannelID = "phase56-fp-channel"
        var snapshot = RealtimeSnapshot()
        snapshot.serversByID[serverID] = Server(id: serverID, ownerID: "phase56-owner", name: "Phase56")
        snapshot.channelsByID[channelID] = Channel(id: channelID, kind: .textChannel, serverID: serverID, name: "general")
        for index in 0..<5 {
            let userID = UserID(rawValue: "phase56-user-\(index)")
            snapshot.usersByID[userID] = User(id: userID, username: "user\(index)", online: true)
            snapshot.membersByServerAndUserID[ServerMemberKey(serverID: serverID, userID: userID)] = ServerMember(
                id: MemberCompositeKey(serverID: serverID, userID: userID),
                joinedAt: Date()
            )
        }
        let model = MainShellViewModel(selection: ShellSelection(space: .server(serverID), serverID: serverID, channelID: channelID), snapshot: snapshot)

        await model.prepareMemberListGroups(for: serverID)
        let revisionAfterFirstPrepare = model.memberListGroupsRevision
        XCTAssertEqual(revisionAfterFirstPrepare, 1)

        var messageOnlySnapshot = model.snapshot
        messageOnlySnapshot.messagesByChannelID[channelID, default: []].append(
            Message(id: MessageID(rawValue: ulid(milliseconds: 1)), channelID: channelID, authorID: "phase56-user-0", content: "hi")
        )
        model.replaceSnapshotForTesting(messageOnlySnapshot, changes: RealtimeSnapshotChangeSet(messageChannelIDs: [channelID]))
        await model.prepareMemberListGroups(for: serverID)
        XCTAssertEqual(model.memberListGroupsRevision, revisionAfterFirstPrepare, "message-only snapshot churn must not force a full member re-derivation")

        let flippedUserID = UserID(rawValue: "phase56-user-0")
        var presenceOnlySnapshot = model.snapshot
        presenceOnlySnapshot.usersByID[flippedUserID]?.online = false
        model.replaceSnapshotForTesting(presenceOnlySnapshot, changes: RealtimeSnapshotChangeSet(userIDs: [flippedUserID]))
        await model.prepareMemberListGroups(for: serverID)
        XCTAssertGreaterThan(model.memberListGroupsRevision, revisionAfterFirstPrepare, "a member's online status changing must trigger re-derivation")
        let groups = model.cachedMemberListGroups(for: serverID)
        XCTAssertTrue(groups.first { $0.id == "offline" }?.items.map(\.userID).contains(UserID(rawValue: "phase56-user-0")) == true)
    }

    @MainActor
    func testPhase55MediaSafeModeResetsAfterImageQueueDrains() async throws {
        let loader = SlowImageResourceLoader(delayNanoseconds: 10_000_000)
        let model = MainShellViewModel(runtimeMode: .mock, imageResourceLoader: loader)
        for index in 0..<32 {
            let file = File(id: FileID(rawValue: "phase55-safemode-\(index)"), tag: "attachments", filename: "\(index).png", contentType: "image/png", size: 1)
            model.loadImageResource(for: file, kind: .attachmentPreview)
        }
        XCTAssertTrue(model.freezePerformanceDiagnostics.mediaSafeModeEnabled)

        for _ in 0..<200 {
            let diagnostics = await model.imageResourceDiagnostics()
            if diagnostics.queuedTaskCount == 0, diagnostics.activeTaskCount == 0 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertFalse(model.freezePerformanceDiagnostics.mediaSafeModeEnabled)
    }

    @MainActor
    func testPhase55InlinePreviewQueueDrainsBeyondConcurrencyLimit() async throws {
        let data = Data("png".utf8)
        let loader = MockRemoteAttachmentLoader(result: .success(RemoteAttachmentData(filename: "photo.png", contentType: "image/png", byteCount: data.count, data: data)))
        let model = MainShellViewModel(snapshot: MockShellData.snapshot, remoteAttachmentLoader: loader)
        let files = (0..<10).map { index in
            File(id: FileID(rawValue: "phase55-inline-\(index)"), tag: "attachments", filename: "photo\(index).png", metadata: .image(width: 10, height: 10, thumbhash: nil, animated: false), contentType: "image/png", size: 100)
        }
        let message = Message(id: "01J00000000000000000550001", channelID: "01HX0000000000000000000101", authorID: MockShellData.currentUserID, attachments: files)

        model.loadInlineImagePreviews(for: message)
        for _ in 0..<100 {
            let states = model.attachmentDisplayItems(for: message).map(\.previewState)
            if states.allSatisfy({ $0 == .readyRemote }) { break }
            try await Task.sleep(for: .milliseconds(10))
        }

        let callCount = await loader.callCount()
        XCTAssertEqual(callCount, 10)
        XCTAssertTrue(model.attachmentDisplayItems(for: message).allSatisfy { $0.previewState == .readyRemote })
    }

    @MainActor
    func testPhase55FailedImageResourceRetriesWithBackoffForAllKinds() async throws {
        let loader = MockImageResourceLoader(result: .failure(AttachmentActionError.unavailable("nope")))
        let model = MainShellViewModel(runtimeMode: .mock, imageResourceLoader: loader)
        let clock = Phase55TestClock(now: Date())
        model.setPhase43NowProvider { clock.now }
        let file = File(id: "phase55-banner", tag: "banners", filename: "banner.png", contentType: "image/png", size: 10)

        model.loadImageResource(for: file, kind: .serverBanner)
        try await Task.sleep(for: .milliseconds(30))
        let afterFirst = await loader.callCount()
        XCTAssertEqual(afterFirst, 1)

        model.loadImageResource(for: file, kind: .serverBanner)
        try await Task.sleep(for: .milliseconds(30))
        let withinBackoff = await loader.callCount()
        XCTAssertEqual(withinBackoff, 1)

        clock.now = clock.now.addingTimeInterval(6)
        model.loadImageResource(for: file, kind: .serverBanner)
        try await Task.sleep(for: .milliseconds(30))
        let afterBackoff = await loader.callCount()
        XCTAssertEqual(afterBackoff, 2)
    }

    @MainActor
    func testPhase57ImageDataMissIsCacheOnlyAndExplicitVisibilityDeduplicatesReload() async throws {
        let data = Data("avatar".utf8)
        let loader = MockImageResourceLoader(result: .success(data))
        let model = MainShellViewModel(runtimeMode: .mock, imageResourceLoader: loader)
        let file = File(id: "phase56-avatar-reload", tag: "avatars", filename: "avatar.png", contentType: "image/png", size: data.count)

        XCTAssertNil(model.imageData(for: file, kind: .userAvatar))
        XCTAssertNil(model.imageData(for: file, kind: .userAvatar))
        try await Task.sleep(for: .milliseconds(20))
        var callCount = await loader.callCount()
        XCTAssertEqual(callCount, 0)

        model.imageResourceBecameVisible(file, kind: .userAvatar, consumerID: "timeline-avatar-test")
        model.imageResourceBecameVisible(file, kind: .userAvatar, consumerID: "timeline-avatar-test")
        for _ in 0..<50 {
            if model.imageData(for: file, kind: .userAvatar) == data { break }
            try await Task.sleep(for: .milliseconds(5))
        }

        XCTAssertEqual(model.imageData(for: file, kind: .userAvatar), data)
        callCount = await loader.callCount()
        XCTAssertEqual(callCount, 1)
    }

    @MainActor
    func testPhase57VisibleImageSurvivesPressureAndEvictedImageDoesNotReloadLoop() async throws {
        let data = Data(repeating: 7, count: 40 * 1024 * 1024)
        let loader = MockImageResourceLoader(result: .success(data))
        let model = MainShellViewModel(runtimeMode: .mock, imageResourceLoader: loader)
        let pinned = File(id: "phase57-pinned", tag: "avatars", filename: "pinned.png", contentType: "image/png", size: data.count)
        let unpinned = File(id: "phase57-unpinned", tag: "avatars", filename: "unpinned.png", contentType: "image/png", size: data.count)

        model.imageResourceBecameVisible(pinned, kind: .userAvatar, consumerID: "member-panel-avatar-pinned")
        for _ in 0..<80 {
            if model.imageData(for: pinned, kind: .userAvatar) != nil { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        model.loadImageResource(for: unpinned, kind: .userAvatar)
        for _ in 0..<80 {
            let diagnostics = await model.imageResourceDiagnostics()
            if diagnostics.presentationEvictionCount > 0 { break }
            try await Task.sleep(for: .milliseconds(5))
        }

        XCTAssertNotNil(model.imageData(for: pinned, kind: .userAvatar))
        XCTAssertNil(model.imageData(for: unpinned, kind: .userAvatar))
        var diagnostics = await model.imageResourceDiagnostics()
        XCTAssertEqual(diagnostics.presentationEvictionCount, 1)
        XCTAssertEqual(diagnostics.reloadAfterEvictionCount, 0)

        model.imageResourceBecameVisible(unpinned, kind: .userAvatar, consumerID: "member-panel-avatar-unpinned")
        for _ in 0..<80 {
            diagnostics = await model.imageResourceDiagnostics()
            if diagnostics.reloadAfterEvictionCount == 1,
               diagnostics.activeTaskCount == 0,
               diagnostics.queuedTaskCount == 0 {
                break
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        try await Task.sleep(for: .milliseconds(30))
        diagnostics = await model.imageResourceDiagnostics()
        XCTAssertEqual(diagnostics.reloadAfterEvictionCount, 1)
        XCTAssertEqual(diagnostics.activeTaskCount, 0)
        XCTAssertEqual(diagnostics.queuedTaskCount, 0)
        let loaderCallCount = await loader.callCount()
        XCTAssertEqual(loaderCallCount, 3)
    }

    @MainActor
    func testPhase62CurrentUserRailAvatarStaysPinnedAndTransfersVisibility() async throws {
        let data = Data(repeating: 9, count: 40 * 1024 * 1024)
        let loader = MockImageResourceLoader(result: .success(data))
        let model = MainShellViewModel(runtimeMode: .mock, imageResourceLoader: loader)
        let original = File(id: "phase62-rail-original", tag: "avatars", filename: "original.png", contentType: "image/png", size: data.count)
        let pressure = File(id: "phase62-pressure", tag: "avatars", filename: "pressure.png", contentType: "image/png", size: data.count)
        let replacement = File(id: "phase62-rail-replacement", tag: "avatars", filename: "replacement.png", contentType: "image/png", size: data.count)

        model.currentUserRailAvatarBecameVisible(original)
        for _ in 0..<80 {
            if model.imageData(for: original, kind: .userAvatar) != nil { break }
            try await Task.sleep(for: .milliseconds(5))
        }

        model.loadImageResource(for: pressure, kind: .userAvatar)
        for _ in 0..<80 {
            let diagnostics = await model.imageResourceDiagnostics()
            if diagnostics.presentationEvictionCount > 0 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertNotNil(model.imageData(for: original, kind: .userAvatar))
        XCTAssertNil(model.imageData(for: pressure, kind: .userAvatar))

        model.currentUserRailAvatarBecameVisible(replacement)
        for _ in 0..<80 {
            if model.imageData(for: replacement, kind: .userAvatar) != nil { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertNil(model.imageData(for: original, kind: .userAvatar))
        XCTAssertNotNil(model.imageData(for: replacement, kind: .userAvatar))
    }

    @MainActor
    func testPhase62PartialMessageIdentityDoesNotInvalidatePinnedAvatar() async throws {
        let data = Data("phase62-avatar".utf8)
        let loader = MockImageResourceLoader(result: .success(data))
        let model = MainShellViewModel(runtimeMode: .mock, imageResourceLoader: loader)
        let userID = UserID(rawValue: "phase62-partial-user")
        let avatar = File(id: "phase62-partial-avatar", tag: "avatars", filename: "avatar.png", contentType: "image/png", size: data.count)
        let completeUser = User(id: userID, username: "phase62", displayName: "Phase 62", avatar: avatar)
        let partialUser = User(id: userID, username: "phase62")

        model.noteVisibleIdentity(userID: userID, user: completeUser, source: .visibleMessage)
        model.imageResourceBecameVisible(avatar, kind: .userAvatar, consumerID: "shell-current-user-avatar")
        for _ in 0..<80 {
            if model.imageData(for: avatar, kind: .userAvatar) != nil { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let before = await model.imageResourceDiagnostics()

        for _ in 0..<20 {
            model.noteVisibleIdentity(userID: userID, user: partialUser, source: .visibleMessage)
        }

        let after = await model.imageResourceDiagnostics()
        XCTAssertNotNil(model.imageData(for: avatar, kind: .userAvatar))
        XCTAssertEqual(after.presentationEvictionCount, before.presentationEvictionCount)
        XCTAssertEqual(after.reloadAfterEvictionCount, before.reloadAfterEvictionCount)
    }

    func testPhase62AvatarCacheTransitionIsSourceAware() {
        let original = File(id: "phase62-policy-original", tag: "avatars", filename: "original.png", contentType: "image/png", size: 1)
        let replacement = File(id: "phase62-policy-replacement", tag: "avatars", filename: "replacement.png", contentType: "image/png", size: 1)

        XCTAssertEqual(
            Phase43AvatarCacheTransition.resolve(previous: original, incoming: nil, source: .messageUser),
            .preserve
        )
        XCTAssertEqual(
            Phase43AvatarCacheTransition.resolve(previous: original, incoming: nil, source: .readyUser),
            .preserve
        )
        XCTAssertEqual(
            Phase43AvatarCacheTransition.resolve(previous: original, incoming: replacement, source: .messageUser),
            .replace(previous: original, next: replacement)
        )
        XCTAssertEqual(
            Phase43AvatarCacheTransition.resolve(previous: original, incoming: nil, source: .realtimeUserUpdate),
            .remove(previous: original)
        )
        XCTAssertEqual(
            Phase43AvatarCacheTransition.resolve(previous: original, incoming: nil, source: .currentUserEdit),
            .remove(previous: original)
        )
        XCTAssertEqual(
            Phase43ServerAvatarCacheTransition.resolve(previous: original, incoming: nil, source: .readyMember),
            .preserve
        )
        XCTAssertEqual(
            Phase43ServerAvatarCacheTransition.resolve(previous: original, incoming: replacement, source: .readyMember),
            .replace(previous: original, next: replacement)
        )
        XCTAssertEqual(
            Phase43ServerAvatarCacheTransition.resolve(previous: original, incoming: nil, source: .realtimeMemberUpdate),
            .remove(previous: original)
        )
    }

    @MainActor
    func testPhase62MemberOverlayDoesNotOscillateGlobalAvatarCache() async throws {
        let data = Data("phase62-member-avatar".utf8)
        let loader = MockImageResourceLoader(result: .success(data))
        let model = MainShellViewModel(runtimeMode: .mock, imageResourceLoader: loader)
        let userID = UserID(rawValue: "phase62-member-user")
        let serverID = ServerID(rawValue: "phase62-member-server")
        let globalAvatar = File(id: "phase62-global-avatar", tag: "avatars", filename: "global.png", contentType: "image/png", size: data.count)
        let memberAvatar = File(id: "phase62-server-avatar", tag: "avatars", filename: "member.png", contentType: "image/png", size: data.count)
        let user = User(id: userID, username: "phase62", avatar: globalAvatar)
        let member = ServerMember(
            id: MemberCompositeKey(serverID: serverID, userID: userID),
            joinedAt: Date(),
            avatar: memberAvatar
        )

        model.imageResourceBecameVisible(globalAvatar, kind: .userAvatar, consumerID: "phase62-global-consumer")
        model.memberAvatarBecameVisible(memberAvatar, consumerID: "member-panel-avatar-\(serverID.rawValue)-\(userID.rawValue)")
        for _ in 0..<80 {
            if model.imageData(for: globalAvatar, kind: .userAvatar) != nil,
               model.imageData(for: memberAvatar, kind: .userAvatar) != nil { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let before = await model.imageResourceDiagnostics()

        for _ in 0..<20 {
            model.noteVisibleIdentity(userID: userID, user: user, member: member, serverID: serverID, source: .visibleMember)
        }

        let identity = model.phase43IdentitySnapshot(for: userID)
        let after = await model.imageResourceDiagnostics()
        XCTAssertEqual(identity?.avatarFile?.id, globalAvatar.id)
        XCTAssertEqual(identity?.serverOverlays[serverID]?.avatarFile?.id, memberAvatar.id)
        XCTAssertNotNil(model.imageData(for: globalAvatar, kind: .userAvatar))
        XCTAssertNotNil(model.imageData(for: memberAvatar, kind: .userAvatar))
        XCTAssertEqual(after.presentationEvictionCount, before.presentationEvictionCount)
        XCTAssertEqual(after.reloadAfterEvictionCount, before.reloadAfterEvictionCount)
    }

    @MainActor
    func testPhase62MemberAvatarVisibilityGraceCancelsAndClears() async throws {
        let data = Data("phase62-member-grace".utf8)
        let loader = MockImageResourceLoader(result: .success(data))
        let model = MainShellViewModel(runtimeMode: .mock, imageResourceLoader: loader)
        let avatar = File(id: "phase62-member-grace", tag: "avatars", filename: "member.png", contentType: "image/png", size: data.count)
        let consumerID = "member-panel-avatar-server-user"

        model.memberAvatarBecameVisible(avatar, consumerID: consumerID)
        model.memberAvatarBecameHidden(consumerID: consumerID)
        XCTAssertEqual(model.pendingMemberAvatarHideCount, 1)
        model.memberAvatarBecameVisible(avatar, consumerID: consumerID)
        XCTAssertEqual(model.pendingMemberAvatarHideCount, 0)

        model.memberAvatarBecameHidden(consumerID: consumerID)
        model.clearMemberAvatarVisibility()
        XCTAssertEqual(model.pendingMemberAvatarHideCount, 0)
        try await Task.sleep(for: .milliseconds(800))
        XCTAssertEqual(model.pendingMemberAvatarHideCount, 0)
    }

    @MainActor
    func testPhase63TimelineAvatarHideGraceCancelsAndClears() async throws {
        let data = Data("phase63-timeline-grace".utf8)
        let loader = MockImageResourceLoader(result: .success(data))
        let model = MainShellViewModel(runtimeMode: .mock, imageResourceLoader: loader)
        let avatar = File(id: "phase63-timeline-grace", tag: "avatars", filename: "author.png", contentType: "image/png", size: data.count)
        let consumerID = "timeline-avatar-channel-row"

        model.timelineAvatarBecameVisible(avatar, consumerID: consumerID)
        model.timelineAvatarBecameHidden(consumerID: consumerID)
        XCTAssertEqual(model.pendingTimelineAvatarHideCount, 1)
        model.timelineAvatarBecameVisible(avatar, consumerID: consumerID)
        XCTAssertEqual(model.pendingTimelineAvatarHideCount, 0)

        model.timelineAvatarBecameHidden(consumerID: consumerID)
        model.clearTimelineVisibilityGrace()
        XCTAssertEqual(model.pendingTimelineAvatarHideCount, 0)
        try await Task.sleep(for: .milliseconds(800))
        XCTAssertEqual(model.pendingTimelineAvatarHideCount, 0)
    }

    @MainActor
    func testPhase63VisibilityGraceUsesOneWorkerForManyTimelineRows() async throws {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot)
        for index in 0..<40 {
            model.timelineAvatarBecameHidden(consumerID: "timeline-avatar-phase63-\(index)")
        }
        XCTAssertEqual(model.pendingTimelineAvatarHideCount, 40)
        XCTAssertTrue(model.hasActiveTimelineVisibilityLeaseWorker)

        try await Task.sleep(for: .milliseconds(850))
        XCTAssertEqual(model.pendingTimelineAvatarHideCount, 0)
        XCTAssertFalse(model.hasActiveTimelineVisibilityLeaseWorker)
        XCTAssertEqual(model.phase63ComposerDiagnostics.visibilityLeaseExpirationCount, 40)
    }

    @MainActor
    func testPhase63InlinePreviewCancellationWaitsForGracePeriod() throws {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot)
        model.selectServer(model.servers[0].id)
        let channelID = try XCTUnwrap(model.selection.channelID)
        let messageID = try XCTUnwrap(model.selectedTimelineMessages.first?.message.id)

        model.updateTimelineVisibility(messageID: messageID, channelID: channelID, isVisible: true)
        XCTAssertEqual(model.pendingInlinePreviewCancelCount, 0)

        // Scrolling the row offscreen schedules the cancellation instead of running it.
        model.updateTimelineVisibility(messageID: messageID, channelID: channelID, isVisible: false)
        XCTAssertEqual(model.pendingInlinePreviewCancelCount, 1)

        // Scrolling straight back keeps the loads: the pending cancellation is dropped.
        model.updateTimelineVisibility(messageID: messageID, channelID: channelID, isVisible: true)
        XCTAssertEqual(model.pendingInlinePreviewCancelCount, 0)

        // A channel switch resolves pending grace work immediately.
        model.updateTimelineVisibility(messageID: messageID, channelID: channelID, isVisible: false)
        XCTAssertEqual(model.pendingInlinePreviewCancelCount, 1)
        let otherChannelID = try XCTUnwrap(
            model.snapshot.channelsByID.values.first { $0.id != channelID && $0.kind == .textChannel }?.id
        )
        model.selectChannel(otherChannelID)
        XCTAssertEqual(model.pendingInlinePreviewCancelCount, 0)
        XCTAssertEqual(model.pendingTimelineAvatarHideCount, 0)
    }

    @MainActor
    func testPhase63TimelineRenderItemViewEquatableSkipsUnchangedRows() {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot)
        let channelID: ChannelID = "phase63-equatable-channel"
        let userID: UserID = "phase63-equatable-user"
        func makeItem(content: String) -> TimelineRenderItem {
            TimelineRenderItem(
                timelineMessage: TimelineMessage(
                    message: Message(id: "phase63-equatable-message", channelID: channelID, authorID: userID, content: content),
                    status: .confirmed
                ),
                groupID: "group",
                authorID: userID,
                showsHeader: true,
                startsGroup: true
            )
        }

        let item = makeItem(content: "hello")
        XCTAssertEqual(
            TimelineRenderItemView(item: item, viewModel: model),
            TimelineRenderItemView(item: item, viewModel: model)
        )
        XCTAssertEqual(
            TimelineRenderItemView(item: item, viewModel: model),
            TimelineRenderItemView(item: makeItem(content: "hello"), viewModel: model)
        )
        XCTAssertNotEqual(
            TimelineRenderItemView(item: item, viewModel: model),
            TimelineRenderItemView(item: makeItem(content: "edited"), viewModel: model)
        )
        let otherModel = MainShellViewModel(snapshot: MockShellData.snapshot)
        XCTAssertNotEqual(
            TimelineRenderItemView(item: item, viewModel: model),
            TimelineRenderItemView(item: item, viewModel: otherModel)
        )
    }

    func testPhase62ProfileBioDisclosureOnlyAppearsForOverflow() {
        XCTAssertFalse(ProfileBioDisclosurePolicy.isOverflowing(measuredHeight: 132, collapsedHeight: 132))
        XCTAssertFalse(ProfileBioDisclosurePolicy.isOverflowing(measuredHeight: 132.5, collapsedHeight: 132))
        XCTAssertTrue(ProfileBioDisclosurePolicy.isOverflowing(measuredHeight: 132.6, collapsedHeight: 132))
        XCTAssertTrue(ProfileBioDisclosurePolicy.isOverflowing(measuredHeight: 134, collapsedHeight: 132))
        XCTAssertEqual(ProfileBioDisclosurePolicy.contentWidth(cardWidth: 480, horizontalPadding: 24), 432)

        var state = ProfileBioDisclosureState(contentKey: "long")
        state.acceptMeasurement(220, contentKey: "long", collapsedHeight: 132)
        XCTAssertFalse(state.showsDisclosure)
        state.acceptPrepared(contentKey: "long")
        state.acceptMeasurement(220, contentKey: "stale", collapsedHeight: 132)
        XCTAssertFalse(state.showsDisclosure)
        state.acceptMeasurement(220, contentKey: "long", collapsedHeight: 132)
        XCTAssertTrue(state.showsDisclosure)
        state.isExpanded = true
        state.reset(contentKey: "short")
        state.acceptPrepared(contentKey: "short")
        state.acceptMeasurement(80, contentKey: "short", collapsedHeight: 132)
        XCTAssertFalse(state.isExpanded)
        XCTAssertFalse(state.showsDisclosure)
    }

    func testPhase63BioDisclosureNeverClipsWithoutButton() {
        let collapsed: CGFloat = 132
        for height in [CGFloat(60), 122, 131.6, 132, 132.4, 132.5, 132.6, 133, 140, 396] {
            var state = ProfileBioDisclosureState(contentKey: "bio")
            state.acceptPrepared(contentKey: "bio")
            state.acceptMeasurement(height, contentKey: "bio", collapsedHeight: collapsed)
            // The clamp may only be applied while measuring or when the button is offered --
            // "clipped content with no See More" must be unreachable.
            XCTAssertEqual(
                state.appliesClamp,
                state.showsDisclosure,
                "height \(height): clamp applied without a matching disclosure button"
            )
            if height > collapsed + ProfileBioDisclosurePolicy.overflowEpsilon {
                XCTAssertTrue(state.showsDisclosure, "height \(height) should overflow")
            } else {
                XCTAssertFalse(state.showsDisclosure, "height \(height) should fit")
                XCTAssertEqual(state.classification, .fits)
            }
        }
    }

    func testPhase63BioDisclosureClampsWhileMeasuringWithoutButton() {
        var state = ProfileBioDisclosureState(contentKey: "bio")
        XCTAssertEqual(state.classification, .measuring)
        XCTAssertTrue(state.appliesClamp)
        XCTAssertFalse(state.showsDisclosure)

        // Placeholder-subtree measurements before prepare are still rejected.
        state.acceptMeasurement(500, contentKey: "bio", collapsedHeight: 132)
        XCTAssertEqual(state.classification, .measuring)
        XCTAssertFalse(state.showsDisclosure)
    }

    func testPhase63BioDisclosureRetainsClassificationAcrossPrepare() {
        var state = ProfileBioDisclosureState(contentKey: "bio")
        state.acceptPrepared(contentKey: "bio")
        state.acceptMeasurement(300, contentKey: "bio", collapsedHeight: 132)
        XCTAssertTrue(state.showsDisclosure)
        state.isExpanded = true

        // A repeated prepare for the same content (e.g. the task re-running) must not zero the
        // classification -- that produced the Phase 62 one-frame button flicker.
        state.acceptPrepared(contentKey: "bio")
        XCTAssertTrue(state.showsDisclosure)
        XCTAssertTrue(state.isExpanded)
        XCTAssertFalse(state.appliesClamp)

        // A fresh, smaller measurement reclassifies to fits and drops the button and clamp.
        state.acceptMeasurement(90, contentKey: "bio", collapsedHeight: 132)
        XCTAssertFalse(state.showsDisclosure)
        XCTAssertFalse(state.appliesClamp)

        // A real content change resets everything, including expansion.
        state.reset(contentKey: "bio-v2")
        XCTAssertEqual(state.classification, .measuring)
        XCTAssertFalse(state.isExpanded)
        XCTAssertNil(state.preparedContentKey)
    }

    func testPhase63BioDisclosureRejectsStalePreparedGeneration() {
        var state = ProfileBioDisclosureState(contentKey: "long|width:432")
        state.acceptPrepared(contentKey: "long|width:432", generation: 2)
        state.acceptMeasurement(600, contentKey: "long|width:432", generation: 1, collapsedHeight: 132)
        XCTAssertEqual(state.classification, .measuring)
        XCTAssertFalse(state.showsDisclosure)

        state.acceptMeasurement(600, contentKey: "long|width:432", generation: 2, collapsedHeight: 132)
        XCTAssertEqual(state.classification, .overflows)
        XCTAssertTrue(state.showsDisclosure)
    }

    @MainActor
    func testPhase63ComposerEditsDoNotRebuildPrepared250MessageTimeline() async {
        let channelID: ChannelID = "phase63-composer-channel"
        let authorID: UserID = "phase63-composer-author"
        let messages = (0..<250).map { index in
            Message(
                id: MessageID(rawValue: String(format: "01P%023d", index)),
                channelID: channelID,
                authorID: authorID,
                content: "Message \(index)"
            )
        }
        let snapshot = RealtimeSnapshot(
            usersByID: [authorID: User(id: authorID, username: "author")],
            channelsByID: [channelID: Channel(id: channelID, kind: .directMessage, recipients: [authorID])],
            messagesByChannelID: [channelID: messages]
        )
        let model = MainShellViewModel(
            selection: ShellSelection(space: .directMessages, dmChannelID: channelID),
            snapshot: snapshot
        )
        await model.prepareSelectedTimelinePresentation()
        let groupingBuilds = model.timelinePresentationDiagnostics.groupingBuildCount
        let rowRequests = model.phase60Diagnostics.rowRequestCount
        let viewportFlushes = model.phase60Diagnostics.coalescedViewportFlushCount

        model.addPastedImageData(Data([137, 80, 78, 71]), to: channelID)
        model.updateDraft("still composing ", for: channelID)
        model.updateDraft("still composing 😭", for: channelID)
        model.updateDraft("still composing 😭😭", for: channelID)
        model.updateDraft("still composing 😭😭", for: channelID)

        XCTAssertEqual(model.composerDraftState(for: channelID).text, "still composing 😭😭")
        XCTAssertEqual(model.composerDraftState(for: channelID).attachments.count, 1)
        XCTAssertEqual(model.selectedTimelineRenderItems.count, 250)
        XCTAssertEqual(model.timelinePresentationDiagnostics.groupingBuildCount, groupingBuilds)
        XCTAssertEqual(model.phase60Diagnostics.rowRequestCount, rowRequests)
        XCTAssertEqual(model.phase60Diagnostics.coalescedViewportFlushCount, viewportFlushes)
        XCTAssertEqual(model.phase63ComposerDiagnostics.acceptedDraftMutationCount, 3)
        XCTAssertEqual(model.phase63ComposerDiagnostics.duplicateDraftMutationCount, 1)
    }

    func testPhase63BioCollapsedHeightDerivedFromLineMetrics() {
        XCTAssertEqual(ProfileBioMetrics.collapsedHeight(lineLimit: 8, lineHeight: 16), 128)
        XCTAssertEqual(ProfileBioMetrics.collapsedHeight(lineLimit: 8, lineHeight: 16.5), 132)
        XCTAssertEqual(ProfileBioMetrics.collapsedHeight(lineLimit: 6, lineHeight: 20.25), 122)
        // Degenerate inputs stay usable rather than collapsing to zero.
        XCTAssertEqual(ProfileBioMetrics.collapsedHeight(lineLimit: 0, lineHeight: 0), 1)
    }

    @MainActor
    func testPhase59AvatarCompletionDoesNotInvalidatePreparedTimelineRows() async throws {
        let data = Data("avatar".utf8)
        let loader = MockImageResourceLoader(result: .success(data))
        let model = MainShellViewModel(runtimeMode: .mock, imageResourceLoader: loader)
        let memberAvatar = File(id: "phase57-member-avatar", tag: "avatars", filename: "member.png", contentType: "image/png", size: data.count)
        let timelineAvatar = File(id: "phase57-timeline-avatar", tag: "avatars", filename: "timeline.png", contentType: "image/png", size: data.count)

        model.imageResourceBecameVisible(memberAvatar, kind: .userAvatar, consumerID: "member-panel-avatar-one")
        for _ in 0..<40 {
            if model.imageData(for: memberAvatar, kind: .userAvatar) != nil { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        var diagnostics = await model.imageResourceDiagnostics()
        XCTAssertEqual(diagnostics.timelineMediaInvalidationCount, 0)

        model.imageResourceBecameVisible(timelineAvatar, kind: .userAvatar, consumerID: "timeline-avatar-one")
        for _ in 0..<40 {
            diagnostics = await model.imageResourceDiagnostics()
            if model.imageData(for: timelineAvatar, kind: .userAvatar) != nil { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        diagnostics = await model.imageResourceDiagnostics()
        XCTAssertEqual(diagnostics.timelineMediaInvalidationCount, 0)
    }

    @MainActor
    func testPhase59LargeMemberChurnDoesNotRebuildShellOrSortMembersAsFriends() async throws {
        let serverID: ServerID = "phase59-large-server"
        let currentUserID: UserID = "phase59-current"
        let friendID: UserID = "phase59-friend"
        let currentUser = User(
            id: currentUserID,
            username: "current",
            relations: [Relationship(id: friendID, status: .friend)]
        )
        var snapshot = RealtimeSnapshot()
        snapshot.serversByID[serverID] = Server(id: serverID, ownerID: currentUserID, name: "Large")
        snapshot.usersByID[currentUserID] = currentUser
        snapshot.usersByID[friendID] = User(id: friendID, username: "friend", relationship: .friend)
        for index in 0..<2_324 {
            let userID = UserID(rawValue: "phase59-member-\(index)")
            snapshot.usersByID[userID] = User(id: userID, username: "member\(index)")
            snapshot.membersByServerAndUserID[ServerMemberKey(serverID: serverID, userID: userID)] = ServerMember(
                id: MemberCompositeKey(serverID: serverID, userID: userID),
                joinedAt: Date()
            )
        }
        let model = MainShellViewModel(
            selection: ShellSelection(space: .server(serverID), serverID: serverID),
            snapshot: snapshot,
            currentUser: currentUser
        )
        XCTAssertEqual(model.shellPresentationSnapshot.allFriendItems.map(\.user.id), [friendID])
        XCTAssertEqual(model.phase51PerformanceDiagnostics.shellRelationshipCandidateCount, 1)
        let requestsBefore = model.phase51PerformanceDiagnostics.shellRequestCount
        let buildsBefore = model.phase51PerformanceDiagnostics.shellBuildCount

        var replacement = snapshot
        let changedKey = ServerMemberKey(serverID: serverID, userID: "phase59-member-100")
        replacement.membersByServerAndUserID[changedKey]?.nickname = "updated"
        model.replaceSnapshotForTesting(
            replacement,
            changes: RealtimeSnapshotChangeSet(memberKeys: [changedKey])
        )
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(model.phase51PerformanceDiagnostics.shellRequestCount, requestsBefore)
        XCTAssertEqual(model.phase51PerformanceDiagnostics.shellBuildCount, buildsBefore)
    }

    @MainActor
    func testPhase59VisibleAvatarPromotesAheadOfQueuedBackgroundAndIdentityWork() async throws {
        let loader = SlowImageResourceLoader(delayNanoseconds: 120_000_000)
        let model = MainShellViewModel(runtimeMode: .mock, imageResourceLoader: loader)
        for index in 0..<8 {
            model.loadImageResource(
                for: File(id: FileID(rawValue: "phase59-background-\(index)"), tag: "banners", filename: "b.png", contentType: "image/png", size: 5),
                kind: .serverBanner
            )
        }
        let ordinary = File(id: "phase59-ordinary-avatar", tag: "avatars", filename: "ordinary.png", contentType: "image/png", size: 5)
        let visible = File(id: "phase59-visible-avatar", tag: "avatars", filename: "visible.png", contentType: "image/png", size: 5)
        model.loadImageResource(for: ordinary, kind: .userAvatar)
        model.imageResourceBecameVisible(visible, kind: .userAvatar, consumerID: "timeline-avatar-phase59-visible")

        for _ in 0..<80 {
            let calls = await loader.calls
            if calls.count >= 10 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let calls = await loader.calls
        XCTAssertGreaterThanOrEqual(calls.count, 10)
        XCTAssertEqual(calls[8].id, visible.id.rawValue)
        XCTAssertEqual(calls[9].id, ordinary.id.rawValue)
    }

    @MainActor
    func testPhase59ReactionIsOptimisticAndDeduplicatesWhileInFlight() async throws {
        let handler = Phase59ReactionHandler(delay: .milliseconds(80))
        let model = MainShellViewModel(snapshot: MockShellData.snapshot, messageActionHandler: handler)
        model.selectServer(model.servers[0].id)
        let message = try XCTUnwrap(model.selectedTimelineMessages.first { $0.status == .confirmed })

        let first = Task { await model.toggleReaction("✅", on: message) }
        try await Task.sleep(for: .milliseconds(5))
        XCTAssertEqual(
            model.selectedTimelineMessages.first { $0.message.id == message.message.id }?.message.reactions["✅"],
            [MockShellData.currentUserID]
        )
        let duplicate = Task { await model.toggleReaction("✅", on: message) }
        await first.value
        await duplicate.value

        let addCallCount = await handler.addCallCount
        XCTAssertEqual(addCallCount, 1)
        XCTAssertEqual(model.phase59ReactionDiagnostics.optimisticMutationCount, 1)
        XCTAssertEqual(model.phase59ReactionDiagnostics.deduplicatedCount, 1)
        XCTAssertEqual(model.phase59ReactionDiagnostics.successCount, 1)
    }

    @MainActor
    func testPhase59ReactionFailureRollsBackAndShowsTransientError() async throws {
        let handler = Phase59ReactionHandler(
            delay: .milliseconds(30),
            error: MessageActionError.unavailable("server rejected reaction")
        )
        let model = MainShellViewModel(snapshot: MockShellData.snapshot, messageActionHandler: handler)
        model.selectServer(model.servers[0].id)
        let message = try XCTUnwrap(model.selectedTimelineMessages.first { $0.status == .confirmed })

        let task = Task { await model.toggleReaction("🚀", on: message) }
        try await Task.sleep(for: .milliseconds(5))
        XCTAssertEqual(
            model.selectedTimelineMessages.first { $0.message.id == message.message.id }?.message.reactions["🚀"],
            [MockShellData.currentUserID]
        )
        await task.value

        XCTAssertNil(
            model.selectedTimelineMessages.first { $0.message.id == message.message.id }?.message.reactions["🚀"]
        )
        XCTAssertEqual(model.phase59ReactionDiagnostics.rollbackCount, 1)
        XCTAssertEqual(model.transientNotice?.severity, .error)
    }

    @MainActor
    func testPhase57TransientNoticePolicyKeepsSuccessSilentAndExpiresFailures() async throws {
        let model = MainShellViewModel(runtimeMode: .mock)

        model.placeholderStatus = "Custom status set."
        XCTAssertNil(model.transientNotice)
        model.placeholderStatus = "Refreshed 2329 members and 2329 users."
        XCTAssertNil(model.transientNotice)

        model.placeholderStatus = "Message action is unavailable."
        XCTAssertEqual(model.transientNotice?.severity, .error)
        model.dismissTransientNotice()
        XCTAssertNil(model.transientNotice)

        model.presentNotice("Reconnect before retrying.", severity: .warning, duration: .milliseconds(20))
        XCTAssertEqual(model.transientNotice?.severity, .warning)
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertNil(model.transientNotice)
    }

    @MainActor
    func testPhase55ChannelMessageControllerPaintsDiskCacheBeforeNetworkFetch() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("phase55-msgcache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileChannelMessageCache(scopeIdentifier: "phase55-msg-scope", directory: directory)
        let channelID: ChannelID = "phase55-cache-channel"
        let cachedMessage = Message(id: "01J00000000000000000550101", channelID: channelID, authorID: "phase55-author", content: "from disk")
        await cache.store([cachedMessage], for: channelID)

        let networkMessage = Message(id: "01J00000000000000000550102", channelID: channelID, authorID: "phase55-author", content: "from network")
        let api = RecordingAPIClient(messagesByChannel: [channelID: [networkMessage]], fetchMessagesDelayNanoseconds: 300_000_000)
        let controller = ChannelMessageController(runtimeMode: .liveManual, apiClient: api, currentUserID: "phase55-me")
        controller.configure(runtimeMode: .liveManual, apiClient: api, currentUserID: "phase55-me", messageCache: cache)

        let loadTask = Task { await controller.loadInitialIfNeeded(channelID: channelID, snapshotMessages: []) }
        var paintedFromDiskBeforeFetch = false
        for _ in 0..<40 {
            if controller.state(for: channelID).timelineMessages.contains(where: { $0.message.id == cachedMessage.id }) {
                paintedFromDiskBeforeFetch = true
                break
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(paintedFromDiskBeforeFetch)
        XCTAssertFalse(controller.state(for: channelID).timelineMessages.contains { $0.message.id == networkMessage.id })

        _ = await loadTask.value
        XCTAssertTrue(controller.state(for: channelID).timelineMessages.contains { $0.message.id == networkMessage.id })
    }

    func testPhase55FileImageDiskCacheRoundTripAndLoaderHit() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("phase55-disk-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = FileImageDiskCache(directory: directory, maxBytes: 1024 * 1024)
        let key = ImageCacheKey(id: "phase55-file", kind: .userAvatar)
        let stored = Data("avatar-bytes".utf8)

        await disk.store(stored, for: key)
        let roundTrip = await disk.data(for: key)
        XCTAssertEqual(roundTrip, stored)

        let loader = LiveImageResourceLoader(cache: ImageMemoryCache(), diskCache: disk)
        let request = ImageResourceRequest(id: "phase55-file", url: URL(string: "https://invalid.example/never")!, kind: .userAvatar, maxBytes: 1024)
        let result = try await loader.loadImage(request)
        XCTAssertTrue(result.fromCache)
        XCTAssertEqual(result.data, stored)

        await disk.removeAll()
        let cleared = await disk.data(for: key)
        XCTAssertNil(cleared)
    }

    func testPhase56MediaRetryPolicyRecoversTransientFailuresAndSkipsPermanentOnes() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SequencedMediaURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let request = ImageResourceRequest(
            id: "phase56-retry-image",
            url: URL(string: "https://media.example/image")!,
            kind: .userAvatar,
            maxBytes: 1024
        )

        SequencedMediaURLProtocol.configure([
            .response(status: 429, headers: ["Retry-After": "0"], data: Data()),
            .response(status: 200, headers: ["Content-Type": "image/png"], data: Data("png".utf8))
        ])
        let imageLoader = LiveImageResourceLoader(cache: ImageMemoryCache(), session: session)
        let image = try await imageLoader.loadImage(request)
        XCTAssertEqual(image.data, Data("png".utf8))
        XCTAssertEqual(SequencedMediaURLProtocol.requestCount, 2)

        SequencedMediaURLProtocol.configure([
            .failure(URLError(.timedOut)),
            .response(status: 200, headers: ["Content-Type": "image/png"], data: Data("attachment".utf8))
        ])
        let attachment = AttachmentDisplayItem(file: File(
            id: "phase56-retry-attachment",
            tag: "attachments",
            filename: "photo.png",
            metadata: .image(width: 10, height: 10, thumbhash: nil, animated: false),
            contentType: "image/png",
            size: 10
        ))
        let attachmentLoader = LiveRemoteAttachmentLoader(environment: .production, session: session)
        let loadedAttachment = try await attachmentLoader.load(attachment, purpose: .preview)
        XCTAssertEqual(loadedAttachment.data, Data("attachment".utf8))
        XCTAssertEqual(SequencedMediaURLProtocol.requestCount, 2)

        SequencedMediaURLProtocol.configure([
            .response(status: 404, headers: [:], data: Data())
        ])
        do {
            _ = try await LiveImageResourceLoader(cache: ImageMemoryCache(), session: session).loadImage(request)
            XCTFail("A permanent 404 must fail.")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("not found"))
        }
        XCTAssertEqual(SequencedMediaURLProtocol.requestCount, 1)
        XCTAssertFalse(MediaRequestRetryPolicy.isTransient(URLError(.cancelled)))
    }

    func testPhase56FileImageDiskCacheTracksByteCountAndEvictsOldestWhenOverCap() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("phase56-disk-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = FileImageDiskCache(directory: directory, maxBytes: 100)

        let oldKey = ImageCacheKey(id: "phase56-old", kind: .userAvatar)
        await disk.store(Data(repeating: 0, count: 40), for: oldKey)
        let afterFirstStore = await disk.byteCount()
        XCTAssertEqual(afterFirstStore, 40)

        // A later modification time ensures the eviction below removes the OLD entry first.
        try await Task.sleep(for: .milliseconds(20))
        let newKey = ImageCacheKey(id: "phase56-new", kind: .userAvatar)
        await disk.store(Data(repeating: 0, count: 40), for: newKey)
        let afterSecondStore = await disk.byteCount()
        XCTAssertEqual(afterSecondStore, 80)

        // Overwriting an existing key must adjust the running total by the size delta, not double-count it.
        await disk.store(Data(repeating: 0, count: 10), for: newKey)
        let afterOverwrite = await disk.byteCount()
        XCTAssertEqual(afterOverwrite, 50)

        // Pushing past the 100-byte cap should evict down toward 80% (80 bytes), removing the oldest entry.
        try await Task.sleep(for: .milliseconds(20))
        let thirdKey = ImageCacheKey(id: "phase56-third", kind: .userAvatar)
        await disk.store(Data(repeating: 0, count: 60), for: thirdKey)
        let finalCount = await disk.byteCount()
        XCTAssertLessThanOrEqual(finalCount, 80)
        let oldData = await disk.data(for: oldKey)
        XCTAssertNil(oldData, "oldest entry should have been evicted first")
        let thirdData = await disk.data(for: thirdKey)
        XCTAssertNotNil(thirdData, "newest entry should survive eviction")
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
    func testPhase28TimelineDiagnosticsAvoidNoOpVisibleRangeSpam() async throws {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot)
        let server = try XCTUnwrap(model.servers.first)
        model.selectServer(server.id)
        let channelID = try XCTUnwrap(model.selectedConversationChannel?.id)
        let messageID = try XCTUnwrap(model.selectedTimelineMessages.first?.message.id)

        model.updateTimelineVisibility(messageID: messageID, channelID: channelID, isVisible: true)
        try await Task.sleep(for: .milliseconds(140))
        await model.prepareSelectedTimelinePresentation()
        for _ in 0..<20 {
            if model.timelinePerformanceDiagnostics.loadedMessageCount > 0 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        model.updateTimelineVisibility(messageID: messageID, channelID: channelID, isVisible: true)

        await model.prepareSelectedTimelinePresentation()
        XCTAssertEqual(model.timelinePerformanceDiagnostics.visibleRangeUpdateCount, 1)
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
        let emoji = Emoji(id: "01J00000000000000000330001", parent: .server(serverID), creatorID: MockShellData.currentUserID, name: "bagel")
        snapshot.emojisByID[emoji.id] = emoji
        let model = MainShellViewModel(selection: ShellSelection(space: .server(serverID), serverID: serverID), snapshot: snapshot)

        let itemByID = model.customEmojiDisplayItem(for: emoji.id.rawValue)
        let itemByName = model.customEmojiDisplayItem(for: ":bagel:")

        XCTAssertEqual(itemByID?.name, "bagel")
        XCTAssertEqual(itemByName?.file.tag, "emojis")
        XCTAssertTrue(model.commonEmojiItems.contains(":\(emoji.id.rawValue):"))
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
        let low = Role(id: lowRoleID, name: "Low", permissions: PermissionOverride(), colour: "#111111", rank: 50)
        let high = Role(id: highRoleID, name: "High", permissions: PermissionOverride(), colour: "#33AAEE", rank: 1)
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
        model.replaceSnapshotForTesting(snapshot)
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
        let emoji = Emoji(id: "01J00000000000000000340004", parent: .server(serverID), creatorID: MockShellData.currentUserID, name: "bagelparty")
        snapshot.emojisByID[emoji.id] = emoji
        let model = MainShellViewModel(selection: ShellSelection(space: .server(serverID), serverID: serverID, channelID: channelID), snapshot: snapshot)

        let pickerItem = model.composerEmojiSections.first(where: { $0.id == "current-server" })?.items.first
        XCTAssertEqual(pickerItem?.displayName, "bagelparty")
        XCTAssertEqual(pickerItem?.insertionText, ":\(emoji.id.rawValue):")
        model.insertEmoji(pickerItem?.insertionText ?? "", in: channelID)
        XCTAssertEqual(model.draft(for: channelID), ":\(emoji.id.rawValue):")
        XCTAssertEqual(model.emojiPickerDiagnostics, "Inserted custom emoji shortcode")

        let officialMessage = Message(id: "01J00000000000000000340003", channelID: channelID, authorID: MockShellData.currentUserID, content: "hello :\(emoji.id.rawValue):")
        let officialInline = model.inlineCustomEmojiItems(for: officialMessage)
        XCTAssertEqual(officialInline.map(\.shortcode), [":\(emoji.id.rawValue):"])
        XCTAssertEqual(officialInline.first?.name, "bagelparty")

        let legacyMessage = Message(id: "01J00000000000000000340005", channelID: channelID, authorID: MockShellData.currentUserID, content: "hello :bagelparty:")
        XCTAssertEqual(model.inlineCustomEmojiItems(for: legacyMessage).map(\.shortcode), [":bagelparty:"])
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
        let publicationBeforeHydration = model.phase68TraceDiagnostics.selectedMemberListPublicationCount

        await model.hydrateServerMembers(serverID: serverID, force: true, reason: "test")
        await model.prepareMemberListGroups(for: serverID)
        let callCount = await api.fetchServerMembersCallCount
        let groups = model.cachedMemberListGroups(for: serverID)
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
        XCTAssertEqual(model.phase68TraceDiagnostics.selectedMemberListPublicationCount, publicationBeforeHydration + 1)
        XCTAssertEqual(model.phase52FreezeDiagnostics.snapshotInstallCount, 1)
        XCTAssertEqual(model.phase52FreezeDiagnostics.memberHydrationCommitCount, 1)
        XCTAssertEqual(model.phase52FreezeDiagnostics.identityBatchCommitCount, 1)
    }

    @MainActor
    func testPhase56MemberHydrationPreservesGatewayFreshPresenceOverStaleRestSnapshot() async {
        var snapshot = RealtimeSnapshot()
        let serverID: ServerID = "phase56-hydration-server"
        let channelID: ChannelID = "phase56-hydration-channel"
        let onlineUserID: UserID = "phase56-online-user"
        snapshot.serversByID[serverID] = Server(id: serverID, ownerID: onlineUserID, name: "Phase56 Hydration")
        snapshot.channelsByID[channelID] = Channel(id: channelID, kind: .textChannel, serverID: serverID, name: "general")
        // The gateway has already told us this user is online with an idle status.
        snapshot.usersByID[onlineUserID] = User(id: onlineUserID, username: "gatewayfresh", status: UserStatus(text: nil, presence: .idle), online: true)
        snapshot.membersByServerAndUserID[ServerMemberKey(serverID: serverID, userID: onlineUserID)] = ServerMember(
            id: MemberCompositeKey(serverID: serverID, userID: onlineUserID),
            joinedAt: Date()
        )
        // The REST member list response is a stale snapshot: it thinks the user is offline.
        let restMembers = [ServerMember(id: MemberCompositeKey(serverID: serverID, userID: onlineUserID), joinedAt: Date())]
        let restUsers = [User(id: onlineUserID, username: "gatewayfresh", displayName: "Updated Name", online: false)]
        let api = RecordingAPIClient(membersByServer: [serverID: restMembers], usersByServer: [serverID: restUsers])
        let model = MainShellViewModel(
            selection: ShellSelection(space: .server(serverID), serverID: serverID, channelID: channelID),
            snapshot: snapshot,
            runtimeMode: .mock,
            communityAPIClient: api
        )

        await model.hydrateServerMembers(serverID: serverID, force: true, reason: "test")

        XCTAssertEqual(model.snapshot.usersByID[onlineUserID]?.online, true, "REST hydration must not clobber gateway-fresh online status")
        XCTAssertEqual(model.snapshot.usersByID[onlineUserID]?.status?.presence, .idle, "REST hydration must not clobber gateway-fresh presence")
        XCTAssertEqual(model.snapshot.usersByID[onlineUserID]?.displayName, "Updated Name", "other REST-sourced fields should still update normally")
    }

    @MainActor
    func testPhase56HydratedUsersSurviveSparseGatewaySnapshotsAndRespectRemoval() async {
        let serverID: ServerID = "phase56-overlay-server"
        let channelID: ChannelID = "phase56-overlay-channel"
        let ownerID: UserID = "phase56-overlay-owner"
        let offlineID: UserID = "phase56-overlay-offline"
        let server = Server(id: serverID, ownerID: ownerID, name: "Overlay")
        let channel = Channel(id: channelID, kind: .textChannel, serverID: serverID, name: "general")
        let members = [ownerID, offlineID].map {
            ServerMember(id: MemberCompositeKey(serverID: serverID, userID: $0), joinedAt: Date())
        }
        let users = [
            User(id: ownerID, username: "owner", online: false),
            User(id: offlineID, username: "offline", displayName: "Offline Member", online: false)
        ]
        let api = RecordingAPIClient(membersByServer: [serverID: members], usersByServer: [serverID: users])
        let model = MainShellViewModel(
            selection: ShellSelection(space: .server(serverID), serverID: serverID, channelID: channelID),
            snapshot: RealtimeSnapshot(
                usersByID: [ownerID: users[0]],
                serversByID: [serverID: server],
                channelsByID: [channelID: channel]
            ),
            runtimeMode: .mock,
            communityAPIClient: api
        )

        await model.hydrateServerMembers(serverID: serverID, force: true, reason: "overlay test")

        let gatewayOwner = User(id: ownerID, username: "owner", status: UserStatus(presence: .busy), online: true)
        model.replaceSnapshotForTesting(
            RealtimeSnapshot(
                usersByID: [ownerID: gatewayOwner],
                serversByID: [serverID: server],
                channelsByID: [channelID: channel],
                membersByServerAndUserID: [ServerMemberKey(members[0].id): members[0]]
            ),
            changes: RealtimeSnapshotChangeSet(isFullReplacement: true)
        )

        XCTAssertEqual(model.snapshot.usersByID.count, 2)
        XCTAssertEqual(model.snapshot.usersByID[offlineID]?.displayName, "Offline Member")
        XCTAssertEqual(model.snapshot.usersByID[ownerID]?.online, true)
        XCTAssertEqual(model.snapshot.usersByID[ownerID]?.status?.presence, .busy)

        let removedKey = ServerMemberKey(serverID: serverID, userID: offlineID)
        var afterRemoval = model.snapshot
        afterRemoval.membersByServerAndUserID[removedKey] = nil
        afterRemoval.usersByID[offlineID] = nil
        model.replaceSnapshotForTesting(
            afterRemoval,
            changes: RealtimeSnapshotChangeSet(removedMemberKeys: [removedKey])
        )

        XCTAssertNil(model.snapshot.membersByServerAndUserID[removedKey])
        XCTAssertNil(model.snapshot.usersByID[offlineID])
    }

    @MainActor
    func testPhase52LargeMemberHydrationCommitsSnapshotAndIdentitiesOnce() async {
        let serverID: ServerID = "phase52-large-server"
        let channelID: ChannelID = "phase52-large-channel"
        let ownerID: UserID = "phase52-user-0"
        let users = (0...2_000).map { index in
            User(id: UserID(rawValue: "phase52-user-\(index)"), username: "user\(index)", displayName: "User \(index)")
        }
        let members = users.map {
            ServerMember(id: MemberCompositeKey(serverID: serverID, userID: $0.id), joinedAt: Date())
        }
        let snapshot = RealtimeSnapshot(
            usersByID: [ownerID: users[0]],
            serversByID: [serverID: Server(id: serverID, ownerID: ownerID, name: "Large")],
            channelsByID: [channelID: Channel(id: channelID, kind: .textChannel, serverID: serverID, name: "general")]
        )
        let api = RecordingAPIClient(membersByServer: [serverID: members], usersByServer: [serverID: users])
        let model = MainShellViewModel(
            selection: ShellSelection(space: .server(serverID), serverID: serverID, channelID: channelID),
            snapshot: snapshot,
            runtimeMode: .mock,
            communityAPIClient: api
        )

        await model.hydrateServerMembers(serverID: serverID, force: true, reason: "phase52 stress")

        XCTAssertEqual(model.snapshot.membersByServerAndUserID.count, 2_001)
        XCTAssertEqual(model.snapshot.usersByID.count, 2_001)
        XCTAssertEqual(model.phase52FreezeDiagnostics.snapshotInstallCount, 1)
        XCTAssertEqual(model.phase52FreezeDiagnostics.memberHydrationCommitCount, 1)
        XCTAssertEqual(model.phase52FreezeDiagnostics.identityBatchCommitCount, 1)
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

        XCTAssertLessThanOrEqual(diagnostics.activeTaskCount, 8)
        XCTAssertGreaterThanOrEqual(diagnostics.queuedTaskCount, 2)
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
        let currentEmojiID: EmojiID = "01J00000000000000000350001"
        let otherEmojiID: EmojiID = "01J00000000000000000350002"
        snapshot.serversByID[currentServerID] = Server(id: currentServerID, ownerID: MockShellData.currentUserID, name: "Current")
        snapshot.channelsByID[channelID] = Channel(id: channelID, kind: .textChannel, serverID: currentServerID, name: "general")
        snapshot.emojisByID[currentEmojiID] = Emoji(id: currentEmojiID, parent: .server(currentServerID), creatorID: MockShellData.currentUserID, name: "currentparty")
        snapshot.emojisByID[otherEmojiID] = Emoji(id: otherEmojiID, parent: .server(otherServerID), creatorID: MockShellData.currentUserID, name: "otherparty")
        let model = MainShellViewModel(selection: ShellSelection(space: .server(currentServerID), serverID: currentServerID, channelID: channelID), snapshot: snapshot)
        let sections = model.composerEmojiSections
        let current = sections.first { $0.id == "current-server" }?.items.map(\.insertionText) ?? []
        let other = sections.first { $0.id == "other-servers" }?.items.map(\.insertionText) ?? []

        XCTAssertTrue(current.contains(":\(currentEmojiID.rawValue):"))
        XCTAssertTrue(other.contains(":\(otherEmojiID.rawValue):"))
    }

    @MainActor
    func testPhase65EmojiCatalogPrefersCurrentServerForDuplicateNameWhileUsingIDToken() throws {
        var snapshot = MockShellData.snapshot
        let currentServerID: ServerID = "phase65-emoji-current"
        let otherServerID: ServerID = "phase65-emoji-other"
        let channelID: ChannelID = "phase65-emoji-channel"
        let currentEmojiID: EmojiID = "01J00000000000000000650001"
        let otherEmojiID: EmojiID = "01J00000000000000000650002"
        snapshot.serversByID[currentServerID] = Server(id: currentServerID, ownerID: MockShellData.currentUserID, name: "Current")
        snapshot.channelsByID[channelID] = Channel(id: channelID, kind: .textChannel, serverID: currentServerID, name: "general")
        snapshot.emojisByID[currentEmojiID] = Emoji(id: currentEmojiID, parent: .server(currentServerID), creatorID: MockShellData.currentUserID, name: "wave")
        snapshot.emojisByID[otherEmojiID] = Emoji(id: otherEmojiID, parent: .server(otherServerID), creatorID: MockShellData.currentUserID, name: "wave")
        let model = MainShellViewModel(
            selection: ShellSelection(space: .server(currentServerID), serverID: currentServerID, channelID: channelID),
            snapshot: snapshot
        )

        let current = try XCTUnwrap(model.composerEmojiSections.first { $0.id == "current-server" })
        let wave = try XCTUnwrap(current.items.first { $0.insertionText == ":\(currentEmojiID.rawValue):" })
        let other = model.composerEmojiSections.first { $0.id == "other-servers" }

        XCTAssertEqual(wave.displayName, "wave")
        XCTAssertEqual(wave.customMediaKey, currentEmojiID.rawValue)
        XCTAssertFalse(other?.items.contains { $0.displayName == "wave" } ?? false)
    }

    @MainActor
    func testPhase65ComposerCustomEmojiArtworkLoadsOnlyAfterVisibleRequest() async throws {
        var snapshot = MockShellData.snapshot
        let serverID: ServerID = "phase65-art-server"
        let channelID: ChannelID = "phase65-art-channel"
        let emojiID: EmojiID = "01J00000000000000000650003"
        snapshot.serversByID[serverID] = Server(id: serverID, ownerID: MockShellData.currentUserID, name: "Artwork")
        snapshot.channelsByID[channelID] = Channel(id: channelID, kind: .textChannel, serverID: serverID, name: "general")
        snapshot.emojisByID[emojiID] = Emoji(id: emojiID, parent: .server(serverID), creatorID: MockShellData.currentUserID, name: "bagelwave")
        let data = Data("phase65-custom-art".utf8)
        let loader = MockImageResourceLoader(result: .success(data))
        let model = MainShellViewModel(
            selection: ShellSelection(space: .server(serverID), serverID: serverID, channelID: channelID),
            snapshot: snapshot,
            runtimeMode: .mock,
            imageResourceLoader: loader
        )

        var item = try XCTUnwrap(
            model.composerEmojiSections
                .first { $0.id == "current-server" }?
                .items.first { $0.insertionText == ":\(emojiID.rawValue):" }
        )
        let metadataBeforeLoad = model.composerEmojiSections
        XCTAssertNil(item.imageData)
        XCTAssertNil(model.composerCustomEmojiImageData(for: item))
        var loaderCallCount = await loader.callCount()
        XCTAssertEqual(loaderCallCount, 0)

        model.requestComposerCustomEmojiImage(item)
        for _ in 0..<50 {
            if model.composerCustomEmojiImageData(for: item) == data { break }
            try await Task.sleep(for: .milliseconds(5))
        }

        XCTAssertEqual(model.composerCustomEmojiImageData(for: item), data)
        XCTAssertEqual(model.composerEmojiSections, metadataBeforeLoad)
        item = try XCTUnwrap(
            model.composerEmojiSections
                .first { $0.id == "current-server" }?
                .items.first { $0.insertionText == ":\(emojiID.rawValue):" }
        )
        XCTAssertNil(item.imageData)
        loaderCallCount = await loader.callCount()
        XCTAssertEqual(loaderCallCount, 1)
        let diagnostics = await model.imageResourceDiagnostics()
        XCTAssertEqual(diagnostics.timelineMediaInvalidationCount, 0)
        model.requestComposerCustomEmojiImage(item)
        try await Task.sleep(for: .milliseconds(10))
        loaderCallCount = await loader.callCount()
        XCTAssertEqual(loaderCallCount, 1)
    }

    func testPhase68IdentitySnapshotMergesAreSemanticallyIdempotent() throws {
        let userID: UserID = "phase68-identity-user"
        let serverID: ServerID = "phase68-identity-server"
        let avatar = File(id: "phase68-avatar", tag: "avatars", filename: "avatar.png", contentType: "image/png", size: 24)
        let user = User(id: userID, username: "bagel", displayName: "Liquid Bagel", avatar: avatar, bot: BotInformation(ownerID: "phase68-owner"))
        let member = ServerMember(
            id: MemberCompositeKey(serverID: serverID, userID: userID),
            joinedAt: Date(timeIntervalSince1970: 1),
            nickname: "Bagel Nick",
            avatar: avatar,
            roles: ["phase68-role"]
        )
        let profile = UserProfile(content: "About this bagel", background: avatar)
        var store = Phase43IdentitySnapshotStore()

        XCTAssertTrue(store.merge(user: user, source: .readyUser, now: Date(timeIntervalSince1970: 10)))
        let userSnapshot = try XCTUnwrap(store.snapshot(for: userID))
        XCTAssertFalse(store.merge(user: user, source: .readyUser, now: Date(timeIntervalSince1970: 20)))
        XCTAssertEqual(store.generation, userSnapshot.generation)
        XCTAssertEqual(store.snapshot(for: userID)?.lastUpdatedAt, userSnapshot.lastUpdatedAt)

        XCTAssertTrue(store.merge(member: member, user: user, source: .readyMember, now: Date(timeIntervalSince1970: 30)))
        let memberSnapshot = try XCTUnwrap(store.snapshot(for: userID))
        let overlayGeneration = try XCTUnwrap(memberSnapshot.serverOverlays[serverID]).generation
        XCTAssertFalse(store.merge(member: member, user: user, source: .readyMember, now: Date(timeIntervalSince1970: 40)))
        XCTAssertEqual(store.generation, memberSnapshot.generation)
        XCTAssertEqual(store.snapshot(for: userID)?.lastUpdatedAt, memberSnapshot.lastUpdatedAt)
        XCTAssertEqual(store.snapshot(for: userID)?.serverOverlays[serverID]?.generation, overlayGeneration)

        XCTAssertTrue(store.merge(profile: profile, userID: userID, now: Date(timeIntervalSince1970: 50)))
        let profileSnapshot = try XCTUnwrap(store.snapshot(for: userID))
        XCTAssertFalse(store.merge(profile: profile, userID: userID, now: Date(timeIntervalSince1970: 60)))
        XCTAssertEqual(store.generation, profileSnapshot.generation)
        XCTAssertEqual(store.snapshot(for: userID)?.lastUpdatedAt, profileSnapshot.lastUpdatedAt)

        XCTAssertTrue(store.markMemberRemoved(userID: userID, serverID: serverID, now: Date(timeIntervalSince1970: 70)))
        let removedSnapshot = try XCTUnwrap(store.snapshot(for: userID))
        XCTAssertFalse(store.markMemberRemoved(userID: userID, serverID: serverID, now: Date(timeIntervalSince1970: 80)))
        XCTAssertEqual(store.generation, removedSnapshot.generation)
        XCTAssertEqual(store.snapshot(for: userID)?.lastUpdatedAt, removedSnapshot.lastUpdatedAt)
    }

    func testPhase68NestedMemberMergeReportsUserChangeWithoutRestampingOverlay() throws {
        let userID: UserID = "phase68-nested-user"
        let serverID: ServerID = "phase68-nested-server"
        let member = ServerMember(id: MemberCompositeKey(serverID: serverID, userID: userID), joinedAt: Date(), nickname: "Stable")
        var store = Phase43IdentitySnapshotStore()
        XCTAssertTrue(store.merge(member: member, user: User(id: userID, username: "before"), source: .readyMember))
        let overlayBefore = try XCTUnwrap(store.snapshot(for: userID)?.serverOverlays[serverID])

        XCTAssertTrue(store.merge(member: member, user: User(id: userID, username: "after"), source: .readyMember))

        let snapshot = try XCTUnwrap(store.snapshot(for: userID))
        XCTAssertEqual(snapshot.username, "after")
        XCTAssertEqual(snapshot.serverOverlays[serverID]?.generation, overlayBefore.generation)
        XCTAssertEqual(snapshot.serverOverlays[serverID]?.lastUpdatedAt, overlayBefore.lastUpdatedAt)
    }

    @MainActor
    func testPhase68MemberListTokenIgnoresUnrelatedIdentityAndTracksRelevantChanges() async throws {
        let serverID: ServerID = "phase68-member-server"
        let otherServerID: ServerID = "phase68-other-server"
        let channelID: ChannelID = "phase68-member-channel"
        let memberUserID: UserID = "phase68-member-user"
        let unrelatedUserID: UserID = "phase68-unrelated-user"
        let user = User(id: memberUserID, username: "member", displayName: "Member", online: true)
        let unrelatedUser = User(id: unrelatedUserID, username: "elsewhere", displayName: "Elsewhere")
        let member = ServerMember(id: MemberCompositeKey(serverID: serverID, userID: memberUserID), joinedAt: Date(), nickname: "Nick")
        let unrelatedMember = ServerMember(id: MemberCompositeKey(serverID: otherServerID, userID: unrelatedUserID), joinedAt: Date(), nickname: "Other Nick")
        let server = Server(id: serverID, ownerID: memberUserID, name: "Phase 68")
        let otherServer = Server(id: otherServerID, ownerID: unrelatedUserID, name: "Elsewhere")
        let channel = Channel(id: channelID, kind: .textChannel, serverID: serverID, name: "general")
        let snapshot = RealtimeSnapshot(
            usersByID: [memberUserID: user, unrelatedUserID: unrelatedUser],
            serversByID: [serverID: server, otherServerID: otherServer],
            channelsByID: [channelID: channel],
            membersByServerAndUserID: [
                ServerMemberKey(serverID: serverID, userID: memberUserID): member,
                ServerMemberKey(serverID: otherServerID, userID: unrelatedUserID): unrelatedMember
            ]
        )
        let api = RecordingAPIClient(profilesByUserID: [memberUserID: UserProfile(content: "Profile-only change")])
        let model = MainShellViewModel(
            selection: ShellSelection(space: .server(serverID), serverID: serverID, channelID: channelID),
            snapshot: snapshot,
            communityAPIClient: api
        )
        let initialToken = model.memberListPresentationToken
        let initialInvalidations = model.phase68TraceDiagnostics.memberListRelevantInvalidationCount

        for _ in 0..<12 {
            model.noteVisibleIdentity(userID: memberUserID, user: user, member: member, serverID: serverID, source: .visibleMember)
        }
        var changedUnrelatedUser = unrelatedUser
        changedUnrelatedUser.displayName = "Changed Elsewhere"
        model.noteVisibleIdentity(userID: unrelatedUserID, user: changedUnrelatedUser, member: unrelatedMember, serverID: otherServerID, source: .visibleMember)
        XCTAssertEqual(model.memberListPresentationToken, initialToken)
        XCTAssertEqual(model.phase68TraceDiagnostics.memberListRelevantInvalidationCount, initialInvalidations + 1)

        model.showUserProfile(memberUserID, source: .memberRow, serverID: serverID)
        for _ in 0..<40 where model.userProfilesByID[memberUserID] == nil {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(model.memberListPresentationToken, initialToken)
        XCTAssertEqual(model.phase68TraceDiagnostics.memberListRelevantInvalidationCount, initialInvalidations + 1)

        var changedUser = user
        changedUser.displayName = "Changed Member"
        model.noteVisibleIdentity(userID: memberUserID, user: changedUser, member: member, serverID: serverID, source: .visibleMember)
        let changedToken = model.memberListPresentationToken
        XCTAssertNotEqual(changedToken, initialToken)
        XCTAssertEqual(model.phase68TraceDiagnostics.memberListRelevantInvalidationCount, initialInvalidations + 2)

        model.noteVisibleIdentity(userID: memberUserID, user: changedUser, member: member, serverID: serverID, source: .visibleMember)
        XCTAssertEqual(model.memberListPresentationToken, changedToken)
        XCTAssertEqual(model.phase68TraceDiagnostics.memberListRelevantInvalidationCount, initialInvalidations + 2)
    }

    @MainActor
    func testPhase68MemberListTokenTracksPresenceRoleNicknameAvatarBotAndMembership() {
        let serverID: ServerID = "phase68-token-server"
        let channelID: ChannelID = "phase68-token-channel"
        let userID: UserID = "phase68-token-user"
        let memberKey = ServerMemberKey(serverID: serverID, userID: userID)
        var user = User(id: userID, username: "token-user", displayName: "Token User", status: UserStatus(presence: .online), online: true)
        var member = ServerMember(id: MemberCompositeKey(serverID: serverID, userID: userID), joinedAt: Date(), nickname: "Token Nick")
        var snapshot = RealtimeSnapshot(
            usersByID: [userID: user],
            serversByID: [serverID: Server(id: serverID, ownerID: userID, name: "Token Server")],
            channelsByID: [channelID: Channel(id: channelID, kind: .textChannel, serverID: serverID, name: "general")],
            membersByServerAndUserID: [memberKey: member]
        )
        let model = MainShellViewModel(
            selection: ShellSelection(space: .server(serverID), serverID: serverID, channelID: channelID),
            snapshot: snapshot
        )

        var previousToken = model.memberListPresentationToken
        user.status = UserStatus(text: "Away", presence: .idle)
        snapshot.usersByID[userID] = user
        model.replaceSnapshotForTesting(snapshot)
        XCTAssertNotEqual(model.memberListPresentationToken, previousToken)

        previousToken = model.memberListPresentationToken
        member.roles = ["phase68-token-role"]
        snapshot.membersByServerAndUserID[memberKey] = member
        model.replaceSnapshotForTesting(snapshot)
        XCTAssertNotEqual(model.memberListPresentationToken, previousToken)

        previousToken = model.memberListPresentationToken
        member.nickname = "Changed Nick"
        snapshot.membersByServerAndUserID[memberKey] = member
        model.replaceSnapshotForTesting(snapshot)
        XCTAssertNotEqual(model.memberListPresentationToken, previousToken)

        previousToken = model.memberListPresentationToken
        user.avatar = File(id: "phase68-token-avatar", tag: "avatars", filename: "avatar.png", contentType: "image/png", size: 42)
        user.bot = BotInformation(ownerID: "phase68-token-owner")
        snapshot.usersByID[userID] = user
        model.replaceSnapshotForTesting(snapshot)
        XCTAssertNotEqual(model.memberListPresentationToken, previousToken)

        previousToken = model.memberListPresentationToken
        snapshot.membersByServerAndUserID.removeValue(forKey: memberKey)
        model.replaceSnapshotForTesting(snapshot)
        XCTAssertNotEqual(model.memberListPresentationToken, previousToken)

        let stableToken = model.memberListPresentationToken
        model.replaceSnapshotForTesting(snapshot)
        XCTAssertEqual(model.memberListPresentationToken, stableToken)
    }

    @MainActor
    func testPhase69LateSelectedServerIdentityPublishesAndRebuildsUnknownMemberExactlyOnce() async throws {
        let serverID: ServerID = "phase69-member-server"
        let otherServerID: ServerID = "phase69-other-server"
        let channelID: ChannelID = "phase69-member-channel"
        let userID: UserID = "phase69-late-user"
        let otherUserID: UserID = "phase69-other-user"
        let memberKey = ServerMemberKey(serverID: serverID, userID: userID)
        let otherMemberKey = ServerMemberKey(serverID: otherServerID, userID: otherUserID)
        let member = ServerMember(id: MemberCompositeKey(serverID: serverID, userID: userID), joinedAt: Date())
        let otherMember = ServerMember(id: MemberCompositeKey(serverID: otherServerID, userID: otherUserID), joinedAt: Date())
        let snapshot = RealtimeSnapshot(
            serversByID: [
                serverID: Server(id: serverID, ownerID: userID, name: "Phase 69"),
                otherServerID: Server(id: otherServerID, ownerID: otherUserID, name: "Other")
            ],
            channelsByID: [channelID: Channel(id: channelID, kind: .textChannel, serverID: serverID, name: "general")],
            membersByServerAndUserID: [memberKey: member, otherMemberKey: otherMember]
        )
        let model = MainShellViewModel(
            selection: ShellSelection(space: .server(serverID), serverID: serverID, channelID: channelID),
            snapshot: snapshot
        )

        await model.prepareMemberListGroups(for: serverID)
        XCTAssertEqual(model.cachedMemberListGroups(for: serverID).flatMap(\.items).first?.displayName, "Unknown member")

        let userPublication = expectation(description: "late user identity publishes selected member token")
        withObservationTracking {
            _ = model.memberListPresentationToken
        } onChange: {
            userPublication.fulfill()
        }
        let publicationBeforeUser = model.phase68TraceDiagnostics.selectedMemberListPublicationCount
        let lateAvatar = File(id: "phase69-user-avatar", tag: "avatars", filename: "avatar.png", contentType: "image/png", size: 42)
        let lateUser = User(id: userID, username: "late-user", displayName: "Late User", avatar: lateAvatar)

        model.noteVisibleIdentity(userID: userID, user: lateUser, member: nil, serverID: serverID, source: .visibleMessage)
        await fulfillment(of: [userPublication], timeout: 1)
        XCTAssertEqual(model.phase68TraceDiagnostics.selectedMemberListPublicationCount, publicationBeforeUser + 1)

        await model.prepareMemberListGroups(for: serverID)
        var rebuiltItem = try XCTUnwrap(model.cachedMemberListGroups(for: serverID).flatMap(\.items).first)
        XCTAssertEqual(rebuiltItem.displayName, "Late User")
        XCTAssertEqual(rebuiltItem.avatar?.id, lateAvatar.id)

        let memberPublication = expectation(description: "late member identity publishes selected member token")
        withObservationTracking {
            _ = model.memberListPresentationToken
        } onChange: {
            memberPublication.fulfill()
        }
        let serverAvatar = File(id: "phase69-server-avatar", tag: "avatars", filename: "server-avatar.png", contentType: "image/png", size: 43)
        var enrichedMember = member
        enrichedMember.nickname = "Late Nickname"
        enrichedMember.avatar = serverAvatar
        let publicationBeforeMember = model.phase68TraceDiagnostics.selectedMemberListPublicationCount

        model.noteVisibleIdentity(userID: userID, user: nil, member: enrichedMember, serverID: serverID, source: .visibleMessage)
        await fulfillment(of: [memberPublication], timeout: 1)
        XCTAssertEqual(model.phase68TraceDiagnostics.selectedMemberListPublicationCount, publicationBeforeMember + 1)

        await model.prepareMemberListGroups(for: serverID)
        rebuiltItem = try XCTUnwrap(model.cachedMemberListGroups(for: serverID).flatMap(\.items).first)
        XCTAssertEqual(rebuiltItem.displayName, "Late Nickname")
        XCTAssertEqual(rebuiltItem.avatar?.id, serverAvatar.id)

        let stableToken = model.memberListPresentationToken
        let stablePublicationCount = model.phase68TraceDiagnostics.selectedMemberListPublicationCount
        let stableGroupingRevision = model.memberListGroupsRevision
        model.noteVisibleIdentity(userID: userID, user: nil, member: enrichedMember, serverID: serverID, source: .visibleMessage)
        XCTAssertEqual(model.memberListPresentationToken, stableToken)
        XCTAssertEqual(model.phase68TraceDiagnostics.selectedMemberListPublicationCount, stablePublicationCount)
        XCTAssertEqual(model.memberListGroupsRevision, stableGroupingRevision)

        let selectedTokenBeforeOtherServer = model.memberListPresentationToken
        model.noteVisibleIdentity(
            userID: otherUserID,
            user: User(id: otherUserID, username: "other", displayName: "Other User"),
            member: otherMember,
            serverID: otherServerID,
            source: .visibleMember
        )
        XCTAssertEqual(model.memberListPresentationToken, selectedTokenBeforeOtherServer)
        XCTAssertEqual(model.phase68TraceDiagnostics.selectedMemberListPublicationCount, stablePublicationCount)
        XCTAssertEqual(model.memberListGroupsRevision, stableGroupingRevision)
    }

    func testPhase68CustomEmojiIndexUsesCurrentServerDeduplicatesAndSkipsFencedCode() throws {
        let currentServerID: ServerID = "phase68-emoji-current"
        let otherServerID: ServerID = "phase68-emoji-other"
        let current = Emoji(id: "01J00000000000000000680011", parent: .server(currentServerID), creatorID: "creator", name: "wave")
        let other = Emoji(id: "01J00000000000000000680012", parent: .server(otherServerID), creatorID: "creator", name: "wave")
        let second = Emoji(id: "01J00000000000000000680013", parent: .server(currentServerID), creatorID: "creator", name: "party")
        let remote = Emoji(id: "01J00000000000000000680014", parent: .server(otherServerID), creatorID: "creator", name: "remote")
        let index = Phase68CustomEmojiIndex(emojisByID: [current.id: current, other.id: other, second.id: second, remote.id: remote])

        XCTAssertEqual(index.item(for: ":wave:", serverID: currentServerID)?.id, current.id)
        XCTAssertNil(index.item(for: other.id.rawValue, serverID: currentServerID))
        XCTAssertEqual(
            index.items(in: ":wave: :wave:\n```\n:party:\n```\n:party:", serverID: currentServerID).map(\.id),
            [current.id, second.id]
        )
        XCTAssertEqual(
            index.matches(in: ":\(other.id.rawValue): :wave: :\(other.id.rawValue):", serverID: currentServerID).map(\.token),
            [":\(other.id.rawValue):", ":wave:"]
        )
        XCTAssertEqual(
            index.matches(in: "```\n:\(other.id.rawValue):\n```", serverID: currentServerID).map(\.token),
            []
        )
        XCTAssertEqual(index.matches(in: ":remote:", serverID: currentServerID), [])
        XCTAssertEqual(index.matches(in: ":unknown:", serverID: currentServerID), [])
    }

    @MainActor
    func testPhase68EmojiIndexReusesCatalogAndInvalidatesOnlyForEmojiChanges() {
        var snapshot = MockShellData.snapshot
        let emoji = Emoji(id: "phase68-index-one", parent: .detached, creatorID: MockShellData.currentUserID, name: "indexed")
        snapshot.emojisByID = [emoji.id: emoji]
        let model = MainShellViewModel(snapshot: snapshot)

        _ = model.composerEmojiSections
        _ = model.composerEmojiSections
        _ = model.customEmojiDisplayItem(for: emoji.id.rawValue)
        XCTAssertEqual(model.phase68TraceDiagnostics.emojiIndexBuildCount, 1)
        XCTAssertGreaterThan(model.phase68TraceDiagnostics.emojiIndexCacheHitCount, 0)

        model.mutateSnapshotForTesting { value in
            value.messagesByChannelID["phase68-unrelated-channel"] = [
                Message(id: "01J00000000000000000680001", channelID: "phase68-unrelated-channel", authorID: MockShellData.currentUserID, content: "ordinary")
            ]
        }
        _ = model.composerEmojiSections
        XCTAssertEqual(model.phase68TraceDiagnostics.emojiIndexBuildCount, 1)

        model.mutateSnapshotForTesting { value in
            let added = Emoji(id: "phase68-index-two", parent: .detached, creatorID: MockShellData.currentUserID, name: "added")
            value.emojisByID[added.id] = added
        }
        _ = model.composerEmojiSections
        XCTAssertEqual(model.phase68TraceDiagnostics.emojiIndexBuildCount, 2)
    }

    @MainActor
    func testPhase68VisibleRowRequestsOnlyReferencedCurrentServerEmojiOnce() async throws {
        let serverID: ServerID = "phase68-load-server"
        let otherServerID: ServerID = "phase68-load-other"
        let channelID: ChannelID = "phase68-load-channel"
        let one = Emoji(id: "phase68-load-one", parent: .server(serverID), creatorID: "creator", name: "one")
        let two = Emoji(id: "phase68-load-two", parent: .server(serverID), creatorID: "creator", name: "two")
        let unused = Emoji(id: "phase68-load-unused", parent: .server(serverID), creatorID: "creator", name: "unused")
        let other = Emoji(id: "phase68-load-other-emoji", parent: .server(otherServerID), creatorID: "creator", name: "other")
        let snapshot = RealtimeSnapshot(
            serversByID: [serverID: Server(id: serverID, ownerID: "owner", name: "Load")],
            channelsByID: [channelID: Channel(id: channelID, kind: .textChannel, serverID: serverID, name: "general")],
            emojisByID: [one.id: one, two.id: two, unused.id: unused, other.id: other]
        )
        let loader = MockImageResourceLoader(result: .success(Data("emoji".utf8)))
        let model = MainShellViewModel(
            selection: ShellSelection(space: .server(serverID), serverID: serverID, channelID: channelID),
            snapshot: snapshot,
            imageResourceLoader: loader
        )
        let message = Message(
            id: "01J00000000000000000680002",
            channelID: channelID,
            authorID: "author",
            content: ":one: :one: :other:\n```\n:unused:\n```",
            reactions: [two.id.rawValue: ["reactor"], one.id.rawValue: ["reactor"]]
        )

        model.loadCustomEmojiImages(for: message)
        for _ in 0..<80 {
            if await loader.callCount() == 2 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let firstCalls = await loader.calls
        let firstIDs = Set(firstCalls.map(\.id))
        let firstCallCount = await loader.callCount()
        XCTAssertEqual(firstIDs, Set([one.id.rawValue, two.id.rawValue]))
        XCTAssertEqual(firstCallCount, 2)

        model.loadCustomEmojiImages(for: message)
        try await Task.sleep(for: .milliseconds(20))
        let repeatedCallCount = await loader.callCount()
        XCTAssertEqual(repeatedCallCount, 2)
    }

    @MainActor
    func testPhase68VisibleIdentityDiagnosticsBurstCoalescesToLatestBuild() async {
        let serverID: ServerID = "phase68-diagnostics-server"
        let channelID: ChannelID = "phase68-diagnostics-channel"
        let userID: UserID = "phase68-diagnostics-user"
        let user = User(id: userID, username: "diagnostic", displayName: "Diagnostic User")
        let member = ServerMember(id: MemberCompositeKey(serverID: serverID, userID: userID), joinedAt: Date())
        let event = Message(
            id: "01J00000000000000000680003",
            channelID: channelID,
            authorID: userID,
            user: user,
            member: member,
            system: SystemMessage(kind: .userJoined, by: userID)
        )
        let snapshot = RealtimeSnapshot(
            usersByID: [userID: user],
            serversByID: [serverID: Server(id: serverID, ownerID: userID, name: "Diagnostics")],
            channelsByID: [channelID: Channel(id: channelID, kind: .textChannel, serverID: serverID, name: "events")],
            messagesByChannelID: [channelID: [event]],
            membersByServerAndUserID: [ServerMemberKey(serverID: serverID, userID: userID): member]
        )
        let model = MainShellViewModel(
            selection: ShellSelection(space: .server(serverID), serverID: serverID, channelID: channelID),
            snapshot: snapshot
        )

        for _ in 0..<24 {
            model.noteVisibleSystemEvent(event)
        }
        await model.waitForPhase68VisibleIdentityDiagnosticsForTesting()

        XCTAssertEqual(model.phase68TraceDiagnostics.visibleIdentityDiagnosticsRequestCount, 24)
        XCTAssertGreaterThanOrEqual(model.phase68TraceDiagnostics.visibleIdentityDiagnosticsCoalescedCount, 23)
        XCTAssertEqual(model.phase68TraceDiagnostics.visibleIdentityDiagnosticsBuildCount, 1)
        XCTAssertEqual(model.visibleIdentityDiagnostics.phase43.systemEventClickableParticipantCount, 1)
        XCTAssertEqual(model.visibleIdentityDiagnostics.unresolvedVisibleUserCount, 0)
    }

    @MainActor
    func testPhase68VisibleIdentityDiagnosticsDiscardStaleBuildAndPublishLatest() async {
        let userID: UserID = "phase68-stale-user"
        let channelID: ChannelID = "phase68-stale-channel"
        let user = User(id: userID, username: "stale", displayName: "Stale Test")
        let event = Message(
            id: "01J00000000000000000680004",
            channelID: channelID,
            authorID: userID,
            user: user,
            system: SystemMessage(kind: .userJoined, by: userID)
        )
        let model = MainShellViewModel(
            selection: ShellSelection(space: .home, dmChannelID: channelID),
            snapshot: RealtimeSnapshot(
                usersByID: [userID: user],
                channelsByID: [channelID: Channel(id: channelID, kind: .directMessage, recipients: [userID])],
                messagesByChannelID: [channelID: [event]]
            )
        )
        let gate = Phase68DiagnosticsBuildGate()
        model.setPhase68VisibleIdentityDiagnosticsPreparerForTesting { input in
            await gate.prepare(input)
        }

        model.noteVisibleSystemEvent(event)
        while await gate.invocationCount == 0 {
            await Task.yield()
        }
        model.noteVisibleSystemEvent(event)
        await gate.releaseFirstBuild()
        await model.waitForPhase68VisibleIdentityDiagnosticsForTesting()

        XCTAssertEqual(model.phase68TraceDiagnostics.visibleIdentityDiagnosticsBuildCount, 2)
        XCTAssertEqual(model.phase68TraceDiagnostics.visibleIdentityDiagnosticsStaleResultCount, 1)
        XCTAssertEqual(model.visibleIdentityDiagnostics.unresolvedVisibleUserCount, 2)
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

    func testPhase54ParityMatrixMatchesDocumentedSectionItemStatuses() throws {
        let matrix = Phase30ParityMatrixBuilder.build()
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
        XCTAssertEqual(
            matrix.items.first { $0.section == "Server/community" && $0.name == "server emoji management" }?.status,
            .partial
        )

        var repositoryRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<4 {
            repositoryRoot.deleteLastPathComponent()
        }
        let matrixDocument = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Docs/ParityMatrix.md"),
            encoding: .utf8
        )
        let allowedStatuses = Set(ParityStatus.allCases.map(\.rawValue))
        let documentedRows = Set(matrixDocument.split(separator: "\n").compactMap { line -> String? in
            let columns = line.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard columns.count >= 11, allowedStatuses.contains(columns[3]) else { return nil }
            return "\(columns[1])\u{1F}\(columns[2])\u{1F}\(columns[3])"
        })
        let runtimeRows = Set(matrix.items.map {
            "\($0.section)\u{1F}\($0.name)\u{1F}\($0.status.rawValue)"
        })

        XCTAssertEqual(runtimeRows, documentedRows)
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
        let matrix = Phase30ParityMatrixBuilder.build()
        let profileEdit = matrix.items.first { $0.section == "Account and session" && $0.name == "account profile edit" }
        let avatarEdit = matrix.items.first { $0.section == "Account and session" && $0.name == "avatar edit" }
        let backgroundEdit = matrix.items.first { $0.section == "Account and session" && $0.name == "profile banner/background edit" }

        XCTAssertEqual(profileEdit?.status, .partial)
        XCTAssertEqual(avatarEdit?.status, .partial)
        XCTAssertEqual(backgroundEdit?.status, .partial)
        XCTAssertFalse([profileEdit, avatarEdit, backgroundEdit].contains { $0?.status == .done })
    }

    @MainActor
    func testPhase55CustomStatusTextSetPatchesStatusAndPreservesPresence() async {
        var snapshot = RealtimeSnapshot()
        let currentUser = User(id: "phase55-me", username: "me", status: UserStatus(text: nil, presence: .idle), relationship: .user)
        snapshot.usersByID[currentUser.id] = currentUser
        let api = RecordingAPIClient(currentUser: currentUser)
        let model = MainShellViewModel(snapshot: snapshot, currentUser: currentUser, communityAPIClient: api)

        model.customStatusDraft = "  Reviewing bagels  "
        await model.submitCustomStatusDraft()

        let drafts = await api.editedUserDrafts
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts.first?.1.status?.text, "Reviewing bagels")
        XCTAssertEqual(drafts.first?.1.status?.presence, .idle)
        XCTAssertTrue(drafts.first?.1.remove.isEmpty ?? false)
        XCTAssertEqual(model.currentUserForPresentation?.status?.text, "Reviewing bagels")
        XCTAssertEqual(model.currentUserForPresentation?.status?.presence, .idle)
        XCTAssertFalse(model.isPresentingCustomStatusEditor)
    }

    @MainActor
    func testPhase55CustomStatusClearUsesRemoveStatusTextField() async {
        var snapshot = RealtimeSnapshot()
        let currentUser = User(id: "phase55-me", username: "me", status: UserStatus(text: "old status", presence: .online), relationship: .user)
        snapshot.usersByID[currentUser.id] = currentUser
        let api = RecordingAPIClient(currentUser: currentUser)
        let model = MainShellViewModel(snapshot: snapshot, currentUser: currentUser, communityAPIClient: api)

        await model.clearCustomStatus()

        let drafts = await api.editedUserDrafts
        XCTAssertEqual(drafts.count, 1)
        XCTAssertNil(drafts.first?.1.status)
        XCTAssertEqual(drafts.first?.1.remove, [.statusText])
        XCTAssertNil(model.currentUserForPresentation?.status?.text)
        XCTAssertEqual(model.currentUserForPresentation?.status?.presence, .online)
    }

    @MainActor
    func testPhase55CustomStatusFailureRollsBackOptimisticText() async {
        var snapshot = RealtimeSnapshot()
        let currentUser = User(id: "phase55-me", username: "me", status: UserStatus(text: "keep me", presence: .online), relationship: .user)
        snapshot.usersByID[currentUser.id] = currentUser
        let api = RecordingAPIClient(currentUser: currentUser, editUserError: StoatAPIError.serverError(statusCode: 500, message: "nope"))
        let model = MainShellViewModel(snapshot: snapshot, currentUser: currentUser, communityAPIClient: api)

        await model.setCurrentUserStatusText("new text")

        let editCount = await api.editUserCallCount
        XCTAssertEqual(editCount, 1)
        XCTAssertEqual(model.currentUserForPresentation?.status?.text, "keep me")
        XCTAssertNotNil(model.statusUpdateStatus)
        XCTAssertTrue(model.statusUpdateStatus?.contains("failed") ?? false)
    }

    @MainActor
    func testPhase55CustomStatusOverLimitAndUnchangedDraftsDoNotMutate() async {
        var snapshot = RealtimeSnapshot()
        let currentUser = User(id: "phase55-me", username: "me", status: UserStatus(text: "same", presence: .online), relationship: .user)
        snapshot.usersByID[currentUser.id] = currentUser
        let api = RecordingAPIClient(currentUser: currentUser)
        let model = MainShellViewModel(snapshot: snapshot, currentUser: currentUser, communityAPIClient: api)

        model.openCustomStatusEditor()
        XCTAssertEqual(model.customStatusDraft, "same")
        XCTAssertTrue(model.isPresentingCustomStatusEditor)

        model.customStatusDraft = String(repeating: "x", count: MainShellViewModel.customStatusTextLimit + 1)
        await model.submitCustomStatusDraft()
        XCTAssertTrue(model.isPresentingCustomStatusEditor)

        model.customStatusDraft = "same"
        await model.submitCustomStatusDraft()

        let editCount = await api.editUserCallCount
        XCTAssertEqual(editCount, 0)
        XCTAssertFalse(model.isPresentingCustomStatusEditor)
    }

    @MainActor
    func testPhase55CreateGroupMergesChannelAndSelectsConversation() async {
        var snapshot = RealtimeSnapshot()
        let currentUser = User(id: "phase55-me", username: "me", relationship: .user)
        snapshot.usersByID[currentUser.id] = currentUser
        let api = RecordingAPIClient(currentUser: currentUser)
        let model = MainShellViewModel(snapshot: snapshot, currentUser: currentUser, communityAPIClient: api)

        model.openNewGroup()
        XCTAssertTrue(model.isPresentingNewGroup)
        model.groupCreateName = " Bagel Crew "
        model.toggleNewGroupCandidate("phase55-friend-b")
        model.toggleNewGroupCandidate("phase55-friend-a")
        await model.createGroupFromDraft()

        let drafts = await api.createdGroupDrafts
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts.first?.name, "Bagel Crew")
        XCTAssertEqual(drafts.first?.users, ["phase55-friend-a", "phase55-friend-b"])
        guard case let .created(channelID) = model.groupCreateState else {
            XCTFail("Expected created state, got \(model.groupCreateState)")
            return
        }
        XCTAssertFalse(model.isPresentingNewGroup)
        XCTAssertEqual(model.selectedConversationChannelID, channelID)
        XCTAssertEqual(model.snapshot.channelsByID[channelID]?.kind, .group)
        XCTAssertEqual(model.snapshot.channelsByID[channelID]?.name, "Bagel Crew")
        XCTAssertTrue(model.groupCreateName.isEmpty)
        XCTAssertTrue(model.groupCreateSelectedUserIDs.isEmpty)
    }

    @MainActor
    func testPhase55CreateGroupFailureKeepsDraftAndReportsSafeError() async {
        var snapshot = RealtimeSnapshot()
        let currentUser = User(id: "phase55-me", username: "me", relationship: .user)
        snapshot.usersByID[currentUser.id] = currentUser
        let api = RecordingAPIClient(
            currentUser: currentUser,
            createGroupError: StoatAPIError.serverError(statusCode: 500, message: "nope")
        )
        let model = MainShellViewModel(snapshot: snapshot, currentUser: currentUser, communityAPIClient: api)

        model.openNewGroup()
        model.groupCreateName = "Bagel Crew"
        model.toggleNewGroupCandidate("phase55-friend-a")
        await model.createGroupFromDraft()

        guard case let .failed(message) = model.groupCreateState else {
            XCTFail("Expected failed state, got \(model.groupCreateState)")
            return
        }
        XCTAssertFalse(message.contains("500"))
        XCTAssertTrue(model.isPresentingNewGroup)
        XCTAssertEqual(model.groupCreateName, "Bagel Crew")
        XCTAssertEqual(model.groupCreateSelectedUserIDs, ["phase55-friend-a"])

        model.groupCreateName = "   "
        await model.createGroupFromDraft()
        let draftCount = await api.createdGroupDrafts.count
        XCTAssertEqual(draftCount, 1)
        if case .failed = model.groupCreateState {} else {
            XCTFail("Empty group name should fail validation")
        }
    }

    @MainActor
    func testPhase58AddGroupMemberOptimisticAppendAndGatewayEchoDeduplicates() async {
        let currentUser = User(id: "phase58-me", username: "me", relationship: .user)
        let groupID = ChannelID(rawValue: "phase58-group")
        var snapshot = RealtimeSnapshot()
        snapshot.usersByID[currentUser.id] = currentUser
        snapshot.channelsByID[groupID] = Channel(id: groupID, kind: .group, name: "Bagel Crew", ownerID: currentUser.id, active: true, recipients: [currentUser.id])
        let api = RecordingAPIClient(currentUser: currentUser)
        let model = MainShellViewModel(snapshot: snapshot, currentUser: currentUser, communityAPIClient: api)

        model.openAddGroupMembers(for: groupID)
        XCTAssertTrue(model.isPresentingAddGroupMembers)
        model.toggleAddGroupMemberCandidate("phase58-friend-a")
        await model.addSelectedGroupMembers()

        let added = await api.addedGroupRecipients
        XCTAssertEqual(added.count, 1)
        XCTAssertEqual(added.first?.0, groupID)
        XCTAssertEqual(added.first?.1, "phase58-friend-a")
        XCTAssertEqual(model.snapshot.channelsByID[groupID]?.recipients, [currentUser.id, "phase58-friend-a"])
        XCTAssertFalse(model.isPresentingAddGroupMembers)

        // Re-running the add for the same now-present recipient (as a realtime ChannelGroupJoin
        // echo would trigger through the same optimistic-append guard) must not duplicate.
        model.openAddGroupMembers(for: groupID)
        model.toggleAddGroupMemberCandidate("phase58-friend-a")
        await model.addSelectedGroupMembers()
        XCTAssertEqual(model.snapshot.channelsByID[groupID]?.recipients, [currentUser.id, "phase58-friend-a"])
    }

    @MainActor
    func testPhase58AddGroupMemberFailureKeepsSheetOpenAndReportsSafeError() async {
        let currentUser = User(id: "phase58-me", username: "me", relationship: .user)
        let groupID = ChannelID(rawValue: "phase58-group")
        var snapshot = RealtimeSnapshot()
        snapshot.usersByID[currentUser.id] = currentUser
        snapshot.channelsByID[groupID] = Channel(id: groupID, kind: .group, name: "Bagel Crew", ownerID: currentUser.id, active: true, recipients: [currentUser.id])
        let api = RecordingAPIClient(currentUser: currentUser, addGroupRecipientError: StoatAPIError.forbidden)
        let model = MainShellViewModel(snapshot: snapshot, currentUser: currentUser, communityAPIClient: api)

        model.openAddGroupMembers(for: groupID)
        model.toggleAddGroupMemberCandidate("phase58-not-a-friend")
        await model.addSelectedGroupMembers()

        guard case .failed = model.groupMembershipActionState else {
            XCTFail("Expected failed state, got \(model.groupMembershipActionState)")
            return
        }
        XCTAssertTrue(model.isPresentingAddGroupMembers)
        XCTAssertEqual(model.snapshot.channelsByID[groupID]?.recipients, [currentUser.id])
    }

    @MainActor
    func testPhase58RemoveGroupMemberIsOwnerGatedAndConfirmed() async {
        let currentUser = User(id: "phase58-owner", username: "owner", relationship: .user)
        let groupID = ChannelID(rawValue: "phase58-group")
        var snapshot = RealtimeSnapshot()
        snapshot.usersByID[currentUser.id] = currentUser
        snapshot.channelsByID[groupID] = Channel(id: groupID, kind: .group, name: "Bagel Crew", ownerID: currentUser.id, active: true, recipients: [currentUser.id, "phase58-member-a"])
        let api = RecordingAPIClient(currentUser: currentUser)
        let model = MainShellViewModel(snapshot: snapshot, currentUser: currentUser, communityAPIClient: api)

        // Self-removal must never be requestable through this path.
        model.requestRemoveGroupMember(currentUser.id, from: groupID, displayName: "Me")
        XCTAssertNil(model.pendingGroupMemberRemoval)

        model.requestRemoveGroupMember("phase58-member-a", from: groupID, displayName: "Member A")
        XCTAssertEqual(model.pendingGroupMemberRemoval?.userID, "phase58-member-a")

        await model.confirmRemoveGroupMember()

        let removed = await api.removedGroupRecipients
        XCTAssertEqual(removed.count, 1)
        XCTAssertEqual(removed.first?.0, groupID)
        XCTAssertEqual(removed.first?.1, "phase58-member-a")
        XCTAssertEqual(model.snapshot.channelsByID[groupID]?.recipients, [currentUser.id])
        XCTAssertNil(model.pendingGroupMemberRemoval)
    }

    @MainActor
    func testPhase58RemoveGroupMemberBlockedForNonOwner() async {
        let currentUser = User(id: "phase58-non-owner", username: "notowner", relationship: .user)
        let ownerID = UserID(rawValue: "phase58-owner")
        let groupID = ChannelID(rawValue: "phase58-group")
        var snapshot = RealtimeSnapshot()
        snapshot.usersByID[currentUser.id] = currentUser
        snapshot.channelsByID[groupID] = Channel(id: groupID, kind: .group, name: "Bagel Crew", ownerID: ownerID, active: true, recipients: [ownerID, currentUser.id, "phase58-member-a"])
        let api = RecordingAPIClient(currentUser: currentUser)
        let model = MainShellViewModel(snapshot: snapshot, currentUser: currentUser, communityAPIClient: api)

        model.requestRemoveGroupMember("phase58-member-a", from: groupID, displayName: "Member A")
        XCTAssertNil(model.pendingGroupMemberRemoval, "Only the group owner may request removal of another member")

        let removed = await api.removedGroupRecipients
        XCTAssertTrue(removed.isEmpty)
    }

    @MainActor
    func testPhase58AddCandidatesExcludeExistingRecipients() {
        let currentUser = User(id: "phase58-me", username: "me", relationship: .user)
        let existingFriend = User(id: "phase58-friend-existing", username: "already-in", relationship: .user)
        let newFriend = User(id: "phase58-friend-new", username: "not-in-yet", relationship: .user)
        let groupID = ChannelID(rawValue: "phase58-group")
        var friendedCurrentUser = currentUser
        friendedCurrentUser.relations = [
            Relationship(id: existingFriend.id, status: .friend),
            Relationship(id: newFriend.id, status: .friend)
        ]
        var snapshot = RealtimeSnapshot()
        snapshot.usersByID[currentUser.id] = friendedCurrentUser
        snapshot.usersByID[existingFriend.id] = existingFriend
        snapshot.usersByID[newFriend.id] = newFriend
        snapshot.channelsByID[groupID] = Channel(id: groupID, kind: .group, name: "Bagel Crew", ownerID: currentUser.id, active: true, recipients: [currentUser.id, existingFriend.id])
        let model = MainShellViewModel(snapshot: snapshot, currentUser: friendedCurrentUser, communityAPIClient: MockStoatAPIClient())

        let candidates = model.addGroupMemberCandidates(for: groupID)
        XCTAssertEqual(candidates.map(\.user.id), [newFriend.id])
    }

    func testPhase58RowPresentationResolvesMentionItemsCacheOnly() {
        let authorID: UserID = "phase58-author"
        let mentionedID: UserID = "01FD58YK5W7QRV5H3D64KTQYX3"
        let channelID: ChannelID = "phase58-mention-channel"
        var snapshot = RealtimeSnapshot()
        snapshot.usersByID[mentionedID] = User(id: mentionedID, username: "enka", displayName: "Enka")
        snapshot.channelsByID[channelID] = Channel(id: channelID, kind: .textChannel, name: "general")
        let message = Message(
            id: "01J00000000000000000580001",
            channelID: channelID,
            authorID: authorID,
            content: "hi <@\(mentionedID.rawValue)>"
        )

        let context = Phase52TimelineAssetContext(snapshot: snapshot, imageDataByKey: [:])
        let items = context.inlineReferenceItems(
            for: message,
            identitySnapshots: Phase43IdentitySnapshotStore(),
            currentUserID: authorID
        )

        let item = try? XCTUnwrap(items["<@\(mentionedID.rawValue)>"])
        XCTAssertEqual(item?.displayName, "Enka")
        XCTAssertEqual(item?.isFallback, false)
        XCTAssertEqual(item?.isCurrentUser, false)
    }

    func testPhase58UnresolvedMentionInPipelineProducesFallbackItem() {
        let channelID: ChannelID = "phase58-mention-channel-2"
        var snapshot = RealtimeSnapshot()
        snapshot.channelsByID[channelID] = Channel(id: channelID, kind: .textChannel, name: "general")
        let unknownID = "01FD58YK5W7QRV5H3D64KTQYX9"
        let message = Message(
            id: "01J00000000000000000580002",
            channelID: channelID,
            authorID: "phase58-author",
            content: "hi <@\(unknownID)>"
        )

        let context = Phase52TimelineAssetContext(snapshot: snapshot, imageDataByKey: [:])
        let items = context.inlineReferenceItems(
            for: message,
            identitySnapshots: Phase43IdentitySnapshotStore(),
            currentUserID: nil
        )

        let item = try? XCTUnwrap(items["<@\(unknownID)>"])
        XCTAssertEqual(item?.displayName, "Unknown member")
        XCTAssertEqual(item?.isFallback, true)
    }

    func testPhase58SelfMentionRowAccentFlagComputedFromMessageMentions() {
        let currentUserID: UserID = "phase58-current"
        let otherUserID: UserID = "phase58-other"
        let channelID: ChannelID = "phase58-accent-channel"
        let mentioningCurrentUser = Message(
            id: "01J00000000000000000580003",
            channelID: channelID,
            authorID: otherUserID,
            content: "hi <@\(currentUserID.rawValue)>",
            mentions: [currentUserID]
        )
        let mentioningSomeoneElse = Message(
            id: "01J00000000000000000580004",
            channelID: channelID,
            authorID: otherUserID,
            content: "hi <@\(otherUserID.rawValue)>",
            mentions: [otherUserID]
        )
        let noMentions = Message(id: "01J00000000000000000580005", channelID: channelID, authorID: otherUserID, content: "hi")

        XCTAssertTrue(Phase52TimelineInteractionPreparer.mentionsCurrentUser(mentioningCurrentUser, currentUserID: currentUserID))
        XCTAssertFalse(Phase52TimelineInteractionPreparer.mentionsCurrentUser(mentioningSomeoneElse, currentUserID: currentUserID))
        XCTAssertFalse(Phase52TimelineInteractionPreparer.mentionsCurrentUser(noMentions, currentUserID: currentUserID))
        XCTAssertFalse(Phase52TimelineInteractionPreparer.mentionsCurrentUser(mentioningCurrentUser, currentUserID: nil))
    }

    @MainActor
    func testPhase58MentionCandidateIndexRebuildsOnlyOnGenerationChange() {
        let currentUser = User(id: "phase58-idx-me", username: "me", relationship: .user)
        let alice = User(id: "phase58-idx-alice", username: "alice", displayName: "Alice")
        let bob = User(id: "phase58-idx-bob", username: "bob", displayName: "Bob")
        let groupID = ChannelID(rawValue: "phase58-idx-group")
        var snapshot = RealtimeSnapshot()
        snapshot.usersByID[currentUser.id] = currentUser
        snapshot.usersByID[alice.id] = alice
        snapshot.usersByID[bob.id] = bob
        snapshot.channelsByID[groupID] = Channel(id: groupID, kind: .group, name: "Crew", ownerID: currentUser.id, active: true, recipients: [currentUser.id, alice.id, bob.id])
        let model = MainShellViewModel(snapshot: snapshot, currentUser: currentUser)

        model.composerInlineTriggerChanged(InlineComposerTrigger(utf16Location: 0, utf16Length: 1, query: ""), for: groupID)
        XCTAssertEqual(Set(model.composerAutocompleteCandidates.map(\.name)), ["Alice", "Bob"])

        var updatedSnapshot = model.snapshot
        let carol = User(id: "phase58-idx-carol", username: "carol", displayName: "Carol")
        updatedSnapshot.usersByID[carol.id] = carol
        if var channel = updatedSnapshot.channelsByID[groupID] {
            channel.recipients.append(carol.id)
            updatedSnapshot.channelsByID[groupID] = channel
        }
        model.replaceSnapshotForTesting(updatedSnapshot)

        model.composerInlineTriggerChanged(InlineComposerTrigger(utf16Location: 0, utf16Length: 1, query: ""), for: groupID)
        XCTAssertEqual(Set(model.composerAutocompleteCandidates.map(\.name)), ["Alice", "Bob", "Carol"])
    }

    @MainActor
    func testPhase58AutocompleteQueryIsCancellableAndCapped() {
        let currentUser = User(id: "phase58-cap-me", username: "me", relationship: .user)
        let groupID = ChannelID(rawValue: "phase58-cap-group")
        var snapshot = RealtimeSnapshot()
        snapshot.usersByID[currentUser.id] = currentUser
        var recipients = [currentUser.id]
        for index in 0..<15 {
            let user = User(id: UserID(rawValue: "phase58-cap-user-\(index)"), username: "user\(index)", displayName: "Match\(index)")
            snapshot.usersByID[user.id] = user
            recipients.append(user.id)
        }
        snapshot.channelsByID[groupID] = Channel(id: groupID, kind: .group, name: "Big Crew", ownerID: currentUser.id, active: true, recipients: recipients)
        let model = MainShellViewModel(snapshot: snapshot, currentUser: currentUser)

        model.composerInlineTriggerChanged(InlineComposerTrigger(utf16Location: 0, utf16Length: 1, query: "match"), for: groupID)
        XCTAssertEqual(model.composerAutocompleteCandidates.count, 10)
        XCTAssertTrue(model.composerAutocompleteCandidates.allSatisfy { $0.name.lowercased().hasPrefix("match") })
    }

    @MainActor
    func testPhase58MentionInsertionProducesVerifiedTokenSyntax() {
        let currentUser = User(id: "phase58-ins-me", username: "me", relationship: .user)
        let alice = User(id: "phase58-ins-alice", username: "alice", displayName: "Alice")
        let groupID = ChannelID(rawValue: "phase58-ins-group")
        var snapshot = RealtimeSnapshot()
        snapshot.usersByID[currentUser.id] = currentUser
        snapshot.usersByID[alice.id] = alice
        snapshot.channelsByID[groupID] = Channel(id: groupID, kind: .group, name: "Crew", ownerID: currentUser.id, active: true, recipients: [currentUser.id, alice.id])
        let model = MainShellViewModel(snapshot: snapshot, currentUser: currentUser)

        model.updateDraft("hi @al", for: groupID)
        model.composerInlineTriggerChanged(InlineComposerTrigger(utf16Location: 3, utf16Length: 3, query: "al"), for: groupID)
        guard let candidate = model.composerAutocompleteCandidates.first(where: { $0.userID == alice.id }) else {
            XCTFail("expected Alice among candidates")
            return
        }
        model.selectComposerAutocompleteCandidate(candidate, for: groupID)

        let expectedToken = "hi <@\(alice.id.rawValue)> "
        XCTAssertEqual(model.draft(for: groupID), expectedToken)
        XCTAssertNil(model.composerAutocompleteTrigger)
        XCTAssertTrue(model.composerAutocompleteCandidates.isEmpty)
        XCTAssertEqual(model.composerCursorRequest?.utf16Offset, (expectedToken as NSString).length)
    }

    @MainActor
    func testPhase71EmojiInsertionUsesUTF16CaretAndSafeFallbacks() {
        let channelID: ChannelID = "phase71-caret-channel"
        var snapshot = RealtimeSnapshot()
        snapshot.channelsByID[channelID] = Channel(id: channelID, kind: .group, name: "Caret")
        let model = MainShellViewModel(snapshot: snapshot)

        model.updateDraft("A😀B", for: channelID)
        model.insertEmoji("🥯", at: 3, in: channelID)
        XCTAssertEqual(model.draft(for: channelID), "A😀🥯B")
        XCTAssertEqual(model.composerCursorRequest?.utf16Offset, 5)

        model.updateDraft("A😀B", for: channelID)
        model.insertEmoji("🥯", in: channelID)
        XCTAssertEqual(model.draft(for: channelID), "A😀B🥯")

        model.updateDraft("A😀B", for: channelID)
        model.insertEmoji("🥯", at: 999, in: channelID)
        XCTAssertEqual(model.draft(for: channelID), "A😀B🥯")
        XCTAssertEqual(model.composerCursorRequest?.utf16Offset, 6)
    }

    @MainActor
    func testPhase71ChannelRoleAndEmojiAutocompleteScopeOrderingAndTokens() throws {
        let currentUser = User(id: "phase71-me", username: "me", relationship: .user)
        let serverID: ServerID = "phase71-server"
        let generalID: ChannelID = "phase71-general"
        let randomID: ChannelID = "phase71-random"
        let voiceID: ChannelID = "phase71-voice"
        let dmID: ChannelID = "phase71-dm"
        let adminID: RoleID = "phase71-admin"
        let memberID: RoleID = "phase71-member"
        let emojiID: EmojiID = "01J00000000000000000710001"
        let roles = [
            memberID: Role(id: memberID, name: "Member", permissions: PermissionOverride(), rank: 20),
            adminID: Role(id: adminID, name: "Admin", permissions: PermissionOverride(), colour: "#3366CC", rank: 1)
        ]
        let server = Server(
            id: serverID,
            ownerID: currentUser.id,
            name: "Phase 71",
            channelIDs: [generalID, voiceID, randomID],
            roles: roles
        )
        var snapshot = RealtimeSnapshot()
        snapshot.usersByID[currentUser.id] = currentUser
        snapshot.serversByID[serverID] = server
        snapshot.channelsByID[generalID] = Channel(id: generalID, kind: .textChannel, serverID: serverID, name: "general")
        snapshot.channelsByID[randomID] = Channel(id: randomID, kind: .textChannel, serverID: serverID, name: "random")
        snapshot.channelsByID[voiceID] = Channel(id: voiceID, kind: .voiceChannel, serverID: serverID, name: "voice")
        snapshot.channelsByID[dmID] = Channel(id: dmID, kind: .directMessage, name: "DM", recipients: [currentUser.id])
        snapshot.emojisByID[emojiID] = Emoji(id: emojiID, parent: .server(serverID), creatorID: currentUser.id, name: "bagel_party")
        let model = MainShellViewModel(
            selection: ShellSelection(space: .server(serverID), serverID: serverID, channelID: generalID),
            snapshot: snapshot,
            currentUser: currentUser
        )

        model.composerInlineTriggerChanged(
            InlineComposerTrigger(utf16Location: 0, utf16Length: 1, query: "", kind: .channel),
            for: generalID
        )
        XCTAssertEqual(model.composerAutocompleteCandidates.map(\.rawID), [generalID.rawValue, randomID.rawValue])

        model.composerInlineTriggerChanged(
            InlineComposerTrigger(utf16Location: 0, utf16Length: 1, query: "", kind: .channel),
            for: dmID
        )
        XCTAssertTrue(model.composerAutocompleteCandidates.isEmpty)

        model.composerInlineTriggerChanged(
            InlineComposerTrigger(utf16Location: 0, utf16Length: 1, query: "", kind: .role),
            for: generalID
        )
        XCTAssertEqual(model.composerAutocompleteCandidates.map(\.rawID), [adminID.rawValue, memberID.rawValue])
        XCTAssertNotNil(model.composerAutocompleteCandidates.first?.roleColor)

        model.updateDraft("#ge", for: generalID)
        model.composerInlineTriggerChanged(
            InlineComposerTrigger(utf16Location: 0, utf16Length: 3, query: "ge", kind: .channel),
            for: generalID
        )
        model.selectComposerAutocompleteCandidate(try XCTUnwrap(model.composerAutocompleteCandidates.first), for: generalID)
        XCTAssertEqual(model.draft(for: generalID), "<#\(generalID.rawValue)> ")

        model.updateDraft("%ad", for: generalID)
        model.composerInlineTriggerChanged(
            InlineComposerTrigger(utf16Location: 0, utf16Length: 3, query: "ad", kind: .role),
            for: generalID
        )
        model.selectComposerAutocompleteCandidate(try XCTUnwrap(model.composerAutocompleteCandidates.first), for: generalID)
        XCTAssertEqual(model.draft(for: generalID), "<%\(adminID.rawValue)> ")

        let pickerToken = try XCTUnwrap(
            model.composerEmojiSections.flatMap(\.items).first { $0.displayName == "bagel_party" }?.insertionText
        )
        model.composerInlineTriggerChanged(
            InlineComposerTrigger(utf16Location: 0, utf16Length: 3, query: "ba", kind: .emoji),
            for: generalID
        )
        let emojiCandidate = try XCTUnwrap(model.composerAutocompleteCandidates.first)
        XCTAssertEqual(Phase71ComposerToken.insertionText(for: emojiCandidate), pickerToken)
        XCTAssertEqual(pickerToken, ":\(emojiID.rawValue):")
    }

    @MainActor
    func testPhase71EmojiAutocompleteReusesPhase68IndexAndAliasIndexKeepsCap() {
        let serverID: ServerID = "phase71-cache-server"
        let channelID: ChannelID = "phase71-cache-channel"
        var snapshot = RealtimeSnapshot()
        snapshot.serversByID[serverID] = Server(id: serverID, ownerID: "owner", name: "Cache")
        snapshot.channelsByID[channelID] = Channel(id: channelID, kind: .textChannel, serverID: serverID, name: "general")
        for index in 0..<15 {
            let id = EmojiID(rawValue: String(format: "01J0000000000000000071%04d", index))
            snapshot.emojisByID[id] = Emoji(id: id, parent: .server(serverID), creatorID: "owner", name: "party_\(index)")
        }
        let model = MainShellViewModel(snapshot: snapshot)

        for query in ["pa", "par", "party"] {
            model.composerInlineTriggerChanged(
                InlineComposerTrigger(utf16Location: 0, utf16Length: query.count + 1, query: query, kind: .emoji),
                for: channelID
            )
        }
        XCTAssertEqual(model.phase68TraceDiagnostics.emojiIndexBuildCount, 1)
        XCTAssertGreaterThanOrEqual(model.phase68TraceDiagnostics.emojiIndexCacheHitCount, 3)
        XCTAssertEqual(model.composerAutocompleteCandidates.count, 10)

        let aliasCandidates = (0..<12).map { index in
            ComposerAutocompleteCandidate(
                kind: .emoji,
                rawID: "alias-\(index)",
                name: "Artwork \(index)",
                searchAliases: ["party\(index)"]
            )
        }
        let aliasMatches = Phase58MentionCandidateIndex(candidates: aliasCandidates).matches(prefix: "party", limit: 10)
        XCTAssertEqual(aliasMatches.count, 10)
        XCTAssertEqual(Set(aliasMatches.map(\.id)).count, 10)
    }

    func testPhase71VerifiedMacShortcutTableHasOfficialUniqueMappings() throws {
        let shortcuts = Phase71Keybinds.verifiedMacShortcuts
        XCTAssertEqual(shortcuts[.selectPreviousServer]?.key, .upArrow)
        XCTAssertEqual(shortcuts[.selectPreviousServer]?.modifiers, [.command, .control])
        XCTAssertEqual(shortcuts[.selectNextServer]?.key, .downArrow)
        XCTAssertEqual(shortcuts[.selectNextServer]?.modifiers, [.command, .control])
        XCTAssertEqual(shortcuts[.selectPreviousChannel]?.key, .upArrow)
        XCTAssertEqual(shortcuts[.selectPreviousChannel]?.modifiers, [.command])
        XCTAssertEqual(shortcuts[.selectNextChannel]?.key, .downArrow)
        XCTAssertEqual(shortcuts[.selectNextChannel]?.modifiers, [.command])

        let identities = shortcuts.values.map { "\($0.key.character)|\($0.modifiers)" }
        XCTAssertEqual(Set(identities).count, identities.count)
    }

    @MainActor
    func testPhase71NilTriggerPublicationsPreservePhase63SuppressionContract() {
        let model = MainShellViewModel(snapshot: RealtimeSnapshot())
        let publications = model.phase63ComposerDiagnostics.inlineTriggerPublicationCount
        let suppressions = model.phase63ComposerDiagnostics.inlineTriggerSuppressionCount

        model.composerInlineTriggerChanged(nil, for: nil)
        model.composerInlineTriggerChanged(nil, for: nil)

        XCTAssertEqual(model.phase63ComposerDiagnostics.inlineTriggerPublicationCount, publications + 2)
        XCTAssertEqual(model.phase63ComposerDiagnostics.inlineTriggerSuppressionCount, suppressions + 2)
    }

    @MainActor
    func testPhase55CloudPreferencesFetchAppliesNewerRemote() async throws {
        var snapshot = RealtimeSnapshot()
        let currentUser = User(id: "phase55-me", username: "me", relationship: .user)
        snapshot.usersByID[currentUser.id] = currentUser
        let remote = SyncedClientPreferences(
            messageDensity: .compact,
            liquidGlassTransparency: 0.4,
            inlineImagePreviewPolicy: .explicitClickOnly
        )
        let payload = String(decoding: try JSONEncoder().encode(remote), as: UTF8.self)
        let api = RecordingAPIClient(
            currentUser: currentUser,
            syncedSettings: [MainShellViewModel.cloudPreferencesKey: SyncedSettingValue(timestamp: 200, rawValue: payload)]
        )
        let model = MainShellViewModel(snapshot: snapshot, currentUser: currentUser, communityAPIClient: api)

        await model.fetchCloudPreferences()

        let fetchedKeys = await api.fetchedSettingsKeys
        XCTAssertEqual(fetchedKeys, [[MainShellViewModel.cloudPreferencesKey]])
        XCTAssertEqual(model.settingsSyncState, .applied(200))
        XCTAssertEqual(model.messageDensity, .compact)
        XCTAssertEqual(model.liquidGlassTransparency, 0.4, accuracy: 0.001)
        XCTAssertEqual(model.inlineImagePreviewPolicy, .explicitClickOnly)
    }

    @MainActor
    func testPhase55CloudPreferencesStaleRemoteRequiresExplicitApply() async throws {
        var snapshot = RealtimeSnapshot()
        let currentUser = User(id: "phase55-me", username: "me", relationship: .user)
        snapshot.usersByID[currentUser.id] = currentUser
        let newer = SyncedClientPreferences(messageDensity: .compact)
        let older = SyncedClientPreferences(messageDensity: .comfortable, liquidGlassTransparency: 0.3)
        let api = RecordingAPIClient(
            currentUser: currentUser,
            syncedSettings: [
                MainShellViewModel.cloudPreferencesKey: SyncedSettingValue(
                    timestamp: 200,
                    rawValue: String(decoding: try JSONEncoder().encode(newer), as: UTF8.self)
                )
            ]
        )
        let model = MainShellViewModel(snapshot: snapshot, currentUser: currentUser, communityAPIClient: api)

        await model.fetchCloudPreferences()
        XCTAssertEqual(model.settingsSyncState, .applied(200))
        XCTAssertEqual(model.messageDensity, .compact)

        await api.overrideSyncedSetting(
            key: MainShellViewModel.cloudPreferencesKey,
            value: SyncedSettingValue(timestamp: 100, rawValue: String(decoding: try JSONEncoder().encode(older), as: UTF8.self))
        )
        await model.fetchCloudPreferences()
        XCTAssertEqual(model.settingsSyncState, .staleRemote(100))
        XCTAssertEqual(model.messageDensity, .compact)

        await model.fetchCloudPreferences(applyOlder: true)
        XCTAssertEqual(model.settingsSyncState, .applied(100))
        XCTAssertEqual(model.messageDensity, .comfortable)
        XCTAssertEqual(model.liquidGlassTransparency, 0.3, accuracy: 0.001)
    }

    @MainActor
    func testPhase55CloudPreferencesPushSendsAllowlistedPayloadAndEmptyStateReports() async throws {
        var snapshot = RealtimeSnapshot()
        let currentUser = User(id: "phase55-me", username: "me", relationship: .user)
        snapshot.usersByID[currentUser.id] = currentUser
        let api = RecordingAPIClient(currentUser: currentUser)
        let model = MainShellViewModel(snapshot: snapshot, currentUser: currentUser, communityAPIClient: api)

        await model.fetchCloudPreferences()
        XCTAssertEqual(model.settingsSyncState, .empty)

        model.messageDensity = .compact
        model.liquidGlassTransparency = 0.5
        await model.pushCloudPreferences()

        let payloads = await api.setSettingsPayloads
        XCTAssertEqual(payloads.count, 1)
        let payload = try XCTUnwrap(payloads.first)
        XCTAssertGreaterThan(payload.timestamp, 0)
        XCTAssertEqual(model.settingsSyncState, .pushed(payload.timestamp))
        let raw = try XCTUnwrap(payload.values[MainShellViewModel.cloudPreferencesKey])
        let decoded = try JSONDecoder().decode(SyncedClientPreferences.self, from: Data(raw.utf8))
        XCTAssertEqual(decoded.messageDensity, .compact)
        XCTAssertEqual(decoded.liquidGlassTransparency, 0.5, accuracy: 0.001)
        XCTAssertNil(raw.range(of: "environmentProfiles"))
        XCTAssertNil(raw.range(of: "lastSelected"))
    }

    @MainActor
    func testPhase55CloudPreferencesFailureReportsSafeError() async {
        var snapshot = RealtimeSnapshot()
        let currentUser = User(id: "phase55-me", username: "me", relationship: .user)
        snapshot.usersByID[currentUser.id] = currentUser
        let api = RecordingAPIClient(
            currentUser: currentUser,
            settingsSyncError: StoatAPIError.serverError(statusCode: 500, message: "secret detail")
        )
        let model = MainShellViewModel(snapshot: snapshot, currentUser: currentUser, communityAPIClient: api)

        await model.fetchCloudPreferences()
        guard case let .failed(message) = model.settingsSyncState else {
            XCTFail("Expected failed state, got \(model.settingsSyncState)")
            return
        }
        XCTAssertFalse(message.contains("500"))
        XCTAssertFalse(message.contains("secret detail"))
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
    func testPhase40RefreshDMsMergesChannelsWithoutDuplicates() async throws {
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
        try await Task.sleep(for: .milliseconds(30))

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
    func testPhase24ServerOverviewAndPermissionGating() async throws {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot)
        let server = model.servers.first { $0.name == "Bagel Lab" }!

        model.selectServer(server.id)
        model.openServerOverview()
        try await Task.sleep(for: .milliseconds(20))

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
        model.channelEditForm?.slowmodeSeconds = 30
        await model.saveChannelSettings()

        XCTAssertEqual(model.snapshot.channelsByID[created!.id]?.displayName, "phase-24-renamed")
        XCTAssertNil(model.snapshot.channelsByID[created!.id]?.description)
        XCTAssertEqual(model.snapshot.channelsByID[created!.id]?.slowmode, 30)

        model.requestDeleteSelectedChannel()
        XCTAssertEqual(model.pendingChannelDeletion?.channel.id, created!.id)
        await model.confirmPendingChannelDeletion()

        XCTAssertNil(model.snapshot.channelsByID[created!.id])
        XCTAssertNotEqual(model.selection.channelID, created!.id)
        XCTAssertEqual(model.phase24Status, "Channel deleted")
    }

    @MainActor
    func testPhase53ServerEmojiCreateRefreshDeleteUsesPreparedSettings() async throws {
        var snapshot = MockShellData.snapshot
        let server = try XCTUnwrap(snapshot.serversByID.values.first { $0.name == "Bagel Lab" })
        snapshot.serversByID[server.id]?.defaultPermissions.insert(.manageCustomisation)
        let model = MainShellViewModel(
            snapshot: snapshot,
            runtimeMode: .mock,
            communityAPIClient: MockStoatAPIClient()
        )
        model.selectServer(server.id)
        model.openServerOverview()
        try await Task.sleep(for: .milliseconds(20))

        model.serverEmojiName = "phase53"
        model.serverEmojiDraft = ServerMediaDraft(
            data: Data([0x89, 0x50, 0x4E, 0x47]),
            filename: "phase53.png",
            mimeType: "image/png"
        )
        await model.createServerEmoji()
        let created = try XCTUnwrap(
            model.snapshot.emojisByID.values.first { $0.name == "phase53" }
        )

        try await Task.sleep(for: .milliseconds(20))
        guard case let .loaded(presentation) = model.serverSettingsPresentationState else {
            return XCTFail("Expected prepared server settings")
        }
        XCTAssertTrue(presentation.emojiItems.contains { $0.id == created.id })

        await model.refreshServerEmojis()
        XCTAssertNotNil(model.snapshot.emojisByID[created.id])

        model.requestDeleteServerEmoji(created.id)
        XCTAssertEqual(model.pendingServerEmojiDeletion?.id, created.id)
        await model.confirmDeleteServerEmoji()
        XCTAssertNil(model.snapshot.emojisByID[created.id])
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
    func testPhase25ServerSettingsCategoriesRolesAndCommandsUseMockAPI() async throws {
        var snapshot = MockShellData.snapshot
        let seedServer = snapshot.serversByID.values.first { $0.name == "Bagel Lab" }!
        snapshot.serversByID[seedServer.id]?.defaultPermissions.insert(.manageRole)
        let model = MainShellViewModel(snapshot: snapshot, runtimeMode: .mock, communityAPIClient: MockStoatAPIClient())
        let server = model.servers.first { $0.name == "Bagel Lab" }!

        model.selectServer(server.id)
        model.openServerOverview()
        try await Task.sleep(for: .milliseconds(20))

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

        model.mutateSnapshotForTesting {
            $0.serversByID[server.id]?.defaultPermissions.insert(.manageRole)
        }
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
        model.replaceSnapshotForTesting(snapshot)
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
        model.replaceSnapshotForTesting(
            snapshot,
            changes: RealtimeSnapshotChangeSet(messageChannelIDs: [channelID])
        )

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
        let matrix = Phase30ParityMatrixBuilder.build()
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
        model.replaceSnapshotForTesting(RealtimeSnapshot())
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
    func testPhase37MemberOrderingHighestRoleColorAndDMIsolation() async throws {
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
            adminID: Role(id: adminID, name: "Admins", permissions: PermissionOverride(allow: [.manageServer]), colour: "#FF3366", hoist: true, rank: 0),
            managerID: Role(id: managerID, name: "Managers", permissions: PermissionOverride(allow: [.manageRole]), colour: "#3366FF", hoist: true, rank: 5),
            ordinaryID: Role(id: ordinaryID, name: "Members", permissions: PermissionOverride(), colour: "#00AA44", rank: 50)
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

        await model.prepareMemberListGroups(for: serverID)
        let groups = model.cachedMemberListGroups(for: serverID)
        XCTAssertEqual(groups.map(\.id), ["role-\(adminID.rawValue)", "role-\(managerID.rawValue)", "online", "unknown"])
        XCTAssertEqual(groups.first?.items.map(\.userID), [userAdmin])
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
        // Phase 58 flips CODE_SIGNING_ALLOWED to YES (ad-hoc) in project.pbxproj.
        XCTAssertTrue(model.notificationBuildReadinessDiagnostics.codeSigningAllowed.contains("YES"))
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

        await model.prepareMemberListGroups(for: serverID)
        await model.prepareMemberListGroups(for: serverID)
        model.updateTimelineVisibility(messageID: "01J00000000000000000370001", channelID: channelID, isVisible: true)
        _ = MarkdownContentPreparer.prepare("hello **markdown**")
        _ = MarkdownContentPreparer.prepare("hello **markdown**")
        for index in 0..<32 {
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

    @MainActor
    func testPhase47EmbedDisplayItemsUseModeledMediaAndImageResourceQueue() async throws {
        let data = Data("embed-image".utf8)
        let loader = MockImageResourceLoader(result: .success(data))
        let serverID: ServerID = "phase47-embed-server"
        let channelID: ChannelID = "phase47-embed-channel"
        let file = File(id: "phase47-embed-media", tag: "attachments", filename: "embed.png", metadata: .image(width: 64, height: 64, thumbhash: nil, animated: false), contentType: "image/png", size: 512)
        let message = Message(
            id: "01J00000000000000000470001",
            channelID: channelID,
            authorID: MockShellData.currentUserID,
            embeds: [Embed(kind: .image, title: "Modeled image", media: file)]
        )
        let channel = Channel(id: channelID, kind: .textChannel, serverID: serverID, name: "embeds")
        let server = Server(id: serverID, ownerID: MockShellData.currentUserID, name: "Embeds", channelIDs: [channelID])
        let snapshot = RealtimeSnapshot(serversByID: [serverID: server], channelsByID: [channelID: channel], messagesByChannelID: [channelID: [message]])
        let model = MainShellViewModel(selection: ShellSelection(space: .server(serverID), serverID: serverID, channelID: channelID), snapshot: snapshot, runtimeMode: .mock, imageResourceLoader: loader)

        var items = model.embedDisplayItems(for: message)
        XCTAssertEqual(items.first?.title, "Modeled image")
        XCTAssertEqual(items.first?.mediaItem?.displayName, "embed.png")
        XCTAssertNil(items.first?.mediaPreviewData)

        model.loadModeledEmbedMediaPreviews(for: message)
        try await Task.sleep(for: .milliseconds(50))

        let callCount = await loader.callCount()
        XCTAssertEqual(callCount, 1)
        items = model.embedDisplayItems(for: message)
        XCTAssertEqual(items.first?.mediaPreviewData, data)
        XCTAssertEqual(items.first?.mediaItem?.previewState, .readyRemote)

        let media = try XCTUnwrap(items.first?.mediaItem)
        await model.previewEmbedMedia(media)
        XCTAssertEqual(model.attachmentPreview?.data, data)
    }

    func testPhase47EmbedOnlySummaryUsesSafeEmbedText() {
        let channelID: ChannelID = "phase47-summary-channel"
        let website = Message(
            id: "01J00000000000000000470002",
            channelID: channelID,
            authorID: MockShellData.currentUserID,
            embeds: [Embed(kind: .website, url: "https://example.com/private?token=secret", title: "<b>Launch notes</b>", siteName: "Example")]
        )

        XCTAssertEqual(Phase44SafeSummary.messageSummary(for: website), "Launch notes")

        let file = File(id: "phase47-summary-image", tag: "attachments", filename: "image.png", metadata: .image(width: 20, height: 20, thumbhash: nil, animated: false), contentType: "image/png", size: 64)
        let imageOnly = Message(
            id: "01J00000000000000000470003",
            channelID: channelID,
            authorID: MockShellData.currentUserID,
            embeds: [Embed(kind: .image, media: file)]
        )

        XCTAssertEqual(Phase44SafeSummary.messageSummary(for: imageOnly), "Image embed")
    }

    // MARK: - Phase 25 CategoryEditorForm reorder tests

    func testCategoryEditorFormMoveCategoriesChangesOrder() {
        let server = MockShellData.snapshot.serversByID.values.first { $0.name == "Bagel Lab" }!
        var form = CategoryEditorForm(server: server)
        XCTAssertEqual(form.categories.map(\.id), ["cat-text", "cat-voice"])

        form.moveCategories(fromOffsets: IndexSet(integer: 0), toOffset: 2)
        XCTAssertEqual(form.categories.map(\.id), ["cat-voice", "cat-text"])
    }

    func testCategoryEditorFormMoveCategoriesNoOpLeavesUnchanged() {
        let server = MockShellData.snapshot.serversByID.values.first { $0.name == "Bagel Lab" }!
        var form = CategoryEditorForm(server: server)
        let original = form.categories.map(\.id)

        form.moveCategories(fromOffsets: IndexSet(integer: 0), toOffset: 1)
        XCTAssertEqual(form.categories.map(\.id), original)
    }

    func testCategoryEditorFormMoveChannelsChangesOrderWithinCategory() {
        let server = MockShellData.snapshot.serversByID.values.first { $0.name == "Bagel Lab" }!
        var form = CategoryEditorForm(server: server)
        let general: ChannelID = "01HX0000000000000000000101"
        let api: ChannelID = "01HX0000000000000000000102"
        let native: ChannelID = "01HX0000000000000000000103"
        XCTAssertEqual(form.categories.first(where: { $0.id == "cat-text" })?.channels, [general, api, native])

        form.moveChannels(inCategory: "cat-text", fromOffsets: IndexSet(integer: 0), toOffset: 3)
        XCTAssertEqual(form.categories.first(where: { $0.id == "cat-text" })?.channels, [api, native, general])
    }

    func testCategoryEditorFormMoveChannelsNoOpLeavesUnchanged() {
        let server = MockShellData.snapshot.serversByID.values.first { $0.name == "Bagel Lab" }!
        var form = CategoryEditorForm(server: server)
        let general: ChannelID = "01HX0000000000000000000101"
        let api: ChannelID = "01HX0000000000000000000102"
        let native: ChannelID = "01HX0000000000000000000103"

        form.moveChannels(inCategory: "cat-text", fromOffsets: IndexSet(integer: 0), toOffset: 1)
        XCTAssertEqual(form.categories.first(where: { $0.id == "cat-text" })?.channels, [general, api, native])
    }

    func testCategoryEditorFormMoveChannelsUnknownCategoryIsNoop() {
        let server = MockShellData.snapshot.serversByID.values.first { $0.name == "Bagel Lab" }!
        var form = CategoryEditorForm(server: server)
        let before = form

        form.moveChannels(inCategory: "nonexistent", fromOffsets: IndexSet(integer: 0), toOffset: 2)
        XCTAssertEqual(form, before)
    }

    // MARK: - openNewDirectMessage command tests

    @MainActor
    func testOpenNewDirectMessageCanPerformInMockMode() {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot)
        XCTAssertTrue(model.canPerform(.openNewDirectMessage))
    }

    @MainActor
    func testOpenNewDirectMessagePerformSetsPresentationFlag() {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot)
        XCTAssertFalse(model.isPresentingNewDirectMessage)

        model.perform(.openNewDirectMessage)

        XCTAssertTrue(model.isPresentingNewDirectMessage)
    }

    @MainActor
    func testOpenNewDirectMessageResetsSearchBeforePresenting() {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot)
        model.newDirectMessageSearch = "old query"

        model.openNewDirectMessage()

        XCTAssertEqual(model.newDirectMessageSearch, "")
        XCTAssertTrue(model.isPresentingNewDirectMessage)
    }

    @MainActor
    func testNewDirectMessageCandidatesEmptyForNonMatchingSearch() {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot)
        model.newDirectMessageSearch = "zzznonexistentxxx"
        XCTAssertTrue(model.newDirectMessageCandidates.isEmpty)
    }

    func testPhase60FlattensTwoHundredFiftyGroupedMessagesIntoStableDirectItems() {
        let channelID: ChannelID = "phase60-flat-channel"
        let authorID: UserID = "phase60-flat-author"
        let timeline = (0..<250).map { index in
            TimelineMessage(
                message: Message(
                    id: MessageID(rawValue: String(format: "01K%023d", index)),
                    channelID: channelID,
                    authorID: authorID,
                    content: "Message \(index)"
                )
            )
        }

        let groups = TimelineMessageGrouping.group(timeline)
        let items = TimelineRenderItemBuilder.flatten(groups)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(items.count, 250)
        XCTAssertEqual(items.map(\.id), timeline.map(\.message.id))
        XCTAssertTrue(items[0].showsHeader)
        XCTAssertTrue(items[0].startsGroup)
        XCTAssertTrue(items.dropFirst().allSatisfy { !$0.showsHeader && !$0.startsGroup })
        XCTAssertEqual(Set(items.map(\.id)).count, 250)
    }

    func testPhase62OptimisticSendKeepsItsAvatarGroupAfterConfirmation() {
        let channelID: ChannelID = "phase62-avatar-channel"
        let authorID: UserID = "phase62-avatar-author"
        let nowMilliseconds = UInt64(Date().timeIntervalSince1970 * 1_000)
        let prior = TimelineMessage(
            message: Message(
                id: MessageID(rawValue: ulid(milliseconds: nowMilliseconds - 1_000)),
                channelID: channelID,
                authorID: authorID,
                content: "Earlier local message"
            ),
            status: .confirmed
        )
        let pending = TimelineMessage(
            message: Message(
                id: "pending-phase62-avatar",
                channelID: channelID,
                authorID: authorID,
                content: "Optimistic local message",
                nonce: "phase62-avatar-nonce"
            ),
            status: .pending
        )
        let confirmed = TimelineMessage(
            message: Message(
                id: MessageID(rawValue: ulid(milliseconds: nowMilliseconds)),
                channelID: channelID,
                authorID: authorID,
                content: "Optimistic local message",
                nonce: "phase62-avatar-nonce"
            ),
            status: .confirmed
        )

        let pendingItems = TimelineRenderItemBuilder.flatten(TimelineMessageGrouping.group([prior, pending]))
        let confirmedItems = TimelineRenderItemBuilder.flatten(TimelineMessageGrouping.group([prior, confirmed]))

        XCTAssertEqual(pendingItems.map(\.showsHeader), [true, false])
        XCTAssertEqual(confirmedItems.map(\.showsHeader), [true, false])
    }

    func testPhase60PreparationPlannerBoundsStartupAndPromotesVisibleLookahead() {
        let channelID: ChannelID = "phase60-plan-channel"
        let authorID: UserID = "phase60-plan-author"
        let items = (0..<250).map { index in
            TimelineRenderItem(
                timelineMessage: TimelineMessage(
                    message: Message(
                        id: MessageID(rawValue: String(format: "01L%023d", index)),
                        channelID: channelID,
                        authorID: authorID,
                        content: "\(index)"
                    )
                ),
                groupID: "group",
                authorID: authorID,
                showsHeader: index == 0,
                startsGroup: index == 0
            )
        }

        let newest = TimelineRowPreparationPlanner.startupTargets(items: items, anchorMessageID: nil)
        XCTAssertEqual(newest.count, 32)
        XCTAssertEqual(newest.first?.messageID, items[218].id)
        XCTAssertEqual(newest.last?.messageID, items[249].id)

        let anchored = TimelineRowPreparationPlanner.startupTargets(
            items: items,
            anchorMessageID: items[100].id
        )
        XCTAssertEqual(anchored.count, 32)
        XCTAssertTrue(anchored.map(\.messageID).contains(items[100].id))

        let promoted = TimelineRowPreparationPlanner.visibleTargets(
            items: items,
            visibleMessageIDs: [items[100].id, items[101].id]
        )
        XCTAssertEqual(promoted.prefix(2).map(\.priority), [.visible, .visible])
        XCTAssertEqual(promoted.filter { $0.priority == .lookahead }.count, 16)
        XCTAssertEqual(Set(promoted.map(\.messageID)).count, promoted.count)
        XCTAssertTrue(promoted.map(\.messageID).contains(items[92].id))
        XCTAssertTrue(promoted.map(\.messageID).contains(items[109].id))

        var reacted = items[100].timelineMessage
        let originalRevision = TimelineRowRevision.value(for: reacted)
        reacted.message.reactions["🥯"] = [authorID]
        XCTAssertEqual(TimelineRowRevision.value(for: reacted), originalRevision)
    }

    @MainActor
    func testPhase60PreparationIsBoundedAndPublishesOnlyRequestedRowStates() async {
        let channelID: ChannelID = "phase60-state-channel"
        let authorID: UserID = "phase60-state-author"
        let messages = (0..<250).map { index in
            Message(
                id: MessageID(rawValue: String(format: "01M%023d", index)),
                channelID: channelID,
                authorID: authorID,
                content: "Message \(index)"
            )
        }
        let snapshot = RealtimeSnapshot(
            usersByID: [authorID: User(id: authorID, username: "author")],
            channelsByID: [
                channelID: Channel(id: channelID, kind: .directMessage, recipients: [authorID])
            ],
            messagesByChannelID: [channelID: messages]
        )
        let model = MainShellViewModel(
            selection: ShellSelection(space: .directMessages, dmChannelID: channelID),
            snapshot: snapshot
        )

        await model.prepareSelectedTimelinePresentation()

        XCTAssertEqual(model.selectedTimelineRenderItems.count, 250)
        XCTAssertEqual(model.phase60Diagnostics.rowCompletionCount, 32)
        XCTAssertLessThanOrEqual(model.phase60Diagnostics.maximumQueueDepth, 32)
        XCTAssertNil(model.timelineRowPresentation(for: messages[0].id))
        XCTAssertNotNil(model.timelineRowPresentation(for: messages[249].id))
        let firstState = model.timelineRowPresentationState(for: messages[0].id)
        let newestState = model.timelineRowPresentationState(for: messages[249].id)
        XCTAssertNotNil(firstState)
        XCTAssertNotNil(newestState)
        XCTAssertFalse(firstState === newestState)
    }

    @MainActor
    func testPhase60VisibleRangeBurstCoalescesAndChannelSwitchCancelsStaleFlush() async throws {
        let firstChannelID: ChannelID = "phase60-visible-first"
        let secondChannelID: ChannelID = "phase60-visible-second"
        let authorID: UserID = "phase60-visible-author"
        let firstMessage = Message(
            id: "01N00000000000000000000001",
            channelID: firstChannelID,
            authorID: authorID,
            content: "first"
        )
        let secondMessage = Message(
            id: "01N00000000000000000000002",
            channelID: secondChannelID,
            authorID: authorID,
            content: "second"
        )
        let snapshot = RealtimeSnapshot(
            usersByID: [authorID: User(id: authorID, username: "author")],
            channelsByID: [
                firstChannelID: Channel(id: firstChannelID, kind: .directMessage, recipients: [authorID]),
                secondChannelID: Channel(id: secondChannelID, kind: .directMessage, recipients: [authorID])
            ],
            messagesByChannelID: [
                firstChannelID: [firstMessage],
                secondChannelID: [secondMessage]
            ]
        )
        let model = MainShellViewModel(
            selection: ShellSelection(space: .directMessages, dmChannelID: firstChannelID),
            snapshot: snapshot
        )
        await model.prepareSelectedTimelinePresentation()

        for _ in 0..<200 {
            model.updateTimelineVisibility(
                messageID: firstMessage.id,
                channelID: firstChannelID,
                isVisible: true
            )
            model.updateTimelineVisibility(
                messageID: firstMessage.id,
                channelID: firstChannelID,
                isVisible: false
            )
        }
        model.updateTimelineVisibility(
            messageID: firstMessage.id,
            channelID: firstChannelID,
            isVisible: true
        )
        try await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(model.phase60Diagnostics.visibilityEventCount, 401)
        XCTAssertEqual(model.phase60Diagnostics.coalescedViewportFlushCount, 1)
        XCTAssertTrue(
            model.timelineViewport.visibleRange?.visibleMessageIDs.contains(firstMessage.id) == true
        )

        model.updateTimelineVisibility(
            messageID: firstMessage.id,
            channelID: firstChannelID,
            isVisible: false
        )
        model.selectChannel(secondChannelID)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(model.phase60Diagnostics.coalescedViewportFlushCount, 1)
    }

    func testPhase61SendConfirmedAndLaterSnapshotBackfillOmittedNonceUserMember() {
        let channelID: ChannelID = "phase61-identity-channel"
        let userID: UserID = "phase61-identity-user"
        let user = User(id: userID, username: "phase61-identity-author")
        let member = ServerMember(id: MemberCompositeKey(serverID: "phase61-identity-server", userID: userID), joinedAt: Date())
        let reducer = ChannelMessageHistoryReducer(messageCapPerChannel: 10)
        var history = ChannelMessageHistory(channelID: channelID)

        let pending = TimelineMessage(
            message: Message(id: "pending-phase61-nonce", channelID: channelID, authorID: userID, content: "hi", nonce: "phase61-nonce", user: user, member: member),
            status: .pending
        )
        history = reducer.reduce(history, event: .optimisticSendCreated(pending))

        // The server's create response omits nonce/user/member entirely.
        let confirmedID = MessageID(rawValue: ulid(milliseconds: 61_000))
        let confirmedFromServer = Message(id: confirmedID, channelID: channelID, authorID: userID, content: "hi")
        history = reducer.reduce(history, event: .sendConfirmed(message: confirmedFromServer, nonce: "phase61-nonce"))

        let confirmedRow = history.messages.first { $0.message.id == confirmedID }
        XCTAssertEqual(confirmedRow?.message.nonce, "phase61-nonce")
        XCTAssertEqual(confirmedRow?.message.user?.id, userID)
        XCTAssertEqual(confirmedRow?.message.member?.id, member.id)

        // A later realtime echo / snapshot refresh of the same now-confirmed message also omits
        // nonce/user/member -- it must not blank out identity that's already been established.
        let laterEcho = Message(id: confirmedID, channelID: channelID, authorID: userID, content: "hi (edited elsewhere)")
        history = reducer.reduce(history, event: .realtimeMessageReceived(laterEcho))

        let echoedRow = history.messages.first { $0.message.id == confirmedID }
        XCTAssertEqual(echoedRow?.message.nonce, "phase61-nonce")
        XCTAssertEqual(echoedRow?.message.user?.id, userID)
        XCTAssertEqual(echoedRow?.message.member?.id, member.id)
        XCTAssertEqual(echoedRow?.message.content, "hi (edited elsewhere)")

        // A foreign user's message is never backfilled from an unrelated locally-sent nonce.
        let foreignID = MessageID(rawValue: ulid(milliseconds: 62_000))
        let foreign = Message(id: foreignID, channelID: channelID, authorID: "phase61-identity-other-user", content: "hey")
        history = reducer.reduce(history, event: .realtimeMessageReceived(foreign))
        XCTAssertNil(history.messages.first { $0.message.id == foreignID }?.message.user)
    }

    @MainActor
    func testPhase62ComposerPasteDiagnosticsAreCategoricalAndSurfaceUnsupportedPayload() {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot)
        model.recordComposerPasteDiagnostic(
            ComposerPasteDiagnostic(source: .keyEquivalent, outcome: .unsupported, providerCount: 1)
        )

        let diagnostics = model.attachmentDiagnostics()
        XCTAssertEqual(diagnostics.lastAttachmentAction, "Composer paste Key equivalent: unknown, unsupported, providers 1, items 0")
        XCTAssertEqual(model.composerError, "Clipboard media could not be read as an attachment.")
        XCTAssertFalse(diagnostics.lastAttachmentAction?.contains("/") == true)
        XCTAssertFalse(diagnostics.lastAttachmentAction?.contains("public.") == true)
    }

    @MainActor
    func testPhase62ComposerPasteDiagnosticMarksValidationLimitAsRejected() {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot)
        let channelID = model.snapshot.channelsByID.values.first { $0.displayName == "general" }!.id

        model.addPastedImageDataFromClipboard(
            Data(repeating: 1, count: AttachmentUploadLimits.maxFileBytes + 1),
            to: channelID
        )
        model.recordComposerPasteDiagnostic(
            ComposerPasteDiagnostic(
                source: .keyEquivalent,
                outcome: .queued,
                mediaCategory: .image,
                providerCount: 1,
                itemCount: 1
            )
        )

        XCTAssertEqual(
            model.attachmentDiagnostics().lastAttachmentAction,
            "Composer paste Key equivalent: image, rejected, providers 1, items 1"
        )
        XCTAssertEqual(model.composerError, "File too large. Liquid Bagel currently supports files up to 20 MB.")
    }

    func testPhase61RenderIdentityStaysStableAcrossPendingToConfirmedForLocalSend() {
        let channelID: ChannelID = "phase61-render-channel"
        let userID: UserID = "phase61-render-user"

        let pendingItem = TimelineRenderItem(
            timelineMessage: TimelineMessage(
                message: Message(id: "pending-phase61-render-nonce", channelID: channelID, authorID: userID, content: "hi", nonce: "phase61-render-nonce"),
                status: .pending
            ),
            groupID: "group",
            authorID: userID,
            showsHeader: true,
            startsGroup: true,
            currentUserID: userID
        )
        let confirmedItem = TimelineRenderItem(
            timelineMessage: TimelineMessage(
                message: Message(id: MessageID(rawValue: ulid(milliseconds: 63_000)), channelID: channelID, authorID: userID, content: "hi", nonce: "phase61-render-nonce"),
                status: .confirmed
            ),
            groupID: "group",
            authorID: userID,
            showsHeader: true,
            startsGroup: true,
            currentUserID: userID
        )

        XCTAssertNotEqual(pendingItem.id, confirmedItem.id)
        XCTAssertEqual(pendingItem.renderIdentity, confirmedItem.renderIdentity)

        // A foreign author's message never gets a nonce-derived identity, even if -- implausibly
        // -- it carried a matching nonce; only the sender's own row is stabilized.
        let foreignItem = TimelineRenderItem(
            timelineMessage: TimelineMessage(
                message: Message(id: MessageID(rawValue: ulid(milliseconds: 64_000)), channelID: channelID, authorID: "phase61-render-other-user", content: "hi", nonce: "phase61-render-nonce"),
                status: .confirmed
            ),
            groupID: "group",
            authorID: "phase61-render-other-user",
            showsHeader: true,
            startsGroup: true,
            currentUserID: userID
        )
        XCTAssertEqual(foreignItem.renderIdentity, foreignItem.id.rawValue)
        XCTAssertNotEqual(foreignItem.renderIdentity, confirmedItem.renderIdentity)
    }

    func testPhase63RenderItemEqualityAndHashingSurviveBoxedPayload() {
        let channelID: ChannelID = "phase63-box-channel"
        let userID: UserID = "phase63-box-user"
        func makeItem(content: String, showsHeader: Bool = true) -> TimelineRenderItem {
            TimelineRenderItem(
                timelineMessage: TimelineMessage(
                    message: Message(id: "phase63-box-message", channelID: channelID, authorID: userID, content: content),
                    status: .confirmed
                ),
                groupID: "phase63-box-group",
                authorID: userID,
                showsHeader: showsHeader,
                startsGroup: true,
                currentUserID: userID
            )
        }

        let item = makeItem(content: "hello")
        let sameValueDistinctInstance = makeItem(content: "hello")
        let editedContent = makeItem(content: "hello, edited")
        let differentFlags = makeItem(content: "hello", showsHeader: false)

        // The boxed payload keeps deep value semantics: separately constructed but identical
        // items compare equal (and hash together), while content or flag changes still register.
        XCTAssertEqual(item, sameValueDistinctInstance)
        XCTAssertEqual(item.hashValue, sameValueDistinctInstance.hashValue)
        XCTAssertNotEqual(item, editedContent)
        XCTAssertNotEqual(item, differentFlags)

        // A copied struct shares its payload -- the identity fast path -- and stays equal.
        let copied = item
        XCTAssertEqual(copied, item)
        XCTAssertEqual(Set([item, sameValueDistinctInstance, copied]).count, 1)

        // Forwarded accessors expose the same values the memberwise struct did.
        XCTAssertEqual(item.id, "phase63-box-message")
        XCTAssertEqual(item.groupID, "phase63-box-group")
        XCTAssertEqual(item.authorID, userID)
        XCTAssertTrue(item.showsHeader)
        XCTAssertTrue(item.startsGroup)
        XCTAssertEqual(item.renderIdentity, item.id.rawValue)
    }

    func testPhase62ScrollTargetResolverUsesRenderedIdentityForOptimisticRows() {
        let channelID: ChannelID = "phase62-scroll-channel"
        let currentUserID: UserID = "phase62-scroll-user"
        let optimistic = TimelineRenderItem(
            timelineMessage: TimelineMessage(
                message: Message(
                    id: "phase62-server-message-id",
                    channelID: channelID,
                    authorID: currentUserID,
                    content: "sent",
                    nonce: "phase62-local-nonce"
                ),
                status: .pending
            ),
            groupID: "phase62-scroll-group",
            authorID: currentUserID,
            showsHeader: true,
            startsGroup: true,
            currentUserID: currentUserID
        )
        let absentID: MessageID = "phase62-absent"

        XCTAssertEqual(optimistic.renderIdentity, "local-send-phase62-local-nonce")
        XCTAssertEqual(
            TimelineScrollTargetResolver.resolve(target: optimistic.id, renderItems: [optimistic]),
            optimistic.renderIdentity
        )
        XCTAssertEqual(
            TimelineScrollTargetResolver.resolve(target: absentID, renderItems: [optimistic]),
            absentID.rawValue
        )
    }

    @MainActor
    func testPhase62CurrentUserPresentationFillsPartialSnapshotIdentityFromReadyUser() {
        let userID: UserID = "phase62-rail-user"
        let avatar = File(
            id: "phase62-rail-avatar",
            tag: "avatars",
            filename: "avatar.png",
            contentType: "image/png",
            size: 1,
            userID: userID
        )
        let readyUser = User(
            id: userID,
            username: "ready-user",
            displayName: "Ready display",
            avatar: avatar,
            status: UserStatus(text: nil, presence: .online)
        )
        var snapshot = RealtimeSnapshot()
        snapshot.usersByID[userID] = User(
            id: userID,
            username: "gateway-user",
            status: UserStatus(text: "Busy", presence: .idle)
        )
        let model = MainShellViewModel(snapshot: snapshot, currentUser: readyUser)

        XCTAssertEqual(model.currentUserForPresentation?.avatar?.id, avatar.id)
        XCTAssertEqual(model.currentUserForPresentation?.displayName, "Ready display")
        XCTAssertEqual(model.currentUserForPresentation?.status?.text, "Busy")
        XCTAssertEqual(model.currentUserForPresentation?.status?.presence, .idle)
    }

    @MainActor
    func testPhase61VisibilityTrackingMigratesToConfirmedIDWithoutRetriggeringAvatarResource() async throws {
        let handler = DelayedMessageActionHandler(delay: .milliseconds(80))
        let model = MainShellViewModel(snapshot: MockShellData.snapshot, messageActionHandler: handler)
        let server = try XCTUnwrap(model.servers.first { $0.name == "Bagel Lab" })
        model.selectServer(server.id)
        let channelID = try XCTUnwrap(model.selection.channelID)
        model.updateDraft("phase61 visibility migration", for: channelID)

        let sendTask = Task { await model.sendDraft(for: channelID) }
        try await Task.sleep(for: .milliseconds(10))

        await model.prepareSelectedTimelinePresentation()
        let pendingItem = try XCTUnwrap(model.selectedTimelineRenderItems.first { $0.timelineMessage.message.content == "phase61 visibility migration" })
        XCTAssertEqual(pendingItem.timelineMessage.status, .pending)
        let stableRenderIdentity = pendingItem.renderIdentity
        model.updateTimelineVisibility(messageID: pendingItem.id, channelID: channelID, isVisible: true)

        await sendTask.value
        await model.prepareSelectedTimelinePresentation()

        let confirmedItem = try XCTUnwrap(model.selectedTimelineRenderItems.first { $0.timelineMessage.message.content == "phase61 visibility migration" })
        XCTAssertEqual(confirmedItem.timelineMessage.status, .confirmed)
        XCTAssertNotEqual(confirmedItem.id, pendingItem.id)
        XCTAssertEqual(confirmedItem.renderIdentity, stableRenderIdentity)

        // Visibility tracking moved to the confirmed id directly (not through a fresh
        // onAppear/onDisappear pair), so toggling it off now registers as a real change instead
        // of being silently ignored because the tracked id was still the stale pending one.
        let eventCountBeforeToggle = model.phase60Diagnostics.visibilityEventCount
        model.updateTimelineVisibility(messageID: confirmedItem.id, channelID: channelID, isVisible: false)
        XCTAssertGreaterThan(model.phase60Diagnostics.visibilityEventCount, eventCountBeforeToggle)
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

    // MARK: - Phase 58 Notification Signature Detection

    func testPhase58SignatureStatusDetectionReportsSignedBuild() {
        XCTAssertEqual(
            NotificationSignatureChecker.detectedSignatureStatus(
                bundleURL: URL(fileURLWithPath: "/nonexistent/does-not-exist.app"),
                overrideAsSigned: true
            ),
            "user marked signed build",
            "the manual override must short-circuit before any real signature check runs"
        )
    }

    func testPhase58SignatureStatusDetectionReportsInvalidForNonexistentPath() {
        let status = NotificationSignatureChecker.detectedSignatureStatus(
            bundleURL: URL(fileURLWithPath: "/nonexistent/does-not-exist.app"),
            overrideAsSigned: false
        )
        XCTAssertNotEqual(status, "signed and valid")
        XCTAssertTrue(status.contains("unsigned") || status.contains("invalid"), "expected an error/invalid classification, got \(status)")
    }

    @MainActor
    func testPhase70SignatureReadinessIsLazyCoalescedAndCached() async throws {
        let counter = LockedInvocationCounter()
        let model = MainShellViewModel(notificationSignatureStatusPreparer: { _ in
            counter.increment()
            try? await Task.sleep(for: .milliseconds(40))
            return "signed and valid"
        })

        _ = model.notificationBuildReadinessDiagnostics
        _ = model.notificationBuildReadinessDiagnostics
        XCTAssertEqual(counter.value, 0)
        XCTAssertEqual(model.notificationSignatureCheckState, .notStarted)

        model.ensureNotificationSignatureStatus()
        model.ensureNotificationSignatureStatus()
        XCTAssertEqual(model.notificationSignatureCheckState, .checking)
        model.copyVisibleIdentityDiagnostics()
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(model.notificationSignatureCheckState, .finished("signed and valid"))
        XCTAssertEqual(counter.value, 1)
        let completed = model.notificationBuildReadinessDiagnostics
        XCTAssertEqual(completed.signatureChecksStarted, 1)
        XCTAssertEqual(completed.signatureChecksCompleted, 1)
        XCTAssertEqual(completed.signatureCheckCacheHits, 1)

        model.testingSignedNotificationBuild = true
        XCTAssertEqual(model.notificationBuildReadinessDiagnostics.detectedSignatureStatus, "user marked signed build")
        model.ensureNotificationSignatureStatus()
        XCTAssertEqual(counter.value, 1)
        XCTAssertEqual(model.notificationBuildReadinessDiagnostics.signatureCheckCacheHits, 2)
    }

    func testPhase70DeveloperDiagnosticActionsHaveDistinctReadableLabels() {
        let titles = DeveloperDiagnosticsCopyAction.allCases.map(\.title)
        XCTAssertEqual(Set(titles).count, titles.count)
        XCTAssertTrue(titles.allSatisfy { $0.hasPrefix("Copy ") && $0.count > "Copy ".count })
    }

    @MainActor
    func testPhase70OfficialEmojiContentIsIdenticalWhileOptimisticAndConfirmed() async throws {
        var snapshot = MockShellData.snapshot
        let server = try XCTUnwrap(snapshot.serversByID.values.first { !$0.channelIDs.isEmpty })
        let channelID = try XCTUnwrap(server.channelIDs.first)
        let emoji = Emoji(
            id: "01J00000000000000000700001",
            parent: .server(server.id),
            creatorID: MockShellData.currentUserID,
            name: "interoperable"
        )
        snapshot.emojisByID[emoji.id] = emoji
        let handler = DelayedMessageActionHandler(delay: .milliseconds(80))
        let model = MainShellViewModel(
            selection: ShellSelection(space: .server(server.id), serverID: server.id, channelID: channelID),
            snapshot: snapshot,
            messageActionHandler: handler
        )
        let content = "before :\(emoji.id.rawValue): after"
        model.updateDraft(content, for: channelID)

        let sendTask = Task { await model.sendDraft(for: channelID) }
        try await Task.sleep(for: .milliseconds(10))
        let optimistic = try XCTUnwrap(model.selectedTimelineMessages.first { $0.message.content == content })
        XCTAssertEqual(optimistic.status, .pending)
        XCTAssertEqual(model.inlineCustomEmojiItems(for: optimistic.message).map(\.shortcode), [":\(emoji.id.rawValue):"])

        await sendTask.value
        let confirmed = try XCTUnwrap(model.selectedTimelineMessages.first { $0.message.content == content })
        XCTAssertEqual(confirmed.status, .confirmed)
        XCTAssertEqual(confirmed.message.content, optimistic.message.content)
        XCTAssertEqual(model.inlineCustomEmojiItems(for: confirmed.message).map(\.shortcode), [":\(emoji.id.rawValue):"])
    }
}

private final class LockedInvocationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int { lock.withLock { count } }

    func increment() {
        lock.withLock { count += 1 }
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
    private let hub = TestStreamHub<RealtimeSnapshotUpdate>()
    private var snapshot: RealtimeSnapshot

    init(snapshot: RealtimeSnapshot) {
        self.snapshot = snapshot
    }

    var updates: AsyncStream<RealtimeSnapshotUpdate> {
        hub.stream()
    }

    func currentSnapshot() async -> RealtimeSnapshot {
        lock.withLock { snapshot }
    }

    func yield(_ snapshot: RealtimeSnapshot) {
        lock.withLock {
            self.snapshot = snapshot
        }
        hub.yield(
            RealtimeSnapshotUpdate(
                snapshot: snapshot,
                changes: RealtimeSnapshotChangeSet(isFullReplacement: true)
            )
        )
    }
}

private final class Phase55TestClock: @unchecked Sendable {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}

private actor Phase68DiagnosticsBuildGate {
    private(set) var invocationCount = 0
    private var firstBuildContinuation: CheckedContinuation<Void, Never>?

    func prepare(_ input: Phase68VisibleIdentityDiagnosticsInput) async -> VisibleIdentityDiagnostics {
        _ = input
        invocationCount += 1
        let invocation = invocationCount
        if invocation == 1 {
            await withCheckedContinuation { continuation in
                firstBuildContinuation = continuation
            }
        }
        return VisibleIdentityDiagnostics(unresolvedVisibleUserCount: invocation)
    }

    func releaseFirstBuild() {
        firstBuildContinuation?.resume()
        firstBuildContinuation = nil
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
    private(set) var createdGroupDrafts: [GroupChannelCreateDraft] = []
    private(set) var fetchedSettingsKeys: [[String]] = []
    private(set) var setSettingsPayloads: [(values: [String: String], timestamp: Int64)] = []
    private(set) var addedGroupRecipients: [(ChannelID, UserID)] = []
    private(set) var removedGroupRecipients: [(ChannelID, UserID)] = []

    private let currentUser: User
    private var messagesByChannel: [ChannelID: [Message]]
    private var membersByServer: [ServerID: [ServerMember]]
    private var usersByServer: [ServerID: [User]]
    private var directMessages: [Channel]
    private var openDirectMessagesByUserID: [UserID: Channel]
    private var editedUsersByID: [UserID: User] = [:]
    private var profilesByUserID: [UserID: UserProfile]
    private let fetchError: (any Error & Sendable)?
    private let fetchMessagesDelayNanoseconds: UInt64
    private let directMessagesFetchError: (any Error & Sendable)?
    private let openDirectMessageError: (any Error & Sendable)?
    private let openDirectMessageDelayNanoseconds: UInt64
    private let memberFetchError: (any Error & Sendable)?
    private let memberFetchDelayNanoseconds: UInt64
    private let editUserError: (any Error & Sendable)?
    private let uploadError: (any Error & Sendable)?
    private let uploadedFileIDsByTag: [UploadTag: FileID]
    private let createGroupError: (any Error & Sendable)?
    private var syncedSettings: [String: SyncedSettingValue]
    private let settingsSyncError: (any Error & Sendable)?
    private let addGroupRecipientError: (any Error & Sendable)?
    private let removeGroupRecipientError: (any Error & Sendable)?

    init(
        currentUser: User = User(id: MockShellData.currentUserID, username: "liquidbagel"),
        messagesByChannel: [ChannelID: [Message]] = [:],
        membersByServer: [ServerID: [ServerMember]] = [:],
        usersByServer: [ServerID: [User]] = [:],
        directMessages: [Channel] = [],
        openDirectMessagesByUserID: [UserID: Channel] = [:],
        profilesByUserID: [UserID: UserProfile] = [:],
        fetchError: (any Error & Sendable)? = nil,
        fetchMessagesDelayNanoseconds: UInt64 = 0,
        directMessagesFetchError: (any Error & Sendable)? = nil,
        openDirectMessageError: (any Error & Sendable)? = nil,
        openDirectMessageDelayNanoseconds: UInt64 = 0,
        memberFetchError: (any Error & Sendable)? = nil,
        memberFetchDelayNanoseconds: UInt64 = 0,
        editUserError: (any Error & Sendable)? = nil,
        uploadError: (any Error & Sendable)? = nil,
        uploadedFileIDsByTag: [UploadTag: FileID] = [:],
        createGroupError: (any Error & Sendable)? = nil,
        syncedSettings: [String: SyncedSettingValue] = [:],
        settingsSyncError: (any Error & Sendable)? = nil,
        addGroupRecipientError: (any Error & Sendable)? = nil,
        removeGroupRecipientError: (any Error & Sendable)? = nil
    ) {
        self.currentUser = currentUser
        self.messagesByChannel = messagesByChannel
        self.membersByServer = membersByServer
        self.usersByServer = usersByServer
        self.directMessages = directMessages
        self.openDirectMessagesByUserID = openDirectMessagesByUserID
        self.profilesByUserID = profilesByUserID
        self.fetchError = fetchError
        self.fetchMessagesDelayNanoseconds = fetchMessagesDelayNanoseconds
        self.directMessagesFetchError = directMessagesFetchError
        self.openDirectMessageError = openDirectMessageError
        self.openDirectMessageDelayNanoseconds = openDirectMessageDelayNanoseconds
        self.memberFetchError = memberFetchError
        self.memberFetchDelayNanoseconds = memberFetchDelayNanoseconds
        self.editUserError = editUserError
        self.uploadError = uploadError
        self.uploadedFileIDsByTag = uploadedFileIDsByTag
        self.createGroupError = createGroupError
        self.syncedSettings = syncedSettings
        self.settingsSyncError = settingsSyncError
        self.addGroupRecipientError = addGroupRecipientError
        self.removeGroupRecipientError = removeGroupRecipientError
    }

    func overrideSyncedSetting(key: String, value: SyncedSettingValue) {
        syncedSettings[key] = value
    }

    func fetchSyncedSettings(keys: [String]) async throws -> [String: SyncedSettingValue] {
        fetchedSettingsKeys.append(keys)
        if let settingsSyncError {
            throw settingsSyncError
        }
        return syncedSettings.filter { keys.contains($0.key) }
    }

    func setSyncedSettings(_ values: [String: String], timestamp: Int64) async throws {
        setSettingsPayloads.append((values: values, timestamp: timestamp))
        if let settingsSyncError {
            throw settingsSyncError
        }
        for (key, value) in values {
            syncedSettings[key] = SyncedSettingValue(timestamp: timestamp, rawValue: value)
        }
    }

    func fetchRootConfiguration() async throws -> StoatConfig {
        throw StoatAPIError.unimplementedEndpoint("test")
    }

    func fetchCurrentUser() async throws -> User {
        fetchCurrentUserCallCount += 1
        return currentUser
    }

    func createGroupChannel(draft: GroupChannelCreateDraft) async throws -> Channel {
        createdGroupDrafts.append(draft)
        if let createGroupError {
            throw createGroupError
        }
        var recipients = [currentUser.id]
        recipients.append(contentsOf: draft.users.filter { $0 != currentUser.id })
        return Channel(
            id: ChannelID(rawValue: "recorded-group-\(createdGroupDrafts.count)"),
            kind: .group,
            name: draft.trimmedName,
            ownerID: currentUser.id,
            active: true,
            recipients: recipients
        )
    }

    func addGroupRecipient(channelID: ChannelID, userID: UserID) async throws {
        addedGroupRecipients.append((channelID, userID))
        if let addGroupRecipientError {
            throw addGroupRecipientError
        }
    }

    func removeGroupRecipient(channelID: ChannelID, userID: UserID) async throws {
        removedGroupRecipients.append((channelID, userID))
        if let removeGroupRecipientError {
            throw removeGroupRecipientError
        }
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
        if fetchMessagesDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: fetchMessagesDelayNanoseconds)
        }
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
        if fetchMessagesDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: fetchMessagesDelayNanoseconds)
        }
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

private actor DelayedMessageActionHandler: MessageActionHandling {
    let delay: Duration

    init(delay: Duration) {
        self.delay = delay
    }

    func sendMessage(channelID: ChannelID, content: String, nonce: String?, replies: [MessageReply]?, attachments: [FileID]?) async throws -> Message {
        try await Task.sleep(for: delay)
        return Message(
            id: "01J00000100000000000030000",
            channelID: channelID,
            authorID: MockShellData.currentUserID,
            content: content,
            nonce: nonce,
            replies: replies?.map(\.id)
        )
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

private actor Phase59ReactionHandler: MessageActionHandling {
    let delay: Duration
    let error: (any Error & Sendable)?
    private(set) var addCallCount = 0
    private(set) var removeCallCount = 0

    init(delay: Duration, error: (any Error & Sendable)? = nil) {
        self.delay = delay
        self.error = error
    }

    func sendMessage(channelID: ChannelID, content: String, nonce: String?, replies: [MessageReply]?, attachments: [FileID]?) async throws -> Message {
        Message(id: "phase59-send", channelID: channelID, authorID: MockShellData.currentUserID, content: content)
    }

    func editMessage(channelID: ChannelID, messageID: MessageID, content: String) async throws -> Message {
        Message(id: messageID, channelID: channelID, authorID: MockShellData.currentUserID, content: content)
    }

    func deleteMessage(channelID: ChannelID, messageID: MessageID) async throws {}

    func addReaction(channelID: ChannelID, messageID: MessageID, emoji: String) async throws {
        addCallCount += 1
        try await Task.sleep(for: delay)
        if let error { throw error }
    }

    func removeReaction(channelID: ChannelID, messageID: MessageID, emoji: String) async throws {
        removeCallCount += 1
        try await Task.sleep(for: delay)
        if let error { throw error }
    }

    func pinMessage(channelID: ChannelID, messageID: MessageID) async throws {}
    func unpinMessage(channelID: ChannelID, messageID: MessageID) async throws {}
    func beginTyping(channelID: ChannelID) async throws {}
    func endTyping(channelID: ChannelID) async throws {}
}

private final class SequencedMediaURLProtocol: URLProtocol, @unchecked Sendable {
    enum Stub {
        case response(status: Int, headers: [String: String], data: Data)
        case failure(URLError)
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var stubs: [Stub] = []
    nonisolated(unsafe) private static var recordedRequestCount = 0

    static var requestCount: Int {
        lock.withLock { recordedRequestCount }
    }

    static func configure(_ stubs: [Stub]) {
        lock.withLock {
            self.stubs = stubs
            recordedRequestCount = 0
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let stub: Stub? = Self.lock.withLock {
            Self.recordedRequestCount += 1
            return Self.stubs.isEmpty ? nil : Self.stubs.removeFirst()
        }
        guard let stub else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        switch stub {
        case let .failure(error):
            client?.urlProtocol(self, didFailWithError: error)
        case let .response(status, headers, data):
            guard let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            ) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
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

    func testPhase51ServerSettingsPresentationBuildsLargeSnapshotOnce() {
        let serverID: ServerID = "phase51-large-server"
        let currentUserID: UserID = "phase51-current"
        var roles: [RoleID: Role] = [:]
        for index in 0..<200 {
            let id = RoleID(rawValue: "phase51-role-\(index)")
            roles[id] = Role(id: id, name: "Role \(index)", permissions: PermissionOverride(), rank: Int64(index))
        }
        let channelIDs = (0..<200).map { ChannelID(rawValue: "phase51-channel-\($0)") }
        let server = Server(
            id: serverID,
            ownerID: currentUserID,
            name: "Large Phase 51",
            channelIDs: channelIDs,
            roles: roles
        )
        var users: [UserID: User] = [:]
        var members: [ServerMemberKey: ServerMember] = [:]
        for index in 0..<2_000 {
            let userID = UserID(rawValue: "phase51-user-\(index)")
            users[userID] = User(id: userID, username: "user\(index)")
            let member = ServerMember(
                id: MemberCompositeKey(serverID: serverID, userID: userID),
                joinedAt: Date(),
                roles: [RoleID(rawValue: "phase51-role-\(index % 200)")]
            )
            members[ServerMemberKey(member.id)] = member
        }
        users[currentUserID] = User(id: currentUserID, username: "current")
        members[ServerMemberKey(serverID: serverID, userID: currentUserID)] = ServerMember(
            id: MemberCompositeKey(serverID: serverID, userID: currentUserID),
            joinedAt: Date()
        )
        let channels = Dictionary(uniqueKeysWithValues: channelIDs.map {
            ($0, Channel(id: $0, kind: .textChannel, serverID: serverID, name: $0.rawValue))
        })
        let snapshot = RealtimeSnapshot(
            usersByID: users,
            serversByID: [serverID: server],
            channelsByID: channels,
            membersByServerAndUserID: members
        )

        let presentation = Phase51PresentationBuilder.serverSettings(
            revision: Phase51PresentationRevision(snapshot: 1),
            snapshot: snapshot,
            serverID: serverID,
            selectedChannelID: channelIDs.first,
            currentUserID: currentUserID,
            runtimeLine: "mock",
            capabilities: ServerManagementCapabilities(canManageServer: true, canManageChannels: true, canInvite: true, isConnectedForLiveActions: true),
            identitySnapshots: Phase43IdentitySnapshotStore(),
            normalizedMemberQuery: ""
        )

        XCTAssertEqual(presentation?.orderedRoles.count, 200)
        XCTAssertEqual(presentation?.textChannels.count, 200)
        XCTAssertEqual(presentation?.memberItems.count, 2_001)
    }

    @MainActor
    func testPhase51QuickSwitcherCapsFiveThousandIndexedChannels() async throws {
        let serverID: ServerID = "phase51-index-server"
        let channels = (0..<5_000).map { index in
            Channel(id: ChannelID(rawValue: "phase51-index-\(index)"), kind: .textChannel, serverID: serverID, name: "indexed channel \(index)")
        }
        let server = Server(id: serverID, ownerID: "owner", name: "Index", channelIDs: channels.map(\.id))
        let snapshot = RealtimeSnapshot(
            serversByID: [serverID: server],
            channelsByID: Dictionary(uniqueKeysWithValues: channels.map { ($0.id, $0) })
        )
        let switcher = QuickSwitcherViewModel(snapshot: snapshot)

        switcher.query = "indexed channel"
        try await Task.sleep(for: .milliseconds(120))

        XCTAssertEqual(switcher.results.count, 50)
        XCTAssertEqual(Set(switcher.results.map(\.id)).count, 50)
    }

    @MainActor
    func testPhase51TimelinePresentationUsesRevisionCache() async {
        let channelID: ChannelID = "phase51-timeline"
        let authorID: UserID = "phase51-author"
        let messages = (0..<250).map { index in
            Message(
                id: MessageID(rawValue: String(format: "01J%023d", index)),
                channelID: channelID,
                authorID: authorID,
                content: "Message \(index)"
            )
        }
        let channel = Channel(id: channelID, kind: .directMessage, recipients: [authorID])
        let snapshot = RealtimeSnapshot(
            usersByID: [authorID: User(id: authorID, username: "author")],
            channelsByID: [channelID: channel],
            messagesByChannelID: [channelID: messages]
        )
        let model = MainShellViewModel(
            selection: ShellSelection(space: .directMessages, dmChannelID: channelID),
            snapshot: snapshot
        )

        await model.prepareSelectedTimelinePresentation()
        let firstBuildCount = model.phase51PerformanceDiagnostics.timelineBuildCount
        await model.prepareSelectedTimelinePresentation()

        XCTAssertFalse(model.selectedTimelineMessageGroups.isEmpty)
        XCTAssertFalse(
            model.timelineRowPresentation(for: messages[249].id)?.actionItems.isEmpty ?? true
        )
        XCTAssertEqual(model.phase51PerformanceDiagnostics.timelineBuildCount, firstBuildCount)
        XCTAssertGreaterThanOrEqual(model.phase51PerformanceDiagnostics.timelineCacheHitCount, 1)
    }

    @MainActor
    func testTimelineGroupsStayVisibleAcrossMediaIdentityAndSnapshotInvalidation() async {
        let currentUserID: UserID = "timeline-current"
        let authorID: UserID = "timeline-author"
        let channelID: ChannelID = "timeline-channel"
        let message = Message(
            id: "01J00000000000000000000991",
            channelID: channelID,
            authorID: authorID,
            content: "still visible"
        )
        let channel = Channel(id: channelID, kind: .directMessage, recipients: [currentUserID, authorID])
        var snapshot = RealtimeSnapshot(
            usersByID: [
                currentUserID: User(id: currentUserID, username: "current"),
                authorID: User(id: authorID, username: "author")
            ],
            channelsByID: [channelID: channel],
            messagesByChannelID: [channelID: [message]]
        )
        let model = MainShellViewModel(
            selection: ShellSelection(space: .directMessages, dmChannelID: channelID),
            snapshot: snapshot,
            currentUser: snapshot.usersByID[currentUserID]
        )
        await model.prepareSelectedTimelinePresentation()
        XCTAssertEqual(model.selectedTimelineMessageGroups.flatMap(\.messages).map(\.message.id), [message.id])

        await model.clearImageMemoryCache()
        XCTAssertEqual(model.selectedTimelineMessageGroups.flatMap(\.messages).map(\.message.id), [message.id])

        snapshot.usersByID[authorID]?.displayName = "Updated Author"
        model.replaceSnapshotForTesting(
            snapshot,
            changes: RealtimeSnapshotChangeSet(userIDs: [authorID])
        )
        XCTAssertEqual(model.selectedTimelineMessageGroups.flatMap(\.messages).map(\.message.id), [message.id])
    }

    @MainActor
    func testSharedTimelineGroupingWorksForEveryConversationKind() async {
        let currentUserID: UserID = "timeline-route-current"
        let otherUserID: UserID = "timeline-route-other"
        let serverID: ServerID = "timeline-route-server"
        let routes: [(Channel, ShellSelection)] = [
            (
                Channel(id: "timeline-route-text", kind: .textChannel, serverID: serverID, name: "general"),
                ShellSelection(space: .server(serverID), serverID: serverID, channelID: "timeline-route-text")
            ),
            (
                Channel(id: "timeline-route-dm", kind: .directMessage, recipients: [currentUserID, otherUserID]),
                ShellSelection(space: .directMessages, dmChannelID: "timeline-route-dm")
            ),
            (
                Channel(id: "timeline-route-group", kind: .group, name: "Group", recipients: [currentUserID, otherUserID]),
                ShellSelection(space: .directMessages, dmChannelID: "timeline-route-group")
            ),
            (
                Channel(id: "timeline-route-saved", kind: .savedMessages, userID: currentUserID, recipients: [currentUserID]),
                ShellSelection(space: .directMessages, dmChannelID: "timeline-route-saved")
            )
        ]

        for (index, route) in routes.enumerated() {
            let channel = route.0
            let message = Message(
                id: MessageID(rawValue: String(format: "01J%023d", 900 + index)),
                channelID: channel.id,
                authorID: otherUserID,
                content: channel.kind.rawAPIValue
            )
            let server = Server(
                id: serverID,
                ownerID: currentUserID,
                name: "Timeline",
                channelIDs: channel.serverID == nil ? [] : [channel.id]
            )
            let snapshot = RealtimeSnapshot(
                usersByID: [
                    currentUserID: User(id: currentUserID, username: "current"),
                    otherUserID: User(id: otherUserID, username: "other")
                ],
                serversByID: channel.serverID == nil ? [:] : [serverID: server],
                channelsByID: [channel.id: channel],
                messagesByChannelID: [channel.id: [message]]
            )
            let model = MainShellViewModel(
                selection: route.1,
                snapshot: snapshot,
                currentUser: snapshot.usersByID[currentUserID]
            )

            await model.prepareSelectedTimelinePresentation()
            XCTAssertEqual(model.selectedTimelineMessageGroups.flatMap(\.messages).map(\.message.id), [message.id])
            await model.clearImageMemoryCache()
            XCTAssertEqual(model.selectedTimelineMessageGroups.flatMap(\.messages).map(\.message.id), [message.id])
        }
    }

    @MainActor
    func testTimelineChannelSwitchNeverShowsPreviousConversationGroups() async {
        let currentUserID: UserID = "timeline-switch-current"
        let firstID: ChannelID = "timeline-switch-first"
        let secondID: ChannelID = "timeline-switch-second"
        let firstMessage = Message(id: "01J00000000000000000000981", channelID: firstID, authorID: currentUserID, content: "first")
        let secondMessage = Message(id: "01J00000000000000000000982", channelID: secondID, authorID: currentUserID, content: "second")
        let snapshot = RealtimeSnapshot(
            usersByID: [currentUserID: User(id: currentUserID, username: "current")],
            channelsByID: [
                firstID: Channel(id: firstID, kind: .directMessage, recipients: [currentUserID]),
                secondID: Channel(id: secondID, kind: .directMessage, recipients: [currentUserID])
            ],
            messagesByChannelID: [firstID: [firstMessage], secondID: [secondMessage]]
        )
        let model = MainShellViewModel(
            selection: ShellSelection(space: .directMessages, dmChannelID: firstID),
            snapshot: snapshot,
            currentUser: snapshot.usersByID[currentUserID]
        )
        await model.prepareSelectedTimelinePresentation()

        model.selectChannel(secondID)
        XCTAssertEqual(model.selectedTimelineMessageGroups.flatMap(\.messages).map(\.message.id), [secondMessage.id])
        await model.prepareSelectedTimelinePresentation()
        XCTAssertEqual(model.selectedTimelineMessageGroups.flatMap(\.messages).map(\.message.id), [secondMessage.id])
    }

    @MainActor
    func testRealtimeMessageMutationDoesNotRestartCompletedHistoryFetch() async {
        let currentUserID: UserID = "timeline-fetch-current"
        let channelID: ChannelID = "timeline-fetch-channel"
        let message = Message(id: "01J00000000000000000000971", channelID: channelID, authorID: currentUserID, content: "hello")
        let channel = Channel(id: channelID, kind: .directMessage, recipients: [currentUserID])
        let snapshot = RealtimeSnapshot(
            usersByID: [currentUserID: User(id: currentUserID, username: "current")],
            channelsByID: [channelID: channel]
        )
        let api = RecordingAPIClient(messagesByChannel: [channelID: [message]])
        let controller = ChannelMessageController(
            runtimeMode: .liveManual,
            apiClient: api,
            currentUserID: currentUserID
        )
        let model = MainShellViewModel(
            selection: ShellSelection(space: .directMessages, dmChannelID: channelID),
            snapshot: snapshot,
            runtimeMode: .liveManual,
            sessionState: .connected,
            currentUser: snapshot.usersByID[currentUserID],
            messageController: controller
        )
        model.selectChannel(channelID)
        try? await Task.sleep(for: .milliseconds(30))

        var updatedSnapshot = snapshot
        var reacted = message
        reacted.reactions["bagel"] = [currentUserID]
        updatedSnapshot.messagesByChannelID[channelID] = [reacted]
        model.replaceSnapshotForTesting(
            updatedSnapshot,
            changes: RealtimeSnapshotChangeSet(messageChannelIDs: [channelID])
        )
        try? await Task.sleep(for: .milliseconds(20))

        let fetchCount = await api.fetchMessagesCallCount
        XCTAssertEqual(fetchCount, 1)
        XCTAssertEqual(model.selectedTimelineMessages.first?.message.reactions["bagel"], [currentUserID])
    }

    @MainActor
    func testRealtimeDeleteRemovesMessageFromControllerAndVisibleGroups() async {
        let currentUserID: UserID = "timeline-delete-current"
        let channelID: ChannelID = "timeline-delete-channel"
        let message = Message(id: "01J00000000000000000000961", channelID: channelID, authorID: currentUserID, content: "delete me")
        let channel = Channel(id: channelID, kind: .directMessage, recipients: [currentUserID])
        let snapshot = RealtimeSnapshot(
            usersByID: [currentUserID: User(id: currentUserID, username: "current")],
            channelsByID: [channelID: channel],
            messagesByChannelID: [channelID: [message]]
        )
        let model = MainShellViewModel(
            selection: ShellSelection(space: .directMessages, dmChannelID: channelID),
            snapshot: snapshot,
            currentUser: snapshot.usersByID[currentUserID]
        )
        await model.prepareSelectedTimelinePresentation()

        var deletedSnapshot = snapshot
        deletedSnapshot.messagesByChannelID[channelID] = []
        model.replaceSnapshotForTesting(
            deletedSnapshot,
            changes: RealtimeSnapshotChangeSet(
                messageChannelIDs: [channelID],
                deletedMessageIDsByChannelID: [channelID: [message.id]]
            )
        )

        XCTAssertTrue(model.selectedTimelineMessages.isEmpty)
        XCTAssertTrue(model.selectedTimelineMessageGroups.isEmpty)
    }

    @MainActor
    func testMessageControllerClearsCachedHistoryWhenUserScopeChanges() async {
        let channelID: ChannelID = "timeline-scope-channel"
        let message = Message(id: "01J00000000000000000000951", channelID: channelID, authorID: "first-user", content: "private")
        let controller = ChannelMessageController(runtimeMode: .mock, currentUserID: "first-user")
        _ = await controller.loadInitialMessages(channelID: channelID, snapshotMessages: [message])
        XCTAssertTrue(controller.state(for: channelID).hasMessages)

        controller.configure(runtimeMode: .liveManual, apiClient: nil, currentUserID: "second-user", loadGeneration: 1)

        XCTAssertEqual(controller.state(for: channelID), .idle)
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
