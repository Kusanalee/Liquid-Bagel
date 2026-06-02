# Phase 25 - Bug Triage Gate, Server Settings, Roles, Categories, and Permissions MVP

Phase 25 expands owner/admin parity without changing the launch contract: Liquid Bagel still starts live-first, disconnected or signed out as appropriate, and does not auto-connect, auto-validate credentials, run hidden server settings refreshes, add background sync, or create persistent message storage.

## Bug Triage Gate

- `git status --short` was clean at the start of the phase.
- Baseline focused tests passed before implementation:
  - `swift test --package-path Packages/StoatModels`
  - `swift test --package-path Packages/StoatAPI`
  - `swift test --package-path Packages/StoatFeatures`
- No build failures, crashes, live-connect/send/media/server-management blockers, or security/privacy regressions were found in the bounded gate.
- Known bug backlog remains empty for blocker/high-priority issues found during this phase. Lower-priority polish remains deferred to normal later-phase backlog.

## Verified Routes

Research was refreshed in `Docs/Research.md` from current upstream primary sources:

- `stoatchat/javascript-client-api` commit `366e0882d50d61c977883deb30fe6aa6eec71a73`
- `stoatchat/stoatchat` commit `0896e6888274451b7bfb8abb012ae1bf32ad224a`

Implemented live route support:

- `PATCH /servers/{target}` for server name, description, icon, banner, remove fields, and full category structure.
- `POST /servers/{target}/roles` for role creation by name.
- `PATCH /servers/{target}/roles/{role_id}` for role name, colour, and hoist edits.
- `DELETE /servers/{target}/roles/{role_id}` for role deletion.
- `PATCH /servers/{server_id}/members/{member_id}` model/API support for member role assignment.

Verified but intentionally deferred:

- server/channel permission write endpoints
- role-rank reorder endpoint
- server deletion
- moderation, bot management, voice/video, push/APNs, background sync, and persistent cache

## Implemented Behavior

- Server Overview is now a Server Settings sheet with tabs for Overview, Appearance, Categories, Roles, Permissions, Members, and a disabled Danger Zone placeholder.
- Opening Server Settings uses the current snapshot only. Refresh remains an explicit button/action and only runs when manually connected.
- Overview edits server name and description with validation, Save/Cancel, safe errors, and local snapshot updates after trusted responses.
- Appearance supports local icon/banner drafts. File selection does not upload; Save uploads using `icons` and `banners`, then patches the server with returned file IDs.
- Category editor can draft category create, rename, delete, and channel moves, then sends the complete verified category array on explicit Apply.
- Roles view shows role name, colour, rank, hoist state, and highlighted permission summary. Role create/edit/delete use verified role routes. Delete requires typing the role name in the sheet before the button enables.
- Permission preview is read-only and uses a pure resolver for owner bypass, default permissions, role overrides, channel overwrites, timeout restriction, missing data warnings, and action booleans.
- Quick switcher includes Server Settings, Server Appearance, Category Editor, Roles, Permissions, Create Role, and Create Category.

## Security And Privacy

- No new hidden live networking was added.
- No startup connect, credential validation, or settings refresh was added.
- Server appearance uploads happen only after explicit Save.
- Category and role mutations happen only after explicit Apply/Save/Delete.
- Server deletion remains disabled.
- Permission editing remains read-only.
- Errors continue to use safe formatting instead of raw server bodies, tokens, or local paths.

## Tests Added

- API route-shape tests for server edit, role create/edit/delete, and member edit role assignment.
- Feature tests for Server Settings open/save, category apply, role create via mock API, quick-switcher command availability, and permission resolver behavior.
- Existing Phase 21 startup tests continue to cover no auto-connect and no auto-validation.
- Existing Phase 24 invite/settings tests continue to cover no hidden invite refresh.

## Manual Live QA Checklist

1. Launch the app.
2. Confirm no auto-connect or auto-validation.
3. Validate saved session manually.
4. Connect manually.
5. Select a server where you have management permission.
6. Open Server Settings.
7. Edit server name/description using a safe test value.
8. Confirm update appears locally/realtime.
9. Restore original server name/description.
10. Pick an icon/banner draft.
11. Confirm no upload happens before Save.
12. Save icon/banner only if safe.
13. Confirm media updates or fallback works.
14. Open Category Editor.
15. Create/rename/delete a low-risk test category.
16. Move a low-risk test channel.
17. Open Roles.
18. Create/edit/delete a low-risk test role.
19. Open Permission Preview.
20. Confirm action gating matches expectations.
21. Relaunch.
22. Confirm no auto-connect or auto-validation happened.

## Known Risks And Limitations

- Member role assignment has API/model support but only a read-only member shortcut in the Phase 25 UI; a fuller member-role picker remains safer as a follow-up.
- Permission editing is intentionally not writable.
- Role rank reorder is deferred because the verified endpoint rewrites the full role order.
- Category editing sends the full category array; manual live QA should use a low-risk server.
- Icon/banner clear/remove is modeled in `ServerEditDraft`, but the Phase 25 UI exposes set/update drafts only.

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

Recommended Phase 26 next step: add a dedicated member-role assignment picker and, after more live QA, consider a guarded permission editor for the already verified permission routes.
