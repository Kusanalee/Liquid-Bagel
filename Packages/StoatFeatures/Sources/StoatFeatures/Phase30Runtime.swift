import Foundation
import StoatModels
import StoatRealtime

public enum ActiveConversation: Hashable, Sendable {
    case none
    case serverChannel(serverID: ServerID, channelID: ChannelID)
    case directMessage(channelID: ChannelID)
    case groupDM(channelID: ChannelID)
    case savedMessages(channelID: ChannelID)

    public var channelID: ChannelID? {
        switch self {
        case .none:
            nil
        case let .serverChannel(_, channelID),
             let .directMessage(channelID),
             let .groupDM(channelID),
             let .savedMessages(channelID):
            channelID
        }
    }

    public var serverID: ServerID? {
        if case let .serverChannel(serverID, _) = self { return serverID }
        return nil
    }

    public var routeDescription: String {
        switch self {
        case .none:
            "none"
        case let .serverChannel(serverID, channelID):
            "server \(serverID.rawValue) channel \(channelID.rawValue)"
        case let .directMessage(channelID):
            "directMessage \(channelID.rawValue)"
        case let .groupDM(channelID):
            "groupDM \(channelID.rawValue)"
        case let .savedMessages(channelID):
            "savedMessages \(channelID.rawValue)"
        }
    }

    public static func resolve(selection: ShellSelection, snapshot: RealtimeSnapshot) -> ActiveConversation {
        switch selection.space {
        case .server:
            guard let channelID = selection.channelID,
                  let channel = snapshot.channelsByID[channelID],
                  let serverID = channel.serverID ?? selection.serverID
            else { return .none }
            return .serverChannel(serverID: serverID, channelID: channelID)
        case .directMessages:
            guard let channelID = selection.dmChannelID,
                  let channel = snapshot.channelsByID[channelID],
                  DMChannelClassifier.isDirectMessageLike(channel)
            else { return .none }
            switch channel.kind {
            case .directMessage:
                return .directMessage(channelID: channelID)
            case .group:
                return .groupDM(channelID: channelID)
            case .savedMessages:
                return .savedMessages(channelID: channelID)
            default:
                return .none
            }
        case .home, .discover:
            return .none
        }
    }
}

public struct DirectMessageLiveTrace: Hashable, Sendable {
    public var clickedRowID: String
    public var clickedChannelID: ChannelID?
    public var clickedUserID: UserID?
    public var clickedChannelKind: String?
    public var clickedChannelExistsInSnapshot: Bool
    public var selectedSpaceBefore: String
    public var selectedSpaceAfter: String
    public var selectedServerIDBefore: ServerID?
    public var selectedServerIDAfter: ServerID?
    public var selectedChannelIDBefore: ChannelID?
    public var selectedChannelIDAfter: ChannelID?
    public var selectedConversationChannelID: ChannelID?
    public var messageLoadRequested: Bool
    public var messageLoadChannelID: ChannelID?
    public var messageLoadUsedREST: Bool
    public var messageLoadResult: String?
    public var timelineChannelID: ChannelID?
    public var timelineMessageCount: Int
    public var composerTargetChannelID: ChannelID?
    public var sidebarParticipantCount: Int
    public var lastError: String?

    public init(
        clickedRowID: String = "-",
        clickedChannelID: ChannelID? = nil,
        clickedUserID: UserID? = nil,
        clickedChannelKind: String? = nil,
        clickedChannelExistsInSnapshot: Bool = false,
        selectedSpaceBefore: String = "-",
        selectedSpaceAfter: String = "-",
        selectedServerIDBefore: ServerID? = nil,
        selectedServerIDAfter: ServerID? = nil,
        selectedChannelIDBefore: ChannelID? = nil,
        selectedChannelIDAfter: ChannelID? = nil,
        selectedConversationChannelID: ChannelID? = nil,
        messageLoadRequested: Bool = false,
        messageLoadChannelID: ChannelID? = nil,
        messageLoadUsedREST: Bool = false,
        messageLoadResult: String? = nil,
        timelineChannelID: ChannelID? = nil,
        timelineMessageCount: Int = 0,
        composerTargetChannelID: ChannelID? = nil,
        sidebarParticipantCount: Int = 0,
        lastError: String? = nil
    ) {
        self.clickedRowID = clickedRowID
        self.clickedChannelID = clickedChannelID
        self.clickedUserID = clickedUserID
        self.clickedChannelKind = clickedChannelKind
        self.clickedChannelExistsInSnapshot = clickedChannelExistsInSnapshot
        self.selectedSpaceBefore = selectedSpaceBefore
        self.selectedSpaceAfter = selectedSpaceAfter
        self.selectedServerIDBefore = selectedServerIDBefore
        self.selectedServerIDAfter = selectedServerIDAfter
        self.selectedChannelIDBefore = selectedChannelIDBefore
        self.selectedChannelIDAfter = selectedChannelIDAfter
        self.selectedConversationChannelID = selectedConversationChannelID
        self.messageLoadRequested = messageLoadRequested
        self.messageLoadChannelID = messageLoadChannelID
        self.messageLoadUsedREST = messageLoadUsedREST
        self.messageLoadResult = messageLoadResult
        self.timelineChannelID = timelineChannelID
        self.timelineMessageCount = timelineMessageCount
        self.composerTargetChannelID = composerTargetChannelID
        self.sidebarParticipantCount = sidebarParticipantCount
        self.lastError = lastError
    }
}

public enum DirectMessageLiveTraceFormatter {
    public static func redactedText(_ trace: DirectMessageLiveTrace) -> String {
        let text = """
        DM live trace
        clickedRowID: \(short(trace.clickedRowID))
        clickedChannelID: \(short(trace.clickedChannelID?.rawValue))
        clickedUserID: \(short(trace.clickedUserID?.rawValue))
        clickedChannelKind: \(trace.clickedChannelKind ?? "-")
        clickedChannelExistsInSnapshot: \(trace.clickedChannelExistsInSnapshot ? "yes" : "no")
        selectedSpaceBefore: \(trace.selectedSpaceBefore)
        selectedSpaceAfter: \(trace.selectedSpaceAfter)
        selectedServerIDBefore: \(short(trace.selectedServerIDBefore?.rawValue))
        selectedServerIDAfter: \(short(trace.selectedServerIDAfter?.rawValue))
        selectedChannelIDBefore: \(short(trace.selectedChannelIDBefore?.rawValue))
        selectedChannelIDAfter: \(short(trace.selectedChannelIDAfter?.rawValue))
        selectedConversationChannelID: \(short(trace.selectedConversationChannelID?.rawValue))
        messageLoadRequested: \(trace.messageLoadRequested ? "yes" : "no")
        messageLoadChannelID: \(short(trace.messageLoadChannelID?.rawValue))
        messageLoadUsedREST: \(trace.messageLoadUsedREST ? "yes" : "no")
        messageLoadResult: \(trace.messageLoadResult ?? "-")
        timelineChannelID: \(short(trace.timelineChannelID?.rawValue))
        timelineMessageCount: \(trace.timelineMessageCount)
        composerTargetChannelID: \(short(trace.composerTargetChannelID?.rawValue))
        sidebarParticipantCount: \(trace.sidebarParticipantCount)
        lastError: \(trace.lastError ?? "-")
        """
        return redactRawPayloads(Phase17MessageActions.redactedDiagnosticText(
            Phase6UIHelpers.safeDiagnostics(
                AttachmentDiagnosticsFormatter.redact(text)
            )
        ))
    }

    private static func short(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "-" }
        return TimelineCopyFormatter.shortID(value)
    }

    private static func redactRawPayloads(_ value: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\{[^\n]*\}"#) else { return value }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.stringByReplacingMatches(in: value, range: range, withTemplate: "[redacted-payload]")
    }
}

public enum ParityStatus: String, Codable, Hashable, Sendable, CaseIterable {
    case done
    case partial
    case broken
    case blockedByUnverifiedAPI
    case deferred
    case outOfScope
}

public struct ParityItem: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var section: String
    public var name: String
    public var status: ParityStatus
    public var sourceOfTruth: String
    public var currentImplementation: String
    public var knownGaps: String
    public var tests: String
    public var manualQA: String
    public var recommendedNextAction: String

    public init(
        section: String,
        name: String,
        status: ParityStatus,
        sourceOfTruth: String,
        currentImplementation: String,
        knownGaps: String,
        tests: String,
        manualQA: String,
        recommendedNextAction: String
    ) {
        self.id = "\(section)-\(name)".lowercased().replacingOccurrences(of: " ", with: "-")
        self.section = section
        self.name = name
        self.status = status
        self.sourceOfTruth = sourceOfTruth
        self.currentImplementation = currentImplementation
        self.knownGaps = knownGaps
        self.tests = tests
        self.manualQA = manualQA
        self.recommendedNextAction = recommendedNextAction
    }
}

public struct ParityMatrix: Hashable, Sendable {
    public var items: [ParityItem]

    public init(items: [ParityItem]) {
        self.items = items
    }

    public var sections: [String] {
        var seen: Set<String> = []
        return items.compactMap { item in
            guard !seen.contains(item.section) else { return nil }
            seen.insert(item.section)
            return item.section
        }
    }

    public func items(in section: String) -> [ParityItem] {
        items.filter { $0.section == section }
    }

    public func count(_ status: ParityStatus) -> Int {
        items.filter { $0.status == status }.count
    }
}

public enum ParityMatrixFormatter {
    public static func redactedText(_ matrix: ParityMatrix) -> String {
        var lines = ["Official client parity matrix"]
        for section in matrix.sections {
            lines.append("")
            lines.append(section)
            for item in matrix.items(in: section) {
                lines.append("- \(item.name): \(item.status.rawValue); gaps: \(item.knownGaps); next: \(item.recommendedNextAction)")
            }
        }
        return Phase17MessageActions.redactedDiagnosticText(
            Phase6UIHelpers.safeDiagnostics(
                AttachmentDiagnosticsFormatter.redact(lines.joined(separator: "\n"))
            )
        )
    }
}

public enum Phase30ParityMatrixBuilder {
    public static func build() -> ParityMatrix {
        let specs: [(String, String, ParityStatus, String, String, String, String, String, String)] = [
            ("Account and session", "login", .partial, "Verified API/client behavior", "Phase 39 email/password login validates, saves the scoped credential, and starts live connection", "Live production credential QA remains pending", "Phase 38/39 login tests", "Run Phase 49 login checklist", "Phase 49 live audit"),
            ("Account and session", "MFA", .partial, "Official client", "Validation failure states exist", "Full MFA login flow is not implemented", "Session validation tests", "Test with MFA account when available", "Phase 31 research"),
            ("Account and session", "token/session import", .partial, "Existing app behavior", "Token import validates, saves to the selected environment scope, and connects", "Live token-import QA remains pending", "Phase 39 token import tests", "Run Phase 49 token import checklist", "Phase 49 live audit"),
            ("Account and session", "live-default startup", .partial, "Phase 32/38/39 runtime", "Shared AppSessionCoordinator performs idempotent saved-credential auto-connect", "Live relaunch and recovery dogfood remains pending", "Phase 38/39 startup tests", "Run Phase 49 startup checklist", "Phase 49 live audit"),
            ("Account and session", "session list", .partial, "Verified session routes", "Account settings has session surface", "Full official-client parity needs more QA", "Session endpoint tests", "Open sessions view", "Audit in Phase 31"),
            ("Account and session", "revoke sessions", .partial, "Verified session routes", "Logout/revoke support is present", "Bulk/session-list parity not fully audited", "Auth endpoint tests", "Revoke a test session", "Audit in Phase 31"),
            ("Account and session", "logout", .done, "Verified auth route", "Explicit logout/disconnect behavior", "None critical", "Auth endpoint tests", "Logout manually", "Keep stable"),
            ("Account and session", "account profile view", .partial, "Verified profile route", "Profile popovers and fetch-on-click", "No hidden fetch storm by design", "Profile mock tests", "Open profile explicitly", "Keep explicit"),
            ("Account and session", "account profile edit", .partial, "Verified PATCH /users/{currentUserID}", "Phase 41 editor patches display name and profile content with source-verified fields", "Source/mock verified only; live edit propagation QA pending", "Phase 41 model/API/feature tests", "Run Phase 41 profile checklist", "Live QA before done"),
            ("Account and session", "avatar edit", .partial, "Verified avatar upload tag and user edit route", "Phase 41 uploads image to avatars then patches avatar file ID", "Source/mock verified only; live avatar propagation QA pending", "Phase 41 upload/edit/cache tests", "Upload and remove avatar live", "Live QA before done"),
            ("Account and session", "profile banner/background edit", .partial, "Verified backgrounds upload tag and user edit route", "Phase 41 uploads image to backgrounds then patches profile.background file ID", "Source/mock verified only; live banner propagation QA pending", "Phase 41 upload/edit/cache tests", "Upload and remove banner live", "Live QA before done"),
            ("Account and session", "status/custom status", .partial, "Ready/User settings, verified user edit route", "Presence menu plus Phase 55 custom status text editor with set/clear", "Live status and custom-text visibility QA pending", "Phase 36/55 status tests", "Inspect user status from a second account", "Phase 55 live audit"),
            ("Account and session", "user settings sync", .partial, "Verified /sync/settings routes", "Phase 55 explicit fetch/push of allowlisted preferences under a namespaced key", "Live cross-device QA and official-client key interpretation pending", "Persistence and Phase 55 sync tests", "Fetch and push from two devices", "Phase 55 live audit"),

            ("Core chat", "server text channels", .partial, "Ready channels and channel messages", "Phase 56 provides immediate paint; Phase 57 adds full-width row interaction", "Switching passed; action hit-target and avatar continuity need re-test", "Message load/send plus Phase 56/57 tests", "Right-click rows and send repeatedly", "Phase 57 live re-test"),
            ("Core chat", "DMs", .partial, "Ready channels, users/dms, users/{target}/dm", "Phase 40 explicit DM refresh/open merge, stable Home rows, shared timeline pipeline, notification routing, and redacted diagnostics", "Live QA has not proven list/load/send/attachments/participants", "Phase 31/32/40 DM regression tests", "Run Phase 40 live DM checklist", "Live QA before done"),
            ("Core chat", "group DMs", .partial, "Ready channel kind Group, verified POST /channels/create", "Selection/load/sidebar supported plus Phase 55 New Group creation flow", "Live creation/load/send QA pending; member add/remove deferred", "Group DM tests, Phase 55 create tests", "Create a group with a friend account", "Phase 55 live audit"),
            ("Core chat", "friends and relationships", .partial, "Verified friend/block routes, Ready users with relations", "Friends tabs with request/accept/deny/remove and block/unblock actions", "Live two-account request/accept/block QA pending", "Phase 22 relationship tests", "Exchange requests between two accounts", "Live QA before done"),
            ("Core chat", "saved messages", .partial, "Ready channel kind SavedMessages", "Selection/load supported when modeled", "Live availability needs QA", "Saved selection tests", "Click Saved Messages if present", "Live QA"),
            ("Core chat", "send/edit/delete messages", .partial, "Verified channel message routes", "Send/edit/delete, immediate timeline paint, Phase 57 full-width actions, and Phase 60 incoming repeated-send pass", "Edit/delete and action variety still need broader live confirmation", "Message action plus Phase 56/57/60 tests", "Reconfirm send while scrolling, then edit/delete", "Phase 60 regression repeat"),
            ("Core chat", "replies", .partial, "Message schema", "Reply composer context exists", "Deep parity needs more QA", "Reply tests", "Reply to loaded message", "Polish later"),
            ("Core chat", "pins", .partial, "Verified pin routes", "Pin actions/search exist", "Full pinned UX parity incomplete", "Pin route tests", "Open pinned search", "Phase 31 polish"),
            ("Core chat", "reactions", .partial, "Verified reaction routes", "Phase 59 optimistic behavior plus Phase 60 single-encoded percentEncodedPath requests", "Pre-fix Unicode HTTP 400; post-fix add/remove/echo/reload and later custom/cross-account QA pending", "Reaction plus Phase 59/60 tests", "Add/remove Unicode reaction, wait for echo, and reload", "Phase 60 live repeat"),
            ("Core chat", "emoji picker", .partial, "Native Unicode input, Ready emojis", "Phase 68 keeps grouped picker sections metadata-only and resolves visible custom artwork per cell", "Live artwork/search/insertion and official autocomplete comparison remain pending", "Phase 32-35, 47, 65, and 68 emoji tests", "Run Phase 68 picker checklist", "Phase 68 live audit"),
            ("Core chat", "custom emoji", .partial, "Ready emojis", "Phase 68 shares one catalog-revision index across reactions, inline tokens, visible-row loads, and composer metadata", "Sent rendering/reaction media need live proof; cross-server and animated scope remain conservative", "Model/realtime plus Phase 65/68 tests", "Inspect and send in an emoji-heavy server", "Phase 68 live audit"),
            ("Core chat", "markdown", .partial, "Message content", "Markdown rendering exists", "Full official rendering parity incomplete", "Render tests", "Open markdown messages", "Polish later"),
            ("Core chat", "embeds", .partial, "Message schema", "Embed rendering exists", "All embed variants not audited", "Render tests", "Open embeds", "Audit variants"),
            ("Core chat", "attachments", .partial, "Verified upload/send/media routes", "Explicit upload/preview/download/open plus bounded transient retry", "Intermittent live recovery needs confirmation", "Attachment and Phase 56 retry tests", "Exercise timeout/rate-limit recovery", "Phase 56 live re-test"),
            ("Core chat", "image preview", .done, "Autumn media routes", "Inline previews and explicit viewer", "Memory-only cache", "Media tests", "Preview image", "Keep bounded"),
            ("Core chat", "drag/drop upload", .done, "Composer attachment flow", "Drop targets active conversation", "No auto-upload until send", "Attachment tests", "Drop file", "Keep stable"),
            ("Core chat", "clipboard paste upload", .done, "macOS pasteboard, composer flow", "Phase 61 queues pasted screenshot/Finder media as visible composer chips, preserves empty/non-empty draft text, and waits for Send before upload; the corrected path passed live macOS QA", "Explicit drag/drop review remains a separate intentional flow", "Phase 33/61 paste tests", "Passed with image/file and empty/non-empty drafts", "Keep stable"),
            ("Core chat", "upload size limit", .done, "Local attachment validation", "Shared 20 MB limit rejects oversized files before upload", "None critical", "Phase 33 boundary tests", "Try a file larger than 20 MB", "Keep stable"),
            ("Core chat", "read ack/unreads", .partial, "Ack route and Ready unreads", "Channel ID ack and local clear", "Live DM ack needs Phase 30 QA", "Ack tests", "Read a DM/server channel", "Monitor diagnostics"),
            ("Core chat", "typing indicators", .partial, "Realtime typing events", "Typing send/end helpers exist", "Full display parity incomplete", "Typing tests", "Type in channel", "Polish later"),
            ("Core chat", "search", .partial, "Verified search routes", "Loaded/live/pinned search exists", "Global search parity incomplete", "Search tests", "Search selected channel", "Phase 31"),
            ("Core chat", "jump to message", .partial, "Message fetch/search routes", "Loaded and around-message behavior exists", "Cross-context route QA needed", "Timeline tests", "Jump from search", "Polish later"),
            ("Core chat", "system events", .partial, "Message system schema", "Safe names and fallbacks with resolvable clickable actors", "Live event payload variety remains pending", "System and Phase 33/35 tests", "Open an event channel", "Live event QA"),
            ("Core chat", "user/avatar hydration", .partial, "Ready/member REST/message/profile data", "Phase 59 visible-first bounded off-main loading; Phase 60 incoming cached/uncached avatar pass", "Broader identity propagation and two-account coverage pending", "Resolver plus Phase 57/59 tests", "Keep avatars green during Phase 60 repeat", "Keep partial for propagation QA"),
            ("Core chat", "mentions", .partial, "Verified backend content-token parser (Docs/Research.md Phase 58 Notes)", "Phase 58 renders resolved user/channel/role mention pills with self-mention row accent and adds composer @ autocomplete inserting the verified <@ULID> token", "Live mention render/insert/click-to-profile QA pending; channel/role mentions render but have no composer autocomplete", "Phase 58 tokenizer, pipeline, and autocomplete tests", "Send/receive mentions and try composer @ autocomplete", "Phase 58 live audit"),

            ("Server/community", "server list", .done, "Ready servers", "Server rail from Ready", "No REST list by design", "Selection tests", "Connect manually", "Keep Ready source"),
            ("Server/community", "server icons", .done, "Ready media files", "Bounded in-memory loading", "No persistent cache by design", "Media tests", "Open server", "Keep bounded"),
            ("Server/community", "server banners", .done, "Ready media files", "Server banner rendering/settings", "Live QA recommended", "Media tests", "Open server settings", "Keep bounded"),
            ("Server/community", "create server", .partial, "Verified route from Phase 23", "Explicit create flow", "Needs parity QA", "Create tests", "Create test server only if safe", "Audit later"),
            ("Server/community", "join invite", .partial, "Verified invite route", "Preview/join flow exists", "Native deep-link parity incomplete", "Invite tests", "Join test invite", "Audit later"),
            ("Server/community", "Discover", .partial, "Web-backed public surface", "Browser handoff", "No verified native listing route", "Discover tests", "Open in browser", "Keep web handoff"),
            ("Server/community", "invite create/list/revoke", .partial, "Verified invite routes", "Manage invites flow exists", "Full parity QA pending", "Invite tests", "Manage invites", "Audit later"),
            ("Server/community", "channel create/edit/delete", .partial, "Verified channel routes", "Create/edit/delete text channels", "Destructive/permission edge QA pending", "Management tests", "Manage test channel", "Audit later"),
            ("Server/community", "categories", .partial, "Server edit categories", "Category editor exists", "Reorder/move parity not complete", "Category tests", "Edit categories", "Polish later"),
            ("Server/community", "server emoji management", .partial, "Verified emoji upload/create/list/delete routes", "Phase 53 provides prepared refresh, create, and confirmed delete flows", "Live permission, persistence, and error-path QA remains pending", "Phase 53 model/API/feature tests", "Manage emoji in a safe owned server", "Phase 54 live audit"),
            ("Server/community", "roles", .partial, "Verified role routes", "Role overview/create/edit/delete", "Rank/perms parity incomplete", "Role tests", "Open roles", "Polish later"),
            ("Server/community", "role assignment", .partial, "Verified member edit", "Confirmed role assignment", "Rank edge QA pending", "Member tests", "Assign test role", "Audit later"),
            ("Server/community", "permissions preview", .done, "Backend permission model", "Read-only resolver", "Write parity separate", "Permission resolver tests", "Open preview", "Keep stable"),
            ("Server/community", "permission editing", .partial, "Verified permission routes", "Guarded writes exist", "Full official UX parity incomplete", "Permission tests", "Edit test permission", "Audit later"),
            ("Server/community", "member list", .partial, "Ready members/users and verified member refresh", "Phase 69 publishes late identities to the selected server so fallback rows rebuild in place", "Three cold-launch correctness passes and role-rank dogfood remain pending", "Member, Phase 56 overlay, and Phase 69 observation tests", "Open the large panel immediately and let identities settle", "Phase 69 live re-test"),
            ("Server/community", "member moderation", .partial, "Verified moderation routes", "Phase 42 central resolver, cached menu availability, confirmations, member/profile/settings/dashboard entry points", "Live hierarchy and destructive-action QA pending", "Moderation tests, menu cache regression tests", "Use test server only", "Run Phase 42 checklist"),
            ("Server/community", "bans/timeouts", .partial, "Verified moderation routes", "Phase 42 ban management plus member-state active timeout management", "Live QA pending; no separate verified timeout-list route", "Moderation tests", "Use test server only", "Run Phase 42 checklist"),

            ("Notifications", "local notifications", .partial, "UserNotifications", "Signed single-account authorization and delivery passed live QA", "Two-account message/mention/DM variety remains unavailable", "Notification and signature tests", "Re-test with second account when available", "Keep partial for remaining variety"),
            ("Notifications", "in-app banners", .done, "Local classifier", "In-app delivery exists", "None critical", "Notification tests", "Receive message", "Keep stable"),
            ("Notifications", "privacy mode", .done, "Notification preferences", "Private content supported", "None critical", "Preference tests", "Toggle privacy", "Keep stable"),
            ("Notifications", "dock badge", .done, "Local unread counts", "Badge manager wired", "None critical", "Badge tests", "Observe dock badge", "Keep stable"),
            ("Notifications", "route on click", .partial, "Notification route center", "Queued until manual connect", "Live route QA pending", "Route tests", "Click notification", "Audit later"),
            ("Notifications", "mutes", .partial, "Notification preferences", "Per-channel suppression exists", "Server-wide mute parity incomplete", "Preference tests", "Mute channel", "Polish later"),
            ("Notifications", "active-channel suppression", .partial, "Classifier active channel", "Uses active conversation", "Phase 30 DM live QA required", "Suppression tests", "Receive active DM", "Monitor trace"),

            ("UI/platform", "keyboard shortcuts", .partial, "App commands", "Many commands wired", "Official shortcut parity incomplete", "Command tests", "Use shortcuts", "Audit later"),
            ("UI/platform", "command palette", .done, "Quick switcher", "Routes and commands indexed", "None critical", "Quick switcher tests", "Open palette", "Keep stable"),
            ("UI/platform", "accessibility", .partial, "SwiftUI accessibility labels", "Core labels exist", "Full VoiceOver audit pending", "UI tests", "Manual VO pass", "Phase 31"),
            ("UI/platform", "high contrast", .partial, "SwiftUI environment", "Previews planned", "Manual QA pending", "Preview coverage", "Enable high contrast", "Phase 31"),
            ("UI/platform", "reduce transparency", .partial, "Local preference", "Reduce glass intensity exists", "System reduce-transparency audit pending", "Preference tests", "Toggle setting", "Polish later"),
            ("UI/platform", "performance with large channels", .partial, "Lazy timeline and bounded media", "Phase 68 coalesces identity diagnostics and replaces row-local full emoji-catalog scans with one revision-keyed index", "The healthier Release trace needs a repaired-build repeat proving hotspots stay absent", "Phase 60-68 performance and invalidation tests", "Repeat the Phase 68 Release capture and confirm CPU settles below 10%", "Phase 68 live repeat"),
            ("UI/platform", "performance with large servers", .partial, "Lazy member list and selected-server hydration", "Phase 68 server-scopes invalidation; Phase 69 publishes only selected-server identity changes", "Three cold-launch identity-settling passes and stable counters remain pending", "Member perf, Phase 59 shell, Phase 68 token, and Phase 69 observation tests", "Repeat the affected cold launch and verify only selected-server regrouping", "Phase 69 live re-test"),
            ("UI/platform", "native macOS window/menu behavior", .partial, "SwiftUI app commands", "Phase 56 adds an adaptive native/fallback Liquid Glass toolbar title", "Desktop/title accessibility QA pending", "App and design-system tests", "Switch short/long titles", "Phase 56 manual QA"),
            ("UI/platform", "settings organization", .partial, "Settings tabs", "Settings scene opens Account/connection/notifications/developer", "Official settings parity incomplete", "Settings tests", "Command-comma", "Polish later"),
            ("UI/platform", "diagnostics", .done, "Developer Verification", "Redacted diagnostics plus Phase 68 counters and Phase 69 selected-member publications", "Developer-only by design", "Redaction and Phase 60/68/69 diagnostics tests", "Copy diagnostics", "Keep safe"),

            ("Deferred / not parity", "voice", .outOfScope, "Deferred scope", "Not implemented", "Out of Phase 30 scope", "Matrix test", "N/A", "Future verified phase"),
            ("Core chat", "video", .partial, "Attachment metadata and media playback URLs", "Native lazy AVPlayer plus Phase 56 bounded poster generation", "Codec and range-request variety need live QA", "Video mapping and poster-cache tests", "Open several playable videos", "Phase 56 live re-test"),
            ("Deferred / not parity", "screen share", .outOfScope, "Deferred scope", "Not implemented", "Out of Phase 30 scope", "Matrix test", "N/A", "Future verified phase"),
            ("Deferred / not parity", "bots/dashboard", .outOfScope, "Deferred scope", "Not implemented", "Out of Phase 30 scope", "Matrix test", "N/A", "Future verified phase"),
            ("Deferred / not parity", "audit logs", .outOfScope, "Deferred scope", "Not implemented", "Out of Phase 30 scope", "Matrix test", "N/A", "Future verified phase"),
            ("Deferred / not parity", "persistent offline cache", .deferred, "Privacy/scope rule", "No persistent message DB", "Deferred by design", "Regression test", "Relaunch", "Scope separately"),
            ("Deferred / not parity", "APNs/background push", .deferred, "Privacy/scope rule", "Not registered", "Deferred by design", "Regression test", "Relaunch", "Scope separately"),
            ("Deferred / not parity", "server deletion", .outOfScope, "Hard scope boundary", "Not implemented", "Destructive out of scope", "Matrix test", "N/A", "Future verified phase"),
            ("Deferred / not parity", "any unverified route", .blockedByUnverifiedAPI, "Route verification rule", "Disabled/deferred", "Must verify before live action", "Matrix test", "N/A", "Research first")
        ]
        return ParityMatrix(items: specs.map {
            ParityItem(section: $0.0, name: $0.1, status: $0.2, sourceOfTruth: $0.3, currentImplementation: $0.4, knownGaps: $0.5, tests: $0.6, manualQA: $0.7, recommendedNextAction: $0.8)
        })
    }
}
