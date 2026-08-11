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
    func testComposerDraftsSendSuccessAndEchoDedupe() async {
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())
        let server = model.servers.first { $0.name == "Bagel Lab" }!
        model.selectServer(server.id)
        let channelID = model.selection.channelID!
        model.updateDraft("hello", for: channelID)

        await model.sendDraft(for: channelID)
        let sent = model.selectedTimelineMessages.filter { $0.message.content == "hello" }

        XCTAssertEqual(model.draft(for: channelID), "")
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?.status, .confirmed)
        XCTAssertNil(model.messageActionStatus)

        model.messageController.hydrate(from: RealtimeSnapshot(messagesByChannelID: [channelID: sent.map(\.message)]))
        XCTAssertEqual(model.selectedTimelineMessages.filter { $0.message.content == "hello" }.count, 1)
    }

    @MainActor
    func testPhase56OptimisticAndConfirmedSendGroupsPaintWithoutPreparationPass() async throws {
        let handler = DelayedMessageActionHandler(delay: .milliseconds(80))
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: handler, communityAPIClient: StubStoatAPIClient())
        let server = try XCTUnwrap(model.servers.first { $0.name == "Bagel Lab" })
        model.selectServer(server.id)
        let channelID = try XCTUnwrap(model.selection.channelID)
        model.updateDraft("paint immediately", for: channelID)
        let tokenBeforeSend = model.selectedTimelineGroupingToken

        let sendTask = Task { await model.sendDraft(for: channelID) }
        try await Task.sleep(for: .milliseconds(10))

        let optimistic = model.selectedTimelineMessageGroups
            .flatMap(\.messages)
            .first { $0.message.content == "paint immediately" }
        XCTAssertEqual(optimistic?.status, .pending)
        XCTAssertNotEqual(model.selectedTimelineGroupingToken, tokenBeforeSend)

        await sendTask.value
        let confirmed = model.selectedTimelineMessageGroups
            .flatMap(\.messages)
            .first { $0.message.content == "paint immediately" }
        XCTAssertEqual(confirmed?.status, .confirmed)
    }

    @MainActor
    func testPhase61LocalSendPreservesWarmAvatarIdentityAcrossReconciliation() async throws {
        var snapshot = TestShellData.snapshot
        let server = try XCTUnwrap(snapshot.serversByID.values.first { $0.name == "Bagel Lab" })
        let channelID = try XCTUnwrap(snapshot.channelsByID.values.first { $0.displayName == "general" }?.id)
        let userAvatar = File(id: "phase61-user-avatar", tag: "avatars", filename: "user.png", contentType: "image/png", size: 8)
        let memberAvatar = File(id: "phase61-member-avatar", tag: "avatars", filename: "member.png", contentType: "image/png", size: 8)
        snapshot.usersByID[TestShellData.currentUserID]?.avatar = userAvatar
        snapshot.membersByServerAndUserID[ServerMemberKey(serverID: server.id, userID: TestShellData.currentUserID)]?.avatar = memberAvatar

        let handler = DelayedMessageActionHandler(delay: .milliseconds(80))
        let model = MainShellViewModel(snapshot: snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: handler, communityAPIClient: StubStoatAPIClient())
        model.selectServer(server.id)
        model.updateDraft("avatar continuity", for: channelID)

        let sendTask = Task { await model.sendDraft(for: channelID) }
        try await Task.sleep(for: .milliseconds(10))

        let pending = try XCTUnwrap(model.selectedTimelineMessages.first { $0.message.content == "avatar continuity" })
        XCTAssertEqual(pending.status, .pending)
        XCTAssertEqual(pending.message.user?.avatar?.id, userAvatar.id)
        XCTAssertEqual(pending.message.member?.avatar?.id, memberAvatar.id)
        XCTAssertEqual(model.pendingRowFallbackPresentation(for: pending)?.authorDisplay.avatarFile?.id, memberAvatar.id)

        await sendTask.value

        let confirmed = try XCTUnwrap(model.selectedTimelineMessages.first { $0.message.content == "avatar continuity" })
        XCTAssertEqual(confirmed.status, .confirmed)
        XCTAssertEqual(confirmed.message.user?.avatar?.id, userAvatar.id)
        XCTAssertEqual(confirmed.message.member?.avatar?.id, memberAvatar.id)
        XCTAssertEqual(model.pendingRowFallbackPresentation(for: confirmed)?.authorDisplay.avatarFile?.id, memberAvatar.id)
    }

    @MainActor
    func testFailedSendMarksTimelineMessageFailed() async {
        let handler = StubMessageActionHandler(sendError: MessageActionError.unavailable("send failed"))
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: handler, communityAPIClient: StubStoatAPIClient())
        let server = model.servers.first { $0.name == "Bagel Lab" }!
        model.selectServer(server.id)
        let channelID = model.selection.channelID!
        model.updateDraft("hello", for: channelID)

        await model.sendDraft(for: channelID)

        XCTAssertTrue(model.selectedTimelineMessages.contains { if case .failed = $0.status { true } else { false } })
    }

    @MainActor
    func testDraftsArePerChannelAndEmptyDraftCannotSend() async {
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())
        let channels = model.channels(for: model.servers.first { $0.name == "Bagel Lab" }!.id).filter { $0.kind == .textChannel }

        model.updateDraft("one", for: channels[0].id)
        model.updateDraft("two", for: channels[1].id)

        XCTAssertEqual(model.draft(for: channels[0].id), "one")
        XCTAssertEqual(model.draft(for: channels[1].id), "two")
        XCTAssertFalse(model.composerReadiness(for: channels[0].id).canSend == false)

        model.updateDraft("   ", for: channels[0].id)
        XCTAssertFalse(model.composerReadiness(for: channels[0].id).canSend)
    }

    @MainActor
    func testPhase32EmojiInsertionAppendsToComposerDraft() {
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())
        let channelID = model.snapshot.channelsByID.values.first { $0.displayName == "general" }!.id

        model.updateDraft("hello", for: channelID)
        model.insertEmoji("🎉", in: channelID)

        XCTAssertEqual(model.draft(for: channelID), "hello🎉")
        XCTAssertTrue(model.commonEmojiItems.contains("🎉"))
        XCTAssertEqual(model.emojiPickerDiagnostics, "Inserted Unicode emoji")
    }

    @MainActor
    func testPhase15AttachmentQueueDoesNotUploadUntilExplicitAction() async throws {
        let uploader = StubAttachmentUploadHandler()
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), attachmentUploadHandler: uploader, communityAPIClient: StubStoatAPIClient())
        let channelID = model.snapshot.channelsByID.values.first { $0.displayName == "general" }!.id
        let url = try makeTemporaryAttachment(name: "note.txt", contents: Data("hello".utf8))

        model.addAttachmentURLs([url], to: channelID)

        XCTAssertEqual(model.composerDraftState(for: channelID).attachments.count, 1)
        let initialUploadCount = await uploader.uploadCount()
        XCTAssertEqual(initialUploadCount, 0)
        XCTAssertTrue(model.composerReadiness(for: channelID).canSend)

        await model.uploadQueuedAttachments(for: channelID)

        let finalUploadCount = await uploader.uploadCount()
        XCTAssertEqual(finalUploadCount, 1)
        XCTAssertNotNil(model.composerDraftState(for: channelID).attachments.first?.uploadedFileID)
    }

    @MainActor
    func testPhase32DroppedFilesOpenReviewBeforeQueueingOrUploading() async throws {
        let uploader = StubAttachmentUploadHandler()
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), attachmentUploadHandler: uploader, communityAPIClient: StubStoatAPIClient())
        let channelID = model.snapshot.channelsByID.values.first { $0.displayName == "general" }!.id
        let url = try makeTemporaryAttachment(name: "phase32 dropped.txt", contents: Data("drop".utf8))

        model.reviewDroppedAttachmentURLs([url], to: channelID)

        let review = try XCTUnwrap(model.pendingAttachmentDrop)
        XCTAssertEqual(review.channelID, channelID)
        XCTAssertEqual(review.items.count, 1)
        XCTAssertTrue(review.items.first?.filename.hasSuffix("phase32 dropped.txt") == true)
        XCTAssertFalse(review.items.first?.filename.contains(FileManager.default.temporaryDirectory.path) == true)
        XCTAssertTrue(review.canAddToMessage)
        XCTAssertTrue(model.composerDraftState(for: channelID).attachments.isEmpty)
        let uploadCountAfterDrop = await uploader.uploadCount()
        XCTAssertEqual(uploadCountAfterDrop, 0)

        model.addPendingDroppedAttachmentsToComposer()

        XCTAssertNil(model.pendingAttachmentDrop)
        XCTAssertEqual(model.composerDraftState(for: channelID).attachments.count, 1)
        let uploadCountAfterAdd = await uploader.uploadCount()
        XCTAssertEqual(uploadCountAfterAdd, 0)
    }

    @MainActor
    func testPhase32DroppedFilesWithoutSendableTargetShowBlockedReview() async throws {
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())
        let url = try makeTemporaryAttachment(name: "phase32 blocked.txt", contents: Data("blocked".utf8))

        model.reviewDroppedAttachmentURLs([url], to: nil)

        let review = try XCTUnwrap(model.pendingAttachmentDrop)
        XCTAssertNil(review.channelID)
        XCTAssertTrue(review.blockedReason?.contains("Select a channel") == true)
        XCTAssertFalse(review.canAddToMessage)
        XCTAssertTrue(review.items.first?.filename.hasSuffix("phase32 blocked.txt") == true)
        model.cancelPendingAttachmentDrop()
        XCTAssertNil(model.pendingAttachmentDrop)
    }

    @MainActor
    func testPhase15AttachmentValidationAndPermissionGate() async throws {
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())
        let channelID = model.snapshot.channelsByID.values.first { $0.displayName == "general" }!.id
        let oversized = try makeTemporaryAttachment(name: "large.txt", contents: Data(repeating: 1, count: 21 * 1024 * 1024))

        model.addAttachmentURLs([oversized], to: channelID)

        XCTAssertTrue(model.composerDraftState(for: channelID).attachments.isEmpty)
        XCTAssertEqual(model.composerError, "File too large. Liquid Bagel currently supports files up to 20 MB.")

        var snapshot = TestShellData.snapshot
        snapshot.channelsByID[channelID]?.permissions = [.viewChannel, .readMessageHistory, .sendMessage]
        let permissionModel = MainShellViewModel(snapshot: snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())
        XCTAssertFalse(permissionModel.canUploadFiles(in: permissionModel.snapshot.channelsByID[channelID]))
    }

    @MainActor
    func testPhase33UploadLimitBoundaryAndPasteReviewDoNotUpload() async throws {
        let uploader = StubAttachmentUploadHandler()
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), attachmentUploadHandler: uploader, communityAPIClient: StubStoatAPIClient())
        let channelID = model.snapshot.channelsByID.values.first { $0.displayName == "general" }!.id
        let exact = try makeTemporaryAttachment(name: "exact-20mb.txt", contents: Data(repeating: 1, count: AttachmentUploadLimits.maxFileBytes))
        let over = try makeTemporaryAttachment(name: "over-20mb.txt", contents: Data(repeating: 1, count: AttachmentUploadLimits.maxFileBytes + 1))

        model.reviewDroppedAttachmentURLs([exact, over], to: channelID)

        let review = try XCTUnwrap(model.pendingAttachmentDrop)
        XCTAssertEqual(review.attachableItems.count, 1)
        XCTAssertEqual(review.items.filter { $0.warning != nil }.first?.warning, "File too large. Liquid Bagel currently supports files up to 20 MB.")
        let uploadCountBeforeQueue = await uploader.uploadCount()
        XCTAssertEqual(uploadCountBeforeQueue, 0)

        model.addPendingDroppedAttachmentsToComposer()
        XCTAssertEqual(model.composerDraftState(for: channelID).attachments.count, 1)
        let uploadCountAfterQueue = await uploader.uploadCount()
        XCTAssertEqual(uploadCountAfterQueue, 0)
    }

    @MainActor
    func testPhase61PastedImageQueuesComposerAttachmentWithoutUploading() async throws {
        let uploader = StubAttachmentUploadHandler()
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), attachmentUploadHandler: uploader, communityAPIClient: StubStoatAPIClient())
        let channelID = model.snapshot.channelsByID.values.first { $0.displayName == "general" }!.id

        model.addPastedImageData(Data(repeating: 2, count: 32), to: channelID)

        XCTAssertNil(model.pendingAttachmentDrop)
        let attachment = try XCTUnwrap(model.composerDraftState(for: channelID).attachments.first)
        XCTAssertEqual(attachment.filename, "Pasted Image.png")
        XCTAssertEqual(attachment.kind, .image)
        XCTAssertEqual(attachment.previewData, Data(repeating: 2, count: 32))
        let uploadCount = await uploader.uploadCount()
        XCTAssertEqual(uploadCount, 0)
    }

    @MainActor
    func testPhase61PastedImageCanSendAttachmentOnly() async throws {
        let uploader = StubAttachmentUploadHandler()
        let handler = RecordingAttachmentMessageActionHandler()
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: handler, attachmentUploadHandler: uploader, communityAPIClient: StubStoatAPIClient())
        let server = model.servers.first { $0.name == "Bagel Lab" }!
        model.selectServer(server.id)
        let channelID = model.selection.channelID!

        model.addPastedImageData(Data([137, 80, 78, 71]), to: channelID)
        await model.sendDraft(for: channelID)

        let uploadCount = await uploader.uploadCount()
        let sent = await handler.sentSnapshot()
        XCTAssertEqual(uploadCount, 1)
        XCTAssertEqual(sent.first?.content, "")
        XCTAssertEqual(sent.first?.attachments?.count, 1)
        XCTAssertTrue(model.composerDraftState(for: channelID).attachments.isEmpty)
    }

    @MainActor
    func testPhase61PastedFileURLsQueueComposerAttachmentsWithoutReviewOrUpload() async throws {
        let uploader = StubAttachmentUploadHandler()
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), attachmentUploadHandler: uploader, communityAPIClient: StubStoatAPIClient())
        let channelID = model.snapshot.channelsByID.values.first { $0.displayName == "general" }!.id
        let url = try makeTemporaryAttachment(name: "pasted-file.txt", contents: Data("paste".utf8))

        model.addAttachmentURLs([url], to: channelID)

        XCTAssertNil(model.pendingAttachmentDrop)
        XCTAssertTrue(model.composerDraftState(for: channelID).attachments.first?.filename.hasSuffix("pasted-file.txt") == true)
        let uploadCount = await uploader.uploadCount()
        XCTAssertEqual(uploadCount, 0)
    }

    @MainActor
    func testPhase61InvalidPastedImageAndMissingChannelStayOutOfComposer() {
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())
        let channelID = model.snapshot.channelsByID.values.first { $0.displayName == "general" }!.id

        model.addPastedImageData(Data(repeating: 1, count: AttachmentUploadLimits.maxFileBytes + 1), to: channelID)

        XCTAssertTrue(model.composerDraftState(for: channelID).attachments.isEmpty)
        XCTAssertEqual(model.composerError, "File too large. Liquid Bagel currently supports files up to 20 MB.")

        model.addPastedImageData(Data(repeating: 2, count: 32), to: nil)

        XCTAssertTrue(model.composerDraftState(for: nil).attachments.isEmpty)
        XCTAssertEqual(model.composerError, "Select a channel or DM before attaching files.")
    }

    @MainActor
    func testPhase15SendUploadsAttachmentsAndSendsFileIDs() async throws {
        let uploader = StubAttachmentUploadHandler()
        let handler = RecordingAttachmentMessageActionHandler()
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: handler, attachmentUploadHandler: uploader, communityAPIClient: StubStoatAPIClient())
        let server = model.servers.first { $0.name == "Bagel Lab" }!
        model.selectServer(server.id)
        let channelID = model.selection.channelID!
        let url = try makeTemporaryAttachment(name: "send.txt", contents: Data("payload".utf8))

        model.addAttachmentURLs([url], to: channelID)
        model.updateDraft("with file", for: channelID)
        await model.sendDraft(for: channelID)

        let sent = await handler.sentSnapshot()
        let uploadCount = await uploader.uploadCount()
        XCTAssertEqual(uploadCount, 1)
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?.content, "with file")
        XCTAssertEqual(sent.first?.attachments?.count, 1)
        XCTAssertEqual(model.composerDraftState(for: channelID).attachments.count, 0)
    }

    @MainActor
    func testPhase15AttachmentOnlySendAndUploadFailureKeepsDraft() async throws {
        let failingUploader = StubAttachmentUploadHandler(uploadError: MessageActionError.unavailable("upload failed"))
        let handler = RecordingAttachmentMessageActionHandler()
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: handler, attachmentUploadHandler: failingUploader, communityAPIClient: StubStoatAPIClient())
        let server = model.servers.first { $0.name == "Bagel Lab" }!
        model.selectServer(server.id)
        let channelID = model.selection.channelID!
        let url = try makeTemporaryAttachment(name: "image.png", contents: Data([137, 80, 78, 71]))

        model.addPastedImageData(Data([137, 80, 78, 71]), to: channelID)
        await model.sendDraft(for: channelID)

        let failedSent = await handler.sentSnapshot()
        XCTAssertEqual(failedSent.count, 0)
        XCTAssertEqual(model.composerDraftState(for: channelID).attachments.count, 1)
        XCTAssertTrue(model.composerError?.contains("upload") == true)

        let workingUploader = StubAttachmentUploadHandler()
        let workingHandler = RecordingAttachmentMessageActionHandler()
        let workingModel = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: workingHandler, attachmentUploadHandler: workingUploader, communityAPIClient: StubStoatAPIClient())
        workingModel.selectServer(server.id)
        let workingChannelID = workingModel.selection.channelID!
        workingModel.addAttachmentURLs([url], to: workingChannelID)
        await workingModel.sendDraft(for: workingChannelID)

        let sent = await workingHandler.sentSnapshot()
        XCTAssertEqual(sent.first?.content, "")
        XCTAssertEqual(sent.first?.attachments?.count, 1)
    }

    @MainActor
    func testPhase16RemotePreviewOnlyLoadsAfterExplicitAction() async throws {
        let loader = StubRemoteAttachmentLoader(result: .success(RemoteAttachmentData(fileID: "file-remote", filename: "note.txt", contentType: "text/plain", byteCount: 5, data: Data("hello".utf8))))
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), remoteAttachmentLoader: loader, communityAPIClient: StubStoatAPIClient())
        let file = File(id: "file-remote", tag: "attachments", filename: "note.txt", metadata: .text, contentType: "text/plain", size: 5)
        let item = AttachmentDisplayItem(file: file)

        let initialCallCount = await loader.callCount()
        XCTAssertEqual(initialCallCount, 0)
        XCTAssertEqual(item.previewState, .notLoaded)

        await model.previewAttachment(item)

        let finalCallCount = await loader.callCount()
        XCTAssertEqual(finalCallCount, 1)
        XCTAssertEqual(model.attachmentPreviewStates[item.id], .readyRemote)
        XCTAssertEqual(model.attachmentPreview?.data, Data("hello".utf8))
    }

    @MainActor
    func testPhase16RemotePreviewFailureIsSafeAndRetryable() async throws {
        let loader = StubRemoteAttachmentLoader(result: .failure(AttachmentActionError.unavailable("token=secret /Users/enka/private/file.png")))
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), remoteAttachmentLoader: loader, communityAPIClient: StubStoatAPIClient())
        let file = File(id: "file-failed", tag: "attachments", filename: "safe.txt", metadata: .text, contentType: "text/plain", size: 5)
        let item = AttachmentDisplayItem(file: file)

        await model.previewAttachment(item)

        guard case let .failed(message) = model.attachmentPreviewStates[item.id] else {
            return XCTFail("Expected failed preview state")
        }
        XCTAssertFalse(message.contains("secret"))
        XCTAssertFalse(message.contains("/Users/enka"))
        let firstCallCount = await loader.callCount()
        XCTAssertEqual(firstCallCount, 1)

        await model.retryAttachmentPreview(item)
        let retryCallCount = await loader.callCount()
        XCTAssertEqual(retryCallCount, 2)
    }

    @MainActor
    func testPhase16DownloadAndOpenUseMocksAndSanitizedFilename() async throws {
        let data = Data("payload".utf8)
        let loader = StubRemoteAttachmentLoader(result: .success(RemoteAttachmentData(fileID: "file-save", filename: "payload.txt", contentType: "text/plain", byteCount: data.count, data: data)))
        let saver = StubAttachmentSaver()
        let opener = StubAttachmentOpener()
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), remoteAttachmentLoader: loader, attachmentSaver: saver, attachmentOpener: opener, communityAPIClient: StubStoatAPIClient())
        let file = File(id: "file-save", tag: "attachments", filename: "/private/payload.txt", metadata: .text, contentType: "text/plain", size: data.count)
        let item = AttachmentDisplayItem(file: file)

        await model.downloadAttachment(item)

        let saveCount = await saver.saveCount()
        XCTAssertEqual(saveCount, 1)
        XCTAssertEqual(model.loadedAttachmentOriginalData[item.id]?.data, data)

        await model.previewAttachment(item)
        await model.openAttachmentExternally(item)

        let openCount = await opener.openCount()
        XCTAssertEqual(openCount, 1)
    }

    @MainActor
    func testPhase16ComposerSummaryFailedReadinessAndDiagnostics() async throws {
        let failingUploader = StubAttachmentUploadHandler(uploadError: MessageActionError.unavailable("upload failed"))
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), attachmentUploadHandler: failingUploader, communityAPIClient: StubStoatAPIClient())
        let server = model.servers.first { $0.name == "Bagel Lab" }!
        model.selectServer(server.id)
        let channelID = model.selection.channelID!

        model.addPastedImageData(Data([1, 2, 3, 4]), to: channelID)
        XCTAssertTrue(model.composerAttachmentSummary(for: channelID)?.contains("1 attachment") == true)
        XCTAssertTrue(model.composerReadiness(for: channelID).canSend)

        await model.sendDraft(for: channelID)

        XCTAssertFalse(model.composerReadiness(for: channelID).canSend)
        XCTAssertTrue(model.composerReadiness(for: channelID).reason.contains("failed"))
        let diagnostics = model.attachmentDiagnostics()
        XCTAssertEqual(diagnostics.failedUploadCount, 1)
        XCTAssertFalse(String(describing: diagnostics).contains("/Users/"))
    }

    func testPhase16LiveMediaURLUsesVerifiedRoutesWithoutQuery() throws {
        let base = URL(string: "https://cdn.stoatusercontent.com")!
        let preview = try LiveRemoteAttachmentLoader.mediaURL(baseURL: base, tag: "attachments", fileID: "file id", filename: nil)
        let original = try LiveRemoteAttachmentLoader.mediaURL(baseURL: base, tag: "attachments", fileID: "file id", filename: "original")

        XCTAssertEqual(preview.absoluteString, "https://cdn.stoatusercontent.com/attachments/file%20id")
        XCTAssertEqual(original.absoluteString, "https://cdn.stoatusercontent.com/attachments/file%20id/original")
        XCTAssertNil(URLComponents(url: original, resolvingAgainstBaseURL: false)?.queryItems)
    }

    func testPhase20AttachmentURLResolverUsesAutumnRoutes() throws {
        let resolver = DefaultAttachmentURLResolver()
        let environment = StoatAPIEnvironment.production
        let file = File(id: "file id", tag: "attachments", filename: "photo.png", metadata: .image(width: 10, height: 10, thumbhash: nil, animated: false), contentType: "image/png", size: 100)
        let preview = try XCTUnwrap(resolver.remoteURL(for: file, environment: environment, purpose: .preview))
        let original = try XCTUnwrap(resolver.remoteURL(for: file, environment: environment, purpose: .original))

        XCTAssertEqual(preview.absoluteString, "https://cdn.stoatusercontent.com/attachments/file%20id")
        XCTAssertEqual(original.absoluteString, "https://cdn.stoatusercontent.com/attachments/file%20id/original")
        XCTAssertNil(URLComponents(url: preview, resolvingAgainstBaseURL: false)?.queryItems)
    }

    @MainActor
    func testPhase20LiveConnectedSendAllowsUnknownPermissionsAndBlocksKnownDenial() async throws {
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .liveManual, sessionState: .connected, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())
        let channelID = try XCTUnwrap(model.snapshot.channelsByID.values.first { $0.displayName == "general" }?.id)
        model.selectChannel(channelID)
        model.updateDraft("live hello", for: channelID)

        XCTAssertTrue(model.composerReadiness(for: channelID).canSend)
        XCTAssertTrue(model.composerInputReadiness(for: channelID).isEnabled)

        var snapshot = TestShellData.snapshot
        snapshot.channelsByID[channelID]?.permissions = [.viewChannel, .readMessageHistory]
        let denied = MainShellViewModel(snapshot: snapshot, runtimeMode: .liveManual, sessionState: .connected, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: StubMessageActionHandler(currentUserID: TestShellData.currentUserID), communityAPIClient: StubStoatAPIClient())
        denied.selectChannel(channelID)
        denied.updateDraft("blocked", for: channelID)

        let readiness = denied.composerReadiness(for: channelID)
        XCTAssertFalse(readiness.canSend)
        XCTAssertTrue(readiness.reason.contains("permission"))
    }

    @MainActor
    func testPhase20SendDiagnosticsAndTimelineCopyStayRedacted() async throws {
        let handler = StubMessageActionHandler(sendError: MessageActionError.unavailable(#"send failed token="secret" /Users/enka/private/file.png {"raw":"payload"}"#))
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: handler, communityAPIClient: StubStoatAPIClient())
        let channelID = try XCTUnwrap(model.snapshot.channelsByID.values.first { $0.displayName == "general" }?.id)
        model.selectChannel(channelID)
        model.updateDraft("diagnostic message", for: channelID)

        await model.sendDraft(for: channelID)

        let diagnostics = model.currentMessageSendDiagnostics()
        XCTAssertEqual(diagnostics.lastSendStage, .failed)
        XCTAssertEqual(diagnostics.lastSendResult, .failed)
        XCTAssertEqual(diagnostics.selectedChannelID, channelID)
        XCTAssertFalse(diagnostics.lastError?.contains("secret") == true)
        XCTAssertFalse(diagnostics.lastError?.contains("/Users/enka") == true)
        XCTAssertFalse(diagnostics.lastError?.contains("payload") == true)

        let copied = Phase17MessageActions.redactedDiagnosticText(MessageSendDiagnosticsFormatter.redactedText(model.currentMessageSendDiagnostics()))
        XCTAssertTrue(copied.contains("stage: failed"))
        XCTAssertFalse(copied.contains("secret"))
        XCTAssertFalse(copied.contains("/Users/enka"))
        XCTAssertFalse(copied.contains("payload"))
    }

    @MainActor
    func testPhase20ImageSendPreservesLocalPreviewData() async throws {
        let uploader = StubAttachmentUploadHandler()
        let handler = ImageAttachmentMessageActionHandler()
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: handler, attachmentUploadHandler: uploader, communityAPIClient: StubStoatAPIClient())
        let channelID = try XCTUnwrap(model.snapshot.channelsByID.values.first { $0.displayName == "general" }?.id)
        let png = Data([137, 80, 78, 71, 13, 10, 26, 10])
        model.selectChannel(channelID)
        model.addPastedImageData(png, to: channelID)

        await model.sendDraft(for: channelID)

        let message = try XCTUnwrap(model.selectedTimelineMessages.first { $0.message.attachments?.isEmpty == false }?.message)
        let item = try XCTUnwrap(model.attachmentDisplayItems(for: message).first)
        XCTAssertEqual(item.kind, .image)
        XCTAssertEqual(item.previewState, .readyRemote)
        XCTAssertEqual(item.previewData, png)
    }

    @MainActor
    func testEditDeleteAndReactionActionsCallHandler() async {
        let handler = StubMessageActionHandler()
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: handler, communityAPIClient: StubStoatAPIClient())
        let server = model.servers.first { $0.name == "Bagel Lab" }!
        model.selectServer(server.id)
        let ownMessage = model.selectedTimelineMessages.first { $0.message.authorID == TestShellData.currentUserID }!

        model.beginEditing(ownMessage)
        model.editingDraft?.content = "edited"
        await model.saveEditingDraft()
        model.requestDelete(ownMessage)
        await model.confirmPendingDelete()
        await model.toggleReaction("👍", on: ownMessage)

        let editedCount = await handler.editedMessages.count
        let deletedCount = await handler.deletedMessages.count
        let reactionCount = await handler.addedReactions.count
        XCTAssertEqual(editedCount, 1)
        XCTAssertEqual(deletedCount, 1)
        XCTAssertEqual(reactionCount, 1)
    }

    @MainActor
    func testTypingBeginDoesNotSpamAndChannelSwitchEndsTyping() async throws {
        let handler = StubMessageActionHandler()
        let model = MainShellViewModel(snapshot: TestShellData.snapshot, runtimeMode: .mock, sessionState: .mock, currentUser: TestShellData.snapshot.usersByID[TestShellData.currentUserID], messageActionHandler: handler, communityAPIClient: StubStoatAPIClient())
        let server = model.servers.first { $0.name == "Bagel Lab" }!
        model.selectServer(server.id)
        let channelID = model.selection.channelID!

        model.updateDraft("h", for: channelID)
        model.updateDraft("he", for: channelID)
        try await Task.sleep(for: .milliseconds(30))
        model.selectHome()
        try await Task.sleep(for: .milliseconds(30))

        let events = await handler.typingEvents
        XCTAssertEqual(events.filter { if case .beginTyping = $0 { true } else { false } }.count, 1)
        XCTAssertEqual(events.filter { if case .endTyping = $0 { true } else { false } }.count, 1)
    }

}
