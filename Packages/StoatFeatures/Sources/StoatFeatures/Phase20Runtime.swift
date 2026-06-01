import Foundation
import StoatModels

public enum MessageSendStage: String, Codable, Hashable, Sendable {
    case idle
    case validatingDraft
    case checkingRuntime
    case checkingPermissions
    case creatingOptimisticMessage
    case uploadingAttachments
    case buildingPayload
    case sendingRequest
    case decodingResponse
    case waitingForRealtimeEcho
    case reconciled
    case failed
}

public enum MessageSendResult: String, Codable, Hashable, Sendable {
    case none
    case pending
    case succeeded
    case failed
}

public struct MessageSendDiagnostics: Hashable, Sendable {
    public var selectedChannelID: ChannelID?
    public var runtimeMode: AppRuntimeMode
    public var sessionState: AppSessionState
    public var connectionStateDescription: String
    public var canSend: Bool
    public var disabledReason: String?
    public var lastSendAttemptAt: Date?
    public var lastSendStage: MessageSendStage?
    public var lastSendResult: MessageSendResult?
    public var lastError: String?

    public init(
        selectedChannelID: ChannelID? = nil,
        runtimeMode: AppRuntimeMode = .mock,
        sessionState: AppSessionState = .mock,
        connectionStateDescription: String = "idle",
        canSend: Bool = false,
        disabledReason: String? = nil,
        lastSendAttemptAt: Date? = nil,
        lastSendStage: MessageSendStage? = .idle,
        lastSendResult: MessageSendResult? = MessageSendResult.none,
        lastError: String? = nil
    ) {
        self.selectedChannelID = selectedChannelID
        self.runtimeMode = runtimeMode
        self.sessionState = sessionState
        self.connectionStateDescription = MessageSendDiagnosticsFormatter.redact(connectionStateDescription)
        self.canSend = canSend
        self.disabledReason = disabledReason.map(MessageSendDiagnosticsFormatter.redact)
        self.lastSendAttemptAt = lastSendAttemptAt
        self.lastSendStage = lastSendStage
        self.lastSendResult = lastSendResult
        self.lastError = lastError.map(MessageSendDiagnosticsFormatter.redact)
    }
}

public enum MessageSendDiagnosticsFormatter {
    public static func redactedText(_ diagnostics: MessageSendDiagnostics) -> String {
        redact(
            """
            Message send diagnostics
            channel: \(shortID(diagnostics.selectedChannelID?.rawValue))
            runtime: \(diagnostics.runtimeMode)
            session: \(diagnostics.sessionState)
            connection: \(diagnostics.connectionStateDescription)
            canSend: \(diagnostics.canSend)
            disabled: \(diagnostics.disabledReason ?? "-")
            lastAttempt: \(diagnostics.lastSendAttemptAt?.formatted(date: .numeric, time: .standard) ?? "-")
            stage: \(diagnostics.lastSendStage?.rawValue ?? "-")
            result: \(diagnostics.lastSendResult?.rawValue ?? "-")
            error: \(diagnostics.lastError ?? "-")
            """
        )
    }

    public static func redact(_ value: String) -> String {
        var output = value
        let patterns = [
            "[A-Za-z0-9_-]{24,}\\.[A-Za-z0-9_-]{24,}\\.[A-Za-z0-9_-]{12,}",
            "(?i)(x-session-token|x-bot-token|session|bot|token|authorization)[=: ]+[A-Za-z0-9._-]+",
            #"(?i)(x-session-token|x-bot-token|session|bot|token|authorization)[=: ]+"[^"]*""#,
            #"https?://[^\s]+"#,
            #"file://[^\s,]+"#,
            #"(/[A-Za-z0-9._ -]+){2,}"#,
            #"\{[^}]*\}"#
        ]
        for pattern in patterns {
            output = output.replacingOccurrences(of: pattern, with: "<redacted>", options: .regularExpression)
        }
        return output
    }

    public static func shortID(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "-" }
        guard value.count > 12 else { return value }
        return "\(value.prefix(6))...\(value.suffix(4))"
    }
}
