import Foundation
import StoatModels
import StoatPersistence
import StoatRealtime

#if canImport(AppKit)
import AppKit
#endif

#if canImport(UserNotifications)
@preconcurrency import UserNotifications
#endif

public enum NotificationPermissionStatus: String, Hashable, Sendable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral
    case unknown

    public var allowsDelivery: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined, .denied, .unknown:
            return false
        }
    }
}

public struct NotificationRoute: Codable, Hashable, Sendable {
    public var serverID: ServerID?
    public var channelID: ChannelID
    public var messageID: MessageID?

    public init(serverID: ServerID? = nil, channelID: ChannelID, messageID: MessageID? = nil) {
        self.serverID = serverID
        self.channelID = channelID
        self.messageID = messageID
    }

    public var userInfo: [String: String] {
        var output = ["channelID": channelID.rawValue]
        if let serverID { output["serverID"] = serverID.rawValue }
        if let messageID { output["messageID"] = messageID.rawValue }
        return output
    }

    public init?(userInfo: [AnyHashable: Any]) {
        guard let channel = userInfo["channelID"] as? String, !channel.isEmpty else { return nil }
        channelID = ChannelID(rawValue: channel)
        serverID = (userInfo["serverID"] as? String).flatMap { $0.isEmpty ? nil : ServerID(rawValue: $0) }
        messageID = (userInfo["messageID"] as? String).flatMap { $0.isEmpty ? nil : MessageID(rawValue: $0) }
    }
}

public enum AppLifecyclePhase: String, Codable, Hashable, Sendable {
    case active
    case inactive
    case background

    public var selectedChannelIsVisible: Bool {
        self == .active
    }
}

public struct QueuedNotificationRoute: Identifiable, Hashable, Sendable {
    public var id: String
    public var route: NotificationRoute
    public var queuedAt: Date
    public var expiresAt: Date

    public init(route: NotificationRoute, queuedAt: Date = Date(), expiresAfter: TimeInterval = 600) {
        self.route = route
        self.queuedAt = queuedAt
        self.expiresAt = queuedAt.addingTimeInterval(expiresAfter)
        self.id = [
            route.serverID?.rawValue ?? "-",
            route.channelID.rawValue,
            route.messageID?.rawValue ?? "-"
        ].joined(separator: ":")
    }

    public func isExpired(at date: Date = Date()) -> Bool {
        expiresAt <= date
    }
}

public enum NotificationRouteOutcome: String, Hashable, Sendable {
    case none
    case opened
    case queuedAwaitingShell
    case queuedAwaitingManualConnect
    case expired
    case failed
}

public enum NotificationClassificationKind: String, Hashable, Sendable {
    case mention
    case directMessage
    case unread
    case suppressed
}

public struct NotificationEvent: Identifiable, Hashable, Sendable {
    public var id: String
    public var route: NotificationRoute
    public var title: String
    public var body: String
    public var kind: NotificationClassificationKind
    public var createdAt: Date

    public init(
        id: String,
        route: NotificationRoute,
        title: String,
        body: String,
        kind: NotificationClassificationKind,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.route = route
        self.title = title
        self.body = body
        self.kind = kind
        self.createdAt = createdAt
    }
}

public enum NotificationSuppressionReason: String, Hashable, Sendable {
    case mockRuntime
    case missingCurrentUser
    case selfMessage
    case channelMuted
    case messageSuppressed
    case activeChannel
    case deliveryScope
    case unknownChannel
}

public enum NotificationClassification: Hashable, Sendable {
    case deliver(NotificationEvent)
    case suppress(NotificationSuppressionReason)
}

public struct NotificationClassificationContext: Hashable, Sendable {
    public var runtimeMode: AppRuntimeMode
    public var currentUserID: UserID?
    public var activeChannelID: ChannelID?
    public var isActiveChannelVisible: Bool
    public var preferences: NotificationPreferences
    public var snapshot: RealtimeSnapshot

    public init(
        runtimeMode: AppRuntimeMode,
        currentUserID: UserID?,
        activeChannelID: ChannelID?,
        isActiveChannelVisible: Bool = true,
        preferences: NotificationPreferences,
        snapshot: RealtimeSnapshot
    ) {
        self.runtimeMode = runtimeMode
        self.currentUserID = currentUserID
        self.activeChannelID = activeChannelID
        self.isActiveChannelVisible = isActiveChannelVisible
        self.preferences = preferences
        self.snapshot = snapshot
    }
}

public struct NotificationBadgeCounts: Hashable, Sendable {
    public var unreadChannelCount: Int
    public var mentionCount: Int

    public init(unreadChannelCount: Int = 0, mentionCount: Int = 0) {
        self.unreadChannelCount = unreadChannelCount
        self.mentionCount = mentionCount
    }

    public func badgeValue(mode: DockBadgePreference) -> Int {
        switch mode {
        case .off:
            return 0
        case .mentionsOnly:
            return mentionCount
        case .unreadChannelsAndMentions:
            return unreadChannelCount + mentionCount
        }
    }
}

public enum NotificationContentFormatter {
    public static func title(message: Message, channel: Channel, snapshot: RealtimeSnapshot, privacy: NotificationContentVisibility) -> String {
        guard privacy == .showSenderAndContent else { return "New Stoat notification" }
        let author = message.user ?? snapshot.usersByID[message.authorID]
        let authorName = author?.displayName ?? author?.username ?? "Someone"
        if channel.kind == .directMessage || channel.kind == .group {
            return authorName
        }
        return "\(authorName) in #\(channel.displayName)"
    }

    public static func body(message: Message, privacy: NotificationContentVisibility) -> String {
        guard privacy == .showSenderAndContent else { return "Open Liquid Bagel to view this message." }
        var parts: [String] = []
        if let content = message.content {
            let sanitized = sanitize(content)
            if !sanitized.isEmpty { parts.append(sanitized) }
        }
        if let attachments = message.attachments, !attachments.isEmpty {
            let count = attachments.count
            parts.append(count == 1 ? "1 attachment" : "\(count) attachments")
        }
        return truncate(parts.isEmpty ? "New message" : parts.joined(separator: " - "), limit: 160)
    }

    public static func sanitize(_ value: String) -> String {
        var output = value
        let replacements = [
            (#"https?://\S+"#, "[redacted-url]"),
            (#"/(?:Users|tmp|var|private|Volumes)/[^\s,;\)]+"#, "[redacted-path]"),
            (#"(?i)(authorization|token|session|password|secret|auth)[\s:=]+"?[^"\s]+"?"#, "$1=[redacted]"),
            (#"<[^>]+>"#, "")
        ]
        for (pattern, replacement) in replacements {
            output = output.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        output = output.replacingOccurrences(of: #"[*_`~>#\(\)]"#, with: "", options: .regularExpression)
        output = output.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func truncate(_ value: String, limit: Int) -> String {
        guard value.count > limit else { return value }
        let index = value.index(value.startIndex, offsetBy: max(0, limit - 1))
        return String(value[..<index]) + "..."
    }
}

public enum NotificationClassifier {
    public static func classify(message: Message, context: NotificationClassificationContext) -> NotificationClassification {
        guard context.runtimeMode == .liveManual else { return .suppress(.mockRuntime) }
        guard let currentUserID = context.currentUserID else { return .suppress(.missingCurrentUser) }
        guard message.authorID != currentUserID else { return .suppress(.selfMessage) }
        guard !message.isSuppressed else { return .suppress(.messageSuppressed) }
        guard let channel = context.snapshot.channelsByID[message.channelID] else { return .suppress(.unknownChannel) }

        let channelPreference = context.preferences.preference(for: message.channelID)
        guard !channelPreference.isMuted else { return .suppress(.channelMuted) }
        if context.preferences.suppressActiveChannel,
           context.isActiveChannelVisible,
           context.activeChannelID == message.channelID {
            return .suppress(.activeChannel)
        }

        let isMention = (message.mentions ?? []).contains(currentUserID) || message.mentionsEveryone
        let isDirect = channel.kind == .directMessage || channel.kind == .group
        let kind: NotificationClassificationKind
        if isMention {
            kind = .mention
        } else if isDirect {
            kind = .directMessage
        } else if context.preferences.deliveryScope == .allMessages {
            kind = .unread
        } else {
            return .suppress(.deliveryScope)
        }

        let event = NotificationEvent(
            id: "message-\(message.id.rawValue)",
            route: NotificationRoute(serverID: channel.serverID, channelID: channel.id, messageID: message.id),
            title: NotificationContentFormatter.title(message: message, channel: channel, snapshot: context.snapshot, privacy: context.preferences.contentVisibility),
            body: NotificationContentFormatter.body(message: message, privacy: context.preferences.contentVisibility),
            kind: kind,
            createdAt: message.createdAt ?? Date()
        )
        return .deliver(event)
    }
}

public enum NotificationBadgeCalculator {
    public static func counts(snapshot: RealtimeSnapshot, preferences: NotificationPreferences, localReadStates: [ChannelID: LocalReadState] = [:]) -> NotificationBadgeCounts {
        var unreadChannels: Set<ChannelID> = []
        var mentions = 0
        for (channelID, unread) in snapshot.unreadsByChannelID {
            let channelPreference = preferences.preference(for: channelID)
            guard !channelPreference.isMuted else { continue }
            if unread.lastMessageID != nil {
                unreadChannels.insert(channelID)
            }
            mentions += unread.mentions.count
        }
        for (channelID, state) in localReadStates {
            let channelPreference = preferences.preference(for: channelID)
            guard !channelPreference.isMuted else { continue }
            if state.unreadCount > 0 {
                unreadChannels.insert(channelID)
            }
            if state.mentionCount > 0 {
                mentions += state.mentionCount
            }
        }
        return NotificationBadgeCounts(unreadChannelCount: unreadChannels.count, mentionCount: mentions)
    }
}

public struct NotificationDiagnostics: Hashable, Sendable {
    public var permissionStatus: NotificationPermissionStatus
    public var nativeEnabled: Bool
    public var inAppEnabled: Bool
    public var dockBadgeValue: Int
    public var deliveredCount: Int
    public var suppressedCount: Int
    public var lastSuppressionReason: NotificationSuppressionReason?
    public var lastEventKind: NotificationClassificationKind?
    public var lifecyclePhase: AppLifecyclePhase
    public var activeChannelVisible: Bool
    public var queuedRouteCount: Int
    public var expiredRouteCount: Int
    public var lastRouteOutcome: NotificationRouteOutcome

    public init(
        permissionStatus: NotificationPermissionStatus = .unknown,
        nativeEnabled: Bool = false,
        inAppEnabled: Bool = true,
        dockBadgeValue: Int = 0,
        deliveredCount: Int = 0,
        suppressedCount: Int = 0,
        lastSuppressionReason: NotificationSuppressionReason? = nil,
        lastEventKind: NotificationClassificationKind? = nil,
        lifecyclePhase: AppLifecyclePhase = .active,
        activeChannelVisible: Bool = true,
        queuedRouteCount: Int = 0,
        expiredRouteCount: Int = 0,
        lastRouteOutcome: NotificationRouteOutcome = .none
    ) {
        self.permissionStatus = permissionStatus
        self.nativeEnabled = nativeEnabled
        self.inAppEnabled = inAppEnabled
        self.dockBadgeValue = dockBadgeValue
        self.deliveredCount = deliveredCount
        self.suppressedCount = suppressedCount
        self.lastSuppressionReason = lastSuppressionReason
        self.lastEventKind = lastEventKind
        self.lifecyclePhase = lifecyclePhase
        self.activeChannelVisible = activeChannelVisible
        self.queuedRouteCount = queuedRouteCount
        self.expiredRouteCount = expiredRouteCount
        self.lastRouteOutcome = lastRouteOutcome
    }

    public var redactedText: String {
        let text = """
        Notification diagnostics
        permission: \(permissionStatus.rawValue)
        nativeEnabled: \(nativeEnabled)
        inAppEnabled: \(inAppEnabled)
        dockBadge: \(dockBadgeValue)
        delivered: \(deliveredCount)
        suppressed: \(suppressedCount)
        lastSuppression: \(lastSuppressionReason?.rawValue ?? "-")
        lastKind: \(lastEventKind?.rawValue ?? "-")
        lifecycle: \(lifecyclePhase.rawValue)
        activeChannelVisible: \(activeChannelVisible)
        queuedRoutes: \(queuedRouteCount)
        expiredRoutes: \(expiredRouteCount)
        lastRouteOutcome: \(lastRouteOutcome.rawValue)
        """
        return NotificationContentFormatter.sanitize(text)
    }
}

public protocol NotificationDelivering: Sendable {
    func deliver(_ event: NotificationEvent) async throws
}

public actor MockNotificationService: NotificationDelivering {
    public private(set) var deliveredEvents: [NotificationEvent] = []

    public init() {}

    public func deliver(_ event: NotificationEvent) async throws {
        deliveredEvents.append(event)
    }

    public func events() -> [NotificationEvent] {
        deliveredEvents
    }
}

public struct UserNotificationsNotificationService: NotificationDelivering {
    public init() {}

    public func deliver(_ event: NotificationEvent) async throws {
        #if canImport(UserNotifications)
        guard UserNotificationsAvailability.canUseCurrentCenter else { return }
        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = event.body
        content.sound = .default
        content.userInfo = event.route.userInfo
        let request = UNNotificationRequest(identifier: event.id, content: content, trigger: nil)
        try await UNUserNotificationCenter.current().add(request)
        #endif
    }
}

public protocol NotificationPermissionManaging: Sendable {
    func status() async -> NotificationPermissionStatus
    func requestAuthorization() async -> NotificationPermissionStatus
}

public struct UserNotificationsPermissionManager: NotificationPermissionManaging {
    public init() {}

    public func status() async -> NotificationPermissionStatus {
        #if canImport(UserNotifications)
        guard UserNotificationsAvailability.canUseCurrentCenter else { return .unknown }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return NotificationPermissionStatus(settings.authorizationStatus)
        #else
        return .unknown
        #endif
    }

    public func requestAuthorization() async -> NotificationPermissionStatus {
        #if canImport(UserNotifications)
        guard UserNotificationsAvailability.canUseCurrentCenter else { return .unknown }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        return await status()
        #else
        return .unknown
        #endif
    }
}

private enum UserNotificationsAvailability {
    static var canUseCurrentCenter: Bool {
        #if canImport(UserNotifications)
        !Bundle.main.bundleURL.path.contains("/Xcode.app/")
        #else
        false
        #endif
    }
}

public actor MockNotificationPermissionManager: NotificationPermissionManaging {
    public var currentStatus: NotificationPermissionStatus
    public private(set) var requestCount = 0

    public init(status: NotificationPermissionStatus = .notDetermined) {
        self.currentStatus = status
    }

    public func status() async -> NotificationPermissionStatus {
        currentStatus
    }

    public func requestAuthorization() async -> NotificationPermissionStatus {
        requestCount += 1
        if currentStatus == .notDetermined {
            currentStatus = .authorized
        }
        return currentStatus
    }
}

public protocol DockBadgeManaging: Sendable {
    func setBadgeCount(_ count: Int) async
}

public struct AppKitDockBadgeManager: DockBadgeManaging {
    public init() {}

    public func setBadgeCount(_ count: Int) async {
        #if canImport(AppKit)
        await MainActor.run {
            guard let app = NSApp else { return }
            app.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
        }
        #endif
    }
}

public actor MockDockBadgeManager: DockBadgeManaging {
    public private(set) var badgeCounts: [Int] = []

    public init() {}

    public func setBadgeCount(_ count: Int) async {
        badgeCounts.append(count)
    }
}

@MainActor
public final class NotificationRouteCenter {
    public static let shared = NotificationRouteCenter()

    private var handler: ((NotificationRoute) -> Void)?
    private var queuedRoutes: [QueuedNotificationRoute] = []
    private let routeExpirySeconds: TimeInterval

    public init(routeExpirySeconds: TimeInterval = 600) {
        self.routeExpirySeconds = routeExpirySeconds
    }

    public func setHandler(_ handler: @escaping (NotificationRoute) -> Void) {
        self.handler = handler
        let routes = drainQueuedRoutes()
        for queued in routes {
            handler(queued.route)
        }
    }

    public func open(_ route: NotificationRoute) {
        guard let handler else {
            queue(route)
            return
        }
        handler(route)
    }

    public func queue(_ route: NotificationRoute, queuedAt: Date = Date()) {
        let queued = QueuedNotificationRoute(route: route, queuedAt: queuedAt, expiresAfter: routeExpirySeconds)
        queuedRoutes.removeAll { $0.id == queued.id }
        queuedRoutes.append(queued)
        queuedRoutes = Array(queuedRoutes.suffix(10))
    }

    public func queuedRouteCount(at date: Date = Date()) -> Int {
        queuedRoutes.filter { !$0.isExpired(at: date) }.count
    }

    public func drainQueuedRoutes(at date: Date = Date()) -> [QueuedNotificationRoute] {
        let liveRoutes = queuedRoutes.filter { !$0.isExpired(at: date) }
        queuedRoutes.removeAll()
        return liveRoutes
    }

    public func clearExpiredRoutes(at date: Date = Date()) -> Int {
        let before = queuedRoutes.count
        queuedRoutes.removeAll { $0.isExpired(at: date) }
        return before - queuedRoutes.count
    }
}

@MainActor
public final class AppLifecycleCenter {
    public static let shared = AppLifecycleCenter()

    private var handler: ((AppLifecyclePhase) -> Void)?
    public private(set) var phase: AppLifecyclePhase = .active

    public init() {}

    public func setHandler(_ handler: @escaping (AppLifecyclePhase) -> Void) {
        self.handler = handler
        handler(phase)
    }

    public func update(_ phase: AppLifecyclePhase) {
        guard self.phase != phase else { return }
        self.phase = phase
        handler?(phase)
    }
}

#if canImport(UserNotifications)
extension NotificationPermissionStatus {
    public init(_ status: UNAuthorizationStatus) {
        switch status {
        case .notDetermined:
            self = .notDetermined
        case .denied:
            self = .denied
        case .authorized:
            self = .authorized
        case .provisional:
            self = .provisional
        case .ephemeral:
            self = .ephemeral
        @unknown default:
            self = .unknown
        }
    }
}
#endif
