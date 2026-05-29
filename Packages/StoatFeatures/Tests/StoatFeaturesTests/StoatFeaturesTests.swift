import XCTest
@testable import StoatFeatures

final class StoatFeaturesTests: XCTestCase {
    func testPhaseZeroStatusUsesOfficialEnvironment() {
        XCTAssertEqual(PhaseZeroStatus.current.environment.apiBaseURL.host(), "api.stoat.chat")
        XCTAssertTrue(PhaseZeroStatus.current.readyFields.contains(.servers))
    }

    @MainActor
    func testRootViewCanBeConstructed() {
        _ = LiquidBagelRootView()
    }
}
