import XCTest
@testable import StoatDesignSystem

final class StoatDesignSystemTests: XCTestCase {
    func testSpacingScaleIsOrdered() {
        XCTAssertLessThan(StoatSpacing.small, StoatSpacing.large)
        XCTAssertLessThan(StoatSpacing.large, StoatSpacing.xxLarge)
    }
}
