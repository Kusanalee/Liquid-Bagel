import SwiftUI
import LiveKit

#if canImport(AppKit)
import AppKit

public struct VoiceVideoView: NSViewRepresentable {
    public let handle: VoiceVideoTrackHandle
    public var mirrored: Bool

    public init(handle: VoiceVideoTrackHandle, mirrored: Bool = false) {
        self.handle = handle
        self.mirrored = mirrored
    }

    public func makeNSView(context: Context) -> VideoView {
        let view = VideoView(frame: .zero)
        view.layoutMode = .fill
        view.mirrorMode = mirrored ? .mirror : .off
        view.track = handle.storage as? VideoTrack
        return view
    }

    public func updateNSView(_ view: VideoView, context: Context) {
        view.mirrorMode = mirrored ? .mirror : .off
        view.track = handle.storage as? VideoTrack
    }
}
#endif
