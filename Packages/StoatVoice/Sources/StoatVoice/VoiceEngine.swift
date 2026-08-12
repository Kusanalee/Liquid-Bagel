import Foundation

/// Connection state of the active voice call, decoupled from LiveKit's own `ConnectionState`
/// so the rest of the app doesn't need to import LiveKit just to read call status.
public enum VoiceConnectionState: String, Sendable, Hashable {
    case disconnected
    case connecting
    case reconnecting
    case connected
    case disconnecting
}

/// A participant in the active voice call, as observed live from the room connection. This is
/// distinct from `ServerMember.voiceChannel` (StoatModels) — the member field is the slow-moving
/// "who is in which channel" roster synced over the gateway, while this is moment-to-moment
/// speaking/mute state that only exists once the local client has actually joined the room.
public struct VoiceParticipant: Sendable, Hashable, Identifiable {
    public var id: String { identity }
    public var identity: String
    public var name: String?
    public var isSpeaking: Bool
    public var audioLevel: Float
    public var isMuted: Bool

    public init(identity: String, name: String? = nil, isSpeaking: Bool = false, audioLevel: Float = 0, isMuted: Bool = false) {
        self.identity = identity
        self.name = name
        self.isSpeaking = isSpeaking
        self.audioLevel = audioLevel
        self.isMuted = isMuted
    }
}

/// A selectable audio input/output device, mirroring LiveKit's `AudioDevice` without exposing
/// the LiveKit type itself outside this package.
public struct VoiceAudioDevice: Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var isDefault: Bool

    public init(id: String, name: String, isDefault: Bool) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
    }
}

public enum VoiceEngineEvent: Sendable {
    case connectionStateChanged(VoiceConnectionState)
    case participantConnected(VoiceParticipant)
    case participantDisconnected(identity: String)
    case speakingParticipantsChanged(identities: Set<String>)
    case participantMuteChanged(identity: String, isMuted: Bool)
    /// The room connection ended, whether cleanly (`reason == nil`) or due to an error.
    case disconnected(reason: String?)
    case error(String)
}

/// Abstraction over the real-time voice transport (LiveKit) so `StoatFeatures` can be built and
/// tested without a live server. `LiveKitVoiceEngine` is the only production conformer in
/// `Sources/`; fakes belong in test targets only, per the Phase 73 Live-Only Runtime gate.
public protocol VoiceEngine: Sendable {
    /// Room/participant lifecycle events. Multiple subscribers are supported.
    var events: AsyncStream<VoiceEngineEvent> { get }
    /// Local microphone level, ~10x/sec while connected. Emits nothing while not connected —
    /// a true pre-join mic preview meter needs a separate capture path and is not implemented
    /// yet (see Docs/Phase75.md "What stayed out").
    var localAudioLevel: AsyncStream<Float> { get }

    func connect(url: URL, token: String) async throws
    func disconnect() async
    func setMicrophoneMuted(_ muted: Bool) async throws
    /// Sets echo cancellation / noise suppression for the next time the microphone track is
    /// (re)published — LiveKit does not support hot-swapping capture options on a live track.
    func setAudioProcessing(echoCancellation: Bool, noiseSuppression: Bool)

    var availableInputDevices: [VoiceAudioDevice] { get }
    var availableOutputDevices: [VoiceAudioDevice] { get }
    var selectedInputDeviceID: String? { get }
    var selectedOutputDeviceID: String? { get }
    func selectInputDevice(id: String)
    func selectOutputDevice(id: String)
}
