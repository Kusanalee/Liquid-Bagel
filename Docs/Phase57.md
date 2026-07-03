# Phase 57 - Live-QA Round 4 Hardening

Phase 57 responds to the fourth live-QA report. Rapid server/DM switching, large-server identity completeness, media playback, toolbar title morphing, group creation, and custom status propagation passed. The remaining regressions were inaccessible message-row actions, a brief avatar fallback during send reconciliation, sustained idle CPU near one core after large member/media activity, and persistent bottom status capsules.

## Implemented Behavior

- **Full-row message interaction:** normal message rows fill the timeline width and provide an explicit rectangular hit-test shape. Hover, selection, and the existing context menu now work from row whitespace without taking link, attachment, avatar, or reply-preview actions away from their controls.
- **Warm decoded-avatar continuity:** the bounded decoded-image pipeline keeps a main-actor front index of already-decoded images. Recreated optimistic/confirmed rows can paint a warm avatar synchronously while all cache misses still decode off-main.
- **Visibility-driven image loading:** render-time image reads are cache-only. Timeline and member rows explicitly register visible avatar consumers, balance them on disappearance, and no longer bulk-prefetch offscreen members.
- **Bounded churn prevention:** the 64 MB presentation cache evicts nonvisible entries first, never reloads merely because SwiftUI evaluated a missing image, and records eviction/reload/queue counts. Member-only avatar completions do not invalidate timeline row presentation.
- **Quiet global feedback:** routine successes remain silent and diagnostics-only. Non-inline warnings and errors appear in one top-center notice, dismiss automatically after four/eight seconds, support manual dismissal, and use opacity-only motion when Reduce Motion is enabled. Actual in-app message notification banners are unchanged.

## Automated Verification

Targeted coverage includes cache-only image reads, explicit visibility deduplication, large-member loading without bulk prefetch, visible-key-aware eviction, settled queues after eviction pressure, member-only invalidation isolation, synchronous decoded-image availability, transient-notice policy/expiry, existing message-action availability, and Phase 56 optimistic/confirmed first paint.

Required final gate:

```sh
swift test --package-path Packages/StoatUI
swift test --package-path Packages/StoatFeatures
git diff --check
Scripts/check.sh
```

Completed verification:

- Phase 17/54/56/57 targeted feature slice: 21 tests passed, including documented/runtime parity-matrix status drift.
- Full `StoatFeatures`: 335 tests passed.
- Full `StoatAPI`, `StoatDesignSystem`, `StoatModels`, `StoatPersistence`, `StoatRealtime`, and `StoatUI` suites passed.
- `git diff --check` passed.
- The macOS application build ended with `** BUILD SUCCEEDED **`.

This remains implementation proof only. The live hit-target, avatar continuity, idle CPU, and memory-stability checks below are still required.

## Live QA Still Required

1. Hover and right-click the whitespace and text portions of normal rows; reply, react, edit, pin, copy, and delete where permitted.
2. Confirm links, attachments, author profiles, and reply previews still receive their own clicks.
3. Send repeatedly and confirm pending-to-confirmed reconciliation never flashes the avatar fallback.
4. Repeat the 2,324-member plus media-heavy scenario, wait for queues to settle, then idle for 30 seconds. Activity Monitor should average below 10% CPU on the same machine and an Instruments sample must show no repeating image/decode/presentation loop.
5. Leave the warmed app open for five minutes and confirm memory stabilizes rather than growing monotonically.
6. Trigger successful custom-status/member refresh actions and confirm no global notice; trigger a safe failure and confirm the animated, manually dismissible top notice.

Affected live-sensitive rows remain `partial` until this evidence is recorded.
