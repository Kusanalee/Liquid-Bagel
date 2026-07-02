# Phase 52 - Full Freeze Elimination

Phase 52 addresses the sampled large-thread freeze at its source and hardens the remaining presentation, realtime, media, and file-I/O paths. It preserves automatic member hydration, current message caps, routes, wire models, and persistence formats.

## Implemented Behavior

- Realtime state now publishes `RealtimeSnapshotUpdate` envelopes with exact impact metadata. Bulk gateway events union their changes and publish once; each subscriber keeps one pending newest snapshot while coalescing every pending change set, and control events with no state mutation are not published.
- The shell consumes update envelopes and reconciles only affected users, members, messages, unread state, typing state, moderation state, notifications, and presentation caches.
- REST member hydration prepares all 2,001-member-scale mutations and identity merges away from the main actor, then installs one snapshot and one identity batch.
- Member and timeline presentation use cancellable, latest-result preparation while retaining the last coherent interactive view. Timeline grouping is keyed only to channel/message revisions, so media, identity, and unrelated snapshot refreshes cannot blank loaded messages while rich row presentation catches up.
- Timeline rows receive prepared Markdown, emoji, attachment, embed, reply, reaction, and identity presentation instead of parsing or sorting during SwiftUI rendering.
- Large Quick Switcher indexes and searches run away from the main actor with cancellation and latest-query-wins delivery.
- File panels are asynchronous. Local reads, temporary writes, and save writes run away from the main actor; render paths no longer call `NSImage(contentsOf:)`.
- Raw image presentation data is capped at 32 MB, decoded images at 128 MB, and attachment previews at 64 MB. Markdown block and inline caches have entry and byte bounds.
- Per-row layout logging and render-time diagnostic mutations were removed.
- Redacted Phase 52 counters cover snapshot installs, member/identity batch commits, preparation duration, coalesced realtime updates, timeline grouping/row rebuilds, stale-result discards, cancellations, and main-thread budget violations.

## Automated Verification

Coverage includes atomic and coalesced realtime publication, empty-control suppression, precise message/typing impacts, interleaved REST/realtime history loading, 2,001-member preparation, cancellation and latest-result behavior, visible timelines across media/identity churn, every conversation kind, 250-message prepared timelines, 5,000-channel Quick Switcher search, and deterministic cache bounds.

Run:

```sh
swift test --package-path Packages/StoatRealtime
swift test --package-path Packages/StoatUI
swift test --package-path Packages/StoatFeatures
git diff --check
Scripts/check.sh
```

## Live Acceptance

Repeat the supplied large-thread scenario with the member panel open and capture a new sample. Acceptance requires:

1. No sustained app-owned main-thread operation above 50 milliseconds.
2. No hydration or identity-merge stack dominating the sample.
3. One member snapshot installation and one identity batch for a hydration response.
4. Memory stabilizing within the configured media-cache budgets.
5. Typing, scrolling, menus, and the last coherent member presentation remaining interactive during preparation.

Automated stress coverage is implementation proof only. Performance parity remains `partial` until this live sample is captured successfully.
