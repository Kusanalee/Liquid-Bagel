# Phase 14 Summary

## What Was Implemented

Phase 14 makes selected-channel search feel connected to the loaded timeline while keeping search state local, explicit, and non-persistent.

Implemented:

- in-memory timeline search highlight state
- row-level highlighting for loaded search results
- stronger current-result highlight
- cycling next/previous result navigation
- scroll intent for loaded current results
- explicit unloaded-result status and load-around affordance
- timeline search count/status strip
- clear search highlights command and Escape lifecycle
- search highlight accessibility labels
- redacted calibration note import
- default tuning decision workflow
- safer tuning recommendation copy before applying
- mock-only tests for highlighting, navigation, accessibility, calibration decisions, and redaction

## Search Highlighting

`TimelineSearchHighlightState` is memory-only and scoped to the active selected channel. It stores the query, search mode, ordered result IDs, current result ID, and unloaded result IDs. It is cleared when the selected channel changes, when search is cleared, or when there are no active results.

Loaded result rows receive a modest row-level highlight. The current result receives a stronger border. Normal message selection and focus styling remain separate from search highlighting, so a selected message and current search result are visually distinct.

Highlight styling respects the existing accessibility environment:

- Reduce Motion avoids animated scroll/highlight behavior.
- Reduce Transparency uses a more solid fill.
- Increased contrast strengthens the border/fill.
- Compact density keeps the same stable row layout.

Inline substring highlighting remains deferred; Phase 14 uses row-level highlighting only.

## Navigation And Lifecycle

Next and previous search result commands now cycle through the current result list. Loaded results update the current highlight and request a timeline scroll intent. Unloaded results stay selected in the result model, show “Result outside loaded range,” and expose “Load Around Result” only when the source-verified route capability is available.

Clear search removes result/highlight/current search state without clearing loaded messages. Closing the search panel does not unload messages. Escape closes transient UI first; if the search panel is already closed, it can clear transient highlights.

Live search and pinned search still run only after explicit user action. There is no search while typing, hidden live search, persistent index, global search, or message database.

## Calibration Decision

Phase 14 inspected existing docs and code for real Live Manual calibration notes. None were recorded beyond Phase 13’s advisory text, so the documented default tuning decision is to remain Conservative.

The Developer Timeline Calibration section now supports redacted manual note import. Imported text is redacted immediately and used only in memory to produce an advisory `TimelineDefaultTuningDecision`.

Decision behavior:

- no notes: remain Conservative
- clean Balanced notes: recommend Balanced
- noisy or mixed notes: remain Conservative
- custom calibration recommendation: recommend the custom validated tuning

Applying a recommendation remains explicit. Tuning persistence is limited to the existing `timelineTuning` preference; raw imported notes and search state are not persisted.

## Security And Redaction

Phase 14 keeps the existing safety boundaries:

- no automatic live connect on launch
- no automatic credential validation on launch
- no hidden network behavior
- no persistent message cache
- no persistent search index
- no tokens in diagnostics, calibration copy, search snippets, or accessibility labels
- no raw server responses in user-facing errors

New copied or imported calibration text uses the existing token-like redaction helper.

## Tests Added

Added mock-only coverage for:

- loaded and unloaded highlight classification
- current result initialization and accessibility labels
- cycling search navigation and scroll intents
- unloaded result status and clear lifecycle
- channel switch highlight clearing
- search style differences for current, high contrast, and reduce transparency
- conservative default decision without real notes
- Balanced advisory from clean imported notes
- conservative decision for noisy notes
- calibration note redaction

## Deferred

Still deferred: persistent search, global search, background sync, notifications, uploads/media UI, full friends/discover APIs, voice, server/channel settings, full permission resolver, moderation tools, and live automated tests requiring credentials.
