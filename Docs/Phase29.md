# Phase 29 - Regression Repair

Phase 29 fixes dogfood-visible regressions from the Phase 28 stabilization pass. The app remains live-first but manual: no auto-connect, no auto-validation of saved credentials, no hidden DM/member/profile refresh, no background sync, no APNs registration, and no persistent message cache.

## Regression Audit

| Issue | Observed problem | Root cause found | Fix implemented | Tests added | Manual QA |
| --- | --- | --- | --- | --- | --- |
| Duplicate member/sidebar controls | Top app toolbar and channel header both exposed the same member-panel toggle. | The shell toolbar and chat header both routed to `toggleMemberPanel()`. | Kept the contextual chat-header toggle with `Show Members` / `Hide Members`; removed the duplicate top toolbar toggle. | Phase 29 UI coverage through command/context regression tests. | Confirm only one visible member-panel toggle in chat. |
| Sparse member list | Missing/offline members could be hard to distinguish from dropped rows. | Diagnostics only reported rendered totals, while user hydration and member counts were separate. | Member derivation keeps missing-user members, removes all-user fallback counts, and records known/rendered/dropped counts. | `testPhase29MemberDiagnosticsKeepMissingAndOfflineMembers`. | Open a large server and confirm missing/offline members still appear. |
| DMs do not load reliably | DM route state could be obscured by stale server/channel IDs or missing participant hydration. | Active conversation helpers used `channelID ?? dmChannelID`, and DM lookup matched only hydrated participants. | Added `selectedConversationChannelID`, recipient-based DM matching, and `DMRouteDiagnostics`. | `testPhase29DirectMessageSelectionLoadsAndSendUsesDMChannel`, `testPhase29OpenDirectMessageMatchesRecipientWhenUserIsMissing`, `testPhase29SelectedConversationPrefersDMInDMSpace`. | Click direct/group/saved DMs and confirm timeline, composer, send target, and participants. |
| Persistent send success status | Sending a message left a “Message sent.” overlay near the composer. | `sendDraft` set `messageActionStatus` on success. | Success now clears composer silently and records only developer diagnostics; failures remain visible. | Updated send success coverage. | Send a channel message and DM; confirm no persistent success toast appears. |
| Duplicate Add Friend entry | DM sidebar included an Add Friend row in addition to Friends controls. | The DM sidebar treated Add Friend like a route row. | Removed the sidebar row; Friends view keeps a top Add Friend action. | Covered by UI structure and route tests. | Open Direct Messages/Friends and confirm Add Friend is only a top action. |
| Vague system events | Join/leave events could show “Someone joined/left.” | Presenter resolved only `usersByID` and did not use member nickname or safe missing-user fallback. | System events resolve member nickname, display name, username, then `User <short id>`. | `testPhase29SystemEventsUseMemberNamesAndSafeFallbacks`. | Open join/leave events and confirm names appear when available. |
| Raw ID/avatar fallback | Missing users could still surface as raw IDs or block avatars. | Some paths did not share member-aware display resolution. | System/member/DM paths use the shared resolver; missing avatars fall back to initials. | Display/member/DM tests. | Open affected member rows, DMs, and system events. |
| Timeline diagnostics in chat | Developer timeline diagnostics rendered at the end of normal chat. | `MessageTimelineView` always appended `timelineDiagnosticsView` when developer controls were enabled. | Removed timeline diagnostics from chat; added Developer Diagnostics in the account/verification sheet. | Developer diagnostics and no-chat diagnostics are covered by Phase 29 tests and previews. | Confirm no Timeline Diagnostics card appears in chat; copy diagnostics from Developer Verification. |
| Missing channel context menu | Right-clicking channels showed an old Phase 3 placeholder. | `ChannelRow` owned a stale generic context menu. | Removed the placeholder and added feature-layer channel menu items for Channel Settings, Create Channel, developer Copy Channel ID, and confirmation-gated Delete. | `testPhase29ChannelContextMenuContainsSettingsAndDeveloperActions`. | Right-click a channel and open Channel Settings. |
| Composer too tall | Empty composer started at the previous large max height. | The input frame fixed min/max around a text view without compact height rules. | Added compact/growing/capped composer sizing and internal scrolling at max height. | `testPhase29ComposerTextSizingStartsCompactAndGrows`. | Type one-line, multiline, and long messages; confirm height grows then caps. |
| Notification permission follow-up | Permission flow needed another regression check. | Phase 28 behavior was correct but needed to remain explicit. | Kept real live authorizer injection and mock-only tests/previews; no launch prompt added. | Existing Phase 28 notification permission test remains. | Open Notification Settings, request/refresh/test explicitly. |

## Diagnostics And Privacy

- Normal chat no longer renders timeline diagnostics.
- Developer Verification includes timeline, DM route, member list, send, and notification diagnostics.
- Copied diagnostics use existing redaction helpers and omit tokens, raw response bodies, message content, raw local file paths, and raw session IDs.
- DM diagnostics report channel IDs in shortened form for copied output and state/count summaries only.

## Performance Guardrails

- Member rows and timeline rows remain lazy-rendered.
- Avatar loading remains visible/selected-context bounded.
- Ready hydration now tolerates duplicate keyed objects by keeping the last value instead of crashing.
- No hidden member/profile/DM fetch storm was added.

## Tests Added

- DM selection/load/send routing, missing participant matching, and stale-ID conversation selection.
- Member list completeness and diagnostics with missing/offline members.
- System event nickname and safe fallback rendering.
- Channel context menu model.
- Composer compact/growing/capped sizing.
- Ready hydration duplicate member/user handling.
- Send success no longer sets persistent status.

## Manual Live QA Checklist

1. Launch app.
2. Confirm no auto-connect or auto-validation.
3. Validate saved session manually.
4. Connect manually.
5. Confirm only one visible member/sidebar toggle exists in chat.
6. Open a server with several roles/members.
7. Confirm all known members appear, including offline and missing-user fallback rows.
8. Confirm missing users hydrate to names/avatars when data appears.
9. Click multiple DM rows.
10. Confirm each DM loads messages.
11. Send a DM.
12. Confirm no persistent “Message sent.” toast remains.
13. Open Friends.
14. Confirm Add Friend is available as the top action, not a DM sidebar row.
15. Open a channel with join/leave events.
16. Confirm events show specific users when available.
17. Confirm no Timeline Diagnostics card appears in chat.
18. Open Developer Verification from the runtime chip.
19. Confirm diagnostics are available there and copy redacted output.
20. Right-click a channel.
21. Open Channel Settings from the context menu.
22. Confirm normal left-click still switches channels.
23. Type a one-line composer message.
24. Confirm composer starts compact.
25. Type multiline text.
26. Confirm composer grows up to max height.
27. Confirm long text scrolls internally.
28. Open Notification Settings.
29. Confirm Request Permission and troubleshooting copy.
30. Relaunch.
31. Confirm no auto-connect or auto-validation happened.

## Deferred

- No hidden live member/profile backfill was added.
- No new parity surface was added.
- Voice/video, bot management, server deletion, audit logs, full moderation, and global search expansion remain deferred.

## Verification

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

## Recommended Phase 30

After Phase 29 live QA, use Phase 30 for the next verified parity area only if DMs, member hydration, diagnostics relocation, channel context menus, notification settings, and composer sizing remain stable in daily use.
