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
