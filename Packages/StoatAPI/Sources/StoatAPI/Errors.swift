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

