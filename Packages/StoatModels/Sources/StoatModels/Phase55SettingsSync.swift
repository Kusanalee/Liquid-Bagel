import Foundation

/// One synced setting from the verified `POST /sync/settings/fetch` response.
/// The wire form is a two-element array of `[timestamp, value]`, where `timestamp`
/// is epoch milliseconds and `value` is the previously uploaded string payload.
public struct SyncedSettingValue: Codable, Hashable, Sendable {
    public var timestamp: Int64
    public var rawValue: String

    public init(timestamp: Int64, rawValue: String) {
        self.timestamp = timestamp
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        timestamp = try container.decode(Int64.self)
        rawValue = try container.decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(timestamp)
        try container.encode(rawValue)
    }
}

/// Body for the verified `POST /sync/settings/fetch` route (`OptionsFetchSettings`).
public struct SyncedSettingsFetchRequest: Codable, Hashable, Sendable {
    public var keys: [String]

    public init(keys: [String]) {
        self.keys = keys
    }
}
