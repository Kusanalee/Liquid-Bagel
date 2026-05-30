# Phase 11 Summary

## What Was Implemented

Phase 11 hardens the in-memory timeline for higher-volume channels while keeping Liquid Bagel mock-safe. The app still launches in mock mode, does not auto-connect to Stoat, and does not validate saved credentials on launch.

Implemented:

- visible-range tracking from timeline row visibility
- stronger at-newest detection using newest visible or near-visible rows
- preserve-position anchors for loading older messages
- unloaded unread recovery state and explicit load-to-unread action
- reply reference resolver abstraction with mock in-memory resolution
- live reply reference resolver disabled as not supported because no single-message route is verified
- richer failed-send retry metadata and retrying state
- explicit loaded-range and pagination-boundary metadata
- visible-range-based local read and live ack selection
- lightweight token-free timeline diagnostics
- mock-only Phase 11 tests

## Timeline Behavior

`TimelineVisibleRange` records the active channel, ordered visible message IDs, first visible ID, last visible ID, and update time. SwiftUI rows report appearance and disappearance to the view model, which coalesces the unordered row events into the loaded timeline order before updating viewport state.

At-newest is true when the newest loaded message is visible or near the visible tail. Receiving new messages while at-newest keeps the tail selected and scrollable; receiving new messages while scrolled away shows the jump-to-newest indicator instead of forcing a jump.

Loading older messages captures the oldest visible message first, falling back to the oldest loaded message. A successful prepend requests a preserve-position scroll to that anchor; failed pagination leaves the viewport alone and stores a safe pagination error.

## Unread And References

Jumping to first unread still preserves the Phase 10 status text, “Unread message is not loaded,” when the target is outside the loaded range. Phase 11 also stores `UnreadRecoveryState.targetUnloaded` and exposes UI copy explaining that the unread target is outside the loaded range.

The explicit load-to-unread action performs bounded older-message pagination only after user action. It never starts a hidden loop. If the target appears, the timeline jumps to it; if history ends or loading fails, the recovery state records a safe missing/failed status.

Reply previews still resolve locally first. `MessageReferenceResolving` adds a mock/in-memory resolver for tests and previews. Live reference fetching returns `.notSupported` because this repository has no verified single-message fetch route; Phase 11 does not invent one.

## Retry, Pagination, Ack, And Diagnostics

Failed sends now preserve `FailedMessageRecoveryMetadata`: original content, original nonce, reply context, mention preference, created/attempt timestamps, attempt count, and last safe error. Retry marks the row retrying, prevents duplicate retry sends, increments attempts, and reconciles success by replacing only the local failed row. Edit-and-retry updates recovery content rather than treating the row as a server edit.

`ChannelLoadedMessageRange` tracks oldest/newest loaded IDs, `hasMoreBefore`, `hasMoreAfter`, optional around-target metadata, and the last safe pagination error. The UI distinguishes loading older, load older, and beginning of loaded history.

Local read state and live ack now prefer the newest visible message when the user is at-newest. Live ack remains Live Manual only, requires an explicit connected session, and still debounces duplicate message IDs.

`TimelineDiagnostics` exposes loaded count, loaded range, visible range, unread target, at-newest, pagination, pending reference fetches, and pending retries. It contains no tokens, credentials, raw responses, or session secrets.

## Tests Added

Added mock-only feature tests for:

- visible range first/last tracking and at-newest derivation
- loaded-range boundaries and unread recovery state
- failed-send retry metadata and double-retry prevention
- reference resolver caching and fallback behavior
- token-free timeline diagnostics

Existing mock-safe startup, no auto-connect, no auto-validation, live ack debounce, reply scaffolding, and message history tests continue to pass.

## Mocked Vs Live

Mock mode remains fully local. Live Manual still calls only previously verified REST routes after explicit user action. Live reply reference fetching is intentionally disabled because a single-message fetch route is not verified in this codebase.

No persistent message cache/database, background sync, notifications, uploads/media UI, full friends/discover APIs, voice, server/channel settings, full permission resolver, or hidden launch-time networking were added.

## Known Risks And Limitations

- SwiftUI row appearance is still a conservative approximation, not a custom virtualized timeline engine.
- The near-newest threshold is intentionally small and may need tuning after real scroll testing.
- Load-to-unread can only paginate older messages; it cannot fetch an arbitrary target directly.
- Live reply references remain unavailable until a single-message route is verified.
- Diagnostics include message IDs for developer use, but no secrets.

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

Run the app from the `LiquidBagel` Xcode scheme. It opens in mock mode. Use Account & Connection settings or the runtime chip to validate/connect manually.

## Recommended Phase 12 Next Step

Phase 12 should focus on validating the hardened timeline in a real connected session: tune visible-range thresholds, verify whether Stoat exposes a safe single-message fetch route, and consider a narrow non-persistent search or around-message fetch if the API supports it without introducing background sync.
