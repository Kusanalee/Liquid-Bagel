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
