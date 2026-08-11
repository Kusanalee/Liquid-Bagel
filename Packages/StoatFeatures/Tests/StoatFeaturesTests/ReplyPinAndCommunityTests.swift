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
    func testPhase44ReplyComposerClearsAfterSuccessAndPersistsAfterFailure() async throws {
        let channelID = try XCTUnwrap(TestShellData.snapshot.channelsByID.values.first { $0.kind == .textChannel }?.id)
        let target = try XCTUnwrap(TestShellData.snapshot.messagesByChannelID[channelID]?.first)

        let failingHandler = RecordingAttachmentMessageActionHandler()
        await failingHandler.setSendError(MessageActionError.unavailable("offline"))
        let failingModel = MainShellViewModel(snapshot: TestShellData.snapshot, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: failingHandler, communityAPIClient: StubStoatAPIClient())
        failingModel.selectChannel(channelID)
        failingModel.beginReply(to: TimelineMessage(message: target, status: .confirmed))
        failingModel.updateDraft("still here", for: channelID)
        await failingModel.sendDraft(for: channelID)

        XCTAssertEqual(failingModel.replyContext(for: channelID)?.messageID, target.id)
        XCTAssertEqual(failingModel.draft(for: channelID), "still here")
        XCTAssertEqual(failingModel.phase44Diagnostics.replyComposerPreservedAfterFailureCount, 1)

        let successHandler = RecordingAttachmentMessageActionHandler()
        let successModel = MainShellViewModel(snapshot: TestShellData.snapshot, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: successHandler, communityAPIClient: StubStoatAPIClient())
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
        let current = User(id: TestShellData.currentUserID, username: "me")
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
        let model = MainShellViewModel(snapshot: RealtimeSnapshot(serversByID: [serverID: server], channelsByID: [channelID: channel]), currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())

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
        let currentUserID = TestShellData.currentUserID
        let channelID: ChannelID = "phase44-ack-channel"
        let message = Message(id: MessageID(rawValue: ulid(milliseconds: 1_000)), channelID: channelID, authorID: "phase44-other", content: "ack me")
        let channel = Channel(id: channelID, kind: .textChannel, serverID: "phase44-ack-server", name: "ack")
        let server = Server(id: "phase44-ack-server", ownerID: currentUserID, name: "Ack", channelIDs: [channelID])
        var snapshot = RealtimeSnapshot(serversByID: [server.id: server], channelsByID: [channelID: channel], messagesByChannelID: [channelID: [message]])
        snapshot.unreadsByChannelID[channelID] = ChannelUnread(id: ChannelCompositeKey(channelID: channelID, userID: currentUserID), lastMessageID: message.id, mentions: [])
        let model = MainShellViewModel(selection: ShellSelection(space: .server(server.id), serverID: server.id, channelID: channelID), snapshot: snapshot, runtimeMode: .liveManual, sessionState: .connected, currentUser: User(id: currentUserID, username: "me"), messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), channelAckSender: sender, communityAPIClient: StubStoatAPIClient())
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
        let loader = StubImageResourceLoader(result: .success(data))
        let serverID: ServerID = "phase47-embed-server"
        let channelID: ChannelID = "phase47-embed-channel"
        let file = File(id: "phase47-embed-media", tag: "attachments", filename: "embed.png", metadata: .image(width: 64, height: 64, thumbhash: nil, animated: false), contentType: "image/png", size: 512)
        let message = Message(
            id: "01J00000000000000000470001",
            channelID: channelID,
            authorID: TestShellData.currentUserID,
            embeds: [Embed(kind: .image, title: "Modeled image", media: file)]
        )
        let channel = Channel(id: channelID, kind: .textChannel, serverID: serverID, name: "embeds")
        let server = Server(id: serverID, ownerID: TestShellData.currentUserID, name: "Embeds", channelIDs: [channelID])
        let snapshot = RealtimeSnapshot(serversByID: [serverID: server], channelsByID: [channelID: channel], messagesByChannelID: [channelID: [message]])
        let model = MainShellViewModel(selection: ShellSelection(space: .server(serverID), serverID: serverID, channelID: channelID), snapshot: snapshot, runtimeMode: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), imageResourceLoader: loader, communityAPIClient: StubStoatAPIClient())

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
            authorID: TestShellData.currentUserID,
            embeds: [Embed(kind: .website, url: "https://example.com/private?token=secret", title: "<b>Launch notes</b>", siteName: "Example")]
        )

        XCTAssertEqual(Phase44SafeSummary.messageSummary(for: website), "Launch notes")

        let file = File(id: "phase47-summary-image", tag: "attachments", filename: "image.png", metadata: .image(width: 20, height: 20, thumbhash: nil, animated: false), contentType: "image/png", size: 64)
        let imageOnly = Message(
            id: "01J00000000000000000470003",
            channelID: channelID,
            authorID: TestShellData.currentUserID,
            embeds: [Embed(kind: .image, media: file)]
        )

        XCTAssertEqual(Phase44SafeSummary.messageSummary(for: imageOnly), "Image embed")
    }

    // MARK: - Phase 25 CategoryEditorForm reorder tests

    func testCategoryEditorFormMoveCategoriesChangesOrder() {
        let server = TestShellData.snapshot.serversByID.values.first { $0.name == "Bagel Lab" }!
        var form = CategoryEditorForm(server: server)
        XCTAssertEqual(form.categories.map(\.id), ["cat-text", "cat-voice"])

        form.moveCategories(fromOffsets: IndexSet(integer: 0), toOffset: 2)
        XCTAssertEqual(form.categories.map(\.id), ["cat-voice", "cat-text"])
    }

    func testCategoryEditorFormMoveCategoriesNoOpLeavesUnchanged() {
        let server = TestShellData.snapshot.serversByID.values.first { $0.name == "Bagel Lab" }!
        var form = CategoryEditorForm(server: server)
        let original = form.categories.map(\.id)

        form.moveCategories(fromOffsets: IndexSet(integer: 0), toOffset: 1)
        XCTAssertEqual(form.categories.map(\.id), original)
    }

    func testCategoryEditorFormMoveChannelsChangesOrderWithinCategory() {
        let server = TestShellData.snapshot.serversByID.values.first { $0.name == "Bagel Lab" }!
        var form = CategoryEditorForm(server: server)
        let general: ChannelID = "01HX0000000000000000000101"
        let api: ChannelID = "01HX0000000000000000000102"
        let native: ChannelID = "01HX0000000000000000000103"
        XCTAssertEqual(form.categories.first(where: { $0.id == "cat-text" })?.channels, [general, api, native])

        form.moveChannels(inCategory: "cat-text", fromOffsets: IndexSet(integer: 0), toOffset: 3)
        XCTAssertEqual(form.categories.first(where: { $0.id == "cat-text" })?.channels, [api, native, general])
    }

    func testCategoryEditorFormMoveChannelsNoOpLeavesUnchanged() {
        let server = TestShellData.snapshot.serversByID.values.first { $0.name == "Bagel Lab" }!
        var form = CategoryEditorForm(server: server)
        let general: ChannelID = "01HX0000000000000000000101"
        let api: ChannelID = "01HX0000000000000000000102"
        let native: ChannelID = "01HX0000000000000000000103"

        form.moveChannels(inCategory: "cat-text", fromOffsets: IndexSet(integer: 0), toOffset: 1)
        XCTAssertEqual(form.categories.first(where: { $0.id == "cat-text" })?.channels, [general, api, native])
    }

    func testCategoryEditorFormMoveChannelsUnknownCategoryIsNoop() {
        let server = TestShellData.snapshot.serversByID.values.first { $0.name == "Bagel Lab" }!
        var form = CategoryEditorForm(server: server)
        let before = form

        form.moveChannels(inCategory: "nonexistent", fromOffsets: IndexSet(integer: 0), toOffset: 2)
        XCTAssertEqual(form, before)
    }

    // MARK: - openNewDirectMessage command tests

    @MainActor
    func testOpenNewDirectMessageCanPerformInMockMode() {
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())
        XCTAssertTrue(model.canPerform(.openNewDirectMessage))
    }

    @MainActor
    func testOpenNewDirectMessagePerformSetsPresentationFlag() {
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())
        XCTAssertFalse(model.isPresentingNewDirectMessage)

        model.perform(.openNewDirectMessage)

        XCTAssertTrue(model.isPresentingNewDirectMessage)
    }

    @MainActor
    func testOpenNewDirectMessageResetsSearchBeforePresenting() {
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())
        model.newDirectMessageSearch = "old query"

        model.openNewDirectMessage()

        XCTAssertEqual(model.newDirectMessageSearch, "")
        XCTAssertTrue(model.isPresentingNewDirectMessage)
    }

    @MainActor
    func testNewDirectMessageCandidatesEmptyForNonMatchingSearch() {
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())
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
            snapshot: snapshot, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())

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
            snapshot: snapshot, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())
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
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())
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
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())
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
        let model = MainShellViewModel(snapshot: snapshot, currentUser: readyUser, messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())

        XCTAssertEqual(model.currentUserForPresentation?.avatar?.id, avatar.id)
        XCTAssertEqual(model.currentUserForPresentation?.displayName, "Ready display")
        XCTAssertEqual(model.currentUserForPresentation?.status?.text, "Busy")
        XCTAssertEqual(model.currentUserForPresentation?.status?.presence, .idle)
    }

    @MainActor
    func testPhase61VisibilityTrackingMigratesToConfirmedIDWithoutRetriggeringAvatarResource() async throws {
        let handler = DelayedMessageActionHandler(delay: .milliseconds(80))
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: handler, communityAPIClient: StubStoatAPIClient())
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

    func ulid(milliseconds: UInt64) -> String {
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
        let model = MainShellViewModel(currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient(), notificationSignatureStatusPreparer: { _ in
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
        var snapshot = TestShellData.snapshot
        let server = try XCTUnwrap(snapshot.serversByID.values.first { !$0.channelIDs.isEmpty })
        let channelID = try XCTUnwrap(server.channelIDs.first)
        let emoji = Emoji(
            id: "01J00000000000000000700001",
            parent: .server(server.id),
            creatorID: TestShellData.currentUserID,
            name: "interoperable"
        )
        snapshot.emojisByID[emoji.id] = emoji
        let handler = DelayedMessageActionHandler(delay: .milliseconds(80))
        let model = MainShellViewModel(
            selection: ShellSelection(space: .server(server.id), serverID: server.id, channelID: channelID),
            snapshot: snapshot,
            currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: handler, communityAPIClient: StubStoatAPIClient())
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
