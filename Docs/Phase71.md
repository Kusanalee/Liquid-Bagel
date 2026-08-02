# Phase 71 - Composer Input Parity

Phase 71 closes the composer half of reference-token support without requiring a live server. It fixes emoji insertion at the native caret, generalizes inline autocomplete across users, channels, roles, and custom emoji, and aligns server/channel navigation with the verified official macOS shortcut table.

## Sources and Root Causes

- The backend parser already recognizes `<@ULID>`, `<#ULID>`, `<%ULID>`, and `:ULID:` outside code spans, while the composer only authored user mentions and picker-selected emoji.
- Picker insertion appended to the draft because no native `NSTextView` caret state reached the view model. The existing mention splice was the correct UTF-16 model but was not shared.
- The official `DEFAULT_MAC_SEQUENCES` table assigns Cmd-Up/Down to channels and Control-Cmd-Up/Down to servers. Liquid Bagel's previous modifiers were inverted, and Cmd-Down also collided with Jump to Newest.

## Composer and Autocomplete Fixes

- A plain, non-observed `ComposerCaretTracker` records collapsed AppKit selections and document UTF-16 length. SwiftUI reads it only when picker insertion occurs; stale or missing state safely appends.
- Emoji and autocomplete selection use one validated/clamped UTF-16 splice helper, publish a cursor request after the replacement, and preserve Phase 70 custom tokens byte-for-byte. Closing the picker explicitly re-requests native composer focus.
- `ComposerAutocompleteKind` and kind-scoped candidate IDs drive one popover and one alias-aware, capped prefix index. User avatars, channel glyphs, sanitized role colors, and lazily requested custom-emoji artwork are kind-specific row accessories.
- Detection supports `@`, `#`, `%`, and `:`. It rejects email/percentage adjacency, whitespace, numeric and hex-color channel shapes, numeric roles, invalid shortcode characters, completed emoji tokens, and sigils inside inline code. Emoji queries require two characters to preserve the Phase 63 no-churn path.
- Channel results reuse the Ready/sidebar selectable-channel predicate and then restrict to text channels. This is Ready-scoped visibility, not `ViewChannel` evaluation. All server roles are offered because the model has no `mentionable` flag. Unicode alias typeahead remains out of scope because there is no verified alias table.

## macOS Keybinds

- Channel navigation is Cmd-Up/Down; server navigation is Control-Cmd-Up/Down.
- Jump to Newest keeps its menu action but has no separate key equivalent. Escape remains the verified combined mark-read/jump-end/focus action.
- The mapping lives in `Phase71Keybinds` so package tests pin the exact table and reject duplicate navigation shortcuts. Because menu shortcuts are global, Cmd-Up/Down no longer invoke native document-begin/end movement inside the composer.

## Automated Proof

- StoatUI tests cover the default user-kind compatibility anchor, all sigils, negative numeric/hex/time/URL/percentage/completed-token cases, code-span suppression, and kind-scoped candidate identity.
- StoatFeatures tests cover surrogate-pair caret splicing, nil/stale fallback, channel/DM scope, role rank/color, exact channel/role tokens, picker/typeahead emoji token identity, Phase 68 index reuse, alias ordering/capping, the verified shortcut table, and Phase 63 nil-trigger diagnostics.
- The focused Phase 58/63/68/70/71 lane passed 12 StoatUI and 44 StoatFeatures tests. The final full check passed 42 StoatUI tests, 408 StoatFeatures tests, every other package suite, and the signed macOS build on August 2, 2026.

## Focused Live Retest

1. Exercise `@`, `#`, `%`, and `:` in the middle of a draft; verify keyboard navigation, exact insertion, and final caret position.
2. Insert picker emoji at a mid-draft caret and confirm the composer immediately regains first responder.
3. Send the same custom emoji from picker and typeahead; compare wire text and artwork with Stoat Web.
4. Confirm the negative cases in QA Lane 2 do not open the popover.
5. Verify Cmd-Up/Down channels, Control-Cmd-Up/Down servers, and Escape jump-end/read/focus behavior in the running app.

The affected parity rows remain `partial` until this live comparison is recorded.
