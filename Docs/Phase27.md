# Phase 27 - Live UX Repair

Phase 27 repairs dogfood-visible live parity issues without changing Liquid Bagel's startup contract. The app remains live-first but disconnected, signed out, or ready to connect as appropriate. It does not auto-connect, auto-validate saved credentials, start hidden live refreshes, upload on drop, request notification permission on launch, add push/APNs, add background sync, or add a persistent message cache.

## Dogfood Bug Audit

| Issue | Observed problem | Suspected root cause | Fix implemented | Tests added | Manual QA |
| --- | --- | --- | --- | --- | --- |
| Direct Messages do not load on click | DM rows existed, but several selected-channel paths still assumed `selection.channelID`/server channels. | DM selection used `dmChannelID`, while restore, composer, and UI header paths were server-channel biased. | Added DM-aware restore through `lastSelectedChannelID`, `selectedConversationChannel`, DM composer/drop/header targeting, and persisted DM channel selection. | `testPhase27RestoresPersistedDMSelection`, `testPhase27DMSelectionTargetsComposerAndQueuesDropWithoutUpload`, `testPhase27DMAckUsesNormalMessage`. | Click a DM row, confirm timeline loads, composer targets the DM, send a test DM. |
| System events render poorly | System events displayed generic/raw fallback copy in normal message rows. | Existing UI showed `system.content ?? "System event"` and normal row affordances could still appear. | Added `Phase27SystemEventPresenter`, subtle centered `SystemEventRow`, and disabled edit/delete/pin/react/reply for system messages. | `testPhase27SystemEventPresenterUsesNamesAndUnknownFallback`, `testPhase27SystemOnlyTimelineDoesNotAckOrExposeNormalActions`. | Open a channel with joins/leaves and confirm human-readable centered rows. |
| Server banner in wrong place | Banner consumed main timeline toolbar space. | `ChatPlaceholderView` rendered the banner behind the main channel toolbar. | Moved banner to the sidebar header below the server name and removed it from the main timeline toolbar. | Covered by build/UI construction and Phase 27 docs; visual QA required. | Open a bannered server and confirm the banner appears below the server name in the sidebar/header. |
| Channel hit target too small | Row padding/background did not reliably feel clickable. | Row content did not explicitly fill available width/content shape in all sidebar contexts. | Made channel and DM row labels fill width and use rectangular content shapes. | Covered by existing construction tests; manual pointer QA required. | Click row padding around channel/DM names and confirm selection changes. |
| Embeds missing/placeholder | Embeds rendered as a minimal placeholder. | `EmbedPreviewPlaceholder` ignored kind, URL, provider, media, and safety details. | Added safe `EmbedTimelineCard` for link/text/image/video metadata, sanitized display URLs, explicit `Link`, no HTML/script/autoplay. | Covered by `StoatUI` build; deeper view inspection can be expanded later. | Open messages with link/image/video embeds and confirm compact safe cards. |
| Read acknowledgement failed spam | User-visible read ack failures repeated while app was otherwise usable. | Ack picked unread IDs even when no valid normal visible message existed, including system-only timelines. | Added `Phase27ReadAckDecision` gating; skips disconnected/missing/stale/no-unread/system-only/duplicate cases and keeps failures in diagnostics instead of message toasts. | `testPhase27SystemOnlyTimelineDoesNotAckOrExposeNormalActions`, `testPhase27DMAckUsesNormalMessage`. | Browse active channels and confirm no recurring read-ack toast. |
| Markdown missing | Message content rendered as plain text only. | Timeline body used raw `Text(content)`. | Added native SwiftUI `MarkdownMessageContent` with safe inline Markdown, code blocks, blockquotes, HTML stripping, and fallback plain text. | Covered by `StoatUI` build; parser unit coverage can be expanded. | Send/view bold, italic, code, quote, and link Markdown. |
| Drag/drop upload unreliable | Drop worked only on composer and only when the composer was visible. | Drop target was scoped to `GlassComposer`; DM/no-channel handling was too silent. | Added whole-timeline/window file drop routing to active server channel or DM, with no auto-upload and safe no-channel error. | `testPhase27DMSelectionTargetsComposerAndQueuesDropWithoutUpload`. | Drag an image/file into the timeline and confirm it queues without uploading until Send. |
| Notifications need end-to-end repair | Phase 18/19 services existed, but Phase 27 needed explicit audit. | Existing notification stack was conservative but needed confirmation against DM/active-channel/privacy expectations. | Preserved explicit settings/request/test model; Phase 27 diagnostics include notification status. Existing classifier already covers DM, mentions, active-channel, privacy, muted channels, click queueing, and dock badge. | Existing Phase 18/19 notification tests plus Phase 27 diagnostics build coverage. | Use Notification Settings, refresh/request permission, test notification, and inactive-app message delivery. |
| Diagnostics needed | Phase-specific state was spread across existing diagnostics. | No single Phase 27 snapshot summarized route, DM, ack, embeds, markdown, drops, and notifications. | Added `Phase27Diagnostics`, derived from existing redacted state and safe counts. | Covered by feature build and existing redaction tests. | Inspect developer diagnostics and confirm no tokens, raw file paths, or raw server bodies. |

## Implemented Behavior

- DM channels now restore from persisted channel selection, load via the existing message controller, target the composer, accept queued attachments, and can ack normal DM messages.
- System events render as compact centered rows with human-readable names when local users are available and safe fallbacks otherwise.
- Server banners render in the sidebar header area below the server name and no longer consume main timeline toolbar space.
- Channel and DM rows use full-width hit targets while preserving existing context menu/accessory behavior.
- Embed cards render safe metadata for websites, text embeds, images, videos, and media references. External links require explicit clicks and displayed URLs omit query/fragment data.
- Markdown rendering supports safe inline Markdown, code blocks, and blockquotes. Raw HTML is stripped rather than rendered.
- Drag/drop queues files into the selected channel or DM. Drops without a selected sendable conversation show a safe message. Upload still happens only during Send or explicit retry.
- Notifications continue through the existing explicit Phase 18/19 model: no launch prompt, no push/APNs, no hidden network calls, privacy mode supported, and click routes queue when disconnected.

## Diagnostics And Security

- `Phase27Diagnostics` reports route, selected channel/kind, DM load state, last system event render, banner placement, read ack decision, embed count, drop queue count, and notification status.
- Diagnostics avoid tokens, raw session IDs, raw server responses, and local file paths.
- Markdown does not render HTML.
- Embed cards do not render remote HTML, execute scripts, autoplay media, or open links automatically.
- Attachment drops and previews reuse existing filename/path redaction and in-memory preview behavior.

## Deferred Or Limited

- Live API behavior for unusual embed/provider variants remains best-effort until more dogfood samples are captured.
- Embed image/video playback is intentionally metadata/card-only in this phase.
- UI hit-target and banner placement are covered by build/tests plus manual QA rather than pixel/screenshot automation.
- Markdown spoilers/custom emoji/mention-rich rendering remain deferred unless the platform syntax is later verified.

## Tests Added

- DM persisted selection restore.
- DM selection composer targeting and drop queue without upload.
- System event name/fallback rendering.
- System-only timeline skips read ack and normal message actions.
- DM read ack uses a normal message.

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

## Manual Live QA Checklist

1. Launch app.
2. Confirm no auto-connect or auto-validation.
3. Validate saved session manually.
4. Connect manually.
5. Click a DM row.
6. Confirm DM messages load.
7. Send a test DM message.
8. Open a server channel with system events.
9. Confirm join/leave/system events render human-readable text.
10. Confirm banner appears under/below server name in sidebar/header.
11. Click channel row padding, not the text.
12. Confirm channel switches.
13. Open a message with an embed.
14. Confirm embed card renders safely.
15. Send or view Markdown message.
16. Confirm Markdown renders safely.
17. Confirm read acknowledgement error no longer spams.
18. Drag an image into the app.
19. Confirm it queues in composer without uploading.
20. Send it.
21. Confirm upload/send works and image appears inline.
22. Open Notification Settings.
23. Request/refresh permission explicitly.
24. Send test notification.
25. Receive a message while app inactive.
26. Confirm notification/badge behavior.
27. Relaunch.
28. Confirm no auto-connect or auto-validation happened.

## Recommended Phase 28

Capture live dogfood samples for embed variants, system event payloads, and notification click routing, then add screenshot/UI automation for banner placement, hit targets, Markdown, and embed cards.
