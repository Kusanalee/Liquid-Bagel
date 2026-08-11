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
        let model = MainShellViewModel(snapshot: snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: currentUser, messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())

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
        let model = MainShellViewModel(snapshot: snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: currentUser, messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())

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
        let model = MainShellViewModel(snapshot: snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: currentUser, messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())

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
        let model = MainShellViewModel(snapshot: snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())

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
            runtimeMode: .mock, sessionState: .mock, currentUser: currentUser, messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())

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
        let model = MainShellViewModel(snapshot: snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())

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
        let model = MainShellViewModel(snapshot: RealtimeSnapshot(), runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())
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
        let model = MainShellViewModel(snapshot: snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: currentUser, messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: api)

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
        let model = MainShellViewModel(snapshot: snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: currentUser, messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: api)

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
        let model = MainShellViewModel(snapshot: snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: currentUser, messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: api)

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
        let model = MainShellViewModel(snapshot: snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: currentUser, messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: api)

        await model.fetchCloudPreferences()
        guard case let .failed(message) = model.settingsSyncState else {
            XCTFail("Expected failed state, got \(model.settingsSyncState)")
            return
        }
        XCTAssertFalse(message.contains("500"))
        XCTAssertFalse(message.contains("secret detail"))
    }

    @MainActor
    func phase40LiveModel(snapshot: RealtimeSnapshot, currentUser: User, api: RecordingAPIClient) async -> MainShellViewModel {
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
            sessionCoordinator: coordinator, messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())
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
        let model = MainShellViewModel(snapshot: snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: api)

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
        let model = MainShellViewModel(snapshot: snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: api)

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
        let handler = StubMessageActionHandler(currentUserID: currentUserID)
        let uploader = StubAttachmentUploadHandler()
        let model = MainShellViewModel(snapshot: snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: snapshot.usersByID[currentUserID], messageActionHandler: handler, attachmentUploadHandler: uploader, communityAPIClient: StubStoatAPIClient())
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
        let model = MainShellViewModel(snapshot: snapshot, runtimeMode: .liveManual, sessionState: .connected, currentUser: snapshot.usersByID[currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), channelAckSender: sender, communityAPIClient: StubStoatAPIClient())
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
            messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), notificationDeliverer: StubNotificationService(),
            notificationPermissionManager: StubNotificationPermissionManager(),
            dockBadgeManager: StubDockBadgeManager(),
            communityAPIClient: StubStoatAPIClient(), notificationRouteCenter: NotificationRouteCenter()
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
        let model = MainShellViewModel(snapshot: snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: snapshot.usersByID[currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())

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
        let manager = StubNotificationPermissionManager(status: .notDetermined)
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), notificationPermissionManager: manager, communityAPIClient: StubStoatAPIClient())

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
        let deniedManager = StubNotificationPermissionManager(status: .denied)
        let deniedService = StubNotificationService()
        let deniedModel = MainShellViewModel(
            snapshot: TestShellData.snapshot,
            runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), notificationDeliverer: deniedService,
            notificationPermissionManager: deniedManager,
            dockBadgeManager: StubDockBadgeManager(), communityAPIClient: StubStoatAPIClient())
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

        let authorizedManager = StubNotificationPermissionManager(status: .authorized)
        let authorizedService = StubNotificationService()
        let authorizedModel = MainShellViewModel(
            snapshot: TestShellData.snapshot,
            runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), notificationDeliverer: authorizedService,
            notificationPermissionManager: authorizedManager,
            dockBadgeManager: StubDockBadgeManager(), communityAPIClient: StubStoatAPIClient())
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
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())
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
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())
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
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())
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
        var snapshot = TestShellData.snapshot
        let server = try XCTUnwrap(snapshot.serversByID.values.first { $0.name == "Bagel Lab" })
        snapshot.serversByID[server.id]?.defaultPermissions.insert(.manageCustomisation)
        let model = MainShellViewModel(
            snapshot: snapshot,
            runtimeMode: .mock,
            sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient()
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
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())
        let server = model.servers.first { $0.name == "Bagel Lab" }!

        model.selectServer(server.id)
        model.openInviteManagement()

        XCTAssertTrue(model.isInviteManagementPresented)
        XCTAssertEqual(model.inviteManagementState, .idle)
    }

    @MainActor
    func testPhase25ServerSettingsCategoriesRolesAndCommandsUseMockAPI() async throws {
        var snapshot = TestShellData.snapshot
        let seedServer = snapshot.serversByID.values.first { $0.name == "Bagel Lab" }!
        snapshot.serversByID[seedServer.id]?.defaultPermissions.insert(.manageRole)
        let model = MainShellViewModel(snapshot: snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())
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

}
