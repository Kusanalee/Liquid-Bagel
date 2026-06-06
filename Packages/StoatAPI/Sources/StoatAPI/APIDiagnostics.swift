import Foundation
import StoatModels

public struct APIRequestDiagnostics: Codable, Hashable, Sendable {
    public var method: String
    public var route: String
    public var redactedResourceID: String?
    public var authHeaderPresent: Bool
    public var httpStatus: Int?
    public var contentType: String?
    public var topLevelResponseShape: String?
    public var decoderSummary: String?
    public var errorCategory: String?
    public var rateLimitInfo: RateLimitInfo
    public var responseByteCount: Int

    public init(
        method: String,
        route: String,
        redactedResourceID: String? = nil,
        authHeaderPresent: Bool,
        httpStatus: Int? = nil,
        contentType: String? = nil,
        topLevelResponseShape: String? = nil,
        decoderSummary: String? = nil,
        errorCategory: String? = nil,
        rateLimitInfo: RateLimitInfo = RateLimitInfo(),
        responseByteCount: Int = 0
    ) {
        self.method = method
        self.route = route
        self.redactedResourceID = redactedResourceID
        self.authHeaderPresent = authHeaderPresent
        self.httpStatus = httpStatus
        self.contentType = contentType
        self.topLevelResponseShape = topLevelResponseShape
        self.decoderSummary = decoderSummary
        self.errorCategory = errorCategory
        self.rateLimitInfo = rateLimitInfo
        self.responseByteCount = responseByteCount
    }

    public var redactedSummary: String {
        [
            "method \(method)",
            "route \(route)",
            "resource \(redactedResourceID ?? "-")",
            "auth \(authHeaderPresent ? "present" : "missing")",
            "status \(httpStatus.map(String.init) ?? "-")",
            "contentType \(contentType ?? "-")",
            "shape \(topLevelResponseShape ?? "-")",
            "decoder \(decoderSummary ?? "-")",
            "category \(errorCategory ?? "-")",
            "rateLimit remaining \(rateLimitInfo.remaining.map(String.init) ?? "-")",
            "bytes \(responseByteCount)"
        ].joined(separator: ", ")
    }
}

public struct StoatAPIDiagnosedError: Error, LocalizedError, Sendable {
    public var apiError: StoatAPIError
    public var diagnostics: APIRequestDiagnostics

    public init(apiError: StoatAPIError, diagnostics: APIRequestDiagnostics) {
        self.apiError = apiError
        self.diagnostics = diagnostics
    }

    public var errorDescription: String? {
        apiError.errorDescription
    }
}

public struct ServerMembersResponse: Decodable, Hashable, Sendable {
    public var members: [ServerMember]
    public var users: [User]
    public var diagnostics: APIRequestDiagnostics?

    public init(members: [ServerMember], users: [User] = [], diagnostics: APIRequestDiagnostics? = nil) {
        self.members = members
        self.users = users
        self.diagnostics = diagnostics
    }

    private enum CodingKeys: String, CodingKey {
        case members
        case users
    }
}

public enum APIResponseShapeSummarizer {
    public static func summarize(_ data: Data) -> String {
        guard !data.isEmpty else { return "empty" }
        guard let value = try? JSONSerialization.jsonObject(with: data) else { return "non-json" }
        if let dictionary = value as? [String: Any] {
            let keys = dictionary.keys.sorted()
            return "object{\(keys.prefix(8).joined(separator: ","))}"
        }
        if let array = value as? [Any] {
            return "array[\(array.count)]"
        }
        if value is String { return "string" }
        if value is NSNumber { return "number/bool" }
        return "json"
    }
}
