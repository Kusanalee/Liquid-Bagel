import Foundation
import StoatModels

public struct EmptyResponse: Codable, Hashable, Sendable {
    public init() {}
}

public struct StoatHTTPResponse: Sendable {
    public var statusCode: Int
    public var headers: [String: String]
    public var data: Data

    public init(statusCode: Int, headers: [String: String] = [:], data: Data = Data()) {
        self.statusCode = statusCode
        self.headers = headers
        self.data = data
    }

    public var rateLimitInfo: RateLimitInfo {
        RateLimitInfo(headers: headers)
    }
}

public struct StoatResponseDecoder: Sendable {
    public var decoder: JSONDecoder

    public init(decoder: JSONDecoder = .stoat) {
        self.decoder = decoder
    }

    public func decode<Response: Decodable & Sendable>(
        _ type: Response.Type,
        from response: StoatHTTPResponse
    ) throws -> Response {
        switch response.statusCode {
        case 200..<300:
            return try decodeSuccess(type, data: response.data)
        case 401:
            throw StoatAPIError.unauthorized
        case 403:
            throw StoatAPIError.forbidden
        case 404:
            throw StoatAPIError.notFound
        case 429:
            throw StoatAPIError.rateLimited(retryAfterMilliseconds: retryAfter(from: response.data))
        case 500..<600:
            throw StoatAPIError.serverError(statusCode: response.statusCode, message: errorMessage(from: response.data))
        default:
            throw StoatAPIError.unknown(statusCode: response.statusCode, body: String(data: response.data, encoding: .utf8))
        }
    }

    private func decodeSuccess<Response: Decodable & Sendable>(_ type: Response.Type, data: Data) throws -> Response {
        if type == EmptyResponse.self {
            return EmptyResponse() as! Response
        }

        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw StoatAPIError.decodingFailed(Self.describeDecodingError(error))
        }
    }

    public static func describeDecodingError(_ error: Error) -> String {
        if let decodingError = error as? DecodingError {
            switch decodingError {
            case let .typeMismatch(type, context):
                return "type mismatch for \(type) at \(codingPath(context.codingPath)): \(context.debugDescription)"
            case let .valueNotFound(type, context):
                return "missing value for \(type) at \(codingPath(context.codingPath)): \(context.debugDescription)"
            case let .keyNotFound(key, context):
                return "missing key \(key.stringValue) at \(codingPath(context.codingPath)): \(context.debugDescription)"
            case let .dataCorrupted(context):
                return "data corrupted at \(codingPath(context.codingPath)): \(context.debugDescription)"
            @unknown default:
                return decodingError.localizedDescription
            }
        }
        return error.localizedDescription
    }

    private static func codingPath(_ path: [CodingKey]) -> String {
        let value = path.map(\.stringValue).joined(separator: ".")
        return value.isEmpty ? "$" : value
    }

    private func retryAfter(from data: Data) -> Int? {
        guard !data.isEmpty else { return nil }
        return try? decoder.decode(APIErrorBody.self, from: data).retryAfter
    }

    private func errorMessage(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        if let body = try? decoder.decode(APIErrorBody.self, from: data) {
            return body.error ?? body.type
        }
        return String(data: data, encoding: .utf8)
    }
}
