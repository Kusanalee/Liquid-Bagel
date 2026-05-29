import Foundation
import StoatModels

public struct PersistenceScope: Equatable, Sendable {
    public var appGroupIdentifier: String?

    public init(appGroupIdentifier: String? = nil) {
        self.appGroupIdentifier = appGroupIdentifier
    }
}

public enum PersistenceError: Error, Equatable, Sendable {
    case notImplemented
}

public protocol StoatCacheRepository: Sendable {
    func cachedCurrentUser() async throws -> User?
}

public struct EmptyStoatCacheRepository: StoatCacheRepository {
    public init() {}

    public func cachedCurrentUser() async throws -> User? {
        nil
    }
}
