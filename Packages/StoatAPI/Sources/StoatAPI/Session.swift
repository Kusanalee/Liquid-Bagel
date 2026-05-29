import Foundation
import StoatModels

public struct ValidatedSession: Hashable, Sendable {
    public var credential: StoatAuthCredential
    public var currentUser: User
    public var environment: StoatAPIEnvironment
    public var validatedAt: Date

    public init(
        credential: StoatAuthCredential,
        currentUser: User,
        environment: StoatAPIEnvironment,
        validatedAt: Date = Date()
    ) {
        self.credential = credential
        self.currentUser = currentUser
        self.environment = environment
        self.validatedAt = validatedAt
    }
}

public enum SessionValidationError: Error, Equatable, Sendable, LocalizedError {
    case missingCredential
    case invalidOrExpired
    case forbidden
    case rateLimited(retryAfterMilliseconds: Int?)
    case networkUnavailable(String)
    case serverUnavailable(String)
    case invalidEnvironment(String)
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .missingCredential:
            "No session credential is available."
        case .invalidOrExpired:
            "The saved session is invalid or expired."
        case .forbidden:
            "This session is not allowed to access the account."
        case let .rateLimited(retryAfterMilliseconds):
            if let retryAfterMilliseconds {
                "Stoat rate limited validation. Try again in \(max(1, retryAfterMilliseconds / 1_000)) seconds."
            } else {
                "Stoat rate limited validation. Try again later."
            }
        case let .networkUnavailable(message):
            "Network unavailable while validating the session: \(message)"
        case let .serverUnavailable(message):
            "Stoat server unavailable while validating the session: \(message)"
        case let .invalidEnvironment(message):
            "The selected environment is invalid: \(message)"
        case let .failed(message):
            "Session validation failed: \(message)"
        }
    }
}

public protocol SessionValidating: Sendable {
    func validate(credential: StoatAuthCredential, environment: StoatAPIEnvironment) async throws -> ValidatedSession
}

public struct LiveSessionValidator: SessionValidating {
    private let apiClientFactory: @Sendable (StoatAPIEnvironment, any CredentialProvider) -> any StoatAPIClient

    public init(
        apiClientFactory: @escaping @Sendable (StoatAPIEnvironment, any CredentialProvider) -> any StoatAPIClient = { environment, provider in
            LiveStoatAPIClient(environment: environment, credentialProvider: provider)
        }
    ) {
        self.apiClientFactory = apiClientFactory
    }

    public func validate(credential: StoatAuthCredential, environment: StoatAPIEnvironment) async throws -> ValidatedSession {
        guard !credential.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SessionValidationError.missingCredential
        }

        do {
            try environment.validate()
            let client = apiClientFactory(environment, StaticCredentialProvider(credential))
            let currentUser = try await client.fetchCurrentUser()
            return ValidatedSession(credential: credential, currentUser: currentUser, environment: environment)
        } catch let error as SessionValidationError {
            throw error
        } catch let error as StoatAPIError {
            throw Self.map(error)
        } catch {
            throw SessionValidationError.failed(error.localizedDescription)
        }
    }

    public static func map(_ error: StoatAPIError) -> SessionValidationError {
        switch error {
        case .missingAuthentication, .unauthorized:
            .invalidOrExpired
        case .forbidden:
            .forbidden
        case let .rateLimited(retryAfterMilliseconds):
            .rateLimited(retryAfterMilliseconds: retryAfterMilliseconds)
        case let .serverError(_, message):
            .serverUnavailable(message ?? "The server returned an error.")
        case let .transport(message):
            .networkUnavailable(message)
        case let .invalidEnvironment(message):
            .invalidEnvironment(message)
        case let .unimplementedEndpoint(message), let .decodingFailed(message):
            .failed(message)
        case .invalidURL:
            .invalidEnvironment("The environment contains an invalid URL.")
        case .notFound:
            .failed("The validation endpoint was not found.")
        case let .unknown(_, body):
            .failed(body ?? "The server returned an unknown response.")
        }
    }
}

public struct SessionLoginRequest: Codable, Hashable, Sendable {
    public var email: String
    public var password: String
    public var friendlyName: String?

    public init(email: String, password: String, friendlyName: String? = nil) {
        self.email = email
        self.password = password
        self.friendlyName = friendlyName
    }

    private enum CodingKeys: String, CodingKey {
        case email
        case password
        case friendlyName = "friendly_name"
    }
}

public enum MFAMethod: String, Codable, Hashable, Sendable, CaseIterable {
    case password = "Password"
    case recovery = "Recovery"
    case totp = "Totp"
}

public enum MFAResponse: Hashable, Sendable, Codable {
    case password(String)
    case recoveryCode(String)
    case totpCode(String)

    private enum CodingKeys: String, CodingKey {
        case password
        case recoveryCode = "recovery_code"
        case totpCode = "totp_code"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let password = try container.decodeIfPresent(String.self, forKey: .password) {
            self = .password(password)
        } else if let recoveryCode = try container.decodeIfPresent(String.self, forKey: .recoveryCode) {
            self = .recoveryCode(recoveryCode)
        } else if let totpCode = try container.decodeIfPresent(String.self, forKey: .totpCode) {
            self = .totpCode(totpCode)
        } else {
            throw DecodingError.dataCorruptedError(forKey: .password, in: container, debugDescription: "Expected one MFA response value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .password(value):
            try container.encode(value, forKey: .password)
        case let .recoveryCode(value):
            try container.encode(value, forKey: .recoveryCode)
        case let .totpCode(value):
            try container.encode(value, forKey: .totpCode)
        }
    }
}

public struct SessionMFALoginRequest: Codable, Hashable, Sendable {
    public var mfaTicket: String
    public var mfaResponse: MFAResponse?
    public var friendlyName: String?

    public init(mfaTicket: String, mfaResponse: MFAResponse? = nil, friendlyName: String? = nil) {
        self.mfaTicket = mfaTicket
        self.mfaResponse = mfaResponse
        self.friendlyName = friendlyName
    }

    private enum CodingKeys: String, CodingKey {
        case mfaTicket = "mfa_ticket"
        case mfaResponse = "mfa_response"
        case friendlyName = "friendly_name"
    }
}

public struct SessionInfo: Codable, Hashable, Sendable, Identifiable {
    public var id: SessionID
    public var name: String

    public init(id: SessionID, name: String) {
        self.id = id
        self.name = name
    }

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name
    }
}

public enum SessionLoginResponse: Hashable, Sendable, Codable {
    case success(SessionLoginSuccess)
    case mfa(ticket: String, allowedMethods: [MFAMethod])
    case disabled(userID: UserID)

    private enum CodingKeys: String, CodingKey {
        case result
        case ticket
        case allowedMethods = "allowed_methods"
        case userID = "user_id"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .result) {
        case "Success":
            self = .success(try SessionLoginSuccess(from: decoder))
        case "MFA":
            self = .mfa(
                ticket: try container.decode(String.self, forKey: .ticket),
                allowedMethods: try container.decode([MFAMethod].self, forKey: .allowedMethods)
            )
        case "Disabled":
            self = .disabled(userID: try container.decode(UserID.self, forKey: .userID))
        case let result:
            throw DecodingError.dataCorruptedError(forKey: .result, in: container, debugDescription: "Unknown login result \(result)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case let .success(success):
            try success.encode(to: encoder)
        case let .mfa(ticket, allowedMethods):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("MFA", forKey: .result)
            try container.encode(ticket, forKey: .ticket)
            try container.encode(allowedMethods, forKey: .allowedMethods)
        case let .disabled(userID):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("Disabled", forKey: .result)
            try container.encode(userID, forKey: .userID)
        }
    }
}

public struct SessionLoginSuccess: Codable, Hashable, Sendable, CustomDebugStringConvertible {
    public var id: SessionID
    public var userID: UserID
    public var token: String
    public var name: String
    public var lastSeen: Date
    public var origin: String?

    public init(id: SessionID, userID: UserID, token: String, name: String, lastSeen: Date, origin: String? = nil) {
        self.id = id
        self.userID = userID
        self.token = token
        self.name = name
        self.lastSeen = lastSeen
        self.origin = origin
    }

    public var credential: StoatAuthCredential {
        .userSession(token: token, sessionID: id)
    }

    public var debugDescription: String {
        "SessionLoginSuccess(id: \(id.rawValue), userID: \(userID.rawValue), token: <redacted>, name: \(name))"
    }

    private enum CodingKeys: String, CodingKey {
        case result
        case id = "_id"
        case userID = "user_id"
        case token
        case name
        case lastSeen = "last_seen"
        case origin
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(SessionID.self, forKey: .id)
        self.userID = try container.decode(UserID.self, forKey: .userID)
        self.token = try container.decode(String.self, forKey: .token)
        self.name = try container.decode(String.self, forKey: .name)
        self.lastSeen = try container.decode(Date.self, forKey: .lastSeen)
        self.origin = try container.decodeIfPresent(String.self, forKey: .origin)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("Success", forKey: .result)
        try container.encode(id, forKey: .id)
        try container.encode(userID, forKey: .userID)
        try container.encode(token, forKey: .token)
        try container.encode(name, forKey: .name)
        try container.encode(lastSeen, forKey: .lastSeen)
        try container.encodeIfPresent(origin, forKey: .origin)
    }
}
