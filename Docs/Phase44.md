# Phase 44 - Core Chat Interaction and Navigation Parity Recovery

Phase 44 recovers high-visibility chat interaction parity without broadening Liquid Bagel beyond verified routes. It focuses on reply previews, pinned-message navigation, search/jump unification, typing indicators, read ack/unreads, notification click routing, mutes, active-channel suppression, and redacted diagnostics.

## Verified Route Boundaries

Implemented behavior uses only routes already present in the checkout:

- `fetchMessage(channelID:messageID:)` for reply reference resolution through the existing resolver.
- `fetchMessages(channelID: options:)` with `nearby` for around-message navigation.
- `searchMessages(channelID: request:)` for selected-channel remote search and pinned-message listing.
- `ackChannel(channelID:messageID:)` for foreground read acknowledgements.
- `pinMessage` and `unpinMessage` for message pin actions.

Global/server search and server-wide cloud mute remain blocked/deferred until a verified route or schema exists.

## Implementation Summary

- Added `Phase44Runtime.swift` with message navigation, reply preview, pinned-message, typing, target-highlight, and diagnostics value types.
- Added a unified message navigation path for loaded search results, remote search results, pinned rows, reply previews, unread/command jumps, and notification clicks.
- Added bounded target highlighting with no repeated scroll when the target is already visible.
- Reply previews now render from pure state and enqueue reference resolution from row visibility, not SwiftUI body construction.
- Reply composer state clears after successful send and persists after failed send.
- Added an explicit pinned-message sheet that fetches selected-channel pinned messages only when opened/refreshed.
- Pinned rows use Phase 43 display resolution, safe summaries, timestamps, jump navigation, and deduped unpin actions.
- Selected-channel search includes `include_users` and result clicks route through the unified coordinator.
- Typing indicators use `TypingIndicatorState`, exclude the current user, coalesce names, and expire stale entries.
- Foreground ack is per-channel deduped; live local unread clear happens after successful ack.
- Notification click routing now calls the unified coordinator and degrades to channel selection when message-level navigation is unavailable.
- Mute/suppression decisions are counted and remain local per-channel/DM preferences unless official cloud scope is verified.

## Diagnostics

Developer Verification includes `Phase 44 Chat Interaction Diagnostics`.

Counters cover:

- reply preview resolution and composer transitions
- pinned list request/result/action and pinned jumps
- local/remote search result buckets
- navigation sources, loaded/unloaded/unavailable/degraded results, and highlights
- typing active-user buckets and stale cleanup
- ack requested/sent/deduped/failed and unread clear sources
- notification queued/replayed/degraded routing
- mute/suppression decisions
- elapsed duration buckets for slow operations

Copied diagnostics run through the existing redaction pipeline and redact session tokens, raw payloads, full IDs, URLs, local paths, emails, password-like strings, MFA values, private message content beyond short summaries, and Phase 42 moderation reason text.

## Blocked Or Deferred Scope

- No global/server search without a verified route.
- No server-wide cloud mute without a verified source of truth.
- No persistent offline message database.
- No APNs/background push.
- No voice, video, screen share, audit logs, bots dashboard, server deletion, or account deletion.
- No parity rows are marked done without live QA.

## Manual QA Checklist

### Reply QA

- [ ] Send a message replying to a loaded message.
- [ ] Confirm reply preview shows the correct user name/avatar.
- [ ] Click reply preview and confirm the original message is highlighted.
- [ ] Reply to a message that is not currently loaded, then reload/open context.
- [ ] Confirm unavailable/deleted reply targets do not break the row.
- [ ] Confirm no full raw IDs appear.

### Pins QA

- [ ] Pin a normal message.
- [ ] Open pinned messages surface.
- [ ] Click pinned message and confirm jump/highlight.
- [ ] Unpin message.
- [ ] Confirm local state updates.
- [ ] Try pin/unpin during network failure and confirm no local corruption.

### Search/jump QA

- [ ] Search loaded messages.
- [ ] Search an unloaded/older message if remote search is available.
- [ ] Open a search result.
- [ ] Confirm target message is highlighted.
- [ ] Try result for inaccessible/deleted message if possible.
- [ ] Confirm graceful fallback.

### Typing QA

- [ ] Type from another account in a server channel.
- [ ] Type from another account in a DM.
- [ ] Type from multiple accounts if possible.
- [ ] Confirm stale indicator clears.
- [ ] Switch channels and confirm old typing indicator disappears.

### Ack/unread QA

- [ ] Receive unread server message.
- [ ] Open channel and confirm unread clears.
- [ ] Receive unread DM.
- [ ] Open DM and confirm unread clears.
- [ ] Confirm no repeated ack storm in diagnostics.
- [ ] Confirm active conversation does not create notifications.

### Notification/mute QA

- [ ] Enable notifications in a signed/dev build where available.
- [ ] Receive notification for inactive channel.
- [ ] Click notification and confirm route.
- [ ] If target message is known, confirm message-level jump or safe channel fallback.
- [ ] Mute a channel and confirm notification suppression.
- [ ] Test Busy/Focus behavior.
- [ ] Test active DM suppression.

### Regression QA

- [ ] Open member context menus repeatedly; confirm no freeze.
- [ ] Kick/ban a test user if Phase 42 QA account is available; confirm Phase 43 identity/system-event behavior still works.
- [ ] Open profiles from messages, member rows, DMs, search results, replies, pinned messages, and system events.
- [ ] Copy Developer Verification diagnostics and confirm redaction.
