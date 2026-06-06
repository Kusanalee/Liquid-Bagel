# Official Client Parity Matrix

Statuses: `done`, `partial`, `broken`, `blockedByUnverifiedAPI`, `deferred`, `outOfScope`.

Live-sensitive items remain `partial` or `broken` until real live QA proves them. Mock tests are not enough to mark DMs, notification permission, member completeness, or user/avatar hydration done.

| Section | Item | Status | Source of truth | Current implementation | Known gaps | Tests | Manual QA | Next action |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Account and session | login | done | Verified API/client behavior | Manual credential/session setup | MFA/full login creation limited | Session tests | Validate manually | Keep stable |
| Account and session | MFA | partial | Official client | Validation failure states | Full MFA login flow not implemented | Session tests | MFA account QA | Research |
| Account and session | token/session import | done | Existing app behavior | Manual token import/validation plus Phase 32 saved-credential auto-connect | Live QA pending for startup failures | Startup tests | Import token/relaunch | Keep explicit setup |
| Account and session | live-default startup | partial | Phase 32 runtime direction | Saved credential auto-validates/connects on launch; no credential shows setup state | Needs live dogfood against production/keychain failure paths | Phase 32 startup tests | Relaunch with saved credential | Live QA |
| Account and session | session list | partial | Verified session routes | Account session surface | Full parity QA pending | Session tests | Open sessions | Audit |
| Account and session | revoke sessions | partial | Verified session routes | Logout/revoke support | Bulk/session-list parity pending | Auth tests | Revoke test session | Audit |
| Account and session | logout | done | Verified auth route | Explicit logout/disconnect | None critical | Auth tests | Logout | Keep stable |
| Account and session | account profile view | partial | Verified profile route | Profile fetch on click with bounded avatar/banner loading and safe Markdown bio rendering | No hidden fetch storm by design; live banner/bio QA pending | Profile mocks, Phase 35 profile test | Open profile | Keep explicit |
| Account and session | account profile edit | blockedByUnverifiedAPI | Unverified route | Not implemented | Edit route not verified | Matrix test | N/A | Verify first |
| Account and session | avatar edit | blockedByUnverifiedAPI | Unverified route | Upload helpers only | Account mutation route not wired | Upload tests | N/A | Verify first |
| Account and session | profile banner/background edit | blockedByUnverifiedAPI | Unverified route | Media model exists | Mutation route not wired | Model tests | N/A | Verify first |
| Account and session | status/custom status | partial | Ready/user settings | Status renders where present | Editing incomplete | Display tests | Inspect status | Audit route |
| Account and session | user settings sync | partial | Ready user_settings | Local preferences plus decoded settings | Cloud sync incomplete | Persistence tests | Open settings | Phase 31 |
| Core chat | server text channels | done | Ready/channels messages | Select/load/send server channels | None critical | Message tests | Open channel | Keep stable |
| Core chat | DMs | broken | Ready, `GET /users/dms`, `GET /users/{target}/dm` | Phase 31/32 routes clicked DM rows to the timeline via active conversation and top-bar DM title | Needs live QA proof for load/send/attachments/participants | Phase 31/32 DM tests | Run Phase 32 checklist | Do not claim parity |
| Core chat | group DMs | partial | Ready channel kind Group | Select/load/sidebar supported | Create/open route not verified | Group DM tests | Click group DM | Verify later |
| Core chat | saved messages | partial | Ready channel kind SavedMessages | Select/load supported | Live availability needs QA | Saved tests | Click Saved Messages | Live QA |
| Core chat | send/edit/delete messages | done | Verified message routes | Send/edit/delete with confirmations | No success toast by design | Action tests | Send/edit/delete | Keep stable |
| Core chat | replies | partial | Message schema | Reply composer context | Deep parity QA pending | Reply tests | Reply manually | Polish |
| Core chat | pins | partial | Verified pin routes | Pin actions/search | Full pinned UX incomplete | Pin tests | Pinned search | Polish |
| Core chat | reactions | partial | Verified reaction routes, Ready emojis | Expanded common reactions; known custom emoji reactions resolve names/images with bounded loading | Custom emoji send/live media QA not audited | Reaction + Phase 33/34 emoji tests | React with custom emoji | Emoji live QA |
| Core chat | emoji picker | partial | Native Unicode input, Ready emojis | Composer popover visibly opens, searches common Unicode aliases and custom shortcodes, and groups Common/Unicode/Current Server/Other Servers where data exists | Full custom autocomplete, exact official syntax, and complete Unicode alias database deferred | Phase 32/33/34 emoji tests, Phase 35 grouping test | Insert/react/search emoji | Custom emoji QA |
| Core chat | custom emoji | partial | Ready emojis | Models decode emojis; picker groups server emoji shortcodes; reaction display and known `:name:` content tokens resolve through bounded `emojis` media loading | Exact message-content syntax/live media QA still pending | Model/realtime/Phase 33/34/35 tests | Emoji server | Live syntax QA |
| Core chat | markdown | partial | Message/profile content | Safe block/inline Markdown renderer for headings, lists, quotes, code, links, and common inline styles; parsed blocks are reused across body recomputation | Exact official rendering parity and persistent message-ID cache incomplete | UI tests/build, Phase 35 docs | Markdown messages/profiles | Polish |
| Core chat | embeds | partial | Message schema | Embed rendering | Variant audit incomplete | Render tests | Embed messages | Audit |
| Core chat | attachments | done | Upload/send/media routes | Explicit upload/preview/download/open | No persistent cache by design | Attachment tests | Send file | Keep explicit |
| Core chat | image preview | done | Autumn media routes | Larger inline previews/explicit viewer | Memory-only cache | Media tests | Preview image | Keep bounded |
| Core chat | drag/drop upload | done | Composer flow | Drop targets open attach review modal before queueing | No auto-upload until send | Phase 32 drop tests | Drop file | Keep stable |
| Core chat | clipboard paste upload | partial | macOS pasteboard, composer flow | Image/file paste opens the attachment review flow; text paste stays normal; Shift-Command-V exposes explicit Paste Attachment | Finder/provider edge QA pending | Phase 33 paste tests | Paste image/file | Live macOS QA |
| Core chat | upload size limit | done | Local attachment validation | Shared 20 MB limit rejects oversized files before upload with clear copy | None critical | Phase 33 boundary tests | Try >20 MB file | Keep stable |
| Core chat | read ack/unreads | partial | Ack route/Ready unreads | Channel-ID ack/local clear | Live DM ack QA needed | Ack tests | Read channels | Monitor |
| Core chat | typing indicators | partial | Realtime typing | Begin/end helpers | Full display parity incomplete | Typing tests | Type | Polish |
| Core chat | search | partial | Verified search routes | Loaded/pinned search plus explicit selected-channel remote search prompt when local loaded search misses; remote result authors use resolver names | Global/server search incomplete; live remote result/open behavior needs QA | Search tests, Phase 35 build coverage | Search loaded and unloaded messages | Live remote QA |
| Core chat | jump to message | partial | Message fetch/search | Loaded/around-message behavior for search results | Cross-context QA needed, deleted/unavailable result edge QA pending | Timeline/search tests | Jump result | Polish |
| Core chat | system events | partial | System message schema | Safe member/user names; zero/system/unknown actors use human fallbacks; resolvable event actors can open profiles | Unsupported events generic; live event payload variety needs QA | System + Phase 33/35 tests | Event channel | Live event QA |
| Core chat | user/avatar hydration | partial | Ready users/members, message users, relationship/profile data | Central resolver prevents full raw-ID author names, member nicknames win, bot metadata preserved, avatar/profile banner metadata loads through bounded queue, member REST/profile fetches update visible surfaces | Live QA must confirm names/avatars in real chat and bot-heavy servers | Phase 31/32/33/34 resolver tests, Phase 35 member/profile tests | Inspect affected chats | Keep partial until live QA |
| Server/community | server list | done | Ready servers | Server rail from Ready | No REST list by design | Selection tests | Connect | Keep Ready |
| Server/community | server icons | done | Ready media | Bounded in-memory loading | No persistent cache | Media tests | Open server | Keep bounded |
| Server/community | server banners | done | Ready media | Banner rendering/settings | Live QA recommended | Media tests | Settings | Keep bounded |
| Server/community | create server | partial | Verified route | Explicit create flow | Parity QA pending | Create tests | Test server | Audit |
| Server/community | join invite | partial | Verified invite route | Preview/join flow | Native deep-link parity incomplete | Invite tests | Join invite | Audit |
| Server/community | Discover | partial | Web-backed surface | Browser handoff plus invite tools | No verified native listing route/feed | Discover tests | Open browser | Keep handoff until verified feed |
| Server/community | invite create/list/revoke | partial | Verified invite routes | Manage invites | Full QA pending | Invite tests | Manage invites | Audit |
| Server/community | channel create/edit/delete | partial | Verified channel routes | Text channel management | Permission/destructive edge QA | Management tests | Test channel | Audit |
| Server/community | categories | partial | Server edit categories | Category editor | Reorder/move parity incomplete | Category tests | Edit categories | Polish |
| Server/community | roles | partial | Verified role routes | Role management plus sanitized highest-role color applied to server-context display names | Rank/perms incomplete; live readability QA pending | Role + Phase 33/34 color tests | Roles view | Polish |
| Server/community | role assignment | partial | Verified member edit | Confirmed role assignment | Rank edge QA | Member tests | Assign role | Audit |
| Server/community | permissions preview | done | Backend model | Read-only resolver | Writes separate | Resolver tests | Preview | Keep stable |
| Server/community | permission editing | partial | Verified permission routes | Guarded writes | Full official UX incomplete | Permission tests | Edit test permission | Audit |
| Server/community | member list | partial | Ready members/users, explicit `GET /servers/{id}/members` hydration | Member panel now uses Ready immediately and foreground-hydrates only the visible selected server; refresh is normal UI, deduped/debounced/stale-aware, and merges into the in-memory member store with missing/offline/bot fallbacks | Live large-server completeness needs dogfood proof; REST overlay reconciliation with later realtime leaves needs QA | Member + Phase 33/34/35 tests | Large server | Keep partial until live QA |
| Server/community | member moderation | partial | Verified moderation routes | Kick/ban/timeout guarded from settings and member context menus | Dashboard incomplete | Moderation tests | Test server | Audit |
| Server/community | bans/timeouts | partial | Verified moderation routes | Ban list/timeouts | Full QA pending | Moderation tests | Test server | Audit |
| Notifications | local notifications | partial | UserNotifications | Explicit opt-in with requestAuthorization diagnostics | Live permission prompt still needs manual QA | Notification tests | Request manually | Keep partial until live prompt works |
| Notifications | in-app banners | done | Local classifier | In-app delivery | None critical | Notification tests | Receive message | Keep stable |
| Notifications | privacy mode | done | Preferences | Private content supported | None critical | Preference tests | Toggle | Keep stable |
| Notifications | dock badge | done | Local unread counts | Badge manager wired | None critical | Badge tests | Observe badge | Keep stable |
| Notifications | route on click | partial | Route center | Queued until reconnect/ready; auto-connect does not request permission | Live route QA pending | Route tests | Click notification | Audit |
| Notifications | mutes | partial | Preferences | Channel suppression | Server-wide mute incomplete | Preference tests | Mute channel | Polish |
| Notifications | active-channel suppression | partial | Classifier active channel | Uses active conversation | Phase 30 DM live QA required | Suppression tests | Active DM | Monitor |
| UI/platform | keyboard shortcuts | partial | App commands | Many commands wired | Official shortcut parity incomplete | Command tests | Use shortcuts | Audit |
| UI/platform | command palette | done | Quick switcher | Routes/commands indexed | None critical | Switcher tests | Open palette | Keep stable |
| UI/platform | accessibility | partial | SwiftUI labels | Core labels exist | VoiceOver audit pending | UI tests | VO pass | Phase 31 |
| UI/platform | high contrast | partial | SwiftUI environment | Preview coverage planned | Manual QA pending | Previews | Enable high contrast | Phase 31 |
| UI/platform | reduce transparency | partial | Local preference | Reduce glass intensity | System audit pending | Preference tests | Toggle | Polish |
| UI/platform | performance with large channels | partial | Lazy timeline, bounded media loading | Image resource queue caps active loads, inline previews are capped/canceled offscreen, original media remains explicit, and diagnostics report active/queued/cache state | More live media-heavy QA needed; persistent thumbnail cache not implemented | Timeline/media perf tests, Phase 35 image queue test | Large image channel | Monitor |
| UI/platform | performance with large servers | partial | Lazy member list, selected-server hydration | Member diagnostics include known/rendered/missing/avatar/dropped counts, hydration source/counts, stale fetch state, and context source | More live large-server QA needed | Member perf tests, Phase 35 hydration tests | Large server | Monitor |
| UI/platform | native macOS window/menu behavior | partial | SwiftUI commands | Native shell exists; Home is compact and right sidebar is contextual | Desktop parity incomplete | App + Phase 34 sidebar tests | Menus/Home/sidebar | Audit |
| UI/platform | settings organization | partial | Settings tabs | App Settings routes to current Account/Connection/Notifications/Developer surface | Official settings parity incomplete | Settings tests | Command-comma | Polish |
| UI/platform | diagnostics | done | Developer Verification | Redacted diagnostics, DM trace, member/sidebar/emoji diagnostics | Developer-only by design | Redaction tests | Copy diagnostics | Keep safe |
| Deferred / not parity | voice | outOfScope | Deferred scope | Not implemented | Out of Phase 30 | Matrix test | N/A | Future phase |
| Deferred / not parity | video | outOfScope | Deferred scope | Not implemented | Out of Phase 30 | Matrix test | N/A | Future phase |
| Deferred / not parity | screen share | outOfScope | Deferred scope | Not implemented | Out of Phase 30 | Matrix test | N/A | Future phase |
| Deferred / not parity | bots/dashboard | outOfScope | Deferred scope | Not implemented | Out of Phase 30 | Matrix test | N/A | Future phase |
| Deferred / not parity | audit logs | outOfScope | Deferred scope | Not implemented | Out of Phase 30 | Matrix test | N/A | Future phase |
| Deferred / not parity | persistent offline cache | deferred | Privacy/scope rule | No persistent message DB | Deferred by design | Regression test | Relaunch | Scope separately |
| Deferred / not parity | APNs/background push | deferred | Privacy/scope rule | Not registered | Deferred by design | Regression test | Relaunch | Scope separately |
| Deferred / not parity | server deletion | outOfScope | Hard scope boundary | Not implemented | Destructive out of scope | Matrix test | N/A | Future phase |
| Deferred / not parity | any unverified route | blockedByUnverifiedAPI | Route verification rule | Disabled/deferred | Must verify first | Matrix test | N/A | Research first |
