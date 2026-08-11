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
    func testPhase22MockRelationshipActionsAndDMSelection() async {
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())
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
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())

        model.perform(.jumpToFriends)
        XCTAssertEqual(model.selection.space, .directMessages)
        XCTAssertEqual(model.friendsTab, .online)

        model.perform(.jumpToAddFriend)
        XCTAssertEqual(model.selection.space, .directMessages)
        XCTAssertEqual(model.friendsTab, .addFriend)

        let switcher = QuickSwitcherViewModel(snapshot: TestShellData.snapshot)
        let friends = QuickSwitcherResult(id: "route-friends", title: "Friends", kind: .route(.friends))
        XCTAssertEqual(switcher.command(for: friends), .jumpToFriends)
    }

    func testPhase22RealtimeRelationshipEventAppliesExplicitStatus() async {
        let user = User(id: "phase22-user", username: "phase22", relationship: .none)
        let store = RealtimeStateStore()

        await store.apply(.userRelationship(UserRelationshipEvent(id: TestShellData.currentUserID, user: user, status: .incoming)))
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
        let uploader = StubAttachmentUploadHandler()
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), attachmentUploadHandler: uploader, communityAPIClient: StubStoatAPIClient())
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
        var snapshot = TestShellData.snapshot
        let channelID = try XCTUnwrap(snapshot.channelsByID.values.first(where: { $0.kind == .textChannel })?.id)
        let message = Message(id: "01J00000000000000000270003", channelID: channelID, authorID: "phase27-user", system: SystemMessage(kind: .userLeft, by: "phase27-user"))
        snapshot.messagesByChannelID[channelID] = [message]
        snapshot.unreadsByChannelID[channelID] = ChannelUnread(id: ChannelCompositeKey(channelID: channelID, userID: TestShellData.currentUserID), lastMessageID: message.id, mentions: [])

        let model = MainShellViewModel(snapshot: snapshot, runtimeMode: .liveManual, sessionState: .connected, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), channelAckSender: sender, communityAPIClient: StubStoatAPIClient())
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
        var snapshot = TestShellData.snapshot
        let dmID = try XCTUnwrap(snapshot.channelsByID.values.first(where: { $0.kind == .directMessage })?.id)
        let message = Message(id: "01J00000000000000000270004", channelID: dmID, authorID: "01HX0000000000000000000003", content: "dm ack")
        snapshot.messagesByChannelID[dmID] = [message]
        snapshot.unreadsByChannelID[dmID] = ChannelUnread(id: ChannelCompositeKey(channelID: dmID, userID: TestShellData.currentUserID), lastMessageID: message.id, mentions: [])

        let model = MainShellViewModel(snapshot: snapshot, runtimeMode: .liveManual, sessionState: .connected, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), channelAckSender: sender, communityAPIClient: StubStoatAPIClient())
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

        let model = MainShellViewModel(snapshot: snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())
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

        let model = MainShellViewModel(selection: ShellSelection(space: .server(serverID), serverID: serverID), snapshot: snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())
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
        let loader = StubImageResourceLoader(result: .success(Data("avatar".utf8)))
        let model = MainShellViewModel(selection: ShellSelection(space: .server(serverID), serverID: serverID), snapshot: snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), imageResourceLoader: loader, communityAPIClient: StubStoatAPIClient())
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
        let model = MainShellViewModel(selection: ShellSelection(space: .server(serverID), serverID: serverID, channelID: channelID), snapshot: snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())

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
        let model = MainShellViewModel(runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), imageResourceLoader: loader, communityAPIClient: StubStoatAPIClient())
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
        let loader = StubRemoteAttachmentLoader(result: .success(RemoteAttachmentData(filename: "photo.png", contentType: "image/png", byteCount: data.count, data: data)))
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), remoteAttachmentLoader: loader, communityAPIClient: StubStoatAPIClient())
        let files = (0..<10).map { index in
            File(id: FileID(rawValue: "phase55-inline-\(index)"), tag: "attachments", filename: "photo\(index).png", metadata: .image(width: 10, height: 10, thumbhash: nil, animated: false), contentType: "image/png", size: 100)
        }
        let message = Message(id: "01J00000000000000000550001", channelID: "01HX0000000000000000000101", authorID: TestShellData.currentUserID, attachments: files)

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
        let loader = StubImageResourceLoader(result: .failure(AttachmentActionError.unavailable("nope")))
        let model = MainShellViewModel(runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), imageResourceLoader: loader, communityAPIClient: StubStoatAPIClient())
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
        let loader = StubImageResourceLoader(result: .success(data))
        let model = MainShellViewModel(runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), imageResourceLoader: loader, communityAPIClient: StubStoatAPIClient())
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
        let loader = StubImageResourceLoader(result: .success(data))
        let model = MainShellViewModel(runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), imageResourceLoader: loader, communityAPIClient: StubStoatAPIClient())
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
        let loader = StubImageResourceLoader(result: .success(data))
        let model = MainShellViewModel(runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), imageResourceLoader: loader, communityAPIClient: StubStoatAPIClient())
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
        let loader = StubImageResourceLoader(result: .success(data))
        let model = MainShellViewModel(runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), imageResourceLoader: loader, communityAPIClient: StubStoatAPIClient())
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
        let loader = StubImageResourceLoader(result: .success(data))
        let model = MainShellViewModel(runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), imageResourceLoader: loader, communityAPIClient: StubStoatAPIClient())
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
        let loader = StubImageResourceLoader(result: .success(data))
        let model = MainShellViewModel(runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), imageResourceLoader: loader, communityAPIClient: StubStoatAPIClient())
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
        let loader = StubImageResourceLoader(result: .success(data))
        let model = MainShellViewModel(runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), imageResourceLoader: loader, communityAPIClient: StubStoatAPIClient())
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
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())
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
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())
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
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())
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
        let otherModel = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())
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
            snapshot: snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())
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
        let loader = StubImageResourceLoader(result: .success(data))
        let model = MainShellViewModel(runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), imageResourceLoader: loader, communityAPIClient: StubStoatAPIClient())
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
            runtimeMode: .mock, sessionState: .mock, currentUser: currentUser, messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())
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
        let model = MainShellViewModel(runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), imageResourceLoader: loader, communityAPIClient: StubStoatAPIClient())
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
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: handler, communityAPIClient: StubStoatAPIClient())
        model.selectServer(model.servers[0].id)
        let message = try XCTUnwrap(model.selectedTimelineMessages.first { $0.status == .confirmed })

        let first = Task { await model.toggleReaction("✅", on: message) }
        try await Task.sleep(for: .milliseconds(5))
        XCTAssertEqual(
            model.selectedTimelineMessages.first { $0.message.id == message.message.id }?.message.reactions["✅"],
            [TestShellData.currentUserID]
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
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: handler, communityAPIClient: StubStoatAPIClient())
        model.selectServer(model.servers[0].id)
        let message = try XCTUnwrap(model.selectedTimelineMessages.first { $0.status == .confirmed })

        let task = Task { await model.toggleReaction("🚀", on: message) }
        try await Task.sleep(for: .milliseconds(5))
        XCTAssertEqual(
            model.selectedTimelineMessages.first { $0.message.id == message.message.id }?.message.reactions["🚀"],
            [TestShellData.currentUserID]
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
        let model = MainShellViewModel(runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())

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
        let manager = StubNotificationPermissionManager(status: .notDetermined)
        let model = MainShellViewModel(
            snapshot: TestShellData.snapshot,
            runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), notificationDeliverer: StubNotificationService(),
            notificationPermissionManager: manager,
            dockBadgeManager: StubDockBadgeManager(), communityAPIClient: StubStoatAPIClient())

        model.requestNotificationPermission()
        for _ in 0..<10 where model.notificationPermissionStatus != .authorized {
            try await Task.sleep(for: .milliseconds(30))
        }

        let requestCount = await manager.requestCount
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(model.notificationPermissionStatus, .authorized)
        XCTAssertTrue(model.notificationDiagnostics.lastPermissionRequest?.requestAuthorizationCalled == true)
        XCTAssertEqual(model.notificationDiagnostics.lastPermissionRequest?.statusAfter, .authorized)
        XCTAssertTrue(model.lastNotificationPermissionRequest?.contains("StubNotificationPermissionManager") == true)
        XCTAssertTrue(model.phase28DogfoodDiagnostics.notificationAuthorizerKind.contains("StubNotificationPermissionManager"))
    }

}
