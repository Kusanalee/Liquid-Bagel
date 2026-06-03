# Phase 28 - Dogfood Stabilization

Phase 28 repairs dogfood-visible DMs, user/member display fallback, notification permission UX, server header actions, native member sidebar behavior, and large-list/timeline performance without changing Liquid Bagel's startup contract. The app remains live-first but disconnected, signed out, or ready to connect as appropriate. It does not auto-connect, auto-validate saved credentials, hidden-refresh DMs or members, request notification permission on launch, add push/APNs, add background sync, or add a persistent message cache.

## Dogfood Bug Audit

| Issue | Observed problem | Suspected root cause | Root cause found | Fix implemented | Tests added | Manual QA |
| --- | --- | --- | --- | --- | --- | --- |
| Direct Messages do not load reliably | DM rows could select visually while serverless/group DM paths still behaved inconsistently. | DM classification and selection paths were not shared everywhere. | `selectDirectMessages()` only picked `.directMessage`, while other paths treated group/saved DMs as DM-like. | Added `DMChannelClassifier`; DM-like channels now route through `selectedConversationChannel`, load messages, target composer, and keep unread/notification context serverless. | `testPhase28DirectMessageLikeSelectionLoadsGroupDMs`. | Click direct, group, and saved-message rows; confirm timeline and composer target update. |
| Users render as raw IDs | Some visible authors, members, and DM participants had no hydrated user object. | UI fallbacks used full IDs or dropped missing participants. | Display fallback was spread across views and used `fallbackID.rawValue`. | Added `UserDisplayResolver` with nickname, display name, username, then shortened ID. DM names now use short unknown-recipient fallbacks. | `testPhase28DisplayResolverUsesSafeFallbacks`. | Open affected channels/DMs and confirm no giant raw IDs appear as normal names. |
| Notification permission request unclear | Settings existed, but dogfood could not tell whether real macOS authorization was used. | UI/diagnostics did not expose authorizer kind or last request result clearly. | Runtime default was real `UserNotificationsPermissionManager`; settings lacked enough troubleshooting detail. | Notification settings now show authorizer kind, last request, denied guidance, request/refresh/test controls, and copied redacted diagnostics. | `testPhase28NotificationPermissionRequestUpdatesDiagnostics`. | Open Notification Settings, request permission, refresh status, and send a test notification. |
| Server settings gear inconsistent | Gear could feel unreliable after banner/header changes. | Banner overlay/hit-testing and small target risk. | Header gear was adjacent to a banner that still participated in hit-testing. | Gear now has a stable minimum hit target, higher z-index, safe action diagnostics, and banner hit-testing disabled. | Existing server settings tests plus Phase 28 diagnostics build coverage. | Open bannered and non-bannered servers and click the gear repeatedly. |
| Member list too sparse and slow | Sidebar only split online/offline users and could eagerly process/load too much. | Member derivation happened inside views and snapshot image loading queued every identity image. | `loadIdentityImagesForCurrentSnapshot()` walked all users/members/servers on connected snapshots. | Added role/bot/online/offline/unknown member grouping, contextual DM/sidebar states, lazy rows, and visible-only image loading. | `testPhase28MemberListGroupsLargeServerWithoutDroppingUnknownUsers`. | Open a large server, scroll members, search/manage members, and confirm responsiveness. |
| Large timelines slow/freeze | Timeline grouping and visible updates could be repeated during SwiftUI layout. | Computed grouping re-sorted and regrouped on every read; visible updates processed no-op events. | `selectedTimelineMessageGroups` was a computed grouping call, and visibility updates did not skip duplicates. | Added cached timeline grouping by message/status key, no-op visible-range skip, and performance diagnostics. | `testPhase28TimelineDiagnosticsAvoidNoOpVisibleRangeSpam`. | Open a high-volume channel, scroll, send, and confirm read ack does not spam errors. |

## Implemented Behavior

- DMs: `.directMessage`, `.group`, and `.savedMessages` are classified consistently as serverless DM-like conversations. DM selection uses the existing timeline, message loading, composer, send, attachment, unread, read-ack, and notification context paths without requiring `serverID`.
- User display: member nickname wins, then display name, username, and a shortened ID fallback. Unknown DM participants and members remain visible instead of being dropped.
- Notifications: permission remains explicit-only. Settings shows status, authorizer type, request/refresh controls, denied guidance, delivery/privacy/dock preferences, and a test notification action.
- Server header: the server settings gear keeps a normal hit target and is not intercepted by banner imagery. Last settings action is captured in redacted diagnostics.
- Member sidebar: server channels show grouped member lists; DMs show participants; Home/Friends/Discover show a contextual empty state.
- Performance: member rows and server-settings member management are lazy-rendered; identity images are loaded for visible/selected context only; timeline grouping is cached and visible-range no-ops are ignored.

## Diagnostics And Privacy

- `Phase28DogfoodDiagnostics` reports DM selection/load state, missing visible user count, notification authorization status/authorizer kind, last permission request, server settings action state, member diagnostics, and timeline performance diagnostics.
- `TimelinePerformanceDiagnostics` and `MemberListPerformanceDiagnostics` report counts and queue sizes only.
- Diagnostics avoid tokens, raw session IDs, raw server response bodies, raw local file paths, and message content.
- Copied notification diagnostics include only sanitized counts/status and authorizer/request metadata.

## Notification Troubleshooting

- macOS only shows the notification prompt after the explicit Request Notification Permission button is clicked.
- If status is `denied`, macOS may not show another prompt. Open System Settings > Notifications, find Liquid Bagel, allow notifications, then click Refresh Status.
- Permission status is tied to the app bundle identity. A debug build and a released build can have different macOS notification settings.
- The app sandbox currently includes network and user-selected file access. No APNs/push entitlement or registration is used in this phase.
- If the authorizer says `MockNotificationPermissionManager`, the view is running under tests/previews or an explicitly injected mock. Live app construction defaults to `UserNotificationsPermissionManager`.
- Test Notification uses the injected deliverer. In tests/previews it is mock-only; in the live app it uses `UNUserNotificationCenter`.

## Tests Added

- Group DM selection opens a serverless DM timeline and targets the composer.
- Display fallback resolves nickname/display/username/short-ID safely.
- Large synthetic member list grouping preserves unknown users and records diagnostics.
- Explicit notification permission request reaches the permission manager and updates diagnostics.
- Timeline visible-range no-op updates do not spam diagnostics.

## Manual Live QA Checklist

1. Launch app.
2. Confirm no auto-connect or auto-validation.
3. Validate saved session manually.
4. Connect manually.
5. Click several DM rows, including group DMs if available.
6. Confirm each DM loads messages.
7. Send a test DM.
8. Confirm DM right sidebar shows participants.
9. Open a server with users that previously rendered as IDs.
10. Confirm display names and avatars resolve or fallback cleanly.
11. Open Notification Settings.
12. Click Request Notification Permission.
13. Confirm macOS permission prompt or clear denied/authorized state.
14. Click Refresh Status.
15. Click Test Notification.
16. Confirm native notification or clear diagnostic.
17. Open a server with banner.
18. Click settings gear repeatedly.
19. Confirm Server Settings opens reliably.
20. Open a large server member list.
21. Confirm grouping and scrolling remain responsive.
22. Open a high-volume channel.
23. Scroll through messages.
24. Confirm app does not freeze.
25. Send a message.
26. Confirm read ack does not spam errors.
27. Relaunch.
28. Confirm no auto-connect or auto-validation happened.

## Deferred Or Limited

- No launch-time missing-user/profile fetch was added. Profile fetch remains explicit when opening a profile.
- Markdown/embed caching is represented in the diagnostics shape but not expanded beyond existing safe rendering in this phase.
- Pixel/screenshot automation for header hit-testing remains deferred; the implementation keeps the button outside banner hit-testing and relies on mock/build coverage plus manual QA.
- Live notification permission behavior still depends on macOS bundle identity and System Settings state.

## How To Verify

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

## Recommended Phase 29

After live QA confirms Phase 28 stability, Phase 29 should focus on the next parity area with verified routes only. Good candidates are richer profile/account editing, channel/server search expansion, or native discover/invite follow-up, but only after DM loading, notifications, and large-list responsiveness remain stable in real use.
