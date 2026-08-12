import XCTest
import StoatAPI
import StoatModels
import StoatPersistence
import StoatRealtime
import StoatVoice
@testable import StoatFeatures

final class VoiceChatTests: XCTestCase {
    // MARK: - Permission gating (pure)

    func testPhase75CanJoinVoiceRequiresConnectPermission() {
        XCTAssertTrue(canJoinVoice(permissions: [.connect]))
        XCTAssertFalse(canJoinVoice(permissions: [.speak, .listen]))
        XCTAssertFalse(canJoinVoice(permissions: []))
    }

    func testPhase75CanSpeakRequiresConnectAndSpeak() {
        XCTAssertTrue(canSpeak(permissions: [.connect, .speak]))
        XCTAssertFalse(canSpeak(permissions: [.connect]))
        XCTAssertFalse(canSpeak(permissions: [.speak]))
    }

    func testPhase75CanListenRequiresConnectAndListen() {
        XCTAssertTrue(canListen(permissions: [.connect, .listen]))
        XCTAssertFalse(canListen(permissions: [.connect]))
    }

    // MARK: - Mute / deafen / push-to-talk transitions (pure)

    func testPhase75DeafenImpliesMuteAndUndeafenDoesNotAutoUnmute() {
        var state = VoiceLocalAudioState()
        state = state.settingDeafened(true)
        XCTAssertTrue(state.isMuted)
        XCTAssertTrue(state.isDeafened)
        XCTAssertFalse(state.isMicrophoneLive)

        state = state.settingDeafened(false)
        // Undeafening restores hearing but does not implicitly unmute — matches Discord's model.
        XCTAssertTrue(state.isMuted)
        XCTAssertFalse(state.isDeafened)
    }

    func testPhase75UnmutingClearsDeafen() {
        var state = VoiceLocalAudioState().settingDeafened(true)
        state = state.settingMuted(false)
        XCTAssertFalse(state.isMuted)
        XCTAssertFalse(state.isDeafened)
        XCTAssertTrue(state.isMicrophoneLive)
    }

    func testPhase75PushToTalkOverridesMuteWhileActiveButNotWhileDeafened() {
        let muted = VoiceLocalAudioState(isMuted: true).settingPushToTalkActive(true)
        XCTAssertTrue(muted.isMicrophoneLive, "Holding push-to-talk should override a persistent mute")

        let deafened = VoiceLocalAudioState(isDeafened: true).settingPushToTalkActive(true)
        XCTAssertFalse(deafened.isMicrophoneLive, "Deafened always wins — no point publishing audio nobody can hear you request to send")
    }

    func testPhase75IsVoiceActivatedComparesLevelAgainstSensitivity() {
        XCTAssertTrue(isVoiceActivated(level: 0.5, sensitivity: 0.3))
        XCTAssertFalse(isVoiceActivated(level: 0.1, sensitivity: 0.3))
        XCTAssertTrue(isVoiceActivated(level: 0.3, sensitivity: 0.3), "Boundary should activate")
    }

    // MARK: - Microphone permission manager

    func testPhase75MicrophonePermissionManagerTransitionsFromNotDeterminedToAuthorized() async {
        let manager = StubMicrophonePermissionManager(status: .notDetermined)
        let before = await manager.status()
        let result = await manager.requestAuthorization()

        XCTAssertEqual(before, .notDetermined)
        XCTAssertEqual(result.statusAfter, .authorized)
        XCTAssertEqual(result.granted, true)
        let requestCount = await manager.requestCount
        XCTAssertEqual(requestCount, 1)
    }

    // MARK: - VoiceCallUIState

    func testPhase75VoiceCallUIStateChannelIDAndActiveness() {
        let channelID: ChannelID = "voice-channel"
        XCTAssertNil(VoiceCallUIState.idle.channelID)
        XCTAssertFalse(VoiceCallUIState.idle.isActive)
        XCTAssertEqual(VoiceCallUIState.connecting(channelID).channelID, channelID)
        XCTAssertTrue(VoiceCallUIState.connected(channelID).isActive)
        XCTAssertFalse(VoiceCallUIState.failed(channelID, reason: "boom").isActive)
    }

    // MARK: - Roster (gateway-synced ServerMember.voiceChannel)

    @MainActor
    func testPhase75VoiceParticipantsFilteredFromGatewaySyncedRoster() {
        let voiceChannelID: ChannelID = "01HX0000000000000000000104"
        let otherUserID: UserID = "01HX0000000000000000000002"
        let serverID: ServerID = "01HX0000000000000000000201"

        let emptyViewModel = Self.makeViewModel()
        XCTAssertTrue(emptyViewModel.voiceParticipants(for: voiceChannelID).isEmpty)

        var snapshotWithParticipant = TestShellData.makeSnapshot()
        let key = ServerMemberKey(serverID: serverID, userID: otherUserID)
        var member = snapshotWithParticipant.membersByServerAndUserID[key]
        XCTAssertNotNil(member, "Fixture should already seed this member")
        member?.voiceChannel = voiceChannelID
        if let member {
            snapshotWithParticipant.membersByServerAndUserID[key] = member
        }
        let joinedViewModel = MainShellViewModel(
            snapshot: snapshotWithParticipant,
            runtimeMode: .mock,
            sessionState: .mock,
            currentUser: snapshotWithParticipant.usersByID[TestShellData.currentUserID],
            messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID),
            communityAPIClient: StubStoatAPIClient()
        )

        let participants = joinedViewModel.voiceParticipants(for: voiceChannelID)
        let revisionAfterFirstCall = joinedViewModel.voiceRosterRevision
        XCTAssertEqual(participants.map(\.id.userID), [otherUserID])
        XCTAssertGreaterThan(revisionAfterFirstCall, 0, "First call should have computed and bumped the revision")

        // Calling again with nothing changed must hit the fingerprint cache, not recompute.
        _ = joinedViewModel.voiceParticipants(for: voiceChannelID)
        XCTAssertEqual(joinedViewModel.voiceRosterRevision, revisionAfterFirstCall)

        // A different channel ID is a different cache key and must not reuse the cached roster.
        XCTAssertTrue(joinedViewModel.voiceParticipants(for: "some-other-channel").isEmpty)
    }

    // MARK: - Join / leave / mute / deafen (integration, via StubVoiceEngine)

    @MainActor
    func testPhase75CanJoinVoiceChannelTrueForServerOwnerFalseForNonVoiceChannel() {
        let viewModel = Self.makeViewModel()
        let voiceChannelID: ChannelID = "01HX0000000000000000000104"
        let textChannelID: ChannelID = "01HX0000000000000000000101"

        XCTAssertTrue(viewModel.canJoinVoiceChannel(voiceChannelID))
        XCTAssertFalse(viewModel.canJoinVoiceChannel(textChannelID))
    }

    @MainActor
    func testPhase76VoiceEnabledTextChannelCanJoinWithoutLosingTextShape() {
        let textChannelID: ChannelID = "01HX0000000000000000000101"
        var snapshot = TestShellData.makeSnapshot()
        snapshot.channelsByID[textChannelID]?.voice = VoiceInformation(maxUsers: 8)
        let viewModel = MainShellViewModel(
            snapshot: snapshot,
            runtimeMode: .mock,
            sessionState: .mock,
            currentUser: snapshot.usersByID[TestShellData.currentUserID],
            messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID),
            communityAPIClient: StubStoatAPIClient()
        )

        XCTAssertEqual(viewModel.snapshot.channelsByID[textChannelID]?.kind, .textChannel)
        XCTAssertTrue(viewModel.canJoinVoiceChannel(textChannelID))
        viewModel.selectChannel(textChannelID)
        XCTAssertEqual(viewModel.selectedConversationChannelID, textChannelID)
    }

    func testPhase76NodeSelectionUsesFastestSuccessAndFallsBackDeterministically() async {
        let first = VoiceNode(name: "first", lat: 0, lon: 0, publicURL: "https://first")
        let fast = VoiceNode(name: "fast", lat: 0, lon: 0, publicURL: "https://fast")
        let selected = await selectVoiceNode(nodes: [first, fast]) { node in node.name == "fast" }
        XCTAssertEqual(selected?.name, "fast")

        let fallback = await selectVoiceNode(nodes: [first, fast]) { _ in false }
        XCTAssertEqual(fallback?.name, "first")
    }

    @MainActor
    func testPhase75JoinVoiceChannelConnectsEngineAndTransitionsToConnected() async throws {
        let engine = StubVoiceEngine()
        let viewModel = Self.makeViewModel(voiceEngine: engine)
        let voiceChannelID: ChannelID = "01HX0000000000000000000104"

        viewModel.perform(.joinVoiceChannel(voiceChannelID))

        try await Self.waitUntilConnected(viewModel)

        XCTAssertEqual(viewModel.activeVoiceCall, .connected(voiceChannelID))
        XCTAssertEqual(engine.connectCallCount, 1)
        XCTAssertEqual(engine.lastConnectToken, "stub-token-\(voiceChannelID.rawValue)")
        XCTAssertEqual(engine.lastConnectURL, URL(string: "wss://voice.stub.test"))
    }

    @MainActor
    func testPhase75JoinVoiceChannelFailureSurfacesAsFailedState() async throws {
        let engine = StubVoiceEngine()
        engine.connectError = URLError(.notConnectedToInternet)
        let viewModel = Self.makeViewModel(voiceEngine: engine)
        let voiceChannelID: ChannelID = "01HX0000000000000000000104"

        viewModel.perform(.joinVoiceChannel(voiceChannelID))

        try await Self.waitUntil {
            if case .failed = viewModel.activeVoiceCall { return true }
            return false
        }

        if case let .failed(channelID, _) = viewModel.activeVoiceCall {
            XCTAssertEqual(channelID, voiceChannelID)
        } else {
            XCTFail("Expected .failed state")
        }
    }

    @MainActor
    func testPhase75LeaveVoiceCallDisconnectsEngineAndResetsState() async throws {
        let engine = StubVoiceEngine()
        let viewModel = Self.makeViewModel(voiceEngine: engine)
        let voiceChannelID: ChannelID = "01HX0000000000000000000104"

        viewModel.perform(.joinVoiceChannel(voiceChannelID))
        try await Self.waitUntilConnected(viewModel)

        viewModel.perform(.leaveVoiceCall)

        XCTAssertEqual(viewModel.activeVoiceCall, .idle)
        XCTAssertTrue(viewModel.activeVoiceCallParticipants.isEmpty)
        try await Self.waitUntil { engine.disconnectCallCount >= 1 }
    }

    @MainActor
    func testPhase75ToggleMicrophoneMutedAppliesToEngineAndIsNoOpWhenIdle() async throws {
        let engine = StubVoiceEngine()
        let viewModel = Self.makeViewModel(voiceEngine: engine)
        let voiceChannelID: ChannelID = "01HX0000000000000000000104"

        // No active call: canPerform gates it, and perform() no-ops via the disabled-reason path.
        XCTAssertFalse(viewModel.canPerform(.toggleMicrophoneMuted))
        viewModel.perform(.toggleMicrophoneMuted)
        XCTAssertFalse(viewModel.voiceLocalAudioState.isMuted)

        viewModel.perform(.joinVoiceChannel(voiceChannelID))
        try await Self.waitUntilConnected(viewModel)

        XCTAssertTrue(viewModel.canPerform(.toggleMicrophoneMuted))
        viewModel.perform(.toggleMicrophoneMuted)
        XCTAssertTrue(viewModel.voiceLocalAudioState.isMuted)
        try await Self.waitUntil { engine.microphoneMutedCalls.last == true }
    }

    @MainActor
    func testPhase75VoiceEngineParticipantAndSpeakingEventsUpdateActiveCallState() async throws {
        let engine = StubVoiceEngine()
        let viewModel = Self.makeViewModel(voiceEngine: engine)
        let voiceChannelID: ChannelID = "01HX0000000000000000000104"

        viewModel.perform(.joinVoiceChannel(voiceChannelID))
        try await Self.waitUntilConnected(viewModel)

        engine.emit(.participantConnected(VoiceParticipant(identity: "remote-1", name: "Remote User")))
        try await Self.waitUntil { viewModel.activeVoiceCallParticipants["remote-1"] != nil }
        XCTAssertEqual(viewModel.activeVoiceCallParticipants["remote-1"]?.isSpeaking, false)

        engine.emit(.speakingParticipantsChanged(identities: ["remote-1"]))
        try await Self.waitUntil { viewModel.activeVoiceCallParticipants["remote-1"]?.isSpeaking == true }

        engine.emit(.participantDisconnected(identity: "remote-1"))
        try await Self.waitUntil { viewModel.activeVoiceCallParticipants["remote-1"] == nil }
    }

    @MainActor
    func testPhase76CameraAndScreenShareCanRunTogetherAndTeardown() async throws {
        let engine = StubVoiceEngine()
        let viewModel = Self.makeViewModel(voiceEngine: engine)
        let channelID: ChannelID = "01HX0000000000000000000104"
        viewModel.joinVoiceChannel(channelID)
        try await Self.waitUntilConnected(viewModel)

        viewModel.toggleCamera()
        try await Self.waitUntil { engine.cameraEnabledCalls.last == true }
        viewModel.startScreenShare(sourceID: "display:1")
        try await Self.waitUntil { engine.screenShareEnabledCalls.last == true }

        XCTAssertTrue(viewModel.voiceMediaState.isCameraEnabled)
        XCTAssertTrue(viewModel.voiceMediaState.isScreenShareEnabled)
        viewModel.leaveVoiceCall()
        XCTAssertEqual(viewModel.voiceMediaState, VoiceMediaState())
        try await Self.waitUntil { engine.disconnectCallCount > 0 }
    }

    // MARK: - Helpers

    @MainActor
    private static func makeViewModel(voiceEngine: any VoiceEngine = StubVoiceEngine()) -> MainShellViewModel {
        let snapshot = TestShellData.makeSnapshot()
        return MainShellViewModel(
            snapshot: snapshot,
            runtimeMode: .mock,
            sessionState: .mock,
            currentUser: snapshot.usersByID[TestShellData.currentUserID],
            messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID),
            voiceEngine: voiceEngine,
            microphonePermissionManager: StubMicrophonePermissionManager(),
            cameraPermissionManager: StubMicrophonePermissionManager(),
            communityAPIClient: StubStoatAPIClient()
        )
    }

    /// `.connecting` also counts as `isActive` — waiting on `isActive` alone can observe the
    /// join mid-flight, before `engine.connect()` has even been called. Tests that need the
    /// engine to have actually connected wait on this instead.
    @MainActor
    private static func waitUntilConnected(_ viewModel: MainShellViewModel, timeout: TimeInterval = 2) async throws {
        try await waitUntil(timeout: timeout) {
            if case .connected = viewModel.activeVoiceCall { return true }
            return false
        }
    }

    /// Voice join/leave run on a detached `Task` (fire-and-forget from `perform`), so tests poll
    /// for the expected state rather than awaiting a specific async call.
    @MainActor
    private static func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Timed out waiting for condition")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
