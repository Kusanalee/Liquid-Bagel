# Phase 5 Summary

## What Was Implemented

Phase 5 adds explicit credential tooling, narrow verified login/session handling, environment-scoped Keychain storage, validation through `fetchCurrentUser()`, logout/forget/revoke controls, and a developer live verification harness.

The app remains mock-safe by default. It still launches in mock mode and does not connect to live Stoat until the user explicitly validates or uses a saved credential and clicks Connect Manually.

## Credential Setup Modes

- Manual Session Token Import is the primary setup path.
- Tokens are entered through a `SecureField`.
- Validation calls `fetchCurrentUser()` before the token can be saved.
- Save stores the validated credential in Keychain and clears the token field.
- Login is also available through the verified `POST /auth/session/login` route.
- Login uses email/password, optional friendly session name, and verified MFA continuation through password, TOTP, or recovery code.

## Verified Auth And Session Endpoints

- `POST /auth/session/login`
- `POST /auth/session/logout`
- `GET /auth/session/all`
- `DELETE /auth/session/all?revoke_self=...`
- `DELETE /auth/session/{id}`
- `PATCH /auth/session/{id}` with `friendly_name`
- `GET /users/@me` remains the validation route.

Login is email/password only. Username login and hCaptcha are not implemented because the verified schema does not include those fields.

## Keychain And Environment Scoping

`TokenStore` remains source compatible. `ScopedTokenStore` adds scoped load/save/delete methods, and `KeychainTokenStore` stores credentials under a stable environment-specific account name.

Environment IDs are stable:

- production: `production`
- custom: deterministic ID derived from API/events/media URLs

Custom environment selection is memory-only for Phase 5. Token persistence is scoped by environment, but non-token environment preferences are deferred.

## Session Validation Behavior

`LiveSessionValidator` validates a credential by creating a temporary API client and calling `fetchCurrentUser()`.

Validation maps:

- 401/missing auth to invalid or expired session
- 403 to forbidden
- 429 to rate limited
- transport errors to network unavailable
- server errors to server unavailable
- invalid environment errors to custom environment failures

Credentials are not saved until validation succeeds.

## Logout, Forget, And Revoke

Forget Session:

- requires explicit confirmation
- disconnects realtime
- clears the scoped Keychain credential
- resets live state without deleting mock data

Revoke Session on Server:

- requires explicit confirmation
- calls the verified current-session logout route
- clears the local credential only after successful server revoke
- leaves local forget available if server revoke fails

## Live Verification Harness

The credential setup sheet includes a developer verification section with safe checks for:

- credential loaded
- current user fetched
- WebSocket connected
- authenticated
- Ready received
- users/servers/channels received
- selected channel available
- selected channel message fetch succeeded
- last realtime event
- last ping latency
- last message action result

The harness can reload the selected channel messages. It can send the current composer text only after explicit confirmation and never creates an automatic test message.

## Security Rules

- Raw tokens are never shown after save.
- Raw tokens are not included in debug descriptions or diagnostics.
- Tokens are not written to UserDefaults, SwiftData, SQLite, files, docs, or logs.
- Token input uses `SecureField`.
- Token fields clear after validation/login attempts.
- Destructive local forget and server revoke both require confirmation.
- Remote HTTP/WS custom environments are rejected; localhost HTTP/WS remains allowed for development.

## Tests Added

Mock-only tests cover:

- scoped in-memory credential storage
- stable environment IDs and Keychain account names
- login model decoding and token redaction
- session validation error mapping
- manual token save only after validation
- failed validation not saving credentials
- saved session validation without auto-connect
- forget clearing scoped credentials
- reset to mock preserving credentials
- live verification state updates

No tests require live credentials or real network access.

## Deferred

- custom environment preference persistence
- production-grade account settings
- account flags and richer suspension/onboarding messages
- hCaptcha
- file uploads/media UI
- notifications
- persistence/cache
- friends/DM/discover APIs
- voice
- broad shell redesign
- live network tests

## How To Run

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

Run the app from the `LiquidBagel` Xcode scheme. It opens in mock mode. Open the runtime chip and choose Set Up Session to validate/import credentials, configure a custom environment, connect manually, or run live verification checks.

## Recommended Phase 6 Next Step

Persist safe non-token environment preferences and add a small account/session management surface if Phase 5 live verification confirms the auth/session routes are stable against real accounts.
