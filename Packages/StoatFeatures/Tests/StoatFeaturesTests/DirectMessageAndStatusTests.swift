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
    func testPhase30DMLiveLoadSendAttachmentParticipantsAndAckUseDMChannel() async throws {
        var snapshot = RealtimeSnapshot()
        let currentUserID: UserID = "phase30-me"
        let missingUserID: UserID = "phase30-missing-user"
        let dmID: ChannelID = "phase30-live-dm"
        let liveMessage = Message(id: "01J00000000000000000300002", channelID: dmID, authorID: missingUserID, content: "from live")
        snapshot.usersByID[currentUserID] = User(id: currentUserID, username: "me")
        snapshot.channelsByID[dmID] = Channel(id: dmID, kind: .directMessage, recipients: [currentUserID, missingUserID])
        snapshot.unreadsByChannelID[dmID] = ChannelUnread(id: ChannelCompositeKey(channelID: dmID, userID: currentUserID), lastMessageID: liveMessage.id, mentions: [])
        let api = RecordingAPIClient(currentUser: User(id: currentUserID, username: "me"), messagesByChannel: [dmID: [liveMessage]])
        let controller = ChannelMessageController(runtimeMode: .liveManual, apiClient: api, currentUserID: currentUserID)
        let sender = RecordingChannelAckSender()
        let handler = StubMessageActionHandler(currentUserID: currentUserID)
        let uploader = StubAttachmentUploadHandler()
        let model = MainShellViewModel(
            snapshot: snapshot,
            runtimeMode: .liveManual,
            sessionState: .connected,
            currentUser: snapshot.usersByID[currentUserID],
            messageController: controller,
            messageActionHandler: handler,
            attachmentUploadHandler: uploader,
            channelAckSender: sender, communityAPIClient: StubStoatAPIClient())
        model.timelineTuning.ackDebounceMilliseconds = 0

        model.selectChannel(dmID)
        try? await Task.sleep(for: .milliseconds(40))
        model.updateDraft("with attachment", for: dmID)
        let url = try makeTemporaryAttachment(name: "phase30.txt", contents: Data("dm file".utf8))
        model.addAttachmentURLs([url], to: dmID)
        await model.sendDraft(for: dmID)
        model.updateTimelineAtNewest(true)
        try? await Task.sleep(for: .milliseconds(25))

        let fetchCount = await api.fetchMessagesCallCount
        let sent = await handler.sentMessages
        let acks = await sender.acks
        XCTAssertEqual(fetchCount, 1)
        XCTAssertEqual(model.selectedTimelineMessages.first?.message.channelID, dmID)
        XCTAssertEqual(sent.last?.channelID, dmID)
        XCTAssertEqual(sent.last?.attachments?.count, 1)
        XCTAssertEqual(model.directMessageParticipantItems(for: snapshot.channelsByID[dmID]!).count, 2)
        XCTAssertTrue(model.directMessageParticipantItems(for: snapshot.channelsByID[dmID]!).contains { $0.userID == missingUserID && $0.user == nil })
        XCTAssertEqual(model.dmLiveTrace.messageLoadChannelID, dmID)
        XCTAssertTrue(model.dmLiveTrace.messageLoadUsedREST)
        XCTAssertEqual(model.dmLiveTrace.sidebarParticipantCount, 2)
        XCTAssertEqual(model.currentMessageSendDiagnostics().selectedChannelID, dmID)
        XCTAssertEqual(acks.last?.0, dmID)
    }

    @MainActor
    func testPhase30GroupDMSavedMessagesAndOpenDMKnownChannelStayExplicit() async throws {
        var snapshot = RealtimeSnapshot()
        let currentUserID: UserID = "phase30-me"
        let otherUserID: UserID = "phase30-other"
        let groupID: ChannelID = "phase30-group"
        let dmID: ChannelID = "phase30-known-dm"
        let savedID: ChannelID = "phase30-saved"
        snapshot.usersByID[currentUserID] = User(id: currentUserID, username: "me")
        snapshot.usersByID[otherUserID] = User(id: otherUserID, username: "other")
        snapshot.channelsByID[groupID] = Channel(id: groupID, kind: .group, name: "Group", recipients: [currentUserID, otherUserID])
        snapshot.channelsByID[dmID] = Channel(id: dmID, kind: .directMessage, recipients: [currentUserID, otherUserID])
        snapshot.channelsByID[savedID] = Channel(id: savedID, kind: .savedMessages, userID: currentUserID, recipients: [])
        let model = MainShellViewModel(snapshot: snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: snapshot.usersByID[currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())

        model.selectChannel(groupID)
        XCTAssertEqual(model.activeConversation, .groupDM(channelID: groupID))
        model.selectChannel(savedID)
        XCTAssertEqual(model.activeConversation, .savedMessages(channelID: savedID))
        await model.openDirectMessage(with: otherUserID)

        XCTAssertEqual(model.selection.dmChannelID, dmID)
        XCTAssertEqual(model.snapshot.channelsByID.count, 3)
        XCTAssertEqual(model.dmLiveTrace.clickedUserID, otherUserID)
    }

    func testPhase30DMTraceAndParityDiagnosticsStayRedacted() {
        let trace = DirectMessageLiveTrace(
            clickedRowID: #"https://secret.example/session token=supersecret"#,
            clickedUserID: "phase30-user",
            clickedChannelExistsInSnapshot: false,
            selectedSpaceBefore: "/Users/enka/private/file.png",
            selectedSpaceAfter: "directMessages",
            lastError: #"X-Session-Token: secret {"raw":"body"} https://api.stoat.chat/private"#
        )
        let text = DirectMessageLiveTraceFormatter.redactedText(trace)

        XCTAssertFalse(text.contains("supersecret"))
        XCTAssertFalse(text.contains("X-Session-Token: secret"))
        XCTAssertFalse(text.contains("/Users/enka/private"))
        XCTAssertFalse(text.contains("https://api.stoat.chat/private"))
        XCTAssertFalse(text.contains(#"{"raw":"body"}"#))
    }

    func testPhase54ParityMatrixMatchesDocumentedSectionItemStatuses() throws {
        let matrix = Phase30ParityMatrixBuilder.build()
        let sections = Set(matrix.sections)
        XCTAssertTrue(sections.isSuperset(of: [
            "Account and session",
            "Core chat",
            "Server/community",
            "Notifications",
            "UI/platform",
            "Deferred / not parity"
        ]))
        XCTAssertFalse(matrix.items.contains { $0.status.rawValue.isEmpty })
        let dm = matrix.items.first { $0.section == "Core chat" && $0.name == "DMs" }
        XCTAssertEqual(dm?.status, .partial)
        XCTAssertFalse(matrix.items.contains { item in
            (item.status == .deferred || item.status == .blockedByUnverifiedAPI) && item.recommendedNextAction.isEmpty
        })
        XCTAssertEqual(
            matrix.items.first { $0.section == "Server/community" && $0.name == "server emoji management" }?.status,
            .partial
        )

        var repositoryRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<4 {
            repositoryRoot.deleteLastPathComponent()
        }
        let matrixDocument = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Docs/ParityMatrix.md"),
            encoding: .utf8
        )
        let allowedStatuses = Set(ParityStatus.allCases.map(\.rawValue))
        let documentedRows = Set(matrixDocument.split(separator: "\n").compactMap { line -> String? in
            let columns = line.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard columns.count >= 11, allowedStatuses.contains(columns[3]) else { return nil }
            return "\(columns[1])\u{1F}\(columns[2])\u{1F}\(columns[3])"
        })
        let runtimeRows = Set(matrix.items.map {
            "\($0.section)\u{1F}\($0.name)\u{1F}\($0.status.rawValue)"
        })

        XCTAssertEqual(runtimeRows, documentedRows)
    }

    @MainActor
    func testPhase41UploadFailurePreventsProfileMutation() async throws {
        var snapshot = RealtimeSnapshot()
        let currentUser = User(id: "phase41-me", username: "me", displayName: "Old Name", relationship: .user)
        snapshot.usersByID[currentUser.id] = currentUser
        let api = RecordingAPIClient(currentUser: currentUser, uploadError: StoatAPIError.unknown(statusCode: 400, body: #"{"error":"reject"}"#))
        let model = MainShellViewModel(snapshot: snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: currentUser, messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: api)

        model.prepareProfileEditor(force: true)
        try model.stageProfileMediaData(kind: .avatar, data: Self.phase41PNGData, filename: "/Users/enka/secret/avatar.png", mimeType: "image/png")
        await model.saveProfileEdit()

        let uploadCount = await api.uploadedFiles.count
        let editCount = await api.editUserCallCount
        XCTAssertEqual(uploadCount, 1)
        XCTAssertEqual(editCount, 0)
        XCTAssertNil(model.currentUserForPresentation?.avatar)
        XCTAssertEqual(model.profileEditDiagnostics.safeErrorCategory, .uploadRejected)
        XCTAssertEqual(model.profileEditDiagnostics.mutationResultCategory, .skipped)
    }

    @MainActor
    func testPhase41MutationFailurePreservesPreviousLocalProfileState() async throws {
        var snapshot = RealtimeSnapshot()
        let currentUser = User(id: "phase41-me", username: "me", displayName: "Old Name", relationship: .user)
        snapshot.usersByID[currentUser.id] = currentUser
        let api = RecordingAPIClient(currentUser: currentUser, editUserError: StoatAPIError.serverError(statusCode: 500, message: "nope"))
        let model = MainShellViewModel(snapshot: snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: currentUser, messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: api)
        model.userProfilesByID[currentUser.id] = UserProfile(content: "old bio")

        model.prepareProfileEditor(force: true)
        model.profileEditDraft.displayName = "New Name"
        model.profileEditDraft.profileContent = "new bio"
        await model.saveProfileEdit()

        let editCount = await api.editUserCallCount
        XCTAssertEqual(editCount, 1)
        XCTAssertEqual(model.currentUserForPresentation?.displayName, "Old Name")
        XCTAssertEqual(model.userProfilesByID[currentUser.id]?.content, "old bio")
        XCTAssertEqual(model.profileEditDiagnostics.safeErrorCategory, .server)
        XCTAssertEqual(model.profileEditDiagnostics.mutationResultCategory, .failed)
    }

    @MainActor
    func testPhase41SuccessfulProfileEditMergesSnapshotAndInvalidatesTargetedCaches() async throws {
        var snapshot = RealtimeSnapshot()
        let currentUserID: UserID = "phase41-me"
        let oldAvatar = File(id: "phase41-old-avatar", tag: "avatars", filename: "old.png", contentType: "image/png", size: 1, userID: currentUserID)
        let oldBackground = File(id: "phase41-old-background", tag: "backgrounds", filename: "old-bg.png", contentType: "image/png", size: 1, userID: currentUserID)
        let unrelatedAvatar = File(id: "phase41-unrelated-avatar", tag: "avatars", filename: "other.png", contentType: "image/png", size: 1)
        let currentUser = User(id: currentUserID, username: "me", displayName: "Old Name", avatar: oldAvatar, relationship: .user)
        let channelID: ChannelID = "phase41-saved"
        let message = Message(id: "phase41-message", channelID: channelID, authorID: currentUserID, content: "hello")
        snapshot.usersByID[currentUserID] = currentUser
        snapshot.channelsByID[channelID] = Channel(id: channelID, kind: .savedMessages, userID: currentUserID, active: true)
        snapshot.messagesByChannelID[channelID] = [message]
        let api = RecordingAPIClient(
            currentUser: currentUser,
            uploadedFileIDsByTag: [.avatars: "phase41-new-avatar", .backgrounds: "phase41-new-background"]
        )
        let model = MainShellViewModel(snapshot: snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: currentUser, messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: api)
        model.userProfilesByID[currentUserID] = UserProfile(content: "old bio", background: oldBackground)
        model.loadedImageResources[ImageCacheKey(id: oldAvatar.id.rawValue, kind: .userAvatar)] = Data("old-avatar".utf8)
        model.loadedImageResources[ImageCacheKey(id: oldBackground.id.rawValue, kind: .profileBackground)] = Data("old-background".utf8)
        model.loadedImageResources[ImageCacheKey(id: unrelatedAvatar.id.rawValue, kind: .userAvatar)] = Data("keep".utf8)

        model.prepareProfileEditor(force: true)
        model.profileEditDraft.displayName = "New Name"
        model.profileEditDraft.profileContent = "new bio"
        try model.stageProfileMediaData(kind: .avatar, data: Self.phase41PNGData, filename: "avatar.png", mimeType: "image/png")
        try model.stageProfileMediaData(kind: .background, data: Self.phase41PNGData, filename: "banner.png", mimeType: "image/png")
        await model.saveProfileEdit()

        let editCount = await api.editUserCallCount
        let uploadedTags = await api.uploadedFiles.map(\.tag)
        XCTAssertEqual(editCount, 1)
        XCTAssertEqual(uploadedTags, [.avatars, .backgrounds])
        XCTAssertEqual(model.currentUserForPresentation?.displayName, "New Name")
        XCTAssertEqual(model.resolvedUserDisplay(for: message).displayName, "New Name")
        XCTAssertEqual(model.directMessageParticipantItems(for: snapshot.channelsByID[channelID]!).first?.displayName, "New Name")
        XCTAssertEqual(model.userProfilesByID[currentUserID]?.content, "new bio")
        XCTAssertEqual(model.userProfilesByID[currentUserID]?.background?.id, "phase41-new-background")
        XCTAssertNil(model.loadedImageResources[ImageCacheKey(id: oldAvatar.id.rawValue, kind: .userAvatar)])
        XCTAssertNil(model.loadedImageResources[ImageCacheKey(id: oldBackground.id.rawValue, kind: .profileBackground)])
        XCTAssertEqual(model.loadedImageResources[ImageCacheKey(id: unrelatedAvatar.id.rawValue, kind: .userAvatar)], Data("keep".utf8))
        XCTAssertNotNil(model.loadedImageResources[ImageCacheKey(id: "phase41-new-avatar", kind: .userAvatar)])
        XCTAssertNotNil(model.loadedImageResources[ImageCacheKey(id: "phase41-new-background", kind: .profileBackground)])
        XCTAssertEqual(model.profileEditDiagnostics.cacheInvalidationCount, 4)
        XCTAssertEqual(model.profileEditDiagnostics.returnedDataShape, .fullUser)
    }

    @MainActor
    func testPhase41ProfileEditorDirtyStateAndSaveEnablement() {
        var snapshot = RealtimeSnapshot()
        let avatar = File(id: "phase41-avatar", tag: "avatars", filename: "avatar.png", contentType: "image/png", size: 1)
        let currentUser = User(id: "phase41-me", username: "me", displayName: "Old Name", avatar: avatar, relationship: .user)
        snapshot.usersByID[currentUser.id] = currentUser
        let model = MainShellViewModel(snapshot: snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: currentUser, messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())

        model.prepareProfileEditor(force: true)
        XCTAssertFalse(model.profileEditDraft.isDirty)
        XCTAssertFalse(model.canSaveProfileEdit)

        model.profileEditDraft.displayName = "New Name"
        XCTAssertTrue(model.profileEditDraft.isDirty)
        XCTAssertTrue(model.canSaveProfileEdit)

        model.cancelProfileEdit()
        XCTAssertFalse(model.profileEditDraft.isDirty)
        model.removeProfileAvatar()
        XCTAssertTrue(model.profileEditDraft.isDirty)
        XCTAssertTrue(model.canSaveProfileEdit)
    }

    func testPhase41SafeErrorCategoryMapping() {
        XCTAssertEqual(ProfileEditSafeErrorCategory.categorize(StoatAPIError.unauthorized), .unauthenticated)
        XCTAssertEqual(ProfileEditSafeErrorCategory.categorize(StoatAPIError.forbidden), .forbidden)
        XCTAssertEqual(ProfileEditSafeErrorCategory.categorize(StoatAPIError.rateLimited(retryAfterMilliseconds: 1)), .rateLimited)
        XCTAssertEqual(ProfileEditSafeErrorCategory.categorize(StoatAPIError.transport("offline")), .network)
        XCTAssertEqual(ProfileEditSafeErrorCategory.categorize(StoatAPIError.serverError(statusCode: 503, message: nil)), .server)
        XCTAssertEqual(ProfileEditSafeErrorCategory.categorize(StoatAPIError.decodingFailed("bad")), .decode)
        XCTAssertEqual(ProfileEditSafeErrorCategory.categorize(ProfileEditValidationError.fileTooLarge(maxBytes: 4)), .fileTooLarge)
        XCTAssertEqual(ProfileEditSafeErrorCategory.categorize(ProfileEditValidationError.unsupportedFileType), .unsupportedFileType)
        XCTAssertEqual(ProfileEditSafeErrorCategory.uploadCategory(StoatAPIError.unknown(statusCode: 400, body: "raw")), .uploadRejected)
    }

    func testPhase41DiagnosticsRedactionDropsSecretsIDsPathsURLsAndUserContent() {
        let secretBio = "private profile bio text"
        let diagnostics = ProfileEditDiagnostics(
            lastAction: "save succeeded",
            routeCategory: .currentUserPatch,
            editedFieldCategories: [.displayName, .profileContent, .avatar, .profileBackground],
            uploadTagCategory: .multiple,
            uploadResultCategory: .succeeded,
            mutationResultCategory: .succeeded,
            durationMilliseconds: 42,
            cacheInvalidationCount: 2,
            returnedDataShape: .fullUser
        )
        let text = ProfileEditDiagnosticsFormatter.redactedText(diagnostics)
        let redacted = ProfileEditDiagnosticsFormatter.redactSensitiveText("""
        X-Session-Token: supersecret
        token=secret-token
        session_id=01J12345678901234567890123
        file id 01JFILE123456789012345678
        user id 01JUSER123456789012345678
        /Users/enka/private/file.png
        https://api.stoat.chat/users/@me
        user@example.com
        password hunter2
        mfa response ticket-secret
        {"content":"\(secretBio)","token":"secret"}
        """)

        XCTAssertFalse(text.contains(secretBio))
        XCTAssertFalse(redacted.contains("supersecret"))
        XCTAssertFalse(redacted.contains("secret-token"))
        XCTAssertFalse(redacted.contains("01J12345678901234567890123"))
        XCTAssertFalse(redacted.contains("01JFILE123456789012345678"))
        XCTAssertFalse(redacted.contains("01JUSER123456789012345678"))
        XCTAssertFalse(redacted.contains("/Users/enka/private"))
        XCTAssertFalse(redacted.contains("https://api.stoat.chat"))
        XCTAssertFalse(redacted.contains("user@example.com"))
        XCTAssertFalse(redacted.contains("hunter2"))
        XCTAssertFalse(redacted.contains("ticket-secret"))
        XCTAssertFalse(redacted.contains(secretBio))
    }

    func testPhase41ParityRowsRemainPartialUntilLiveQA() {
        let matrix = Phase30ParityMatrixBuilder.build()
        let profileEdit = matrix.items.first { $0.section == "Account and session" && $0.name == "account profile edit" }
        let avatarEdit = matrix.items.first { $0.section == "Account and session" && $0.name == "avatar edit" }
        let backgroundEdit = matrix.items.first { $0.section == "Account and session" && $0.name == "profile banner/background edit" }

        XCTAssertEqual(profileEdit?.status, .partial)
        XCTAssertEqual(avatarEdit?.status, .partial)
        XCTAssertEqual(backgroundEdit?.status, .partial)
        XCTAssertFalse([profileEdit, avatarEdit, backgroundEdit].contains { $0?.status == .done })
    }

    @MainActor
    func testPhase55CustomStatusTextSetPatchesStatusAndPreservesPresence() async {
        var snapshot = RealtimeSnapshot()
        let currentUser = User(id: "phase55-me", username: "me", status: UserStatus(text: nil, presence: .idle), relationship: .user)
        snapshot.usersByID[currentUser.id] = currentUser
        let api = RecordingAPIClient(currentUser: currentUser)
        let model = MainShellViewModel(snapshot: snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: currentUser, messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: api)

        model.customStatusDraft = "  Reviewing bagels  "
        await model.submitCustomStatusDraft()

        let drafts = await api.editedUserDrafts
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts.first?.1.status?.text, "Reviewing bagels")
        XCTAssertEqual(drafts.first?.1.status?.presence, .idle)
        XCTAssertTrue(drafts.first?.1.remove.isEmpty ?? false)
        XCTAssertEqual(model.currentUserForPresentation?.status?.text, "Reviewing bagels")
        XCTAssertEqual(model.currentUserForPresentation?.status?.presence, .idle)
        XCTAssertFalse(model.isPresentingCustomStatusEditor)
    }

    @MainActor
    func testPhase55CustomStatusClearUsesRemoveStatusTextField() async {
        var snapshot = RealtimeSnapshot()
        let currentUser = User(id: "phase55-me", username: "me", status: UserStatus(text: "old status", presence: .online), relationship: .user)
        snapshot.usersByID[currentUser.id] = currentUser
        let api = RecordingAPIClient(currentUser: currentUser)
        let model = MainShellViewModel(snapshot: snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: currentUser, messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: api)

        await model.clearCustomStatus()

        let drafts = await api.editedUserDrafts
        XCTAssertEqual(drafts.count, 1)
        XCTAssertNil(drafts.first?.1.status)
        XCTAssertEqual(drafts.first?.1.remove, [.statusText])
        XCTAssertNil(model.currentUserForPresentation?.status?.text)
        XCTAssertEqual(model.currentUserForPresentation?.status?.presence, .online)
    }

    @MainActor
    func testPhase55CustomStatusFailureRollsBackOptimisticText() async {
        var snapshot = RealtimeSnapshot()
        let currentUser = User(id: "phase55-me", username: "me", status: UserStatus(text: "keep me", presence: .online), relationship: .user)
        snapshot.usersByID[currentUser.id] = currentUser
        let api = RecordingAPIClient(currentUser: currentUser, editUserError: StoatAPIError.serverError(statusCode: 500, message: "nope"))
        let model = MainShellViewModel(snapshot: snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: currentUser, messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: api)

        await model.setCurrentUserStatusText("new text")

        let editCount = await api.editUserCallCount
        XCTAssertEqual(editCount, 1)
        XCTAssertEqual(model.currentUserForPresentation?.status?.text, "keep me")
        // Phase 74: the failure is reported in plain language rather than by interpolating the
        // raw API error, so assert it is present and carries no diagnostic detail.
        let status = model.statusUpdateStatus ?? ""
        XCTAssertFalse(status.isEmpty)
        XCTAssertFalse(status.contains("500"))
        XCTAssertFalse(status.lowercased().contains("http"))
    }

    @MainActor
    func testPhase55CustomStatusOverLimitAndUnchangedDraftsDoNotMutate() async {
        var snapshot = RealtimeSnapshot()
        let currentUser = User(id: "phase55-me", username: "me", status: UserStatus(text: "same", presence: .online), relationship: .user)
        snapshot.usersByID[currentUser.id] = currentUser
        let api = RecordingAPIClient(currentUser: currentUser)
        let model = MainShellViewModel(snapshot: snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: currentUser, messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: api)

        model.openCustomStatusEditor()
        XCTAssertEqual(model.customStatusDraft, "same")
        XCTAssertTrue(model.isPresentingCustomStatusEditor)

        model.customStatusDraft = String(repeating: "x", count: MainShellViewModel.customStatusTextLimit + 1)
        await model.submitCustomStatusDraft()
        XCTAssertTrue(model.isPresentingCustomStatusEditor)

        model.customStatusDraft = "same"
        await model.submitCustomStatusDraft()

        let editCount = await api.editUserCallCount
        XCTAssertEqual(editCount, 0)
        XCTAssertFalse(model.isPresentingCustomStatusEditor)
    }

    @MainActor
    func testPhase55CreateGroupMergesChannelAndSelectsConversation() async {
        var snapshot = RealtimeSnapshot()
        let currentUser = User(id: "phase55-me", username: "me", relationship: .user)
        snapshot.usersByID[currentUser.id] = currentUser
        let api = RecordingAPIClient(currentUser: currentUser)
        let model = MainShellViewModel(snapshot: snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: currentUser, messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: api)

        model.openNewGroup()
        XCTAssertTrue(model.isPresentingNewGroup)
        model.groupCreateName = " Bagel Crew "
        model.toggleNewGroupCandidate("phase55-friend-b")
        model.toggleNewGroupCandidate("phase55-friend-a")
        await model.createGroupFromDraft()

        let drafts = await api.createdGroupDrafts
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts.first?.name, "Bagel Crew")
        XCTAssertEqual(drafts.first?.users, ["phase55-friend-a", "phase55-friend-b"])
        guard case let .created(channelID) = model.groupCreateState else {
            XCTFail("Expected created state, got \(model.groupCreateState)")
            return
        }
        XCTAssertFalse(model.isPresentingNewGroup)
        XCTAssertEqual(model.selectedConversationChannelID, channelID)
        XCTAssertEqual(model.snapshot.channelsByID[channelID]?.kind, .group)
        XCTAssertEqual(model.snapshot.channelsByID[channelID]?.name, "Bagel Crew")
        XCTAssertTrue(model.groupCreateName.isEmpty)
        XCTAssertTrue(model.groupCreateSelectedUserIDs.isEmpty)
    }

    @MainActor
    func testPhase55CreateGroupFailureKeepsDraftAndReportsSafeError() async {
        var snapshot = RealtimeSnapshot()
        let currentUser = User(id: "phase55-me", username: "me", relationship: .user)
        snapshot.usersByID[currentUser.id] = currentUser
        let api = RecordingAPIClient(
            currentUser: currentUser,
            createGroupError: StoatAPIError.serverError(statusCode: 500, message: "nope")
        )
        let model = MainShellViewModel(snapshot: snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: currentUser, messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: api)

        model.openNewGroup()
        model.groupCreateName = "Bagel Crew"
        model.toggleNewGroupCandidate("phase55-friend-a")
        await model.createGroupFromDraft()

        guard case let .failed(message) = model.groupCreateState else {
            XCTFail("Expected failed state, got \(model.groupCreateState)")
            return
        }
        XCTAssertFalse(message.contains("500"))
        XCTAssertTrue(model.isPresentingNewGroup)
        XCTAssertEqual(model.groupCreateName, "Bagel Crew")
        XCTAssertEqual(model.groupCreateSelectedUserIDs, ["phase55-friend-a"])

        model.groupCreateName = "   "
        await model.createGroupFromDraft()
        let draftCount = await api.createdGroupDrafts.count
        XCTAssertEqual(draftCount, 1)
        if case .failed = model.groupCreateState {} else {
            XCTFail("Empty group name should fail validation")
        }
    }

    @MainActor
    func testPhase58AddGroupMemberOptimisticAppendAndGatewayEchoDeduplicates() async {
        let currentUser = User(id: "phase58-me", username: "me", relationship: .user)
        let groupID = ChannelID(rawValue: "phase58-group")
        var snapshot = RealtimeSnapshot()
        snapshot.usersByID[currentUser.id] = currentUser
        snapshot.channelsByID[groupID] = Channel(id: groupID, kind: .group, name: "Bagel Crew", ownerID: currentUser.id, active: true, recipients: [currentUser.id])
        let api = RecordingAPIClient(currentUser: currentUser)
        let model = MainShellViewModel(snapshot: snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: currentUser, messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: api)

        model.openAddGroupMembers(for: groupID)
        XCTAssertTrue(model.isPresentingAddGroupMembers)
        model.toggleAddGroupMemberCandidate("phase58-friend-a")
        await model.addSelectedGroupMembers()

        let added = await api.addedGroupRecipients
        XCTAssertEqual(added.count, 1)
        XCTAssertEqual(added.first?.0, groupID)
        XCTAssertEqual(added.first?.1, "phase58-friend-a")
        XCTAssertEqual(model.snapshot.channelsByID[groupID]?.recipients, [currentUser.id, "phase58-friend-a"])
        XCTAssertFalse(model.isPresentingAddGroupMembers)

        // Re-running the add for the same now-present recipient (as a realtime ChannelGroupJoin
        // echo would trigger through the same optimistic-append guard) must not duplicate.
        model.openAddGroupMembers(for: groupID)
        model.toggleAddGroupMemberCandidate("phase58-friend-a")
        await model.addSelectedGroupMembers()
        XCTAssertEqual(model.snapshot.channelsByID[groupID]?.recipients, [currentUser.id, "phase58-friend-a"])
    }

    @MainActor
    func testPhase58AddGroupMemberFailureKeepsSheetOpenAndReportsSafeError() async {
        let currentUser = User(id: "phase58-me", username: "me", relationship: .user)
        let groupID = ChannelID(rawValue: "phase58-group")
        var snapshot = RealtimeSnapshot()
        snapshot.usersByID[currentUser.id] = currentUser
        snapshot.channelsByID[groupID] = Channel(id: groupID, kind: .group, name: "Bagel Crew", ownerID: currentUser.id, active: true, recipients: [currentUser.id])
        let api = RecordingAPIClient(currentUser: currentUser, addGroupRecipientError: StoatAPIError.forbidden)
        let model = MainShellViewModel(snapshot: snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: currentUser, messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: api)

        model.openAddGroupMembers(for: groupID)
        model.toggleAddGroupMemberCandidate("phase58-not-a-friend")
        await model.addSelectedGroupMembers()

        guard case .failed = model.groupMembershipActionState else {
            XCTFail("Expected failed state, got \(model.groupMembershipActionState)")
            return
        }
        XCTAssertTrue(model.isPresentingAddGroupMembers)
        XCTAssertEqual(model.snapshot.channelsByID[groupID]?.recipients, [currentUser.id])
    }

    @MainActor
    func testPhase58RemoveGroupMemberIsOwnerGatedAndConfirmed() async {
        let currentUser = User(id: "phase58-owner", username: "owner", relationship: .user)
        let groupID = ChannelID(rawValue: "phase58-group")
        var snapshot = RealtimeSnapshot()
        snapshot.usersByID[currentUser.id] = currentUser
        snapshot.channelsByID[groupID] = Channel(id: groupID, kind: .group, name: "Bagel Crew", ownerID: currentUser.id, active: true, recipients: [currentUser.id, "phase58-member-a"])
        let api = RecordingAPIClient(currentUser: currentUser)
        let model = MainShellViewModel(snapshot: snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: currentUser, messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: api)

        // Self-removal must never be requestable through this path.
        model.requestRemoveGroupMember(currentUser.id, from: groupID, displayName: "Me")
        XCTAssertNil(model.pendingGroupMemberRemoval)

        model.requestRemoveGroupMember("phase58-member-a", from: groupID, displayName: "Member A")
        XCTAssertEqual(model.pendingGroupMemberRemoval?.userID, "phase58-member-a")

        await model.confirmRemoveGroupMember()

        let removed = await api.removedGroupRecipients
        XCTAssertEqual(removed.count, 1)
        XCTAssertEqual(removed.first?.0, groupID)
        XCTAssertEqual(removed.first?.1, "phase58-member-a")
        XCTAssertEqual(model.snapshot.channelsByID[groupID]?.recipients, [currentUser.id])
        XCTAssertNil(model.pendingGroupMemberRemoval)
    }

    @MainActor
    func testPhase58RemoveGroupMemberBlockedForNonOwner() async {
        let currentUser = User(id: "phase58-non-owner", username: "notowner", relationship: .user)
        let ownerID = UserID(rawValue: "phase58-owner")
        let groupID = ChannelID(rawValue: "phase58-group")
        var snapshot = RealtimeSnapshot()
        snapshot.usersByID[currentUser.id] = currentUser
        snapshot.channelsByID[groupID] = Channel(id: groupID, kind: .group, name: "Bagel Crew", ownerID: ownerID, active: true, recipients: [ownerID, currentUser.id, "phase58-member-a"])
        let api = RecordingAPIClient(currentUser: currentUser)
        let model = MainShellViewModel(snapshot: snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: currentUser, messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: api)

        model.requestRemoveGroupMember("phase58-member-a", from: groupID, displayName: "Member A")
        XCTAssertNil(model.pendingGroupMemberRemoval, "Only the group owner may request removal of another member")

        let removed = await api.removedGroupRecipients
        XCTAssertTrue(removed.isEmpty)
    }

    @MainActor
    func testPhase58AddCandidatesExcludeExistingRecipients() {
        let currentUser = User(id: "phase58-me", username: "me", relationship: .user)
        let existingFriend = User(id: "phase58-friend-existing", username: "already-in", relationship: .user)
        let newFriend = User(id: "phase58-friend-new", username: "not-in-yet", relationship: .user)
        let groupID = ChannelID(rawValue: "phase58-group")
        var friendedCurrentUser = currentUser
        friendedCurrentUser.relations = [
            Relationship(id: existingFriend.id, status: .friend),
            Relationship(id: newFriend.id, status: .friend)
        ]
        var snapshot = RealtimeSnapshot()
        snapshot.usersByID[currentUser.id] = friendedCurrentUser
        snapshot.usersByID[existingFriend.id] = existingFriend
        snapshot.usersByID[newFriend.id] = newFriend
        snapshot.channelsByID[groupID] = Channel(id: groupID, kind: .group, name: "Bagel Crew", ownerID: currentUser.id, active: true, recipients: [currentUser.id, existingFriend.id])
        let model = MainShellViewModel(snapshot: snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: friendedCurrentUser, messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())

        let candidates = model.addGroupMemberCandidates(for: groupID)
        XCTAssertEqual(candidates.map(\.user.id), [newFriend.id])
    }

    func testPhase58RowPresentationResolvesMentionItemsCacheOnly() {
        let authorID: UserID = "phase58-author"
        let mentionedID: UserID = "01FD58YK5W7QRV5H3D64KTQYX3"
        let channelID: ChannelID = "phase58-mention-channel"
        var snapshot = RealtimeSnapshot()
        snapshot.usersByID[mentionedID] = User(id: mentionedID, username: "enka", displayName: "Enka")
        snapshot.channelsByID[channelID] = Channel(id: channelID, kind: .textChannel, name: "general")
        let message = Message(
            id: "01J00000000000000000580001",
            channelID: channelID,
            authorID: authorID,
            content: "hi <@\(mentionedID.rawValue)>"
        )

        let context = Phase52TimelineAssetContext(snapshot: snapshot, imageDataByKey: [:])
        let items = context.inlineReferenceItems(
            for: message,
            identitySnapshots: Phase43IdentitySnapshotStore(),
            currentUserID: authorID
        )

        let item = try? XCTUnwrap(items["<@\(mentionedID.rawValue)>"])
        XCTAssertEqual(item?.displayName, "Enka")
        XCTAssertEqual(item?.isFallback, false)
        XCTAssertEqual(item?.isCurrentUser, false)
    }

    func testPhase58UnresolvedMentionInPipelineProducesFallbackItem() {
        let channelID: ChannelID = "phase58-mention-channel-2"
        var snapshot = RealtimeSnapshot()
        snapshot.channelsByID[channelID] = Channel(id: channelID, kind: .textChannel, name: "general")
        let unknownID = "01FD58YK5W7QRV5H3D64KTQYX9"
        let message = Message(
            id: "01J00000000000000000580002",
            channelID: channelID,
            authorID: "phase58-author",
            content: "hi <@\(unknownID)>"
        )

        let context = Phase52TimelineAssetContext(snapshot: snapshot, imageDataByKey: [:])
        let items = context.inlineReferenceItems(
            for: message,
            identitySnapshots: Phase43IdentitySnapshotStore(),
            currentUserID: nil
        )

        let item = try? XCTUnwrap(items["<@\(unknownID)>"])
        XCTAssertEqual(item?.displayName, "Unknown member")
        XCTAssertEqual(item?.isFallback, true)
    }

}
