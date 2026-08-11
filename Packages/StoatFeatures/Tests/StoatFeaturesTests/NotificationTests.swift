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

}
