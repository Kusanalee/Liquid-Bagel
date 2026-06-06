import XCTest
import StoatModels
@testable import StoatAPI

final class StoatAPITests: XCTestCase {
    func testProductionEnvironmentUsesCurrentDocumentedDefaults() throws {
        let environment = StoatAPIEnvironment.production

        XCTAssertEqual(environment.apiBaseURL.absoluteString, "https://api.stoat.chat")
        XCTAssertEqual(environment.eventsURL.absoluteString, "wss://events.stoat.chat")
        XCTAssertEqual(environment.mediaBaseURL?.absoluteString, "https://cdn.stoatusercontent.com")
        XCTAssertNoThrow(try environment.validate())
    }

    func testEnvironmentValidationAllowsLocalhostAndRejectsInsecureRemote() throws {
        XCTAssertNoThrow(try StoatAPIEnvironment.custom(
            apiBaseURL: URL(string: "http://localhost:8080")!,
            eventsURL: URL(string: "ws://localhost:9000")!
        ))

        XCTAssertThrowsError(try StoatAPIEnvironment.custom(
            apiBaseURL: URL(string: "http://example.com")!,
            eventsURL: URL(string: "wss://events.example.com")!
        ))
    }

    func testAuthenticationHeaderNamesAndRedaction() {
        let user = StoatAuthCredential.userSession(token: "secret-user-token", sessionID: "session-1")
        let bot = StoatAuthCredential.botToken("secret-bot-token")

        XCTAssertEqual(user.headerName, "X-Session-Token")
        XCTAssertEqual(bot.headerName, "X-Bot-Token")
        XCTAssertEqual(user.token, "secret-user-token")
        XCTAssertFalse(user.redactedDescription.contains("secret-user-token"))
        XCTAssertFalse(bot.debugDescription.contains("secret-bot-token"))
    }

    func testInMemoryTokenStoreRoundTrip() async throws {
        let store = InMemoryTokenStore()
        let credential = StoatAuthCredential.userSession(token: "secret", sessionID: "session")

        let emptyCredential = try await store.loadCredential()
        XCTAssertNil(emptyCredential)
        try await store.saveCredential(credential)
        let loadedCredential = try await store.loadCredential()
        XCTAssertEqual(loadedCredential, credential)
        try await store.clearCredential()
        let clearedCredential = try await store.loadCredential()
        XCTAssertNil(clearedCredential)
    }

    func testScopedInMemoryTokenStoreSeparatesEnvironments() async throws {
        let store = InMemoryTokenStore()
        let production = CredentialScope(environmentID: "production")
        let custom = CredentialScope(environmentID: "custom-http-localhost-14702")

        try await store.saveCredential(.sessionToken("prod-secret"), scope: production)
        try await store.saveCredential(.sessionToken("custom-secret"), scope: custom)

        let productionCredential = try await store.loadCredential(scope: production)
        let customCredential = try await store.loadCredential(scope: custom)
        XCTAssertEqual(productionCredential?.token, "prod-secret")
        XCTAssertEqual(customCredential?.token, "custom-secret")
        try await store.clearCredential(scope: production)
        let clearedProductionCredential = try await store.loadCredential(scope: production)
        let remainingCustomCredential = try await store.loadCredential(scope: custom)
        XCTAssertNil(clearedProductionCredential)
        XCTAssertEqual(remainingCustomCredential?.token, "custom-secret")
    }

    func testEnvironmentStableIDAndScopedKeychainAccountNames() throws {
        let custom = try StoatAPIEnvironment.custom(
            apiBaseURL: URL(string: "http://localhost:14702")!,
            eventsURL: URL(string: "ws://localhost:14703")!,
            mediaBaseURL: URL(string: "http://localhost:14704")!
        )
        let scope = CredentialScope(environmentID: custom.stableID, accountUserID: "user-1")

        XCTAssertEqual(StoatAPIEnvironment.production.stableID, "production")
        XCTAssertTrue(custom.stableID.hasPrefix("custom-"))
        XCTAssertTrue(scope.keychainAccountName.contains(custom.stableID))
        XCTAssertTrue(scope.keychainAccountName.contains("user-1"))
    }

    func testSessionLoginModelsDecodeAndRedactTokens() throws {
        let data = Data(#"{"result":"Success","_id":"session-1","user_id":"user-1","token":"login-secret","name":"Liquid Bagel macOS","last_seen":"2026-05-29T00:00:00.000Z"}"#.utf8)
        let response = try JSONDecoder.stoat.decode(SessionLoginResponse.self, from: data)

        guard case let .success(success) = response else {
            return XCTFail("Expected success")
        }
        XCTAssertEqual(success.credential.token, "login-secret")
        XCTAssertFalse(success.debugDescription.contains("login-secret"))

        let stored = StoredSessionCredential(credential: success.credential, scope: .production, currentUserID: "user-1")
        XCTAssertFalse(stored.debugDescription.contains("login-secret"))
    }

    func testSessionListEndpointRequest() async throws {
        let transport = RecordingHTTPTransport(data: Data(#"[{"_id":"01J00000000000000000000001","name":"Mac"}]"#.utf8))
        let client = LiveStoatAPIClient(
            credentialProvider: StaticCredentialProvider(.sessionToken("secret")),
            transport: transport
        )

        let sessions = try await client.fetchSessions()
        let capturedRequest = await transport.lastRequest()
        let request = try XCTUnwrap(capturedRequest)

        XCTAssertEqual(sessions.first?.name, "Mac")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/auth/session/all")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Session-Token"), "secret")
    }

    func testSessionRenameEndpointRequest() async throws {
        let transport = RecordingHTTPTransport(data: Data(#"{"_id":"session-1","name":"Renamed"}"#.utf8))
        let client = LiveStoatAPIClient(
            credentialProvider: StaticCredentialProvider(.sessionToken("secret")),
            transport: transport
        )

        let session = try await client.renameSession(id: "session-1", friendlyName: "Renamed")
        let capturedRequest = await transport.lastRequest()
        let request = try XCTUnwrap(capturedRequest)
        let body = String(data: try XCTUnwrap(request.httpBody), encoding: .utf8)

        XCTAssertEqual(session.name, "Renamed")
        XCTAssertEqual(request.httpMethod, "PATCH")
        XCTAssertEqual(request.url?.path, "/auth/session/session-1")
        XCTAssertTrue(body?.contains(#""friendly_name":"Renamed""#) == true)
    }

    func testSessionRevokeEndpointRequests() async throws {
        let revokeTransport = RecordingHTTPTransport(statusCode: 204)
        let revokeClient = LiveStoatAPIClient(
            credentialProvider: StaticCredentialProvider(.sessionToken("secret")),
            transport: revokeTransport
        )

        try await revokeClient.revokeSession(id: "session-1")
        let capturedRevokeRequest = await revokeTransport.lastRequest()
        let revokeRequest = try XCTUnwrap(capturedRevokeRequest)
        XCTAssertEqual(revokeRequest.httpMethod, "DELETE")
        XCTAssertEqual(revokeRequest.url?.path, "/auth/session/session-1")

        let revokeAllTransport = RecordingHTTPTransport(statusCode: 204)
        let revokeAllClient = LiveStoatAPIClient(
            credentialProvider: StaticCredentialProvider(.sessionToken("secret")),
            transport: revokeAllTransport
        )

        try await revokeAllClient.revokeAllSessions(revokeSelf: false)
        let capturedRevokeAllRequest = await revokeAllTransport.lastRequest()
        let revokeAllRequest = try XCTUnwrap(capturedRevokeAllRequest)
        XCTAssertEqual(revokeAllRequest.httpMethod, "DELETE")
        XCTAssertEqual(revokeAllRequest.url?.path, "/auth/session/all")
        XCTAssertEqual(URLComponents(url: try XCTUnwrap(revokeAllRequest.url), resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "revoke_self" }?.value, "false")
    }

    func testCurrentSessionLogoutEndpointRequest() async throws {
        let transport = RecordingHTTPTransport(statusCode: 204)
        let client = LiveStoatAPIClient(
            credentialProvider: StaticCredentialProvider(.sessionToken("secret")),
            transport: transport
        )

        try await client.logoutCurrentSession()
        let capturedRequest = await transport.lastRequest()
        let request = try XCTUnwrap(capturedRequest)

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/auth/session/logout")
    }

    func testChannelAckEndpointRequestHasNoBody() async throws {
        let transport = RecordingHTTPTransport(statusCode: 204)
        let client = LiveStoatAPIClient(
            credentialProvider: StaticCredentialProvider(.sessionToken("secret")),
            transport: transport
        )

        try await client.ackChannel(channelID: "channel-1", messageID: "message-1")
        let capturedRequest = await transport.lastRequest()
        let request = try XCTUnwrap(capturedRequest)

        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.path, "/channels/channel-1/ack/message-1")
        XCTAssertNil(request.httpBody)
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Session-Token"), "secret")
    }

    func testPhase24ServerAndChannelManagementEndpointRequests() async throws {
        let serverJSON = Data(#"{"server":{"_id":"server-1","owner":"user-1","name":"Lab","channels":["channel-1"],"default_permissions":0},"channels":[{"_id":"channel-1","channel_type":"TextChannel","server":"server-1","name":"general"}]}"#.utf8)
        let fetchTransport = RecordingHTTPTransport(data: serverJSON)
        let fetchClient = LiveStoatAPIClient(
            credentialProvider: StaticCredentialProvider(.sessionToken("secret")),
            transport: fetchTransport
        )

        let response = try await fetchClient.fetchServer(id: "server-1", includeChannels: true)
        let capturedFetchRequest = await fetchTransport.lastRequest()
        let fetchRequest = try XCTUnwrap(capturedFetchRequest)
        XCTAssertEqual(response.server.id, "server-1")
        XCTAssertEqual(response.channels.first?.id, "channel-1")
        XCTAssertEqual(fetchRequest.httpMethod, "GET")
        XCTAssertEqual(fetchRequest.url?.path, "/servers/server-1")
        XCTAssertEqual(URLComponents(url: try XCTUnwrap(fetchRequest.url), resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "include_channels" }?.value, "true")

        let channelJSON = Data(#"{"_id":"channel-2","channel_type":"TextChannel","server":"server-1","name":"ops","description":"Ops"}"#.utf8)
        let createTransport = RecordingHTTPTransport(data: channelJSON)
        let createClient = LiveStoatAPIClient(
            credentialProvider: StaticCredentialProvider(.sessionToken("secret")),
            transport: createTransport
        )
        _ = try await createClient.createChannel(serverID: "server-1", draft: ChannelCreateDraft(name: "ops", description: "Ops", nsfw: true))
        let capturedCreateRequest = await createTransport.lastRequest()
        let createRequest = try XCTUnwrap(capturedCreateRequest)
        let createBody = String(data: try XCTUnwrap(createRequest.httpBody), encoding: .utf8)
        XCTAssertEqual(createRequest.httpMethod, "POST")
        XCTAssertEqual(createRequest.url?.path, "/servers/server-1/channels")
        XCTAssertTrue(createBody?.contains(#""type":"Text""#) == true)
        XCTAssertTrue(createBody?.contains(#""name":"ops""#) == true)

        let editTransport = RecordingHTTPTransport(data: channelJSON)
        let editClient = LiveStoatAPIClient(
            credentialProvider: StaticCredentialProvider(.sessionToken("secret")),
            transport: editTransport
        )
        _ = try await editClient.editChannel(id: "channel-2", draft: ChannelEditDraft(name: "ops-renamed", description: nil, remove: [.description]))
        let capturedEditRequest = await editTransport.lastRequest()
        let editRequest = try XCTUnwrap(capturedEditRequest)
        let editBody = String(data: try XCTUnwrap(editRequest.httpBody), encoding: .utf8)
        XCTAssertEqual(editRequest.httpMethod, "PATCH")
        XCTAssertEqual(editRequest.url?.path, "/channels/channel-2")
        XCTAssertTrue(editBody?.contains(#""name":"ops-renamed""#) == true)
        XCTAssertTrue(editBody?.contains(#""remove":["Description"]"#) == true)

        let deleteTransport = RecordingHTTPTransport(statusCode: 204)
        let deleteClient = LiveStoatAPIClient(
            credentialProvider: StaticCredentialProvider(.sessionToken("secret")),
            transport: deleteTransport
        )
        try await deleteClient.deleteChannel(id: "channel-2")
        let capturedDeleteRequest = await deleteTransport.lastRequest()
        let deleteRequest = try XCTUnwrap(capturedDeleteRequest)
        XCTAssertEqual(deleteRequest.httpMethod, "DELETE")
        XCTAssertEqual(deleteRequest.url?.path, "/channels/channel-2")
    }

    func testPhase22DirectMessageAndProfileEndpointRequests() async throws {
        let profileTransport = RecordingHTTPTransport(data: Data(#"{"content":"hello"}"#.utf8))
        let profileClient = LiveStoatAPIClient(
            credentialProvider: StaticCredentialProvider(.sessionToken("secret")),
            transport: profileTransport
        )

        let profile = try await profileClient.fetchUserProfile(userID: "user-1")
        let capturedProfileRequest = await profileTransport.lastRequest()
        let profileRequest = try XCTUnwrap(capturedProfileRequest)
        XCTAssertEqual(profile.content, "hello")
        XCTAssertEqual(profileRequest.httpMethod, "GET")
        XCTAssertEqual(profileRequest.url?.path, "/users/user-1/profile")

        let dmsTransport = RecordingHTTPTransport(data: Data(#"[{"_id":"dm-1","channel_type":"DirectMessage","active":true,"recipients":["me","user-1"]}]"#.utf8))
        let dmsClient = LiveStoatAPIClient(
            credentialProvider: StaticCredentialProvider(.sessionToken("secret")),
            transport: dmsTransport
        )

        let dms = try await dmsClient.fetchDirectMessages()
        let capturedDMSRequest = await dmsTransport.lastRequest()
        let dmsRequest = try XCTUnwrap(capturedDMSRequest)
        XCTAssertEqual(dms.first?.id, "dm-1")
        XCTAssertEqual(dmsRequest.httpMethod, "GET")
        XCTAssertEqual(dmsRequest.url?.path, "/users/dms")

        let openTransport = RecordingHTTPTransport(data: Data(#"{"_id":"dm-2","channel_type":"DirectMessage","active":true,"recipients":["me","user-2"]}"#.utf8))
        let openClient = LiveStoatAPIClient(
            credentialProvider: StaticCredentialProvider(.sessionToken("secret")),
            transport: openTransport
        )

        let opened = try await openClient.openDirectMessage(userID: "user-2")
        let capturedOpenRequest = await openTransport.lastRequest()
        let openRequest = try XCTUnwrap(capturedOpenRequest)
        XCTAssertEqual(opened.id, "dm-2")
        XCTAssertEqual(openRequest.httpMethod, "GET")
        XCTAssertEqual(openRequest.url?.path, "/users/user-2/dm")
    }

    func testPhase22RelationshipEndpointRequests() async throws {
        let userJSON = Data(#"{"_id":"user-1","username":"friend","relationship":"Friend","online":true}"#.utf8)

        let sendTransport = RecordingHTTPTransport(data: userJSON)
        let sendClient = LiveStoatAPIClient(
            credentialProvider: StaticCredentialProvider(.sessionToken("secret")),
            transport: sendTransport
        )
        _ = try await sendClient.sendFriendRequest(username: "friend#0000")
        let capturedSendRequest = await sendTransport.lastRequest()
        let sendRequest = try XCTUnwrap(capturedSendRequest)
        let sendBody = String(data: try XCTUnwrap(sendRequest.httpBody), encoding: .utf8)
        XCTAssertEqual(sendRequest.httpMethod, "POST")
        XCTAssertEqual(sendRequest.url?.path, "/users/friend")
        XCTAssertTrue(sendBody?.contains(#""username":"friend#0000""#) == true)

        let acceptTransport = RecordingHTTPTransport(data: userJSON)
        let acceptClient = LiveStoatAPIClient(
            credentialProvider: StaticCredentialProvider(.sessionToken("secret")),
            transport: acceptTransport
        )
        _ = try await acceptClient.acceptFriendRequest(userID: "user-1")
        let capturedAcceptRequest = await acceptTransport.lastRequest()
        let acceptRequest = try XCTUnwrap(capturedAcceptRequest)
        XCTAssertEqual(acceptRequest.httpMethod, "PUT")
        XCTAssertEqual(acceptRequest.url?.path, "/users/user-1/friend")

        let removeTransport = RecordingHTTPTransport(data: userJSON)
        let removeClient = LiveStoatAPIClient(
            credentialProvider: StaticCredentialProvider(.sessionToken("secret")),
            transport: removeTransport
        )
        _ = try await removeClient.removeFriend(userID: "user-1")
        let capturedRemoveRequest = await removeTransport.lastRequest()
        let removeRequest = try XCTUnwrap(capturedRemoveRequest)
        XCTAssertEqual(removeRequest.httpMethod, "DELETE")
        XCTAssertEqual(removeRequest.url?.path, "/users/user-1/friend")

        let blockTransport = RecordingHTTPTransport(data: userJSON)
        let blockClient = LiveStoatAPIClient(
            credentialProvider: StaticCredentialProvider(.sessionToken("secret")),
            transport: blockTransport
        )
        _ = try await blockClient.blockUser(userID: "user-1")
        let capturedBlockRequest = await blockTransport.lastRequest()
        let blockRequest = try XCTUnwrap(capturedBlockRequest)
        XCTAssertEqual(blockRequest.httpMethod, "PUT")
        XCTAssertEqual(blockRequest.url?.path, "/users/user-1/block")

        let unblockTransport = RecordingHTTPTransport(data: userJSON)
        let unblockClient = LiveStoatAPIClient(
            credentialProvider: StaticCredentialProvider(.sessionToken("secret")),
            transport: unblockTransport
        )
        _ = try await unblockClient.unblockUser(userID: "user-1")
        let capturedUnblockRequest = await unblockTransport.lastRequest()
        let unblockRequest = try XCTUnwrap(capturedUnblockRequest)
        XCTAssertEqual(unblockRequest.httpMethod, "DELETE")
        XCTAssertEqual(unblockRequest.url?.path, "/users/user-1/block")
    }

    func testSingleMessageFetchEndpointRequest() async throws {
        let transport = RecordingHTTPTransport(data: Data(#"{"_id":"message-1","channel":"channel-1","author":"user-1","content":"hello"}"#.utf8))
        let client = LiveStoatAPIClient(
            credentialProvider: StaticCredentialProvider(.sessionToken("secret")),
            transport: transport
        )

        let message = try await client.fetchMessage(channelID: "channel-1", messageID: "message-1")
        let capturedRequest = await transport.lastRequest()
        let request = try XCTUnwrap(capturedRequest)

        XCTAssertEqual(message.id, "message-1")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/channels/channel-1/messages/message-1")
    }

    func testNearbyMessageFetchEndpointRequest() async throws {
        let transport = RecordingHTTPTransport(data: Data(#"[{"_id":"message-1","channel":"channel-1","author":"user-1","content":"hello"}]"#.utf8))
        let client = LiveStoatAPIClient(
            credentialProvider: StaticCredentialProvider(.sessionToken("secret")),
            transport: transport
        )

        _ = try await client.fetchMessages(channelID: "channel-1", options: MessageFetchOptions(nearby: "message-1", sort: .latest, limit: 9, includeUsers: false))
        let capturedRequest = await transport.lastRequest()
        let request = try XCTUnwrap(capturedRequest)
        let query = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems ?? []

        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/channels/channel-1/messages")
        XCTAssertEqual(query.first { $0.name == "nearby" }?.value, "message-1")
        XCTAssertEqual(query.first { $0.name == "sort" }?.value, "Latest")
        XCTAssertEqual(query.first { $0.name == "limit" }?.value, "9")
        XCTAssertEqual(query.first { $0.name == "include_users" }?.value, "false")
    }

    func testChannelSearchEndpointRequest() async throws {
        let transport = RecordingHTTPTransport(data: Data(#"[{"_id":"message-1","channel":"channel-1","author":"user-1","content":"needle"}]"#.utf8))
        let client = LiveStoatAPIClient(
            credentialProvider: StaticCredentialProvider(.sessionToken("secret")),
            transport: transport
        )

        _ = try await client.searchMessages(channelID: "channel-1", request: ChannelMessageSearchRequest(query: "needle", limit: 25, sort: .relevance))
        let capturedRequest = await transport.lastRequest()
        let request = try XCTUnwrap(capturedRequest)
        let body = String(data: try XCTUnwrap(request.httpBody), encoding: .utf8)

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/channels/channel-1/search")
        XCTAssertTrue(body?.contains(#""query":"needle""#) == true)
        XCTAssertTrue(body?.contains(#""sort":"Relevance""#) == true)
    }

    func testSendMessageEndpointUsesIdempotencyHeaderAndVerifiedBodyShape() async throws {
        let transport = RecordingHTTPTransport(data: Data(#"{"_id":"message-1","channel":"channel-1","author":"user-1","content":"hello","nonce":"nonce-1","attachments":[{"_id":"file-1","tag":"attachments","filename":"photo.png","metadata":{"type":"Image","width":8,"height":8},"content_type":"image/png","size":100}],"replies":["message-reply"]}"#.utf8))
        let client = LiveStoatAPIClient(
            credentialProvider: StaticCredentialProvider(.sessionToken("secret")),
            transport: transport
        )

        let message = try await client.sendMessage(
            channelID: "channel-1",
            draft: MessageDraft(
                content: "hello",
                nonce: "nonce-1",
                attachments: ["file-1"],
                replies: [MessageReply(id: "message-reply", mention: false)]
            )
        )
        let capturedRequest = await transport.lastRequest()
        let request = try XCTUnwrap(capturedRequest)
        let bodyData = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])

        XCTAssertEqual(message.nonce, "nonce-1")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/channels/channel-1/messages")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Session-Token"), "secret")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Idempotency-Key"), "nonce-1")
        XCTAssertEqual(object["content"] as? String, "hello")
        XCTAssertNil(object["nonce"])
        XCTAssertEqual(object["attachments"] as? [String], ["file-1"])
        let replies = try XCTUnwrap(object["replies"] as? [[String: Any]])
        XCTAssertEqual(replies.first?["id"] as? String, "message-reply")
        XCTAssertEqual(replies.first?["mention"] as? Bool, false)
    }

    func testSendMessageOmitsNilUnsupportedFields() async throws {
        let transport = RecordingHTTPTransport(data: Data(#"{"_id":"message-1","channel":"channel-1","author":"user-1","content":"hello","nonce":"nonce-2"}"#.utf8))
        let client = LiveStoatAPIClient(
            credentialProvider: StaticCredentialProvider(.sessionToken("secret")),
            transport: transport
        )

        _ = try await client.sendMessage(channelID: "channel-1", draft: MessageDraft(content: "hello", nonce: "nonce-2"))
        let capturedRequest = await transport.lastRequest()
        let request = try XCTUnwrap(capturedRequest)
        let bodyData = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])

        XCTAssertEqual(Set(object.keys), ["content"])
        XCTAssertEqual(request.value(forHTTPHeaderField: "Idempotency-Key"), "nonce-2")
    }

    func testSessionValidationErrorMapping() {
        XCTAssertEqual(LiveSessionValidator.map(.unauthorized), .invalidOrExpired)
        XCTAssertEqual(LiveSessionValidator.map(.forbidden), .forbidden)
        XCTAssertEqual(LiveSessionValidator.map(.rateLimited(retryAfterMilliseconds: 1234)), .rateLimited(retryAfterMilliseconds: 1234))
        XCTAssertEqual(LiveSessionValidator.map(.invalidEnvironment("bad")), .invalidEnvironment("bad"))
    }

    func testRequestBuilderCombinesURLQueryAndAuthentication() throws {
        let request = StoatRequest<User>(
            method: .get,
            path: "/channels/channel-1/messages",
            queryItems: [
                URLQueryItem(name: "limit", value: "50"),
                URLQueryItem(name: "before", value: "message-1")
            ]
        )
        let builder = StoatRequestBuilder(environment: .production)
        let urlRequest = try builder.build(request, credential: .botToken("bot-secret"))

        XCTAssertEqual(urlRequest.url?.scheme, "https")
        XCTAssertEqual(urlRequest.url?.host, "api.stoat.chat")
        XCTAssertEqual(urlRequest.url?.path, "/channels/channel-1/messages")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "X-Bot-Token"), "bot-secret")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(urlRequest.httpMethod, "GET")
        XCTAssertTrue(urlRequest.url?.query?.contains("limit=50") == true)
    }

    func testUnauthenticatedRequestOmitsAuthHeader() throws {
        let request = StoatRequest<StoatConfig>(method: .get, path: "/", requiresAuthentication: false)
        let urlRequest = try StoatRequestBuilder(environment: .production).build(request, credential: nil)

        XCTAssertNil(urlRequest.value(forHTTPHeaderField: "X-Session-Token"))
        XCTAssertNil(urlRequest.value(forHTTPHeaderField: "X-Bot-Token"))
    }

    func testJSONBodyEncoding() throws {
        let draft = MessageDraft(content: "hello", nonce: "nonce-1")
        let body = RequestBody.json(try JSONEncoder.stoat.encode(draft))
        let request = StoatRequest<Message>(
            method: .post,
            path: "/channels/channel/messages",
            body: body,
            headers: ["Idempotency-Key": "nonce-1"]
        )
        let urlRequest = try StoatRequestBuilder(environment: .production).build(
            request,
            credential: .userSession(token: "token", sessionID: nil)
        )

        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Idempotency-Key"), "nonce-1")
        XCTAssertTrue(String(data: try XCTUnwrap(urlRequest.httpBody), encoding: .utf8)?.contains(#""content":"hello""#) == true)
    }

    func testMultipartUploadBodyContainsFileField() throws {
        let body = MultipartFormData.fileBody(
            data: Data("hello".utf8),
            filename: "hello.txt",
            mimeType: "text/plain",
            boundary: "TestBoundary"
        )
        let request = StoatRequest<UploadedFile>(
            base: .media,
            method: .post,
            path: "/attachments",
            body: body
        )
        let urlRequest = try StoatRequestBuilder(environment: .production).build(
            request,
            credential: .userSession(token: "token", sessionID: nil)
        )
        let string = String(data: try XCTUnwrap(urlRequest.httpBody), encoding: .utf8)

        XCTAssertEqual(urlRequest.url?.absoluteString, "https://cdn.stoatusercontent.com/attachments")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Content-Type"), "multipart/form-data; boundary=TestBoundary")
        XCTAssertTrue(string?.contains("TestBoundary") == true)
        XCTAssertTrue(string?.contains(#"name="file""#) == true)
        XCTAssertTrue(string?.contains(#"filename="hello.txt""#) == true)
        XCTAssertTrue(string?.contains("Content-Type: text/plain") == true)
        XCTAssertTrue(string?.contains("hello") == true)
    }

    func testResponseDecoderSuccessEmptyAndErrors() throws {
        let decoder = StoatResponseDecoder(decoder: .stoat)
        let userData = try fixtureData("user", bundle: Bundle.module, fallbackBundle: Bundle(for: StoatAPITests.self))
        let user = try decoder.decode(User.self, from: StoatHTTPResponse(statusCode: 200, data: userData))
        XCTAssertEqual(user.username, "liquidbagel")

        let empty = try decoder.decode(EmptyResponse.self, from: StoatHTTPResponse(statusCode: 204))
        XCTAssertEqual(empty, EmptyResponse())

        assertThrows(try decoder.decode(User.self, from: StoatHTTPResponse(statusCode: 401)), .unauthorized)
        assertThrows(try decoder.decode(User.self, from: StoatHTTPResponse(statusCode: 403)), .forbidden)
        assertThrows(try decoder.decode(User.self, from: StoatHTTPResponse(statusCode: 404)), .notFound)
        assertThrows(try decoder.decode(User.self, from: StoatHTTPResponse(statusCode: 503, data: Data(#"{"type":"InternalError"}"#.utf8))), .serverError(statusCode: 503, message: "InternalError"))
        assertThrows(try decoder.decode(User.self, from: StoatHTTPResponse(statusCode: 200, data: Data("not json".utf8))), .decodingFailed(""))
    }

    func testRateLimitHeadersAndRetryBody() throws {
        let headers = [
            "X-RateLimit-Limit": "20",
            "X-RateLimit-Bucket": "bucket-1",
            "X-RateLimit-Remaining": "0",
            "X-RateLimit-Reset-After": "10000"
        ]
        let info = RateLimitInfo(headers: headers)
        XCTAssertEqual(info.limit, 20)
        XCTAssertEqual(info.bucket, "bucket-1")
        XCTAssertEqual(info.remaining, 0)
        XCTAssertEqual(info.resetAfterMilliseconds, 10000)

        let data = try fixtureData("rate_limited")
        XCTAssertThrowsError(try StoatResponseDecoder().decode(User.self, from: StoatHTTPResponse(statusCode: 429, data: data))) { error in
            XCTAssertEqual(error as? StoatAPIError, .rateLimited(retryAfterMilliseconds: 1234))
        }
    }

    func testUploadResponseFixture() throws {
        let uploaded = try JSONDecoder.stoat.decode(UploadedFile.self, from: fixtureData("upload_response"))

        XCTAssertEqual(uploaded.id.rawValue, "file-upload-1")
    }

    func testPhase25ServerRoleAndMemberEndpointRequests() async throws {
        let serverJSON = Data(#"{"_id":"server-1","owner":"user-1","name":"Lab Updated","description":"Updated","channels":[],"default_permissions":0}"#.utf8)
        let serverTransport = RecordingHTTPTransport(data: serverJSON)
        let serverClient = LiveStoatAPIClient(
            credentialProvider: StaticCredentialProvider(.sessionToken("secret")),
            transport: serverTransport
        )
        _ = try await serverClient.editServer(id: "server-1", draft: ServerEditDraft(name: "Lab Updated", description: "Updated", icon: "file-icon", banner: "file-banner"))
        let capturedServerRequest = await serverTransport.lastRequest()
        let serverRequest = try XCTUnwrap(capturedServerRequest)
        let serverBody = String(data: try XCTUnwrap(serverRequest.httpBody), encoding: .utf8)
        XCTAssertEqual(serverRequest.httpMethod, "PATCH")
        XCTAssertEqual(serverRequest.url?.path, "/servers/server-1")
        XCTAssertTrue(serverBody?.contains(#""name":"Lab Updated""#) == true)
        XCTAssertTrue(serverBody?.contains(#""icon":"file-icon""#) == true)
        XCTAssertTrue(serverBody?.contains(#""banner":"file-banner""#) == true)

        let roleResponseJSON = Data(#"{"id":"role-1","role":{"_id":"role-1","name":"Operators","permissions":{"a":0,"d":0},"rank":1}}"#.utf8)
        let createRoleTransport = RecordingHTTPTransport(data: roleResponseJSON)
        let createRoleClient = LiveStoatAPIClient(
            credentialProvider: StaticCredentialProvider(.sessionToken("secret")),
            transport: createRoleTransport
        )
        _ = try await createRoleClient.createRole(serverID: "server-1", draft: RoleCreateDraft(name: "Operators"))
        let capturedCreateRoleRequest = await createRoleTransport.lastRequest()
        let createRoleRequest = try XCTUnwrap(capturedCreateRoleRequest)
        XCTAssertEqual(createRoleRequest.httpMethod, "POST")
        XCTAssertEqual(createRoleRequest.url?.path, "/servers/server-1/roles")
        XCTAssertTrue(String(data: try XCTUnwrap(createRoleRequest.httpBody), encoding: .utf8)?.contains(#""name":"Operators""#) == true)

        let roleJSON = Data(##"{"_id":"role-1","name":"Ops","permissions":{"a":0,"d":0},"colour":"#FFAA00","hoist":true,"rank":1}"##.utf8)
        let editRoleTransport = RecordingHTTPTransport(data: roleJSON)
        let editRoleClient = LiveStoatAPIClient(
            credentialProvider: StaticCredentialProvider(.sessionToken("secret")),
            transport: editRoleTransport
        )
        _ = try await editRoleClient.editRole(serverID: "server-1", roleID: "role-1", draft: RoleEditDraft(name: "Ops", colour: "#FFAA00", hoist: true))
        let capturedEditRoleRequest = await editRoleTransport.lastRequest()
        let editRoleRequest = try XCTUnwrap(capturedEditRoleRequest)
        XCTAssertEqual(editRoleRequest.httpMethod, "PATCH")
        XCTAssertEqual(editRoleRequest.url?.path, "/servers/server-1/roles/role-1")
        XCTAssertTrue(String(data: try XCTUnwrap(editRoleRequest.httpBody), encoding: .utf8)?.contains(##""colour":"#FFAA00""##) == true)

        let deleteRoleTransport = RecordingHTTPTransport(statusCode: 204)
        let deleteRoleClient = LiveStoatAPIClient(
            credentialProvider: StaticCredentialProvider(.sessionToken("secret")),
            transport: deleteRoleTransport
        )
        try await deleteRoleClient.deleteRole(serverID: "server-1", roleID: "role-1")
        let capturedDeleteRoleRequest = await deleteRoleTransport.lastRequest()
        let deleteRoleRequest = try XCTUnwrap(capturedDeleteRoleRequest)
        XCTAssertEqual(deleteRoleRequest.httpMethod, "DELETE")
        XCTAssertEqual(deleteRoleRequest.url?.path, "/servers/server-1/roles/role-1")

        let memberJSON = Data(#"{"_id":{"server":"server-1","user":"user-2"},"joined_at":"2026-06-02T00:00:00.000Z","roles":["role-1"]}"#.utf8)
        let memberTransport = RecordingHTTPTransport(data: memberJSON)
        let memberClient = LiveStoatAPIClient(
            credentialProvider: StaticCredentialProvider(.sessionToken("secret")),
            transport: memberTransport
        )
        _ = try await memberClient.editMember(serverID: "server-1", userID: "user-2", draft: MemberEditDraft(roles: ["role-1"]))
        let capturedMemberRequest = await memberTransport.lastRequest()
        let memberRequest = try XCTUnwrap(capturedMemberRequest)
        XCTAssertEqual(memberRequest.httpMethod, "PATCH")
        XCTAssertEqual(memberRequest.url?.path, "/servers/server-1/members/user-2")
        XCTAssertTrue(String(data: try XCTUnwrap(memberRequest.httpBody), encoding: .utf8)?.contains(#""roles":["role-1"]"#) == true)
    }

    func testPhase26MemberModerationAndPermissionEndpointRequests() async throws {
        let memberJSON = Data(#"{"_id":{"server":"server-1","user":"user-2"},"joined_at":"2026-06-02T00:00:00.000Z","nickname":"Ops","timeout":"2026-06-03T00:00:00.000Z","roles":["role-1"]}"#.utf8)
        let memberTransport = RecordingHTTPTransport(data: memberJSON)
        let memberClient = LiveStoatAPIClient(
            credentialProvider: StaticCredentialProvider(.sessionToken("secret")),
            transport: memberTransport
        )
        _ = try await memberClient.editMember(serverID: "server-1", userID: "user-2", draft: MemberEditDraft(nickname: "Ops", timeout: Date(timeIntervalSince1970: 1_801_440_000), remove: [.avatar]))
        let capturedPhase26MemberRequest = await memberTransport.lastRequest()
        let memberRequest = try XCTUnwrap(capturedPhase26MemberRequest)
        let memberBody = String(data: try XCTUnwrap(memberRequest.httpBody), encoding: .utf8)
        XCTAssertEqual(memberRequest.httpMethod, "PATCH")
        XCTAssertEqual(memberRequest.url?.path, "/servers/server-1/members/user-2")
        XCTAssertTrue(memberBody?.contains(#""nickname":"Ops""#) == true)
        XCTAssertTrue(memberBody?.contains(#""remove":["Avatar"]"#) == true)

        let memberListJSON = Data(#"[{"_id":{"server":"server-1","user":"user-2"},"joined_at":"2026-06-02T00:00:00.000Z","roles":["role-1"]}]"#.utf8)
        let memberListTransport = RecordingHTTPTransport(data: memberListJSON)
        let memberListClient = LiveStoatAPIClient(credentialProvider: StaticCredentialProvider(.sessionToken("secret")), transport: memberListTransport)
        let fetchedMembers = try await memberListClient.fetchServerMembers(serverID: "server-1")
        let capturedMemberListRequest = await memberListTransport.lastRequest()
        let memberListRequest = try XCTUnwrap(capturedMemberListRequest)
        XCTAssertEqual(fetchedMembers.count, 1)
        XCTAssertEqual(memberListRequest.httpMethod, "GET")
        XCTAssertEqual(memberListRequest.url?.path, "/servers/server-1/members")

        let kickTransport = RecordingHTTPTransport(statusCode: 204)
        let kickClient = LiveStoatAPIClient(credentialProvider: StaticCredentialProvider(.sessionToken("secret")), transport: kickTransport)
        try await kickClient.kickMember(serverID: "server-1", userID: "user-2")
        let capturedKickRequest = await kickTransport.lastRequest()
        let kickRequest = try XCTUnwrap(capturedKickRequest)
        XCTAssertEqual(kickRequest.httpMethod, "DELETE")
        XCTAssertEqual(kickRequest.url?.path, "/servers/server-1/members/user-2")

        let banJSON = Data(#"{"_id":{"server":"server-1","user":"user-2"},"reason":"spam"}"#.utf8)
        let banTransport = RecordingHTTPTransport(data: banJSON)
        let banClient = LiveStoatAPIClient(credentialProvider: StaticCredentialProvider(.sessionToken("secret")), transport: banTransport)
        _ = try await banClient.banMember(serverID: "server-1", userID: "user-2", draft: BanCreateDraft(reason: "spam", deleteMessageSeconds: 3600))
        let capturedBanRequest = await banTransport.lastRequest()
        let banRequest = try XCTUnwrap(capturedBanRequest)
        let banBody = String(data: try XCTUnwrap(banRequest.httpBody), encoding: .utf8)
        XCTAssertEqual(banRequest.httpMethod, "PUT")
        XCTAssertEqual(banRequest.url?.path, "/servers/server-1/bans/user-2")
        XCTAssertTrue(banBody?.contains(#""reason":"spam""#) == true)
        XCTAssertTrue(banBody?.contains(#""delete_message_seconds":3600"#) == true)

        let banListJSON = Data(#"{"users":[{"_id":"user-2","username":"target","discriminator":"0001"}],"bans":[{"_id":{"server":"server-1","user":"user-2"},"reason":"spam"}]}"#.utf8)
        let banListTransport = RecordingHTTPTransport(data: banListJSON)
        let banListClient = LiveStoatAPIClient(credentialProvider: StaticCredentialProvider(.sessionToken("secret")), transport: banListTransport)
        _ = try await banListClient.fetchServerBans(serverID: "server-1")
        let capturedBanListRequest = await banListTransport.lastRequest()
        let banListRequest = try XCTUnwrap(capturedBanListRequest)
        XCTAssertEqual(banListRequest.httpMethod, "GET")
        XCTAssertEqual(banListRequest.url?.path, "/servers/server-1/bans")

        let unbanTransport = RecordingHTTPTransport(statusCode: 204)
        let unbanClient = LiveStoatAPIClient(credentialProvider: StaticCredentialProvider(.sessionToken("secret")), transport: unbanTransport)
        try await unbanClient.unbanMember(serverID: "server-1", userID: "user-2")
        let capturedUnbanRequest = await unbanTransport.lastRequest()
        let unbanRequest = try XCTUnwrap(capturedUnbanRequest)
        XCTAssertEqual(unbanRequest.httpMethod, "DELETE")
        XCTAssertEqual(unbanRequest.url?.path, "/servers/server-1/bans/user-2")

        let serverJSON = Data(#"{"_id":"server-1","owner":"user-1","name":"Lab","channels":[],"roles":{"role-1":{"_id":"role-1","name":"Ops","permissions":{"a":4,"d":0},"rank":1}},"default_permissions":2097152}"#.utf8)
        let serverPermissionTransport = RecordingHTTPTransport(data: serverJSON)
        let serverPermissionClient = LiveStoatAPIClient(credentialProvider: StaticCredentialProvider(.sessionToken("secret")), transport: serverPermissionTransport)
        _ = try await serverPermissionClient.setServerRolePermissions(serverID: "server-1", roleID: "role-1", draft: ServerRolePermissionDraft(permissions: PermissionWriteOverride(allow: .managePermissions, deny: [])))
        let capturedServerPermissionRequest = await serverPermissionTransport.lastRequest()
        let serverPermissionRequest = try XCTUnwrap(capturedServerPermissionRequest)
        let serverPermissionBody = String(data: try XCTUnwrap(serverPermissionRequest.httpBody), encoding: .utf8)
        XCTAssertEqual(serverPermissionRequest.httpMethod, "PUT")
        XCTAssertEqual(serverPermissionRequest.url?.path, "/servers/server-1/permissions/role-1")
        XCTAssertTrue(serverPermissionBody?.contains(#""allow":4"#) == true)
        XCTAssertFalse(serverPermissionBody?.contains(#""a":"#) == true)

        let serverDefaultTransport = RecordingHTTPTransport(data: serverJSON)
        let serverDefaultClient = LiveStoatAPIClient(credentialProvider: StaticCredentialProvider(.sessionToken("secret")), transport: serverDefaultTransport)
        _ = try await serverDefaultClient.setServerDefaultPermissions(serverID: "server-1", draft: ServerDefaultPermissionDraft(permissions: [.viewChannel, .readMessageHistory]))
        let capturedServerDefaultRequest = await serverDefaultTransport.lastRequest()
        let serverDefaultRequest = try XCTUnwrap(capturedServerDefaultRequest)
        XCTAssertEqual(serverDefaultRequest.httpMethod, "PUT")
        XCTAssertEqual(serverDefaultRequest.url?.path, "/servers/server-1/permissions/default")

        let channelJSON = Data(#"{"_id":"channel-1","channel_type":"TextChannel","server":"server-1","name":"general","default_permissions":{"a":4194304,"d":0},"role_permissions":{"role-1":{"a":4,"d":0}}}"#.utf8)
        let channelPermissionTransport = RecordingHTTPTransport(data: channelJSON)
        let channelPermissionClient = LiveStoatAPIClient(credentialProvider: StaticCredentialProvider(.sessionToken("secret")), transport: channelPermissionTransport)
        _ = try await channelPermissionClient.setChannelDefaultPermissions(channelID: "channel-1", draft: .override(PermissionWriteOverride(allow: .sendMessage, deny: [])))
        let capturedChannelPermissionRequest = await channelPermissionTransport.lastRequest()
        let channelPermissionRequest = try XCTUnwrap(capturedChannelPermissionRequest)
        XCTAssertEqual(channelPermissionRequest.httpMethod, "PUT")
        XCTAssertEqual(channelPermissionRequest.url?.path, "/channels/channel-1/permissions/default")
    }

    private func assertThrows<T>(_ expression: @autoclosure () throws -> T, _ expected: StoatAPIError) {
        XCTAssertThrowsError(try expression()) { error in
            guard let apiError = error as? StoatAPIError else {
                return XCTFail("Expected StoatAPIError, got \(error)")
            }
            switch (apiError, expected) {
            case (.decodingFailed, .decodingFailed):
                return
            default:
                XCTAssertEqual(apiError, expected)
            }
        }
    }

    private func fixtureData(_ name: String, bundle: Bundle = .module, fallbackBundle: Bundle? = nil) throws -> Data {
        if let url = bundle.url(forResource: name, withExtension: "json") {
            return try Data(contentsOf: url)
        }
        if let fallbackBundle, let url = fallbackBundle.url(forResource: name, withExtension: "json") {
            return try Data(contentsOf: url)
        }
        if let modelURL = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "../StoatModelsTests_Fixtures") {
            return try Data(contentsOf: modelURL)
        }
        throw XCTSkip("Missing fixture \(name).json")
    }
}

private actor RecordingHTTPTransport: HTTPTransport {
    private var requests: [URLRequest] = []
    private let statusCode: Int
    private let data: Data

    init(statusCode: Int = 200, data: Data = Data()) {
        self.statusCode = statusCode
        self.data = data
    }

    func data(for request: URLRequest) async throws -> StoatHTTPResponse {
        requests.append(request)
        return StoatHTTPResponse(statusCode: statusCode, data: data)
    }

    func lastRequest() -> URLRequest? {
        requests.last
    }
}
