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
}
