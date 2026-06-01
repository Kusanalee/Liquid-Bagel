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
}
