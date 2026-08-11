//  Phase 74 -- continuous timeline pagination.
//
//  The "Load Older Messages" button used to be the only way to fetch history, which made the
//  fetch a deliberate user action. Now it happens automatically while scrolling, so these tests
//  exist to prove the automatic path cannot re-enter, cannot spin, and cannot retry a failing
//  request forever.

import StoatModels
import StoatAPI
import StoatPersistence
import StoatRealtime
import StoatUI
import XCTest
@testable import StoatFeatures

/// A message client with real pagination semantics.
///
/// The shared `RecordingAPIClient` slices `before` with `prefix`, so its very first page is the
/// *oldest* messages in the channel and there is never anything older to fetch. That is fine for
/// the call-count assertions it was written for, but automatic pagination has to be tested across
/// several real pages, so this one returns the newest page first and walks backwards -- the way
/// the Stoat `before` cursor actually behaves.
actor PagingMessageAPIClient: StoatAPIClient {
    private(set) var fetchMessagesCallCount = 0
    private(set) var requestedBeforeCursors: [MessageID?] = []

    private let messages: [Message]
    private let failAfterCallCount: Int?

    /// - Parameter failAfterCallCount: once this many fetches have succeeded, every later fetch
    ///   throws. Used to fail *pagination* while leaving the initial load intact.
    init(messages: [Message], failAfterCallCount: Int? = nil) {
        self.messages = messages.sorted { $0.id.rawValue < $1.id.rawValue }
        self.failAfterCallCount = failAfterCallCount
    }

    func fetchMessages(channelID: ChannelID, options: MessageFetchOptions) async throws -> [Message] {
        fetchMessagesCallCount += 1
        requestedBeforeCursors.append(options.before)
        if let failAfterCallCount, fetchMessagesCallCount > failAfterCallCount {
            throw MessageActionError.unavailable("boom")
        }
        let limit = max(1, options.limit ?? 50)
        var window = messages.filter { $0.channelID == channelID }
        if let before = options.before, let index = window.firstIndex(where: { $0.id == before }) {
            window = Array(window[..<index])
        }
        // The newest page within the cursor, returned in chronological order.
        return Array(window.suffix(limit))
    }

    func fetchMessages(channelID: ChannelID, before: MessageID?, after: MessageID?, limit: Int?) async throws -> [Message] {
        try await fetchMessages(
            channelID: channelID,
            options: MessageFetchOptions(before: before, after: after, limit: limit)
        )
    }

    // The protocol supplies `unimplementedEndpoint` defaults for everything else; these are the
    // handful with no default. Nothing in the pagination path calls them.
    private func unsupported() -> StoatAPIError { .unimplementedEndpoint("Pagination-only client.") }
    func fetchRootConfiguration() async throws -> StoatConfig { throw unsupported() }
    func fetchCurrentUser() async throws -> User { throw unsupported() }
    func fetchServers() async throws -> [Server] { throw unsupported() }
    func fetchChannels() async throws -> [Channel] { throw unsupported() }
    func fetchChannel(id: ChannelID) async throws -> Channel { throw unsupported() }
    func sendMessage(channelID: ChannelID, draft: MessageDraft) async throws -> Message { throw unsupported() }
    func editMessage(channelID: ChannelID, messageID: MessageID, draft: MessageEditDraft) async throws -> Message { throw unsupported() }
    func deleteMessage(channelID: ChannelID, messageID: MessageID) async throws { throw unsupported() }
    func addReaction(channelID: ChannelID, messageID: MessageID, emoji: String) async throws { throw unsupported() }
    func removeReaction(channelID: ChannelID, messageID: MessageID, emoji: String, removeAll: Bool) async throws { throw unsupported() }
    func pinMessage(channelID: ChannelID, messageID: MessageID) async throws { throw unsupported() }
    func unpinMessage(channelID: ChannelID, messageID: MessageID) async throws { throw unsupported() }
    func uploadFile(data: Data, filename: String, mimeType: String, tag: UploadTag) async throws -> UploadedFile { throw unsupported() }
}

extension StoatFeaturesTests {

    // MARK: - Pure policy

    func testPhase74PrefetchPolicyTriggersWithinDistanceAndNotBeyondIt() {
        // 150% of an 800pt viewport == begin fetching within 1200pt of the top.
        XCTAssertTrue(TimelinePrefetchPolicy.isNearOldest(contentOffsetY: 1_199, containerHeight: 800, distancePercent: 150))
        XCTAssertFalse(TimelinePrefetchPolicy.isNearOldest(contentOffsetY: 1_201, containerHeight: 800, distancePercent: 150))
    }

    func testPhase74PrefetchPolicyWithZeroDistanceOnlyTriggersAtTheTop() {
        XCTAssertTrue(TimelinePrefetchPolicy.isNearOldest(contentOffsetY: 0, containerHeight: 800, distancePercent: 0))
        XCTAssertFalse(TimelinePrefetchPolicy.isNearOldest(contentOffsetY: 1, containerHeight: 800, distancePercent: 0))
    }

    func testPhase74PrefetchPolicyIsInertBeforeLayoutHasAHeight() {
        // A zero container is a pre-layout pass, not "we are at the top of history".
        XCTAssertFalse(TimelinePrefetchPolicy.isNearOldest(contentOffsetY: 0, containerHeight: 0, distancePercent: 150))
    }

    func testPhase74RowBackstopTriggersOnlyWithinThreshold() {
        XCTAssertTrue(TimelinePrefetchPolicy.isNearOldestRow(firstVisibleIndex: 5, rowThreshold: 12))
        XCTAssertFalse(TimelinePrefetchPolicy.isNearOldestRow(firstVisibleIndex: 40, rowThreshold: 12))
        XCTAssertFalse(TimelinePrefetchPolicy.isNearOldestRow(firstVisibleIndex: nil, rowThreshold: 12))
    }

    func testPhase74RestorationScrollsAreNeverAnimated() {
        // Animating a restoration renders the jump it exists to hide as a deliberate swoop.
        XCTAssertFalse(TimelineScrollAnimationPolicy.shouldAnimate(
            intent: .preservePositionAfterPrepend(previousOldestID: "m1"), reduceMotion: false))
        XCTAssertFalse(TimelineScrollAnimationPolicy.shouldAnimate(
            intent: .preserveVisibleAnchor("m1"), reduceMotion: false))
        // Navigation the user asked for still animates.
        XCTAssertTrue(TimelineScrollAnimationPolicy.shouldAnimate(
            intent: .newest(reason: .jumpCommand), reduceMotion: false))
        XCTAssertFalse(TimelineScrollAnimationPolicy.shouldAnimate(
            intent: .newest(reason: .jumpCommand), reduceMotion: true))
    }

    // MARK: - Gating

    @MainActor
    func testPhase74PrefetchDoesNotFireWhenNoMoreHistoryExists() async {
        let channelID: ChannelID = "phase74-nomore"
        let only = message(id: ulid(milliseconds: 1_000), author: "a", channel: channelID)
        let api = RecordingAPIClient(messagesByChannel: [channelID: [only]])
        // pageSize 50 with 1 returned message means hasMoreBefore resolves false.
        let model = await paginationModel(channelID: channelID, api: api, pageSize: 50)

        let before = await api.fetchMessagesCallCount
        let loaded = await model.requestOlderMessagesIfNeeded(channelID: channelID, trigger: .scrollPrefetch)
        let after = await api.fetchMessagesCallCount

        XCTAssertFalse(loaded)
        XCTAssertEqual(before, after, "hasMoreBefore == false must not issue a request")
        XCTAssertEqual(model.phase74PaginationDiagnostics.lastSuppressionReason, .noMoreBefore)
    }

    @MainActor
    func testPhase74PrefetchIsSuppressedForANonSelectedChannel() async {
        let channelID: ChannelID = "phase74-other"
        let api = RecordingAPIClient(messagesByChannel: [:])
        let model = MainShellViewModel(
            snapshot: RealtimeSnapshot(),
            runtimeMode: .liveManual,
            sessionState: .connected,
            currentUser: User(id: "a", username: "a"),
            messageController: ChannelMessageController(runtimeMode: .liveManual, apiClient: api, currentUserID: "a"),
            messageActionHandler: StubMessageActionHandler(currentUserID: "a"),
            communityAPIClient: StubStoatAPIClient()
        )

        let loaded = await model.requestOlderMessagesIfNeeded(channelID: channelID, trigger: .scrollPrefetch)

        XCTAssertFalse(loaded)
        XCTAssertEqual(model.phase74PaginationDiagnostics.lastSuppressionReason, .notSelectedChannel)
    }

    @MainActor
    func testPhase74ConcurrentPrefetchTriggersIssueExactlyOneFetch() async {
        let channelID: ChannelID = "phase74-concurrent"
        let messages = (0..<4).map { message(id: ulid(milliseconds: UInt64(1_000 + $0)), author: "a", channel: channelID) }
        // A slow fetch keeps the first request in flight while the second arrives.
        let api = RecordingAPIClient(messagesByChannel: [channelID: messages], fetchMessagesDelayNanoseconds: 40_000_000)
        let model = await paginationModel(channelID: channelID, api: api, pageSize: 2)
        let baseline = await api.fetchMessagesCallCount

        async let first = model.requestOlderMessagesIfNeeded(channelID: channelID, trigger: .scrollPrefetch)
        async let second = model.requestOlderMessagesIfNeeded(channelID: channelID, trigger: .visibleRangeNearOldest)
        _ = await (first, second)

        let issued = await api.fetchMessagesCallCount - baseline
        XCTAssertEqual(issued, 1, "overlapping triggers must collapse to one request")
    }

    @MainActor
    func testPhase74AutomaticPagingStopsAtBudgetUntilTheUserScrollsAway() async {
        let channelID: ChannelID = "phase74-budget"
        let api = PagingMessageAPIClient(messages: pagedMessages(channelID: channelID, count: 40))
        let model = await paginationModel(channelID: channelID, api: api, pageSize: 2)

        // The channel is shorter than a viewport, so nothing would ever move the scroll offset
        // and re-arm the trigger. Only the budget stops this.
        for _ in 0..<(OlderLoadPacingState.maximumConsecutiveAutomaticPages + 3) {
            _ = await model.requestOlderMessagesIfNeeded(channelID: channelID, trigger: .scrollPrefetch)
        }

        XCTAssertEqual(model.phase74PaginationDiagnostics.pageLoadedCount, OlderLoadPacingState.maximumConsecutiveAutomaticPages)
        XCTAssertEqual(model.phase74PaginationDiagnostics.lastSuppressionReason, .automaticPageBudgetExhausted)

        // Scrolling away refunds the budget.
        model.timelineOlderPrefetchThresholdChanged(false)
        _ = await model.requestOlderMessagesIfNeeded(channelID: channelID, trigger: .scrollPrefetch)

        XCTAssertEqual(model.phase74PaginationDiagnostics.pageLoadedCount, OlderLoadPacingState.maximumConsecutiveAutomaticPages + 1)
    }

    @MainActor
    func testPhase74ExplicitCommandBypassesTheAutomaticBudget() async {
        let channelID: ChannelID = "phase74-explicit"
        let api = PagingMessageAPIClient(messages: pagedMessages(channelID: channelID, count: 40))
        let model = await paginationModel(channelID: channelID, api: api, pageSize: 2)

        for _ in 0..<OlderLoadPacingState.maximumConsecutiveAutomaticPages {
            _ = await model.requestOlderMessagesIfNeeded(channelID: channelID, trigger: .scrollPrefetch)
        }
        let exhausted = model.phase74PaginationDiagnostics.pageLoadedCount
        _ = await model.requestOlderMessagesIfNeeded(channelID: channelID, trigger: .explicitCommand)

        XCTAssertEqual(model.phase74PaginationDiagnostics.pageLoadedCount, exhausted + 1)
    }

    @MainActor
    func testPhase74ChannelSwitchClearsPrefetchBookkeeping() async {
        let first: ChannelID = "phase74-switch-a"
        let second: ChannelID = "phase74-switch-b"
        var snapshot = RealtimeSnapshot()
        snapshot.usersByID["a"] = User(id: "a", username: "a")
        snapshot.channelsByID[first] = Channel(id: first, kind: .directMessage, recipients: ["a", "b"])
        snapshot.channelsByID[second] = Channel(id: second, kind: .directMessage, recipients: ["a", "c"])
        let api = PagingMessageAPIClient(
            messages: pagedMessages(channelID: first, count: 40)
                + pagedMessages(channelID: second, count: 40, millisecondOffset: 100_000)
        )
        let controller = ChannelMessageController(runtimeMode: .liveManual, apiClient: api, currentUserID: "a", pageSize: 2)
        let model = MainShellViewModel(
            snapshot: snapshot,
            runtimeMode: .liveManual,
            sessionState: .connected,
            currentUser: snapshot.usersByID["a"],
            messageController: controller,
            messageActionHandler: StubMessageActionHandler(currentUserID: "a"),
            communityAPIClient: StubStoatAPIClient()
        )

        model.selectChannel(first)
        try? await Task.sleep(for: .milliseconds(40))
        for _ in 0..<OlderLoadPacingState.maximumConsecutiveAutomaticPages {
            _ = await model.requestOlderMessagesIfNeeded(channelID: first, trigger: .scrollPrefetch)
        }
        XCTAssertEqual(model.phase74PaginationDiagnostics.lastSuppressionReason, nil)

        model.selectChannel(second)
        try? await Task.sleep(for: .milliseconds(40))
        let loaded = await model.requestOlderMessagesIfNeeded(channelID: second, trigger: .scrollPrefetch)

        XCTAssertTrue(loaded, "a freshly selected channel must not inherit the previous channel's exhausted budget")
    }

    // MARK: - Failure handling

    func testPhase74PaginationFailureKeepsTheTimelineLoadedAndReportsSeparately() {
        let channelID: ChannelID = "phase74-fail"
        let reducer = ChannelMessageHistoryReducer(messageCapPerChannel: 10)
        let messages = [
            message(id: ulid(milliseconds: 1_000), author: "a", channel: channelID),
            message(id: ulid(milliseconds: 2_000), author: "a", channel: channelID)
        ]
        var history = reducer.reduce(
            ChannelMessageHistory(channelID: channelID),
            event: .initialLoadSucceeded(messages: messages, hasMoreBefore: true, loadedAt: Date())
        )

        history = reducer.reduce(history, event: .olderLoadFailed("Couldn't load older messages."))

        // The whole timeline must NOT flip to .failed. An automatic background fetch failing is
        // not a reason to replace the messages the user is reading with an error state -- that
        // was tolerable when a button meant the user had asked, and is not now.
        guard case let .loaded(loaded, _) = history.state else {
            return XCTFail("expected .loaded, got \(history.state)")
        }
        XCTAssertEqual(loaded.count, messages.count)
        XCTAssertEqual(history.loadedRange.lastPaginationError, "Couldn't load older messages.")
        XCTAssertNil(history.errorMessage)
        XCTAssertFalse(history.isLoadingOlder)
    }

    func testPhase74InitialLoadFailureStillOwnsTheFullTimelineErrorState() {
        // The counterpart to the test above: `errorMessage` remains the initial-load channel, so
        // a genuine first-load failure still gets the full error state and its retry button.
        let channelID: ChannelID = "phase74-initial-fail"
        let reducer = ChannelMessageHistoryReducer(messageCapPerChannel: 10)
        let history = reducer.reduce(
            ChannelMessageHistory(channelID: channelID),
            event: .initialLoadFailed("Couldn't load this channel.")
        )

        XCTAssertEqual(history.errorMessage, "Couldn't load this channel.")
        guard case .failed = history.state else {
            return XCTFail("expected .failed, got \(history.state)")
        }
    }

    @MainActor
    func testPhase74FailureCooldownBlocksAutomaticRetryButNotAnExplicitOne() async {
        let channelID: ChannelID = "phase74-cooldown"
        // Succeed the initial load, then fail every page after it.
        let api = PagingMessageAPIClient(
            messages: pagedMessages(channelID: channelID, count: 40),
            failAfterCallCount: 1
        )
        let model = await paginationModel(channelID: channelID, api: api, pageSize: 2)

        _ = await model.requestOlderMessagesIfNeeded(channelID: channelID, trigger: .scrollPrefetch)
        XCTAssertEqual(model.phase74PaginationDiagnostics.pageFailedCount, 1)

        _ = await model.requestOlderMessagesIfNeeded(channelID: channelID, trigger: .scrollPrefetch)
        XCTAssertEqual(model.phase74PaginationDiagnostics.lastSuppressionReason, .failureCooldown)

        _ = await model.requestOlderMessagesIfNeeded(channelID: channelID, trigger: .explicitCommand)
        XCTAssertEqual(model.phase74PaginationDiagnostics.pageFailedCount, 2, "an explicit retry must ignore the cooldown")
    }

    // MARK: - Header state

    @MainActor
    func testPhase74HeaderReportsBeginningOnlyWhenOnline() async {
        let channelID: ChannelID = "phase74-header"
        let only = message(id: ulid(milliseconds: 1_000), author: "a", channel: channelID)
        let model = await paginationModel(
            channelID: channelID,
            api: RecordingAPIClient(messagesByChannel: [channelID: [only]]),
            pageSize: 50
        )

        guard case .beginning = model.olderHistoryHeaderState else {
            return XCTFail("connected with no more history should read as the beginning of the channel")
        }

        // Offline, "no more history" only means "no more *cached* history". Claiming the user has
        // reached the start of the channel would be a lie.
        model.sessionState = .connecting
        XCTAssertEqual(model.olderHistoryHeaderState, .unavailableOffline)
    }

    @MainActor
    func testPhase74HeaderPrefersFailureOverBeginning() async {
        let channelID: ChannelID = "phase74-header-fail"
        let api = PagingMessageAPIClient(
            messages: pagedMessages(channelID: channelID, count: 40),
            failAfterCallCount: 1
        )
        let model = await paginationModel(channelID: channelID, api: api, pageSize: 2)

        _ = await model.requestOlderMessagesIfNeeded(channelID: channelID, trigger: .explicitCommand)

        guard case .failed = model.olderHistoryHeaderState else {
            return XCTFail("expected .failed, got \(model.olderHistoryHeaderState)")
        }
    }

    // MARK: - Helpers

    private func pagedMessages(channelID: ChannelID, count: Int, millisecondOffset: UInt64 = 0) -> [Message] {
        (0..<count).map {
            message(id: ulid(milliseconds: millisecondOffset + UInt64(1_000 + $0)), author: "a", channel: channelID)
        }
    }

    /// A live-mode shell with `channelID` selected and its first page already loaded.
    @MainActor
    private func paginationModel(
        channelID: ChannelID,
        api: any StoatAPIClient,
        pageSize: Int
    ) async -> MainShellViewModel {
        var snapshot = RealtimeSnapshot()
        snapshot.usersByID["a"] = User(id: "a", username: "a")
        snapshot.channelsByID[channelID] = Channel(id: channelID, kind: .directMessage, recipients: ["a", "b"])
        let controller = ChannelMessageController(runtimeMode: .liveManual, apiClient: api, currentUserID: "a", pageSize: pageSize)
        let model = MainShellViewModel(
            snapshot: snapshot,
            runtimeMode: .liveManual,
            sessionState: .connected,
            currentUser: snapshot.usersByID["a"],
            messageController: controller,
            messageActionHandler: StubMessageActionHandler(currentUserID: "a"),
            communityAPIClient: StubStoatAPIClient()
        )
        model.selectChannel(channelID)
        try? await Task.sleep(for: .milliseconds(50))
        return model
    }
}

// Phase 74 -- developer options are opt-in.
extension StoatFeaturesTests {
    @MainActor
    func testPhase74DeveloperControlsAreOffByDefaultAndWhenUnconfigured() async {
        XCTAssertFalse(AppPreferences.defaults.showDeveloperRuntimeControls)

        // A shell with no coordinator attached must also fall closed. An unconfigured shell is
        // not evidence that the user asked to see internals.
        let model = MainShellViewModel(
            snapshot: RealtimeSnapshot(),
            runtimeMode: .liveManual,
            sessionState: .signedOut,
            currentUser: nil,
            messageActionHandler: StubMessageActionHandler(currentUserID: "a"),
            communityAPIClient: StubStoatAPIClient()
        )
        XCTAssertFalse(model.isDeveloperControlsEnabled)
    }

    func testPhase74StoredPreferencesWithoutTheDeveloperKeyStayOff() throws {
        // An upgrade from a build that predates the key must not silently opt the user in.
        let json = Data("""
        { "messageDensity": "compact" }
        """.utf8)
        let preferences = try JSONDecoder.stoat.decode(AppPreferences.self, from: json)
        XCTAssertFalse(preferences.showDeveloperRuntimeControls)
    }

    func testPhase74TimelineTuningDecodesPayloadsWrittenBeforePrefetchExisted() throws {
        // TimelineTuningConfiguration used synthesized Codable, which throws on a missing key.
        // Adding the prefetch fields would have invalidated every stored preference blob.
        let json = Data("""
        {
          "nearNewestMessageThreshold": 3,
          "visibleRangeUpdateDebounceMilliseconds": 90,
          "loadToUnreadMaxAttempts": 5,
          "referenceFetchMaxAttempts": 1,
          "referenceFetchCooldownSeconds": 30,
          "ackDebounceMilliseconds": 1200
        }
        """.utf8)
        let tuning = try JSONDecoder.stoat.decode(TimelineTuningConfiguration.self, from: json)

        XCTAssertEqual(tuning.nearNewestMessageThreshold, 3)
        XCTAssertEqual(tuning.olderPrefetchDistancePercent, TimelineTuningConfiguration.defaults.olderPrefetchDistancePercent)
        XCTAssertEqual(tuning.olderPrefetchRowThreshold, TimelineTuningConfiguration.defaults.olderPrefetchRowThreshold)
    }
}

// Phase 74 -- user-facing error copy.
extension StoatFeaturesTests {
    /// The contract, asserted mechanically: nothing a user reads carries a status code, a
    /// decoder path, a diagnostic category, a URL, or a bare enum case name.
    func testPhase74UserFacingErrorsNeverLeakDiagnosticDetail() {
        let leaky: [any Error] = [
            StoatAPIError.serverError(statusCode: 500, message: "upstream connect error 111"),
            StoatAPIError.unknown(statusCode: 502, body: "<html>bad gateway</html>"),
            StoatAPIError.decodingFailed("keyNotFound(CodingKeys(stringValue: \"_id\"))"),
            StoatAPIError.transport("The request timed out. https://api.stoat.chat/users/@me"),
            StoatAPIError.rateLimited(retryAfterMilliseconds: 4_312),
            StoatAPIError.unauthorized,
            StoatAPIError.forbidden
        ]

        for error in leaky {
            let message = UserFacingError.message(for: error)
            for forbidden in ["500", "502", "111", "4312", "CodingKeys", "keyNotFound", "http", "<html>"] {
                XCTAssertFalse(
                    message.lowercased().contains(forbidden.lowercased()),
                    "\(error) produced \"\(message)\", which leaks \(forbidden)"
                )
            }
            XCTAssertFalse(message.isEmpty)
            XCTAssertTrue(message.hasSuffix(".") , "\(message) should be a complete sentence")
        }
    }

    func testPhase74AlreadyUserFacingErrorsKeepTheirOwnWords() {
        // Sanitising is for errors that leak internals. An error that already names the thing
        // the user can fix must survive untouched.
        XCTAssertEqual(
            UserFacingError.message(for: AttachmentValidationError.tooLarge(maxBytes: 20 * 1024 * 1024), context: .attachment),
            "File too large. Liquid Bagel currently supports files up to 20 MB."
        )
        XCTAssertEqual(
            UserFacingError.message(for: AttachmentValidationError.tooManyAttachments(5), context: .attachment),
            "Attach up to 5 files per message."
        )
    }

    func testPhase74ErrorCopyIsContextual() {
        let error = StoatAPIError.serverError(statusCode: 503, message: nil)
        XCTAssertEqual(
            UserFacingError.message(for: error, context: .sendMessage),
            UserFacingError.message(for: error, context: .members),
            "server trouble reads the same everywhere"
        )
        // A missing resource, though, depends on what the user was doing.
        XCTAssertNotEqual(
            UserFacingError.message(for: StoatAPIError.notFound, context: .sendMessage),
            UserFacingError.message(for: StoatAPIError.notFound, context: .members)
        )
    }

    func testPhase74NoticePolicyNowRecognisesConfirmations() {
        // These all previously returned nil and were dropped on the floor.
        XCTAssertEqual(TransientAppNoticePolicy.severity(for: "Attachment saved"), .success)
        XCTAssertEqual(TransientAppNoticePolicy.severity(for: "Message pinned"), .success)
        XCTAssertEqual(TransientAppNoticePolicy.severity(for: "Profile updated."), .success)
        XCTAssertEqual(TransientAppNoticePolicy.severity(for: "Message ID copied"), .success)
        // Failures and warnings keep classifying as before.
        XCTAssertEqual(TransientAppNoticePolicy.severity(for: "Attachment upload failed."), .error)
        XCTAssertEqual(TransientAppNoticePolicy.severity(for: "Reconnect to refresh live state"), .warning)
        // Unrecognised text stays silent rather than becoming a toast, so adding a new status
        // string cannot accidentally start interrupting people.
        XCTAssertNil(TransientAppNoticePolicy.severity(for: "Timeline calibration started"))
        XCTAssertNil(TransientAppNoticePolicy.severity(for: ""))
    }

    @MainActor
    func testPhase74MemberPanelIsSilentWhenHealthy() async {
        let model = MainShellViewModel(
            snapshot: TestShellData.snapshot,
            runtimeMode: .mock,
            sessionState: .mock,
            currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID],
            messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID),
            communityAPIClient: StubStoatAPIClient()
        )
        let serverID = TestShellData.snapshot.serversByID.values.first!.id

        // No error, not loading: the panel says nothing at all. It used to narrate
        // "Members refreshed from Stoat" / "Showing Ready members".
        XCTAssertNil(model.memberHydrationStatusMessage(for: serverID))
    }
}
