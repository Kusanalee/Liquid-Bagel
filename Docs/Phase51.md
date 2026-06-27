# Phase 51 - Freeze-Proof Parity Gate

Phase 51 removes synchronous presentation work from the app's highest-risk SwiftUI paths before the Phase 48 and Phase 49 live parity audits. It does not add routes, persistent content caches, hidden fetches, or speculative wire behavior.

## Implemented Behavior

- Added revision-keyed shell, timeline-row, and Server Settings presentation snapshots.
- Server Settings now presents a lightweight loading state and prepares ordered roles, channels, permission groups, member rows, and timeout rows away from the main actor.
- Member search preparation is cancellable and debounced by 150 milliseconds.
- Timeline grouping uses the selected channel's message revision instead of rebuilding an O(n) string signature from loaded messages.
- Timeline grouping and identity presentation are prepared outside SwiftUI body evaluation.
- Quick Switcher builds its index only when its source snapshot changes, stores normalized search text, caps unfiltered results at 16, and caps searched results at 50.
- Server rail unread/mention counts and Friends/DM derivations come from a shell presentation snapshot rather than repeated row-level scans.
- All production `NSImage(data:)` calls were removed from SwiftUI render paths.
- Added a bounded, deduplicating ImageIO pipeline that downsamples image data away from the main actor before SwiftUI receives a `CGImage`.
- Cached inline Markdown tokenization and attributed-string parsing; message timestamps use shared format styles rather than allocating a formatter per row.
- Existing freeze diagnostics now publish at most once every 250 milliseconds.
- Developer Verification includes Phase 51 presentation, cancellation, throttling, and main-thread budget counters.

## Render-Safety Contract

SwiftUI bodies, modal builders, and context menus may read prepared values and bounded dictionaries only. Network work, image decoding, Markdown parsing, permission resolution, member derivation, channel sorting, and large collection filtering must start from lifecycle, command, or task boundaries.

The Phase 46 moderation contract remains unchanged: render paths read cached action state, lifecycle hooks prewarm it, and explicit moderation actions revalidate the current permission state before presenting or sending a destructive operation.

## Automated Verification

Phase 51 coverage includes:

- 2,001-member, 200-role, and 200-channel Server Settings preparation.
- A 5,000-channel Quick Switcher index with a 50-result cap.
- A maximum-size 250-message timeline proving revision-cache reuse.
- Concurrent requests for identical image resources proving one decode and bounded cache reuse.

Run:

```sh
swift test --package-path Packages/StoatUI --filter Phase51
swift test --package-path Packages/StoatFeatures --filter Phase51
swift test --package-path Packages/StoatFeatures --filter 'StoatFeaturesTests/testPhase4(2|4|6|7)'
git diff --check
Scripts/check.sh
```

## Manual Performance And Live-Parity Checklist

Use two safe accounts, one test server, the official client, and a Time Profiler or hangs trace.

1. Repeatedly open the member panel, profile popover, Server Settings tabs, Quick Switcher, emoji picker, pinned messages, and channel search.
2. Open a role-heavy server and a media-heavy channel; confirm typing, scrolling, menu opening, and modal dismissal remain responsive.
3. Confirm affected main-thread stacks contain no image decode, permission resolution, large sort/filter, or Markdown parse work.
4. Confirm no app-owned Phase 51 signpost exceeds 50 milliseconds during the audit.
5. Complete the Phase 48 chat/DM/notification checklist and record official-client comparisons.
6. Complete the Phase 49 account/profile checklist and record propagation through the second account.
7. Complete the Phase 42/46 moderation checklist only in the safe test server.
8. Complete the Phase 50 macOS appearance, Reduce Transparency, Increase Contrast, and VoiceOver checklist.
9. Copy Developer Verification and confirm no tokens, message bodies, profile content, full IDs, URLs, or local paths appear.

Live-sensitive parity rows remain `partial` until this checklist has real evidence. Automated stress coverage alone does not promote them.
