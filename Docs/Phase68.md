# Phase 68 - Trace-Driven Invalidation and Emoji Hardening

Phase 68 is a narrow performance-hardening pass derived from the 104-second Release Instruments capture `Liquid Bagel Profile 1.trace`. It does not change Stoat routes, payloads, timeline structure, cross-server emoji policy, animation support, or cache budgets. Large-channel and large-server performance remain `partial` until the repaired Release build completes the focused live capture below.

## Trace Evidence

- Instruments reported no hangs, crashes, or runtime issues. Recording ended because Stop was pressed.
- `AppKitPopUpAdaptor.updateNSView` used 116 ms total and no contiguous run exceeded 2 ms. The Phase 65 hidden-menu regression was absent.
- `measureEstimates` used 1.089 seconds in scattered layout/scrolling work, with no contiguous run above 27 ms. The Phase 64 full-history measurement loop was absent.
- CPU peaked at 110.9% during active interaction, then repeatedly returned to approximately 0.8-5.6%. A bounded instantaneous peak is not treated as a failure.
- Physical footprint peaked near 249 MiB while media loaded and later returned to roughly 124 MiB resident. This capture does not prove a leak.
- Three smaller app-owned costs remained material: repeated member-list preparation after identical identity delivery, synchronous full visible-identity diagnostics scans, and repeated full custom-emoji catalog lookup/equality work.

## Identity and Member-List Invalidation

`Phase43IdentitySnapshotStore` now treats repeated identical user, member, profile, and removal delivery as a semantic no-op. Generations and timestamps advance only for presentation-relevant changes, including a new source category, increased confidence, identity text, avatar metadata, bot metadata, profile data, or a server overlay change.

The nested `merge(member:user:)` path preserves user-change reporting. If the embedded user changes while its server overlay does not, the call still returns `true`, but the overlay generation and timestamp are not restamped.

The member-list presentation key no longer depends on the global Phase 43 identity generation. It combines the selected server's member/role/presence fingerprint with a per-server identity-presentation revision. A revision advances only when the identity fields capable of changing that server's member rows change, or when selected-server member hydration/removal replaces server member state. Profile biography/background changes, another server's identities, DM-only identities, repeat row appearance, messages, and media completion do not invalidate the selected member list.

Detached preparation, cancellation, stale-result rejection, role grouping and ordering, and the existing cached render path remain unchanged.

## Coalesced Visible-Identity Diagnostics

Normal diagnostics invalidation is latest-only and coalesced. The main actor snapshots immutable value data, aggregation runs in a detached utility task, and publication succeeds only when the captured generation is still current. A stale build is discarded and one build for the latest generation is scheduled.

Each build computes its missing visible user-ID set once while aggregating timeline authors, system-event targets, DM recipients, and selected-server members. Normal scrolling, member appearance, hydration, avatar failure, and profile work no longer synchronously perform the full developer-diagnostics scan.

The explicit **Copy Identity Diagnostics** action retains a synchronous refresh so copied evidence reflects the current screen. Existing categorical fields and redaction remain intact.

## Custom-Emoji Index and Picker Artwork

Phase 68 adds one immutable custom-emoji index keyed by emoji ID and normalized shortcode. It is rebuilt only when `snapshot.emojisByID` changes and is reused across reaction resolution, inline content tokens, visible-row image requests, row preparation, composer grouping, and search metadata.

Current-server lookup precedence and detached emoji fallback are preserved. Other-server emoji remain excluded from a selected server's message context. Colon-token scanning deduplicates referenced emoji and skips fenced Markdown code, so literal examples do not trigger invisible image loads. `loadCustomEmojiImages(for:)` now examines only reaction keys and content tokens in the message rather than mapping, filtering, and sorting the entire catalog for every row.

Composer sections are stable metadata only. `EmojiPickerItem.imageData` does not change as artwork arrives. `GlassComposer` and `EmojiPickerPopover` accept a source-compatible optional artwork resolver; each visible custom cell resolves cached bytes and requests its own image only when absent. Image completion therefore updates the visible cell without rebuilding or comparing the complete section array.

## Safe Counters

Developer diagnostics and the copied identity report include categorical counters for:

- semantic identity no-op merges;
- relevant per-server member-list invalidations;
- emoji-index builds and cache hits;
- visible-identity diagnostics requests, coalesced requests, builds, and stale results.

The counters contain no IDs, content, URLs, paths, or payloads.

## Automated Proof

Phase 68 regression tests cover:

- identical user/member/profile/removal merges preserving generations and timestamps;
- nested member merges reporting a user-only change without restamping the server overlay;
- repeated appearances, another-server identity changes, and profile-only changes preserving the selected member-list token;
- one selected-server identity change advancing the token exactly once;
- current-server duplicate shortcode precedence, other-server exclusion, token deduplication, and fenced-code literal behavior;
- emoji-index reuse across unrelated snapshot changes and rebuild after a catalog change;
- visible rows requesting only their referenced current-server emoji, with no duplicate request on repeat appearance;
- latest-only diagnostics coalescing and current publication;
- picker section metadata remaining equal while visible artwork becomes available through the resolver.

The acceptance gate is the focused Phase 43/52/60/65/67/68 coverage, complete StoatUI and StoatFeatures package suites, `git diff --check`, and `Scripts/check.sh`.

Completed automated validation for this implementation:

- focused Phase 68 suite: 9 tests passed;
- focused Phase 43/52/60/65/67/68 lane: 16 tests passed;
- complete StoatUI suite: 41 tests passed;
- complete StoatFeatures suite: 399 tests passed in the final repository gate;
- `git diff --check`: passed;
- `Scripts/check.sh`: all package suites passed and the signed macOS app build succeeded.

## Focused Live Retest

Run a Release Instruments capture with the member panel open while loading the capped channel. Scroll with the pointer inside and outside the timeline, cross message-action boundaries, open and search the emoji picker, insert a current-server custom emoji, and allow emoji/avatar artwork to settle.

Pass conditions:

1. No freeze, beachball, row movement, hover flicker, or rewrapping.
2. CPU settles below 10% within two seconds after interaction.
3. No sustained app-owned main-thread operation exceeds 50 ms.
4. `AppKitPopUpAdaptor` does not dominate and `measureEstimates` does not form a full-history loop.
5. Identical visible identities do not keep advancing identity generation or retriggering selected-server member grouping.
6. Normal interaction stacks contain no material `updateVisibleIdentityDiagnostics` aggregation.
7. `loadCustomEmojiImages`, catalog sorting, and whole `EmojiPickerSection` equality are no longer material main-thread hotspots.
8. Member names, nicknames, roles, presence grouping, bot state, avatars, profile opening, reaction artwork, picker search/insertion, and sent-message rendering remain correct.
9. Jump-to-newest, load-older position preservation, and unread-separator scrolling remain correct.
10. After a 30-second settled period, image queues stop changing, CPU remains below the gate, and memory shows a stable plateau rather than monotonic growth.

Brief CPU peaks during active scrolling, decoding, and first member hydration remain acceptable when bounded and followed by rapid settling. Existing off-main decoding and cache budgets remain unchanged unless a longer follow-up capture establishes a leak.
