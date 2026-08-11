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

}
