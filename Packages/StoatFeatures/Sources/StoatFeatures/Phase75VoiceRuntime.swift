import Foundation
import StoatAPI
import StoatModels
import StoatPersistence
import StoatRealtime
import StoatVoice

#if canImport(AVFoundation)
import AVFoundation
#endif

#if canImport(AppKit)
import AppKit
#endif

// MARK: - Call state

/// The local client's relationship to a voice call, independent of any particular UI. Kept
/// SwiftUI-free and independently testable, following the Phase 60/68/74 convention of pulling
/// decision logic out of `MainShellViewModel`.
public enum VoiceCallUIState: Hashable, Sendable {
    case idle
    case connecting(ChannelID)
    case connected(ChannelID)
    case reconnecting(ChannelID)
    case failed(ChannelID, reason: String)

    public var channelID: ChannelID? {
        switch self {
        case .idle: nil
        case let .connecting(id), let .connected(id), let .reconnecting(id): id
        case let .failed(id, _): id
        }
    }

    public var isActive: Bool {
        switch self {
        case .idle: false
        default: true
        }
    }
}

// MARK: - Permission gating

/// Whether the resolved channel permissions allow joining a voice channel at all.
public func canJoinVoice(permissions: Permissions) -> Bool {
    permissions.contains(.connect)
}

/// Whether the resolved channel permissions allow publishing a microphone track once connected.
/// A client can be connected (listening) without being able to speak — mirrors Discord/Revolt's
/// connect-without-speak moderation model.
public func canSpeak(permissions: Permissions) -> Bool {
    permissions.contains(.connect) && permissions.contains(.speak)
}

/// Whether the resolved channel permissions allow hearing other participants. Rare to be false
/// when `connect` is granted, but modeled distinctly since the server exposes it distinctly.
public func canListen(permissions: Permissions) -> Bool {
    permissions.contains(.connect) && permissions.contains(.listen)
}

// MARK: - Mute / deafen / push-to-talk

/// Local audio-output state. Deafening implies muting (can't hear anyone, so no point sending
/// audio either) but the reverse is not true — muting alone still lets you hear others.
public struct VoiceLocalAudioState: Hashable, Sendable {
    public var isMuted: Bool
    public var isDeafened: Bool
    /// Transient unmute from an active push-to-talk key press, layered independently of the
    /// persistent `isMuted` toggle — releasing the key restores whatever `isMuted` already was.
    public var isPushToTalkActive: Bool

    public init(isMuted: Bool = false, isDeafened: Bool = false, isPushToTalkActive: Bool = false) {
        self.isMuted = isMuted
        self.isDeafened = isDeafened
        self.isPushToTalkActive = isPushToTalkActive
    }

    /// Whether the microphone should actually be publishing right now, folding together the
    /// persistent mute toggle, deafen (which forces mute), and any push-to-talk override.
    public var isMicrophoneLive: Bool {
        if isDeafened { return false }
        if isPushToTalkActive { return true }
        return !isMuted
    }

    public func settingMuted(_ muted: Bool) -> Self {
        var copy = self
        copy.isMuted = muted
        if !muted { copy.isDeafened = false }
        return copy
    }

    public func settingDeafened(_ deafened: Bool) -> Self {
        var copy = self
        copy.isDeafened = deafened
        if deafened { copy.isMuted = true }
        return copy
    }

    public func settingPushToTalkActive(_ active: Bool) -> Self {
        var copy = self
        copy.isPushToTalkActive = active
        return copy
    }
}

/// Evaluates a rolling input level against the voice-activation threshold, for when
/// push-to-talk is disabled. `level`/`sensitivity` are both in the engine's 0...1 range.
public func isVoiceActivated(level: Float, sensitivity: Double) -> Bool {
    Double(level) >= sensitivity
}

// MARK: - Microphone permission

public enum MicrophonePermissionStatus: String, Hashable, Sendable {
    case notDetermined
    case denied
    case restricted
    case authorized
    case unknown

    public var allowsCapture: Bool {
        self == .authorized
    }
}

public struct MicrophonePermissionRequestResult: Hashable, Sendable {
    public var statusBefore: MicrophonePermissionStatus
    public var requestAuthorizationCalled: Bool
    public var granted: Bool?
    public var statusAfter: MicrophonePermissionStatus

    public init(
        statusBefore: MicrophonePermissionStatus,
        requestAuthorizationCalled: Bool,
        granted: Bool? = nil,
        statusAfter: MicrophonePermissionStatus
    ) {
        self.statusBefore = statusBefore
        self.requestAuthorizationCalled = requestAuthorizationCalled
        self.granted = granted
        self.statusAfter = statusAfter
    }
}

/// Mirrors `NotificationPermissionManaging` (Phase18Runtime.swift) exactly, so microphone
/// permission gets the same testable DI seam notification permission already has.
public protocol MicrophonePermissionManaging: Sendable {
    func status() async -> MicrophonePermissionStatus
    func requestAuthorization() async -> MicrophonePermissionRequestResult
}

public struct AVCaptureMicrophonePermissionManager: MicrophonePermissionManaging {
    public init() {}

    public func status() async -> MicrophonePermissionStatus {
        #if canImport(AVFoundation)
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .authorized: return .authorized
        @unknown default: return .unknown
        }
        #else
        return .unknown
        #endif
    }

    public func requestAuthorization() async -> MicrophonePermissionRequestResult {
        let before = await status()
        #if canImport(AVFoundation)
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        let after = await status()
        return MicrophonePermissionRequestResult(
            statusBefore: before,
            requestAuthorizationCalled: true,
            granted: granted,
            statusAfter: after
        )
        #else
        return MicrophonePermissionRequestResult(
            statusBefore: before,
            requestAuthorizationCalled: false,
            statusAfter: .unknown
        )
        #endif
    }
}

// MARK: - Errors

public enum VoiceCallError: Error, LocalizedError {
    case noAvailableNode

    public var errorDescription: String? {
        switch self {
        case .noAvailableNode: "No voice server is available right now."
        }
    }
}

// MARK: - Roster cache key

struct VoiceRosterCacheKey: Hashable {
    var channelID: ChannelID
    var fingerprint: Int
}

// MARK: - MainShellViewModel wiring
//
// Kept in this file rather than the StoatFeatures.swift monolith: voice is a large,
// self-contained subsystem, and every stored property it touches (`activeVoiceCall`,
// `voiceRosterCacheKey`, etc.) uses `internal`/`internal(set)` access specifically so this
// extension can reach them from a separate file within the same module.
public extension MainShellViewModel {
    // MARK: Permission gating

    func voicePermissions(for channelID: ChannelID) -> Permissions {
        guard let channel = snapshot.channelsByID[channelID], let serverID = channel.serverID else { return [] }
        let server = snapshot.serversByID[serverID]
        let member = currentUser.flatMap { snapshot.membersByServerAndUserID[ServerMemberKey(serverID: serverID, userID: $0.id)] }
        return Phase25PermissionResolver.resolve(server: server, channel: channel, member: member, currentUserID: currentUser?.id).effectivePermissions
    }

    func canJoinVoiceChannel(_ channelID: ChannelID) -> Bool {
        guard let channel = snapshot.channelsByID[channelID], channel.kind == .voiceChannel else { return false }
        guard apiClientForVoice() != nil else { return false }
        return canJoinVoice(permissions: voicePermissions(for: channelID))
    }

    func voiceJoinDisabledReason(_ channelID: ChannelID) -> String {
        guard snapshot.channelsByID[channelID]?.kind == .voiceChannel else { return "Not a voice channel." }
        guard apiClientForVoice() != nil else {
            return "Reconnect before joining a voice channel."
        }
        return "You don't have permission to join this voice channel."
    }

    /// Same fallback shape as `apiClientForCommunityAction`/`apiClientForDMRefresh`: mock mode
    /// always has an API client (for tests/previews), live mode needs an actual connection.
    private func apiClientForVoice() -> (any StoatAPIClient)? {
        if effectiveRuntimeMode == .mock { return communityAPIClient }
        guard effectiveRuntimeMode == .liveManual, effectiveSessionState == .connected else { return nil }
        return sessionCoordinator?.apiClient
    }

    // MARK: Roster (gateway-synced `ServerMember.voiceChannel`; works even for channels not joined)

    /// Members currently in `channelID` according to the slow-moving, gateway-synced roster —
    /// distinct from `activeVoiceCallParticipants`, which is live LiveKit state for the call the
    /// local client has actually joined.
    func voiceParticipants(for channelID: ChannelID) -> [ServerMember] {
        let key = VoiceRosterCacheKey(channelID: channelID, fingerprint: voiceRosterFingerprint(for: channelID))
        if key == voiceRosterCacheKey { return voiceRosterCache }
        let result = snapshot.membersByServerAndUserID.values.filter { $0.voiceChannel == channelID }
        voiceRosterCacheKey = key
        voiceRosterCache = result
        voiceRosterRevision &+= 1
        return result
    }

    private func voiceRosterFingerprint(for channelID: ChannelID) -> Int {
        var combined = 0
        for member in snapshot.membersByServerAndUserID.values where member.voiceChannel == channelID {
            var hasher = Hasher()
            hasher.combine(member.id.userID)
            hasher.combine(member.canPublish)
            hasher.combine(member.canReceive)
            combined ^= hasher.finalize()
        }
        return combined
    }

    // MARK: Call lifecycle

    func joinVoiceChannel(_ channelID: ChannelID) {
        guard let channel = snapshot.channelsByID[channelID], channel.kind == .voiceChannel else { return }
        guard let apiClient = apiClientForVoice() else {
            presentNotice("Reconnect before joining a voice channel.", severity: .warning)
            return
        }
        if let currentChannelID = activeVoiceCall.channelID {
            if currentChannelID == channelID, activeVoiceCall.isActive { return }
            leaveVoiceCall()
        }
        activeVoiceCall = .connecting(channelID)
        let engine = voiceEngine
        voiceCallTask?.cancel()
        voiceCallTask = Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await apiClient.joinVoiceChannel(channelID: channelID)
                let url = try await self.resolveVoiceURL(from: response, apiClient: apiClient)
                engine.setAudioProcessing(
                    echoCancellation: self.voicePreferences.echoCancellation,
                    noiseSuppression: self.voicePreferences.noiseSuppression
                )
                try await engine.connect(url: url, token: response.token)
                guard !Task.isCancelled else { await engine.disconnect(); return }
                try? await engine.setMicrophoneMuted(!self.voiceLocalAudioState.isMicrophoneLive)
                self.activeVoiceCall = .connected(channelID)
                self.activeVoiceCallParticipants = [:]
                self.installPushToTalkMonitorIfNeeded()
                for await event in engine.events {
                    if Task.isCancelled { break }
                    self.handle(voiceEvent: event, channelID: channelID)
                }
            } catch {
                guard !Task.isCancelled else { return }
                let message = UserFacingError.message(for: error)
                self.activeVoiceCall = .failed(channelID, reason: message)
                self.presentNotice("Couldn't join voice channel: \(message)", severity: .error)
            }
        }
    }

    func leaveVoiceCall() {
        voiceCallTask?.cancel()
        voiceCallTask = nil
        let engine = voiceEngine
        activeVoiceCall = .idle
        activeVoiceCallParticipants = [:]
        removePushToTalkMonitor()
        Task { await engine.disconnect() }
    }

    // MARK: Push-to-talk (in-app-focused only — see Docs/Phase75.md)
    //
    // A local `NSEvent` monitor only fires while Liquid Bagel is the key app, which is exactly
    // the in-app-focused scope decided for this round. A true global hotkey (works while another
    // app is focused) needs the macOS Input Monitoring permission and is a separate follow-up.

    func installPushToTalkMonitorIfNeeded() {
        removePushToTalkMonitor()
        #if canImport(AppKit)
        guard activeVoiceCall.isActive, voicePreferences.pushToTalkEnabled, let keyCode = voicePreferences.pushToTalkKeyCode else { return }
        pushToTalkKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self, event.keyCode == keyCode else { return event }
            switch event.type {
            case .keyDown:
                if !self.voiceLocalAudioState.isPushToTalkActive {
                    self.voiceLocalAudioState = self.voiceLocalAudioState.settingPushToTalkActive(true)
                    self.applyLocalAudioState()
                }
                return nil
            case .keyUp:
                self.voiceLocalAudioState = self.voiceLocalAudioState.settingPushToTalkActive(false)
                self.applyLocalAudioState()
                return nil
            default:
                return event
            }
        }
        #endif
    }

    func removePushToTalkMonitor() {
        #if canImport(AppKit)
        if let pushToTalkKeyMonitor {
            NSEvent.removeMonitor(pushToTalkKeyMonitor)
        }
        #endif
        pushToTalkKeyMonitor = nil
    }

    func toggleMicrophoneMuted() {
        guard activeVoiceCall.isActive else { return }
        voiceLocalAudioState = voiceLocalAudioState.settingMuted(!voiceLocalAudioState.isMuted)
        applyLocalAudioState()
    }

    func toggleDeafened() {
        guard activeVoiceCall.isActive else { return }
        voiceLocalAudioState = voiceLocalAudioState.settingDeafened(!voiceLocalAudioState.isDeafened)
        applyLocalAudioState()
    }

    func showVoiceSettings() {
        selectedSettingsTab = .voice
    }

    /// Write-through to `AppPreferences.voicePreferences`, mirroring
    /// `saveNotificationPreferences()`. Local-only (not part of `SyncedClientPreferences`) since
    /// device IDs are per-machine. Hydration on connect happens in `syncFromSessionCoordinator()`.
    func saveVoicePreferences() {
        let preferences = voicePreferences
        Task { [weak self] in
            guard let self else { return }
            await self.sessionCoordinator?.updatePreferences { $0.voicePreferences = preferences }
        }
        voiceEngine.setAudioProcessing(echoCancellation: preferences.echoCancellation, noiseSuppression: preferences.noiseSuppression)
        if let inputDeviceID = preferences.inputDeviceID { voiceEngine.selectInputDevice(id: inputDeviceID) }
        if let outputDeviceID = preferences.outputDeviceID { voiceEngine.selectOutputDevice(id: outputDeviceID) }
        installPushToTalkMonitorIfNeeded()
    }

    // MARK: Microphone permission (mirrors requestNotificationPermission/refreshNotificationPermissionStatus)

    func refreshMicrophonePermissionStatus() {
        Task { [weak self, manager = microphonePermissionManager] in
            let status = await manager.status()
            await MainActor.run { self?.microphonePermissionStatus = status }
        }
    }

    func requestMicrophonePermission() {
        Task { [weak self, manager = microphonePermissionManager] in
            let result = await manager.requestAuthorization()
            await MainActor.run {
                self?.microphonePermissionStatus = result.statusAfter
                switch result.statusAfter {
                case .authorized:
                    self?.presentNotice("Microphone access is on.", severity: .success)
                case .denied, .restricted:
                    self?.presentNotice("Microphone access is turned off in System Settings.", severity: .warning)
                case .notDetermined, .unknown:
                    break
                }
            }
        }
    }

    func openMacOSMicrophoneSettings() {
        #if canImport(AppKit)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
            placeholderStatus = "Opened macOS Microphone Privacy Settings"
        }
        #endif
    }

    // MARK: Device pickers (StoatVoice's AudioManager-backed enumeration)

    var voiceInputDevices: [VoiceAudioDevice] { voiceEngine.availableInputDevices }
    var voiceOutputDevices: [VoiceAudioDevice] { voiceEngine.availableOutputDevices }

    private func applyLocalAudioState() {
        let engine = voiceEngine
        let muted = !voiceLocalAudioState.isMicrophoneLive
        Task { try? await engine.setMicrophoneMuted(muted) }
    }

    private func handle(voiceEvent event: VoiceEngineEvent, channelID: ChannelID) {
        switch event {
        case let .connectionStateChanged(state):
            guard activeVoiceCall.channelID == channelID else { return }
            switch state {
            case .connected: activeVoiceCall = .connected(channelID)
            case .reconnecting: activeVoiceCall = .reconnecting(channelID)
            case .connecting, .disconnected, .disconnecting: break
            }
        case let .participantConnected(participant):
            activeVoiceCallParticipants[participant.identity] = participant
        case let .participantDisconnected(identity):
            activeVoiceCallParticipants.removeValue(forKey: identity)
        case let .speakingParticipantsChanged(identities):
            for key in activeVoiceCallParticipants.keys {
                activeVoiceCallParticipants[key]?.isSpeaking = identities.contains(key)
            }
        case let .participantMuteChanged(identity, isMuted):
            activeVoiceCallParticipants[identity]?.isMuted = isMuted
        case let .disconnected(reason):
            guard activeVoiceCall.channelID == channelID else { return }
            activeVoiceCall = .idle
            activeVoiceCallParticipants = [:]
            removePushToTalkMonitor()
            if let reason {
                presentNotice("Voice call ended: \(reason)", severity: .warning)
            }
        case let .error(message):
            presentNotice(message, severity: .error)
        }
    }

    private func resolveVoiceURL(from response: VoiceJoinResponse, apiClient: any StoatAPIClient) async throws -> URL {
        if let urlString = response.url, let url = URL(string: urlString) { return url }
        let config = try await cachedOrFetchedRootConfiguration(apiClient: apiClient)
        guard let node = config.features.livekit.nodes.first, let url = URL(string: node.publicURL) else {
            throw VoiceCallError.noAvailableNode
        }
        return url
    }

    private func cachedOrFetchedRootConfiguration(apiClient: any StoatAPIClient) async throws -> StoatConfig {
        if let cachedRootConfiguration { return cachedRootConfiguration }
        let config = try await apiClient.fetchRootConfiguration()
        cachedRootConfiguration = config
        return config
    }
}
