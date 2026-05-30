import XCTest
@testable import StoatDesignSystem

final class StoatDesignSystemTests: XCTestCase {
    func testSpacingScaleIsOrdered() {
        XCTAssertLessThan(StoatSpacing.small, StoatSpacing.large)
        XCTAssertLessThan(StoatSpacing.large, StoatSpacing.xxLarge)
    }

    func testCoreDimensionsAreStable() {
        XCTAssertEqual(StoatSize.serverRailWidth, 72)
        XCTAssertEqual(StoatSize.channelSidebarWidth, 260)
        XCTAssertEqual(StoatSize.memberPanelWidth, 240)
    }

    func testBadgeAccessibilityText() {
        XCTAssertEqual(StoatBadges.mentionAccessibilityLabel(count: 1), "1 mention")
        XCTAssertEqual(StoatBadges.unreadAccessibilityLabel(count: 3), "3 unread messages")
    }

    func testPhase8AccessibilityHelperText() {
        let channel = StoatAccessibility.channelLabel(name: "general", unreadCount: 1, mentionCount: 2, isSelected: true)
        XCTAssertTrue(channel.contains("selected"))
        XCTAssertTrue(channel.contains("1 unread message"))
        XCTAssertTrue(channel.contains("2 mentions"))

        let message = StoatAccessibility.messageLabel(author: "Liquid Bagel", timestamp: "9:41 AM", content: "hello", isEdited: true, status: "failed", isSelected: true)
        XCTAssertTrue(message.contains("edited"))
        XCTAssertTrue(message.contains("failed"))
        XCTAssertTrue(message.contains("selected"))

        let runtime = StoatAccessibility.runtimeLabel(mode: "Live Manual", connection: "Ready", health: "Live connection ready")
        XCTAssertFalse(runtime.localizedCaseInsensitiveContains("token"))
    }

    func testPhase8AdaptiveStyleHelpers() {
        XCTAssertEqual(StoatDensityStyle.timelineSpacing(for: "compact"), StoatSpacing.small)
        XCTAssertEqual(StoatDensityStyle.timelineSpacing(for: "comfortable"), StoatSpacing.medium)

        let solid = StoatMaterialStyle.resolved(reduceTransparency: true, increaseContrast: true, reduceGlassIntensity: false)
        XCTAssertFalse(solid.usesMaterial)
        XCTAssertGreaterThan(solid.strokeOpacity, 0.3)

        let reducedGlass = StoatMaterialStyle.resolved(reduceTransparency: false, increaseContrast: false, reduceGlassIntensity: true)
        XCTAssertFalse(reducedGlass.usesMaterial)
    }

    func testPhase9AccessibilityHelperText() {
        let message = StoatAccessibility.messageLabel(author: "A", timestamp: "now", content: "body", isPinned: true, reactionCount: 3, status: "failed", isSelected: true)
        XCTAssertTrue(message.contains("pinned"))
        XCTAssertTrue(message.contains("3 reactions"))
        XCTAssertTrue(message.contains("failed"))
        XCTAssertTrue(message.contains("selected"))

        XCTAssertEqual(StoatAccessibility.reactionLabel(emoji: "👍", count: 2, hasReacted: false), "Reaction 👍, 2 reactions")
        XCTAssertTrue(StoatAccessibility.inlineEditLabel(isSaving: false, errorMessage: "Edit failed").contains("Edit failed"))
    }
}
