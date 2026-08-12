import XCTest
import StoatAPI
import StoatModels
@testable import StoatRealtime

final class StoatRealtimeTests: XCTestCase {
    private let decoder = JSONDecoder.stoat
    private let encoder = JSONEncoder.stoat

    func testReadyFieldWireNamesMatchDocs() {
        XCTAssertEqual(ReadyField.userSettings.rawValue, "user_settings")
        XCTAssertEqual(ReadyField.channelUnreads.rawValue, "channel_unreads")
        XCTAssertTrue(ReadyField.allCases.contains(.policyChanges))
    }

    func testClientEventEncodingAndRedaction() throws {
        XCTAssertEqual(try jsonObject(.authenticate(token: "secret-token"))["type"] as? String, "Authenticate")
        XCTAssertEqual(try jsonObject(.authenticate(token: "secret-token"))["token"] as? String, "secret-token")
        XCTAssertEqual(try jsonObject(.beginTyping(channel: "channel1"))["channel"] as? String, "channel1")
        XCTAssertEqual(try jsonObject(.endTyping(channel: "channel1"))["channel"] as? String, "channel1")
        XCTAssertEqual(try jsonObject(.ping(data: 42))["data"] as? Int, 42)
        XCTAssertEqual(try jsonObject(.subscribe(serverID: "server1"))["server_id"] as? String, "server1")
        XCTAssertFalse(ClientGatewayEvent.authenticate(token: "secret-token").debugDescription.contains("secret-token"))
    }

    func testURLConstructionUsesVersionFormatReadyAndNoTokenByDefault() throws {
        let environment = StoatAPIEnvironment.production
        let url = try LiveStoatRealtimeClient.makeWebSocketURL(
            environment: environment,
            readyFields: [.users, .servers, .channelUnreads]
        )
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = components?.queryItems ?? []
        XCTAssertEqual(components?.scheme, "wss")
        XCTAssertEqual(items.first(where: { $0.name == "version" })?.value, "1")
        XCTAssertEqual(items.first(where: { $0.name == "format" })?.value, "json")
        XCTAssertEqual(items.filter { $0.name == "ready" }.map(\.value), ["channel_unreads", "servers", "users"])
        XCTAssertNil(items.first(where: { $0.name == "token" }))
    }

    func testTokenURLFallbackRedactsToken() throws {
        let url = try LiveStoatRealtimeClient.makeWebSocketURL(
            environment: .production,
            readyFields: [.users],
            token: "secret-token"
        )
        XCTAssertTrue(url.absoluteString.contains("secret-token"))
        XCTAssertFalse(LiveStoatRealtimeClient.redactedURLDescription(url).contains("secret-token"))
        XCTAssertTrue(LiveStoatRealtimeClient.redactedURLDescription(url).contains("%3Credacted%3E") || LiveStoatRealtimeClient.redactedURLDescription(url).contains("<redacted>"))
    }

    func testDecodesCoreEventsAndUnknownEvent() throws {
        XCTAssertEqual(try decodeFixture("authenticated"), .authenticated)
        XCTAssertEqual(try decodeFixture("error_invalid_session"), .error(.invalidSession))
        XCTAssertEqual(try decodeFixture("logout"), .logout)
        XCTAssertEqual(try decodeFixture("pong"), .pong(data: 42))

        if case let .ready(payload) = try decodeFixture("ready_full") {
            XCTAssertEqual(payload.users?.first?.id, "user1")
            XCTAssertEqual(payload.servers?.first?.id, "server1")
            XCTAssertEqual(payload.channels?.first?.id, "channel1")
            XCTAssertEqual(payload.channelUnreads?.first?.id.channelID, "channel1")
            XCTAssertEqual(payload.userSettings?.values["ordering"], .string("alpha"))
        } else {
            XCTFail("Expected Ready")
        }

        if case let .unknown(type, raw) = try decodeFixture("unknown_event") {
            XCTAssertEqual(type, "FutureEvent")
            XCTAssertNotNil(raw)
        } else {
            XCTFail("Expected unknown")
        }

        XCTAssertThrowsError(try decodeFixture("malformed_event"))
    }

    func testDecodesMessageChannelServerUserEmojiAndAuthEvents() throws {
        XCTAssertEvent("message") { if case .message = $0 { true } else { false } }
        XCTAssertEvent("message_update") { if case .messageUpdate = $0 { true } else { false } }
        XCTAssertEvent("message_append") { if case .messageAppend = $0 { true } else { false } }
        XCTAssertEvent("message_delete") { if case .messageDelete = $0 { true } else { false } }
        XCTAssertEvent("message_react") { if case .messageReact = $0 { true } else { false } }
        XCTAssertEvent("message_unreact") { if case .messageUnreact = $0 { true } else { false } }
        XCTAssertEvent("message_remove_reaction") { if case .messageRemoveReaction = $0 { true } else { false } }
        XCTAssertEvent("channel_create") { if case .channelCreate = $0 { true } else { false } }
        XCTAssertEvent("channel_update") { if case .channelUpdate = $0 { true } else { false } }
        XCTAssertEvent("channel_delete") { if case .channelDelete = $0 { true } else { false } }
        XCTAssertEvent("typing_start") { if case .channelStartTyping = $0 { true } else { false } }
        XCTAssertEvent("typing_stop") { if case .channelStopTyping = $0 { true } else { false } }
        XCTAssertEvent("channel_ack") { if case .channelAck = $0 { true } else { false } }
        XCTAssertEvent("server_create") { if case .serverCreate = $0 { true } else { false } }
        XCTAssertEvent("server_update") { if case .serverUpdate = $0 { true } else { false } }
        XCTAssertEvent("server_delete") { if case .serverDelete = $0 { true } else { false } }
        XCTAssertEvent("server_member_join") { if case .serverMemberJoin = $0 { true } else { false } }
        XCTAssertEvent("server_member_leave") { if case .serverMemberLeave = $0 { true } else { false } }
        XCTAssertEvent("server_member_update") { if case .serverMemberUpdate = $0 { true } else { false } }
        XCTAssertEvent("server_role_update") { if case .serverRoleUpdate = $0 { true } else { false } }
        XCTAssertEvent("server_role_delete") { if case .serverRoleDelete = $0 { true } else { false } }
        XCTAssertEvent("user_update") { if case .userUpdate = $0 { true } else { false } }
        XCTAssertEvent("user_relationship") { if case .userRelationship = $0 { true } else { false } }
        XCTAssertEvent("user_platform_wipe") { if case .userPlatformWipe = $0 { true } else { false } }
        XCTAssertEvent("emoji_create") { if case .emojiCreate = $0 { true } else { false } }
        XCTAssertEvent("emoji_update") { if case .emojiUpdate = $0 { true } else { false } }
        XCTAssertEvent("emoji_delete") { if case .emojiDelete = $0 { true } else { false } }
        XCTAssertEvent("auth_delete_session") { if case .auth(.deleteSession) = $0 { true } else { false } }
    }

    func testPhase75ServerMemberUpdateDecodesVoiceChannelAndCanPublishReceive() throws {
        let json = """
        {
          "type": "ServerMemberUpdate",
          "id": { "server": "phase75-server", "user": "phase75-user" },
          "data": { "voice_channel": "phase75-voice-channel", "can_publish": false, "can_receive": true },
          "clear": []
        }
        """
        let event = try decoder.decode(StoatGatewayEvent.self, from: Data(json.utf8))
        guard case let .serverMemberUpdate(update) = event else {
            return XCTFail("Expected serverMemberUpdate")
        }
        XCTAssertEqual(update.data.voiceChannel, "phase75-voice-channel")
        XCTAssertEqual(update.data.canPublish, false)
        XCTAssertEqual(update.data.canReceive, true)
    }

    func testPhase75RealtimeStateStoreAppliesVoiceChannelJoinAndLeave() async throws {
        let store = RealtimeStateStore()
        var iterator = store.updates.makeAsyncIterator()
        let serverID: ServerID = "phase75-server"
        let userID: UserID = "phase75-user"
        let voiceChannelID: ChannelID = "phase75-voice-channel"
        let member = ServerMember(id: MemberCompositeKey(serverID: serverID, userID: userID), joinedAt: Date())

        _ = await store.apply(.serverMemberJoin(ServerMemberJoinEvent(id: serverID, userID: userID, member: member)))
        _ = await iterator.next()

        // Joining voice rides the existing ServerMemberUpdate event, not a dedicated voice event.
        let joinJSON = """
        {
          "type": "ServerMemberUpdate",
          "id": { "server": "\(serverID.rawValue)", "user": "\(userID.rawValue)" },
          "data": { "voice_channel": "\(voiceChannelID.rawValue)" },
          "clear": []
        }
        """
        let joinEvent = try decoder.decode(StoatGatewayEvent.self, from: Data(joinJSON.utf8))
        let joinUpdate = await store.apply(joinEvent)
        let joinPublished = await iterator.next()

        let key = ServerMemberKey(serverID: serverID, userID: userID)
        XCTAssertEqual(joinUpdate.snapshot.membersByServerAndUserID[key]?.voiceChannel, voiceChannelID)
        XCTAssertEqual(joinPublished?.snapshot.membersByServerAndUserID[key]?.voiceChannel, voiceChannelID)

        // Leaving clears the field via the documented "VoiceChannel" clear key, mirroring
        // MemberEditRemovedField.voiceChannel.
        let leaveJSON = """
        {
          "type": "ServerMemberUpdate",
          "id": { "server": "\(serverID.rawValue)", "user": "\(userID.rawValue)" },
          "data": {},
          "clear": ["VoiceChannel"]
        }
        """
        let leaveEvent = try decoder.decode(StoatGatewayEvent.self, from: Data(leaveJSON.utf8))
        let leaveUpdate = await store.apply(leaveEvent)

        XCTAssertNil(leaveUpdate.snapshot.membersByServerAndUserID[key]?.voiceChannel)
    }

    func testBulkDecodesAndClientFlattensEvents() async throws {
        if case let .bulk(events) = try decodeFixture("bulk_messages") {
            XCTAssertEqual(events.count, 2)
        } else {
            XCTFail("Expected Bulk")
        }

        let transport = ScriptedWebSocketTransport(receiveQueue: [
            .success(try fixture("authenticated")),
            .success(try fixture("ready_minimal")),
            .success(try fixture("bulk_messages"))
        ])
        let client = LiveStoatRealtimeClient(
            transportFactory: ScriptedWebSocketTransportFactory(transports: [transport]),
            configuration: RealtimeClientConfiguration(pingInterval: .seconds(60), reconnectPolicy: ReconnectPolicy(maximumAttempts: 0))
        )
        var iterator = client.events.makeAsyncIterator()
        try await client.connect(credential: .sessionToken("token"), environment: .production, readyFields: [.users])
        _ = await iterator.next()
        _ = await iterator.next()
        let firstBulkItem = await iterator.next()
        let secondBulkItem = await iterator.next()
        if case .message = firstBulkItem, case .message = secondBulkItem {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected flattened bulk message events")
        }
        await client.disconnect()
    }

    func testConnectSendsAuthenticateAndTransitionsReady() async throws {
        let transport = ScriptedWebSocketTransport(receiveQueue: [
            .success(try fixture("authenticated")),
            .success(try fixture("ready_minimal"))
        ])
        let client = LiveStoatRealtimeClient(
            transportFactory: ScriptedWebSocketTransportFactory(transports: [transport]),
            configuration: RealtimeClientConfiguration(pingInterval: .seconds(60), reconnectPolicy: ReconnectPolicy(maximumAttempts: 0))
        )
        var states = client.connectionState.makeAsyncIterator()
        try await client.connect(credential: .sessionToken("token"), environment: .production, readyFields: [.users])
        var observed: [RealtimeConnectionState] = []
        for _ in 0..<5 {
            if let state = await states.next() {
                observed.append(state)
                if state == .ready { break }
            }
        }
        XCTAssertTrue(transport.sentTexts.contains { $0.contains(#""type":"Authenticate""#) && $0.contains("token") })
        XCTAssertTrue(observed.contains(.connecting))
        XCTAssertTrue(observed.contains(.authenticating))
        XCTAssertTrue(observed.contains(.authenticated))
        XCTAssertTrue(observed.contains(.ready))
        await client.disconnect()
    }

    func testPingLoopAndPongDiagnostics() async throws {
        let transport = ScriptedWebSocketTransport(receiveQueue: [
            .success(try fixture("authenticated")),
            .success(try fixture("ready_minimal"))
        ])
        let client = LiveStoatRealtimeClient(
            transportFactory: ScriptedWebSocketTransportFactory(transports: [transport]),
            configuration: RealtimeClientConfiguration(pingInterval: .milliseconds(20), reconnectPolicy: ReconnectPolicy(maximumAttempts: 0))
        )
        var diagnostics = client.diagnosticsStream.makeAsyncIterator()
        try await client.connect(credential: .sessionToken("token"), environment: .production, readyFields: [.users])
        try await Task.sleep(for: .milliseconds(80))
        transport.enqueueText(try fixture("pong"))
        XCTAssertTrue(transport.sentTexts.contains { $0.contains(#""type":"Ping""#) })
        var sawPong = false
        for _ in 0..<10 {
            if let item = await diagnostics.next(), item.lastPongAt != nil {
                sawPong = true
                break
            }
        }
        XCTAssertTrue(sawPong)
        await client.disconnect()
    }

    func testInvalidSessionFailsWithoutReconnect() async throws {
        let transport = ScriptedWebSocketTransport(receiveQueue: [.success(try fixture("error_invalid_session"))])
        let client = LiveStoatRealtimeClient(
            transportFactory: ScriptedWebSocketTransportFactory(transports: [transport]),
            configuration: RealtimeClientConfiguration(pingInterval: .seconds(60), reconnectPolicy: ReconnectPolicy(maximumAttempts: 3))
        )
        var states = client.connectionState.makeAsyncIterator()
        try await client.connect(credential: .sessionToken("token"), environment: .production, readyFields: [.users])
        var observed: [RealtimeConnectionState] = []
        for _ in 0..<5 {
            if let state = await states.next() {
                observed.append(state)
                if case .failed = state { break }
            }
        }
        XCTAssertTrue(observed.contains(.failed(.authenticationFailed(.invalidSession))))
        XCTAssertFalse(observed.contains { if case .reconnecting = $0 { true } else { false } })
        await client.disconnect()
    }

    func testUnexpectedCloseSchedulesReconnectAndExplicitDisconnectStopsIt() async throws {
        let first = ScriptedWebSocketTransport(receiveQueue: [
            .success(try fixture("authenticated")),
            .success(try fixture("ready_minimal")),
            .failure(RealtimeError.transport("closed"))
        ])
        let second = ScriptedWebSocketTransport(receiveQueue: [
            .success(try fixture("authenticated")),
            .success(try fixture("ready_minimal"))
        ])
        let client = LiveStoatRealtimeClient(
            transportFactory: ScriptedWebSocketTransportFactory(transports: [first, second]),
            configuration: RealtimeClientConfiguration(
                pingInterval: .seconds(60),
                reconnectPolicy: ReconnectPolicy(initialDelay: .milliseconds(10), maximumDelay: .milliseconds(20), maximumAttempts: 2)
            )
        )
        var states = client.connectionState.makeAsyncIterator()
        try await client.connect(credential: .sessionToken("token"), environment: .production, readyFields: [.users])
        var sawReconnect = false
        for _ in 0..<10 {
            if let state = await states.next(), case .reconnecting = state {
                sawReconnect = true
                break
            }
        }
        XCTAssertTrue(sawReconnect)
        await client.disconnect()
        XCTAssertFalse(first.closeCalls.isEmpty)
    }

    func testReducerHydratesAndAppliesCommonEvents() async throws {
        let store = RealtimeStateStore(messageCapPerChannel: 1)
        await store.apply(try decodeFixture("ready_full"))
        var snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.usersByID["user1"]?.username, "enka")
        XCTAssertEqual(snapshot.serversByID["server1"]?.name, "Bagel Server")
        XCTAssertEqual(snapshot.channelsByID["channel1"]?.name, "general")

        await store.apply(try decodeFixture("message"))
        await store.apply(try decodeFixture("message_update"))
        await store.apply(try decodeFixture("message_react"))
        await store.apply(try decodeFixture("typing_start"))
        await store.apply(try decodeFixture("channel_ack"))
        snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.messagesByChannelID["channel1"]?.first?.content, "edited")
        XCTAssertEqual(snapshot.messagesByChannelID["channel1"]?.first?.reactions["smile"], ["user1"])
        XCTAssertEqual(snapshot.typingUsersByChannelID["channel1"], ["user1"])
        XCTAssertEqual(snapshot.unreadsByChannelID["channel1"]?.lastMessageID, "msg1")

        await store.apply(try decodeFixture("typing_stop"))
        await store.apply(try decodeFixture("message_delete"))
        snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.typingUsersByChannelID["channel1"], [])
        XCTAssertEqual(snapshot.messagesByChannelID["channel1"], [])
    }

    func testPhase29ReadyHydrationKeepsLastDuplicateMemberWithoutCrashing() async {
        let store = RealtimeStateStore()
        let user = User(id: "phase29-user", username: "first")
        let updatedUser = User(id: "phase29-user", username: "second", displayName: "Second")
        let memberID = MemberCompositeKey(serverID: "phase29-server", userID: "phase29-user")
        let firstMember = ServerMember(id: memberID, joinedAt: Date(), nickname: "First")
        let lastMember = ServerMember(id: memberID, joinedAt: Date(), nickname: "Last")
        await store.apply(.ready(ReadyPayload(users: [user, updatedUser], members: [firstMember, lastMember])))

        let snapshot = await store.snapshot()

        XCTAssertEqual(snapshot.usersByID["phase29-user"]?.displayName, "Second")
        XCTAssertEqual(snapshot.membersByServerAndUserID[ServerMemberKey(memberID)]?.nickname, "Last")
    }

    func testMessageCapIsEnforced() async {
        let store = RealtimeStateStore(messageCapPerChannel: 1)
        await store.apply(.message(Message(id: "msg1", channelID: "channel1", authorID: "user1", content: "1")))
        await store.apply(.message(Message(id: "msg2", channelID: "channel1", authorID: "user1", content: "2")))
        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.messagesByChannelID["channel1"]?.map(\.id), ["msg2"])
    }

    func testPhase52BulkPublishesOneAtomicUpdateWithUnionedChanges() async {
        let store = RealtimeStateStore()
        var iterator = store.updates.makeAsyncIterator()
        let channelID: ChannelID = "phase52-channel"
        let first = Message(id: "phase52-message-1", channelID: channelID, authorID: "phase52-user", content: "one")
        let second = Message(id: "phase52-message-2", channelID: channelID, authorID: "phase52-user", content: "two")

        let returned = await store.apply(.bulk([.message(first), .message(second)]))
        let published = await iterator.next()

        XCTAssertEqual(returned, published)
        XCTAssertEqual(published?.changes.messageChannelIDs, [channelID])
        XCTAssertEqual(published?.changes.insertedMessages.map(\.id), [first.id, second.id])
        XCTAssertEqual(published?.snapshot.messagesByChannelID[channelID]?.map(\.id), [first.id, second.id])
    }

    func testPendingRealtimeUpdatesCoalesceLatestSnapshotAndAllChanges() async {
        let store = RealtimeStateStore()
        var iterator = store.updates.makeAsyncIterator()
        let firstChannelID: ChannelID = "coalesce-first"
        let secondChannelID: ChannelID = "coalesce-second"
        let first = Message(id: "coalesce-message-1", channelID: firstChannelID, authorID: "coalesce-user", content: "one")
        let second = Message(id: "coalesce-message-2", channelID: secondChannelID, authorID: "coalesce-user", content: "two")

        await store.apply(.message(first))
        await store.apply(.message(second))
        let published = await iterator.next()

        XCTAssertEqual(published?.changes.messageChannelIDs, [firstChannelID, secondChannelID])
        XCTAssertEqual(published?.changes.insertedMessages.map(\.id), [first.id, second.id])
        XCTAssertEqual(published?.snapshot.messagesByChannelID[firstChannelID]?.map(\.id), [first.id])
        XCTAssertEqual(published?.snapshot.messagesByChannelID[secondChannelID]?.map(\.id), [second.id])
        XCTAssertEqual(store.coalescedUpdateCount, 1)
    }

    func testEmptyControlUpdateIsReturnedButNotPublished() async {
        let store = RealtimeStateStore()
        var iterator = store.updates.makeAsyncIterator()
        let empty = await store.apply(.pong(data: 42))
        let message = Message(id: "after-pong", channelID: "pong-channel", authorID: "pong-user", content: "visible")
        await store.apply(.message(message))
        let published = await iterator.next()

        XCTAssertTrue(empty.changes.isEmpty)
        XCTAssertEqual(published?.changes.insertedMessages.map(\.id), [message.id])
    }

    func testCoalescingInsertThenDeletePublishesNetDeletionWithoutStaleInsert() async {
        let store = RealtimeStateStore()
        var iterator = store.updates.makeAsyncIterator()
        let channelID: ChannelID = "coalesce-delete-channel"
        let message = Message(id: "coalesce-delete-message", channelID: channelID, authorID: "coalesce-user", content: "temporary")

        await store.apply(.message(message))
        await store.apply(.messageDelete(MessageDeleteEvent(id: message.id, channelID: channelID)))
        let published = await iterator.next()

        XCTAssertTrue(published?.changes.insertedMessages.isEmpty == true)
        XCTAssertEqual(published?.changes.deletedMessageIDsByChannelID[channelID], [message.id])
        XCTAssertTrue(published?.snapshot.messagesByChannelID[channelID]?.isEmpty != false)
    }

    private func jsonObject(_ event: ClientGatewayEvent) throws -> [String: Any] {
        let data = try encoder.encode(event)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func decodeFixture(_ name: String) throws -> StoatGatewayEvent {
        try decoder.decode(StoatGatewayEvent.self, from: Data(fixture(name).utf8))
    }

    private func fixture(_ name: String) throws -> String {
        let url = Bundle.module.url(forResource: name, withExtension: "json")!
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func XCTAssertEvent(_ fixtureName: String, matches: (StoatGatewayEvent) -> Bool, file: StaticString = #filePath, line: UInt = #line) {
        do {
            let event = try decodeFixture(fixtureName)
            XCTAssertTrue(matches(event), file: file, line: line)
        } catch {
            XCTFail("Failed to decode \(fixtureName): \(error)", file: file, line: line)
        }
    }
}
