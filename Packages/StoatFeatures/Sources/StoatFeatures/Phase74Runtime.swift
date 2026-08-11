import Foundation
import StoatModels

// Phase 74 -- continuous timeline pagination.
//
// The "Load Older Messages" button is gone. Older pages are fetched automatically as the user
// scrolls toward the start of loaded history, which means the fetch decision is no longer a
// deliberate user action and has to defend itself: it must not re-enter, must not spin when the
// channel is shorter than the viewport, and must not retry a failing request forever.
//
// The pure decision logic lives here so it can be tested without SwiftUI or a live view model.

/// Decides when the timeline is close enough to the oldest loaded message to start fetching the
/// next page.
///
/// This runs from `onScrollGeometryChange`, i.e. potentially on every scroll tick, so it stays
/// pure arithmetic with no allocation. Callers must quantise the result to a `Bool` *inside* the
/// geometry transform: SwiftUI only invokes the action when the transformed value changes, so a
/// `Bool` costs one call per threshold crossing while a `CGFloat` would cost one per frame.
public enum TimelinePrefetchPolicy {
    public static func isNearOldest(
        contentOffsetY: CGFloat,
        containerHeight: CGFloat,
        distancePercent: Int
    ) -> Bool {
        guard containerHeight > 0 else { return false }
        // 0% means "only when actually at the top", which is what the debugStrict preset wants.
        guard distancePercent > 0 else { return contentOffsetY <= 0 }
        return contentOffsetY < containerHeight * (CGFloat(distancePercent) / 100)
    }

    /// Backstop trigger.
    ///
    /// The geometry `Bool` only fires on a change. After a prepend restores position the offset
    /// should grow and flip it back to `false`, re-arming it -- but restoration is anchored to a
    /// row top, not an exact offset, so that is not guaranteed. If the flag stays `true` the
    /// geometry callback never fires again and pagination silently stops. Row distance is
    /// recomputed from scratch on every visibility flush, so it cannot get stuck that way.
    public static func isNearOldestRow(firstVisibleIndex: Int?, rowThreshold: Int) -> Bool {
        guard let firstVisibleIndex else { return false }
        return firstVisibleIndex <= rowThreshold
    }
}

/// Scroll intents fall into two families that want opposite treatment.
///
/// A *navigation* (jump to newest, jump to a search hit) is movement the user asked for, and
/// animating it communicates where they went. A *restoration* (holding position while older
/// messages are inserted above) is meant to be invisible -- animating it renders the very jump
/// the restoration exists to hide as a deliberate 180 ms swoop.
public enum TimelineScrollAnimationPolicy {
    public static func shouldAnimate(intent: TimelineScrollIntent, reduceMotion: Bool) -> Bool {
        guard !reduceMotion else { return false }
        switch intent {
        case .preservePositionAfterPrepend, .preserveVisibleAnchor:
            return false
        case .message, .newest, .firstUnread:
            return true
        }
    }
}

/// What asked for an older page. Automatic triggers are rate-limited; an explicit user command
/// bypasses the cooldown and the consecutive-page budget, because the user asking again is itself
/// the signal that they want another attempt.
public enum OlderLoadTrigger: Hashable, Sendable {
    case scrollPrefetch
    case visibleRangeNearOldest
    case explicitCommand

    public var isAutomatic: Bool { self != .explicitCommand }
}

/// Why a prefetch request was dropped. Recorded for diagnostics so a channel that mysteriously
/// stops paginating can be explained without a debugger.
public enum OlderLoadSuppressionReason: String, Hashable, Sendable {
    case notSelectedChannel
    case alreadyInFlight
    case noLoadedHistory
    case initialLoadInFlight
    case pageAlreadyLoading
    case noMoreBefore
    case unreadRecoveryInProgress
    case failureCooldown
    case automaticPageBudgetExhausted
}

/// The single 32 pt slot at the top of loaded history.
///
/// It is always present and always the same height. The old implementation swapped a button
/// (~32 pt) for a spinner (~20 pt) for a caption (~16 pt) at index 0 of the `LazyVStack`, so
/// every pagination state change shifted all content below it -- a source of visible jump that
/// no scroll-anchor mechanism can compensate for.
public enum OlderHistoryHeaderState: Hashable, Sendable {
    /// More history exists and nothing is happening yet. Renders as reserved empty space.
    case idle
    case loading
    /// Genuinely the start of the channel.
    case beginning(channelName: String?)
    /// Out of *cached* history while offline. Distinct from `beginning` on purpose: telling
    /// someone they have reached the start of a channel when they have only reached the end of
    /// what was cached is a lie the offline shell should not tell.
    case unavailableOffline
    case failed(message: String)
}

// MARK: - Connection chrome

public enum ConnectionChromeLevel: Hashable, Sendable {
    case info
    case warning
    case error
}

/// What the window says about the connection.
///
/// Produced as `nil` when everything is fine. A healthy app should not spend a permanent line of
/// the sidebar telling you it is connected -- that is the expected state, and stating it is noise
/// that trains people to ignore the place real problems appear.
public struct ConnectionChrome: Hashable, Sendable {
    public var level: ConnectionChromeLevel
    public var title: String
    public var detail: String?
    public var systemImage: String
    public var actionTitle: String?

    public init(
        level: ConnectionChromeLevel,
        title: String,
        detail: String? = nil,
        systemImage: String,
        actionTitle: String? = nil
    ) {
        self.level = level
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.actionTitle = actionTitle
    }
}

/// Anything that changes state on the server.
public enum WriteAction: Hashable, Sendable {
    case sendMessage
    case attachFile
    case react
    case edit
    case delete
    case pin

    /// Completes "Reconnect to ___."
    var verb: String {
        switch self {
        case .sendMessage: "send messages"
        case .attachFile: "attach files"
        case .react: "react"
        case .edit: "edit messages"
        case .delete: "delete messages"
        case .pin: "pin messages"
        }
    }
}

public struct Phase74PaginationDiagnostics: Hashable, Sendable {
    public var prefetchTriggerCount: Int
    public var prefetchSuppressedCount: Int
    public var pageLoadedCount: Int
    public var pageFailedCount: Int
    public var lastSuppressionReason: OlderLoadSuppressionReason?
    public var lastTrigger: OlderLoadTrigger?

    public init(
        prefetchTriggerCount: Int = 0,
        prefetchSuppressedCount: Int = 0,
        pageLoadedCount: Int = 0,
        pageFailedCount: Int = 0,
        lastSuppressionReason: OlderLoadSuppressionReason? = nil,
        lastTrigger: OlderLoadTrigger? = nil
    ) {
        self.prefetchTriggerCount = prefetchTriggerCount
        self.prefetchSuppressedCount = prefetchSuppressedCount
        self.pageLoadedCount = pageLoadedCount
        self.pageFailedCount = pageFailedCount
        self.lastSuppressionReason = lastSuppressionReason
        self.lastTrigger = lastTrigger
    }
}

/// Per-channel bookkeeping for automatic pagination.
public struct OlderLoadPacingState: Hashable, Sendable {
    public var isInFlight: Bool
    /// Consecutive automatic pages loaded without the user scrolling away from the top.
    ///
    /// This is the runaway guard. When loaded content is shorter than the viewport the scroll
    /// offset never moves, so "near the oldest message" stays true and every completed page
    /// immediately qualifies for the next one. The budget stops that; scrolling away resets it.
    public var consecutiveAutomaticPages: Int
    public var lastFailureAt: Date?

    public init(
        isInFlight: Bool = false,
        consecutiveAutomaticPages: Int = 0,
        lastFailureAt: Date? = nil
    ) {
        self.isInFlight = isInFlight
        self.consecutiveAutomaticPages = consecutiveAutomaticPages
        self.lastFailureAt = lastFailureAt
    }

    public static let maximumConsecutiveAutomaticPages = 3
    public static let failureCooldown: TimeInterval = 5
}
