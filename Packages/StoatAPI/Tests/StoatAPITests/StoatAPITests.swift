import XCTest
@testable import StoatAPI

final class StoatAPITests: XCTestCase {
    func testOfficialEnvironmentUsesCurrentDocumentedDefaults() {
        XCTAssertEqual(StoatAPIEnvironment.official.apiBaseURL.absoluteString, "https://api.stoat.chat")
        XCTAssertEqual(StoatAPIEnvironment.official.eventsWebSocketURL.absoluteString, "wss://events.stoat.chat")
    }

    func testAuthenticationHeaderNames() {
        XCTAssertEqual(StoatAuthCredential.sessionToken("secret").headerName, "X-Session-Token")
        XCTAssertEqual(StoatAuthCredential.botToken("secret").headerName, "X-Bot-Token")
    }
}
