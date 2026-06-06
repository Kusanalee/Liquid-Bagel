# Phase 34 - Member List, Role Colors, Custom Emoji, And Home Cleanup

Phase 34 fixes the visible blocker bugs left after Phase 33 without replacing the app architecture. The work stays on the existing `ActiveConversation`, `MemberListDeriver`, resolver, composer, and Developer Settings surfaces.

## Live Bug Audit

| Area | Observed problem | Root cause found | Fix implemented | Tests added | Live QA step |
| --- | --- | --- | --- | --- | --- |
| Right sidebar | Home/Friends/Discover could show a server-style Members panel. | `MainShellView` rendered `MemberPanelView` whenever the persisted member-panel preference was true. | Added `RightSidebarContext` from `ActiveConversation`; Home/Friends/Discover hide the right sidebar by default. | `testPhase34RightSidebarContextTracksRouteWithoutStaleMembers` | Open Home, Friends, Discover, server channel, and DM; verify the panel changes correctly. |
| Member list source | Member panel could use stale server selection and feel incomplete. | `MemberPanelView` asked for members through `selection.serverID` instead of an explicit sidebar context. | Server members now use `.serverMembers(serverID:channelID:)`; DMs use participant contexts; diagnostics report known/rendered/missing counts. | Phase 28/29 member tests plus `testPhase34MemberDiagnosticsReportMissingAvatarsWithoutDroppingMembers` | Open a large server and compare Developer Settings counts against expected Ready/member state. |
| Manual member refresh | There was no explicit way to request the verified member REST list. | The API client did not expose `GET /servers/{id}/members`. | Added `fetchServerMembers(serverID:)` and a Developer Settings Refresh Members action; it never runs on launch or panel open. | API endpoint request assertion | In a server channel, open Developer Settings and click Refresh Members. |
| Role colors | Role colors appeared as chips/labels rather than coloring names consistently. | `ResolvedRoleColor` existed but was not resolved/applied across server-context names. | Added `RoleColorResolver`; highest ranked valid colored role tints member, message author, and server-context profile display names; high contrast falls back. | `testPhase34HighestRoleColorAppliesToServerMessageButNotDM` | Inspect member rows, message author rows, and profiles in light/dark/high-contrast. |
| Emoji button | The composer emoji affordance could appear to do nothing. | The control was a menu/grid presentation with no explicit visible picker state. | Replaced it with an explicit popover that always shows a picker or disabled reason. | Existing insertion tests plus Phase 34 custom emoji insertion test | Click the composer emoji button with and without custom emoji data. |
| Custom emoji | Ready emoji could be modeled but not visibly useful enough. | Reactions resolved custom emoji, but message content had no custom emoji render hook. | Picker includes server emoji shortcodes; insertion appends `:name:`; reactions and known message shortcodes resolve through bounded `emojis` media loading; unknowns remain text. | `testPhase34CustomEmojiInsertionAndInlineResolverUseReadyEmoji` | Insert a server custom emoji and view known custom emoji reactions/messages. |
| Home | Home felt like a debug dashboard with repeated actions. | Home embedded a compact Friends surface and multiple cards/actions. | Home now shows compact identity/status, recent DMs, friend summary, and one action row. | Sidebar/context tests cover no Members panel; visual preview added | Open Home signed out, connected, and with no DMs/friends. |
| Diagnostics | Member/sidebar/emoji diagnostics needed to stay out of normal UI. | Normal member/sidebar empty states were doing too much explanatory work. | Diagnostics live in Developer Settings only and remain redacted. | Existing redaction tests plus Phase 34 diagnostics assertions | Confirm normal chat/Home has no developer diagnostics. |

## Behavior

- Server channel sidebars show Members derived from all known server members in the current snapshot.
- DM and group DM sidebars show Participants.
- Home, Friends, Discover, and settings do not show an irrelevant Members panel.
- Missing user objects, avatars, and roles do not drop member rows.
- Role color is derived from the highest ranked valid colored role and applied to display names in server context.
- High contrast disables role-color name tinting to preserve readability.
- The emoji button opens a popover with Unicode emoji and current-server custom emoji shortcodes.
- Known custom emoji reactions and recognized `:name:` message tokens use bounded memory-only image loading.
- Unknown custom emoji fall back to text.

## Diagnostics

Developer Settings now reports sidebar context, known/rendered/missing member counts, missing avatar count, dropped count/reasons, role group count, emoji count, picker diagnostics, image queue count, and the manual Refresh Members action. Diagnostics omit tokens, raw response bodies, local file paths, and full message content.

## Security And Privacy

Phase 34 does not add APNs, background sync, persistent message storage, voice/video, screen share, bot dashboards, server deletion, destructive bulk moderation, or speculative mutation routes. Member refresh is explicit and manual. Custom emoji media loading stays bounded and memory-only.

## Tests Added

- Right sidebar context for Home, Discover, server channels, and DMs.
- Member diagnostics for missing avatars without dropping rows.
- Highest role color wins and does not leak into DMs.
- Custom emoji shortcode insertion and inline resolver.
- API request test for `GET /servers/{id}/members`.

## Deferred

- Live proof that large production servers provide every expected member through Ready or explicit member refresh.
- Exact official custom emoji message-content syntax parity beyond known `:name:` shortcode handling.
- Full custom emoji autocomplete and richer picker categories.
- Native Discover feed remains web-backed until a stable feed/API is verified.

## Known Risks

- Member completeness is still limited by Ready/realtime data unless the user explicitly runs Refresh Members.
- Manual refresh updates the current in-memory snapshot; later realtime Ready snapshots may replace that state.
- Inline custom emoji rendering is intentionally minimal and falls back to text for unknown/unloaded emoji.

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
3. Open a server channel.
4. Confirm right sidebar shows Members.
5. Confirm known members appear.
6. Confirm offline/missing-user members are not silently dropped.
7. Confirm role-colored members show the color on the name itself.
8. Confirm role color remains readable.
9. Confirm bots show names, avatars, and bot badge where available.
10. Open message rows from colored-role users.
11. Confirm author name uses role color where appropriate.
12. Click the emoji button in composer.
13. Confirm emoji picker opens.
14. Insert a Unicode emoji.
15. If server custom emoji exists, confirm it appears in picker.
16. Insert or render a custom emoji if syntax is verified.
17. React with custom emoji if supported.
18. Open Home.
19. Confirm Home is compact and native-feeling.
20. Confirm Home does not show a Members sidebar.
21. Open Friends.
22. Confirm Friends does not show a Members sidebar.
23. Open a DM.
24. Confirm right sidebar shows Participants.
25. Open Discover.
26. Confirm no irrelevant Members sidebar appears.
27. Open Developer Settings.
28. Confirm member/role/emoji/sidebar diagnostics are there and redacted.
29. Relaunch.
30. Confirm auto-connect still works and no mock UI appears.

## Recommended Phase 35

Run live QA on large servers and emoji-heavy servers. If live member counts and custom emoji syntax are verified, tighten parity claims; otherwise keep those items partial with the exact source limitations recorded.
