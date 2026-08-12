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

public struct VoiceCameraDevice: Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public enum VoiceScreenShareSourceKind: String, Sendable, Hashable {
    case display
    case window
}

public struct VoiceScreenShareSource: Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var detail: String?
    public var kind: VoiceScreenShareSourceKind

    public init(id: String, name: String, detail: String? = nil, kind: VoiceScreenShareSourceKind) {
        self.id = id
        self.name = name
        self.detail = detail
        self.kind = kind
    }
}

public enum VoiceVideoSource: String, Sendable, Hashable {
    case camera
    case screenShare
}

/// Opaque media handle. LiveKit stays private to StoatVoice while the package-owned video view
/// can still render the underlying track.
public final class VoiceVideoTrackHandle: @unchecked Sendable, Hashable, Identifiable {
    public let id: String
    let storage: AnyObject?

    public init(id: String) {
        self.id = id
        storage = nil
    }

    init(id: String, storage: AnyObject) {
        self.id = id
        self.storage = storage
    }

    public static func == (lhs: VoiceVideoTrackHandle, rhs: VoiceVideoTrackHandle) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

public struct VoiceVideoTrack: Sendable, Hashable, Identifiable {
    public var id: String { handle.id }
    public var participantIdentity: String
    public var participantName: String?
    public var source: VoiceVideoSource
    public var isLocal: Bool
    public var handle: VoiceVideoTrackHandle

    public init(participantIdentity: String, participantName: String? = nil, source: VoiceVideoSource, isLocal: Bool, handle: VoiceVideoTrackHandle) {
        self.participantIdentity = participantIdentity
        self.participantName = participantName
        self.source = source
        self.isLocal = isLocal
        self.handle = handle
    }
}

public enum VoiceEngineEvent: Sendable {
    case connectionStateChanged(VoiceConnectionState)
    case participantConnected(VoiceParticipant)
    case participantDisconnected(identity: String)
    case speakingParticipantsChanged(identities: Set<String>)
    case participantMuteChanged(identity: String, isMuted: Bool)
    case videoTrackAdded(VoiceVideoTrack)
    case videoTrackRemoved(id: String)
    case localCameraChanged(Bool)
    case localScreenShareChanged(Bool)
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
    func setCameraEnabled(_ enabled: Bool, deviceID: String?, maxWidth: Int?, maxHeight: Int?) async throws
    func setScreenShareEnabled(_ enabled: Bool, sourceID: String?, maxWidth: Int?, maxHeight: Int?) async throws
    /// Sets echo cancellation / noise suppression for the next time the microphone track is
    /// (re)published — LiveKit does not support hot-swapping capture options on a live track.
    func setAudioProcessing(echoCancellation: Bool, noiseSuppression: Bool)

    var availableInputDevices: [VoiceAudioDevice] { get }
    var availableOutputDevices: [VoiceAudioDevice] { get }
    var selectedInputDeviceID: String? { get }
    var selectedOutputDeviceID: String? { get }
    func selectInputDevice(id: String)
    func selectOutputDevice(id: String)
    func availableCameraDevices() async -> [VoiceCameraDevice]
    func availableScreenShareSources() async throws -> [VoiceScreenShareSource]
}
