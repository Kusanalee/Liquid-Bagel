import AppKit
import StoatDesignSystem
import StoatModels
import UniformTypeIdentifiers
import XCTest
@testable import StoatUI

final class StoatUITests: XCTestCase {
    func testInitialsGeneration() {
        XCTAssertEqual(StoatInitials.make("Bagel Lab"), "BL")
        XCTAssertEqual(StoatInitials.make("stoat"), "S")
        XCTAssertEqual(StoatInitials.make("", fallback: "LB"), "LB")
    }

    func testBadgeFormatting() {
        XCTAssertEqual(StoatBadges.displayCount(0), "")
        XCTAssertEqual(StoatBadges.displayCount(7), "7")
        XCTAssertEqual(StoatBadges.displayCount(120), "99+")
    }

    func testAccessibilityLabelsIncludeState() {
        let label = StoatAccessibility.serverLabel(name: "Bagel Lab", unreadCount: 2, mentionCount: 1, isSelected: true)
        XCTAssertTrue(label.contains("selected"))
        XCTAssertTrue(label.contains("2 unread messages"))
        XCTAssertTrue(label.contains("1 mention"))
    }

    func testPhase8AccessibilityLabelsIncludeDisabledReasons() {
        let composer = StoatAccessibility.composerLabel(isEnabled: false, disabledReason: "Connect Live Manual before sending.")
        XCTAssertTrue(composer.contains("disabled"))
        XCTAssertTrue(composer.contains("Connect Live Manual"))

        let channel = StoatAccessibility.channelLabel(name: "voice", isDisabled: true)
        XCTAssertTrue(channel.contains("unavailable"))
    }

    func testPhase9MessageActionAccessibilityHelpers() {
        let message = StoatAccessibility.messageLabel(author: "Liquid", timestamp: "now", content: "hello", isEdited: true, isPinned: true, reactionCount: 2, status: "selected")
        XCTAssertTrue(message.contains("edited"))
        XCTAssertTrue(message.contains("pinned"))
        XCTAssertTrue(message.contains("2 reactions"))

        XCTAssertTrue(StoatAccessibility.inlineEditLabel(isSaving: true).contains("saving"))
        XCTAssertTrue(StoatAccessibility.failedMessageActionLabel(action: "Retry", error: "send failed").contains("failed message"))
        XCTAssertTrue(StoatAccessibility.reactionLabel(emoji: "✅", count: 1, hasReacted: true).contains("selected"))
    }

    func testPhase16AttachmentDisplaySanitizesAndInfersKind() {
        let image = File(id: "file-image", tag: "attachments", filename: "/tmp/private/photo.png", metadata: .image(width: 80, height: 60, thumbhash: nil, animated: false), contentType: "image/png", size: 12_000)
        let item = AttachmentDisplayItem(file: image)

        XCTAssertEqual(item.displayName, "photo.png")
        XCTAssertEqual(item.kind, .image)
        XCTAssertEqual(item.source.fileID?.rawValue, "file-image")
        XCTAssertFalse(item.debugDescription.contains("/tmp/private"))
    }

    func testPhase16AttachmentKindInferenceAndAccessibilityHelpers() {
        XCTAssertEqual(AttachmentDisplayFormatting.kind(contentType: "application/pdf", filename: "brief.pdf"), .pdf)
        XCTAssertEqual(AttachmentDisplayFormatting.kind(contentType: "text/csv", filename: "data.csv"), .text)
        XCTAssertEqual(AttachmentDisplayFormatting.kind(contentType: nil, filename: "bundle.zip"), .archive)

        let label = StoatAccessibility.attachmentLabel(filename: "brief.pdf", kind: "PDF", size: "42 KB", state: "Not loaded")
        XCTAssertTrue(label.contains("PDF"))
        XCTAssertTrue(StoatAccessibility.attachmentActionLabel(action: "Save As", filename: "brief.pdf").contains("brief.pdf"))
    }

    func testPhase55VideoAttachmentKindMapping() {
        XCTAssertEqual(AttachmentDisplayFormatting.kind(contentType: "video/mp4", filename: "clip.mp4"), .video)
        XCTAssertEqual(AttachmentDisplayFormatting.kind(contentType: "video/quicktime", filename: "clip.mov"), .video)
        XCTAssertEqual(AttachmentDisplayFormatting.kind(contentType: nil, filename: "clip.m4v"), .video)
        XCTAssertEqual(AttachmentDisplayFormatting.kind(contentType: "video/webm", filename: "clip.webm"), .unsupported)
        XCTAssertEqual(AttachmentDisplayFormatting.kind(contentType: "video/mp4", filename: "clip.mp4", metadata: .video(width: 10, height: 10)), .video)
        XCTAssertEqual(AttachmentDisplayFormatting.kind(contentType: "video/webm", filename: "clip.webm", metadata: .video(width: 10, height: 10)), .unsupported)
        XCTAssertEqual(AttachmentDisplayFormatting.kind(contentType: "audio/mpeg", filename: "song.mp3", metadata: .audio), .unsupported)

        let video = File(id: "file-video", tag: "attachments", filename: "clip.mp4", metadata: .video(width: 640, height: 480), contentType: "video/mp4", size: 1_000)
        let item = AttachmentDisplayItem(file: video)
        XCTAssertEqual(item.kind, .video)
        XCTAssertFalse(item.kind.isPreviewable)
        XCTAssertNil(item.playbackURL)
    }

    @MainActor
    func testPhase56PresenceDotGatesOnOfflineRegardlessOfStoredPresence() {
        // An offline member whose stored (configured) presence is still "Online" must show
        // as offline — `status.presence` persists after disconnect and must not override a
        // known-false `isOnline`.
        let offlineWithOnlinePresence = PresenceDot.resolve(presence: .online, isOnline: false)
        XCTAssertEqual(offlineWithOnlinePresence.color, .secondary)
        XCTAssertEqual(offlineWithOnlinePresence.label, "Offline")

        let offlineWithIdlePresence = PresenceDot.resolve(presence: .idle, isOnline: false)
        XCTAssertEqual(offlineWithIdlePresence.color, .secondary)
        XCTAssertEqual(offlineWithIdlePresence.label, "Offline")

        let onlineWithIdlePresence = PresenceDot.resolve(presence: .idle, isOnline: true)
        XCTAssertEqual(onlineWithIdlePresence.color, .orange)
        XCTAssertEqual(onlineWithIdlePresence.label, "Idle")

        let onlineNoPresence = PresenceDot.resolve(presence: nil, isOnline: true)
        XCTAssertEqual(onlineNoPresence.color, .green)
        XCTAssertEqual(onlineNoPresence.label, "Online")

        // isOnline unknown (nil): some call sites don't have it, fall back to presence-first.
        let unknownOnlineWithPresence = PresenceDot.resolve(presence: .online, isOnline: nil)
        XCTAssertEqual(unknownOnlineWithPresence.color, .green)
        XCTAssertEqual(unknownOnlineWithPresence.label, "Online")

        let unknownOnlineNoPresence = PresenceDot.resolve(presence: nil, isOnline: nil)
        XCTAssertEqual(unknownOnlineNoPresence.color, .secondary)
        XCTAssertEqual(unknownOnlineNoPresence.label, "Offline")

        let invisibleButOnline = PresenceDot.resolve(presence: .invisible, isOnline: true)
        XCTAssertEqual(invisibleButOnline.color, .secondary)
        XCTAssertEqual(invisibleButOnline.label, "Invisible")
    }

    func testPhase56VideoPosterStoreBoundsEntriesAndBytes() async {
        let store = VideoPosterStore(maxEntries: 2, maxBytes: 7)
        let first = URL(fileURLWithPath: "/tmp/phase56-first.mov")
        let second = URL(fileURLWithPath: "/tmp/phase56-second.mov")
        let third = URL(fileURLWithPath: "/tmp/phase56-third.mov")

        await store.insert(Data(repeating: 1, count: 3), for: first)
        await store.insert(Data(repeating: 2, count: 3), for: second)
        await store.insert(Data(repeating: 3, count: 3), for: third)

        let diagnostics = await store.diagnostics()
        let firstPoster = await store.cachedPoster(for: first)
        let secondPoster = await store.cachedPoster(for: second)
        let thirdPoster = await store.cachedPoster(for: third)
        XCTAssertEqual(diagnostics.cacheCount, 2)
        XCTAssertEqual(diagnostics.byteCount, 6)
        XCTAssertNil(firstPoster)
        XCTAssertNotNil(secondPoster)
        XCTAssertNotNil(thirdPoster)
    }

    func testPhase55ExternalEmbedMediaFactorySynthesizesSafeItems() {
        let imageEmbed = Embed(kind: .website, url: "https://tenor.com/view", image: EmbedImage(url: "https://media1.tenor.com/m/abc/dance.gif", width: 200, height: 200))
        let imageItem = ExternalEmbedMediaFactory.mediaItem(for: imageEmbed)
        XCTAssertEqual(imageItem?.kind, .image)
        XCTAssertTrue(imageItem?.isExternalEmbedMedia == true)
        XCTAssertEqual(imageItem?.playbackURL?.absoluteString, "https://media1.tenor.com/m/abc/dance.gif")
        XCTAssertTrue(imageItem?.id.hasPrefix("embed-ext-") == true)

        let insecureEmbed = Embed(kind: .website, image: EmbedImage(url: "http://insecure.example/x.png", width: 10, height: 10))
        XCTAssertNil(ExternalEmbedMediaFactory.mediaItem(for: insecureEmbed))

        let topLevelImage = Embed(kind: .image, url: "https://images.example/direct.png")
        XCTAssertEqual(ExternalEmbedMediaFactory.mediaItem(for: topLevelImage)?.kind, .image)

        let videoEmbed = Embed(kind: .website, video: EmbedVideo(url: "https://cdn.example/clip.mp4", width: 640, height: 480))
        XCTAssertEqual(ExternalEmbedMediaFactory.mediaItem(for: videoEmbed)?.kind, .video)

        let embedPlayerVideo = Embed(kind: .website, video: EmbedVideo(url: "https://www.youtube.com/embed/xyz", width: 640, height: 480))
        XCTAssertNil(ExternalEmbedMediaFactory.mediaItem(for: embedPlayerVideo))

        let youtube = Embed(kind: .website, special: .object(["type": .string("YouTube"), "id": .string("dQw4w9WgXcQ")]))
        let thumbnail = ExternalEmbedMediaFactory.mediaItem(for: youtube)
        XCTAssertEqual(thumbnail?.playbackURL?.absoluteString, "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg")

        let evilYoutube = Embed(kind: .website, special: .object(["type": .string("YouTube"), "id": .string("../evil?x=1")]))
        XCTAssertNil(ExternalEmbedMediaFactory.mediaItem(for: evilYoutube))
    }

    func testPhase17MessageActionAndReactionDisplayHelpers() {
        let action = MessageRowActionItem(id: "delete", title: "Delete Message", systemImage: "trash", role: .destructive, isEnabled: false)
        XCTAssertEqual(action.id, "delete")

        let actionLabel = StoatAccessibility.messageActionLabel(title: action.title, isDestructive: action.role == .destructive, isEnabled: action.isEnabled)
        XCTAssertTrue(actionLabel.contains("destructive"))
        XCTAssertTrue(actionLabel.contains("unavailable"))

        let reaction = MessageReactionDisplayItem(emoji: "👍", count: 2, hasCurrentUserReacted: true)
        let reactionLabel = StoatAccessibility.reactionLabel(emoji: reaction.emoji, count: reaction.count, hasReacted: reaction.hasCurrentUserReacted)
        XCTAssertTrue(reactionLabel.contains("2 reactions"))
        XCTAssertTrue(reactionLabel.contains("selected"))
    }

    func testPhase29ComposerTextSizingStartsCompactAndGrows() {
        XCTAssertEqual(ComposerTextSizing.height(for: ""), ComposerTextSizing.compactHeight)
        XCTAssertEqual(ComposerTextSizing.height(for: "one line"), ComposerTextSizing.compactHeight)

        let multiline = ComposerTextSizing.height(for: "one\ntwo\nthree")
        XCTAssertGreaterThan(multiline, ComposerTextSizing.compactHeight)
        XCTAssertLessThanOrEqual(multiline, ComposerTextSizing.maximumHeight)

        let capped = ComposerTextSizing.height(for: String(repeating: "long message wraps ", count: 80), approximateCharactersPerLine: 24)
        XCTAssertEqual(capped, ComposerTextSizing.maximumHeight)
    }

    func testPhase47MarkdownCustomEmojiKeepsCodeBlocksLiteral() {
        let emoji = MessageInlineCustomEmojiItem(shortcode: ":bagel:", name: "bagel")

        let inlineTokens = MarkdownMessageContent._testInlineTokenDescriptions(
            for: "**Bold** :bagel:",
            customEmojiItems: [emoji]
        )
        XCTAssertEqual(inlineTokens, ["text::**Bold** ", "emoji:::bagel:"])

        let codeBlocks = MarkdownMessageContent._testBlockDescriptions(for: "```\nlet value = \":bagel:\"\n```")
        XCTAssertEqual(codeBlocks, ["code::let value = \":bagel:\""])
    }

    func testPhase58MentionTokenizerExtractsUserMentionsOutsideCode() {
        let userID = "01FD58YK5W7QRV5H3D64KTQYX3"
        let mention = MessageInlineReferenceItem(kind: .user, rawID: userID, displayName: "Enka")

        let tokens = MarkdownMessageContent._testInlineTokenDescriptions(
            for: "hello <@\(userID)> how are you",
            customEmojiItems: [],
            referenceItems: ["<@\(userID)>": mention]
        )
        XCTAssertEqual(tokens, ["text::hello ", "reference:user::\(userID)", "text:: how are you"])
    }

    func testPhase58MentionTokenizerLeavesFencedCodeLiteral() {
        let userID = "01FD58YK5W7QRV5H3D64KTQYX3"
        let mention = MessageInlineReferenceItem(kind: .user, rawID: userID, displayName: "Enka")

        let codeBlocks = MarkdownMessageContent._testBlockDescriptions(for: "```\n<@\(userID)>\n```")
        XCTAssertEqual(codeBlocks, ["code::<@\(userID)>"])

        // The inline tokenizer itself (given only the fenced content, as the block parser would
        // hand it) still recognizes the shape -- literalness comes from the block parser routing
        // code blocks away from inline tokenization entirely (MarkdownContentPreparer.prepare).
        let tokens = MarkdownMessageContent._testInlineTokenDescriptions(
            for: "<@\(userID)>",
            customEmojiItems: [],
            referenceItems: ["<@\(userID)>": mention]
        )
        XCTAssertEqual(tokens, ["reference:user::\(userID)"])
    }

    func testPhase58UnresolvedMentionRendersUnknownUserFallback() {
        let userID = "01FD58YK5W7QRV5H3D64KTQYX3"

        let tokens = MarkdownMessageContent._testInlineTokenDescriptions(
            for: "hey <@\(userID)>",
            customEmojiItems: [],
            referenceItems: [:]
        )
        XCTAssertEqual(tokens, ["text::hey ", "reference:user::\(userID)"])
    }

    func testPhase58MentionTokensDoNotHitAngleBracketSanitizer() {
        // Malformed/short bracket content (not a real 26-char ULID) should NOT be treated as a
        // mention -- it stays literal text and is still subject to the existing sanitizer.
        let tokens = MarkdownMessageContent._testInlineTokenDescriptions(
            for: "a <div> tag and <@short>",
            customEmojiItems: [],
            referenceItems: [:]
        )
        XCTAssertEqual(tokens, ["text::a <div> tag and <@short>"])
    }

    func testPhase58ChannelAndRoleMentionsAreRecognized() {
        let channelID = "01FD58YK5W7QRV5H3D64KTQYX3"
        let roleID = "01FD58YK5W7QRV5H3D64KTQYX4"
        let tokens = MarkdownMessageContent._testInlineTokenDescriptions(
            for: "<#\(channelID)> and <%\(roleID)>",
            customEmojiItems: [],
            referenceItems: [:]
        )
        XCTAssertEqual(tokens, ["reference:channel::\(channelID)", "text:: and ", "reference:role::\(roleID)"])
    }

    #if canImport(AppKit)
    @MainActor
    func testPhase58InlineTriggerDetectionAtCaretAndCancellation() {
        let atEnd = GlassComposer._testDetectInlineTrigger(text: "hello @enk", caretUTF16Offset: 10)
        XCTAssertEqual(atEnd?.query, "enk")
        XCTAssertEqual(atEnd?.utf16Location, 6)
        XCTAssertEqual(atEnd?.utf16Length, 4)

        let bareAt = GlassComposer._testDetectInlineTrigger(text: "hello @", caretUTF16Offset: 7)
        XCTAssertEqual(bareAt?.query, "")

        // Caret sits right after "@enk", mid-word (before the trailing "a") -- query is only
        // what's been typed so far, not the whole word.
        let midWord = GlassComposer._testDetectInlineTrigger(text: "@enka is here", caretUTF16Offset: 4)
        XCTAssertEqual(midWord?.query, "enk")
        XCTAssertEqual(midWord?.utf16Location, 0)

        let noTrigger = GlassComposer._testDetectInlineTrigger(text: "hello world", caretUTF16Offset: 11)
        XCTAssertNil(noTrigger)

        let cancelledByWhitespace = GlassComposer._testDetectInlineTrigger(text: "hey @enk done", caretUTF16Offset: 13)
        XCTAssertNil(cancelledByWhitespace)

        // A word character immediately before "@" (e.g. an email address) must not trigger.
        let emailLikeNoTrigger = GlassComposer._testDetectInlineTrigger(text: "a@b.com", caretUTF16Offset: 7)
        XCTAssertNil(emailLikeNoTrigger)
    }

    @MainActor
    func testPhase61PasteFileURLWinsOverAccompanyingTextRepresentation() {
        let fileURL = URL(fileURLWithPath: "/tmp/phase61-example.png")
        let outcome = GlassComposer._testPaste(existingText: "") { pasteboard in
            pasteboard.writeObjects([fileURL as NSURL])
            pasteboard.setString("phase61-example.png", forType: .string)
        }
        XCTAssertEqual(outcome.pastedFileURLs, [fileURL])
        XCTAssertNil(outcome.pastedImageData)
        XCTAssertEqual(outcome.resultingText, "")
    }

    @MainActor
    func testPhase61PasteImageDataWinsOverAccompanyingTextRepresentation() {
        let pngData = Data([0x89, 0x50, 0x4E, 0x47])
        let outcome = GlassComposer._testPaste(existingText: "") { pasteboard in
            pasteboard.setData(pngData, forType: .png)
            pasteboard.setString("clipboard.png", forType: .string)
        }
        XCTAssertNil(outcome.pastedFileURLs)
        XCTAssertEqual(outcome.pastedImageData, pngData)
        XCTAssertEqual(outcome.resultingText, "")
    }

    @MainActor
    func testPhase61PastePreservesExistingComposerTextWhenAttachmentWins() {
        let pngData = Data([0x89, 0x50, 0x4E, 0x47])
        let outcome = GlassComposer._testPaste(existingText: "Hello there") { pasteboard in
            pasteboard.setData(pngData, forType: .png)
            pasteboard.setString("clipboard.png", forType: .string)
        }
        XCTAssertEqual(outcome.pastedImageData, pngData)
        XCTAssertNil(outcome.pastedFileURLs)
        XCTAssertEqual(outcome.resultingText, "Hello there")
    }

    @MainActor
    func testPhase62ReadSelectionInterceptsScreenshotDataBeforeTextFallback() {
        let pngData = Data([0x89, 0x50, 0x4E, 0x47])
        let outcome = GlassComposer._testReadSelection(existingText: "Keep this") { pasteboard in
            pasteboard.setData(pngData, forType: .png)
            pasteboard.setString("screenshot.png", forType: .string)
        }

        XCTAssertEqual(outcome.pastedImageData, pngData)
        XCTAssertNil(outcome.pastedFileURLs)
        XCTAssertEqual(outcome.resultingText, "Keep this")
    }

    @MainActor
    func testPhase62SwiftUIPasteLoadsScreenshotProviderBeforeTextRepresentation() async {
        let outcome = await GlassComposer._testSwiftUIPaste(
            existingText: "Keep this",
            providers: [screenshotProvider()]
        )

        XCTAssertNil(outcome.pastedFileURLs)
        XCTAssertEqual(outcome.pastedImageDataList.count, 1)
        XCTAssertEqual(outcome.pastedImageData?.prefix(8), Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
        XCTAssertEqual(outcome.resultingText, "Keep this")
        XCTAssertEqual(outcome.diagnostics.last?.source, .swiftUI)
        XCTAssertEqual(outcome.diagnostics.last?.outcome, .queued)
        XCTAssertEqual(outcome.diagnostics.last?.mediaCategory, .image)
    }

    @MainActor
    func testPhase62SwiftUIPastePrefersFileURLAndQueuesMultipleProviders() async {
        let fileURL = URL(fileURLWithPath: "/tmp/phase62-provider-file.png")
        let fileProvider = NSItemProvider()
        fileProvider.registerDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier, visibility: .all) { completion in
            completion(fileURL.dataRepresentation, nil)
            return nil
        }

        let outcome = await GlassComposer._testSwiftUIPaste(
            existingText: "Draft text",
            providers: [screenshotProvider(), fileProvider]
        )

        XCTAssertEqual(outcome.pastedFileURLs, [fileURL])
        XCTAssertEqual(outcome.pastedImageDataList.count, 1)
        XCTAssertEqual(outcome.diagnostics.last?.itemCount, 2)
        XCTAssertEqual(outcome.diagnostics.last?.mediaCategory, .mixed)
        XCTAssertEqual(outcome.resultingText, "Draft text")
    }

    @MainActor
    func testPhase62SwiftUIPasteReportsUnsupportedProviderWithoutChangingDraft() async {
        let textProvider = NSItemProvider()
        textProvider.registerDataRepresentation(forTypeIdentifier: UTType.plainText.identifier, visibility: .all) { completion in
            completion(Data("plain clipboard text".utf8), nil)
            return nil
        }

        let outcome = await GlassComposer._testSwiftUIPaste(existingText: "Keep this", providers: [textProvider])

        XCTAssertNil(outcome.pastedFileURLs)
        XCTAssertTrue(outcome.pastedImageDataList.isEmpty)
        XCTAssertEqual(outcome.diagnostics.last?.outcome, .unsupported)
        XCTAssertEqual(outcome.diagnostics.last?.mediaCategory, .unknown)
        XCTAssertEqual(outcome.resultingText, "Keep this")
    }

    @MainActor
    func testPhase62SwiftUIReservationSuppressesNativeDuplicateDelivery() async {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("StoatUITests.ComposerPaste.Dedupe.\(UUID().uuidString)"))
        pasteboard.clearContents()
        let pngData = screenshotPNGData()
        pasteboard.setData(pngData, forType: .png)

        let coordinator = ComposerPasteCoordinator()
        let nativeTextView = ComposerPasteInterceptingTextView()
        nativeTextView.pasteboardOverride = pasteboard
        nativeTextView.pasteCoordinator = coordinator
        var nativeDeliveries = 0
        var swiftUIDeliveries = 0
        let delivery = expectation(description: "SwiftUI provider delivery")
        nativeTextView.onPasteImageData = { _ in nativeDeliveries += 1 }
        coordinator.beginSwiftUIPaste(
            providers: [screenshotProvider()],
            onPasteFileURLs: { _ in },
            onPasteImageData: { _ in swiftUIDeliveries += 1 },
            onDiagnostic: { diagnostic in
                if diagnostic.source == .swiftUI, diagnostic.outcome == .queued {
                    delivery.fulfill()
                }
            },
            pasteboardChangeCount: pasteboard.changeCount
        )

        nativeTextView.paste(nil)
        XCTAssertEqual(nativeDeliveries, 0)
        await fulfillment(of: [delivery], timeout: 1)
        XCTAssertEqual(swiftUIDeliveries, 1)
    }

    @MainActor
    func testPhase61PasteFallsBackToPlainTextWhenNoAttachmentPayload() {
        let outcome = GlassComposer._testPaste(existingText: "") { pasteboard in
            pasteboard.setString("plain clipboard text", forType: .string)
        }
        XCTAssertNil(outcome.pastedFileURLs)
        XCTAssertNil(outcome.pastedImageData)
        XCTAssertEqual(outcome.resultingText, "plain clipboard text")
    }

    private func screenshotProvider() -> NSItemProvider {
        let provider = NSItemProvider()
        let tiffData = screenshotTIFFData()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.tiff.identifier, visibility: .all) { completion in
            completion(tiffData, nil)
            return nil
        }
        provider.registerDataRepresentation(forTypeIdentifier: UTType.plainText.identifier, visibility: .all) { completion in
            completion(Data("screenshot.tiff".utf8), nil)
            return nil
        }
        return provider
    }

    private func screenshotPNGData() -> Data {
        let bitmap = makeScreenshotBitmap()
        return bitmap.representation(using: .png, properties: [:])!
    }

    private func screenshotTIFFData() -> Data {
        makeScreenshotBitmap().tiffRepresentation!
    }

    private func makeScreenshotBitmap() -> NSBitmapImageRep {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 1,
            pixelsHigh: 1,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        bitmap.setColor(NSColor(calibratedRed: 0.95, green: 0.25, blue: 0.55, alpha: 1), atX: 0, y: 0)
        return bitmap
    }
    #endif

    func testPhase47EmbedDisplayItemSanitizesURLsAndLabelsVariants() {
        let website = Embed(
            kind: .website,
            url: "https://example.com/path?token=secret#fragment",
            title: "<b>Launch</b>",
            description: "A safe description",
            siteName: " Example "
        )
        let item = MessageEmbedDisplayItem(id: "embed", embed: website)

        XCTAssertEqual(item.label, "Link")
        XCTAssertEqual(item.title, "Launch")
        XCTAssertEqual(item.displayURL, "https://example.com/path")
        XCTAssertNotNil(item.externalURL)
        XCTAssertTrue(item.accessibilityLabel.contains("Launch"))

        let unsafeImage = Embed(kind: .image, url: "file:///Users/enka/private.png", image: EmbedImage(url: "file:///Users/enka/private.png", width: 20, height: 20))
        let imageItem = MessageEmbedDisplayItem(id: "image", embed: unsafeImage)
        XCTAssertEqual(imageItem.label, "Image")
        XCTAssertNil(imageItem.externalURL)
        XCTAssertNil(imageItem.displayURL)
        XCTAssertTrue(imageItem.accessibilityLabel.contains("external image preview available"))

        XCTAssertEqual(MessageEmbedDisplayItem.label(for: .video), "Video")
        XCTAssertEqual(MessageEmbedDisplayItem.label(for: .unknown("Poll")), "Embed Poll")
    }

    func testPhase47EmbedDisplayItemCarriesModeledMediaPreviewData() {
        let file = File(id: "embed-media", tag: "attachments", filename: "/tmp/private/embed.png", metadata: .image(width: 40, height: 40, thumbhash: nil, animated: false), contentType: "image/png", size: 128)
        let data = Data("png".utf8)
        var mediaItem = AttachmentDisplayItem(file: file, previewState: .readyRemote)
        mediaItem.previewData = data

        let item = MessageEmbedDisplayItem(
            id: "embed",
            embed: Embed(kind: .image, title: "Modeled image", media: file),
            mediaItem: mediaItem,
            mediaPreviewData: data
        )

        XCTAssertEqual(item.mediaItem?.displayName, "embed.png")
        XCTAssertEqual(item.mediaPreviewData, data)
        XCTAssertTrue(item.accessibilityLabel.contains("media embed.png"))
    }

    func testPhase51DecodedImagePipelineDedupesIdenticalResources() async throws {
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
        let key = DecodedImageKey(id: "phase51-pixel", pixelSize: 32)
        await DecodedImagePipeline.reset()

        async let first = DecodedImagePipeline.prepare(data: png, key: key)
        async let second = DecodedImagePipeline.prepare(data: png, key: key)
        let firstResult = await first
        let secondResult = await second
        XCTAssertTrue(firstResult)
        XCTAssertTrue(secondResult)
        _ = await DecodedImagePipeline.prepare(data: png, key: key)
        let diagnostics = await DecodedImagePipeline.diagnostics()

        XCTAssertEqual(diagnostics.decodeCount, 1)
        XCTAssertGreaterThanOrEqual(diagnostics.dedupeCount + diagnostics.cacheHitCount, 2)
        XCTAssertEqual(diagnostics.cacheCount, 1)
        let isSynchronouslyCached = await MainActor.run {
            DecodedImagePipeline.hasSynchronouslyCachedImage(for: key)
        }
        XCTAssertTrue(isSynchronouslyCached)
    }

    @MainActor
    func testPhase60TimelineSkeletonHonorsReduceMotionPolicy() {
        XCTAssertTrue(TimelineSkeletonAnimationPolicy.usesShimmer(reduceMotion: false))
        XCTAssertFalse(TimelineSkeletonAnimationPolicy.usesShimmer(reduceMotion: true))
        _ = TimelineSkeletonRow()
        _ = MessageRow(
            message: Message(
                id: "phase60-row",
                channelID: "phase60-channel",
                authorID: "phase60-author",
                content: "Prepared only"
            ),
            author: nil
        )
    }
}
