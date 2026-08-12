import Foundation
import StoatAPI

public enum TransientAppNoticeSeverity: String, Hashable, Sendable {
    case success
    case info
    case warning
    case error

    public var defaultDuration: Duration {
        switch self {
        case .success: .seconds(2)
        case .info: .seconds(3)
        case .warning: .seconds(4)
        case .error: .seconds(8)
        }
    }

    public var systemImage: String {
        switch self {
        case .success: "checkmark.circle"
        case .info: "info.circle"
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
    /// Legacy fallback for status strings that have not been converted to typed notices yet.
    ///
    /// Inferring severity from substrings is guesswork and the long-term answer is
    /// `presentNotice(_:severity:)` with a severity the caller states outright. Until every
    /// call site is migrated this keeps them visible.
    ///
    /// Success markers exist because the original matcher only recognised failure, so every
    /// confirmation in the app -- "Attachment saved", "Message pinned", "Profile updated." --
    /// fell through to `nil` and was silently discarded.
    ///
    /// Unrecognised text still returns `nil`. That is deliberate: a lot of these strings are
    /// ambient state rather than events ("Waiting for realtime data"), and toasting all of them
    /// would trade invisible confirmations for constant interruption.
    public static func severity(for status: String) -> TransientAppNoticeSeverity? {
        let normalized = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }

        let errorMarkers = [
            "failed",
            "error",
            "could not",
            "couldn't",
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
            "waiting for",
            "offline"
        ]
        if warningMarkers.contains(where: normalized.contains) {
            return .warning
        }

        let successMarkers = [
            "copied",
            "saved",
            "sent",
            "updated",
            "opened",
            "pinned",
            "removed",
            "accepted",
            "denied",
            "blocked",
            "unblocked",
            "imported",
            "recorded",
            "delivered",
            "verified",
            "complete"
        ]
        if successMarkers.contains(where: normalized.contains) {
            return .success
        }
        return nil
    }
}

/// An error whose `errorDescription` is already written for a person and can be shown verbatim.
///
/// Conform only when the copy names something the user did or can fix, and contains no status
/// code, decoder path, diagnostic category, URL, or identifier.
public protocol UserPresentableError: LocalizedError {}

extension AttachmentValidationError: UserPresentableError {}

/// Turns any error into one short sentence a person can act on.
///
/// The rule: a user-facing message never contains an HTTP status code, a decoder path, an
/// internal diagnostic category, a URL, or an identifier. Those belong in the redacted
/// diagnostics behind Developer Options, and `StoatAPIError.errorDescription` -- which says
/// things like "Stoat returned server error 500: ..." -- is a diagnostic string, not user copy.
public enum UserFacingError {
    public static func message(for error: any Error, context: Context = .general) -> String {
        // Errors that already speak to the user keep their own words. Rewriting
        // "File too large. Liquid Bagel currently supports files up to 20 MB." into a generic
        // apology would be a downgrade, not a sanitisation.
        if let presentable = error as? any UserPresentableError,
           let description = presentable.errorDescription {
            return description
        }
        if let apiError = error as? StoatAPIError {
            return message(for: apiError, context: context)
        }
        if let urlError = error as? URLError {
            return message(for: urlError, context: context)
        }
        if let actionError = error as? MessageActionError {
            switch actionError {
            case let .unavailable(reason) where !reason.isEmpty:
                return reason
            default:
                return context.genericFailure
            }
        }
        return context.genericFailure
    }

    public static func message(for error: StoatAPIError, context: Context = .general) -> String {
        switch error {
        case .transport:
            return "You're offline. Check your connection and try again."
        case .unauthorized, .missingAuthentication:
            return "Your session expired. Sign in again."
        case .forbidden:
            return "You don't have permission to do that."
        case .notFound:
            return context.notFound
        case .rateLimited:
            return "Too many requests. Wait a moment and try again."
        case .serverError:
            // The status code and server body stay out of this deliberately.
            return "Stoat is having trouble right now. Try again in a moment."
        case .decodingFailed:
            return "Liquid Bagel couldn't understand Stoat's response."
        case .unknown:
            return "Stoat couldn't complete that request."
        case .invalidURL, .invalidEnvironment:
            return "This server address isn't valid."
        case .unimplementedEndpoint:
            return "Liquid Bagel doesn't support that yet."
        }
    }

    public static func message(for error: URLError, context: Context = .general) -> String {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return "You're offline. Check your connection and try again."
        case .timedOut:
            return "Stoat took too long to respond. Try again."
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return "Couldn't reach Stoat."
        case .cancelled:
            return context.cancelled
        default:
            return context.genericFailure
        }
    }

    /// Lets one error produce copy that fits where it appears. Everything here is a complete
    /// sentence; none of it interpolates server text.
    public enum Context: Hashable, Sendable {
        case general
        case sendMessage
        case attachment
        case members
        case search
        case signIn
        case voiceJoin

        var genericFailure: String {
            switch self {
            case .general: "Something went wrong. Try again."
            case .sendMessage: "Your message didn't send. Try again."
            case .attachment: "That attachment didn't upload. Try again."
            case .members: "Couldn't refresh members."
            case .search: "Search didn't work. Try again."
            case .signIn: "Couldn't sign in. Try again."
            case .voiceJoin: "Couldn't connect to the voice server. Try again."
            }
        }

        var notFound: String {
            switch self {
            case .general, .signIn, .voiceJoin: "That's no longer available."
            case .sendMessage: "This channel is no longer available."
            case .attachment: "That attachment is no longer available."
            case .members: "This server is no longer available."
            case .search: "This channel is no longer available."
            }
        }

        var cancelled: String {
            switch self {
            case .attachment: "Upload cancelled."
            default: "Cancelled."
            }
        }
    }
}
