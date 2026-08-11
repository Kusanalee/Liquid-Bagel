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

    func phase18Snapshot(currentUserID: UserID, otherUserID: UserID, textChannelID: ChannelID, dmChannelID: ChannelID) -> RealtimeSnapshot {
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

    func message(
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

}
