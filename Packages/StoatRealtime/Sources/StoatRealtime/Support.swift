import Foundation
import StoatModels

final class StreamHub<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]

    func stream() -> AsyncStream<Element> {
        AsyncStream { continuation in
            let id = UUID()
            lock.lock()
            continuations[id] = continuation
            lock.unlock()
            continuation.onTermination = { [weak self] _ in
                self?.lock.lock()
                self?.continuations.removeValue(forKey: id)
                self?.lock.unlock()
            }
        }
    }

    func yield(_ value: Element) {
        lock.lock()
        let continuations = Array(continuations.values)
        lock.unlock()
        for continuation in continuations {
            continuation.yield(value)
        }
    }

    func finish() {
        lock.lock()
        let continuations = Array(continuations.values)
        self.continuations.removeAll()
        lock.unlock()
        for continuation in continuations {
            continuation.finish()
        }
    }
}

struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

public struct RealtimeLogger: Sendable {
    public var debug: @Sendable (String) -> Void
    public var info: @Sendable (String) -> Void
    public var warning: @Sendable (String) -> Void
    public var error: @Sendable (String) -> Void

    public init(
        debug: @escaping @Sendable (String) -> Void,
        info: @escaping @Sendable (String) -> Void,
        warning: @escaping @Sendable (String) -> Void,
        error: @escaping @Sendable (String) -> Void
    ) {
        self.debug = debug
        self.info = info
        self.warning = warning
        self.error = error
    }

    public static let noop = RealtimeLogger(debug: { _ in }, info: { _ in }, warning: { _ in }, error: { _ in })
}

public struct RealtimeDiagnostics: Hashable, Sendable {
    public var connectedAt: Date?
    public var authenticatedAt: Date?
    public var readyAt: Date?
    public var lastReceivedEventAt: Date?
    public var lastPongAt: Date?
    public var lastNonControlEventAt: Date?
    public var lastLatencyMilliseconds: Int?
    public var reconnectAttempt: Int

    public init(
        connectedAt: Date? = nil,
        authenticatedAt: Date? = nil,
        readyAt: Date? = nil,
        lastReceivedEventAt: Date? = nil,
        lastPongAt: Date? = nil,
        lastNonControlEventAt: Date? = nil,
        lastLatencyMilliseconds: Int? = nil,
        reconnectAttempt: Int = 0
    ) {
        self.connectedAt = connectedAt
        self.authenticatedAt = authenticatedAt
        self.readyAt = readyAt
        self.lastReceivedEventAt = lastReceivedEventAt
        self.lastPongAt = lastPongAt
        self.lastNonControlEventAt = lastNonControlEventAt
        self.lastLatencyMilliseconds = lastLatencyMilliseconds
        self.reconnectAttempt = reconnectAttempt
    }
}

public enum RealtimeDisconnectReason: Equatable, Sendable {
    case requested
    case loggedOut
    case invalidSession
    case network
    case serverClosed(code: Int?, reason: String?)
    case unknown
}

public enum RealtimeError: Error, Equatable, Sendable {
    case invalidEventsURL
    case missingCredential
    case unsupportedCredential
    case authenticationFailed(GatewayErrorCode)
    case onboardingNotFinished
    case alreadyAuthenticated
    case disconnected(RealtimeDisconnectReason)
    case decodeFailed(String)
    case encodeFailed(String)
    case transport(String)
    case timeout(String)
    case unknown(String)
}

public enum RealtimeConnectionState: Equatable, Sendable {
    case idle
    case connecting
    case connected
    case authenticating
    case authenticated
    case ready
    case reconnecting(attempt: Int, nextDelay: Duration)
    case disconnected(reason: RealtimeDisconnectReason?)
    case failed(RealtimeError)
}

public struct ReconnectPolicy: Hashable, Sendable {
    public var initialDelay: Duration
    public var maximumDelay: Duration
    public var multiplier: Double
    public var jitterRatio: Double
    public var maximumAttempts: Int?

    public init(
        initialDelay: Duration = .seconds(1),
        maximumDelay: Duration = .seconds(30),
        multiplier: Double = 2,
        jitterRatio: Double = 0.2,
        maximumAttempts: Int? = nil
    ) {
        self.initialDelay = initialDelay
        self.maximumDelay = maximumDelay
        self.multiplier = multiplier
        self.jitterRatio = jitterRatio
        self.maximumAttempts = maximumAttempts
    }

    public func delay(forAttempt attempt: Int, jitter: Double = Double.random(in: -1...1)) -> Duration {
        let initial = initialDelay.secondsValue
        let maximum = maximumDelay.secondsValue
        let exponential = initial * pow(multiplier, Double(max(0, attempt - 1)))
        let capped = min(exponential, maximum)
        let adjusted = capped * (1 + jitterRatio * jitter)
        return .milliseconds(Int64(max(0, adjusted) * 1000))
    }
}

extension Duration {
    var secondsValue: Double {
        let components = components
        return Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }
}

public enum ReadyField: String, Codable, CaseIterable, Hashable, Sendable {
    case users
    case servers
    case channels
    case members
    case emojis
    case userSettings = "user_settings"
    case channelUnreads = "channel_unreads"
    case policyChanges = "policy_changes"
}

public struct PolicyChange: Codable, Hashable, Sendable {
    public var createdTime: String?
    public var effectiveTime: String?
    public var description: String?
    public var url: String?
    public var raw: JSONValue?

    public init(createdTime: String? = nil, effectiveTime: String? = nil, description: String? = nil, url: String? = nil, raw: JSONValue? = nil) {
        self.createdTime = createdTime
        self.effectiveTime = effectiveTime
        self.description = description
        self.url = url
        self.raw = raw
    }

    private enum CodingKeys: String, CodingKey {
        case createdTime = "created_time"
        case effectiveTime = "effective_time"
        case description
        case url
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        createdTime = try container.decodeIfPresent(String.self, forKey: .createdTime)
        effectiveTime = try container.decodeIfPresent(String.self, forKey: .effectiveTime)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        raw = try? JSONValue(from: decoder)
    }
}

public struct ReadyPayload: Codable, Hashable, Sendable {
    public var users: [User]?
    public var servers: [Server]?
    public var channels: [Channel]?
    public var members: [ServerMember]?
    public var emojis: [Emoji]?
    public var userSettings: UserSettings?
    public var channelUnreads: [ChannelUnread]?
    public var policyChanges: [PolicyChange]?

    public init(
        users: [User]? = nil,
        servers: [Server]? = nil,
        channels: [Channel]? = nil,
        members: [ServerMember]? = nil,
        emojis: [Emoji]? = nil,
        userSettings: UserSettings? = nil,
        channelUnreads: [ChannelUnread]? = nil,
        policyChanges: [PolicyChange]? = nil
    ) {
        self.users = users
        self.servers = servers
        self.channels = channels
        self.members = members
        self.emojis = emojis
        self.userSettings = userSettings
        self.channelUnreads = channelUnreads
        self.policyChanges = policyChanges
    }

    private enum CodingKeys: String, CodingKey {
        case users
        case servers
        case channels
        case members
        case emojis
        case userSettings = "user_settings"
        case channelUnreads = "channel_unreads"
        case policyChanges = "policy_changes"
    }
}
