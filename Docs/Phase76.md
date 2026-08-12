# Phase 76 - Voice, Video, and Interface Polish

Phase 76 repairs the v1.2 call path and adds camera video, display/window sharing, and an inline call stage. It also restructures Server Settings, Home, Friends, and Saved Notes navigation. This phase does not change the app version or ship a release.

## Call architecture

- `Channel.isVoiceCapable` recognizes both Stoat wire shapes: a dedicated `VoiceChannel`, and a `TextChannel` with non-null `voice` metadata. Selecting a voice-enabled text channel keeps its timeline and exposes a Join preview; selecting a dedicated voice channel opens the stage directly.
- `VoiceJoinRequest` sends the chosen LiveKit node to `POST /channels/{id}/join_call`. Nodes are probed concurrently with a short timeout; the fastest success wins and the first configured node is the deterministic fallback. The response requires both `token` and `url`.
- `StoatVoice` owns all LiveKit types. `VoiceEngine` exposes opaque video handles, camera/display/window discovery, independent camera and screen-share publishing, and publication/removal events. `VoiceVideoView` is the package-owned AppKit/SwiftUI renderer.
- Camera and screen sharing are independently tracked and may run together. Screen shares take the wide primary tile; cameras use an adaptive grid; audio-only participants keep avatar/speaking tiles. The sidebar call bar remains visible while another channel is selected.
- Publishing video requires an active call, the channel `Video` permission, and the current account's instance limit. New-user/default limits are selected from ULID account age and capture dimensions are clamped to the configured resolution.

## macOS privacy and local settings

Camera starts disabled and requires explicit action. The app includes `NSCameraUsageDescription` and the sandbox camera entitlement. Camera selection is stored only in local `VoicePreferences`, with fallback decoding for preference files written before Phase 76.

Screen sharing uses an in-app source sheet backed by LiveKit display/window enumeration. Liquid Bagel windows are excluded and audio is not published. The sheet has explicit cancellation, denied/empty recovery, `NSScreenCaptureUsageDescription`, and an Open Screen Recording Settings action.

## Interface changes

- Server Settings is a 900 by 680 sheet with persistent grouped vertical navigation and an independently scrolling detail pane. Every existing destination remains available.
- Home keeps a compact full-width account strip and uses an adaptive two-column Recent DMs/Friends layout that collapses to one column.
- Friends is top-anchored with counted Online, All, Pending, and Blocked tabs, a distinct Add Friend action, and full-width divided rows.
- Saved Notes is a labeled note-icon row directly below Friends. It no longer appears as an avatar-like DM or in Recent DMs; the existing self-DM resolver and recovery path remain unchanged.

## Scope and proof boundary

DM/group calls, system-audio sharing, recording, backgrounds, and global push-to-talk remain deferred. Package tests and `Scripts/check.sh` validate model, request, state, presentation, and build behavior, but they are not proof of signed-in LiveKit interoperability. Before release, perform two-client signed-in QA for audio, permissions, camera rendering, display/window sharing, navigation, reconnect/leave cleanup, and instance-limit rejection, plus manual narrow/wide resizing of Home, Friends, and Server Settings.
