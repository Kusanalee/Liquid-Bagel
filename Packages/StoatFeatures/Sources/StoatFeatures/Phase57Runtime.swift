import Foundation

public enum TransientAppNoticeSeverity: String, Hashable, Sendable {
    case warning
    case error

    public var defaultDuration: Duration {
        switch self {
        case .warning: .seconds(4)
        case .error: .seconds(8)
        }
    }

    public var systemImage: String {
        switch self {
        case .warning: "exclamationmark.triangle"
        case .error: "xmark.octagon"
        }
    }
}

public struct TransientAppNotice: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var message: String
    public var severity: TransientAppNoticeSeverity

    public init(
        id: UUID = UUID(),
        message: String,
        severity: TransientAppNoticeSeverity
    ) {
        self.id = id
        self.message = message
        self.severity = severity
    }
}

public enum TransientAppNoticePolicy {
    public static func severity(for status: String) -> TransientAppNoticeSeverity? {
        let normalized = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }

        let errorMarkers = [
            "failed",
            "error",
            "could not",
            "cannot",
            "can't",
            "unavailable",
            "not available"
        ]
        if errorMarkers.contains(where: normalized.contains) {
            return .error
        }

        let warningMarkers = [
            "reconnect",
            "select ",
            "requires ",
            "not loaded",
            "not found",
            "waiting for"
        ]
        if warningMarkers.contains(where: normalized.contains) {
            return .warning
        }
        return nil
    }
}
