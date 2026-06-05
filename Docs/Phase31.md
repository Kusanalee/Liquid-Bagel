# Phase 31 - Live Dogfood Blocker Fix

Phase 31 is a blocker-fix phase. It does not add a new parity area and does not claim Direct Messages, notification permission, or user/avatar hydration are done until live QA proves them in a real connected app session.

## Live Bug Audit

Live QA reported that clicking a DM row selected the row and could update the right sidebar, but the center content stayed on Friends/Home. Routine refresh notices also stayed visible, chat authors could still render as raw IDs, Command-comma opened an obsolete Phase 5 settings window, and notification permission requests stayed `notDetermined` without useful diagnostics.

## DM Root Cause Found

`MainShellView` still rendered `FriendsPlaceholderView` for every `.directMessages` shell space. Phase 30 had already added `ActiveConversation` and `selectedConversationChannelID`, but the center-content switch did not use that active conversation as the authority.

## DM Routing/Main-Content Fix

The center content now renders the chat timeline whenever `activeConversation != .none`. Friends/DM list mode remains visible only when the Direct Messages space has no selected DM channel. Opening the Friends/DM list no longer auto-selects the first DM; clicking a specific DM row is the explicit route that selects and loads that channel.

## DM Load/Send/Sidebar Fix

DMs, group DMs, and saved messages continue to use the existing channel-message route by channel ID. The DM trace records the clicked channel, active conversation channel, timeline channel, message-load channel, composer target, and participant count. Composer placeholders are DM-aware, and send/attachment/read-ack paths continue to use `selectedConversationChannelID`.

## User/Avatar Hydration Fix

Phase 31 adds `ResolvedUserDisplay` as the central display result. The fallback order is server nickname, user display name, username, then shortened ID. Message rows now receive resolver output and the shared UI row no longer falls back to a full raw author ID. Avatar resolution uses member avatar, then user avatar, then initials fallback.

## Sticky Notice Fix

Routine successful refreshes no longer leave persistent status overlays. Successful Friends/DM refresh records developer status instead of showing a sticky user-facing notice. Generic refresh success messages auto-clear quickly; errors remain visible.

## Settings Routing Fix

The obsolete static `LiquidBagelSettingsView` and its “App phase: Phase 5” copy were removed. The SwiftUI Settings scene now opens the current Account, Sessions, Connection, Notifications, and Developer settings surface.

## Notification Permission Root Cause And Fix

The live authorizer path already defaulted to `UserNotificationsPermissionManager`, but the request result was too opaque: errors were swallowed and diagnostics only showed a final status such as `result notDetermined`. Phase 31 records whether `requestAuthorization` was called, the requested alert/sound/badge options, completion grant state, error text, status before, status after, and whether the authorizer was mock or live.

## Notification Troubleshooting

If clicking Request Notification Permission still leaves the status at `notDetermined`, check:

1. System Settings -> Notifications -> Liquid Bagel.
2. Whether the app has a stable bundle identifier.
3. Whether the app is signed for the local run.
4. Whether diagnostics say the mock authorizer was used.
5. Whether diagnostics say `requestAuthorization` was called.
6. Whether an error was returned by `UNUserNotificationCenter`.

No notification prompt is shown on launch, and Phase 31 does not add APNs or push registration.

## Parity Matrix Honesty

`Docs/ParityMatrix.md` keeps DMs `broken`, native notification permission `partial`, and user/avatar hydration `partial` until live QA proves them. Mock tests are evidence for regressions, not parity completion.

## Security And Privacy Behavior

Phase 31 adds no auto-connect, no saved-credential auto-validation, no hidden DM refresh on launch, no hidden profile fetch storm, no background sync, no APNs registration, and no persistent message database/cache. DM and notification diagnostics stay redacted and do not include tokens, raw response bodies, local paths, session IDs, or message content.

## Tests Added

Phase 31 adds mock-only tests for:

1. DM list mode staying list-only until row click.
2. Clicked DM row activating the timeline route.
3. Timeline/load/composer trace all using the clicked DM channel.
4. Structured user display resolving nickname/avatar and shortened fallback.
5. Notification permission request options and authorizer diagnostics.

## What Remains Deferred

Voice/video, bots, server deletion, audit logs, full moderation dashboard, persistent offline cache, APNs/background push, speculative user hydration fetches, and new parity surfaces remain deferred.

## Known Risks And Limitations

Live QA is still required. If macOS refuses to show a notification prompt for bundle/signing/System Settings reasons, Phase 31 should now make that diagnosable, but it cannot force macOS to re-prompt a previously decided permission.

## How To Run App/Tests

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

1. Launch app.
2. Confirm no auto-connect or auto-validation.
3. Validate saved session manually.
4. Connect manually.
5. Open Direct Messages.
6. Click a DM row.
7. Confirm center content switches from Friends/Home to DM timeline.
8. Confirm DM trace clicked channel ID equals active conversation channel ID.
9. Confirm message loader requested that same DM channel ID.
10. Confirm DM messages appear.
11. Confirm composer placeholder targets the DM.
12. Send a DM text message.
13. Confirm no sticky “Message sent” notice.
14. Send an image/file in DM.
15. Confirm attachment appears inline.
16. Click another DM.
17. Confirm the second DM loads and does not show the old Friends view.
18. Open a server chat with authors that previously rendered as IDs.
19. Confirm names and avatars render or fallback cleanly.
20. Run Friends/DM refresh.
21. Confirm “Friends and DMs refreshed” either does not appear or auto-dismisses quickly.
22. Press Command-comma.
23. Confirm the current settings surface opens, not the obsolete Phase 5 window.
24. Open Notification Settings.
25. Click Request Notification Permission.
26. Confirm macOS prompts, or if not, confirm diagnostics explain exactly why.
27. Refresh permission status.
28. Send test notification if authorized.
29. Open Parity Matrix.
30. Confirm DMs/notifications/user hydration statuses reflect real live QA, not mock-only success.
31. Relaunch.
32. Confirm no auto-connect or auto-validation.

## Recommended Phase 32

After live QA proves the Phase 31 blockers, Phase 32 should either mark the live evidence in the parity matrix or continue with one narrow verified parity area. Do not start a broad new parity area while DMs or notification permission remain broken in live dogfood.
