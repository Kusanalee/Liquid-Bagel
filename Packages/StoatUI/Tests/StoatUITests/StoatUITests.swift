import StoatDesignSystem
import StoatModels
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
    }
}
