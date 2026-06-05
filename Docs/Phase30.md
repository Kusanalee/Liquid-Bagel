# Phase 30 - Parity Release Candidate Gate

Phase 30 is a release-candidate gate, not a parity claim. Liquid Bagel must not claim official-client parity until Direct Messages pass live QA. The implementation in this phase keeps the app live-first and manual: no auto-connect on launch, no automatic saved-credential validation, no hidden DM refresh on launch, no background sync, no APNs registration, and no persistent message database/cache.

## DM Root-Cause Investigation

Phase 29 improved DM routing but still left too much behavior split across `serverID`, `channelID`, and `dmChannelID`. Live QA could still show a clicked DM row diverging from the selected conversation, message loader, composer target, or sidebar participant state. The likely failure class was stale server/channel selection obscuring a DM route or a friend/profile action opening a user rather than selecting a known DM channel.

Phase 30 adds `ActiveConversation` as the single derived conversation source and a richer `DirectMessageLiveTrace` so manual QA can see the exact clicked row, selected route, load channel, timeline state, composer target, and participant count immediately after clicking a DM.

## DM Fixes Implemented

- Existing DM rows select their real channel ID through `selectDirectMessageItem(_:)`.
- DM selection clears stale server and server-channel state, then resolves to `.directMessage`, `.groupDM`, or `.savedMessages`.
- `selectedConversationChannelID` now comes from `activeConversation`, so timeline, composer, attachments, search, unread clearing, read ack, and notification active-channel checks use one source.
- DM message loading still uses the verified channel messages route by channel ID and does not require a server ID.
- DM composer send and attachment upload/readiness target the selected DM channel ID.
- DM participants use channel recipients, the current user, hydrated users, and safe missing-user fallbacks instead of showing an empty member list when recipient IDs are present.
- Known open-DM actions select an existing DM channel; `GET /users/{target}/dm` remains explicit and only runs after the user clicks Message when no known channel exists.
- Manual `GET /users/dms` refresh remains behind the explicit Friends/DM refresh action.

## DM Live Diagnostics

Developer Verification now exposes a DM trace with:

- clicked row/channel/user/kind
- before/after selected space, server, and channel IDs
- selected conversation channel ID
- message load request, load channel, and whether REST was used
- timeline channel and message count
- composer target channel
- sidebar participant count
- safe last error

The Copy DM Trace action uses redaction for tokens, URLs, raw payload-shaped JSON, local paths, and response/error text. It never includes message content.

## Manual Live QA Result

Automated mock QA passes, but live dogfood QA is still required. Until the checklist below passes in a real connected session, the parity matrix keeps DMs marked `broken`.

## Official-Client Parity Matrix Summary

The full matrix is in `Docs/ParityMatrix.md`. Critical Phase 30 status:

- DMs: `broken` until live QA proves selection/load/send/attachments/participants/notifications.
- Server text chat, attachments, image preview, drag/drop upload, command palette, diagnostics, member list, dock badge, and system events: core implementation is present.
- Many official-client surfaces remain `partial`, `blockedByUnverifiedAPI`, `deferred`, or `outOfScope` rather than being papered over.

## Critical Parity Gaps Fixed

- DM routing now has first-class active conversation resolution.
- DM load/send/attachment/sidebar/read-ack paths all use the active DM channel ID.
- Developer-only DM trace makes live divergence copyable and redacted.
- Parity matrix models and tests prevent DMs being marked done without a live QA flag.

## Critical Parity Gaps Still Broken

- DMs are still considered broken until live QA completes.
- Group DM creation/opening beyond known Ready channels is not implemented without route verification.
- Account/profile editing and avatar/banner mutation remain blocked until account edit routes are verified.

## Deferred Parity Areas

Voice, video, screen share, bots/dashboard, audit logs, APNs/background push, persistent offline cache, server deletion, speculative unverified routes, and broad official-client redesign remain outside Phase 30.

## Security And Privacy

- No tokens, raw session IDs, raw local file paths, raw server response bodies, or message content are copied in diagnostics.
- No hidden live networking was added.
- DM refresh, open-DM, notification permission, and destructive actions remain user-initiated.
- Attachment/media behavior remains explicit and memory-only.

## Tests Added

- DM row trace and stale server-selection regression.
- Live-manual DM load/send/attachment/participant/read-ack target regression using mocks.
- Group DM, saved messages, and known open-DM selection regression.
- DM trace redaction and parity matrix status regression.
- Existing no-auto-connect/no-auto-validation/no-hidden-fetch tests remain in place.

## Manual Live QA Checklist

1. Launch app.
2. Confirm no auto-connect or auto-validation.
3. Validate saved session manually.
4. Connect manually.
5. Open Direct Messages.
6. Click a direct DM row.
7. Confirm developer DM trace shows clicked channel ID.
8. Confirm selected conversation channel ID equals clicked DM channel ID.
9. Confirm message load requested that same channel ID.
10. Confirm timeline shows DM messages.
11. Confirm composer placeholder targets the DM.
12. Send a test DM.
13. Confirm message appears in DM.
14. Send image/file in DM.
15. Confirm attachment appears inline.
16. Click another DM.
17. Confirm previous server channel does not override DM selection.
18. Click a group DM.
19. Confirm group DM loads.
20. Click Saved Messages if available.
21. Confirm Saved Messages loads.
22. Open a friend profile and click Message.
23. Confirm existing DM is selected or open-DM route runs after explicit click.
24. Confirm right sidebar shows DM participants.
25. Confirm DM notification active-channel suppression works.
26. Confirm no persistent success toast.
27. Open Developer Verification.
28. Copy redacted DM trace.
29. Open Parity Matrix.
30. Confirm DMs are marked Done only after this QA passes.
31. Relaunch.
32. Confirm no auto-connect or auto-validation happened.

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

## Known Risks And Limitations

- Live QA is still the deciding evidence for DMs.
- The parity matrix is intentionally conservative; partial items should not be marketed as official parity.
- The DM trace stores safe IDs and counts only, so deeper server-side failures still need live API/realtime logs outside user-facing diagnostics.

## Recommended Phase 31

After live DM QA passes, Phase 31 should close one narrow verified parity area at a time, starting with account/profile editing route verification or group DM polish if the official API path is confirmed.
