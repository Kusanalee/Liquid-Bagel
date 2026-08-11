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

}
