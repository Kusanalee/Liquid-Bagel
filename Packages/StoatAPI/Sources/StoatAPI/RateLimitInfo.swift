import Foundation

public struct RateLimitInfo: Codable, Hashable, Sendable {
    public var limit: Int?
    public var bucket: String?
    public var remaining: Int?
    public var resetAfterMilliseconds: Int?

    public init(limit: Int? = nil, bucket: String? = nil, remaining: Int? = nil, resetAfterMilliseconds: Int? = nil) {
        self.limit = limit
        self.bucket = bucket
        self.remaining = remaining
        self.resetAfterMilliseconds = resetAfterMilliseconds
    }

    public init(headers: [String: String]) {
        func value(_ name: String) -> String? {
            headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
        }

        limit = value("X-RateLimit-Limit").flatMap(Int.init)
        bucket = value("X-RateLimit-Bucket")
        remaining = value("X-RateLimit-Remaining").flatMap(Int.init)
        resetAfterMilliseconds = value("X-RateLimit-Reset-After").flatMap(Int.init)
    }
}

