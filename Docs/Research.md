# Stoat Research Notes

Phase 0 captures enough current API and client research to keep the native macOS skeleton honest. Exact endpoint payloads and auth/login behavior are intentionally left for Phase 1 verification.

## Current Hosted Endpoints

- The current Stoat developer endpoint page lists `https://api.stoat.chat` as the production API endpoint and `wss://events.stoat.chat` as the production events endpoint: https://developers.stoat.chat/developers/endpoints/
- The live API root at `https://api.stoat.chat/` returns a `ws` value of `wss://events.stoat.chat`, plus feature URLs for media and proxy services.
- The official web client source still defaults to `https://stoat.chat/api` and `wss://stoat.chat/events`: https://raw.githubusercontent.com/stoatchat/for-web/main/packages/client/components/common/lib/env.ts
- Phase 1 should prefer the current endpoint docs/API root unless source inspection shows the web-client defaults are required for a specific deployment path.

## Authentication

- API authentication uses `X-Session-Token` for user sessions and `X-Bot-Token` for bots: https://developers.stoat.chat/developers/api/authentication/
- Phase 0 does not implement login or token storage. Phase 1 must verify session creation, hCaptcha requirements, email/username login behavior, onboarding errors, and logout/session invalidation.

## Events And Ready

- The events connection needs a WebSocket URL from the API root and a valid session or bot token: https://developers.stoat.chat/developers/events/establishing/
- Authentication can happen through query parameters or by sending an `Authenticate` event.
- After authentication, the server sends `Authenticated`, then `Ready`.
- Clients should send `Ping` every 10 to 30 seconds.
- Ready fields include `users`, `servers`, `channels`, `members`, `emojis`, `user_settings`, `channel_unreads`, and `policy_changes`.
- The events protocol documents `Ready`, message create/update/append/delete/reaction events, channel create/update/delete/typing/ack events, server/member/role events, user relationship/update/platform wipe events, emoji events, and forwarded auth session events: https://developers.stoat.chat/developers/events/protocol/

## Messages, Models, Uploads, And Rate Limits

- Message events reuse the API message schema with an added event `type`; update events carry partial objects.
- Channel, server, member, role, user, emoji, relationship, typing, ack, unread, and policy data all appear in the documented realtime protocol, but exact REST schemas should be verified against the OpenAPI source in Phase 1.
- File uploads first POST a `multipart/form-data` body with a `file` field to `{endpoint}/{tag}`, then use the returned file ID in API payloads: https://developers.stoat.chat/developers/api/uploading-files/
- Rate limits use fixed windows and expose `X-RateLimit-Limit`, `X-RateLimit-Bucket`, `X-RateLimit-Remaining`, and `X-RateLimit-Reset-After`; 429 bodies contain `retry_after`: https://developers.stoat.chat/developers/api/ratelimits/

## Official Client Surface

- The official web client powers `https://stoat.chat/app` and is built with Solid.js: https://github.com/stoatchat/for-web
- Its documented app routes are `/login`, `/pwa`, `/dev`, `/discover`, `/settings`, `/invite`, `/bot`, `/friends`, `/server`, and `/channel`.
- The desktop client is currently an Electron wrapper, not a native macOS client: https://github.com/stoatchat/for-desktop

## Phase 1 TODOs

- Locate and verify the current OpenAPI schema and generated TypeScript types from `stoatchat/javascript-client-api`.
- Confirm exact login/session endpoints and whether public login requires hCaptcha.
- Confirm current message send/edit/delete/pin/reaction endpoints and payloads.
- Confirm model fields for users, servers, channels, messages, members, roles, permissions, relationships, attachments, embeds, and user settings.
- Confirm media upload tags and returned file metadata beyond the documented `{ "id": "0" }` shape.
- Confirm any source/docs conflicts and prefer source code when live behavior or generated API types disagree.

## Phase 1 Notes

### Sources inspected

- Official endpoint docs: https://developers.stoat.chat/developers/endpoints/
- Official authentication docs: https://developers.stoat.chat/developers/api/authentication/
- Official file upload docs: https://developers.stoat.chat/developers/api/uploading-files/
- Official rate-limit docs: https://developers.stoat.chat/developers/api/ratelimits/
- Official permission docs: https://developers.stoat.chat/developers/api/permissions/
- Live API root: `GET https://api.stoat.chat/`
- Generated API/OpenAPI package: `stoatchat/javascript-client-api` at `366e0882d50d61c977883deb30fe6aa6eec71a73`
- Official JS SDK: `stoatchat/javascript-client-sdk` at `3453407ba83a6364e470f2c64e2c839e1c74a9bc`
- Backend source: `stoatchat/stoatchat` at `bd987bf72aedb8271846629e05f072247179a22d`

### Endpoint defaults

- Current docs and live root confirm API `https://api.stoat.chat` and events `wss://events.stoat.chat`.
- Live root returns `features.autumn.url = https://cdn.stoatusercontent.com`, `features.january.url = https://proxy.stoatusercontent.com`, and `app = https://stoat.chat`.
- Conflict: `javascript-client-api/src/baseURL.ts` still auto-generates `https://api.revolt.chat`.
- Conflict: `javascript-client-sdk/src/Client.ts` still defaults to `https://stoat.chat/api`; Phase 1 uses the current Stoat docs/live root as the least risky default.

### Authentication

- Official docs confirm user auth through `X-Session-Token` and bot auth through `X-Bot-Token`.
- Upload service OpenAPI also advertises both `session_token` and `bot_token` security schemes.
- Delta OpenAPI uses lowercase `x-session-token` in the security scheme; HTTP headers are case-insensitive, but Liquid Bagel sends the documented `X-Session-Token` / `X-Bot-Token` names.

### Models and routes implemented

- Core model shapes were taken from OpenAPI schemas plus backend `crates/core/models/src/v0/*`.
- Implemented verified live REST routes:
  - `GET /`
  - `GET /users/@me`
  - `GET /channels/{target}`
  - `GET /channels/{target}/messages`
  - `POST /channels/{target}/messages`
  - `PATCH /channels/{target}/messages/{msg}`
  - `DELETE /channels/{target}/messages/{msg}`
  - `PUT /channels/{target}/messages/{msg}/reactions/{emoji}`
  - `DELETE /channels/{target}/messages/{msg}/reactions/{emoji}`
  - `POST /channels/{target}/messages/{msg}/pin`
  - `DELETE /channels/{target}/messages/{msg}/pin`
  - media upload `POST {autumn}/{tag}` with multipart field `file`
- Deferred live list methods:
  - `fetchServers()` and all-channel `fetchChannels()` throw `unimplementedEndpoint` in the live client because no verified REST route lists the current user's servers/channels. Realtime `Ready` is the documented source for those collections and belongs in Phase 2.

### Uploads

- Upload tags verified from Autumn OpenAPI/source: `attachments`, `avatars`, `backgrounds`, `icons`, `banners`, `emojis`.
- Upload request is `multipart/form-data` with a single `file` field.
- Upload response is `{ "id": "<file id>" }`; Liquid Bagel exposes this as `UploadedFile`.

### Phase 16 media serving notes

- Current Stoat upload docs say Autumn/media serving has two unique file paths: a preview route and an original route, and clients should not add query parameters to media URLs.
- Backend Autumn source confirms public fetch routes:
  - `GET /{tag}/{file_id}` returns an image preview where available and redirects to the original file for non-previewable or animated attachment content.
  - `GET /{tag}/{file_id}/{file_name}` returns original bytes with `Content-Disposition: attachment`.
  - Passing `original` as `{file_name}` redirects to the encoded stored filename.
- Phase 16 uses these routes only after explicit user actions. It does not prefetch visible attachments, attach auth headers to media fetches, store persistent media, or add query parameters.

### Phase 20 message send and media notes

- Generated API package `stoatchat/javascript-client-api` package version `0.13.7` confirms `POST /channels/{target}/messages`.
- The message send route accepts an `Idempotency-Key` header and a `DataMessageSend` JSON body.
- Current body fields are `content`, `attachments`, `replies`, `embeds`, `masquerade`, `interactions`, and `flags`.
- The legacy body `nonce` is deprecated and replaced by the `Idempotency-Key` header.
- Backend source at `bd987bf72aedb8271846629e05f072247179a22d` consumes the idempotency header before creating the message, then populates returned `Message.nonce` from that header key.
- Sending the same value in both `Idempotency-Key` and body `nonce` can be rejected as a duplicate nonce operation.
- Official web/SDK behavior sends the header and omits body `nonce`; Liquid Bagel now mirrors that shape.
- Live API root still reports media `https://cdn.stoatusercontent.com`, proxy `https://proxy.stoatusercontent.com`, and events `wss://events.stoat.chat`.
- Attachment references in message send payloads are `string[]` file IDs, matching uploaded Autumn IDs.
- Phase 20 keeps media loading explicit and uses Autumn preview/original routes without query parameters.

### Phase 24 server and channel management notes

- Generated OpenAPI confirms:
  - `GET /servers/{target}` returns server data, or server plus visible channels when `include_channels=true`.
  - `POST /servers/{server}/channels` creates a server text or voice channel with `name`, `type`, optional `description`, optional `nsfw`, and optional voice info.
  - `PATCH /channels/{target}` edits channel `name`, `description`, `icon`, `nsfw`, `voice`, `slowmode`, and supports `remove`.
  - `DELETE /channels/{target}` deletes server text channels, closes DMs, or leaves groups depending on channel type.
  - `PATCH /servers/{target}` can update server `categories`, but Phase 24 only uses this for safe category preservation after channel create.
  - `POST /channels/{target}/invites`, `GET /servers/{target}/invites`, and `DELETE /invites/{target}` are verified invite-management routes.
- Backend route source confirms permission checks:
  - channel create/edit/delete require `ManageChannel`;
  - server invite listing requires `ManageServer`;
  - invite creation requires `InviteOthers`;
  - server category edits require `ManageChannel` through the server edit route.
- Realtime protocol already documents channel create/update/delete and server update/delete events. Phase 24 updates local snapshot from trusted REST responses and lets later realtime events dedupe by ID.
- Deferred despite route support: server deletion, role editor, channel permission editor, category creation/reorder/move UI, voice UI, server owner transfer, public Discover editing, and full permission resolution.

### Phase 25 server settings, roles, categories, and permissions notes

- Sources inspected:
  - `stoatchat/javascript-client-api` commit `366e0882d50d61c977883deb30fe6aa6eec71a73`.
  - `stoatchat/stoatchat` commit `0896e6888274451b7bfb8abb012ae1bf32ad224a`.
  - Official permissions docs: https://developers.stoat.chat/developers/api/permissions/
  - Official events protocol docs: https://developers.stoat.chat/developers/events/protocol/
  - Official upload docs: https://developers.stoat.chat/developers/api/uploading-files/
- Generated client route/schema confirms:
  - `PATCH /servers/{target}` with `DataEditServer` supports `name`, `description`, `icon`, `banner`, `categories`, and `remove`.
  - `POST /servers/{target}/roles` creates a role with `DataCreateRole.name`; create-time `rank` is marked removed/no effect.
  - `PATCH /servers/{target}/roles/{role_id}` edits role `name`, `colour`, `hoist`, `icon`, and `remove`; `rank` is marked removed/no effect.
  - `DELETE /servers/{target}/roles/{role_id}` deletes a role.
  - `PATCH /servers/{server_id}/members/{member_id}` accepts `DataMemberEdit.roles` for member role assignment.
  - `PUT /servers/{target}/permissions/{role_id}`, `PUT /servers/{target}/permissions/default`, `PUT /channels/{target}/permissions/{role_id}`, and `PUT /channels/{target}/permissions/default` exist, but Phase 25 keeps permission editing read-only.
  - `PATCH /servers/{target}/roles/ranks` exists, but Phase 25 keeps role rank reorder deferred because it rewrites all role ordering.
- Backend permission checks confirm:
  - server name, description, icon, banner, system messages, analytics, or remove require `ManageServer`;
  - category updates through server edit require `ManageChannel`;
  - role create/edit/delete and role-rank reorder require `ManageRole`;
  - server permission edits require `ManagePermissions` and rank/grant checks;
  - member role assignment requires `AssignRoles`, rank checks, and valid target role IDs.
- Backend server edit validates category channel membership and removes duplicate channel assignment by rejecting invalid category structures. Phase 25 sends the full category array only on explicit Apply.
- Backend role create returns `{ id, role }`; create supports name only. Role colour/hoist are edited through the role edit route after creation.
- Permission resolver source confirms:
  - owner or privileged users receive `GrantAllSafe`;
  - server permissions start from `default_permissions`, then apply ordered role overrides;
  - role overrides apply allow first, then deny;
  - server channel permissions apply default channel overwrite, then ordered channel role overwrites;
  - timeout restricts to `ViewChannel` and `ReadMessageHistory`;
  - missing `ViewChannel` revokes all channel permissions.
- Phase 25 implements server settings edit, icon/banner set/update, category create/rename/delete/move by full category array, role overview/create/edit/delete for non-permission fields, and read-only permission preview. Permission writes, role rank reorder, server deletion, moderation, bot management, and voice/video remain deferred.

### Phase 26 member moderation and permission write notes

- Sources refreshed for Phase 26:
  - Generated API/OpenAPI package: `stoatchat/javascript-client-api` `main` as of 2026-06-02.
  - Backend route files in `stoatchat/stoatchat` `main` under `crates/delta/src/routes/servers/*` and `crates/delta/src/routes/channels/*`.
- Generated client route/schema confirms:
  - `GET /servers/{target}/members`, `GET /servers/{server_id}/members/{member_id}`, and `GET /servers/{target}/members_experimental_query` exist, but Phase 26 does not add hidden member refresh; the settings UI uses the current Ready snapshot unless the user explicitly invokes an action.
  - `PATCH /servers/{server_id}/members/{member_id}` accepts `DataMemberEdit.nickname`, `avatar`, `roles`, `timeout`, `can_publish`, `can_receive`, `voice_channel`, and `remove`.
  - `DELETE /servers/{server_id}/members/{member_id}` removes/kicks a member.
  - `PUT /servers/{server}/bans/{target}` creates a ban with `reason` and optional `delete_message_seconds`; `DELETE /servers/{server}/bans/{target}` removes a ban; `GET /servers/{target}/bans` lists bans.
  - Permission writes are `PUT /servers/{target}/permissions/default`, `PUT /servers/{target}/permissions/{role_id}`, `PUT /channels/{target}/permissions/default`, and `PUT /channels/{target}/permissions/{role_id}`.
  - Server default permission write uses a direct `permissions` bitset; server role and text-channel overwrite writes use `permissions.allow` / `permissions.deny`. Existing stored role/channel override models still decode `a` / `d`.
- Backend permission checks confirm:
  - member nickname self-edit requires `ChangeNickname`; editing another member nickname requires `ManageNicknames`;
  - member avatar self-edit requires `ChangeAvatar`; removing another member avatar requires `RemoveAvatars`;
  - member role edits require `AssignRoles`, target rank checks, and added-role rank checks;
  - timeout edit/clear requires `TimeoutMembers`, and timeout cannot be applied to users who already have timeout permission;
  - kick requires `KickMembers`, blocks self/owner targets, and enforces target rank checks;
  - ban/list/unban require `BanMembers`; ban enforces rank checks only when the target is still a server member;
  - permission writes require `ManagePermissions`, rank checks for role scopes, and `CannotGiveMissingPermissions` style grant checks.
- Phase 26 implements guarded role assignment, nickname edit/reset, avatar remove, kick, ban, unban/list, timeout/clear, server default permission edits, server role permission edits, text-channel default overwrites, and text-channel role overwrites.
- Deferred despite verified fields/routes: voice mute/deafen/move, role rank reorder, server deletion, hidden/background member sync, automatic live tests with credentials, full moderation dashboard, audit logs, bot management, voice/video UI, and bulk permission templates.

### Rate limits

- Docs confirm fixed-window buckets and headers `X-RateLimit-Limit`, `X-RateLimit-Bucket`, `X-RateLimit-Remaining`, `X-RateLimit-Reset-After`.
- `429` bodies contain `retry_after` in milliseconds.
- Conflict: public docs list `/auth` limit as `3`; backend `crates/delta/src/util/ratelimits.rs` currently returns `15` for `auth`. Phase 1 only parses metadata and does not implement scheduling.

### Permissions

- Public permission docs list allocated bits through `MoveMembers` (`1 << 35`).
- SDK/backend source additionally define `Listen` (`1 << 36`), `MentionEveryone` (`1 << 37`), `MentionRoles` (`1 << 38`), and `BypassSlowmode` (`1 << 39`).
- Liquid Bagel includes the documented bits plus these source-confirmed newer bits, using `UInt64` to preserve voice/video and future high bits.

### Open questions

- Full login/session creation, hCaptcha behavior, MFA, and session invalidation are not implemented in Phase 1.
- Full server/channel permission resolution is documented but intentionally deferred.
- Realtime `Ready` hydration is required before the live app can list servers/channels without mocks.

## Phase 2 Notes

### Sources inspected

- Official establishing-a-connection docs: https://developers.stoat.chat/developers/events/establishing/
- Official events protocol docs: https://developers.stoat.chat/developers/events/protocol/
- Official JS SDK event client at `stoatchat/javascript-client-sdk` commit `3453407ba83a6364e470f2c64e2c839e1c74a9bc`
- Official web client at `stoatchat/for-web` commit `8ca71f2a6c5d8faf0531fe337594408b7ce91879a`
- Backend Bonfire/WebSocket source at `stoatchat/stoatchat` commit `bd987bf72aedb8271846629e05f072247179a22d`

### Connection and authentication

- The WebSocket URL is discovered from the API root/config. Current docs and Phase 1 environment source of truth use `wss://events.stoat.chat` for production.
- Bonfire supports `version`, `format`, `token`, and repeated `ready` query parameters.
- `version=1` is optional today but the docs recommend setting it because it may become mandatory.
- `format=json` is supported and is the only Phase 2 transport format implemented by Liquid Bagel.
- Authentication can be done with a `token` query parameter or by sending a client-to-server `Authenticate` event. Liquid Bagel defaults to sending `Authenticate` after the socket opens so session tokens do not appear in URLs or logs. Query-token auth exists only as an explicit fallback path and must be redacted from diagnostics.
- After authentication, Bonfire sends `Authenticated`, then a `Ready` event. The JS SDK historically treats connection as fully connected when `Ready` arrives.
- Clients should send `Ping` every 10 to 30 seconds. Liquid Bagel defaults to 20 seconds and tracks matching `Pong` latency.

### Ready fields

- Repeated `ready` query parameters are supported.
- Supported documented fields are `users`, `servers`, `channels`, `members`, `emojis`, `user_settings`, `channel_unreads`, and `policy_changes`.
- Backend source also has `voice_states`, but Phase 2 intentionally defers voice and does not request or model it.
- Backend defaults send most fields if no `ready` parameter is present, but `channel_unreads` defaults false. Liquid Bagel explicitly sends requested Phase 2 fields.
- `user_settings` is source-confirmed as an object/record (`UserSettings`), not an array. Phase 2 decodes it as `UserSettings` backed by `JSONValue`.

### Event protocol details

- Client-to-server events implemented: `Authenticate`, `BeginTyping`, `EndTyping`, `Ping`, and `Subscribe`.
- Source-confirmed server `Error` events use a `data` field containing the error code; older docs examples may use `error`.
- `Bulk` contains `v`, and Liquid Bagel decodes it recursively and emits public events flattened.
- Implemented server events include `Authenticated`, `Logout`, `Pong`, `Ready`, message create/update/append/delete/reaction events, channel create/update/delete/group/typing/ack events, server create/update/delete/member/role events, user update/relationship/presence/settings/platform wipe events, emoji create/update/delete, and forwarded auth session events.
- Unknown valid event types decode to `.unknown(type:raw:)`; malformed JSON still throws.
- Source-confirmed newer or deferred events such as voice, webhook, report, slowmode, and role-rank events are preserved as unknown events for Phase 2 rather than modeled as product features.

### Subscribe behavior

- Normal users do not receive all server-fanned `UserUpdate` events by default.
- Clients may send `Subscribe` for server `UserUpdate` events.
- Documentation says subscriptions expire within 15 minutes, only 5 active subscriptions are allowed, bot sessions are unaffected, clients should only send `Subscribe` while focused, and should aim for at most one subscribe every 10 minutes per server.
- Phase 2 includes a small `ServerSubscriptionManager` that enforces the local focused/rate/cap rules, but app focus wiring is deferred.

### Diagnostics and ghost-state note

- A previously reported class of issue had sockets appearing alive because `Ready` and ping/pong worked while normal message events did not arrive.
- Phase 2 does not assume that bug still exists and does not reconnect production users simply because a quiet server has no chat events.
- Liquid Bagel tracks `lastReceivedEventAt`, `lastPongAt`, `lastNonControlEventAt`, latency, and reconnect attempt so future UI/debug tooling can identify “pongs but no non-control events” without destructive recovery behavior.

## Phase 5 Notes

### Sources inspected

- Official authentication docs: https://developers.stoat.chat/developers/api/authentication/
- Generated API routes: https://raw.githubusercontent.com/stoatchat/javascript-client-api/main/src/routes.ts
- Generated API schema: https://raw.githubusercontent.com/stoatchat/javascript-client-api/main/src/schema.ts
- Official JS SDK login/logout surface: https://raw.githubusercontent.com/stoatchat/javascript-client-sdk/main/src/Client.ts
- Official web login flow: https://raw.githubusercontent.com/stoatchat/for-web/main/packages/client/components/auth/src/flows/FlowLogin.tsx
- Official web MFA flow: https://raw.githubusercontent.com/stoatchat/for-web/main/packages/client/components/modal/modals/MFAFlow.tsx
- Official web session management: https://raw.githubusercontent.com/stoatchat/for-web/main/packages/client/components/app/interface/settings/user/Sessions.tsx

### Verified auth/session behavior

- API authentication still uses `X-Session-Token` for user sessions and `X-Bot-Token` for bots.
- Current token validation should use the already verified `GET /users/@me` / `fetchCurrentUser()` route.
- Login is verified as `POST /auth/session/login`.
- Initial login payload is email/password plus optional `friendly_name`; no username login or hCaptcha field is present in the generated login schema.
- Login success returns `result: "Success"`, `_id`, `user_id`, `token`, `name`, `last_seen`, optional `origin`, and optional web push subscription.
- MFA-required login returns `result: "MFA"`, a `ticket`, and `allowed_methods`.
- MFA continuation reuses `POST /auth/session/login` with `mfa_ticket`, optional `mfa_response`, and optional `friendly_name`.
- Verified MFA response shapes are one of `password`, `totp_code`, or `recovery_code`.
- Disabled-account login returns `result: "Disabled"` and `user_id`.
- Session list is verified as `GET /auth/session/all`, returning `SessionInfo` objects with `_id` and `name`.
- Current session logout is verified as `POST /auth/session/logout`.
- Specific session revoke is verified as `DELETE /auth/session/{id}`.
- Revoke-all is verified as `DELETE /auth/session/all?revoke_self=...`.
- Session rename is verified as `PATCH /auth/session/{id}` with `friendly_name`.

### Implementation decisions

- Phase 5 implements manual session token import and validation first.
- Phase 5 also implements the narrow verified email/password login and MFA continuation model, but keeps it explicit and manual.
- Session credentials are saved only after validation succeeds.
- Credentials are scoped by environment ID in Keychain so production and custom/self-hosted credentials do not collide.
- Custom environment preference persistence is deferred because the project has no settings/preferences persistence system yet; custom environment selection is memory-only for Phase 5.

### Remaining uncertainties

- Official docs say users may “authenticate through API” but do not document the login payload directly; the exact login/MFA/session shapes come from generated API/source and official client source.
- Self-hosted/custom environments are assumed to expose the same auth/session routes when they run the same Stoat backend, but Liquid Bagel does not verify that automatically.
- hCaptcha, onboarding completion, account flags, and richer login failure handling remain deferred unless official/current client behavior requires them in a later phase.

## Phase 22 Notes

### Sources inspected

- Generated API routes: https://raw.githubusercontent.com/stoatchat/javascript-client-api/main/src/routes.ts
- Generated API schema: https://raw.githubusercontent.com/stoatchat/javascript-client-api/main/src/schema.ts
- Official events protocol: https://developers.stoat.chat/developers/events/protocol/
- Official web Friends UI: https://raw.githubusercontent.com/stoatchat/for-web/main/packages/client/src/interface/Friends.tsx
- Official web Home sidebar: https://raw.githubusercontent.com/stoatchat/for-web/main/packages/client/src/interface/navigation/channels/HomeSidebar.tsx
- Official web profile actions: https://raw.githubusercontent.com/stoatchat/for-web/main/packages/client/components/ui/components/features/profiles/ProfileActions.tsx
- Official JS SDK user actions: https://raw.githubusercontent.com/stoatchat/javascript-client-sdk/main/src/classes/User.ts

### Verified relationship, profile, and DM routes

- There is no separate `GET /relationships` route in the generated API. The current user's relationship list is available on `GET /users/@me` as `User.relations`, while each visible user also carries a `relationship` field.
- `GET /users/dms` fetches current direct-message and group-DM channels.
- `GET /users/{target}/dm` opens a DM with a user; the generated operation notes that targeting self returns a Saved Messages channel.
- `GET /users/{target}/profile` returns `UserProfile` with optional `content` and `background`.
- `POST /users/friend` sends a friend request with `DataSendFriendRequest`, whose current body is `{ "username": "name#discriminator" }`.
- `PUT /users/{target}/friend` accepts an incoming friend request.
- `DELETE /users/{target}/friend` denies an incoming request, cancels an outgoing request, or removes an existing friend.
- `PUT /users/{target}/block` blocks a user.
- `DELETE /users/{target}/block` unblocks a user.
- `POST /channels/create` creates a group channel with `DataCreateGroup`, but new group creation remains deferred for Phase 22.

### Verified schemas and realtime behavior

- `RelationshipStatus` values are `None`, `User`, `Friend`, `Outgoing`, `Incoming`, `Blocked`, and `BlockedOther`; Liquid Bagel keeps unknown-case decoding.
- `UserProfile` contains optional profile text and optional background `File`; profile background rendering is deferred beyond compact card support.
- `Channel` supports `SavedMessages`, `DirectMessage`, `Group`, and server channel variants. Direct messages include `active`, `recipients`, and optional `last_message_id`; group DMs include `name`, `owner`, `recipients`, optional icon, and optional `last_message_id`.
- Realtime `Ready` may include `users`, `channels`, and `channel_unreads`, which are sufficient to build the Friends and existing DM lists without REST calls after manual connection.
- Realtime `UserRelationship` carries a `user` object and optional `status`; Phase 22 applies the explicit status before updating the snapshot.
- Realtime `ChannelCreate`, `ChannelDelete`, `ChannelAck`, `UserUpdate`, and `UserPresence` are already modeled and feed the same snapshot used by Friends/DM derivations.

### Phase 22 safety decisions

- Liquid Bagel does not fetch friends, profiles, or DMs on launch.
- Manual refresh may call `GET /users/@me` and `GET /users/dms` only after the user is connected.
- Friend, block, profile, and open-DM calls are explicit user actions only.
- Errors shown in the Friends/Profile surfaces are short and do not expose raw response bodies.
- Notification routing continues to store only safe route IDs.

## Phase 6 Notes

### Session management re-check

- Current generated API routes still expose:
  - `GET /auth/session/all`
  - `PATCH /auth/session/{id}` with `friendly_name`
  - `DELETE /auth/session/{id}`
  - `DELETE /auth/session/all?revoke_self=...`
  - `POST /auth/session/logout`
- Current generated schema still defines `SessionInfo` as `_id` and `name` only. It does not expose a token, `current`, `created_at`, or `updated_at` field.
- The official web client identifies the current session by comparing each session ID to the client's locally held `sessionId`; Liquid Bagel should do the same when the saved credential includes a session ID.
- The official SDK derives session creation time from the ULID session ID. Liquid Bagel may display that derived created time when decoding succeeds, but should not claim an API-provided timestamp.
- The official web client's “Log Out Other Sessions” behavior maps to deleting all sessions with `revoke_self=false`.

### Phase 6 safety implications

- Session IDs are acceptable for internal matching and shortened display, but broad diagnostics should continue to avoid raw full session IDs.
- If a manually imported token has no session ID, Liquid Bagel can list sessions but cannot mark the current session with certainty.
- Revoke-all-other-sessions is verified and safe when called with `revoke_self=false`; revoke-self behavior should remain behind explicit current-session logout/revoke confirmation.

## Phase 10 Notes

### Sources inspected

- Generated API routes: https://raw.githubusercontent.com/stoatchat/javascript-client-api/main/src/routes.ts
- Generated API schema: https://raw.githubusercontent.com/stoatchat/javascript-client-api/main/src/schema.ts
- Official web client text channel behavior: https://github.com/stoatchat/for-web/blob/main/packages/client/src/interface/channels/text/TextChannel.tsx
- Official JS SDK channel/message ack behavior: https://github.com/stoatchat/javascript-client-sdk/blob/main/src/classes/Channel.ts
- Backend channel ack route: https://github.com/stoatchat/stoatchat/blob/main/crates/delta/src/routes/channels/channel_ack.rs
- Backend unread update behavior: https://github.com/stoatchat/stoatchat/blob/main/crates/core/database/src/models/channel_unreads/ops/mongodb.rs

### Verified read acknowledgement behavior

- Channel read acknowledgement is verified as `PUT /channels/{target}/ack/{message}`.
- The route takes channel ID and message ID in the path, returns 204, and has no JSON request body.
- Backend source rejects bot users for channel ack.
- Backend unread state sets `last_id` to the acked message ID and removes mention IDs less than or equal to the acked message ID.
- The official SDK locally clears channel mentions when acknowledging and debounces network ack sends at about 1.5 seconds with an upper limit around 4 seconds.
- The official web client sends channel ack automatically only when the channel is unread, the client is focused, and the text timeline is at the end; its jump-end command also sends ack before scrolling to the bottom.
- `ChannelAck` remains the receive-side realtime event for other-client/server state updates and carries channel ID, user ID, and `message_id`.

### Phase 10 implementation decision

- Liquid Bagel implements only the narrow channel ack route, scoped to the active selected channel in Live Manual.
- Server-wide ack remains deferred.
- Mention clearing is allowed after a successful live ack or equivalent verified ack state, but local-only mock behavior continues to avoid claiming server acknowledgement.

## Phase 12 Notes

### Sources inspected

- Current generated API routes: https://raw.githubusercontent.com/stoatchat/javascript-client-api/main/src/routes.ts
- Current generated API schema: https://raw.githubusercontent.com/stoatchat/javascript-client-api/main/src/schema.ts
- Backend single-message fetch route: https://raw.githubusercontent.com/stoatchat/stoatchat/main/crates/delta/src/routes/channels/message_fetch.rs
- Backend message query route: https://raw.githubusercontent.com/stoatchat/stoatchat/main/crates/delta/src/routes/channels/message_query.rs
- Backend message search route: https://raw.githubusercontent.com/stoatchat/stoatchat/main/crates/delta/src/routes/channels/message_search.rs

### Verified route findings

- Single message fetch is verified as `GET /channels/{target}/messages/{msg}`. Backend checks `ViewChannel`, fetches the referenced message, and returns `NotFound` if the message does not belong to the target channel.
- Around-message fetch is verified on `GET /channels/{target}/messages` with query parameter `nearby`. The generated schema says `nearby` ignores `before`, `after`, and `sort`, uses the limit on both sides, and includes the target message.
- Standard channel message fetch also supports `before`, `after`, `sort`, `limit`, and `include_users`.
- Selected-channel message search is verified as `POST /channels/{target}/search`, with `query`, `pinned`, `before`, `after`, `limit`, `sort`, and `include_users`.
- Pinned-message listing is available through the selected-channel search route with `pinned: true`; no separate pinned-message list endpoint was found or needed for Phase 12.

### Phase 12 safety decisions

- Live reference fetching may use the verified single-message route only after explicit Live Manual connection and visible/explicit timeline need.
- Around-message fetch may use verified `nearby` only for explicit recovery actions such as load-to-unread or load-around-target.
- Remote search remains selected-channel only, explicit, non-persistent, and Live Manual only. Local “Find in loaded messages” remains available in mock and live loaded data without network calls.
