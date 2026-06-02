import Foundation
import StoatModels

public protocol StoatAPIClient: Sendable {
    func fetchRootConfiguration() async throws -> StoatConfig
    func fetchCurrentUser() async throws -> User
    func fetchUserProfile(userID: UserID) async throws -> UserProfile
    func fetchServers() async throws -> [Server]
    func fetchChannels() async throws -> [Channel]
    func fetchDirectMessages() async throws -> [Channel]
    func openDirectMessage(userID: UserID) async throws -> Channel
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
    func sendFriendRequest(username: String) async throws -> User
    func acceptFriendRequest(userID: UserID) async throws -> User
    func denyFriendRequest(userID: UserID) async throws -> User
    func removeFriend(userID: UserID) async throws -> User
    func blockUser(userID: UserID) async throws -> User
    func unblockUser(userID: UserID) async throws -> User
    func fetchInvitePreview(code: InviteCode) async throws -> InvitePreview
    func joinInvite(code: InviteCode) async throws -> InviteJoinResponse
    func createInvite(channelID: ChannelID) async throws -> Invite
    func fetchServerInvites(serverID: ServerID) async throws -> [Invite]
    func deleteInvite(code: InviteCode) async throws
    func createServer(draft: ServerCreateDraft) async throws -> ServerCreateResponse
    func fetchServer(id: ServerID, includeChannels: Bool) async throws -> ServerFetchResponse
    func editServer(id: ServerID, draft: ServerEditDraft) async throws -> Server
    func createRole(serverID: ServerID, draft: RoleCreateDraft) async throws -> RoleCreateResponse
    func editRole(serverID: ServerID, roleID: RoleID, draft: RoleEditDraft) async throws -> Role
    func deleteRole(serverID: ServerID, roleID: RoleID) async throws
    func editMember(serverID: ServerID, userID: UserID, draft: MemberEditDraft) async throws -> ServerMember
    func kickMember(serverID: ServerID, userID: UserID) async throws
    func banMember(serverID: ServerID, userID: UserID, draft: BanCreateDraft) async throws -> ServerBan
    func unbanMember(serverID: ServerID, userID: UserID) async throws
    func fetchServerBans(serverID: ServerID) async throws -> BanListResult
    func setServerRolePermissions(serverID: ServerID, roleID: RoleID, draft: ServerRolePermissionDraft) async throws -> Server
    func setServerDefaultPermissions(serverID: ServerID, draft: ServerDefaultPermissionDraft) async throws -> Server
    func setChannelRolePermissions(channelID: ChannelID, roleID: RoleID, draft: ServerRolePermissionDraft) async throws -> Channel
    func setChannelDefaultPermissions(channelID: ChannelID, draft: ChannelDefaultPermissionDraft) async throws -> Channel
    func createChannel(serverID: ServerID, draft: ChannelCreateDraft) async throws -> Channel
    func editChannel(id: ChannelID, draft: ChannelEditDraft) async throws -> Channel
    func deleteChannel(id: ChannelID) async throws
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

    func fetchUserProfile(userID: UserID) async throws -> UserProfile {
        throw StoatAPIError.unimplementedEndpoint("User profile fetch is not implemented by this API client.")
    }

    func fetchDirectMessages() async throws -> [Channel] {
        throw StoatAPIError.unimplementedEndpoint("Direct message listing is not implemented by this API client.")
    }

    func openDirectMessage(userID: UserID) async throws -> Channel {
        throw StoatAPIError.unimplementedEndpoint("Direct message opening is not implemented by this API client.")
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

    func sendFriendRequest(username: String) async throws -> User {
        throw StoatAPIError.unimplementedEndpoint("Friend requests are not implemented by this API client.")
    }

    func acceptFriendRequest(userID: UserID) async throws -> User {
        throw StoatAPIError.unimplementedEndpoint("Friend requests are not implemented by this API client.")
    }

    func denyFriendRequest(userID: UserID) async throws -> User {
        try await removeFriend(userID: userID)
    }

    func removeFriend(userID: UserID) async throws -> User {
        throw StoatAPIError.unimplementedEndpoint("Friend removal is not implemented by this API client.")
    }

    func blockUser(userID: UserID) async throws -> User {
        throw StoatAPIError.unimplementedEndpoint("User blocking is not implemented by this API client.")
    }

    func unblockUser(userID: UserID) async throws -> User {
        throw StoatAPIError.unimplementedEndpoint("User unblocking is not implemented by this API client.")
    }

    func fetchInvitePreview(code: InviteCode) async throws -> InvitePreview {
        throw StoatAPIError.unimplementedEndpoint("Invite preview is not implemented by this API client.")
    }

    func joinInvite(code: InviteCode) async throws -> InviteJoinResponse {
        throw StoatAPIError.unimplementedEndpoint("Invite join is not implemented by this API client.")
    }

    func createInvite(channelID: ChannelID) async throws -> Invite {
        throw StoatAPIError.unimplementedEndpoint("Invite creation is not implemented by this API client.")
    }

    func fetchServerInvites(serverID: ServerID) async throws -> [Invite] {
        throw StoatAPIError.unimplementedEndpoint("Server invite listing is not implemented by this API client.")
    }

    func deleteInvite(code: InviteCode) async throws {
        throw StoatAPIError.unimplementedEndpoint("Invite deletion is not implemented by this API client.")
    }

    func createServer(draft: ServerCreateDraft) async throws -> ServerCreateResponse {
        throw StoatAPIError.unimplementedEndpoint("Server creation is not implemented by this API client.")
    }

    func fetchServer(id: ServerID, includeChannels: Bool = false) async throws -> ServerFetchResponse {
        throw StoatAPIError.unimplementedEndpoint("Server fetch is not implemented by this API client.")
    }

    func editServer(id: ServerID, draft: ServerEditDraft) async throws -> Server {
        throw StoatAPIError.unimplementedEndpoint("Server edit is not implemented by this API client.")
    }

    func createRole(serverID: ServerID, draft: RoleCreateDraft) async throws -> RoleCreateResponse {
        throw StoatAPIError.unimplementedEndpoint("Role creation is not implemented by this API client.")
    }

    func editRole(serverID: ServerID, roleID: RoleID, draft: RoleEditDraft) async throws -> Role {
        throw StoatAPIError.unimplementedEndpoint("Role editing is not implemented by this API client.")
    }

    func deleteRole(serverID: ServerID, roleID: RoleID) async throws {
        throw StoatAPIError.unimplementedEndpoint("Role deletion is not implemented by this API client.")
    }

    func editMember(serverID: ServerID, userID: UserID, draft: MemberEditDraft) async throws -> ServerMember {
        throw StoatAPIError.unimplementedEndpoint("Member editing is not implemented by this API client.")
    }

    func kickMember(serverID: ServerID, userID: UserID) async throws {
        throw StoatAPIError.unimplementedEndpoint("Member removal is not implemented by this API client.")
    }

    func banMember(serverID: ServerID, userID: UserID, draft: BanCreateDraft) async throws -> ServerBan {
        throw StoatAPIError.unimplementedEndpoint("Member banning is not implemented by this API client.")
    }

    func unbanMember(serverID: ServerID, userID: UserID) async throws {
        throw StoatAPIError.unimplementedEndpoint("Member unbanning is not implemented by this API client.")
    }

    func fetchServerBans(serverID: ServerID) async throws -> BanListResult {
        throw StoatAPIError.unimplementedEndpoint("Ban listing is not implemented by this API client.")
    }

    func setServerRolePermissions(serverID: ServerID, roleID: RoleID, draft: ServerRolePermissionDraft) async throws -> Server {
        throw StoatAPIError.unimplementedEndpoint("Server role permission editing is not implemented by this API client.")
    }

    func setServerDefaultPermissions(serverID: ServerID, draft: ServerDefaultPermissionDraft) async throws -> Server {
        throw StoatAPIError.unimplementedEndpoint("Server default permission editing is not implemented by this API client.")
    }

    func setChannelRolePermissions(channelID: ChannelID, roleID: RoleID, draft: ServerRolePermissionDraft) async throws -> Channel {
        throw StoatAPIError.unimplementedEndpoint("Channel role permission editing is not implemented by this API client.")
    }

    func setChannelDefaultPermissions(channelID: ChannelID, draft: ChannelDefaultPermissionDraft) async throws -> Channel {
        throw StoatAPIError.unimplementedEndpoint("Channel default permission editing is not implemented by this API client.")
    }

    func createChannel(serverID: ServerID, draft: ChannelCreateDraft) async throws -> Channel {
        throw StoatAPIError.unimplementedEndpoint("Channel creation is not implemented by this API client.")
    }

    func editChannel(id: ChannelID, draft: ChannelEditDraft) async throws -> Channel {
        throw StoatAPIError.unimplementedEndpoint("Channel editing is not implemented by this API client.")
    }

    func deleteChannel(id: ChannelID) async throws {
        throw StoatAPIError.unimplementedEndpoint("Channel deletion is not implemented by this API client.")
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

    public func fetchUserProfile(userID: UserID) async throws -> UserProfile {
        try await perform(StoatRequest<UserProfile>(method: .get, path: "/users/\(userID.rawValue.stoatPathComponentEscaped)/profile"))
    }

    public func fetchServers() async throws -> [Server] {
        throw StoatAPIError.unimplementedEndpoint("No verified REST route lists the current user's servers; use Ready over realtime in Phase 2.")
    }

    public func fetchChannels() async throws -> [Channel] {
        throw StoatAPIError.unimplementedEndpoint("No verified REST route lists all current-user channels; use Ready/users/dms plus server channels later.")
    }

    public func fetchDirectMessages() async throws -> [Channel] {
        try await perform(StoatRequest<[Channel]>(method: .get, path: "/users/dms"))
    }

    public func openDirectMessage(userID: UserID) async throws -> Channel {
        try await perform(StoatRequest<Channel>(method: .get, path: "/users/\(userID.rawValue.stoatPathComponentEscaped)/dm"))
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

    public func sendFriendRequest(username: String) async throws -> User {
        try await perform(
            StoatRequest<User>(
                method: .post,
                path: "/users/friend",
                body: .json(try encoder.encode(FriendRequestBody(username: username)))
            )
        )
    }

    public func acceptFriendRequest(userID: UserID) async throws -> User {
        try await perform(StoatRequest<User>(method: .put, path: "/users/\(userID.rawValue.stoatPathComponentEscaped)/friend"))
    }

    public func denyFriendRequest(userID: UserID) async throws -> User {
        try await removeFriend(userID: userID)
    }

    public func removeFriend(userID: UserID) async throws -> User {
        try await perform(StoatRequest<User>(method: .delete, path: "/users/\(userID.rawValue.stoatPathComponentEscaped)/friend"))
    }

    public func blockUser(userID: UserID) async throws -> User {
        try await perform(StoatRequest<User>(method: .put, path: "/users/\(userID.rawValue.stoatPathComponentEscaped)/block"))
    }

    public func unblockUser(userID: UserID) async throws -> User {
        try await perform(StoatRequest<User>(method: .delete, path: "/users/\(userID.rawValue.stoatPathComponentEscaped)/block"))
    }

    public func fetchInvitePreview(code: InviteCode) async throws -> InvitePreview {
        try await perform(StoatRequest<InvitePreview>(method: .get, path: "/invites/\(code.rawValue.stoatPathComponentEscaped)", requiresAuthentication: false))
    }

    public func joinInvite(code: InviteCode) async throws -> InviteJoinResponse {
        try await perform(StoatRequest<InviteJoinResponse>(method: .post, path: "/invites/\(code.rawValue.stoatPathComponentEscaped)"))
    }

    public func createInvite(channelID: ChannelID) async throws -> Invite {
        try await perform(StoatRequest<Invite>(method: .post, path: "/channels/\(channelID.rawValue.stoatPathComponentEscaped)/invites"))
    }

    public func fetchServerInvites(serverID: ServerID) async throws -> [Invite] {
        try await perform(StoatRequest<[Invite]>(method: .get, path: "/servers/\(serverID.rawValue.stoatPathComponentEscaped)/invites"))
    }

    public func deleteInvite(code: InviteCode) async throws {
        _ = try await perform(StoatRequest<EmptyResponse>(method: .delete, path: "/invites/\(code.rawValue.stoatPathComponentEscaped)"))
    }

    public func createServer(draft: ServerCreateDraft) async throws -> ServerCreateResponse {
        guard let validated = draft.validatedForCreate else {
            throw StoatAPIError.invalidEnvironment("Server name must be 1 to 32 characters.")
        }
        return try await perform(
            StoatRequest<ServerCreateResponse>(
                method: .post,
                path: "/servers/create",
                body: .json(try encoder.encode(validated))
            )
        )
    }

    public func fetchServer(id: ServerID, includeChannels: Bool = false) async throws -> ServerFetchResponse {
        let queryItems = includeChannels ? [URLQueryItem(name: "include_channels", value: "true")] : []
        return try await perform(
            StoatRequest<ServerFetchResponse>(
                method: .get,
                path: "/servers/\(id.rawValue.stoatPathComponentEscaped)",
                queryItems: queryItems
            )
        )
    }

    public func editServer(id: ServerID, draft: ServerEditDraft) async throws -> Server {
        try await perform(
            StoatRequest<Server>(
                method: .patch,
                path: "/servers/\(id.rawValue.stoatPathComponentEscaped)",
                body: .json(try encoder.encode(draft))
            )
        )
    }

    public func createRole(serverID: ServerID, draft: RoleCreateDraft) async throws -> RoleCreateResponse {
        guard let validated = draft.validatedForCreate else {
            throw StoatAPIError.invalidEnvironment("Role name must be 1 to 32 characters.")
        }
        return try await perform(
            StoatRequest<RoleCreateResponse>(
                method: .post,
                path: "/servers/\(serverID.rawValue.stoatPathComponentEscaped)/roles",
                body: .json(try encoder.encode(validated))
            )
        )
    }

    public func editRole(serverID: ServerID, roleID: RoleID, draft: RoleEditDraft) async throws -> Role {
        try await perform(
            StoatRequest<Role>(
                method: .patch,
                path: "/servers/\(serverID.rawValue.stoatPathComponentEscaped)/roles/\(roleID.rawValue.stoatPathComponentEscaped)",
                body: .json(try encoder.encode(draft))
            )
        )
    }

    public func deleteRole(serverID: ServerID, roleID: RoleID) async throws {
        _ = try await perform(
            StoatRequest<EmptyResponse>(
                method: .delete,
                path: "/servers/\(serverID.rawValue.stoatPathComponentEscaped)/roles/\(roleID.rawValue.stoatPathComponentEscaped)"
            )
        )
    }

    public func editMember(serverID: ServerID, userID: UserID, draft: MemberEditDraft) async throws -> ServerMember {
        try await perform(
            StoatRequest<ServerMember>(
                method: .patch,
                path: "/servers/\(serverID.rawValue.stoatPathComponentEscaped)/members/\(userID.rawValue.stoatPathComponentEscaped)",
                body: .json(try encoder.encode(draft))
            )
        )
    }

    public func kickMember(serverID: ServerID, userID: UserID) async throws {
        _ = try await perform(
            StoatRequest<EmptyResponse>(
                method: .delete,
                path: "/servers/\(serverID.rawValue.stoatPathComponentEscaped)/members/\(userID.rawValue.stoatPathComponentEscaped)"
            )
        )
    }

    public func banMember(serverID: ServerID, userID: UserID, draft: BanCreateDraft) async throws -> ServerBan {
        try await perform(
            StoatRequest<ServerBan>(
                method: .put,
                path: "/servers/\(serverID.rawValue.stoatPathComponentEscaped)/bans/\(userID.rawValue.stoatPathComponentEscaped)",
                body: .json(try encoder.encode(draft))
            )
        )
    }

    public func unbanMember(serverID: ServerID, userID: UserID) async throws {
        _ = try await perform(
            StoatRequest<EmptyResponse>(
                method: .delete,
                path: "/servers/\(serverID.rawValue.stoatPathComponentEscaped)/bans/\(userID.rawValue.stoatPathComponentEscaped)"
            )
        )
    }

    public func fetchServerBans(serverID: ServerID) async throws -> BanListResult {
        try await perform(
            StoatRequest<BanListResult>(
                method: .get,
                path: "/servers/\(serverID.rawValue.stoatPathComponentEscaped)/bans"
            )
        )
    }

    public func setServerRolePermissions(serverID: ServerID, roleID: RoleID, draft: ServerRolePermissionDraft) async throws -> Server {
        try await perform(
            StoatRequest<Server>(
                method: .put,
                path: "/servers/\(serverID.rawValue.stoatPathComponentEscaped)/permissions/\(roleID.rawValue.stoatPathComponentEscaped)",
                body: .json(try encoder.encode(draft))
            )
        )
    }

    public func setServerDefaultPermissions(serverID: ServerID, draft: ServerDefaultPermissionDraft) async throws -> Server {
        try await perform(
            StoatRequest<Server>(
                method: .put,
                path: "/servers/\(serverID.rawValue.stoatPathComponentEscaped)/permissions/default",
                body: .json(try encoder.encode(draft))
            )
        )
    }

    public func setChannelRolePermissions(channelID: ChannelID, roleID: RoleID, draft: ServerRolePermissionDraft) async throws -> Channel {
        try await perform(
            StoatRequest<Channel>(
                method: .put,
                path: "/channels/\(channelID.rawValue.stoatPathComponentEscaped)/permissions/\(roleID.rawValue.stoatPathComponentEscaped)",
                body: .json(try encoder.encode(draft))
            )
        )
    }

    public func setChannelDefaultPermissions(channelID: ChannelID, draft: ChannelDefaultPermissionDraft) async throws -> Channel {
        try await perform(
            StoatRequest<Channel>(
                method: .put,
                path: "/channels/\(channelID.rawValue.stoatPathComponentEscaped)/permissions/default",
                body: .json(try encoder.encode(draft))
            )
        )
    }

    public func createChannel(serverID: ServerID, draft: ChannelCreateDraft) async throws -> Channel {
        guard let validated = draft.validatedForCreate else {
            throw StoatAPIError.invalidEnvironment("Channel name must be 1 to 32 characters.")
        }
        return try await perform(
            StoatRequest<Channel>(
                method: .post,
                path: "/servers/\(serverID.rawValue.stoatPathComponentEscaped)/channels",
                body: .json(try encoder.encode(validated))
            )
        )
    }

    public func editChannel(id: ChannelID, draft: ChannelEditDraft) async throws -> Channel {
        try await perform(
            StoatRequest<Channel>(
                method: .patch,
                path: "/channels/\(id.rawValue.stoatPathComponentEscaped)",
                body: .json(try encoder.encode(draft))
            )
        )
    }

    public func deleteChannel(id: ChannelID) async throws {
        _ = try await perform(StoatRequest<EmptyResponse>(method: .delete, path: "/channels/\(id.rawValue.stoatPathComponentEscaped)"))
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

private struct FriendRequestBody: Encodable {
    var username: String
}
