# Phase 37 - Post-Member-Breakthrough Correctness

Phase 37 follows the Phase 36 member-wrapper fix with a focused correctness, UX, and profiling pass. The existing SwiftPM package layout, shell view model, resolver, member derivation, profile flow, notification service, mock services, and bounded media queue remain in place.

## Live Correctness Audit

| issue | observed live behavior | suspected cause | root cause found | fix implemented | tests added | live QA step | remaining risk |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Member order did not match native hierarchy | Members appeared after Phase 36, but group order could follow dictionary/hoist-only behavior. | `MemberListDeriver` grouped only hoisted roles and lacked hierarchy diagnostics. | Role grouping did not consistently choose each member's highest displayable role or report sort mode. | `MemberListDeriver.result` now groups each member once by owner/highest role, role rank, admin/manager fallback, bot/status/offline/unknown fallback, with counts and duration diagnostics. | `testPhase37MemberOrderingHighestRoleColorAndDMIsolation` | Open a large server and compare admin/manager/high roles against native ordering. | Rank semantics still need live confirmation if upstream rank direction differs. |
| Role colors were not the name color everywhere | Some surfaces showed role chips or uncolored names. | Role color lived too close to view styling instead of the display model. | `ResolvedUserDisplay` did not carry server-context role color/diagnostics. | Resolver now returns optional role color, diagnostics, and server context; message authors, member rows, profile names, system events, search/moderation rows use it where a server exists. | `testPhase37MemberOrderingHighestRoleColorAndDMIsolation` | Check colored-role users in messages, member list, profile, search, and system events. | Live contrast/readability still needs light/dark QA. |
| DM/Home/Friends color leakage risk | Server role colors could accidentally be reused outside server context. | Display calls did not distinguish global and server display strongly enough. | No central uncolored/global overload contract. | Server contexts pass `server`; DMs/Home/Friends/global profile paths pass no server and resolve uncolored. | `testPhase37MemberOrderingHighestRoleColorAndDMIsolation` | Open DMs after a colored server channel and confirm no stale tint. | Future call sites must keep passing explicit context. |
| Avatar/username bugs reduced but still visible | Some rows could still show weak identity after partial hydration. | Merge paths and visible diagnostics were too coarse. | Member wrapper/profile fetch/user/member update invalidation was inconsistent. | User/member/profile merges invalidate display caches, update profile context, and report visible unresolved users, shortened IDs, avatar failed cache, profile merges, and member-wrapper user merges. | `testPhase37IdentityFreezeMarkdownAndImageSafeModeDiagnostics` | Open old raw-ID cases before and after member/profile hydration. | Missing upstream user payloads still require shortened fallback. |
| Random freeze remained hard to diagnose | Media/member-heavy screens could lock up without actionable counters. | Image queue diagnostics existed, but derivation/Markdown/timeline diagnostics were too coarse. | Member grouping and Markdown cache hits, diagnostics publish count, and queue saturation were not surfaced together. | Added `FreezePerformanceDiagnostics`, member grouping cache/duration counts, Markdown cache diagnostics, image kind counters, visible range counts, read/status-loop markers, and media safe-mode flag. | `testPhase37IdentityFreezeMarkdownAndImageSafeModeDiagnostics` | Scroll media-heavy and member-heavy screens while watching Developer Settings counters. | This adds visibility and guardrails; a remaining hang may still require live stack sampling. |
| Profile popover was too simple | Profile opened from several places but did not feel native-card complete. | Profile presentation context was implicit and split between views. | The card did not carry open source, server role color, mutuals, bot owner, or explicit fetch-on-open state as one model. | Added `ProfilePresentationContext` and a native Liquid Glass profile card with banner/avatar/status, role-colored name, handle, actions, Markdown bio, roles, bot owner, and Profile/Mutual Groups/Mutual Servers tabs. | `testPhase37ProfileContextNotificationReadinessAndTopBarTitle` | Open profile from message avatar/name and member rows. | Action parity remains permission/route-gated. |
| Notification permission prompt did not appear | Debug app did not reliably trigger the native macOS prompt. | Unsigned/unstable bundle builds can confuse notification registration. | Project inspection found `CODE_SIGNING_ALLOWED = NO` for checked Xcode build settings. | Replaced one-line checklist with structured build-readiness diagnostics; requests remain explicit and self-test remains authorized-only. | `testPhase37ProfileContextNotificationReadinessAndTopBarTitle` | Compare debug build and signed stable build behavior in System Settings. | Prompt reliability cannot be claimed fixed until signed-build QA passes. |
| Principal top bar checkmark risk | A connection chip/checkmark had previously appeared in the principal title area. | Normal UI carried connection state too prominently. | Principal toolbar is route title only; the remaining checkmark symbols are save/confirm controls outside the principal title. | Top bar remains title-only; connection/security detail stays in settings/developer diagnostics. | `testPhase37ProfileContextNotificationReadinessAndTopBarTitle` | Confirm no checkmark beside title in server, DM, Home, Friends. | Future title changes should keep status out of normal principal UI. |
| Status regression risk | Phase 36 status support needed recheck. | Profile/member surfaces changed. | Status indicators needed to stay resolver/profile-friendly. | Existing current-user menu, Online/Idle/Focus/Do Not Disturb/Invisible display, optimistic rollback, and Busy/Focus notification suppression remain intact; profile and member rows render status from the same user data. | Existing Phase 36 status tests plus Phase 37 profile test | Right-click current user avatar and change each status in live QA. | Invisible/server read semantics remain dependent on verified API behavior. |

## Member Ordering Behavior

Member sections are derived through `MemberListDeriver.result`. Each member is emitted at most once. Owners are grouped first when modeled, then members are grouped by their highest displayable role. Role ordering prefers explicit `rank` descending, then admin/manager-like permissions or names, then localized role name, then role ID. Remaining members fall into bot, online, idle/focus/DND, offline, and unknown fallback groups.

Diagnostics report role sort mode, group order, member counts per group, duplicate suppression count, unknown role count, cache hits, and grouping duration. Member rows remain lazy through the existing `LazyVStack` panel.

## Role Color On Names

`ResolvedUserDisplay` now carries optional `roleColor`, `roleColorDiagnostics`, and `serverContextID`. The role color is selected from the highest applicable colored role in the current server context and invalid role colors are rejected. Server-context names tint the display name text itself for message authors, member rows, profile names, system-event actors, search results, and member moderation surfaces.

DMs, Home, Friends, and global profile displays call the resolver without a server context and stay uncolored. High contrast mode uses the safer uncolored fallback.

## Identity And Avatar Cleanup

Embedded message users, REST member-wrapper users, profile fetches, realtime user updates, and member updates now invalidate display/member caches. Visible identity diagnostics include unresolved visible user count, shortened-ID count, avatar failure cache count, profile merge count, and member wrapper user merge count. Developer Settings includes a copy action for the visible identity diagnostics.

Fallbacks continue to shorten raw IDs, show initials/color avatars, and suppress infinite failed-avatar retry loops.

## Freeze Profiling And Guardrails

Developer-only freeze diagnostics include the latest long-operation marker, timeline render/update counts, member grouping count/duration/cache hits, Markdown parse/cache counts, image/avatar/custom-emoji/profile-media active and queued counters, visible range update count, diagnostics publish count, read-ack/status-loop suspicion, and media safe-mode state.

Markdown rendering uses an in-memory block cache keyed by source/revision. Member grouping uses an in-memory cache keyed by server/member/role/user state. Image resources report kind-specific counts and enter media safe mode when the queue saturates, causing nonessential previews to show placeholders instead of starting more background work. Original/full-size media remains explicit only.

## Native Profile Popover

`ProfilePresentationContext` carries user ID, optional server ID, open source, local display model, role list, relationship/action availability, known mutual groups/servers, and bot owner when modeled. `showUserProfile` opens immediately with local data and starts one explicit fetch-on-open task.

The profile card is a native macOS popover with adaptive material styling, optional banner, overlapping avatar/status, role-colored display name in server context, username/discriminator line, status/custom status, action buttons, and segmented Profile/Mutual Groups/Mutual Servers tabs. Profile content renders safe cached Markdown. Avatar and banner media use the bounded image queue and do not request originals.

Profile entry points now include message author/avatar/name, member sidebar rows, DM participant rows, friend rows, Home current user, and resolvable system event actors.

## Notification Build Readiness

Notification permission remains explicit only; no launch request was added. The notification settings panel now shows a structured readiness checklist:

- Bundle identifier
- Bundle display name
- App path
- Xcode code-signing setting
- Detected signature status where safe
- Sandbox entitlement signal
- Notification delegate status
- Last `UNError` name
- Before/after authorization status
- System Settings manual-check text
- "I am testing a signed build" metadata toggle

The checked project settings currently include `CODE_SIGNING_ALLOWED = NO`, bundle ID `com.bagel.LiquidBagel`, display name `Liquid Bagel`, and a sandbox entitlement. Unsigned/debug builds may fail to prompt reliably, unstable bundle IDs can confuse macOS notification registration, and stale System Settings entries may need removal or reset. The parity row remains partial until signed/stable build QA proves prompt behavior.

## Top Bar Cleanup

The principal toolbar shows only the current route title. Connection/security details remain in Settings or Developer diagnostics. A source sweep found remaining checkmark SF Symbols only in save/confirm controls, not the principal title model.

## Status Regression Check

The current-user avatar keeps the context menu/status path. Supported statuses remain Online, Idle, Focus, Do Not Disturb (`Busy` API value), and Invisible. Status changes use the verified user edit route, optimistically update local state, and roll back on failure. Busy suppresses notifications and Focus suppresses non-mentions.

## Diagnostics Behavior

Diagnostics added or expanded in Phase 37 are developer-facing and redacted:

- Role sorting and role-color source/fallback reasons
- Visible identity unresolved/shortened/merge/avatar-failure counts
- Freeze/performance counters
- Markdown cache counters
- Image kind counters and media safe-mode state
- Notification build-readiness bundle

Normal chat, Home, DMs, Friends, and member list surfaces do not expose mock mode or raw diagnostic dumps.

## Security And Privacy

Phase 37 does not add APNs, push registration, background sync, persistent message databases/caches, voice/video, screen share, bot dashboards, server deletion, destructive bulk moderation, speculative mutation routes, or hidden prefetching. Profile fetch remains explicit-on-open. Member hydration remains selected-server foreground work. Notification prompts remain user-initiated.

## Tests Added

- Phase 37 member ordering, highest-role grouping, bot/offline/unknown fallback, stable cache behavior, role color, invalid/high-contrast fallback, and DM color isolation.
- Phase 37 profile presentation context, bot owner, local immediate profile data, fetch-on-open diagnostics, notification readiness fields, and top-bar title cleanup.
- Phase 37 visible identity diagnostics, Markdown cache diagnostics, member grouping cache hit, image safe mode, and bounded profile media loading.

Existing Phase 32-36 tests continue to cover auto-connect, no normal mock UI, member wrapper hydration, custom emoji, explicit remote search, 20 MB upload limit, clipboard paste review, status suppression, and notification authorization gating.

## Deferred

- Live proof that member rank direction matches upstream native ordering.
- Signed/stable app notification prompt QA.
- Full profile edit/banner/avatar mutation routes.
- Rich custom status editing.
- Persistent thumbnail/message cache.
- Global/server search parity.
- Exact official custom emoji autocomplete syntax.

## Known Risks And Limitations

- Mock tests prove derivation and UI state, not live server parity.
- A remaining random hang may require Instruments or live stack sampling now that app-level freeze counters exist.
- Missing upstream user/member/profile payloads still fall back to shortened IDs and initials.
- Notification System Settings visibility cannot be reliably detected from sandboxed code, so the app provides a manual check plus copyable diagnostics.

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

## Manual Live QA Checklist

1. Launch app with saved credential.
2. Confirm auto-connect still works.
3. Open a large server.
4. Confirm member list appears.
5. Confirm member list is ordered by role hierarchy like native app.
6. Confirm admins/managers/high roles appear before ordinary members.
7. Confirm offline/bot/fallback groups appear in sensible order.
8. Confirm role color applies to names themselves.
9. Open a server channel with colored-role users.
10. Confirm message author names use role colors.
11. Open a DM.
12. Confirm DM names are not incorrectly colored by stale server role context.
13. Open messages that previously showed raw IDs.
14. Confirm names/avatars render or fallback cleanly.
15. Open a member-heavy server and scroll member list.
16. Confirm no freeze.
17. Open media-heavy channel and scroll quickly.
18. Confirm no freeze.
19. Click message author avatar.
20. Confirm profile popover opens.
21. Click message author name.
22. Confirm profile popover opens.
23. Click member sidebar row.
24. Confirm profile popover opens.
25. Confirm profile shows banner/avatar/status/bio/roles/actions where available.
26. Confirm profile bio Markdown renders.
27. Confirm bot profile shows bot owner if available.
28. Open Notification Settings.
29. Confirm build-readiness diagnostics are clear.
30. Test notification request in debug build and document result.
31. Test notification request in signed/stable build if available and document result.
32. Confirm top bar has no checkmark.
33. Right-click current user avatar below Home.
34. Confirm status menu works.
35. Change status if verified.
36. Confirm status appears in member list/profile/current user area.
37. Relaunch.
38. Confirm auto-connect still works and no mock UI appears.

## Recommended Phase 38

Run the manual live QA checklist on a large role-heavy server, a bot-heavy server, a media-heavy channel, and a signed/stable installed build. Use the new freeze diagnostics and notification readiness bundle to decide whether Phase 38 should focus on a live hang root cause, signed-build notification delivery, or final member/role parity polish.
