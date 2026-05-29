import StoatModels
import XCTest
@testable import StoatFeatures

final class StoatFeaturesTests: XCTestCase {
    func testPhaseThreeStatusUsesOfficialEnvironment() {
        XCTAssertEqual(PhaseThreeStatus.current.environment.apiBaseURL.host(), "api.stoat.chat")
        XCTAssertTrue(PhaseThreeStatus.current.readyFields.contains(.servers))
    }

    @MainActor
    func testRootViewCanBeConstructed() {
        _ = LiquidBagelRootView()
    }

    @MainActor
    func testInitialSelectionDefaultsToHome() {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot)
        XCTAssertEqual(model.selection.space, .home)
        XCTAssertNil(model.selection.serverID)
        XCTAssertNil(model.selection.channelID)
    }

    @MainActor
    func testSelectingServerUpdatesSelectionAndAutoSelectsFirstTextChannel() {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot)
        let server = model.servers.first { $0.name == "Bagel Lab" }!

        model.selectServer(server.id)

        XCTAssertEqual(model.selection.space, .server(server.id))
        XCTAssertEqual(model.selection.serverID, server.id)
        XCTAssertEqual(model.selectedChannel?.kind, .textChannel)
        XCTAssertEqual(model.selectedChannel?.displayName, "general")
    }

    @MainActor
    func testSelectingChannelUpdatesChannelAndServerRoute() {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot)
        let channel = model.snapshot.channelsByID.values.first { $0.displayName == "macos-native" }!

        model.selectChannel(channel.id)

        XCTAssertEqual(model.selection.serverID, channel.serverID)
        XCTAssertEqual(model.selection.channelID, channel.id)
        XCTAssertEqual(model.selection.space, .server(channel.serverID!))
    }

    @MainActor
    func testHomeAndDiscoverClearServerChannelSelection() {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot)
        model.selectServer(model.servers[0].id)

        model.selectHome()
        XCTAssertEqual(model.selection.space, .home)
        XCTAssertNil(model.selection.serverID)
        XCTAssertNil(model.selection.channelID)

        model.selectDiscover()
        XCTAssertEqual(model.selection.space, .discover)
        XCTAssertNil(model.selection.serverID)
        XCTAssertNil(model.selection.channelID)
    }

    @MainActor
    func testToggleMemberPanel() {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot)
        XCTAssertTrue(model.selection.isMemberPanelVisible)
        model.toggleMemberPanel()
        XCTAssertFalse(model.selection.isMemberPanelVisible)
    }

    @MainActor
    func testInvalidSelectedChannelFallsBackSafely() {
        let server = MockShellData.snapshot.serversByID.values.first { $0.name == "Bagel Lab" }!
        let model = MainShellViewModel(
            selection: ShellSelection(space: .server(server.id), serverID: server.id, channelID: "missing"),
            snapshot: MockShellData.snapshot
        )

        XCTAssertEqual(model.selectedChannel?.displayName, "general")
    }

    @MainActor
    func testServerIndexSelectionHandlesValidAndOutOfRangeIndexes() {
        let model = MainShellViewModel(snapshot: MockShellData.snapshot)

        model.selectServer(atOneBasedIndex: 1)
        XCTAssertEqual(model.selection.serverID, model.servers[0].id)

        let selected = model.selection.serverID
        model.selectServer(atOneBasedIndex: 99)
        XCTAssertEqual(model.selection.serverID, selected)
    }

    func testMessageGroupingEmptyInputReturnsEmpty() {
        XCTAssertEqual(MessageGrouping.group([]), [])
    }

    func testMessageGroupingSameAuthorCloseTimeGroupsTogether() {
        let messages = [
            message(id: ulid(milliseconds: 1_000), author: "a", channel: "c"),
            message(id: ulid(milliseconds: 1_000 + 60_000), author: "a", channel: "c")
        ]

        XCTAssertEqual(MessageGrouping.group(messages).map(\.messages.count), [2])
    }

    func testMessageGroupingSameAuthorFarTimeSplits() {
        let messages = [
            message(id: ulid(milliseconds: 1_000), author: "a", channel: "c"),
            message(id: ulid(milliseconds: 1_000 + 10 * 60_000), author: "a", channel: "c")
        ]

        XCTAssertEqual(MessageGrouping.group(messages).map(\.messages.count), [1, 1])
    }

    func testMessageGroupingDifferentAuthorSplits() {
        let messages = [
            message(id: ulid(milliseconds: 1_000), author: "a", channel: "c"),
            message(id: ulid(milliseconds: 2_000), author: "b", channel: "c")
        ]

        XCTAssertEqual(MessageGrouping.group(messages).count, 2)
    }

    func testMessageGroupingDifferentChannelSplits() {
        let messages = [
            message(id: ulid(milliseconds: 1_000), author: "a", channel: "c1"),
            message(id: ulid(milliseconds: 2_000), author: "a", channel: "c2")
        ]

        XCTAssertEqual(MessageGrouping.group(messages).count, 2)
    }

    func testMessageGroupingSystemMessagesSplit() {
        let messages = [
            message(id: ulid(milliseconds: 1_000), author: "a", channel: "c"),
            message(id: ulid(milliseconds: 2_000), author: "a", channel: "c", system: SystemMessage(kind: .text, content: "joined"))
        ]

        XCTAssertEqual(MessageGrouping.group(messages).count, 2)
    }

    func testMessageGroupingRepliesSplitButEditedMessagesDoNot() {
        let messages = [
            message(id: ulid(milliseconds: 1_000), author: "a", channel: "c", edited: true),
            message(id: ulid(milliseconds: 2_000), author: "a", channel: "c"),
            message(id: ulid(milliseconds: 3_000), author: "a", channel: "c", replies: ["reply"])
        ]

        XCTAssertEqual(MessageGrouping.group(messages).map(\.messages.count), [2, 1])
    }

    private func message(
        id: String,
        author: UserID,
        channel: ChannelID,
        system: SystemMessage? = nil,
        edited: Bool = false,
        replies: [MessageID]? = nil
    ) -> Message {
        Message(
            id: MessageID(rawValue: id),
            channelID: channel,
            authorID: author,
            content: system == nil ? "hello" : nil,
            system: system,
            editedAt: edited ? Date() : nil,
            replies: replies
        )
    }

    private func ulid(milliseconds: UInt64) -> String {
        let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
        var value = milliseconds
        var chars = Array(repeating: alphabet[0], count: 10)
        for index in stride(from: 9, through: 0, by: -1) {
            chars[index] = alphabet[Int(value % 32)]
            value /= 32
        }
        return String(chars) + "0000000000000000"
    }
}
