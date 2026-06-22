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

        let fullGlass = StoatMaterialStyle.resolved(reduceTransparency: false, increaseContrast: false, liquidGlassTransparency: 1.0)
        let lowGlass = StoatMaterialStyle.resolved(reduceTransparency: false, increaseContrast: false, liquidGlassTransparency: 0.25)
        XCTAssertTrue(fullGlass.usesMaterial)
        XCTAssertFalse(lowGlass.usesMaterial)
        XCTAssertGreaterThan(lowGlass.backgroundOpacity, fullGlass.backgroundOpacity)
        XCTAssertEqual(StoatLiquidGlassTransparency.clamped(-1), StoatLiquidGlassTransparency.minimum)
        XCTAssertEqual(StoatLiquidGlassTransparency.clamped(2), StoatLiquidGlassTransparency.maximum)
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

    func testPhase14SearchHighlightStyleStrengthensCurrentAndHighContrast() {
        let normal = SearchHighlightStyle()
        XCTAssertEqual(normal.fillOpacity, 0)
        XCTAssertEqual(normal.borderOpacity, 0)

        let highlighted = SearchHighlightStyle(isHighlighted: true)
        let current = SearchHighlightStyle(isHighlighted: true, isCurrent: true)
        XCTAssertGreaterThan(current.fillOpacity, highlighted.fillOpacity)
        XCTAssertGreaterThan(current.borderOpacity, highlighted.borderOpacity)

        let highContrast = SearchHighlightStyle(isHighlighted: true, isCurrent: true, highContrast: true)
        XCTAssertGreaterThan(highContrast.borderOpacity, current.borderOpacity)

        let reducedTransparency = SearchHighlightStyle(isHighlighted: true, isCurrent: true, reduceTransparency: true)
        XCTAssertGreaterThan(reducedTransparency.fillOpacity, current.fillOpacity)
    }

    func testPhase14MessageAccessibilityCanIncludeSearchResultStatus() {
        let label = StoatAccessibility.messageLabel(
            author: "A",
            timestamp: "now",
            content: "body",
            isSelected: true,
            searchResultStatus: "current search result"
        )
        XCTAssertTrue(label.contains("selected"))
        XCTAssertTrue(label.contains("current search result"))
    }
}
