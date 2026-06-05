# Phase 32 - Live-Default Release Candidate

Phase 32 moves Liquid Bagel from an explicit live/manual prototype posture toward a normal live-default macOS client. The app now treats a saved credential for the selected environment as enough to start a live session during foreground launch. If no credential exists, the shell stays in a signed-out/setup state with no mock servers or fake channels.

## Live Dogfood Audit

| Area | Observed problem | Root cause found | Fix implemented | Tests added | Live QA step |
| --- | --- | --- | --- | --- | --- |
| Startup | Saved credentials still required a manual connect action. | `startLiveFirstSession()` only loaded credential presence and stopped in an unvalidated state. | Startup now loads preferences, checks scoped credential, validates, starts realtime, and hydrates Ready through the live path. | `testPhase32SavedCredentialAutoConnectsOnStartup` | Relaunch with saved credential and confirm connection starts automatically. |
| No credential state | Normal runtime could still feel preview/mock-shaped. | Empty live state and mock preview state shared too much user-facing language. | No saved credential keeps signed-out/setup state; preview data controls removed from normal runtime menus. | Existing missing-credential startup tests | Launch after forgetting credential and confirm no fake data appears. |
| Top bar | The top bar still exposed debug wording such as Live Manual. | Runtime mode label was shown in the main toolbar. | Toolbar now shows channel/DM/Home title and compact icon-only connection status; runtime details live in Developer Settings. | Existing title/selection tests plus source sweep | Confirm channel, DM, Home, and Friends titles. |
| Member list | Live member lists could drop or obscure members when user records were missing. | Member derivation depended on user hydration for display quality and diagnostics did not count missing users. | Server members derive from all known members, include offline/missing-user rows, preserve role grouping, and report missing user count. | Missing/offline/large member tests updated | Open a large server and compare diagnostics to expected member count. |
| Usernames/avatars | Rows could fall back to raw-ish IDs or stale unknown names. | Some moderation/member surfaces bypassed the central resolver. | Member management rows now use `UserDisplayResolver`; DM top titles use participant display names; avatar paths remain bounded/memory-only. | Existing resolver tests | Inspect prior raw-ID channels and member profiles. |
| Drag/drop | Drop queued attachments immediately instead of offering a review step. | Composer drop path called the attachment queue helper directly. | Drop now opens an Attach Files review sheet; Add to Message queues; upload still waits for Send/upload action. | Phase 32 drop review tests | Drag files into timeline/composer and verify no upload before confirmation. |
| Image previews | Inline images were too small for real dogfooding. | Timeline card max dimensions were conservative. | Timeline attachment cards now allow larger responsive image previews with bounded height. | Existing media tests | Send/view landscape, portrait, and small images. |
| Emoji | Composer had only a disabled emoji affordance. | No picker state or insertion hook existed. | Composer emoji menu inserts common Unicode emoji; quick reaction set expanded. | Phase 32 emoji insertion test | Insert emoji and react in server/DM. |
| Moderation | Member actions were mostly buried in settings surfaces. | Member list rows lacked direct context actions. | Server member rows now expose permission-gated context menu actions with confirmation before kick/ban/timeout/clear timeout. | Existing Phase 26 moderation tests | Use a private test server and verify confirmation/error behavior. |
| Notifications | Auto-connect must not trigger notification permission. | Permission request remained explicit, but copy referenced manual reconnect. | No launch permission request added; notification route copy now uses reconnect language. | Route/copy regression updated | Launch with notifications not determined and confirm no system prompt appears. |

## Runtime Direction Change

Normal app startup is live-default:

- Saved credential for the selected environment: validate, connect realtime, hydrate Ready, and restore safe prior selection.
- No saved credential: show signed-out/setup with no mock data.
- Connection failure: show failed/retry state, keep setup/reconnect visible, and do not crash.
- Mock services remain available for tests, previews, and developer-only fixtures.

This is foreground app-session startup only. Phase 32 does not add background sync, APNs, push registration, persistent message storage, or hidden daemons.

## User-Facing Mock Mode Removal

Normal runtime menus no longer expose Open Preview Data, Reset to Mock, or Mock Mode language. Preview data still exists for SwiftUI previews and tests. Developer diagnostics may describe internal runtime state, but normal chat UI does not require the user to choose a mock/manual mode.

## Top Bar Cleanup

The top bar now prioritizes conversation identity:

- server channel: `# Channel Name`
- DM: participant/group/saved-message name
- Home/Friends/Direct Messages: route title
- connection state: compact icon-only affordance

## Member List Repair

Member list derivation remains local and bounded. It includes all known server members from Ready/member state, keeps missing-user members with shortened-ID fallback, includes offline members, groups role-hoisted members first where role data exists, and reports known/rendered/missing/dropped counts in Developer Diagnostics.

## User And Avatar Hydration

Display naming uses the shared resolver order: member nickname, display name, username, then shortened ID. Avatars continue to prefer member/server avatar metadata when modeled, then user avatar, then initials/color fallback. Image loading remains memory-only and avoids broad profile/avatar fetch storms.

## Drag/Drop Upload Modal

Dropping files onto the app opens an Attach Files review sheet. The sheet shows sanitized filenames, type/size hints, validation status, local image thumbnails when available, remove controls, Cancel, and Add to Message. Add to Message queues attachments in the composer; upload still waits for Send or an explicit upload path. Drops without a sendable target produce a blocked review reason.

## Larger Inline Image Previews

Timeline image cards now render larger while preserving aspect ratio and bounded height. The existing explicit viewer remains the path for full-size inspection.

## Emoji Support

Unicode emoji render naturally in SwiftUI text. The composer emoji button now opens a common-emoji menu and inserts into the draft. Reaction quick choices include a larger common set. Custom emoji remains partial: modeled emoji/media support is preserved, but autocomplete and exhaustive official-client parity are deferred until live schema behavior is verified.

## Moderation Support

Phase 32 keeps moderation scoped. Member list context menus expose timeout, clear timeout, kick, and ban through existing permission/rank gates and confirmation flow. Message deletion/removal continues to use the existing confirmation-gated action path. Full dashboards, audit logs, bulk actions, server deletion, bot dashboards, and automod configuration remain out of scope.

## Notification Behavior

Auto-connect does not request notification authorization. Request Permission remains explicit in Settings. If the user has already granted permission and enabled notifications, live in-app/native notification behavior continues through existing classifiers. No APNs or background sync was added.

## Diagnostics

Developer surfaces now report auto-connect credential detection, runtime/session/connection state, hydration status, member known/rendered/missing/dropped counts, attachment drop review state, emoji insertion diagnostics, moderation errors, notification authorization state, and top-bar display mode. Diagnostics avoid tokens, raw local paths, and raw response bodies.

## Parity Matrix Updates

`Docs/ParityMatrix.md` now records live-default startup as partial pending live QA, drag/drop review and larger image previews as implemented, emoji as partial, member list/user hydration as partial pending live QA, moderation as partial, and notification behavior as partial until permission/delivery are live-confirmed.

## Security And Privacy

Phase 32 keeps credentials scoped per environment, avoids token logging, keeps attachment local paths out of UI, does not upload on drop, avoids hidden profile/avatar fetch storms, requires confirmation for destructive moderation, and keeps mock data out of normal startup.

## Tests Added

- Saved credential auto-connect startup.
- Dropped files open review without queueing or uploading.
- Dropped files without sendable target show a safe blocked review.
- Unicode emoji insertion into the composer.
- Missing user count in member-list diagnostics.
- Notification queued-route copy updated for reconnect language.

## Deferred

- Custom emoji autocomplete and exhaustive custom emoji rendering parity.
- Full moderation dashboard, audit logs, server deletion, bulk actions, and automod.
- Persistent message cache/database.
- APNs, push registration, and background sync.
- Live proof for DMs, member completeness, hydration, notifications, and moderation edge cases.

## Known Risks

Live QA is still required for production member completeness and identity media. Auto-connect failure handling is mock-tested but should be exercised against invalid/revoked credentials. Finder drag/drop behavior can vary across macOS item providers, so the review helper is tested separately from Finder automation.

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

1. Launch app with saved credentials.
2. Confirm app auto-connects without pressing Connect Manually.
3. Confirm no user-facing Mock Mode appears.
4. Confirm top bar does not say Live Manual.
5. Confirm channel title appears correctly.
6. Open a server with many members.
7. Confirm member list shows all known members or clear diagnostics explain missing data.
8. Confirm offline members appear if present in Ready.
9. Confirm member avatars and names render or fallback cleanly.
10. Open chat messages from users that previously rendered as raw IDs.
11. Confirm names and avatars resolve.
12. Drag an image/file into the app.
13. Confirm attach modal appears.
14. Confirm nothing uploads until Add to Message and Send.
15. Send dropped image/file.
16. Confirm inline image preview appears larger.
17. Click image and confirm viewer opens.
18. Open emoji picker.
19. Insert emoji into composer.
20. React with emoji.
21. Use a safe moderation action in a private test server if implemented.
22. Confirm confirmation appears before destructive action.
23. Open Notification Settings.
24. Confirm no permission prompt happened on launch.
25. Request permission manually if needed.
26. Relaunch.
27. Confirm auto-connect works again without exposing mock mode.

## Recommended Phase 33

Run a focused live dogfood pass on production member completeness, DM identity hydration, notification delivery after auto-connect, Finder drag/drop provider behavior, and safe moderation errors. Use that evidence to either mark live-sensitive parity items done or keep them partial with exact diagnostics.
