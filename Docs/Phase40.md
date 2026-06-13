# Phase 40: DM Conversation Parity Recovery

## Summary

Phase 40 recovers direct-message reliability without replacing the existing conversation spine. `ActiveConversation`, `selectedConversationChannelID`, and the channel-based message pipeline remain the source of selection, message loading, sending, editing, deleting, reactions, attachments, read ack, and notification routing.

The phase adds explicit DM refresh/open behavior, merge-by-channel-ID recovery, stable Home/sidebar presentation for Saved Notes, direct messages, and existing group DMs, and developer diagnostics that can prove what the app knows without leaking sensitive data.

No live QA was performed during implementation, so the parity matrix moves Core chat / DMs only from `broken` to `partial`.

## DM Route And Source Findings

Verified project research continues to be the route source of truth:

- `GET /users/dms` returns direct-message and group-DM channels for the current user.
- `GET /users/{target}/dm` opens or returns a DM with a user. Generated API notes say targeting self returns a Saved Messages channel.
- Existing message routes for load, send, edit, delete, reactions, attachments, previews/downloads, and channel ack are channel-ID based and already work for channels outside server text when not blocked by UI assumptions.
- Realtime Ready may include users, channels, and channel unreads. Those Ready channels must remain usable even if an explicit DM refresh later fails.
- Liquid Bagel still avoids hidden DM/profile/friend fetch storms on launch. DM refresh and open are user-visible explicit actions.

No verified route/schema was found for new group-DM creation that is safe to add in Phase 40.

## Architecture Changes

Phase 40 adds `Phase40Runtime` types for DM source/status diagnostics:

- `DMRefreshSource` and `DMOpenSource`
- safe operation statuses and error categories
- `SavedNotesChannelState`
- `DMChannelMergeResult`
- `DMDiagnostics`
- redacted `DMDiagnosticsFormatter`

`MainShellViewModel` now owns one DM merge path:

- Channels are upserted by channel ID.
- Duplicate merges are counted diagnostically, not rendered as duplicate conversations.
- Ready/current channels are preserved on refresh failure.
- Existing snapshot users remain the shared resolver input for message rows, profile popovers, notifications, Friends, member rows, and DM rows.
- Missing recipient-user and raw-ID fallback counts are recomputed from the central snapshot.

The notification badge calculation now treats a verified local DM ack clear as authoritative over stale Ready unread fields for that channel.

## Home And DM Sidebar Behavior

Home and the sidebar now render DMs as native, stable conversation rows:

- `Saved Notes` entry appears when the account exposes a saved channel. If it is unknown or unavailable, the UI shows an explicit open/refresh affordance instead of fabricating a live channel.
- Direct Messages show resolved recipient name, avatar/status data through the central resolver, unread and mention counts, muted state, and selected state.
- Existing Group DMs show safe group name, icon data when present, member count, unread and mention counts, muted state, and selected state.
- Normal UI avoids raw IDs. Unknown recipient fallback copy is human-readable and counted in diagnostics.
- Empty, refresh, loading, and error/retry states are visible on Home/DM surfaces.

The user-facing copy is standardized to `Saved Notes` in the Home entry, member/sidebar title, composer-adjacent derivation, and top-bar title behavior.

## Open-DM Flow

`openDirectMessage(with:source:forceNetwork:)` is now the shared path for DM entry points:

- Friends row message buttons use `.friendsRow`.
- Profile popover message actions use `.profilePopover`.
- Member row/profile actions use `.memberRow`.
- Search/profile results can use `.searchResult` where available.
- Saved Notes uses the same path with the current user and `.savedNotes`.
- Notification recovery can force explicit refresh/open behavior with `.notification`.

Known direct/saved conversations are selected without network unless `forceNetwork` is requested. REST-returned channels are merged by ID, selected, and left to the existing selected-channel timeline pipeline to load messages.

Rapid duplicate opens for the same user ID are coalesced by an in-flight target set so double-clicks do not create duplicate REST work or duplicate conversations.

## Saved Notes Behavior

Liquid Bagel uses the current project copy, `Saved Notes`, for the self-DM/Saved Messages surface.

If Ready or `GET /users/{target}/dm` exposes a saved channel, the Home entry routes to it and the normal message pipeline supports load/send/edit/delete/reaction/attachment/ack operations by channel ID. If the account/API does not expose a saved channel, the UI records a recoverable unavailable state and offers explicit open/refresh rather than inventing a channel.

## Group DM Behavior

Existing group DMs from Ready or explicit DM refresh now display and route in the same conversation list as direct messages. The row renders group icon data when present, a safe display name, and member count from recipients.

Message load/send/edit/delete/reaction/attachment/ack flows continue through the shared channel pipeline. Creating new group DMs remains deferred because Phase 40 did not verify a safe route/schema.

Voice and call affordances remain out of scope.

## Notifications

DM notification routing is hardened:

- If a DM notification click arrives before live connection/Ready, it remains queued.
- Once Ready is available, known DM channels are selected and target-message loading is requested when possible.
- If a connected/Ready app receives a DM notification for an unknown DM channel, it performs one explicit notification-sourced DM refresh before deciding the route is unavailable.
- Active DM suppression uses `selectedConversationChannelID`.
- DM unread/mention state continues to feed in-app notifications and dock badge counts.

The Phase 40 tests exercise routing and suppression without requiring APNs.

## Diagnostics

Developer Verification includes a DM diagnostics section when developer runtime controls are enabled:

- known direct DM count
- known group DM count
- Saved Notes state
- last DM refresh status, source, count, duration, and safe error category
- last open-DM status, source, and safe error category
- duplicate merge count
- missing recipient/user count
- raw-ID fallback count
- unread/ack summary
- accumulated safe error categories
- `Copy DM Diagnostics`

The copied text uses existing redaction conventions and excludes tokens, raw response bodies, full session IDs, local paths, URLs, and full user/channel IDs.

## Tests

Focused Phase 40 tests were added in `StoatFeaturesTests` for:

- Ready DirectMessage channels appearing in Home conversations
- `GET /users/dms` refresh merging channels/users without duplicates
- refresh failure preserving Ready DM channels
- known-DM open selecting without network
- REST open merging and selecting a new DM
- rapid duplicate open-DM calls coalescing
- Friends/profile/member actions using the same open-DM path
- Saved Notes resolving/routing and unavailable-state recovery
- existing group-DM row rendering name/icon/member count and routing
- DM timeline load/send/edit/delete/reaction/attachment paths using the shared pipeline
- DM ack clearing unread/mentions locally after verified ack
- DM notification route queuing until Ready and then selecting channel/message
- active DM notification suppression by active conversation ID
- diagnostics redaction for IDs/tokens/raw bodies/paths
- parity matrix regression preventing DMs from becoming `done` without live QA

API route tests for `/users/dms` and `/users/{target}/dm` remain unchanged because Phase 40 kept the verified wire shapes as `Channel` and `[Channel]`.

## Manual QA Checklist

1. Connect with a real account.
2. Confirm Home shows existing DMs.
3. Refresh DMs and confirm the list preserves existing entries while updating.
4. Open a DM from Friends.
5. Open a DM from a profile popover.
6. Open a DM from a member row.
7. Send, edit, delete, and react in a DM.
8. Upload an attachment in a DM.
9. Confirm read ack clears unread state.
10. Receive a DM notification while the DM is not active.
11. Click a DM notification and confirm routing to the channel/message.
12. Confirm the active DM suppresses in-app/local notification.
13. Open Saved Notes and send a message if the account exposes it.
14. Open an existing Group DM, load messages, and send.
15. Copy DM diagnostics and confirm the copy is redacted.

## Deferrals

- Marking DMs `done` is deferred until live QA proves list/load/send/attachments/participants.
- Saved Notes and Group DMs remain `partial` without live QA.
- New group-DM creation is deferred until the route/schema is verified and mock-tested safely.
- Voice, video, screen share, APNs/background push, and persistent offline cache remain unchanged.

## Recommended Phase 41

Run a live DM dogfood pass with a real account and capture evidence for:

- DM list refresh against production
- existing and newly opened direct DMs
- Saved Notes availability and send behavior
- existing group DM load/send behavior
- attachment upload/preview/download in DMs
- participant/avatar/status resolution
- notification receive, click route, and active suppression
- redacted Developer Verification diagnostics

If live QA exposes missing participant or user payloads, Phase 41 should add a verified participant/user hydration route rather than guessing an unverified wrapper schema.
