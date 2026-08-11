import Foundation
import Network

// Phase 74 -- network reachability.
//
// The gateway already reconnects with exponential backoff when its socket dies, but nothing ever
// told it that the network had come *back*. On a Mac that woke from sleep onto a different
// network, or reconnected to Wi-Fi after a walk between rooms, the app would sit in backoff
// waiting out a delay that had nothing to do with reality.
//
// Reachability lives in StoatRealtime, next to `ReconnectPolicy`, because it is a transport
// concern. `Network.framework` needs no entitlement beyond the `network.client` the app already
// has.

public enum NetworkPathStatus: Hashable, Sendable {
    /// No observation has happened yet. Distinct from `unsatisfied`: never treat it as "offline",
    /// or a launch would report no internet before the first path update arrives.
    case unknown
    case satisfied
    case unsatisfied
    case requiresConnection

    public var isSatisfied: Bool { self == .satisfied }

    /// `unknown` is deliberately not "known offline". Only an observed `unsatisfied` justifies
    /// telling the user there is no internet connection rather than that the server is
    /// unreachable.
    public var isKnownOffline: Bool { self == .unsatisfied || self == .requiresConnection }
}

public protocol NetworkPathMonitoring: Sendable {
    var pathUpdates: AsyncStream<NetworkPathStatus> { get }
    func currentStatus() async -> NetworkPathStatus
    func start() async
    func cancel() async
}

public actor NWPathNetworkMonitor: NetworkPathMonitoring {
    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "chat.stoat.liquidbagel.networkpath")
    private let hub = StreamHub<NetworkPathStatus>()
    private var status: NetworkPathStatus = .unknown
    private var isStarted = false

    public init() {
        self.monitor = NWPathMonitor()
    }

    public nonisolated var pathUpdates: AsyncStream<NetworkPathStatus> {
        hub.stream()
    }

    public func currentStatus() async -> NetworkPathStatus { status }

    public func start() async {
        guard !isStarted else { return }
        isStarted = true
        monitor.pathUpdateHandler = { [weak self] path in
            let status = Self.status(for: path)
            Task { await self?.apply(status) }
        }
        monitor.start(queue: queue)
    }

    public func cancel() async {
        guard isStarted else { return }
        isStarted = false
        monitor.pathUpdateHandler = nil
        monitor.cancel()
    }

    private func apply(_ status: NetworkPathStatus) {
        // NWPathMonitor re-reports the same path on unrelated interface changes; only forward
        // genuine transitions so downstream debouncing is not fighting duplicates.
        guard status != self.status else { return }
        self.status = status
        hub.yield(status)
    }

    private static func status(for path: NWPath) -> NetworkPathStatus {
        switch path.status {
        case .satisfied: .satisfied
        case .unsatisfied: .unsatisfied
        case .requiresConnection: .requiresConnection
        @unknown default: .unknown
        }
    }
}

/// Deterministic monitor for tests: reachability transitions are driven explicitly rather than
/// waiting on real hardware.
public actor StaticNetworkPathMonitor: NetworkPathMonitoring {
    private let hub = StreamHub<NetworkPathStatus>()
    private var status: NetworkPathStatus

    public init(initial: NetworkPathStatus = .satisfied) {
        self.status = initial
    }

    public nonisolated var pathUpdates: AsyncStream<NetworkPathStatus> {
        hub.stream()
    }

    public func currentStatus() async -> NetworkPathStatus { status }
    public func start() async {}
    public func cancel() async {}

    public func send(_ status: NetworkPathStatus) {
        self.status = status
        hub.yield(status)
    }
}
