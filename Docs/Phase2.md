# Phase 2 Summary

## Implemented

- Replaced the placeholder `StoatRealtime` package with a Foundation-only realtime layer that depends on `StoatModels` and `StoatAPI`.
- Added a public realtime client API, WebSocket transport abstraction, live `URLSessionWebSocketTask` transport, scripted/mock transport, connection states, typed errors, diagnostics, logging hooks, reconnect policy, and token-redacted URL helpers.
- Implemented JSON client-to-server encoding for `Authenticate`, `BeginTyping`, `EndTyping`, `Ping`, and `Subscribe`.
- Implemented resilient server-to-client decoding for core gateway events, `Bulk` flattening, `Ready` payloads, partial update payloads, unknown event fallback, and malformed JSON failure.
- Added an in-memory `RealtimeStateStore` reducer/snapshot that hydrates from `Ready`, applies common mutations, tracks typing/unreads/reactions, and caps messages per channel.
- Added a small `ServerSubscriptionManager` for the documented focused/capped/rate-limited server user-update subscription behavior.

## Public API Overview

- `StoatRealtimeClient` exposes `connectionState`, `events`, `connect`, `disconnect`, and `send`.
- `LiveStoatRealtimeClient` is the concrete actor implementation. It accepts a `WebSocketTransportFactory`, Stoat JSON encoder/decoder, `RealtimeClientConfiguration`, and `RealtimeLogger`.
- `RealtimeConnectionState`, `RealtimeDisconnectReason`, `RealtimeError`, `RealtimeDiagnostics`, `ReconnectPolicy`, `ReadyField`, `ReadyPayload`, `ClientGatewayEvent`, and `StoatGatewayEvent` are public.
- `WebSocketTransport` / `WebSocketTransportFactory` allow tests and future alternative transports without live credentials or network.

## Connection Lifecycle

- WebSocket URLs are built from `StoatAPIEnvironment.eventsURL` with `version=1`, `format=json`, and repeated `ready=` query parameters.
- Tokens are not included in URLs by default. The client opens the socket, sends `Authenticate`, waits for `Authenticated`, then treats `Ready` as usable realtime state.
- `Ping` runs every 20 seconds by default and is configurable for tests. Matching `Pong` events update diagnostics and latency.
- Unexpected transport failures schedule exponential reconnect with jitter. Explicit disconnect, logout, invalid session, and onboarding-not-finished do not reconnect.

## Event Coverage

- Implemented typed decoding for auth/control events, Ready, message events, channel events, server/member/role events, user events, emoji events, and forwarded auth session events.
- `Bulk` events are recursively decoded and public event streams emit each contained event individually.
- Unknown/new valid event types decode as `.unknown(type:raw:)`.
- Deferred source-confirmed event families such as voice, webhooks, reports, slowmodes, and role-rank changes are intentionally not product-modeled in Phase 2.

## Reducer Behavior

- `Ready` hydrates users, servers, channels, members, emojis, user settings, channel unreads, and policy changes.
- Message create/update/append/delete and reactions update per-channel message lists.
- Channel/server/member/user/emoji events update snapshot maps conservatively.
- Typing and ack events update typing sets and unread records.
- State is memory-only and capped per channel. No persistence is written.

## Tests

- Added `StoatRealtimeTests` fixtures for control events, Ready, message/channel/server/member/user/emoji/auth events, unknown events, and malformed JSON.
- Test groups cover event decoding, client event encoding/redaction, WebSocket URL construction, mock transport/client lifecycle, ping/pong diagnostics, reconnect behavior, invalid-session failure, and reducer/store behavior.

Run:

```sh
swift test --package-path Packages/StoatModels
swift test --package-path Packages/StoatAPI
swift test --package-path Packages/StoatRealtime
Scripts/check.sh
```

## Intentionally Deferred

- Production chat UI, login UI, notifications, persistence/cache, voice, live credential tests, markdown rendering, and real WebSocket tests.
- App launch does not open a live WebSocket.
- Query-token authentication is fallback-only and redacted.

## Risks And Uncertainties

- Docs and source differ on `Error` field naming; source/SDK use `data`, so Phase 2 implements `data`.
- Backend includes `voice_states` in Ready and several voice events, but voice is out of scope.
- Partial update payloads are conservatively typed for common fields and retain raw JSON for future expansion.
- Quiet servers can legitimately produce no non-control events, so diagnostics observe ghost-state symptoms without forcing reconnects.

## Recommended Phase 3 Next Step

Use `RealtimeStateStore` as the live hydration source for server/channel/message lists, then add a mock-safe connection status/debug surface before wiring real credential-driven connection controls.
