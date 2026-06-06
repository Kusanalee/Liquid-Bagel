# Phase 35 - Hard Fix: Member Pipeline, Identity, Media Safety, Profiles, Events, Emoji, And Search

Phase 35 fixes the root causes behind repeated member, identity, and media-heavy timeline bugs without recreating the project or replacing the existing shell, realtime snapshot, message controller, resolver, or media architecture.

## Hard Bug Audit

| bug | observed live behavior | root cause found | fix implemented | tests added | manual QA step | remaining risk |
| --- | --- | --- | --- | --- | --- | --- |
| Member list incomplete | Large servers could show only the current user or a small Ready subset unless Developer Settings refresh was used. | Normal member panel still derived only from Ready/realtime snapshot data; the verified REST member fetch was hidden in Developer Settings. | Selected server member panel now shows Ready data immediately, then foreground-hydrates the visible server with `GET /servers/{id}/members`; fetches are per-server, deduped, debounced, cancel/discard stale results, and update the in-memory member store. | `testPhase35SelectedServerMemberHydrationMergesRestMembersAndDiagnostics`, `testPhase35StaleMemberHydrationIsDiscardedAfterServerSwitch` | Open a large server channel and confirm the panel refreshes once without visiting Developer Settings. | Live completeness still depends on the REST route returning the expected full server member set. |
| Missing users dropped or showed IDs | Some rows rendered IDs or disappeared when user objects were absent. | Member derivation needed to keep member rows even when user hydration was incomplete. | REST member results replace the selected server member slice, missing users remain visible with resolver fallback, and returned avatars/nicknames flow through the existing central resolver. | Phase 28/29/34 member tests plus Phase 35 member hydration test | Compare rows before and after hydration in a server known to have offline or missing-user members. | REST member payload currently merges members; if a member lacks user data, name quality still depends on future user/profile hydration. |
| Bot names/avatars inconsistent | Bot rows could follow the same broken path as ordinary users. | Bot metadata only renders when the central resolver is used and user/avatar metadata exists. | Message rows, member rows, profile rows, system event targets, and search results continue using resolver-backed identity; bot badge/name/avatar fall through the same path. | Existing Phase 31/33/34 resolver tests and Phase 35 profile/member tests | Inspect bot messages, bot member rows, and bot profile. | Bot avatar quality still depends on modeled file metadata from Ready/member/profile payloads. |
| Media-heavy channels freeze | Image-heavy timelines could start too many preview/avatar/custom-emoji loads and starve the app. | Image and preview work could be eager, uncapped, and not canceled when rows left the visible range. | Image resource loads now go through a bounded queue, inline preview loads are capped, offscreen preview tasks cancel, failed avatars stop retrying forever, and diagnostics report active/queued image work. | `testPhase35ImageResourceQueueCapsConcurrentLoads` | Open an image-heavy channel, scroll quickly, and confirm thumbnails load progressively without a hang. | Thumbnail downsampling still relies on the existing loader/cache; full live memory pressure needs dogfood validation. |
| Profile viewer incomplete | Profiles opened in some places but profile media/bio were weaker than native expectations. | Profile fetch and profile media rendering did not fully reuse the newer bounded image/Markdown paths. | Profile fetch remains explicit-on-open; profile banners use bounded `backgrounds` media loading, avatars prefer member avatar, role chips render, and bios use safe Markdown rendering. | `testPhase35ProfileFetchRunsOnlyWhenOpenedAndKeepsBackground` | Open profiles from messages, members, DMs, and Friends; inspect avatar, banner, bio, roles, and actions. | Relationship/moderation action parity remains route-gated and conservative. |
| System events showed useless placeholders | Events could show `User 000... joined` or raw-like unknown names. | Unknown actor fallback still treated non-zero unknown IDs as displayable user names. | System events now use resolver names only when a user/member is known; zero/system/unknown actors fall back to human copy, and resolvable actor names can open profiles. | `testPhase35SystemEventUnknownActorUsesHumanFallbackAndKnownTargetOpensProfile` plus existing Phase 27/29/33 tests | Open event-heavy channels and check joins/leaves/pins. | Unsupported event types still render generic copy. |
| Markdown re-parsed too often | Message/profile Markdown could be reparsed on every SwiftUI body recompute. | `MarkdownMessageContent` parsed through a computed property. | Parsed blocks are now captured at initialization and reused through body recomputation; profiles use the same safe renderer. | Existing UI Markdown coverage through package build/tests | Open Markdown-heavy messages and profile bios. | A persistent per-message content-revision Markdown cache remains deferred. |
| Emoji picker not searchable/grouped | Emoji button opened a picker but search/grouping were too thin. | Composer passed a flat emoji list. | Added searchable emoji popover sections for Common, Unicode, Current Server, and Other Servers where data exists. Custom emoji shortcodes remain text insertion and use bounded media elsewhere. | `testPhase35EmojiSectionsGroupCurrentAndOtherServers` | Open picker, search Unicode/custom emoji, confirm current-server grouping. | Exact official autocomplete syntax and full Unicode alias database remain deferred. |
| Search missed unloaded messages | Local search only covered loaded messages and remote search was easy to miss. | The search UI did not clearly prompt an explicit remote channel search after no local hits. | Search panel now offers an explicit remote channel search action when loaded-only search finds nothing; remote results use resolver-backed author names and existing load-around behavior. | Existing Phase 13/14 search tests, resolver-backed result path covered by build | Search for an older unloaded message, click Search Channel Remotely, open a result. | Server/global search remains deferred unless route behavior is verified safe in live QA. |
| Diagnostics leaked into normal workflow risk | Member/media/search diagnostics needed to remain developer-facing. | Previous phases added multiple diagnostics surfaces; normal UI only needs status/error copy. | Member status in the panel is user-facing; detailed member/media/profile/search diagnostics remain in Developer Settings and copied diagnostics stay redacted. | Existing redaction/diagnostic tests plus Phase 35 diagnostics assertions | Confirm chat/Home do not show developer counters; open Developer Settings for diagnostics. | Future diagnostics additions must stay redacted and off normal Home/chat surfaces. |

## Member Data Pipeline

The member panel no longer depends on a hidden Developer Settings refresh. When a server channel is visible, the panel derives rows from Ready/realtime data immediately and starts one foreground hydration for the selected server. Hydration uses the verified `GET /servers/{id}/members` client method, never runs for every server at launch, and is deduped per server.

Server switches cancel or discard stale member fetches. Returned members replace the selected server's in-memory member slice, invalidate member grouping, update the quick switcher snapshot, and trigger bounded visible identity image loading. Missing users do not drop members. Offline members and bots are shown when returned by Ready or REST.

## User, Avatar, And Bot Hydration

The existing central identity resolver remains the single path for normal display names. It prefers server nickname, display name, username, bot metadata, then shortened ID fallback, and avoids full raw IDs in normal display. Member/profile/avatar views prefer member avatar where modeled, then user avatar, then initials fallback.

Profile fetches and member REST results merge into the same in-memory stores used by messages, member rows, DMs, Friends, system events, and search result rendering. Failed avatar/image loads now cache failure state so visible rows fall back instead of retrying forever.

## Media-Heavy Timeline Safety

Phase 35 adds a bounded image-resource queue with active and queued diagnostics. Inline image preview loading is capped separately, offscreen preview tasks are canceled, and queue saturation records a media-heavy safe-mode action. Avatar, server media, profile background, and custom emoji image requests share bounded image loading.

Original attachment data still loads only through explicit open/download/viewer actions. Inline previews use the existing preview route/path and keep memory-only cache behavior.

## User Profile Viewer

Profiles open from message authors, member rows, DM/Friend rows, and resolvable system-event names using locally known data immediately. Fetching extra profile data is explicit-on-open only. The profile view renders avatar, banner/background where available, display name, username, bot badge, server nickname context, role chips with role colors, status/relationship information where modeled, safe Markdown bio text, and gated actions.

Developer-only copy-user-ID behavior remains gated to developer surfaces.

## System Events

Known actors resolve through the central resolver, so events can render names such as `Enka joined` or a server nickname where known. Unknown, zero-like, or system actors use human fallback copy such as `A member joined`, `A member left`, or `A message was pinned`. Resolvable event names can open profiles; unknown/system actor fallbacks are not clickable.

## Markdown Rendering

Messages and profile bios use the same safe SwiftUI Markdown renderer. It supports headings, bold, italic, strikethrough where `AttributedString` supports it, inline code, fenced code blocks, blockquotes, unordered lists, ordered lists, links, and line breaks. HTML is stripped before inline Markdown parsing, scripts are not executed, and malformed Markdown falls back to displayable text.

The parser now captures parsed blocks during view initialization instead of reparsing through every body recomputation. A persistent message-ID/content-revision cache remains a future improvement.

## Emoji Search And Grouping

The composer emoji popover now includes a search field and grouped sections:

- Common
- Unicode
- Current Server
- Other Servers

Unicode search covers a small local alias set for common emoji. Custom emoji search matches shortcode/name text and keeps current-server emoji separate from other known server emoji. Selecting an emoji inserts it into the composer. Custom emoji images remain bounded through the existing image loader where reactions/messages render them.

## Remote Search

Loaded-message search remains local and fast. When no loaded results are found, the search panel offers an explicit remote selected-channel search action. Remote search is never launched in the background or on startup. Results show resolver-backed author names, snippets, timestamps, and channel context, then use the existing load-around/jump behavior when opened.

## Diagnostics

Developer Settings diagnostics now include member hydration source and counts, stale fetch discard state, image active/queued/cache counts, profile fetch state, system-event fallback behavior through tests, emoji source/group behavior, and remote-search route/result state. Copied diagnostics stay redacted: no tokens, raw response bodies, local file paths, or full message content.

Normal chat/Home UI only shows user-facing loading/error states.

## Parity Matrix Updates

`Docs/ParityMatrix.md` now keeps live-sensitive items partial while reflecting the Phase 35 implementation:

- Member list now uses foreground selected-server REST hydration.
- User/avatar/bot hydration notes include resolver-backed profile/search/event surfaces.
- Media-heavy performance notes include bounded image/preview queues and offscreen cancellation.
- Profile Markdown, system events, emoji search/grouping, custom emoji, and remote channel search are updated conservatively.

## Security And Privacy

Phase 35 does not add APNs, push registration, background sync daemons, persistent message databases, voice/video, screen share, bot dashboards, server deletion, destructive bulk moderation, or speculative mutation routes. Member hydration is foreground selected-server only. Profile fetch is explicit-on-open only. Remote search is explicit user action only. Media and diagnostics remain memory-only/redacted.

## Tests Added

- Selected-server member hydration fetches once, merges returned members, and reports REST diagnostics.
- Stale member hydration is discarded after server switch.
- REST-hydrated member list updates from Ready-only state and keeps missing-user fallbacks.
- Image resource queue caps concurrent loads and reports queued work.
- Profile fetch runs only on open and preserves profile background metadata.
- System event unknown actors use human fallback; known actors expose a profile target.
- Emoji sections group current-server and other-server custom emoji.

Existing mock-only tests continue to cover auto-connect, mock UI hiding, attachment drop/paste review, 20 MB upload limit, role colors, custom emoji button behavior, Home sidebar context, search/load-around, and diagnostics redaction.

## Deferred

- Persistent per-message Markdown cache keyed by message ID/content revision.
- Full Unicode emoji alias/category database.
- Exact official custom emoji autocomplete/rendering syntax beyond known shortcodes.
- Server/global remote search unless live route behavior is verified safe.
- Persistent thumbnail cache or background media prefetching, both intentionally out of scope.
- Live proof that `GET /servers/{id}/members` returns complete large-server membership under production permissions.

## Known Risks

- REST-hydrated members are held in memory for the session and overlaid onto later snapshots; a later realtime leave/update may need more nuanced reconciliation if live QA exposes stale rows.
- Profile banners and custom emoji depend on correct file metadata from Ready/profile payloads.
- Media-heavy safe mode is mock-tested for queue caps; live memory pressure still needs dogfood validation.
- Parity statuses remain conservative until the manual live checklist is completed.

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

## Manual Live QA Checklist

1. Launch app with saved credential.
2. Confirm auto-connect still works.
3. Open a large server.
4. Open a server channel.
5. Confirm member panel shows loading or Ready members immediately.
6. Confirm selected-server member fetch runs once.
7. Confirm full known member list appears after hydration.
8. Confirm offline members and bots appear where returned.
9. Confirm users that previously showed IDs now show names or shortened fallback only.
10. Confirm avatars render or fallback cleanly.
11. Open a media-heavy channel.
12. Scroll quickly.
13. Confirm app does not freeze.
14. Confirm thumbnails load progressively.
15. Click image.
16. Confirm original opens only on explicit viewer.
17. Click a message author.
18. Confirm profile opens.
19. Confirm profile banner appears if available.
20. Confirm bio Markdown renders safely.
21. Click a member row.
22. Confirm profile opens.
23. Open an event-heavy channel.
24. Confirm joins/leaves name known users or use human fallback.
25. Open Markdown-heavy channel.
26. Confirm headings/lists/quotes/code/links render.
27. Open emoji picker.
28. Search emoji.
29. Confirm current-server custom emoji are grouped/searchable.
30. Search for an older message not currently loaded.
31. Run remote channel search explicitly.
32. Open result and confirm around-message loading/jump works.
33. Relaunch.
34. Confirm auto-connect still works and no mock UI appears.

## Recommended Phase 36

Run the Phase 35 live checklist on at least one large server, one bot-heavy server, and one image-heavy channel. Use the results to reconcile REST-hydrated member overlays with realtime joins/leaves, add a persistent message Markdown cache if profiling still shows parse cost, and tighten emoji/search parity only after exact live syntax and route behavior are confirmed.
