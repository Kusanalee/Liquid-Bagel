# Phase 22 — Home, Friends, Direct Messages, Relationships, and Profiles

Phase 22 implements the first useful non-server chat surfaces for Liquid Bagel while preserving live-first manual startup.

## Implemented

- Verified relationship, profile, DM, and group-DM route/schema research is recorded in `Docs/Research.md`.
- `StoatAPIClient` now supports verified profile, DM, friend request, accept/deny/remove, block, and unblock routes.
- `UserProfile` is modeled with optional profile text and background file.
- Home now shows current user, session state, friend/request counts, recent DMs, quick actions, and a manual Friends/DM refresh.
- Friends now has Online, All, Pending, Blocked, and Add Friend tabs derived from `User.relationship`.
- Pending separates incoming and outgoing requests.
- Relationship actions are explicit; destructive actions use confirmation.
- Existing DMs, group DMs, and saved-message channels are derived from `Ready.channels` and manual `GET /users/dms` refreshes.
- DM selection uses the existing channel timeline, send, attachment, image-preview, read-ack, and notification paths.
- User profile popovers are available from Home/Friends rows and fetch profile details only after the profile is opened.
- Quick switcher can route to Friends and Add Friend and continues to index DM channels.
- DM notification classification now includes group DM channels.
- Tests cover route shapes, derivation, mock relationship actions, DM routing, quick switcher routing, and realtime relationship status application.

## Deferred

- New group DM creation through `POST /channels/create`.
- Full profile background rendering and full account profile editing.
- Persistent DM history, persistent media cache, background sync, APNs/push, voice/video, Discover, and server/channel settings.
- Any live automated test that requires credentials.

## Safety Notes

- No live relationship, profile, or DM network call runs on launch.
- No saved credential is auto-validated and no realtime connection starts automatically.
- Manual refresh requires a connected Live Manual session.
- Friend/block/DM creation actions require an explicit user click.
- User-facing errors remain short and redacted; raw server bodies, tokens, and session IDs are not surfaced.
