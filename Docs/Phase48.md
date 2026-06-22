# Phase 48 - Core Chat Live Parity Audit

Phase 48 is the live-first audit layer on top of Phase 47 core chat polish. It is intended to compare Liquid Bagel against the official client for the most visible chat behavior, record exact evidence, and drive only the fixes that are proven by real messages, real DMs, and real notification paths.

This repository pass did not capture live dogfood evidence. The preflight test slice passed, no repo-proven rendering or routing defect was found, and all live-sensitive parity rows remain `partial` until the checklist below is completed with real accounts.

## Scope And Route Boundaries

- Use only the already verified message fetch, around-message fetch, selected-channel search, pin, unpin, reaction, ack, and media routes.
- Do not add global/server search, server-wide cloud mute, APNs/background push, persistent message/media/thumbnail/markdown caches, external embed media autoloading, or unverified emoji/embed wire shapes.
- Keep identity fixes on the Phase 43 snapshot/resolver path if live reply, pin, search, or notification surfaces show degraded names or avatars.
- Keep embed media bounded: modeled `embed.media` can use the existing image-resource path; arbitrary external embed image/video URLs remain display-only or explicit link/open actions.
- Keep diagnostics developer-only and redacted.

## Preflight Verification

These preflight commands passed before Phase 48 documentation updates:

```sh
swift test --package-path Packages/StoatUI --filter Phase47
swift test --package-path Packages/StoatFeatures --filter 'StoatFeaturesTests/testPhase4(4|7)'
```

Results:

- `StoatUI` Phase 47 slice: 3 tests passed.
- `StoatFeatures` Phase 44/47 slice: 10 tests passed.

No code fix is included in this phase document because the preflight run did not expose a concrete repo-level defect and live QA was not captured in this implementation pass.

## Live Evidence Ledger

| Surface | Official-client comparison | Liquid Bagel result | Fix needed | Verification | Final parity status |
| --- | --- | --- | --- | --- | --- |
| Markdown plus custom emoji | Pending real message comparison for headings, lists, quotes, inline styles, links, fenced code, and `:shortcode:` coexistence | Phase 47 mock/UI coverage preserves markdown and keeps code blocks literal | Unknown until live QA | Preflight UI tests passed; live checklist pending | `partial` |
| Embeds | Pending website, text, image, video, none, and unknown embed comparison | Phase 47 cards sanitize text/URLs and support modeled media controls | Unknown until live payload variety is inspected | Preflight UI/feature tests passed; live checklist pending | `partial` |
| Embed-only summaries | Pending official-client comparison in replies, pins, and search results | Phase 47 summaries prefer safe embed title/description/site/host over `1 embed` | Unknown until live embed-only messages are inspected | Feature summary tests passed; live checklist pending | `partial` |
| Replies | Pending creation/open/jump comparison for loaded, unloaded, deleted, and inaccessible targets | Phase 44 unified jump path and Phase 47 safer summaries are covered by tests | Unknown until live target varieties are tested | Feature tests passed; live checklist pending | `partial` |
| Pins | Pending pin/open/unpin route and selected-channel pinned-list comparison | Phase 44 explicit pinned sheet uses selected-channel search and unified jump | Unknown until live route/action QA | Feature tests passed; live checklist pending | `partial` |
| Reactions and custom emoji | Pending Unicode/custom reaction send, remove, render, and media comparison | Existing reaction routes and bounded custom emoji media are mock/source covered | Unknown until live custom emoji syntax/media QA | Existing reaction and emoji tests; live checklist pending | `partial` |
| Typing indicators | Pending live server, DM, and group-DM typing event comparison | Phase 44 state excludes current user, coalesces names, and expires stale entries | Unknown until multi-account live QA | Feature tests passed; live checklist pending | `partial` |
| Read ack and unreads | Pending live server/DM ack and unread-clear comparison | Phase 44 dedupes foreground ack and clears local unread only after success | Unknown until live ack behavior is observed | Feature tests passed; live checklist pending | `partial` |
| Search and jump | Pending selected-channel remote search and unloaded-target jump comparison | Phase 44 routes loaded/remote search results through one coordinator; global search remains blocked | Unknown until live result/open behavior is tested | Feature tests passed; live checklist pending | `partial` |
| Notification click routing | Pending server and DM notification click comparison, including unavailable targets | Phase 44 routes through unified navigation and degrades to channel selection | Unknown until signed/live notification QA | Feature tests passed; live checklist pending | `partial` |
| Mutes and active suppression | Pending live channel/DM mute, Busy, Focus, and active-channel comparison | Local mute/suppression decisions are modeled and counted diagnostically | Unknown until live delivery/suppression QA | Existing notification tests; live checklist pending | `partial` |
| Diagnostics redaction | Pending copied Developer Verification review after live audit actions | Existing redaction paths cover chat interaction, identity, media, and notification diagnostics | Add only categorical Phase 48 evidence if live gaps require it | Redaction tests passed in prior phase slices; live copy review pending | `partial` for live audit, diagnostics row remains `done` |

## Manual Dogfood Checklist

Use two real accounts and one safe test server plus at least one DM path.

1. Send markdown messages with headings, lists, quotes, inline styles, links, and fenced code blocks.
2. Send or inspect current-server custom emoji shortcodes inside normal text and fenced code.
3. Compare the same messages in the official client and Liquid Bagel.
4. Inspect website, text, image, video, none, unknown, and embed-only messages when available.
5. Confirm external embed image/video URLs do not autoload in Liquid Bagel.
6. Reply to loaded and unloaded messages, then open the reply preview and confirm jump/highlight behavior.
7. Inspect deleted or inaccessible reply targets if a safe test case exists.
8. Pin a normal message, open the pinned-message sheet, jump to it, and unpin it.
9. Pin or search an embed-only message and confirm the summary is useful and does not leak private URLs or raw IDs.
10. React with common Unicode emoji.
11. React with current-server custom emoji and confirm render/media behavior.
12. Type from the second account in a server channel, DM, and group DM if available.
13. Receive unread server and DM messages, open them, and confirm unread/mention state clears after ack.
14. Search loaded messages locally, then run explicit selected-channel remote search for an unloaded message and open the result.
15. Trigger server and DM notifications while the target conversation is inactive, then click them.
16. Test notification click routing when the target message is unavailable or deleted if possible.
17. Mute a channel or DM and confirm notifications suppress.
18. Set Busy and Focus statuses and confirm suppression behavior matches the intended policy.
19. Keep the official client open beside Liquid Bagel for visual and behavior comparison.
20. Copy Developer Verification diagnostics and confirm no tokens, raw payloads, message bodies beyond safe snippets, private URLs, full IDs, local paths, MFA values, or user-entered secrets leak.

## Promotion Rules

- Promote a parity row to `done` only when the evidence ledger includes live pass evidence for that row and no live-sensitive gap remains.
- Keep rows `partial` when behavior is implemented and tested only with mocks/source verification.
- Keep rows `blockedByUnverifiedAPI` when parity requires a route or schema that is not verified.
- If live QA exposes a concrete bug, add the smallest code fix in the owning seam and add a focused regression test before updating the matrix.

## Final Verification Required After Any Code Fix

```sh
swift test --package-path Packages/StoatUI --filter Phase47
swift test --package-path Packages/StoatFeatures --filter 'StoatFeaturesTests/testPhase4(4|7)'
git diff --check
Scripts/check.sh
```
