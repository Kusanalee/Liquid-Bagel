# Phase 63 - Composer Isolation, Reliable Bio Disclosure, And Timeline Smoothness

Phase 63 responds to a sampled live hang after queuing a pasted image, typing text, and inserting two Unicode sobbing emoji through macOS text input. The 1.8-second sample kept the main thread inside one SwiftUI/AttributeGraph layout transaction: lazy timeline placement, stack alignment, and value copying dominated. Image decoding, upload, networking, and emoji parsing did not dominate the sample.

## P0 Composer Hang

- The selected-channel composer is now a separate observation boundary below the chat container. Draft text, attachments, readiness, reply state, emoji presentation, mention state, and composer callbacks no longer make the sibling timeline participate in a keystroke update.
- Identical drafts are ignored, native text input suppresses duplicate inline-trigger reports, and clearing an already-empty mention state is a no-op.
- The typing-end deadline uses one coalesced worker rather than creating and cancelling a task for every character.
- Emoji sections are cached by context/snapshot revision and attachment chips are cached by attachment state, so ordinary typing does not re-sort server emoji or rebuild preview presentation.
- Developer diagnostics expose categorical edit, mutation, trigger, typing-deadline, timeline-baseline, and visibility-lease counters without recording draft text, emoji content, filenames, paths, or clipboard data.

## P1 Biography Disclosure

- Prepared Markdown overflow is measured by an uncapped, non-interactive subtree at the exact card content width. The visibly clipped subtree is never used as the full-height measurement.
- Preparation and measurement carry the current user/content/width generation. Placeholder geometry and stale tab/profile completions cannot classify the current biography.
- Confirmed overflow always offers `See More`; confirmed fitting content is not clamped. Expansion remains inside the profile card scroll view and resets when profile content changes.

## Timeline Smoothness

- Phase 60 direct lazy rows, Phase 61 render identity, immutable boxed render payloads, and row equality remain in place.
- Timeline avatar and inline-preview release deadlines share one 750 ms lease worker. Rows recycled back into view cancel their lease; channel changes clear departing work immediately.
- Visibility lookup uses the grouping-owned message index and Phase 60 keeps its bounded visible-first preparation and 120 ms viewport publication debounce.

## Automated Proof

- The native AppKit regression pastes image data through a scratch pasteboard, then drives text plus `😭😭` through `NSTextView.insertText`, matching the Keyboard/Character Viewer path.
- A 250-message regression proves image queueing and three draft edits do not change grouping builds, row requests, or viewport flushes; a duplicate final edit is suppressed.
- Visibility coverage proves forty expiring rows share one worker, reappearance cancels release, and channel changes clear pending work.
- Biography coverage rejects stale prepared generations and retains the no-clamp-without-disclosure invariant.

## Live QA Required

- In both a short and capped 250-message channel, repeat image paste -> ordinary text -> `😭😭` through Keyboard/Character Viewer. The chip and draft must remain intact and input/cursor movement must stay immediate.
- Capture a fresh sample during the sequence. No repeating lazy-placement/AttributeGraph layout loop or app-owned main-thread operation above 50 ms should remain.
- Reopen very long Markdown biographies repeatedly and switch through both mutual tabs. `See More`, expansion, internal scrolling, and `Show Less` must work every time; short biographies must remain undisclosed.
- Rapidly scroll a media-heavy 250-message channel for ten seconds, then confirm CPU settles below 10% within two seconds and stays settled through a 30-second idle observation.

The composer fix, biography repair, and timeline optimization have implementation/test proof only. Live-sensitive biography and large-channel performance rows remain `partial` until the repeated live checks pass.
