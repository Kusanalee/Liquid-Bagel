# Phase 7 Summary

## What Was Implemented

Phase 7 stabilizes the explicit Live Manual workflow after a user chooses to connect. The app still launches in mock mode, restores only safe local metadata, checks scoped credential presence, and does not validate credentials or open REST/WebSocket connections automatically.

Implemented:

- deterministic live server/channel restoration after realtime `Ready`
- token-free live hydration status and connection health summaries
- clearer reconnect, disconnect, reset-to-mock, and refresh controls
- friendlier empty and partial Ready states
- safer selected-channel message refresh behavior
- live selection persistence only for IDs present in the current live snapshot
- current user and environment display in connection surfaces
- mock-only tests for restoration, hydration, reconnect, refresh, and redaction helpers

## Runtime Flow Behavior

Startup remains mock-safe:

1. load safe preferences
2. restore selected environment metadata
3. check scoped credential presence
4. keep mock snapshot active
5. do not validate credentials
6. do not open REST or WebSocket

Manual connect still requires explicit user action. It loads the selected environment's scoped credential, validates the session by fetching the current user, creates live API/realtime clients, authenticates the WebSocket, waits for `Ready`, hydrates the realtime store, then lets the shell restore a valid live selection.

## Selection Restoration Rules

`ShellSelectionRestorer` owns the live fallback rules:

- persisted server and channel both exist: restore both
- server exists but channel is missing or invalid: select first visible text-style channel in that server
- server is missing: select first server with a visible text-style channel
- no servers: return Home with “No servers available”
- server exists but no text-style channels exist: select the server with no channel and show “No text channels available”
- Home/Discover are preserved when there is no persisted live selection and the snapshot has usable live channels

Live selection persistence writes only safe non-token IDs and only when those IDs exist in the current live snapshot. Mock IDs are not persisted as live selections unless they also exist in the live snapshot.

## Realtime Hydration Status

`LiveHydrationStatus` tracks:

- whether `Ready` was received
- user/server/channel/member/unread counts
- selected server/channel availability
- last hydration time
- a friendly warning for empty or partial snapshots

The status is exposed in the runtime chip and Account & Connection surfaces. It contains no tokens, raw session IDs, or raw server responses.

## Partial And Empty Ready Handling

The shell now treats partial Ready payloads as recoverable states:

- no servers: “No servers available”
- no text channels: “No text channels available”
- waiting for Ready: “Waiting for realtime data”
- disconnected/failed live refresh: “Reconnect to refresh live state”
- missing selected channel: fallback selection plus “Selected channel no longer exists”

The realtime store still accepts missing Ready fields conservatively and keeps existing defaults for absent optional collections.

## Reconnect UX

Reconnect is explicit. The toolbar runtime menu and settings surfaces expose Reconnect, Disconnect, Reset to Mock, and channel refresh actions. Manual reconnect disconnects any active realtime client first, then reconnects with the currently selected environment and its scoped credential.

The existing realtime client's automatic transport reconnect policy remains in place, but Phase 7 only surfaces its state; it does not introduce a new credential/session loop or background launch behavior.

## Manual Refresh Behavior

Command+R and refresh controls now route by runtime state:

- mock mode: safely refreshes mock/message state and reports “Mock data refreshed”
- live connected/Ready: reloads selected channel messages through REST
- live disconnected/failed: reports that reconnect is needed
- no selected channel: refreshes status messaging only

Message fetch failures continue to preserve cached timeline messages and expose retry.

## Channel Navigation Behavior

The server rail and channel list continue to bind to the active `RealtimeSnapshot`. Selecting live channels loads messages through `ChannelMessageController`, active channels locally clear unread state, and inactive unread/mention badges remain visible.

When realtime deletes a selected channel or server, the shell validates selection and falls back safely instead of crashing or keeping a stale route.

## Error Recovery States

The UI now gives clearer next actions for common live states:

- missing credential: set up or validate a session
- invalid session: validate or replace the session
- failed connection/auth/network: reconnect, disconnect, or reset to mock
- Ready not received yet: wait for realtime data
- selected channel fetch failed: retry message load
- stale live snapshot: reconnect to refresh live state

## Security And Redaction

Phase 7 preserves the previous security model:

- tokens remain Keychain-only
- preferences store only non-token values
- diagnostics and health text do not expose tokens
- WebSocket query-token auth remains redacted
- reconnect uses only the currently selected environment's scoped credential
- custom environments do not share credentials
- new UI helpers redact token-like diagnostics

## Tests Added

New mock-only tests cover:

- selection restoration success and fallback branches
- no-server and no-text-channel restoration states
- Home preservation when no persisted selection exists
- Ready-driven hydration status counts
- manual reconnect disconnecting first and using selected environment scope
- refresh behavior in mock and disconnected live states
- connection/hydration helper labels and token redaction

Existing tests continue to cover mock-safe startup, no auto-connect, no auto-validation, message loading, cached-message preservation, unread clearing, and invalid-session surfacing.

## Deferred

Still deferred:

- automatic live connect on launch
- automatic credential validation on launch
- notifications
- uploads/media UI
- persistent message cache/database
- full friends/DM/discover APIs
- voice
- server/channel settings
- full account editing
- full permission resolver
- live tests requiring real credentials

## Known Risks And API Uncertainties

- Ready is still the source of truth for live server/channel collections because verified REST list endpoints remain unavailable.
- Live channel ack send remains deferred; unread clearing is local.
- Partial Ready behavior depends on which fields the server chooses to omit versus return empty.
- The automatic transport reconnect policy is surfaced but not redesigned.

## How To Run

```sh
swift test --package-path Packages/StoatModels
swift test --package-path Packages/StoatAPI
swift test --package-path Packages/StoatRealtime
swift test --package-path Packages/StoatFeatures
swift test --package-path Packages/StoatUI
swift test --package-path Packages/StoatDesignSystem
swift test --package-path Packages/StoatPersistence
Scripts/check.sh
```

Run the app from the `LiquidBagel` Xcode scheme. It opens in mock mode. Use the runtime chip or Account & Connection settings to validate/setup a session, connect manually, reconnect, disconnect, refresh, or reset to mock.

## Recommended Phase 8 Next Step

Phase 8 should focus on keyboard/accessibility polish, command routing, and deeper live navigation ergonomics while keeping uploads, notifications, persistent message cache, friends/discover, and voice deferred.
