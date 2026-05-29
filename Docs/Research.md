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
