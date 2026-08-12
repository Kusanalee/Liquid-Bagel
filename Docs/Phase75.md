# Phase 75 - Voice Chat Foundation

Phase 75 implements voice chat, the first of the three features every phase from 2 through 74 explicitly deferred (voice, video, screen share). It adds join/leave, mute/deafen, push-to-talk, device selection, and a live participant roster — video and screen share stay out of scope, per plan.

## Architecture

The backend's real-time voice transport is LiveKit (a WebRTC SFU) — confirmed by `StoatConfig.features.livekit`, present since the app's earliest config decoding but never acted on. Rather than hand-roll WebRTC and LiveKit's signaling protocol, this phase adds the official LiveKit Swift SDK (`livekit/client-sdk-swift`) as a dependency, isolated behind a new package:

- **`Packages/StoatVoice`** (new): a `VoiceEngine` protocol plus `LiveKitVoiceEngine`, the only production conformer. Isolating the WebRTC binary dependency here keeps it out of every other package's build graph — `StoatModels`, `StoatUI`, etc. don't need to know LiveKit exists. `StoatFeatures` depends on it; nothing else does.
- **`StoatModels`**: `ServerMember.voiceChannel: ChannelID?` (wire key `voice_channel`) and `VoiceJoinResponse`. `ServerMember` already decoded `can_publish`/`can_receive` from the real wire format before this phase (nobody had wired them to anything) — `voiceChannel` fills the missing piece.
- **`StoatRealtime`**: `PartialServerMember` now decodes `voice_channel`/`can_publish`/`can_receive` (previously decoded neither — a pre-existing gap, not just a voice one: live moderator mute/deafen wouldn't have applied over the gateway even before this phase). No new `StoatGatewayEvent` cases were needed — "who is in which voice channel" rides the existing `ServerMemberUpdate`/`ServerMemberJoin` events once the field exists on the model, since Revolt models voice membership as member state, not a separate event stream.
- **`StoatAPI`**: `joinVoiceChannel(channelID:)` → `POST /channels/{target}/join_call`, returning a LiveKit token. No `leaveVoiceChannel` REST call is modeled — leaving is a client-side `VoiceEngine.disconnect()`; no `leave_call` route has been confirmed to exist.
- **`StoatFeatures/Phase75VoiceRuntime.swift`**: SwiftUI-free logic (`VoiceCallUIState`, mute/deafen/push-to-talk transitions, permission gating via the existing `connect`/`speak`/`listen` bits and `Phase25PermissionResolver`, `MicrophonePermissionManaging` mirroring `NotificationPermissionManaging` exactly) plus the `MainShellViewModel` extension that wires it all together — join/leave flow, the gateway-synced roster (`voiceParticipants(for:)`, fingerprint-cached the same way `memberListGroups` is), LiveKit event handling, and the push-to-talk key monitor.
- **UI**: `ChannelRow`'s blanket `isDisabled` for voice channels is gone — the caller now resolves a real permission-based gate. A new `VoiceCallBar` shows the active call with mute/deafen/leave controls and a live participant strip with speaking rings. Settings gains a `Voice` tab mirroring `NotificationSettingsTab`'s structure: permission section, device pickers (via `AudioManager.shared` on the LiveKit side, no raw CoreAudio needed), processing toggles, push-to-talk key capture, and an input-sensitivity slider with a live meter.
- **`StoatPersistence`**: `VoicePreferences` added to `AppPreferences` exactly like `NotificationPreferences` — per-field fallback decoding, `validated()` clamping — and deliberately **not** part of `SyncedClientPreferences`: device IDs are per-machine, so syncing them across devices would make one machine's mic pick fight another's.

## A note on file layout

Property declarations for voice state live in `StoatFeatures.swift` (stored properties can't live in an extension), but the actual join/leave/roster/event-handling logic lives in `Phase75VoiceRuntime.swift` as an `extension MainShellViewModel` — a deliberate deviation from this codebase's usual pattern of adding everything to the `StoatFeatures.swift` monolith. Voice is a large, self-contained subsystem; every stored property it touches uses `internal`/`internal(set)` access (rather than `private`) specifically so this extension, in a separate file within the same module, can reach them.

## Push-to-talk: in-app-focused only

A local `NSEvent` monitor only fires while Liquid Bagel is the key app — exactly the scope decided for this round. A hotkey that works while another app is focused needs the macOS Input Monitoring permission and a global event tap, a meaningfully larger and separate piece of work on an app that's already ad-hoc signed. The monitor installs when a call becomes active and push-to-talk is enabled, and tears down on leave/disconnect.

## What's automated vs. needs a live pass

Automated: permission gating (`canJoinVoice`/`canSpeak`/`canListen`), mute/deafen/push-to-talk state transitions, `VoicePreferences` persistence round-trip, `PartialServerMember` decode of the new fields including the `clear` list, and roster cache correctness/invalidation.

Needs a live pass — nothing here can be exercised without a real server and real audio hardware:

- `join_call`'s wire shape has since been checked against the upstream `revolt_models::v0` types (`DataJoinCall`/`CreateVoiceUserResponse` in `voice_join.rs`): the request's `node`/`force_disconnect`/`recipients` are all optional (so sending just `node`, as this client does, is valid) and the response is `{ token, url }`, `url` being the LiveKit host for the node the server picked — matching `VoiceJoinRequest`/`VoiceJoinResponse` exactly. That closes out the "is this the right shape" question; what's still unverified is only the live-audio behaviour below.
- A join failure previously always surfaced as the same opaque "Something went wrong. Try again." — `VoiceCallError` wasn't `UserPresentableError` and LiveKit `room.connect` errors weren't distinguished or logged. Fixed: `VoiceCallError` now conforms to `UserPresentableError` with a distinct case per failure (no node available, an invalid `join_call` response, or a LiveKit connect failure), and both `joinVoiceChannel`'s catch and `LiveKitVoiceEngine.connect`'s catch log the raw underlying error (`Logger(subsystem: "LiquidBagel", category: "Voice")`) without putting it in user-facing copy.
- Whether a `leave_call` route exists at all — currently assumed not to, and leaving is handled entirely client-side.
- The actual audio path: join with two accounts, confirm the roster and speaking indicators update on both sides, mute/deafen/push-to-talk are audible, device switching in Settings takes effect, and the microphone permission prompt/System Settings deep link work from a fresh TCC state.

## What stayed out

Video and screen share: unchanged, deferred, per the user's explicit direction this round. Global (unfocused) push-to-talk: deferred, needs Input Monitoring. Server-side voice moderation (force-mute/deafen/move a member) — the model fields already exist from earlier phases (`canPublish`/`canReceive`/`voiceChannel` on the member edit draft) but wiring a moderation UI onto them is a separate follow-up, not required for basic voice chat.

## Automated proof

Package tests added: `VoiceChatTests.swift` (StoatFeatures) and `StoatVoiceTests` (new package). `Scripts/check.sh` — the no-Mock/Stub/Fake gate, per-package tests, and the signed macOS build — all pass with `StoatVoice` and its LiveKit dependency in the graph.
