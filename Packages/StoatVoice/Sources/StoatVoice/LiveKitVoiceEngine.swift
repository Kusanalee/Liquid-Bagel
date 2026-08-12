import Foundation
import LiveKit

/// Real `VoiceEngine` implementation backed by the LiveKit Swift SDK. Wraps a single `Room` for
/// the lifetime of one call; callers are expected to `disconnect()` before `connect()`-ing again
/// for a different channel (matches the app's one-active-call-at-a-time model).
public final class LiveKitVoiceEngine: NSObject, VoiceEngine, @unchecked Sendable {
    private let room: Room
    private let lock = NSLock()
    private var eventContinuations: [UUID: AsyncStream<VoiceEngineEvent>.Continuation] = [:]
    private var audioLevelContinuations: [UUID: AsyncStream<Float>.Continuation] = [:]
    private var captureOptions = AudioCaptureOptions()
    private var audioLevelTask: Task<Void, Never>?

    public override init() {
        room = Room()
        super.init()
        room.delegates.add(delegate: self)
    }

    deinit {
        audioLevelTask?.cancel()
    }

    public var events: AsyncStream<VoiceEngineEvent> {
        AsyncStream { [weak self] continuation in
            guard let self else { continuation.finish(); return }
            let id = UUID()
            lock.lock()
            eventContinuations[id] = continuation
            lock.unlock()
            continuation.onTermination = { [weak self] _ in
                self?.removeEventContinuation(id)
            }
        }
    }

    public var localAudioLevel: AsyncStream<Float> {
        AsyncStream { [weak self] continuation in
            guard let self else { continuation.finish(); return }
            let id = UUID()
            lock.lock()
            audioLevelContinuations[id] = continuation
            lock.unlock()
            continuation.onTermination = { [weak self] _ in
                self?.removeAudioLevelContinuation(id)
            }
        }
    }

    public func connect(url: URL, token: String) async throws {
        do {
            try await room.connect(url: url.absoluteString, token: token)
            _ = try? await room.localParticipant.setMicrophone(enabled: true, captureOptions: captureOptions)
            startAudioLevelPolling()
        } catch {
            emit(.error(error.localizedDescription))
            throw error
        }
    }

    public func disconnect() async {
        audioLevelTask?.cancel()
        audioLevelTask = nil
        await room.disconnect()
    }

    public func setMicrophoneMuted(_ muted: Bool) async throws {
        _ = try await room.localParticipant.setMicrophone(enabled: !muted, captureOptions: captureOptions)
    }

    public func setAudioProcessing(echoCancellation: Bool, noiseSuppression: Bool) {
        captureOptions = AudioCaptureOptions(echoCancellation: echoCancellation, noiseSuppression: noiseSuppression)
    }

    public var availableInputDevices: [VoiceAudioDevice] {
        AudioManager.shared.inputDevices.map { VoiceAudioDevice(id: $0.deviceId, name: $0.name, isDefault: $0.isDefault) }
    }

    public var availableOutputDevices: [VoiceAudioDevice] {
        AudioManager.shared.outputDevices.map { VoiceAudioDevice(id: $0.deviceId, name: $0.name, isDefault: $0.isDefault) }
    }

    public var selectedInputDeviceID: String? { AudioManager.shared.inputDevice.deviceId }
    public var selectedOutputDeviceID: String? { AudioManager.shared.outputDevice.deviceId }

    public func selectInputDevice(id: String) {
        guard let device = AudioManager.shared.inputDevices.first(where: { $0.deviceId == id }) else { return }
        AudioManager.shared.inputDevice = device
    }

    public func selectOutputDevice(id: String) {
        guard let device = AudioManager.shared.outputDevices.first(where: { $0.deviceId == id }) else { return }
        AudioManager.shared.outputDevice = device
    }

    // MARK: - Event plumbing

    private func emit(_ event: VoiceEngineEvent) {
        lock.lock()
        let continuations = Array(eventContinuations.values)
        lock.unlock()
        for continuation in continuations { continuation.yield(event) }
    }

    private func emitAudioLevel(_ level: Float) {
        lock.lock()
        let continuations = Array(audioLevelContinuations.values)
        lock.unlock()
        for continuation in continuations { continuation.yield(level) }
    }

    private func removeEventContinuation(_ id: UUID) {
        lock.lock()
        eventContinuations.removeValue(forKey: id)
        lock.unlock()
    }

    private func removeAudioLevelContinuation(_ id: UUID) {
        lock.lock()
        audioLevelContinuations.removeValue(forKey: id)
        lock.unlock()
    }

    private func startAudioLevelPolling() {
        audioLevelTask?.cancel()
        audioLevelTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                self.emitAudioLevel(self.room.localParticipant.audioLevel)
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }
}

extension LiveKitVoiceEngine: RoomDelegate {
    public func room(_ room: Room, didUpdateConnectionState connectionState: ConnectionState, from oldConnectionState: ConnectionState) {
        let mapped: VoiceConnectionState
        switch connectionState {
        case .disconnected: mapped = .disconnected
        case .connecting: mapped = .connecting
        case .reconnecting: mapped = .reconnecting
        case .connected: mapped = .connected
        case .disconnecting: mapped = .disconnecting
        @unknown default: mapped = .disconnected
        }
        emit(.connectionStateChanged(mapped))
    }

    public func room(_ room: Room, participantDidConnect participant: RemoteParticipant) {
        emit(.participantConnected(VoiceParticipant(
            identity: participant.identity?.stringValue ?? "",
            name: participant.name,
            isSpeaking: participant.isSpeaking,
            audioLevel: participant.audioLevel
        )))
    }

    public func room(_ room: Room, participantDidDisconnect participant: RemoteParticipant) {
        emit(.participantDisconnected(identity: participant.identity?.stringValue ?? ""))
    }

    public func room(_ room: Room, didUpdateSpeakingParticipants participants: [Participant]) {
        emit(.speakingParticipantsChanged(identities: Set(participants.compactMap { $0.identity?.stringValue })))
    }

    public func room(_ room: Room, participant: Participant, trackPublication: TrackPublication, didUpdateIsMuted isMuted: Bool) {
        guard let identity = participant.identity?.stringValue else { return }
        emit(.participantMuteChanged(identity: identity, isMuted: isMuted))
    }

    public func room(_ room: Room, didDisconnectWithError error: LiveKitError?) {
        emit(.disconnected(reason: error?.localizedDescription))
    }
}
