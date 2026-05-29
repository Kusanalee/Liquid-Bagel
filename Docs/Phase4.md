# Phase 4 Summary

## What Was Implemented

Phase 4 moves Liquid Bagel from a mock-only shell toward a controlled chat-client runtime. The app still launches in mock mode and does not open a live REST or WebSocket connection automatically. Live behavior is available only through the developer runtime menu when a saved credential exists.

Implemented:

- explicit runtime/session state through `AppSessionCoordinator`
- mock and realtime snapshot sources for the shell
- snapshot-driven shell selection reconciliation
- channel-scoped message loading state and pagination
- state-driven timeline loading, empty, error, retry, older-load, pending, failed, unread, and typing UI
- per-channel composer drafts
- permission-aware composer readiness
- optimistic text send with nonce reconciliation and failure state
- basic edit, delete, and quick reaction actions through message handlers
- typing begin/end plumbing with throttling
- local read/unread clearing on active channel selection
- runtime debug connection menu
- mock-only tests for runtime, snapshots, messages, composer, actions, typing, and unread behavior

## Runtime And Session Architecture

`AppRuntimeMode` now supports `mock` and `liveManual`. `AppSessionState` models mock, signed-out, credential loading, ready, connecting, connected, and failed states.

`AppSessionCoordinator` owns the runtime boundary:

- starts in mock mode with `MockShellData`
- checks Keychain credential availability without connecting
- creates live API/realtime clients only in `connectLiveManually()`
- fetches the current user before live realtime connection
- routes realtime events through `RealtimeStateStore`
- exposes non-token diagnostics and connection state
- disconnects cleanly and can reset to mock

No session token is shown or logged by the Phase 4 UI.

## Snapshot Source Architecture

The shell consumes `ShellSnapshotSource` instead of caring whether data is mock or realtime:

- `MockShellSnapshotSource` yields a fixed mock snapshot.
- `RealtimeStoreSnapshotSource` streams snapshots from `RealtimeStateStore`.

`MainShellViewModel` observes the selected source, hydrates message state from snapshots, and validates selection after each update. If a selected channel disappears, it falls back to the first visible text-style channel. If the selected server disappears, it returns Home.

## Message Loading Behavior

`ChannelMessageController` owns channel message state:

- snapshot/mock messages are used first
- live REST `fetchMessages(channelID:before:after:limit:)` is used only in live manual mode with an API client
- `before` pagination powers the Load Older affordance
- duplicate messages are deduped by ID and optimistic nonces
- messages are sorted chronologically
- failed loads keep cached timeline messages
- stale channel loads are token-guarded
- each channel is memory-capped

Mock mode does not call live REST.

## Composer And Send Behavior

The composer now stores local drafts per channel and uses a real send button/action. It disables sending when no channel is selected, the draft is blank, permissions deny sending, the runtime is not send-capable, or the channel is already sending.

Enter sends, and Shift+Enter inserts a newline through a small macOS `NSTextView` wrapper. Attachment and emoji buttons remain disabled placeholders.

## Optimistic And Realtime Reconciliation

Sending creates a pending `TimelineMessage` with a client nonce. On API success, the pending item is replaced with the confirmed message. If realtime later echoes the same message by nonce or ID, hydration dedupes it. If sending fails, the pending item becomes failed and exposes retry.

UI-only pending/failed state lives in `TimelineMessageStatus`; core `Message` remains API-shaped.

## Edit, Delete, And Reactions

Basic context-menu actions are wired:

- Copy Message
- Edit own message
- Delete own message, or permissioned delete when `manageMessages` is known
- quick reactions for 👍, ❤️, and 😂 when `react` is allowed
- debug-only Copy Message ID

Live handlers call the verified Phase 1 API methods. Failures surface as non-crashing inline/status messages. Rich inline editing UX, full emoji picker, and custom emoji handling remain deferred.

## Typing And Ack

Typing uses Phase 2 realtime client events:

- first non-empty draft sends `BeginTyping`
- repeated keystrokes do not spam begin events
- inactivity or channel changes send `EndTyping`
- selected-channel typing display excludes the current user
- mock handlers record typing events for tests

Live channel ack send is deferred because the current codebase has receive-side `ChannelAck` but no verified send/API route. Phase 4 implements local read-state behavior: selecting or actively viewing a channel clears the unread dot locally while preserving mention badges.

## Permission Handling

Composer and actions use `channel.permissions` when present, then server `defaultPermissions` when available. Unknown permissions remain conservative but usable:

- mock mode allows sending
- real unknown permissions do not block all usage
- known missing `sendMessage`, `uploadFiles`, or `react` disables the relevant UI/action

Full server/channel permission resolution is still deferred.

## Tests Added

`StoatFeaturesTests` now covers:

- mock startup and no auto-connect
- missing credential signed-out state
- manual connect/disconnect with realtime mocks
- invalid-session failure surfacing
- mock snapshot emission
- view model snapshot binding
- deleted channel/server fallback
- mock message loading without API calls
- live message fetch, pagination, dedupe, sorting
- failed load retaining cached messages
- per-channel drafts
- empty draft blocking
- successful optimistic send and echo dedupe
- failed send state
- edit/delete/reaction handler calls
- typing begin/end throttling
- current-user typing exclusion
- local unread clearing

No tests require live network or real credentials.

## Mocked Or Deferred

Still mocked or deferred:

- login/session onboarding UI
- production credential management
- live channel ack send
- file upload UI
- emoji picker
- media viewer
- notifications
- persistence/cache
- friends/DM/discover APIs
- full search
- settings
- voice
- full permission resolver

## Risks And API Uncertainties

- Live message CRUD/reactions use Phase 1 verified methods, but real-world permission failures and rate limits still need UX polish.
- Live channel ack remains uncertain and is intentionally local-only.
- Realtime echo dedupe relies on nonce/ID consistency.
- The timeline remains a simple SwiftUI scroll view; deeper virtualization is deferred until message volume demands it.

## How To Run

```sh
swift test --package-path Packages/StoatModels
swift test --package-path Packages/StoatAPI
swift test --package-path Packages/StoatRealtime
swift test --package-path Packages/StoatFeatures
swift test --package-path Packages/StoatUI
swift test --package-path Packages/StoatDesignSystem
Scripts/check.sh
```

Run the app from the `LiquidBagel` Xcode scheme. It opens in mock mode. Use the toolbar runtime chip to inspect mode/session/connection state, connect manually when a saved credential exists, disconnect, or reset to mock.

## Recommended Phase 5 Next Step

Phase 5 should add explicit developer credential tooling or a narrowly scoped login/session setup flow, then verify live realtime hydration and message actions against a real account without introducing automatic launch-time connection.
