import Foundation
import StoatModels

public struct ModerationDiagnostics: Hashable, Sendable {
    public var lastActionCategory: String
    public var selectedServerPresenceCategory: String
    public var targetCategory: String
    public var permissionResultCategory: String
    public var routeCategory: String
    public var requestResultCategory: String
    public var responseShapeCategory: String
    public var safeErrorCategory: String
    public var durationBucket: String
    public var memberCacheMutationCategory: String
    public var bansKnownCount: Int
    public var bansRenderedCount: Int
    public var bansPendingCount: Int
    public var timeoutsKnownCount: Int
    public var timeoutsRenderedCount: Int
    public var timeoutsPendingCount: Int
    public var elapsedDurationBucket: String
    public var copiedDiagnosticsRedactedReasonText: Bool
    public var targetIDPrefix: String
    public var serverIDPrefix: String

    public init(
        lastActionCategory: String = "none",
        selectedServerPresenceCategory: String = "none",
        targetCategory: String = "unknown",
        permissionResultCategory: String = "unknown",
        routeCategory: String = "none",
        requestResultCategory: String = "idle",
        responseShapeCategory: String = "none",
        safeErrorCategory: String = "none",
        durationBucket: String = "none",
        memberCacheMutationCategory: String = "none",
        bansKnownCount: Int = 0,
        bansRenderedCount: Int = 0,
        bansPendingCount: Int = 0,
        timeoutsKnownCount: Int = 0,
        timeoutsRenderedCount: Int = 0,
        timeoutsPendingCount: Int = 0,
        elapsedDurationBucket: String = "none",
        copiedDiagnosticsRedactedReasonText: Bool = true,
        targetIDPrefix: String = "-",
        serverIDPrefix: String = "-"
    ) {
        self.lastActionCategory = lastActionCategory
        self.selectedServerPresenceCategory = selectedServerPresenceCategory
        self.targetCategory = targetCategory
        self.permissionResultCategory = permissionResultCategory
        self.routeCategory = routeCategory
        self.requestResultCategory = requestResultCategory
        self.responseShapeCategory = responseShapeCategory
        self.safeErrorCategory = safeErrorCategory
        self.durationBucket = durationBucket
        self.memberCacheMutationCategory = memberCacheMutationCategory
        self.bansKnownCount = bansKnownCount
        self.bansRenderedCount = bansRenderedCount
        self.bansPendingCount = bansPendingCount
        self.timeoutsKnownCount = timeoutsKnownCount
        self.timeoutsRenderedCount = timeoutsRenderedCount
        self.timeoutsPendingCount = timeoutsPendingCount
        self.elapsedDurationBucket = elapsedDurationBucket
        self.copiedDiagnosticsRedactedReasonText = copiedDiagnosticsRedactedReasonText
        self.targetIDPrefix = targetIDPrefix
        self.serverIDPrefix = serverIDPrefix
    }
}

public enum ModerationDiagnosticsFormatter {
    public static func redactedText(_ diagnostics: ModerationDiagnostics) -> String {
        let text = """
        Phase 42 Moderation Diagnostics
        lastAction: \(diagnostics.lastActionCategory)
        selectedServer: \(diagnostics.selectedServerPresenceCategory)
        server: \(diagnostics.serverIDPrefix)
        target: \(diagnostics.targetCategory) \(diagnostics.targetIDPrefix)
        permission: \(diagnostics.permissionResultCategory)
        route: \(diagnostics.routeCategory)
        request: \(diagnostics.requestResultCategory)
        responseShape: \(diagnostics.responseShapeCategory)
        safeError: \(diagnostics.safeErrorCategory)
        timeoutDuration: \(diagnostics.durationBucket)
        memberCacheMutation: \(diagnostics.memberCacheMutationCategory)
        bans: known \(diagnostics.bansKnownCount), rendered \(diagnostics.bansRenderedCount), pending \(diagnostics.bansPendingCount)
        timeouts: known \(diagnostics.timeoutsKnownCount), rendered \(diagnostics.timeoutsRenderedCount), pending \(diagnostics.timeoutsPendingCount)
        elapsed: \(diagnostics.elapsedDurationBucket)
        reasonRedacted: \(diagnostics.copiedDiagnosticsRedactedReasonText ? "yes" : "no")
        """
        return redactModerationOnly(
            Phase17MessageActions.redactedDiagnosticText(
                Phase6UIHelpers.safeDiagnostics(
                    TimelineCopyFormatter.redactTokenLikeStrings(text)
                )
            )
        )
    }

    public static func shortID(_ value: String?) -> String {
        TimelineCopyFormatter.shortID(value)
    }

    public static func elapsedBucket(_ interval: TimeInterval) -> String {
        switch interval {
        case ..<0.25: "under250ms"
        case ..<1: "under1s"
        case ..<3: "under3s"
        case ..<10: "under10s"
        default: "slow"
        }
    }

    private static func redactModerationOnly(_ value: String) -> String {
        var output = value
        output = replace(output, pattern: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, with: "[redacted-email]", options: [.caseInsensitive])
        output = replace(output, pattern: #"\b[A-Za-z0-9]{20,}\b"#, with: "[redacted-id]")
        return output
    }

    private static func replace(_ value: String, pattern: String, with replacement: String, options: NSRegularExpression.Options = []) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return value }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.stringByReplacingMatches(in: value, range: range, withTemplate: replacement)
    }
}
