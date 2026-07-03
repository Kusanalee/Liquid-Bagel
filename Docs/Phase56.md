# Phase 56 - Live-QA Round 3 Hardening

Phase 56 responds to the third live-QA pass after the member-panel freeze and media-memory fixes. It keeps the existing architecture and mock fixtures, fixes the new send-render regression first, then hardens member identity, avatars, attachments, video presentation, and the macOS title treatment.

## Implemented Behavior

- **Immediate timeline paint:** per-channel presentation revisions are observable. A stale or missing grouping cache synchronously groups the capped 250-message history for first paint, while the existing detached grouping and row-presentation builders continue to own the prepared caches. Optimistic sends, confirmations, realtime messages, edits, reactions, deletes, and channel switches no longer wait for channel re-entry.
- **Stable hydrated members:** selected-server REST hydration now retains its merged user records alongside member records. Sparse Ready/realtime snapshots fill from that overlay, while user records present in the gateway snapshot remain authoritative for presence and status. Member leaves remove both overlay records, and account/environment/connection-generation changes clear the scoped overlay.
- **Self-healing avatars:** a render-time image-data miss schedules a deferred, deduplicated request through the existing bounded queue instead of mutating observed state during view evaluation. The presentation-data budget is 64 MB; memory and disk caches, concurrency limits, failure cooldowns, and eviction remain bounded.
- **Transient media retry:** image and attachment HTTP loads retry at most twice after the first attempt for timeouts, connection loss, HTTP 408/429, and 5xx responses. `Retry-After` is honored up to five seconds. Cancellation, permanent client errors, invalid content, and oversized files do not retry.
- **Video posters:** playable MP4/MOV/M4V cards lazily request an early-frame poster through a StoatUI actor. Requests coalesce by URL and use a 40-entry/16 MB memory-only LRU. Poster failure leaves the existing native player fallback unchanged.
- **Tahoe title glass:** the principal toolbar title uses a reusable design-system capsule. macOS 26 uses native `glassEffect`; macOS 15-25 uses regular material. Reduce Motion, Reduce Transparency, increased contrast, and the existing Liquid Glass transparency preference remain authoritative.

## Safety Boundaries

- No new Stoat routes, request fields, hidden broad profile hydration, background member fetching, or persistent video-thumbnail cache.
- True unresolved identities remain in the Unknown section rather than being mislabeled as offline.
- Retry work is bounded and cancellation-aware; 403/404 responses are never hammered.
- Mock runtime infrastructure remains available only through the existing test/preview seams.

## Verification

Targeted coverage includes immediate optimistic/confirmed timeline paint, channel switching, sparse-gateway user-overlay retention and member-leave cleanup, deferred avatar reload deduplication, transient media recovery/permanent-error behavior, video-poster cache eviction, presence regression coverage, and design-system compilation.

Final acceptance requires:

```sh
swift test --package-path Packages/StoatDesignSystem
swift test --package-path Packages/StoatUI
swift test --package-path Packages/StoatFeatures
git diff --check
Scripts/check.sh
```

## Live QA Still Required

1. Send in a server channel and confirm the pending/confirmed row appears without leaving the channel.
2. Switch rapidly across loaded channels and confirm no normal “Preparing messages…” pause or previous-channel rows.
3. Leave the 2,324-member panel open while realtime events arrive; confirm hydrated names and avatars do not collapse back to Unknown.
4. Revisit media-heavy channels and confirm evicted avatars reload, transient attachment failures recover, and memory remains bounded.
5. Confirm video posters appear lazily and native playback still starts on click.
6. Confirm the toolbar capsule morphs cleanly between short and long channel names with normal and reduced transparency/motion settings.

Affected live-sensitive parity rows remain `partial` until this pass is recorded.
