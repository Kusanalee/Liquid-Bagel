import XCTest
@testable import StoatUI

final class StoatUITests: XCTestCase {
    @MainActor
    func testPhaseZeroShellCanBeConstructed() {
        _ = PhaseZeroShellView()
    }
}
