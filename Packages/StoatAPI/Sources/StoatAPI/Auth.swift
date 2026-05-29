import Foundation
import StoatModels

public enum StoatAuthCredential: Codable, Hashable, Sendable, CustomDebugStringConvertible {
    case userSession(token: String, sessionID: SessionID?)
    case botToken(String)

    public static func sessionToken(_ token: String) -> StoatAuthCredential {
        .userSession(token: token, sessionID: nil)
    }

    public var headerName: String {
        switch self {
        case .userSession:
            "X-Session-Token"
        case .botToken:
            "X-Bot-Token"
        }
    }

    public var token: String {
        switch self {
        case let .userSession(token, _):
            token
        case let .botToken(token):
            token
        }
    }

    public var redactedDescription: String {
        switch self {
        case let .userSession(_, sessionID):
            "userSession(token: <redacted>, sessionID: \(sessionID?.rawValue ?? "nil"))"
        case .botToken:
            "botToken(<redacted>)"
        }
    }

    public var debugDescription: String { redactedDescription }

    private enum CodingKeys: String, CodingKey {
        case kind
        case token
        case sessionID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "userSession":
            self = .userSession(
                token: try container.decode(String.self, forKey: .token),
                sessionID: try container.decodeIfPresent(SessionID.self, forKey: .sessionID)
            )
        case "botToken":
            self = .botToken(try container.decode(String.self, forKey: .token))
        case let kind:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unknown credential kind \(kind)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .userSession(token, sessionID):
            try container.encode("userSession", forKey: .kind)
            try container.encode(token, forKey: .token)
            try container.encodeIfPresent(sessionID, forKey: .sessionID)
        case let .botToken(token):
            try container.encode("botToken", forKey: .kind)
            try container.encode(token, forKey: .token)
        }
    }
}

public protocol CredentialProvider: Sendable {
    func credential() async throws -> StoatAuthCredential?
}

public struct StaticCredentialProvider: CredentialProvider {
    private let storedCredential: StoatAuthCredential?

    public init(_ credential: StoatAuthCredential?) {
        self.storedCredential = credential
    }

    public func credential() async throws -> StoatAuthCredential? {
        storedCredential
    }
}

public struct TokenStoreCredentialProvider: CredentialProvider {
    private let tokenStore: any TokenStore

    public init(tokenStore: any TokenStore) {
        self.tokenStore = tokenStore
    }

    public func credential() async throws -> StoatAuthCredential? {
        try await tokenStore.loadCredential()
    }
}
