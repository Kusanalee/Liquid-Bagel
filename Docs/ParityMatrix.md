# Official Client Parity Matrix

Statuses: `done`, `partial`, `broken`, `blockedByUnverifiedAPI`, `deferred`, `outOfScope`.

DMs intentionally remain `broken` until the Phase 30 live QA checklist proves the trace, load, send, attachment, participants, and active-notification behavior in a real live session.

| Section | Item | Status | Source of truth | Current implementation | Known gaps | Tests | Manual QA | Next action |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Account and session | login | done | Verified API/client behavior | Manual credential/session setup | MFA/full login creation limited | Session tests | Validate manually | Keep stable |
| Account and session | MFA | partial | Official client | Validation failure states | Full MFA login flow not implemented | Session tests | MFA account QA | Research |
| Account and session | token/session import | done | Existing app behavior | Manual token import/validation | No launch auto-validation by design | Startup tests | Import token | Keep explicit |
| Account and session | session list | partial | Verified session routes | Account session surface | Full parity QA pending | Session tests | Open sessions | Audit |
| Account and session | revoke sessions | partial | Verified session routes | Logout/revoke support | Bulk/session-list parity pending | Auth tests | Revoke test session | Audit |
| Account and session | logout | done | Verified auth route | Explicit logout/disconnect | None critical | Auth tests | Logout | Keep stable |
| Account and session | account profile view | partial | Verified profile route | Profile fetch on click | No hidden fetch storm by design | Profile mocks | Open profile | Keep explicit |
| Account and session | account profile edit | blockedByUnverifiedAPI | Unverified route | Not implemented | Edit route not verified | Matrix test | N/A | Verify first |
| Account and session | avatar edit | blockedByUnverifiedAPI | Unverified route | Upload helpers only | Account mutation route not wired | Upload tests | N/A | Verify first |
| Account and session | profile banner/background edit | blockedByUnverifiedAPI | Unverified route | Media model exists | Mutation route not wired | Model tests | N/A | Verify first |
| Account and session | status/custom status | partial | Ready/user settings | Status renders where present | Editing incomplete | Display tests | Inspect status | Audit route |
| Account and session | user settings sync | partial | Ready user_settings | Local preferences plus decoded settings | Cloud sync incomplete | Persistence tests | Open settings | Phase 31 |
| Core chat | server text channels | done | Ready/channels messages | Select/load/send server channels | None critical | Message tests | Open channel | Keep stable |
| Core chat | DMs | broken | Ready, `GET /users/dms`, `GET /users/{target}/dm` | Phase 30 trace and active conversation repair | Needs live QA proof | Phase 30 DM tests | Run checklist | Do not claim parity |
| Core chat | group DMs | partial | Ready channel kind Group | Select/load/sidebar supported | Create/open route not verified | Group DM tests | Click group DM | Verify later |
| Core chat | saved messages | partial | Ready channel kind SavedMessages | Select/load supported | Live availability needs QA | Saved tests | Click Saved Messages | Live QA |
| Core chat | send/edit/delete messages | done | Verified message routes | Send/edit/delete with confirmations | No success toast by design | Action tests | Send/edit/delete | Keep stable |
| Core chat | replies | partial | Message schema | Reply composer context | Deep parity QA pending | Reply tests | Reply manually | Polish |
| Core chat | pins | partial | Verified pin routes | Pin actions/search | Full pinned UX incomplete | Pin tests | Pinned search | Polish |
| Core chat | reactions | partial | Verified reaction routes | Common reactions | Custom emoji send not audited | Reaction tests | React | Emoji audit |
| Core chat | custom emoji | partial | Ready emojis | Models decode emojis | Picker/render parity incomplete | Model tests | Emoji server | Polish |
| Core chat | markdown | partial | Message content | Markdown rendering | Official rendering parity incomplete | Render tests | Markdown messages | Polish |
| Core chat | embeds | partial | Message schema | Embed rendering | Variant audit incomplete | Render tests | Embed messages | Audit |
| Core chat | attachments | done | Upload/send/media routes | Explicit upload/preview/download/open | No persistent cache by design | Attachment tests | Send file | Keep explicit |
| Core chat | image preview | done | Autumn media routes | Inline previews/explicit viewer | Memory-only cache | Media tests | Preview image | Keep bounded |
| Core chat | drag/drop upload | done | Composer flow | Drop targets active conversation | No auto-upload until send | Attachment tests | Drop file | Keep stable |
| Core chat | read ack/unreads | partial | Ack route/Ready unreads | Channel-ID ack/local clear | Live DM ack QA needed | Ack tests | Read channels | Monitor |
| Core chat | typing indicators | partial | Realtime typing | Begin/end helpers | Full display parity incomplete | Typing tests | Type | Polish |
| Core chat | search | partial | Verified search routes | Loaded/live/pinned search | Global search incomplete | Search tests | Search channel | Phase 31 |
| Core chat | jump to message | partial | Message fetch/search | Loaded/around-message behavior | Cross-context QA needed | Timeline tests | Jump result | Polish |
| Core chat | system events | done | System message schema | Safe names/fallbacks | Unsupported events generic | System tests | Event channel | Keep stable |
| Server/community | server list | done | Ready servers | Server rail from Ready | No REST list by design | Selection tests | Connect | Keep Ready |
| Server/community | server icons | done | Ready media | Bounded in-memory loading | No persistent cache | Media tests | Open server | Keep bounded |
| Server/community | server banners | done | Ready media | Banner rendering/settings | Live QA recommended | Media tests | Settings | Keep bounded |
| Server/community | create server | partial | Verified route | Explicit create flow | Parity QA pending | Create tests | Test server | Audit |
| Server/community | join invite | partial | Verified invite route | Preview/join flow | Native deep-link parity incomplete | Invite tests | Join invite | Audit |
| Server/community | Discover | partial | Web-backed surface | Browser handoff | No native listing route | Discover tests | Open browser | Keep handoff |
| Server/community | invite create/list/revoke | partial | Verified invite routes | Manage invites | Full QA pending | Invite tests | Manage invites | Audit |
| Server/community | channel create/edit/delete | partial | Verified channel routes | Text channel management | Permission/destructive edge QA | Management tests | Test channel | Audit |
| Server/community | categories | partial | Server edit categories | Category editor | Reorder/move parity incomplete | Category tests | Edit categories | Polish |
| Server/community | roles | partial | Verified role routes | Role management | Rank/perms incomplete | Role tests | Roles view | Polish |
| Server/community | role assignment | partial | Verified member edit | Confirmed role assignment | Rank edge QA | Member tests | Assign role | Audit |
| Server/community | permissions preview | done | Backend model | Read-only resolver | Writes separate | Resolver tests | Preview | Keep stable |
| Server/community | permission editing | partial | Verified permission routes | Guarded writes | Full official UX incomplete | Permission tests | Edit test permission | Audit |
| Server/community | member list | done | Ready members/users | Missing/offline fallbacks | No hidden member fetch | Member tests | Large server | Keep stable |
| Server/community | member moderation | partial | Verified moderation routes | Kick/ban/timeout guarded | Dashboard incomplete | Moderation tests | Test server | Audit |
| Server/community | bans/timeouts | partial | Verified moderation routes | Ban list/timeouts | Full QA pending | Moderation tests | Test server | Audit |
| Notifications | local notifications | partial | UserNotifications | Explicit opt-in | No launch prompt by design | Notification tests | Request manually | Keep explicit |
| Notifications | in-app banners | done | Local classifier | In-app delivery | None critical | Notification tests | Receive message | Keep stable |
| Notifications | privacy mode | done | Preferences | Private content supported | None critical | Preference tests | Toggle | Keep stable |
| Notifications | dock badge | done | Local unread counts | Badge manager wired | None critical | Badge tests | Observe badge | Keep stable |
| Notifications | route on click | partial | Route center | Queued until manual connect | Live route QA pending | Route tests | Click notification | Audit |
| Notifications | mutes | partial | Preferences | Channel suppression | Server-wide mute incomplete | Preference tests | Mute channel | Polish |
| Notifications | active-channel suppression | partial | Classifier active channel | Uses active conversation | Phase 30 DM live QA required | Suppression tests | Active DM | Monitor |
| UI/platform | keyboard shortcuts | partial | App commands | Many commands wired | Official shortcut parity incomplete | Command tests | Use shortcuts | Audit |
| UI/platform | command palette | done | Quick switcher | Routes/commands indexed | None critical | Switcher tests | Open palette | Keep stable |
| UI/platform | accessibility | partial | SwiftUI labels | Core labels exist | VoiceOver audit pending | UI tests | VO pass | Phase 31 |
| UI/platform | high contrast | partial | SwiftUI environment | Preview coverage planned | Manual QA pending | Previews | Enable high contrast | Phase 31 |
| UI/platform | reduce transparency | partial | Local preference | Reduce glass intensity | System audit pending | Preference tests | Toggle | Polish |
| UI/platform | performance with large channels | partial | Lazy timeline | Diagnostics/caps | More live QA needed | Timeline perf tests | Large channel | Monitor |
| UI/platform | performance with large servers | partial | Lazy member list | Member diagnostics | More live QA needed | Member perf tests | Large server | Monitor |
| UI/platform | native macOS window/menu behavior | partial | SwiftUI commands | Native shell exists | Desktop parity incomplete | App tests | Menus | Audit |
| UI/platform | settings organization | partial | Settings tabs | Account/connection/notifications/developer | Official settings parity incomplete | Settings tests | Open settings | Polish |
| UI/platform | diagnostics | done | Developer Verification | Redacted diagnostics and DM trace | Developer-only by design | Redaction tests | Copy diagnostics | Keep safe |
| Deferred / not parity | voice | outOfScope | Deferred scope | Not implemented | Out of Phase 30 | Matrix test | N/A | Future phase |
| Deferred / not parity | video | outOfScope | Deferred scope | Not implemented | Out of Phase 30 | Matrix test | N/A | Future phase |
| Deferred / not parity | screen share | outOfScope | Deferred scope | Not implemented | Out of Phase 30 | Matrix test | N/A | Future phase |
| Deferred / not parity | bots/dashboard | outOfScope | Deferred scope | Not implemented | Out of Phase 30 | Matrix test | N/A | Future phase |
| Deferred / not parity | audit logs | outOfScope | Deferred scope | Not implemented | Out of Phase 30 | Matrix test | N/A | Future phase |
| Deferred / not parity | persistent offline cache | deferred | Privacy/scope rule | No persistent message DB | Deferred by design | Regression test | Relaunch | Scope separately |
| Deferred / not parity | APNs/background push | deferred | Privacy/scope rule | Not registered | Deferred by design | Regression test | Relaunch | Scope separately |
| Deferred / not parity | server deletion | outOfScope | Hard scope boundary | Not implemented | Destructive out of scope | Matrix test | N/A | Future phase |
| Deferred / not parity | any unverified route | blockedByUnverifiedAPI | Route verification rule | Disabled/deferred | Must verify first | Matrix test | N/A | Research first |
