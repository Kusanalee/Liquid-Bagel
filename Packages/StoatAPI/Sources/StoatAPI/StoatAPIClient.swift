import Foundation
import StoatModels

public protocol StoatAPIClient: Sendable {
    func fetchRootConfiguration() async throws -> StoatConfig
    func fetchCurrentUser() async throws -> User
    func fetchServers() async throws -> [Server]
    func fetchChannels() async throws -> [Channel]
    func fetchChannel(id: ChannelID) async throws -> Channel
    func fetchMessage(channelID: ChannelID, messageID: MessageID) async throws -> Message
    func fetchMessages(channelID: ChannelID, options: MessageFetchOptions) async throws -> [Message]
    func fetchMessages(channelID: ChannelID, before: MessageID?, after: MessageID?, limit: Int?) async throws -> [Message]
    func searchMessages(channelID: ChannelID, request: ChannelMessageSearchRequest) async throws -> [Message]
    func sendMessage(channelID: ChannelID, draft: MessageDraft) async throws -> Message
    func editMessage(channelID: ChannelID, messageID: MessageID, draft: MessageEditDraft) async throws -> Message
    func deleteMessage(channelID: ChannelID, messageID: MessageID) async throws
    func ackChannel(channelID: ChannelID, messageID: MessageID) async throws
    func addReaction(channelID: ChannelID, messageID: MessageID, emoji: String) async throws
    func removeReaction(channelID: ChannelID, messageID: MessageID, emoji: String, removeAll: Bool) async throws
    func pinMessage(channelID: ChannelID, messageID: MessageID) async throws
    func unpinMessage(channelID: ChannelID, messageID: MessageID) async throws
    func uploadFile(data: Data, filename: String, mimeType: String, tag: UploadTag) async throws -> UploadedFile
    func login(request: SessionLoginRequest) async throws -> SessionLoginResponse
    func continueLogin(request: SessionMFALoginRequest) async throws -> SessionLoginResponse
    func logoutCurrentSession() async throws
    func fetchSessions() async throws -> [SessionInfo]
    func revokeSession(id: SessionID) async throws
    func revokeAllSessions(revokeSelf: Bool) async throws
    func renameSession(id: SessionID, friendlyName: String) async throws -> SessionInfo
}

public extension StoatAPIClient {
    func fetchMessage(channelID: ChannelID, messageID: MessageID) async throws -> Message {
        throw StoatAPIError.unimplementedEndpoint("Single message fetch is not implemented by this API client.")
    }

    func fetchMessages(channelID: ChannelID, options: MessageFetchOptions) async throws -> [Message] {
        try await fetchMessages(channelID: channelID, before: options.before, after: options.after, limit: options.limit)
    }

    func searchMessages(channelID: ChannelID, request: ChannelMessageSearchRequest) async throws -> [Message] {
        throw StoatAPIError.unimplementedEndpoint("Channel message search is not implemented by this API client.")
    }

    func ackChannel(channelID: ChannelID, messageID: MessageID) async throws {
        throw StoatAPIError.unimplementedEndpoint("Channel read acknowledgement is not implemented by this API client.")
    }

    func login(request: SessionLoginRequest) async throws -> SessionLoginResponse {
        throw StoatAPIError.unimplementedEndpoint("Session login is not implemented by this API client.")
    }

    func continueLogin(request: SessionMFALoginRequest) async throws -> SessionLoginResponse {
        throw StoatAPIError.unimplementedEndpoint("MFA login is not implemented by this API client.")
    }

    func logoutCurrentSession() async throws {
        throw StoatAPIError.unimplementedEndpoint("Session logout is not implemented by this API client.")
    }

    func fetchSessions() async throws -> [SessionInfo] {
        throw StoatAPIError.unimplementedEndpoint("Session listing is not implemented by this API client.")
    }

    func revokeSession(id: SessionID) async throws {
        throw StoatAPIError.unimplementedEndpoint("Session revocation is not implemented by this API client.")
    }

    func revokeAllSessions(revokeSelf: Bool) async throws {
        throw StoatAPIError.unimplementedEndpoint("Session revocation is not implemented by this API client.")
    }

    func renameSession(id: SessionID, friendlyName: String) async throws -> SessionInfo {
        throw StoatAPIError.unimplementedEndpoint("Session rename is not implemented by this API client.")
    }
}

public actor LiveStoatAPIClient: StoatAPIClient {
    private let environment: StoatAPIEnvironment
    private let credentialProvider: any CredentialProvider
    private let transport: any HTTPTransport
    private let encoder: JSONEncoder
    private let responseDecoder: StoatResponseDecoder
    private let requestBuilder: StoatRequestBuilder

    public init(
        environment: StoatAPIEnvironment = .production,
        credentialProvider: any CredentialProvider = StaticCredentialProvider(nil),
        transport: any HTTPTransport = URLSessionHTTPTransport(),
        decoder: JSONDecoder = .stoat,
        encoder: JSONEncoder = .stoat
    ) {
        self.environment = environment
        self.credentialProvider = credentialProvider
        self.transport = transport
        self.encoder = encoder
        self.responseDecoder = StoatResponseDecoder(decoder: decoder)
        self.requestBuilder = StoatRequestBuilder(environment: environment)
    }

    public func fetchRootConfiguration() async throws -> StoatConfig {
        try await perform(StoatRequest<StoatConfig>(method: .get, path: "/", requiresAuthentication: false))
    }

    public func fetchCurrentUser() async throws -> User {
        try await perform(StoatRequest<User>(method: .get, path: "/users/@me"))
    }

    public func fetchServers() async throws -> [Server] {
        throw StoatAPIError.unimplementedEndpoint("No verified REST route lists the current user's servers; use Ready over realtime in Phase 2.")
    }

    public func fetchChannels() async throws -> [Channel] {
        throw StoatAPIError.unimplementedEndpoint("No verified REST route lists all current-user channels; use Ready/users/dms plus server channels later.")
    }

    public func fetchChannel(id: ChannelID) async throws -> Channel {
        try await perform(StoatRequest<Channel>(method: .get, path: "/channels/\(id.rawValue.stoatPathComponentEscaped)"))
    }

    public func fetchMessage(channelID: ChannelID, messageID: MessageID) async throws -> Message {
        try await perform(
            StoatRequest<Message>(
                method: .get,
                path: "/channels/\(channelID.rawValue.stoatPathComponentEscaped)/messages/\(messageID.rawValue.stoatPathComponentEscaped)"
            )
        )
    }

    public func fetchMessages(channelID: ChannelID, options: MessageFetchOptions) async throws -> [Message] {
        var queryItems: [URLQueryItem] = []
        if let before = options.before {
            queryItems.append(URLQueryItem(name: "before", value: before.rawValue))
        }
        if let after = options.after {
            queryItems.append(URLQueryItem(name: "after", value: after.rawValue))
        }
        if let nearby = options.nearby {
            queryItems.append(URLQueryItem(name: "nearby", value: nearby.rawValue))
        }
        if let sort = options.sort {
            queryItems.append(URLQueryItem(name: "sort", value: sort.rawValue))
        }
        if let limit = options.limit {
            queryItems.append(URLQueryItem(name: "limit", value: String(limit)))
        }
        if let includeUsers = options.includeUsers {
            queryItems.append(URLQueryItem(name: "include_users", value: includeUsers ? "true" : "false"))
        }
        let response = try await perform(
            StoatRequest<BulkMessageResponse>(
                method: .get,
                path: "/channels/\(channelID.rawValue.stoatPathComponentEscaped)/messages",
                queryItems: queryItems
            )
        )
        return response.messages
    }

    public func fetchMessages(channelID: ChannelID, before: MessageID?, after: MessageID?, limit: Int?) async throws -> [Message] {
        try await fetchMessages(channelID: channelID, options: MessageFetchOptions(before: before, after: after, limit: limit))
    }

    public func searchMessages(channelID: ChannelID, request: ChannelMessageSearchRequest) async throws -> [Message] {
        let response = try await perform(
            StoatRequest<BulkMessageResponse>(
                method: .post,
                path: "/channels/\(channelID.rawValue.stoatPathComponentEscaped)/search",
                body: .json(try encoder.encode(request))
            )
        )
        return response.messages
    }

    public func sendMessage(channelID: ChannelID, draft: MessageDraft) async throws -> Message {
        var headers: [String: String] = [:]
        if let nonce = draft.nonce {
            headers["Idempotency-Key"] = nonce
        }
        let wireDraft = MessageSendWireDraft(draft)
        return try await perform(
            StoatRequest<Message>(
                method: .post,
                path: "/channels/\(channelID.rawValue.stoatPathComponentEscaped)/messages",
                body: .json(try encoder.encode(wireDraft)),
                headers: headers
            )
        )
    }

    public func editMessage(channelID: ChannelID, messageID: MessageID, draft: MessageEditDraft) async throws -> Message {
        try await perform(
            StoatRequest<Message>(
                method: .patch,
                path: "/channels/\(channelID.rawValue.stoatPathComponentEscaped)/messages/\(messageID.rawValue.stoatPathComponentEscaped)",
                body: .json(try encoder.encode(draft))
            )
        )
    }

    public func deleteMessage(channelID: ChannelID, messageID: MessageID) async throws {
        let request = StoatRequest<EmptyResponse>(
            method: .delete,
            path: "/channels/\(channelID.rawValue.stoatPathComponentEscaped)/messages/\(messageID.rawValue.stoatPathComponentEscaped)"
        )
        _ = try await perform(request)
    }

    public func ackChannel(channelID: ChannelID, messageID: MessageID) async throws {
        let request = StoatRequest<EmptyResponse>(
            method: .put,
            path: "/channels/\(channelID.rawValue.stoatPathComponentEscaped)/ack/\(messageID.rawValue.stoatPathComponentEscaped)"
        )
        _ = try await perform(request)
    }

    public func addReaction(channelID: ChannelID, messageID: MessageID, emoji: String) async throws {
        let request = StoatRequest<EmptyResponse>(
            method: .put,
            path: "/channels/\(channelID.rawValue.stoatPathComponentEscaped)/messages/\(messageID.rawValue.stoatPathComponentEscaped)/reactions/\(emoji.stoatPathComponentEscaped)"
        )
        _ = try await perform(request)
    }

    public func removeReaction(channelID: ChannelID, messageID: MessageID, emoji: String, removeAll: Bool) async throws {
        var queryItems: [URLQueryItem] = []
        if removeAll {
            queryItems.append(URLQueryItem(name: "remove_all", value: "true"))
        }
        let request = StoatRequest<EmptyResponse>(
            method: .delete,
            path: "/channels/\(channelID.rawValue.stoatPathComponentEscaped)/messages/\(messageID.rawValue.stoatPathComponentEscaped)/reactions/\(emoji.stoatPathComponentEscaped)",
            queryItems: queryItems
        )
        _ = try await perform(request)
    }

    public func pinMessage(channelID: ChannelID, messageID: MessageID) async throws {
        let request = StoatRequest<EmptyResponse>(
            method: .post,
            path: "/channels/\(channelID.rawValue.stoatPathComponentEscaped)/messages/\(messageID.rawValue.stoatPathComponentEscaped)/pin"
        )
        _ = try await perform(request)
    }

    public func unpinMessage(channelID: ChannelID, messageID: MessageID) async throws {
        let request = StoatRequest<EmptyResponse>(
            method: .delete,
            path: "/channels/\(channelID.rawValue.stoatPathComponentEscaped)/messages/\(messageID.rawValue.stoatPathComponentEscaped)/pin"
        )
        _ = try await perform(request)
    }

    public func uploadFile(data: Data, filename: String, mimeType: String, tag: UploadTag) async throws -> UploadedFile {
        try await perform(
            StoatRequest<UploadedFile>(
                base: .media,
                method: .post,
                path: "/\(tag.rawAPIValue)",
                body: MultipartFormData.fileBody(data: data, filename: filename, mimeType: mimeType)
            )
        )
    }

    public func login(request: SessionLoginRequest) async throws -> SessionLoginResponse {
        try await perform(
            StoatRequest<SessionLoginResponse>(
                method: .post,
                path: "/auth/session/login",
                body: .json(try encoder.encode(request)),
                requiresAuthentication: false
            )
        )
    }

    public func continueLogin(request: SessionMFALoginRequest) async throws -> SessionLoginResponse {
        try await perform(
            StoatRequest<SessionLoginResponse>(
                method: .post,
                path: "/auth/session/login",
                body: .json(try encoder.encode(request)),
                requiresAuthentication: false
            )
        )
    }

    public func logoutCurrentSession() async throws {
        _ = try await perform(StoatRequest<EmptyResponse>(method: .post, path: "/auth/session/logout"))
    }

    public func fetchSessions() async throws -> [SessionInfo] {
        try await perform(StoatRequest<[SessionInfo]>(method: .get, path: "/auth/session/all"))
    }

    public func revokeSession(id: SessionID) async throws {
        _ = try await perform(StoatRequest<EmptyResponse>(method: .delete, path: "/auth/session/\(id.rawValue.stoatPathComponentEscaped)"))
    }

    public func revokeAllSessions(revokeSelf: Bool) async throws {
        _ = try await perform(
            StoatRequest<EmptyResponse>(
                method: .delete,
                path: "/auth/session/all",
                queryItems: [URLQueryItem(name: "revoke_self", value: revokeSelf ? "true" : "false")]
            )
        )
    }

    public func renameSession(id: SessionID, friendlyName: String) async throws -> SessionInfo {
        try await perform(
            StoatRequest<SessionInfo>(
                method: .patch,
                path: "/auth/session/\(id.rawValue.stoatPathComponentEscaped)",
                body: .json(try encoder.encode(SessionEditRequest(friendlyName: friendlyName)))
            )
        )
    }

    private func perform<Response: Decodable & Sendable>(_ request: StoatRequest<Response>) async throws -> Response {
        let credential = request.requiresAuthentication ? try await credentialProvider.credential() : nil
        let urlRequest = try requestBuilder.build(request, credential: credential)
        let httpResponse = try await transport.data(for: urlRequest)
        return try responseDecoder.decode(Response.self, from: httpResponse)
    }
}

private struct SessionEditRequest: Encodable {
    var friendlyName: String

    private enum CodingKeys: String, CodingKey {
        case friendlyName = "friendly_name"
    }
}
