import Foundation
import StoatAPI
import StoatModels
import StoatRealtime

public enum InvitePreviewState: Hashable, Sendable {
    case idle
    case parsing
    case loading(InviteCode)
    case loaded(InvitePreview)
    case failed(InviteCode?, String)
}

public enum DiscoverState: Hashable, Sendable {
    case webBacked
    case loading
    case failed(String)
}

public struct PendingInviteJoin: Identifiable, Hashable, Sendable {
    public var id: String { code.rawValue }
    public var code: InviteCode
    public var preview: InvitePreview

    public init(code: InviteCode, preview: InvitePreview) {
        self.code = code
        self.preview = preview
    }
}

public struct PendingInviteDeletion: Identifiable, Hashable, Sendable {
    public var id: String { code.rawValue }
    public var code: InviteCode

    public init(code: InviteCode) {
        self.code = code
    }
}

public enum ServerCreateState: Hashable, Sendable {
    case idle
    case creating
    case created(ServerID)
    case failed(String)
}

public enum InviteManagementState: Hashable, Sendable {
    case idle
    case loading
    case loaded([Invite])
    case failed(String)
}

public enum Phase23Safety {
    public static func safeError(_ error: any Error) -> String {
        if let apiError = error as? StoatAPIError {
            switch apiError {
            case .missingAuthentication, .unauthorized:
                return "Connect manually before using this action."
            case .forbidden:
                return "You do not have permission for that action."
            case .notFound:
                return "Invite or server was not found."
            case let .rateLimited(retryAfterMilliseconds):
                if let retryAfterMilliseconds {
                    return "Rate limited. Try again in \(max(1, retryAfterMilliseconds / 1000)) seconds."
                }
                return "Rate limited. Try again shortly."
            case .decodingFailed:
                return "Stoat returned an unsupported response."
            case .transport:
                return "Network request failed."
            case .unimplementedEndpoint:
                return "This route is not available in this build."
            case .invalidEnvironment:
                return "This environment is not ready for that action."
            case .serverError:
                return "Stoat is unavailable for that action."
            case .invalidURL, .unknown:
                return "Request failed."
            }
        }
        return MessageSendDiagnosticsFormatter.redact(error.userFacingMessage)
    }

    public static func redactedDiagnostics(_ value: String) -> String {
        MessageSendDiagnosticsFormatter.redact(value)
    }
}

public enum Phase23SnapshotIntegrator {
    public static func upserting(server: Server, channels: [Channel], into snapshot: RealtimeSnapshot) -> RealtimeSnapshot {
        var snapshot = snapshot
        var server = server
        let channelIDs = channels.map(\.id)
        if !channelIDs.isEmpty {
            server.channelIDs = orderedUnique(server.channelIDs + channelIDs)
        }
        snapshot.serversByID[server.id] = server
        for channel in channels {
            snapshot.channelsByID[channel.id] = channel
        }
        return snapshot
    }

    public static func selection(for server: Server, channels: [Channel], memberPanelVisible: Bool) -> ShellSelection {
        let firstText = channels.first { $0.kind == .textChannel } ?? channels.first
        return ShellSelection(space: .server(server.id), serverID: server.id, channelID: firstText?.id, isMemberPanelVisible: memberPanelVisible)
    }

    private static func orderedUnique<T: Hashable>(_ values: [T]) -> [T] {
        var seen = Set<T>()
        var output: [T] = []
        for value in values where seen.insert(value).inserted {
            output.append(value)
        }
        return output
    }
}
