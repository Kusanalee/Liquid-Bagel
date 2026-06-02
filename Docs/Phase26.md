# Phase 26 - Members, Role Assignment, Guarded Permissions, and Moderation MVP

Phase 26 turns the Phase 25 read-only member and permission surfaces into guarded administration tools. Liquid Bagel still launches live-first but disconnected/signed out/ready-to-connect as appropriate, with no auto-connect, no credential auto-validation, no hidden settings refresh, no background sync, and no persistent message cache.

## Bug Triage Gate

- `git status --short` was clean at the start of the phase.
- Baseline focused tests passed before implementation:
  - `swift test --package-path Packages/StoatModels`
  - `swift test --package-path Packages/StoatAPI`
  - `swift test --package-path Packages/StoatFeatures`
- TODO/recent-management scan found no build failures, crashes, privacy leaks, live-connect blockers, send/media blockers, or server/member/role/permission blockers requiring diversion before Phase 26 implementation.
- Phase 26 backlog for lower-priority polish remains:
  - polish compact member row layout for very large role lists;
  - add richer member-list role filtering beyond local text search;
  - add a more specialized permission-group UI after live QA confirms the first guarded editor shape.

## Verified Routes Implemented

Research was refreshed in `Docs/Research.md` from current generated API and backend route sources.

Implemented live API support:

- `PATCH /servers/{server_id}/members/{member_id}` for role assignment, nickname edit/reset, avatar remove, and timeout/clear.
- `DELETE /servers/{server_id}/members/{member_id}` for kick.
- `PUT /servers/{server}/bans/{target}` for ban.
- `DELETE /servers/{server}/bans/{target}` for unban.
- `GET /servers/{target}/bans` for explicit ban-list fetch.
- `PUT /servers/{target}/permissions/default`.
- `PUT /servers/{target}/permissions/{role_id}`.
- `PUT /channels/{target}/permissions/default`.
- `PUT /channels/{target}/permissions/{role_id}`.

Verified but intentionally deferred:

- voice mute/deafen/move fields in `DataMemberEdit`;
- role rank reorder;
- server deletion;
- full moderation dashboard, audit logs, bot management, voice/video, push/APNs, background sync, and persistent cache.

## Implemented Behavior

- Members tab now supports local member search, member display names, usernames, role summaries, timeout status, member detail, role assignment, nickname edit/reset, avatar remove, kick, ban, timeout, clear timeout, and explicit ban-list fetch.
- Member role assignment uses a draft picker, shows added/removed roles, and requires confirmation before saving.
- Member moderation actions create a pending confirmation before any API call. Destructive actions remove local member state only after trusted API success.
- Permission tab keeps a read-only preview by default, then opens an explicit editor for server defaults, server roles, text-channel defaults, and text-channel role overwrites.
- Permission edits distinguish inherit/allow/deny where overwrite routes support it. Server defaults use direct allow/deny behavior because the verified route accepts a bitset.
- Permission saves show a diff preview and require confirmation before calling the API.
- Dangerous permissions are highlighted in the editor model: server/channel/role/permission management plus kick, ban, timeout, and role assignment.
- Quick switcher and the native Servers menu now include Members, Permission Editor, and Ban List commands.
- Realtime member update reconciliation now understands nickname, avatar, roles, timeout, and clear fields.

## Security And Privacy

- No new hidden live networking was added.
- Opening Server Settings and Members does not fetch member or ban data.
- Ban list fetch is explicit and permission-gated.
- Member search is local.
- Member IDs are hidden unless developer controls are enabled.
- Rank/hierarchy uncertainty blocks risky member and role-assignment actions.
- Permission and moderation failures use existing safe error formatting; raw server bodies, tokens, URLs, and local paths are not surfaced.
- Permission writes, role assignment, kick, ban, timeout, nickname reset, and avatar remove all require explicit user action, and destructive/sensitive flows require confirmation.

## Tests Added

- API route-shape tests for Phase 26 member edit, kick, ban, ban list, unban, server permission writes, and channel permission writes.
- Feature tests for role assignment diff confirmation, permission diff confirmation/save, member moderation confirmation, no automatic ban-list load, and command availability.
- Existing startup tests continue to cover no auto-connect and no auto-validation.
- Existing invite/settings tests continue to cover no hidden refresh on open.

## Manual Live QA Checklist

1. Launch the app.
2. Confirm no auto-connect or auto-validation.
3. Validate saved session manually.
4. Connect manually.
5. Select a low-risk test server where you have administration permissions.
6. Open Server Settings, then Members.
7. Confirm member list uses current snapshot without a hidden refresh.
8. Search locally for a member.
9. Open a member detail.
10. Assign a low-risk test role, review the diff, confirm, then restore the original roles.
11. Edit and reset a member nickname if safe.
12. Apply and clear a short timeout if safe.
13. Avoid kick/ban on real users unless using a dedicated test account.
14. Explicitly load the ban list only on a test server.
15. Open Permissions.
16. Edit a low-risk permission scope, review the diff, confirm, then restore the original value.
17. Relaunch and confirm no auto-connect or auto-validation occurred.

## How To Verify

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
