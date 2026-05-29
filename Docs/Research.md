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
