# Phase 36 - Live Blocker Fixes

Phase 36 fixes the member-list live blocker first, then tightens the related identity, profile, notification, role color, emoji, toolbar, and status paths without changing the existing app architecture.

Sources checked by the Phase 36 plan: `stoatchat/javascript-client-api`, `stoatchat/stoatchat`, and `stoatchat/for-web`.

## Live Blocker Audit

| Area | blocker | verified cause | fix implemented | tests | live QA status |
| --- | --- | --- | --- | --- | --- |
| Member REST | `GET /servers/{id}/members` did not hydrate live members correctly. | Liquid Bagel decoded the route as a bare `[ServerMember]`, while current upstream returns `{ "members": [...], "users": [...] }`. | Added `ServerMembersResponse`, decode diagnostics, explicit `exclude_offline=false`, and user merge into the in-memory snapshot. | API wrapper test, Phase 35/36 member tests | Pending |
| Member panel | Failures could look sticky or vague. | The normal panel had Ready data but lacked response-shape diagnostics and clearer state copy. | Panel keeps Ready members on failure, reports loading/Ready/refreshed/failure, and developer diagnostics show HTTP/status/shape/decode/rate data. | `testPhase36MemberHydrationFailureKeepsReadyMembersAndRecordsAPIShape` | Pending |
| Fetch scope | A complete member fix could accidentally become a launch-wide fetch storm. | Hydration must stay tied to the visible selected server. | Hydration remains right-sidebar/foreground scoped, debounced per server, cancelable, and stale-result guarded. | Phase 35 stale-discard test | Pending |
| Identity merge | REST members alone are not enough when user objects arrive in the wrapper. | User payloads must update the same resolver stores used by messages, members, DMs, Friends, search, notifications, and profiles. | Member wrapper users are merged through `upsertUser`; profile fetch and embedded author paths keep using `UserDisplayResolver`. | Phase 35/36 resolver and member tests | Pending |
| Profile opening | Profile popovers were split across local rows. | Multiple local popovers made click sources harder to reason about. | Message authors, member rows, DM participants, Friends rows, Home current user, and resolvable system events now use one shared profile popover path. | Existing profile/system-event tests | Pending |
| Toolbar | Principal toolbar still had a connection chip/checkmark path. | The title bar should show the current route title, with connection details in settings/diagnostics. | Removed `connectionChip` from the principal toolbar and deleted the stale helper. | Source sweep plus feature build | Pending |
| Notifications | Permission and local notification failures lacked enough app-build detail. | `UNError` codes, before/after settings, bundle/signing/sandbox details, and self-test steps were not recorded together. | Added named `UNError` mapping, build/signing checklist, reset/copy diagnostics, macOS settings opener, and authorized-only local self-test scheduling. | Phase 28 plus Phase 36 notification tests | Pending |
| App Intents noise | `com.apple.linkd.autoShortcut` could be mistaken for app-owned Shortcut code. | Current project inspection found no app-owned `AppIntent` or shortcut implementation. | Document as system/Xcode noise unless a future project source adds App Intents. | Source sweep | N/A |
| Role colors | Colors must not leak into DM/Home contexts. | Role color belongs only to server-context names. | Highest readable role color continues to tint only the display name text in server messages/member rows. DMs/Home/Friends stay uncolored without server context. | Phase 34 role color test | Pending |
| Custom emoji | Picker/rendering needed current-server scoping and bounded media behavior. | Known Ready emojis were available, but current-server filtering and inline rendering needed tighter tests. | Picker groups current/other server emoji, shortcode insert remains explicit, inline/reaction rendering uses bounded `emojis` image loading, and other-server shortcodes do not render in current-server messages. | Phase 33/34/35/36 emoji tests | Pending |
| Status | Status was visible but not editable through the verified route. | Upstream user edit supports `PATCH /users/{currentUserID}` with `status.presence`. | Added `UserEditDraft`, optimistic status update/rollback, `Presence.displayName`, current-user status menu, Busy as `Do Not Disturb`, and Busy/Focus notification suppression. | Phase 36 status suppression test plus API build | Pending |

## Member Root Cause And Fix

The exact member root cause was a response-shape mismatch. Phase 35 had moved member refresh into the normal selected-server panel, but the API client still decoded `GET /servers/{id}/members` as `[ServerMember]`. Current upstream schema/backend return an object wrapper:

```json
{
  "members": [],
  "users": []
}
```

Phase 36 adds `ServerMembersResponse` in `StoatAPI`, decodes the wrapper, attaches redacted request diagnostics, and merges both `members` and `users`. The feature layer preserves Ready members that are absent from a failed or partial REST pass, keeps missing users visible with shortened fallbacks, and invalidates the member grouping cache after successful hydration.

## Diagnostics

Member diagnostics now include method, route, redacted server ID, auth-present state, HTTP status, content type, rate-limit data, response byte count, top-level JSON shape, decoder summary, and error category. Copied diagnostics remain redacted and omit tokens, full IDs, raw response bodies, message content, and local paths.

Notification diagnostics now include permission status, before/after request summary, named `UNError.Code` when available, delegate status, bundle ID, sandbox signal, sanitized app path, self-test result, and reset/copy actions. The self-test requests permission only from the explicit settings action and schedules a local notification only when the resulting status allows delivery.

## Status Behavior

Supported `Presence` values are `Online`, `Idle`, `Focus`, `Busy`, and `Invisible`. UI copy displays `Busy` as `Do Not Disturb`. Status changes call `PATCH /users/{currentUserID}` with `status.presence`, optimistically update the local user, and roll back on API failure.

Notification policy now treats `Busy` as suppress-all and `Focus` as suppress-non-mentions. Mentions still deliver during Focus.

## Privacy And Scope

Phase 36 does not add APNs, background sync, persistent message storage, broad profile fetching, launch-wide member fetching, unverified mutation routes, destructive bulk moderation, or a redesign. Saved-credential auto-connect remains intact. Mock services remain for tests and previews, but normal UI does not expose mock-mode controls.

## Manual QA Checklist

1. Relaunch with a saved production credential and confirm auto-connect.
2. Open a large server channel and confirm the member panel shows Ready rows immediately.
3. Confirm the selected server member refresh runs once, returns full counts, and keeps offline/bot members where returned.
4. Force a member refresh failure if possible and confirm Ready rows remain visible with a non-sticky retry path.
5. Copy developer diagnostics and confirm member API shape/decode data is present and redacted.
6. Open profiles from a message author, member row, DM participant, Friends row, Home current user, and a known system-event actor.
7. Confirm the principal toolbar shows only the route title and no connection chip/checkmark.
8. Open notification settings, run self-test denied and authorized, and verify macOS settings/open/reset/copy behavior.
9. Confirm `com.apple.linkd.autoShortcut` logs do not correspond to app-owned App Intents.
10. Confirm server-context role colors tint only names, while DMs/Home/Friends stay uncolored.
11. Search/insert current-server custom emoji and verify other-server shortcodes do not render in the current server message context.
12. Change status to Online, Idle, Focus, Do Not Disturb, and Invisible; confirm rollback if the API fails.
13. While Busy, confirm notifications suppress. While Focus, confirm non-mentions suppress and mentions deliver.

## Known Risks

- Live member completeness still needs dogfood proof on a large server because the fix is mock-tested plus schema-backed, not live-recorded.
- Ready-preserved members can remain visible if the REST wrapper omits them; later live QA should decide whether omission means unavailable, stale, or permission-filtered.
- Custom emoji syntax is still conservative. `:name:` rendering is supported for known current-server emoji, but exact official autocomplete parity is not claimed.
- Notification diagnostics can identify common macOS configuration problems, but native delivery still depends on signing, bundle identity, system settings, and user authorization.

## Phase 37 Recommendation

Run a live QA pass on one large server, one bot-heavy server, one emoji-heavy server, and one account with macOS notifications denied/authorized. Phase 37 should reconcile any observed REST/Ready member drift, record live status PATCH behavior, and only then move parity rows from partial to done.
