import Foundation
import StoatModels

public struct StoatAPIEnvironment: Equatable, Sendable {
    public var apiBaseURL: URL
    public var eventsWebSocketURL: URL
    public var mediaBaseURL: URL?
    public var proxyBaseURL: URL?

    public init(
        apiBaseURL: URL,
        eventsWebSocketURL: URL,
        mediaBaseURL: URL? = nil,
        proxyBaseURL: URL? = nil
    ) {
        self.apiBaseURL = apiBaseURL
        self.eventsWebSocketURL = eventsWebSocketURL
        self.mediaBaseURL = mediaBaseURL
        self.proxyBaseURL = proxyBaseURL
    }

    public static let official = StoatAPIEnvironment(
        apiBaseURL: URL(string: "https://api.stoat.chat")!,
        eventsWebSocketURL: URL(string: "wss://events.stoat.chat")!,
        mediaBaseURL: URL(string: "https://cdn.stoatusercontent.com"),
        proxyBaseURL: URL(string: "https://proxy.stoatusercontent.com")
    )
}

public enum StoatAuthCredential: Equatable, Sendable {
    case sessionToken(String)
    case botToken(String)

    public var headerName: String {
        switch self {
        case .sessionToken:
            "X-Session-Token"
        case .botToken:
            "X-Bot-Token"
        }
    }
}

public enum StoatAPIError: Error, Equatable, Sendable {
    case notImplemented
    case invalidResponse
    case rateLimited(retryAfterMilliseconds: Int?)
}

public protocol StoatAPIClient: Sendable {
    func getCurrentUser() async throws -> User
}

public struct MockStoatAPIClient: StoatAPIClient {
    private let currentUser: User

    public init(currentUser: User = User(id: UserID(rawValue: "phase-zero"), username: "liquidbagel")) {
        self.currentUser = currentUser
    }

    public func getCurrentUser() async throws -> User {
        currentUser
    }
}
