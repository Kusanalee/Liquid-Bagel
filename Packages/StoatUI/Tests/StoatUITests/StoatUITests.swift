import StoatDesignSystem
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
}
