import XCTest
@testable import StoatRealtime

final class StoatRealtimeTests: XCTestCase {
    func testReadyFieldWireNamesMatchDocs() {
        XCTAssertEqual(ReadyField.userSettings.rawValue, "user_settings")
        XCTAssertEqual(ReadyField.channelUnreads.rawValue, "channel_unreads")
        XCTAssertTrue(ReadyField.allCases.contains(.policyChanges))
    }
}
