import XCTest
@testable import StoatModels

final class StoatModelsTests: XCTestCase {
    func testIDWrappersEncodeDecodeAndHash() throws {
        let userID: UserID = "user_123"
        let data = try JSONEncoder.stoat.encode(userID)
        let decoded = try JSONDecoder.stoat.decode(UserID.self, from: data)

        XCTAssertEqual(decoded, userID)
        XCTAssertEqual(Set([decoded, userID]).count, 1)
        XCTAssertEqual(decoded.rawValue, "user_123")
    }

    func testDecodeUserFixture() throws {
        let user = try decodeFixture(User.self, named: "user")

        XCTAssertEqual(user.id.rawValue, "01HX0000000000000000000001")
        XCTAssertEqual(user.displayName, "Liquid Bagel")
        XCTAssertEqual(user.status?.presence, .online)
        XCTAssertEqual(user.relationship, .user)
    }

    func testDecodeServerFixture() throws {
        let server = try decodeFixture(Server.self, named: "server")

        XCTAssertEqual(server.name, "Bagel Lab")
        XCTAssertEqual(server.channelIDs.count, 2)
        XCTAssertTrue(server.defaultPermissions.contains(.sendMessage))
        XCTAssertEqual(server.roles.first?.value.permissions.allow.contains(.uploadFiles), true)
    }

    func testDecodeTextAndDMChannels() throws {
        let text = try decodeFixture(Channel.self, named: "channel_text")
        let dm = try decodeFixture(Channel.self, named: "channel_dm")

        XCTAssertEqual(text.kind, .textChannel)
        XCTAssertEqual(text.serverID?.rawValue, "01HX0000000000000000000201")
        XCTAssertEqual(text.voice?.maxUsers, 8)
        XCTAssertEqual(dm.kind, .directMessage)
        XCTAssertEqual(dm.recipients.count, 2)
    }

    func testDecodeMessagesAndFileMetadata() throws {
        let basic = try decodeFixture(Message.self, named: "message_basic")
        let attachment = try decodeFixture(Message.self, named: "message_with_attachments")
        let reactions = try decodeFixture(Message.self, named: "message_with_reactions")

        XCTAssertEqual(basic.content, "Hello from a fixture.")
        XCTAssertEqual(basic.mentions?.first?.rawValue, "01HX0000000000000000000002")
        XCTAssertEqual(attachment.attachments?.first?.filename, "notes.png")
        XCTAssertEqual(attachment.isSuppressed, true)
        XCTAssertEqual(reactions.reactions["🥯"]?.count, 2)
        XCTAssertTrue(reactions.isPinned)
        XCTAssertTrue(reactions.mentionsEveryone)
    }

    func testUnknownEnumCasesDecodeSafely() throws {
        let channelKind = try JSONDecoder.stoat.decode(ChannelKind.self, from: Data(#""ForumChannel""#.utf8))
        let relationship = try JSONDecoder.stoat.decode(RelationshipStatus.self, from: Data(#""BestFriend""#.utf8))
        let presence = try JSONDecoder.stoat.decode(Presence.self, from: Data(#""Away""#.utf8))

        XCTAssertEqual(channelKind, .unknown("ForumChannel"))
        XCTAssertEqual(relationship, .unknown("BestFriend"))
        XCTAssertEqual(presence, .unknown("Away"))
    }

    func testMessageULIDCreatedAt() throws {
        let message = try decodeFixture(Message.self, named: "message_basic")

        XCTAssertEqual(message.createdAt?.timeIntervalSince1970 ?? 0, 1_469_922_850.259, accuracy: 0.001)
    }

    func testPermissionsDecodeAndCombine() throws {
        let cases: [(Permissions, UInt64)] = [
            (.manageChannel, 1 << 0),
            (.manageServer, 1 << 1),
            (.managePermissions, 1 << 2),
            (.manageRole, 1 << 3),
            (.manageCustomisation, 1 << 4),
            (.kickMembers, 1 << 6),
            (.banMembers, 1 << 7),
            (.timeoutMembers, 1 << 8),
            (.assignRoles, 1 << 9),
            (.changeNickname, 1 << 10),
            (.manageNicknames, 1 << 11),
            (.changeAvatar, 1 << 12),
            (.removeAvatars, 1 << 13),
            (.viewChannel, 1 << 20),
            (.readMessageHistory, 1 << 21),
            (.sendMessage, 1 << 22),
            (.manageMessages, 1 << 23),
            (.manageWebhooks, 1 << 24),
            (.inviteOthers, 1 << 25),
            (.sendEmbeds, 1 << 26),
            (.uploadFiles, 1 << 27),
            (.masquerade, 1 << 28),
            (.react, 1 << 29),
            (.connect, 1 << 30),
            (.speak, 1 << 31),
            (.video, 1 << 32),
            (.muteMembers, 1 << 33),
            (.deafenMembers, 1 << 34),
            (.moveMembers, 1 << 35),
            (.listen, 1 << 36),
            (.mentionEveryone, 1 << 37),
            (.mentionRoles, 1 << 38),
            (.bypassSlowmode, 1 << 39)
        ]

        for (permission, rawValue) in cases {
            let decoded = try JSONDecoder.stoat.decode(Permissions.self, from: Data(String(rawValue).utf8))
            XCTAssertEqual(decoded, permission)
        }

        let combined: Permissions = [.sendMessage, .uploadFiles]
        XCTAssertTrue(combined.contains(.sendMessage))
        XCTAssertTrue(combined.contains(.uploadFiles))
        XCTAssertFalse(combined.contains(.manageMessages))

        let highBit = UInt64(1) << 50
        let decodedHigh = try JSONDecoder.stoat.decode(Permissions.self, from: Data(String(highBit).utf8))
        XCTAssertEqual(decodedHigh.rawValue, highBit)
    }

    func testDecodeConfigFixture() throws {
        let config = try decodeFixture(StoatConfig.self, named: "config")

        XCTAssertEqual(config.ws, "wss://events.stoat.chat")
        XCTAssertEqual(config.features.autumn.url, "https://cdn.stoatusercontent.com")
        XCTAssertEqual(config.features.limits.global.groupSize, 100)
    }

    func testDecodeUserSettingsPlaceholder() throws {
        let settings = try JSONDecoder.stoat.decode(UserSettings.self, from: Data(#"{"ordering":["a","b"],"compact":true}"#.utf8))

        XCTAssertEqual(settings.values["compact"], .bool(true))
    }

    func testPhase41UserProfileEditDraftEncodesVerifiedFieldsAndOmitsNil() throws {
        let draft = UserEditDraft(
            displayName: "Liquid Tester",
            avatar: "avatar-file",
            profile: UserProfileEditDraft(content: "hello profile", background: "background-file")
        )
        let object = try encodedJSONObject(draft)

        XCTAssertEqual(object["display_name"] as? String, "Liquid Tester")
        XCTAssertEqual(object["avatar"] as? String, "avatar-file")
        let profile = try XCTUnwrap(object["profile"] as? [String: Any])
        XCTAssertEqual(profile["content"] as? String, "hello profile")
        XCTAssertEqual(profile["background"] as? String, "background-file")
        XCTAssertNil(object["status"])
        XCTAssertNil(object["badges"])
        XCTAssertNil(object["flags"])
    }

    func testPhase41UserProfileEditDraftPartialProfileOmitsNilFields() throws {
        let object = try encodedJSONObject(UserEditDraft(profile: UserProfileEditDraft(content: "bio")))
        let profile = try XCTUnwrap(object["profile"] as? [String: Any])

        XCTAssertEqual(profile["content"] as? String, "bio")
        XCTAssertNil(profile["background"])
        XCTAssertNil(object["display_name"])
        XCTAssertNil(object["avatar"])
        XCTAssertNil(object["status"])
    }

    func testPhase41UserEditRemoveFieldsEncodeExactSourceStrings() throws {
        let object = try encodedJSONObject(UserEditDraft(remove: [.displayName, .avatar, .profileContent, .profileBackground]))
        let remove = try XCTUnwrap(object["remove"] as? [String])

        XCTAssertEqual(Set(remove), Set(["DisplayName", "Avatar", "ProfileContent", "ProfileBackground"]))
    }

    func testPhase42ModerationModelsDecodeBanListAndOptionalFields() throws {
        let data = Data(#"{"users":[{"_id":"user-2","username":"target","discriminator":"0001"}],"bans":[{"_id":{"server":"server-1","user":"user-2"}},{"_id":{"server":"server-1","user":"user-3"},"reason":"spam"}]}"#.utf8)
        let result = try JSONDecoder.stoat.decode(BanListResult.self, from: data)

        XCTAssertEqual(result.users.first?.id, "user-2")
        XCTAssertEqual(result.users.first?.username, "target")
        XCTAssertNil(result.users.first?.avatar)
        XCTAssertEqual(result.bans.count, 2)
        XCTAssertNil(result.bans.first?.reason)
        XCTAssertEqual(result.bans.last?.reason, "spam")
    }

    func testPhase42BanCreateDraftEncodesVerifiedCompatibilityFields() throws {
        let object = try encodedJSONObject(BanCreateDraft(reason: "spam", deleteMessageSeconds: 3600))

        XCTAssertEqual(object["reason"] as? String, "spam")
        XCTAssertEqual(object["delete_message_seconds"] as? Int, 3600)
    }

    func testPhase42TimeoutApplyAndClearDraftsEncodeExactFields() throws {
        let timeout = Date(timeIntervalSince1970: 1_801_440_000)
        let apply = try encodedJSONObject(MemberEditDraft(timeout: timeout))
        let clear = try encodedJSONObject(MemberEditDraft(remove: [.timeout]))

        XCTAssertNotNil(apply["timeout"])
        XCTAssertEqual(apply["remove"] as? [String], [])
        XCTAssertEqual(clear["remove"] as? [String], ["Timeout"])
        XCTAssertNil(clear["timeout"])
    }

    func testPhase53SlowmodeAndEmojiDraftsEncodeVerifiedFields() throws {
        let channel = Channel(
            id: "channel-1",
            kind: .textChannel,
            serverID: "server-1",
            name: "general",
            slowmode: 5
        )
        let slowmode = try XCTUnwrap(
            ChannelEditDraft(slowmode: 30).validatedForEdit(original: channel)
        )
        let slowmodeObject = try encodedJSONObject(slowmode)
        XCTAssertEqual(slowmodeObject["slowmode"] as? Int, 30)

        let emoji = try XCTUnwrap(
            EmojiCreateDraft(name: " bagel ", serverID: "server-1").validated
        )
        let emojiObject = try encodedJSONObject(emoji)
        XCTAssertEqual(emojiObject["name"] as? String, "bagel")
        XCTAssertEqual(
            (emojiObject["parent"] as? [String: Any])?["type"] as? String,
            "Server"
        )
        XCTAssertEqual(
            (emojiObject["parent"] as? [String: Any])?["id"] as? String,
            "server-1"
        )
    }

    private func decodeFixture<T: Decodable>(_ type: T.Type, named name: String) throws -> T {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        let data = try Data(contentsOf: url)
        return try JSONDecoder.stoat.decode(type, from: data)
    }

    private func encodedJSONObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder.stoat.encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
