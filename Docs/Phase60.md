# Phase 60 - Reaction Encoding And Timeline Freeze Hardening

Phase 60 fixes the confirmed Unicode reaction HTTP 400 and removes the remaining long-channel preparation, layout-copy, and viewport-publication loops without changing the SwiftUI timeline, native Liquid Glass, 50-message pages, 250-message cap, avatar behavior, or optimistic reaction contract.

## Confirmed Root Causes

- Reaction call sites already percent-escaped Unicode path components, but `StoatRequestBuilder` joined them through `URLComponents.path`. Foundation then escaped the existing percent signs, turning `%F0...` into `%25F0...`. The official SDK passes Unicode or custom emoji IDs directly and the backend validates the decoded route component, so the route itself remains unchanged.
- The timeline created one eager nested `VStack` per author group and copied the full `MessageRow` value payload during layout.
- Every loaded message was prepared in one detached map, so opening a capped 250-message channel still parsed Markdown and derived media/actions for all 250 rows.
- Every row appearance/disappearance synchronously published viewport, validation, diagnostics, and acknowledgement state. Rapid scrolling therefore fanned hundreds of geometry events into whole-timeline observation updates.

## Implemented Behavior

- `StoatRequestBuilder` now combines already-escaped route components through `percentEncodedPath`; query items remain owned by `URLComponents`.
- Reaction request tests cover Unicode, variation selectors, custom emoji IDs, add/remove methods, `remove_all`, and prove one encoding pass with no `%25`.
- `TimelineRenderItemBuilder` flattens message groups into one stable item per message. The `LazyVStack` owns those items directly while header/group spacing, message IDs, edits, replies, actions, reactions, system events, and send-status rows remain intact.
- `MessageRow` retains its source-compatible initializer but stores immutable values and callbacks in one internal reference object, avoiding repeated multi-kilobyte value copies during layout.
- Each message owns a stable observable `TimelineRowPresentationState`. A completed preparation publishes only through that row state.
- The single-worker preparation queue starts with at most 32 rows around the current jump/unread anchor, or the newest 32 by default. Visible rows promote ahead of queued startup work, with eight rows of lookahead in each direction. Requests dedupe by channel/message/revision, reaction-only changes do not rebuild Markdown/media/actions, and stale channel results are discarded.
- An unprepared visible row shows `TimelineSkeletonRow`: an avatar circle and two text bars. Its left-to-right shimmer is a Core Animation layer, not a SwiftUI animation; Reduce Motion leaves the same placeholder static and dismantling the row removes all layer animations.
- Visibility events update an observation-ignored pending set immediately. Media cancellation stays immediate, while viewport state, validation, diagnostics, and acknowledgements publish once after the configured 120 ms quiet period. Channel changes cancel stale flush and row work.
- Developer diagnostics add redacted Phase 60 visibility-event/coalesced-flush, row request/dedupe/completion/stale-discard, active-skeleton, and maximum-queue-depth counters.

## Automated Verification

Phase 60 coverage verifies:

- single-encoded reaction URLs for Unicode, variation-selector emoji, and custom IDs across add/remove and query handling;
- 250 messages from one author become 250 stable direct render items with one preserved group header;
- startup preparation is bounded to 32, defaults to the newest rows, centers around an anchor, promotes visible rows, and adds eight-row lookahead without duplicates;
- hundreds of visibility events coalesce into one viewport publication and a channel switch prevents the stale flush;
- prepared content is held by distinct stable row states;
- shimmer is enabled normally and static under Reduce Motion.

Run before completion:

```sh
swift test --package-path Packages/StoatAPI
swift test --package-path Packages/StoatFeatures
swift test --package-path Packages/StoatUI
git diff --check
Scripts/check.sh
```

## Live Evidence Entering Phase 60

- **Pass:** cached avatars, uncached progressive avatars, settled idle CPU, and repeated sending.
- **Current failure:** adding the visible Unicode reaction returns HTTP 400 because the emoji path was double-encoded.
- **Current failure:** loading/rapidly scrolling a long channel can freeze or churn.

The reaction and large-channel performance rows remain `partial`. Repeat acceptance must prove add/remove survives realtime echo and reload, a 250-message channel stays responsive, CPU settles below 10% within two seconds, and a fresh sample contains no repeating viewport-publication, full-timeline-preparation, or row-layout invalidation loop. Avatars, sends, signed notifications, and settled idle behavior must remain green. Two-account propagation and native macOS parity checks remain deferred.
