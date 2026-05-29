# Phase 1 Summary

## Implemented

- Expanded `StoatModels` with Foundation-only Stoat value types, robust enum decoding, ID wrappers, config decoding, file/embed/message/server/channel/member/role/invite/emoji/unread models, and `Permissions` as a `UInt64` bitmask.
- Built `StoatAPI` with environment configuration, auth credentials, token-store abstractions, Keychain storage, request building, multipart upload encoding, response decoding, rate-limit metadata parsing, typed errors, verified live REST methods, and a mock API client.
- Wired the placeholder macOS shell to `MockStoatAPIClient` through `StoatFeatures`; no live credentials or live calls are required.

## Tested

- Model fixture decoding for users, servers, text/DM channels, messages, attachments, reactions, config, unknown enum cases, ID wrappers, ULID timestamps, user settings, and permissions.
- API tests for environment validation, auth headers/redaction, in-memory token storage, request construction, JSON body encoding, multipart upload bodies, response decoding, error mapping, rate-limit metadata, and upload response decoding.

## Stubbed Or Deferred

- Live `fetchServers()` and all-channel `fetchChannels()` throw `unimplementedEndpoint`; verified live server/channel collection hydration belongs to Phase 2 realtime `Ready`.
- Login UI, session creation, MFA, persistence/cache, markdown rendering, notifications, media viewer, and full permission resolution remain out of scope.
- Keychain integration is implemented but not exercised in automated tests to avoid CI/user keychain flakiness.

## Commands

```bash
swift test --package-path Packages/StoatModels
swift test --package-path Packages/StoatAPI
Scripts/check.sh
```

## Phase 2 Next

- Implement the realtime WebSocket foundation using root `ws`, protocol version/format query parameters, authentication, heartbeat, `Ready` decoding, and incremental events.
- Use `Ready` to replace mock server/channel/message lists with live hydrated state.

## API Uncertainties

- Docs/live root prefer `https://api.stoat.chat`; generated API and SDK still include older Revolt/Stoat fallback defaults.
- Public rate-limit docs and backend source disagree on `/auth` bucket limit.
- Source defines newer permission bits not yet shown in the public permission table.
