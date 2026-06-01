# Phase 21: Live-First Runtime And Media Identity

Phase 21 makes normal Liquid Bagel launch live-first while keeping mock infrastructure for previews, tests, and developer preview data.

## What Was Implemented

- Normal app launch now calls `startLiveFirstSession()` instead of booting the Bagel Lab mock snapshot.
- Live-first startup loads preferences and credential presence only, then shows signed-out or saved-credential state without validating, connecting, opening WebSocket, fetching messages, or prefetching media.
- Mock data, mock services, mock tests, and SwiftUI previews remain intact behind explicit preview/developer paths.
- Timeline image attachments can render inline thumbnails when policy allows, and clicking the inline image opens the larger attachment viewer.
- User avatars, member/message avatars, current-user avatars, server rail icons, and server header banners can render from Autumn media with fallbacks.
- A bounded in-memory image cache and generic image loader were added for identity media.
- The developer/live verification surface includes image reload and cache-clear actions.

## User-Facing Mock Mode Removal

The normal app runtime no longer starts in user-facing mock mode. The root view starts with an empty live manual snapshot and the coordinator sets:

- `signedOut` when no saved credential exists.
- `savedCredentialUnvalidated` when a saved credential exists.

No automatic validation or live connect is performed. User-facing copy now refers to mock data as Preview Data, and reset/open preview controls are gated by developer controls.

## Inline Image Rendering

Image attachments use the existing attachment display model, but loaded image previews now render as bounded inline images inside the message row. Remote images use the Autumn preview route:

```text
https://cdn.stoatusercontent.com/{tag}/{file_id}
```

Clicking the inline image opens the larger native preview sheet. Non-image files remain file cards. Local pasted-image preview bytes continue to render immediately from memory.

## Inline Image Loading Policy

`InlineImagePreviewPolicy` was added to preferences:

- `automaticSmallImages` is the default and auto-loads visible remote image previews under the preview byte limit.
- `explicitClickOnly` keeps remote images metadata-first until the user clicks Load Image.
- `disabled` leaves image cards metadata-first.

Inline loading is visible-timeline only. There is no startup prefetch and no persistent media cache.

## Avatars, Icons, And Banners

Identity media resolves through Autumn preview routes:

- user and member avatars: `avatars`
- server icons: `icons`
- server banners: `banners`

Avatars and icons fall back to initials. Server banners fall back to the regular glass header and use a subtle scrim when present. Member nickname display is preferred over user display name where a server member is available.

## Image Cache And Loader

Phase 21 adds `ImageMemoryCache`, `ImageResourceRequest`, `ImageResourceKind`, and live/mock image loaders.

The cache is:

- in memory only
- bounded by entry count and bytes
- clearable from the developer/live verification panel
- keyed separately by image kind and file ID

The live loader sends no auth headers, rejects HTML/XHTML and non-image content types, applies byte limits, and returns safe short errors.

## Security And Privacy

- No tokens, raw URLs, raw local paths, or raw response bodies are surfaced in diagnostics.
- Remote media requests do not include auth headers.
- No disk media cache was added.
- No hidden media fetch happens on launch.
- Image viewer opens only after explicit click.
- HTML/non-image responses are rejected for image resources.
- Missing or failed identity media uses initials/placeholders.

## Tests Added

Mock-only tests cover:

- live-first empty startup without connect or validation
- saved credential startup staying unvalidated and disconnected
- mock preview session still available
- automatic inline image loading
- explicit-click-only policy not auto-loading
- image cache hit/miss/eviction/clear
- Autumn tag URL mapping for avatars, icons, and banners

## Manual Live QA Checklist

1. Launch the app.
2. Confirm no fake mock server appears in normal mode.
3. Confirm signed-out or saved-credential state appears.
4. Validate saved session manually.
5. Connect manually.
6. Confirm Ready arrives.
7. Confirm real servers appear.
8. Confirm server icons appear or fallback cleanly.
9. Select a server with a banner.
10. Confirm banner appears or fallback cleanly.
11. Select a text channel.
12. Confirm member avatars appear or fallback cleanly.
13. Confirm message row avatars appear or fallback cleanly.
14. Send a text message.
15. Confirm it appears.
16. Send a PNG/JPEG attachment.
17. Confirm it renders inline in chat.
18. Click the inline image.
19. Confirm larger image viewer opens.
20. Close viewer.
21. Disconnect.
22. Relaunch.
23. Confirm no auto-connect happened.
24. Reconnect manually.
25. Confirm inline images can reload from server metadata.

## Deferred

Persistent media cache, persistent message database, background sync, APNs, full gallery, image editing, video/audio playback, OCR, full friends/discover APIs, voice, server/channel settings, and live automated tests requiring credentials remain deferred.

## How To Run

```sh
swift test --package-path Packages/StoatFeatures
swift test --package-path Packages/StoatUI
swift test --package-path Packages/StoatPersistence
Scripts/check.sh
```

## Recommended Phase 22

Phase 22 should focus on real dogfood polish after live QA: tighter loading indicators, manual reconnect recovery, richer media failure telemetry, and any Stoat API differences observed while testing avatars/icons/banners against live accounts.
