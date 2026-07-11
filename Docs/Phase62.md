# Phase 62 - Rail Avatar Continuity And Profile Card Repair

Phase 62 follows the completed Phase 61 live retest. Clipboard image/file paste now passes with empty and non-empty drafts, chat-row avatar continuity passes through send confirmation, Unicode reactions pass, and rapid scrolling settles from a brief peak to 0-10% CPU within two seconds. The remaining avatar failure is isolated to the always-visible current-user item in the server rail.

## Implementation

- The current-user rail avatar now registers one stable `shell-current-user-avatar` visibility consumer. Cache pressure cannot evict its decoded bytes while the rail is visible, avatar-file replacement transfers that pin to the new resource, and rail disappearance releases it.
- The existing current-user presentation fallback continues to fill avatar/display metadata from the authenticated user when a realtime snapshot contains a partial user object.
- The shared profile popover remains anchored to the main window but now uses a fixed 480-by-560 rectangular, vertically scrollable card.
- Profile actions use an adaptive grid, the segmented picker hides its redundant label, role chips wrap through an adaptive grid, and profile Markdown receives the full card width.
- Profile bios measure their rendered Markdown height. Overflowing bios start at a bounded preview with `See More`, expand inside the profile scroll area, and offer `Show Less`; short bios do not show a disclosure control.

## P1 Remediation: Partial Identity Churn And Bio Width

The first Phase 62 live pass failed two paths. The upper-left current-user avatar still flashed during sends and warmed-channel scrolling, and long bot-profile biographies collapsed into narrow vertical columns. Profile actions, tabs, roles, and the `See More` / `Show Less` interaction otherwise passed.

- Phase 43 avatar cache invalidation now follows the same source-aware merge contract as identity metadata. Missing avatars from embedded message/member/Ready/hydration records preserve the existing file and cached bytes; only a real replacement or an authoritative realtime/current-user-edit removal invalidates them.
- A visible current-user replacement transfers the stable rail request before loading, and the rail retains its last decoded art until the replacement is ready. Partial identity churn therefore cannot expose initials during sends, timeline preparation, or scrolling.
- Text-only inline Markdown now renders as one wrapping text flow instead of an intrinsic-width token row. Profile content receives the card's explicit inner width before height measurement, while custom emoji and mention/reference pills retain their existing token-row path.
- Bio expansion and measured height reset when either the presented user or profile content changes.

## Automated Proof

- Phase 62 regression coverage pins the rail avatar through presentation-cache pressure and proves that visibility transfers when the avatar file changes.
- Bio disclosure policy coverage proves that the control appears only after rendered content exceeds the collapsed height.
- Existing partial-snapshot identity, optimistic-send avatar grouping, scroll-target, and clipboard diagnostic regression tests remain in the Phase 62 focused slice.
- Remediation coverage repeats partial message-identity merges against a pinned avatar, verifies authoritative replacement/removal policy, checks presentation churn counters, and selects wrapping text for long plain/Markdown biographies while preserving token rows for emoji/references.

## Live QA Required

- Repeatedly send in a warmed channel and confirm the upper-left rail avatar never falls back to initials while the chat avatar remains stable.
- Open self, friend, bot, moderation-enabled, role-heavy, short-bio, and long-Markdown profiles from the available rail/message/member/Friends/system-event entry points.
- Confirm action labels stay on one line, tabs remain aligned, roles do not force horizontal compression, and long bios show `See More`, expand, scroll within the card, and collapse with `Show Less`.
- Recheck Increase Contrast, Reduce Motion, keyboard focus, and VoiceOver labels on the repaired card.

For the remediation retest, prioritize the first two items. Accessibility QA is explicitly deferred by the tester and does not gate this P1 bug-fix pass.

The remediated rail-avatar and profile-bio changes have implementation/test proof only. Their live-sensitive parity rows remain `partial` until repeated sends/scrolling show no rail flash and the supplied long bot bio wraps across the card normally.
