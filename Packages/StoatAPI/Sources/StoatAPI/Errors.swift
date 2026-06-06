import Foundation

public enum StoatAPIError: Error, Equatable, Sendable {
    case invalidURL
    case invalidEnvironment(String)
    case missingAuthentication
    case unauthorized
    case forbidden
    case notFound
    case rateLimited(retryAfterMilliseconds: Int?)
    case serverError(statusCode: Int, message: String?)
    case decodingFailed(String)
    case transport(String)
    case unimplementedEndpoint(String)
    case unknown(statusCode: Int, body: String?)
}

extension StoatAPIError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The request URL is invalid."
        case let .invalidEnvironment(message):
            return message
        case .missingAuthentication:
            return "This request requires a signed-in session."
        case .unauthorized:
            return "The saved session is not authorized."
        case .forbidden:
            return "You do not have permission to perform this request."
        case .notFound:
            return "The requested Stoat resource was not found."
        case let .rateLimited(retryAfterMilliseconds):
            if let retryAfterMilliseconds {
                return "Stoat rate-limited this request. Retry after \(retryAfterMilliseconds) ms."
            }
            return "Stoat rate-limited this request."
        case let .serverError(statusCode, message):
            return message.map { "Stoat returned server error \(statusCode): \($0)" } ?? "Stoat returned server error \(statusCode)."
        case let .decodingFailed(message):
            return "Stoat response did not match the expected shape: \(message)"
        case let .transport(message):
            return "Network request failed: \(message)"
        case let .unimplementedEndpoint(message):
            return message
        case let .unknown(statusCode, _):
            return "Stoat returned unexpected HTTP status \(statusCode)."
        }
    }

    public var diagnosticCategory: String {
        switch self {
        case .missingAuthentication, .unauthorized:
            return "authentication"
        case .forbidden:
            return "permission"
        case .notFound:
            return "not-found"
        case .rateLimited:
            return "rate-limit"
        case .serverError:
            return "server"
        case .decodingFailed:
            return "response-mismatch"
        case .transport:
            return "network"
        case .invalidURL, .invalidEnvironment, .unimplementedEndpoint:
            return "client"
        case .unknown:
            return "unknown-status"
        }
    }
}

public struct APIErrorBody: Codable, Hashable, Sendable {
    public var type: String?
    public var location: String?
    public var retryAfter: Int?
    public var error: String?

    private enum CodingKeys: String, CodingKey {
        case type
        case location
        case retryAfter = "retry_after"
        case error
    }
}
