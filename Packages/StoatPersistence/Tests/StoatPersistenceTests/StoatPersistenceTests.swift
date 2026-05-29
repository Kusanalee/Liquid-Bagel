import XCTest
@testable import StoatPersistence

final class StoatPersistenceTests: XCTestCase {
    func testEmptyRepositoryReturnsNoCurrentUser() async throws {
        let repository = EmptyStoatCacheRepository()
        let user = try await repository.cachedCurrentUser()

        XCTAssertNil(user)
    }
}
