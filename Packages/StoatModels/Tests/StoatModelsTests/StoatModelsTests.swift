import XCTest
@testable import StoatModels

final class StoatModelsTests: XCTestCase {
    func testStableIDWrappersEncodeRawValues() throws {
        let userID = UserID(rawValue: "user_123")
        let data = try JSONEncoder().encode(userID)
        let decoded = try JSONDecoder().decode(UserID.self, from: data)

        XCTAssertEqual(decoded, userID)
        XCTAssertEqual(decoded.id, "user_123")
    }

    func testPlaceholderUserIsHashableAndCodable() throws {
        let user = User(id: UserID(rawValue: "u"), username: "bagel", displayName: "Liquid Bagel")
        let data = try JSONEncoder().encode(user)
        let decoded = try JSONDecoder().decode(User.self, from: data)

        XCTAssertEqual(decoded, user)
    }
}
