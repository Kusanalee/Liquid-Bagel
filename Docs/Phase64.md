# Phase 64 - Channel-Load Freeze Regression Fix

Phase 64 responds to a live QA blocker introduced by Phase 63: loading a channel froze the app at 100% CPU before any of the Phase 63 acceptance passes could run. A 1.77-second sample kept the main thread inside one SwiftUI layout transaction: `StackLayout.placeChildren -> sizeChildrenIdeally -> ScrollViewLayoutComputer -> LazyVStackLayout -> LazyStack.measureEstimates` fully measuring every loaded message row, with `LazyLayoutViewCache.updatePrefetchPhases` array churn and text-selection `SelectionOverlay` font invalidations as downstream cost.

## Root Cause

- Phase 63 added `.layoutPriority(1)` to `MessageTimelineView` in the chat container as a window-resize mitigation.
- A layout-prioritized child is asked for its ideal size. A vertical `ScrollView` answers an ideal-height query with its content's total height, which forces the timeline `LazyVStack` to measure every loaded row — markdown with `fixedSize`, selection overlays, attachments, and embeds — instead of only visible rows.
- With a capped 250-message channel this single pass is effectively unbounded; laziness is the only thing that made those rows affordable.

## Fix

- Removed `.layoutPriority(1)` from the timeline and replaced it with a guard comment explaining why the timeline must keep default stack priority. With all three chat-container children at default priority, the `ScrollView` receives the flexible remainder in a concrete proposal and the `LazyVStack` stays lazy — the known-good layout of Phases 1–62.
- No other code changed. The Phase 63 composer observation boundary (`SelectedChannelComposerView`), row `.equatable()` fast path, boxed render payloads, and the single coalesced visibility-lease worker are all retained; each was verified against the sample and none participates in the freeze.
- No replacement resize mitigation ships in this phase. If a window-resize hang reproduces live, the follow-up is a `safeAreaInset`-based toolbar/composer restructure with full scroll-intent QA — never layout priority on the ScrollView subtree.

## Automated Proof

- The existing Phase 63 suites pass unmodified: composer-isolation 250-message no-rebuild, render-item equality/hashing, coalesced-lease coverage, and the native AppKit paste/emoji regression. No test referenced the removed modifier.
- `Scripts/check.sh` and the macOS app build pass.

## Live QA Required

- Open the capped 250-message channel. The timeline must appear immediately; a fresh `sample` must show no `measureEstimates`/`sizeChildrenIdeally` layout loop; CPU must settle below 10% within two seconds.
- Resize the window continuously for ten seconds with the long channel loaded, then confirm the layout settles without a beachball (validates dropping the Phase 63 resize mitigation).
- Type roughly twenty characters and confirm composer isolation still holds: accepted draft mutations increment while timeline grouping-build, row-request, and viewport-flush counters stay flat.
- Re-verify scroll intents: jump-to-newest, load-older with position preserve, and unread-separator scroll.
- Then resume the blocked Phase 63 live acceptance list (attachment plus Character Viewer emoji, long-biography disclosure, rapid-scroll settling).

Bio and large-channel performance rows remain `partial` until the combined Phase 63/64 live passes complete.

## Live QA Result (2026-07-14)

- **Channel load passed:** the capped timeline appeared almost immediately. CPU briefly reached 87% and returned to 0% within one second; the Phase 64 full-history load freeze did not reproduce.
- **Resize remained partial:** continuous resizing did not freeze, but it was visibly laggy and reached roughly 150% CPU. Phase 65 moves toolbar/composer chrome to timeline safe-area insets without restoring timeline layout priority.
- **Composer isolation passed:** typing stayed immediate and the Phase 63 isolation behavior held. Live QA exposed a separate row-hover regression where inserting the action bar changed message width and shifted content.
- **Scroll intents passed:** jump-to-newest, load-older position preservation, and unread scrolling worked. Rapid scrolling still felt laggy, so large-channel performance remains `partial`.
- **Blocked Phase 63 checks resumed:** attachment plus Character Viewer input passed, and long/short biography disclosure passed. The emoji picker exposed custom emoji as shortcode labels without artwork; Phase 65 adds bounded lazy picker artwork.

This live pass closes the Phase 64 channel-load blocker and the biography-disclosure retest. It does not promote large-channel performance or custom emoji to `done`.
