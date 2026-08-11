import Foundation
import StoatModels
import StoatRealtime

// Phase 74 -- getting back online.
//
// `LiveStoatRealtimeClient` already retries a dropped socket with exponential backoff, but it only
// ever reacts to its own failures. Two things it cannot see:
//
//   1. The Mac slept. The socket is dead, the OS may not have delivered an error yet, and the
//      network on the other side of the wake is often a different one.
//   2. The network came back. Backoff is counting down a delay that stopped being relevant the
//      moment Wi-Fi reassociated.
//
// This adds those two signals. The hard rule -- stated once, enforced in one place -- is that the
// supervisor never starts a connection while the client's own backoff is running. Two independent
// retry loops racing each other is worse than either alone.

public enum SystemPowerEvent: Hashable, Sendable {
    case willSleep
    case didWake
}

/// Bridge for `NSWorkspace` sleep/wake notifications, mirroring `AppLifecycleCenter`. AppKit stays
/// in the app target; this is the seam it posts through.
@MainActor
public final class SystemPowerCenter {
    public static let shared = SystemPowerCenter()

    private var handler: ((SystemPowerEvent) -> Void)?

    public init() {}

    public func setHandler(_ handler: @escaping (SystemPowerEvent) -> Void) {
        self.handler = handler
    }

    public func note(_ event: SystemPowerEvent) {
        handler?(event)
    }
}

public struct ConnectivitySupervisorDiagnostics: Hashable, Sendable {
    public var wakeTriggeredConnectCount: Int
    public var pathTriggeredConnectCount: Int
    public var foregroundTriggeredConnectCount: Int
    public var suppressedBecauseBackoffActiveCount: Int
    public var suppressedBecauseCooldownCount: Int
    public var suppressedBecauseOfflineCount: Int
    public var sleepSuspensionCount: Int

    public init(
        wakeTriggeredConnectCount: Int = 0,
        pathTriggeredConnectCount: Int = 0,
        foregroundTriggeredConnectCount: Int = 0,
        suppressedBecauseBackoffActiveCount: Int = 0,
        suppressedBecauseCooldownCount: Int = 0,
        suppressedBecauseOfflineCount: Int = 0,
        sleepSuspensionCount: Int = 0
    ) {
        self.wakeTriggeredConnectCount = wakeTriggeredConnectCount
        self.pathTriggeredConnectCount = pathTriggeredConnectCount
        self.foregroundTriggeredConnectCount = foregroundTriggeredConnectCount
        self.suppressedBecauseBackoffActiveCount = suppressedBecauseBackoffActiveCount
        self.suppressedBecauseCooldownCount = suppressedBecauseCooldownCount
        self.suppressedBecauseOfflineCount = suppressedBecauseOfflineCount
        self.sleepSuspensionCount = sleepSuspensionCount
    }
}

/// What prompted a reconnect attempt.
public enum ConnectivityTrigger: Hashable, Sendable {
    case wake
    case networkPath
    case foreground
}

/// Whether the supervisor may start a connection right now.
///
/// Extracted from the supervisor so the arbitration rules can be tested as a function of state
/// rather than by simulating hardware.
public enum ConnectivityPolicy {
    /// Connection states the supervisor is allowed to act from.
    ///
    /// Everything else means a connection attempt is already in progress -- including
    /// `.reconnecting`, which is the client's own backoff. Starting a second attempt there is the
    /// thing this policy exists to prevent.
    public static func isTerminal(_ state: RealtimeConnectionState) -> Bool {
        switch state {
        case .idle, .disconnected, .failed:
            return true
        case .connecting, .connected, .authenticating, .authenticated, .ready, .reconnecting:
            return false
        }
    }

    public static func cooldown(for trigger: ConnectivityTrigger) -> TimeInterval {
        switch trigger {
        // A wake is a strong, rare signal, so it is nearly unthrottled.
        case .wake: 1
        // Path changes flap: an interface can bounce several times while a laptop settles onto a
        // network.
        case .networkPath: 5
        // Activating the app is frequent and weak. It should top up a stalled connection, not
        // hammer a server that is genuinely down.
        case .foreground: 30
        }
    }

    /// The pause after `didWake` before trying. Waking hardware reports itself ready well before
    /// Wi-Fi has reassociated, so connecting immediately mostly buys one guaranteed failure.
    public static let wakeSettleDelay: Duration = .milliseconds(1_500)

    /// Debounce applied to a path becoming satisfied, for the same flapping reason as its
    /// cooldown.
    public static let pathSettleDelay: Duration = .seconds(2)

    public enum Decision: Hashable, Sendable {
        case connect
        case suppressedBackoffActive
        case suppressedCooldown
        case suppressedOffline
    }

    public static func decide(
        trigger: ConnectivityTrigger,
        connectionState: RealtimeConnectionState,
        pathStatus: NetworkPathStatus,
        lastAttemptAt: Date?,
        now: Date
    ) -> Decision {
        guard isTerminal(connectionState) else { return .suppressedBackoffActive }
        // `unknown` is not "offline" -- it means no path update has arrived yet, and refusing to
        // connect on it would strand a launch that never sees one.
        guard !pathStatus.isKnownOffline else { return .suppressedOffline }
        if let lastAttemptAt, now.timeIntervalSince(lastAttemptAt) < cooldown(for: trigger) {
            return .suppressedCooldown
        }
        return .connect
    }
}
