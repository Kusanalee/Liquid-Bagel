# Phase 72 - Chat Presentation Fidelity

Phase 72 closes the QA Lane 2 defects found in live use: markdown that rendered wrong, custom emoji and mentions that could not wrap, an autocomplete popover that sliced its own rows, and embed cards that did not read as native. All of it is StoatUI-local except one embed display-item property.

## Sources and Root Causes

- `MarkdownInlineContent` switched the whole paragraph from `Text` to a single-line `HStack` of per-token views as soon as any mention or custom emoji appeared. An `HStack` cannot line-break, so a mid-sentence mention refused to wrap and compressed or truncated the text around it. The alternative `wrappingAttributedText` path dropped every non-text token by construction, so it could never show a pill either.
- The autocomplete popover is an `.overlay` on the composer text field, so SwiftUI proposed it the field's height (34pt collapsed, 92pt maximum). The bare `VStack` accepted that proposal while holding up to ten two-line rows, so it under-allocated height and sliced them. The `alignmentGuide` then offset by the already-collapsed height, so the position was wrong by exactly the clipped amount.
- The block renderer collapsed all six markdown heading levels onto two fonts, measured list indentation *after* trimming it away, emitted one `.quote` block per `>` line, discarded the fence info string, and used a single uniform gap between every block pair.
- `EmbedTimelineCard` declared no `@Environment`, drew its accent bar as an overlay on top of the rounded background, printed the embed kind as visible text, duplicated provenance, and never consulted `EmbedImage.width/height` or `ImageSize`.

## Inline Composition

- One `Text` per paragraph. Mentions are tinted `AttributedString` runs and custom emoji are interpolated image glyphs, so SwiftUI line-breaks them exactly like words.
- Mentions carry `.link`, the only run attribute SwiftUI hit-tests, routed through a scheme-validating `MentionLinkRoute` and an `OpenURLAction` that returns `.systemAction` for ordinary URLs so real links keep working.
- The run is padded and name-joined with U+00A0, so a mention moves to the next line whole instead of splitting into two tinted fragments.
- Emoji `CGImage`s are seeded synchronously from `DecodedImageFrontCache` in `init` and filled by one `.task` per row. This is strictly fewer tasks than the previous one-per-image `DecodedDataImage`. `PreparedMarkdownContent` is deliberately untouched.

## Accepted Tradeoffs

- **The mention background is a rectangle, not a capsule.** A capsule cannot participate in line breaking. The only macOS 15 mechanism that could draw one per line fragment is `TextRenderer`, which replaces the text's drawing with a `GraphicsContext` pass: it has no selectable representation and no link hit-testing, and it applies to the whole subtree so it cannot be scoped to the pill. Adopting it would trade the wrap bug for losing text selection on every message body. `Text.LayoutKey` was also rejected: it is undocumented, and a preference flowing up from every row's text layout is the full-history measurement pass Phase 64 forbids.
- **Per-pill VoiceOver labels are gone.** A single `Text` is one accessibility element, and per-run accessibility is not expressible on an `AttributedString`. `accessibleDescription` now expands mentions inline to "mentions you", "mention, `<name>`", "channel mention, `<name>`", and "role mention, `<name>`", so every mention is still announced with its kind. QA Lane 7 step 6 is updated to match.
- Verified by pixel-sampling an `ImageRenderer` render that a run's `foregroundColor` survives `.link` styling (and is not overridden by `.tint`), so **role-colored mentions are preserved**. This was the one open design risk and it resolved in our favor.

## Markdown

- Six distinct, monotonically shrinking heading fonts.
- List depth is captured before trimming, capped at 4, and drives both indent and bullet glyph. Ordered markers keep the author's numbering.
- Consecutive `>` lines accumulate into one quote block; a blank line or a paragraph still separates two quotes. The quote bar is a capsule inset past the text rather than a square rectangle overlaid on it.
- Fence info strings are captured and shown as a label, validated against a conservative identifier so arbitrary text cannot become visible UI.
- Horizontal rules are supported. Block spacing is per-pair, so consecutive list items sit tighter than paragraphs.
- The inline HTML sanitizer's `<[^>]+>` pattern ate ordinary prose - `5 < 10 > 3` lost its middle. It is now HTML-tag-specific. `<b and c>` is still stripped deliberately: it is a well-formed `<b>` tag with attributes, so treating it as markup is correct.

## Embeds

- The accent bar is a laid-out sibling inside the clipped shape, so it is rounded with the card and no longer sits under the text.
- The card reads `colorSchemeContrast` and `accessibilityReduceTransparency` and carries a stroke border, matching `AttachmentTimelineCard`.
- The kind caption, the duplicated bottom URL, and the in-card Preview/Save As/Open/Retry button bar are gone. Media actions moved to the card's context menu, which also gains Open Link.
- Width matches `AttachmentTimelineCard` at 460/620, pinned by a test so the two families cannot drift apart again.
- `EmbedMediaLayout` sizes media from the model's declared dimensions, restoring the side-thumbnail variant for `ImageSize.preview`. Because the size is known before the image arrives, the placeholder is reserved at final size and **the row no longer reflows when media loads** - a freeze-gate improvement, not only cosmetic.
- The favicon is a bounded local monogram. Fetching `embed.iconURL` would break the "external embed media does not autoload" guarantee QA Lane 2 step 4 checks.

## Explicitly Deferred

- **Spoilers (`||x||`) and `__underline__`.** Phase 27 requires platform syntax to be verified before implementing it, and there is no verified source for either in Stoat. Implementing them on assumption would render literal user text incorrectly.
- **Syntax highlighting.** Tokenizing and coloring source per row is unbounded main-thread work on a lazy timeline - the Phase 51/64 hazard class. The fence language is captured and labeled, which is the useful half.
- **Tables.** Rare in Stoat, meaningful parser work, and a per-row `Grid` is fresh layout cost on the path Phase 64 regressed.

## Freeze Rules for This Subsystem

All of Phase 72 is per-row timeline work. These are hard constraints, not preferences:

1. Never add `.layoutPriority` anywhere in the timeline subtree. That was Phase 64's root cause.
2. No `GeometryReader`, no `PreferenceKey` reduction, and no `Text.LayoutKey` in a message row.
3. Do not put image data in `PreparedMarkdownContent`. It is `Hashable` and embedded in `TimelineRowPresentation` (`Phase51Runtime.swift:107`), which backs the Phase 63 `.equatable()` fast path. New block *cases* are fine; image payloads are not.
4. All decoding stays off the main thread via `DecodedImageFrontCache` plus `DecodedImageStore`. No `NSImage(data:)` in a render path.
5. Bound every new recursion and collection: list depth 4, inline tokens 200 before falling back to plain text.
6. `EmbedMediaLayout` must size from the model, never from the decoded image.
7. `.fixedSize()` on the autocomplete popover is safe because it lives in the composer overlay. Do not copy it into a message row.

## Automated Proof

- `testPhase62InlineMediaAndReferencesKeepTokenRow` asserted that emoji and mentions forced the `HStack` path, so **the test encoded the bug**. It is replaced by `testPhase72InlineMediaAndReferencesComposeIntoOneText`. This is a corrected expectation, not a regression.
- Two code-block expectations were updated for the block descriptor, which now carries the fence language; the block contents are unchanged.
- StoatUI grew from 42 to 59 tests covering composition, mention run text and link routing, accessibility expansion, emoji glyph scaling, popover sizing and offset, six heading levels, list depth, quote grouping, fence-language validation, rules, block spacing, sanitizer prose preservation, embed media placement, embed width parity, and site monograms.
- Every package suite passes and the macOS build succeeds.

## Live Retest

Re-run QA Lane 1 in full: per-row rendering changed, so the freeze gate has to be re-proved. Then QA Lane 2 steps 1-4, 14-18, 21, 23, plus the two new steps 24 and 25.

The affected parity rows stay `partial` until that live comparison is recorded.
