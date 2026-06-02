# Phase 24 - Server and Channel Management Basics MVP

Phase 24 completes the interrupted Phase 23 community work and adds a conservative server/channel management MVP for owners/admins. The app still launches live-first, disconnected or signed out as appropriate, and does not auto-connect, auto-validate credentials, run hidden management refreshes, or add background sync.

## Phase 23 Audit

- `Docs/Phase23.md` was missing and is now created.
- Partial Phase 23 code already existed for invite parsing, invite preview/join, create server, invite management, Discover, and quick-switcher commands.
- Discover remains web-backed because no native Discover listing API was verified.
- Invite preview, invite join, create server, invite create/list/revoke are implemented through explicit user actions and safe error copy.
- Invite management no longer refreshes automatically when opened; the Refresh button is the explicit live action.

## Verified Routes

- Server details: `GET /servers/{target}` with optional `include_channels=true`.
- Create channel: `POST /servers/{server}/channels` with `DataCreateServerChannel`.
- Edit channel: `PATCH /channels/{target}` with `DataEditChannel`.
- Delete channel: `DELETE /channels/{target}`.
- Category preservation: `PATCH /servers/{target}` with `categories` through `DataEditServer`.
- Invites: `POST /channels/{target}/invites`, `GET /servers/{target}/invites`, `DELETE /invites/{target}`.
- Backend permission checks require `ManageChannel` for channel create/edit/delete, `ManageServer` for server invite listing, and `InviteOthers` for invite creation.

## Implemented Behavior

- Server Overview shows selected server name, description, icon, channel count, member count, owner ID, runtime status, management capability hints, invite management, create channel, explicit refresh, and category summary.
- Create Channel supports text channel name, description, NSFW flag, and optional existing category placement. Voice UI and private channels remain deferred.
- Channel Settings supports editing name, description, and NSFW flag for text channels. Empty description removes the description field.
- Channel Delete requires confirmation with the channel name, removes local channel state after API success, and falls back to the next text channel or server empty state.
- Category support displays existing server categories and can append a newly-created channel to an existing category when the current category structure can be preserved.
- Quick switcher and command handling include Server Overview, Create Channel, Channel Settings, and Delete Channel. No destructive keyboard-only delete shortcut was added.
- Permission-aware UI gating uses existing owner/default/channel permission hints and conservative disabled reasons when resolution is incomplete.

## Security And Privacy

- Management actions run only from explicit user actions.
- No tokens, raw session IDs, raw response bodies, or sensitive URLs are surfaced in management errors.
- Destructive channel delete and invite revoke require confirmation.
- Server deletion, role editing, moderation, bot management, push/APNs, persistent message cache, and hidden live networking remain deferred.

## Tests Added

- API route-shape tests for server fetch, channel create/edit/delete.
- Feature tests for server overview/gating, channel create/edit/delete local integration, category append, fallback selection, and invite management no-auto-refresh.
- Existing Phase 21 live-first startup tests continue to assert no auto-connect or auto-validation.

## Manual Live QA Checklist

1. Launch the app.
2. Confirm no auto-connect or auto-validation.
3. Validate saved session manually.
4. Connect manually.
5. Open Discover/Join Invite and confirm Phase 23 surfaces are not broken.
6. Select a server where you have management permission.
7. Open Server Overview.
8. Confirm server name/icon/banner/channel count display.
9. Open Create Channel.
10. Create a low-risk test text channel.
11. Confirm it appears in the channel list.
12. Send a message in the new channel.
13. Edit the test channel name/description.
14. Confirm local/realtime update appears.
15. Delete the test channel with confirmation.
16. Confirm selection falls back safely.
17. Create/copy an invite if desired.
18. Revoke the test invite with confirmation.
19. Relaunch.
20. Confirm no auto-connect or auto-validation happened.

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

## Deferred To Later Phases

- Full server settings editor.
- Category creation, reorder, and move UI.
- Full role/permission resolver and role editor.
- Server deletion and other owner-destructive server actions.
- Voice/video, moderation dashboard, bot management, Discover marketplace clone, push/APNs, and persistent message database/cache.

Recommended Phase 25 next step: broaden server settings carefully, starting with verified server name/description/icon/banner editing and a proper category editor only if the UI can preserve server category structure safely.
