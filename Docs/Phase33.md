# Phase 33 - Identity, Clipboard, Markdown, Profiles, Roles, And Emoji Repair

Phase 33 tightens the remaining dogfood-facing identity and content-rendering surfaces without replacing the existing architecture. The work stays local, mock-testable, and conservative for live-sensitive parity claims.

## Live Dogfood Audit

| Area | Observed problem | Root cause found | Fix implemented | Tests added | Live QA step |
| --- | --- | --- | --- | --- | --- |
| Member list | Large server membership could still feel incomplete or hard to trust. | Member rows depended on partially hydrated user quality and did not expose role/color context. | Member rows continue deriving from all known Ready members, preserve missing-user rows, open profiles, show bot badges, and add sanitized role color chips. | Phase 28/29 member completeness tests plus Phase 33 role color tests. | Open a large server and compare visible counts and diagnostics to expected Ready/member state. |
| User/avatar/bot identity | Some bot/user surfaces could still look generic or hide bot state. | Display metadata did not carry a bot flag through the central resolver. | `UserDisplayResolver` now preserves bot identity metadata and message/member/profile rows use resolver-backed names. | Phase 33 bot resolver assertion. | Inspect bot messages, bot member rows, and bot profiles. |
| Clipboard paste | Paste could queue images/files immediately instead of using the review step. | Composer paste hooks bypassed the drag/drop review flow. | Image/file paste now opens the Attach Files review; text paste in the editor remains normal; `Message > Paste Attachment` handles explicit attachment paste. | Phase 33 pasted-image review test. | Copy an image, press Command+V in chat, confirm review opens and nothing uploads. |
| Upload limit | Oversized upload copy was generic. | The 20 MB limit was local to validation policy and error text did not match Phase 33 requirements. | Added `AttachmentUploadLimits.maxFileBytes` and the required 20 MB error copy for picker/drop/paste validation. | Phase 33 exact-boundary and mixed-batch test. | Try exactly 20 MB and 20 MB + 1 byte files. |
| Markdown | Markdown rendering was still mostly inline plus code/quotes. | The block parser did not distinguish headings or lists. | Markdown blocks now include headings, unordered lists, ordered lists, quotes, fenced code, and safe inline Markdown with HTML stripping. | Existing UI compile coverage; manual QA required for visual fidelity. | Open Markdown-heavy channels and inspect headings/lists/quotes/code/links. |
| Profiles | Profiles existed but were not reachable from enough identity surfaces. | Message/member rows lacked a direct profile action. | Message author avatar/name and member rows now open the explicit profile view; Friends/DM profile paths remain intact. | Existing profile mocks plus Phase 33 member/profile interaction code coverage through build. | Open profiles from message rows, member rows, DM rows, and Friends. |
| Discover | Native Discover remains unverified. | No stable first-party listing API is implemented in `StoatAPIClient`; existing research treats Discover as web-backed. | Keep browser handoff and invite paste/create actions. Native feed remains deferred until a verified public feed/API exists. | Existing Discover route tests. | Open Discover and confirm safe fallback/browser path. |
| System events | Zero/system actors could render as useless ID fallbacks. | The system-event presenter treated zero-like IDs as ordinary unknown users. | Zero/system actors now use phrases such as "A member joined"; known member/user names still win. | Phase 33 zero-actor system-event test. | Open event-heavy channels and inspect joins/leaves/pins. |
| Role colors | Role colors were mostly limited to settings. | No shared sanitized role color presentation helper existed for chat/member/profile surfaces. | Added `ResolvedRoleColor` and use it for member/profile chips with invalid/high-contrast fallback. | Phase 33 role color tests. | Inspect member list and profile role chips in light/dark/high-contrast. |
| Custom emoji | Ready emoji data was modeled but picker/reactions did not resolve it. | Reaction/picker display used raw strings only. | Added custom emoji display items from Ready, server-context picker shortcodes, reaction name/image resolution, and bounded `emojis` media loading. | Phase 33 custom emoji resolver/picker test. | View custom emoji reactions and insert a known custom emoji shortcode. |

## Behavior

- Member lists derive from known server members and do not drop members just because user hydration is missing.
- Names resolve through nickname, display name, username/bot name, then shortened ID.
- Avatars use member/server avatar first, then user avatar, then initials fallback.
- Pasted attachments and dropped files use the same review model; no upload happens until Add to Message and Send/upload.
- Files over 20 MB are rejected before upload with: `File too large. Liquid Bagel currently supports files up to 20 MB.`
- Markdown remains safe: raw HTML is stripped, scripts are not executed, and malformed Markdown falls back to displayable text.
- User profiles fetch only after explicit open and remain memory-only.
- Custom emoji image loading is visible-only and memory-only through the existing image resource loader.

## Diagnostics

Developer diagnostics continue to report member known/rendered/missing/dropped counts, avatar queue state, attachment queue/upload/failure counts, and DM trace state. Phase 33 also makes attachment paste classification visible through `lastAttachmentAction`, and custom emoji/role behavior remains observable through Ready counts and rendered rows. Diagnostics stay out of normal chat UI and avoid tokens, raw local paths, raw response bodies, and full message content.

## Security And Privacy

Phase 33 does not add APNs, background sync, persistent message databases, voice/video, screen share, bot dashboard, server deletion, audit logs, or speculative mutation routes. Discover remains a browser handoff because a native public feed/API is not verified. Profile fetches are explicit-on-open only.

## Tests Added

- Upload limit boundary and mixed valid/invalid batch.
- Pasted image review before queue/upload.
- Bot display resolver metadata.
- Role color valid/invalid/high-contrast behavior.
- Custom emoji Ready resolver and picker shortcode.
- Zero/system actor event fallback.

## Manual Live QA Checklist

1. Launch app with saved credential.
2. Confirm auto-connect still works.
3. Open a server with many members.
4. Confirm member list count is plausible.
5. Confirm offline members appear if present in Ready.
6. Confirm bots display names and avatars when available.
7. Open chat messages that previously showed raw IDs.
8. Confirm names and avatars render or fallback cleanly.
9. Copy an image to clipboard.
10. Press Command+V in chat.
11. Confirm attach modal opens.
12. Confirm nothing uploads until confirmed and sent.
13. Try a file larger than 20 MB.
14. Confirm it is rejected before upload.
15. Open Markdown-heavy channel.
16. Confirm headings/lists/quotes/code/links render better.
17. Open a user profile from a message row.
18. Open a user profile from member list.
19. Open Discover.
20. Confirm native feed fallback explains why and browser handoff works.
21. Open a system-event-heavy channel.
22. Confirm join/leave events name users where possible.
23. Confirm role colors appear but remain readable.
24. View custom emoji reactions if available.
25. Insert a known custom emoji shortcode if available.
26. Relaunch.
27. Confirm auto-connect still works and no mock UI appears.

## Deferred

- Native Discover feed until a stable public feed/API is verified.
- Full custom emoji autocomplete and exact message-content image replacement until live syntax is verified.
- Live parity claims for member completeness, user/avatar hydration, custom emoji media, and profile behavior until manual dogfood QA confirms them.

## How To Run

```sh
swift test --package-path Packages/StoatModels
swift test --package-path Packages/StoatAPI
swift test --package-path Packages/StoatRealtime
swift test --package-path Packages/StoatFeatures
swift test --package-path Packages/StoatUI
swift test --package-path Packages/StoatDesignSystem
swift test --package-path Packages/StoatPersistence
Scripts/check.sh
```

## Recommended Phase 34

Use live QA evidence from Phase 33 to either mark member/identity/custom-emoji parity done or keep it partial with precise blockers. If Discover is still important, verify a first-party or public static feed before implementing native cards.
