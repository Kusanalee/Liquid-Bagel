//  Split from StoatFeaturesTests.swift (Phase 74). Behavior unchanged.

import StoatModels
import StoatAPI
import StoatPersistence
import StoatRealtime
import StoatUI
import Observation
import SwiftUI
import XCTest
@testable import StoatFeatures


extension StoatFeaturesTests {
    @MainActor
    func testCurrentUserExcludedFromTypingDisplayAndUnreadClearsOnSelection() {
        var snapshot = TestShellData.snapshot
        let server = snapshot.serversByID.values.first { $0.name == "Bagel Lab" }!
        let channelID = server.channelIDs[1]
        snapshot.typingUsersByChannelID[channelID, default: []].insert(TestShellData.currentUserID)
        let model = MainShellViewModel(snapshot: snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())

        model.selectChannel(channelID)

        XCTAssertFalse(model.typingUsers(for: channelID).contains { $0.id == TestShellData.currentUserID })
        XCTAssertNil(model.unread(for: channelID)?.lastMessageID)
    }

    func testSelectionRestorerRestoresPersistedServerAndChannel() throws {
        let snapshot = TestShellData.snapshot
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
        let snapshot = TestShellData.snapshot
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
            snapshot: TestShellData.snapshot,
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
            snapshot: TestShellData.snapshot,
            mode: .liveManual
        )

        XCTAssertEqual(result.selection.space, .home)
        XCTAssertNil(result.selection.channelID)
    }

    @MainActor
    func testReadyEventUpdatesHydrationStatus() async throws {
        let store = InMemoryTokenStore(credential: .sessionToken("token"))
        let ready = StoatGatewayEvent.ready(ReadyPayload(
            users: Array(TestShellData.snapshot.usersByID.values),
            servers: Array(TestShellData.snapshot.serversByID.values),
            channels: Array(TestShellData.snapshot.channelsByID.values),
            members: TestShellData.snapshot.membersByServerAndUserID.values.map { $0 },
            channelUnreads: Array(TestShellData.snapshot.unreadsByChannelID.values)
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
        XCTAssertEqual(session.hydrationStatus.serverCount, TestShellData.snapshot.serversByID.count)
        XCTAssertEqual(session.hydrationStatus.channelCount, TestShellData.snapshot.channelsByID.count)
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

        await session.loadPreferences()
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
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())
        model.refreshCurrentContext()
        XCTAssertEqual(model.placeholderStatus, "Mock data refreshed")

        let live = MainShellViewModel(runtimeMode: .liveManual, sessionState: .readyToConnect, currentUser: nil, messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())
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
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())
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
        let model = MainShellViewModel(snapshot: RealtimeSnapshot(), runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())

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
        await session.loadPreferences()
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], sessionCoordinator: session, messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())
        model.syncFromSessionCoordinator()

        model.perform(.refresh)

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
        await session.loadPreferences()
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], sessionCoordinator: session, messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())

        model.syncFromSessionCoordinator()

        XCTAssertEqual(model.messageDensity, .compact)
        XCTAssertEqual(model.liquidGlassTransparency, 0.55)
    }

    @MainActor
    func testQuickSwitcherIndexesFiltersAndActivatesLocalResults() {
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())
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
        let model = MainShellViewModel(snapshot: RealtimeSnapshot(), runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())
        model.perform(.openQuickSwitcher)
        let titles = model.quickSwitcherViewModel.results.map(\.title)

        XCTAssertTrue(titles.contains("Home"))
        XCTAssertTrue(titles.contains("Refresh"))
    }

    @MainActor
    func testNavigationHelpersMoveServersChannelsAndUnreadChannels() {
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())
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
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())
        model.selectServer(model.servers[0].id)
        model.requestFocus(.composer)

        XCTAssertFalse(model.canPerform(.selectNextChannel))
        model.perform(.selectNextChannel)
        XCTAssertTrue(model.placeholderStatus?.contains("typing") == true)
    }

    @MainActor
    func testTimelineSelectionMovesFallsBackAndCopiesContentOnly() async {
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())
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
        let handler = StubMessageActionHandler()
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: handler, communityAPIClient: StubStoatAPIClient())
        model.selectServer(model.servers[0].id)
        let channelID = model.selection.channelID!
        let ownMessage = model.selectedTimelineMessages.first { $0.message.authorID == TestShellData.currentUserID }!

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
        let handler = StubMessageActionHandler()
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: handler, communityAPIClient: StubStoatAPIClient())
        model.selectServer(model.servers[0].id)
        let ownMessage = model.selectedTimelineMessages.first { $0.message.authorID == TestShellData.currentUserID }!
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
        let handler = StubMessageActionHandler(sendError: MessageActionError.unavailable("send failed"))
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: handler, communityAPIClient: StubStoatAPIClient())
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

        model.beginEditing(model.selectedTimelineMessages.first { $0.message.authorID == TestShellData.currentUserID }!)
        XCTAssertFalse(model.canPerform(.copySelectedMessage))
    }

    @MainActor
    func testPhase9PinReactionAndJumpCommandsRouteThroughSelection() async throws {
        let handler = StubMessageActionHandler()
        var snapshot = TestShellData.snapshot
        let channelID = try XCTUnwrap(snapshot.channelsByID.values.first { $0.displayName == "general" }?.id)
        snapshot.channelsByID[channelID]?.permissions = [.viewChannel, .readMessageHistory, .sendMessage, .react, .manageMessages]
        let model = MainShellViewModel(snapshot: snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: handler, communityAPIClient: StubStoatAPIClient())
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
        XCTAssertEqual(model.selectedTimelineMessage?.message.reactions["✅"], [TestShellData.currentUserID])

        model.jumpToNewestMessage()
        XCTAssertEqual(model.timelineSelection.messageID, model.selectedTimelineMessages.last?.message.id)
    }

    @MainActor
    func testPhase9LocalUnreadStatePreservesMentionAndJumpsFirstUnread() throws {
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())
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
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())
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
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())
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
        let model = MainShellViewModel(snapshot: RealtimeSnapshot(), runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())
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
        let handler = StubMessageActionHandler()
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: handler, communityAPIClient: StubStoatAPIClient())
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
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())
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
        let channelID = try XCTUnwrap(TestShellData.snapshot.channelsByID.values.first { $0.displayName == "macos-native" }?.id)
        let sender = RecordingChannelAckSender()
        let model = MainShellViewModel(
            snapshot: TestShellData.snapshot,
            runtimeMode: .liveManual,
            sessionState: .connected,
            currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), channelAckSender: sender, communityAPIClient: StubStoatAPIClient())

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
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())
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
        let handler = StubMessageActionHandler(sendError: MessageActionError.unavailable("offline"))
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: handler, communityAPIClient: StubStoatAPIClient())
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

}
